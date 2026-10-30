#Requires -Version 7.0
<#
.SYNOPSIS
    CI 门禁：预检 → 构建 → colcon test → Python 静态检查/单测，输出汇总并返回退出码。

.DESCRIPTION
    可以在本地手工跑（提交前），也可以被 CI 直接调用；退出码 0 = 全绿，非 0 = 有阶段失败。

    设计要点：
      - **不 fail-fast**：默认把所有阶段跑完再汇总，一次就能看到全部问题；
      - **每阶段独立计时/记录**，结果写到 <ws>\log\ci\<时间戳>\（summary.md + result.json）；
      - 构建/测试复用 Ros2-Build.ps1 / Ros2-Test.ps1，不重复环境装配逻辑；
      - 只依赖"本机已按 AGENTS.md 装好 SDK"，因此 CI 跑在本机或同构的 self-hosted runner 上。

.PARAMETER ConfigPath
    ros2.config.psd1 路径。默认 D:\deepseek project\config\ros2.config.psd1，
    可用环境变量 ROS2_CI_CONFIG 覆盖（CI 里从 checkout 目录取配置时用）。

.PARAMETER Stage
    all（默认）/ build / test / python，只跑指定阶段（排障时用）。

.PARAMETER SkipBuild
    跳过构建，直接测已有产物（改测试代码时快一点）。

.PARAMETER Workspace
    覆盖配置里的 UserWorkspace。CI 把仓库 checkout 到别的目录时用这个参数，
    脚本会生成一份临时配置（原配置只覆盖 UserWorkspace，其余照抄），再传给子脚本。

.PARAMETER Bootstrap
    .venv 不存在时先跑 tools\Setup-Ros2PyEnv.ps1 建好（首次跑或 CI 全新 checkout 时用）。
    不加这个开关就按"环境已就绪"处理，缺 .venv 会让 Python 阶段明确失败。

.EXAMPLE
    pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1
    pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1 -Stage python
    pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1 -Workspace D:\actions-runner\_work\ws\ws -Bootstrap
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = $(if ($env:ROS2_CI_CONFIG) { $env:ROS2_CI_CONFIG } else { 'D:\deepseek project\config\ros2.config.psd1' }),
    [ValidateSet('all', 'build', 'test', 'python')]
    [string]$Stage = 'all',
    [switch]$SkipBuild,
    [string]$Workspace,
    [switch]$Bootstrap
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ScriptsDir = Split-Path -Parent $ConfigPath | Split-Path -Parent
$ScriptsDir = Join-Path $ScriptsDir 'scripts'
$BuildScript = Join-Path $ScriptsDir 'Ros2-Build.ps1'
$TestScript = Join-Path $ScriptsDir 'Ros2-Test.ps1'

$results = [System.Collections.Generic.List[object]]::new()

function Write-Head([string]$Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

function Invoke-Stage {
    param([string]$Name, [scriptblock]$Body)

    Write-Head $Name
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $errorText = $null

    try {
        & $Body
        # 外部命令的退出码不会被 try/catch 捕获，这里手动判定
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "命令退出码 $LASTEXITCODE"
        }
        $ok = $true
    }
    catch {
        $errorText = $_.Exception.Message
        Write-Host "  FAILED: $errorText" -ForegroundColor Red
    }
    finally {
        $watch.Stop()
    }

    $results.Add([pscustomobject]@{
            Stage   = $Name
            Ok      = $ok
            Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
            Error   = $errorText
        })
}

# ---------------------------------------------------------------- 预检
Invoke-Stage '预检' {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "找不到配置 $ConfigPath" }
    $cfg = Import-PowerShellDataFile -Path $ConfigPath
    $effectiveWs = if ($Workspace) { (Resolve-Path -LiteralPath $Workspace).Path } else { $cfg.UserWorkspace }
    Write-Host "  SDK       : $($cfg.InstallRoot)"
    Write-Host "  工作区    : $effectiveWs"
    Write-Host "  配置文件  : $ConfigPath"

    if (-not (Test-Path -LiteralPath (Join-Path $cfg.InstallRoot 'local_setup.bat'))) {
        throw "SDK 不完整：$($cfg.InstallRoot)\local_setup.bat 不存在"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $effectiveWs 'src'))) {
        throw "工作区不存在：$effectiveWs\src"
    }
    if (-not (Test-Path -LiteralPath $BuildScript)) { throw "找不到 $BuildScript" }
    if (-not (Test-Path -LiteralPath $TestScript)) { throw "找不到 $TestScript" }
    if (-not (Get-Command pixi -ErrorAction SilentlyContinue)) {
        # 与 scripts\_Common.ps1 的 Resolve-Pixi 同一约定：默认装在 %LOCALAPPDATA%\pixi\bin
        $pixiExe = Join-Path $env:LOCALAPPDATA 'pixi\bin\pixi.exe'
        if (-not (Test-Path -LiteralPath $pixiExe)) { throw 'pixi 不可用（不在 PATH，也没有 %LOCALAPPDATA%\pixi\bin\pixi.exe）' }
        Write-Host "  pixi      : $pixiExe"
    }
}

$cfg = $null
$WorkspaceOverride = $Workspace   # 保存调用方是否显式指定了 -Workspace
$Workspace = $RepoRoot
$VenvPython = Join-Path $Workspace '.venv\Scripts\python.exe'
$Ruff = Join-Path $Workspace '.venv\Scripts\ruff.exe'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutDir = Join-Path $Workspace "log\ci\$Stamp"

# 预检失败就没必要继续（后面的阶段都依赖配置里的路径），直接落到汇总
if ($results[0].Ok) {
    $cfg = Import-PowerShellDataFile -Path $ConfigPath

    if ($WorkspaceOverride) {
        # CI 场景：仓库在别处 checkout，生成一份只把 UserWorkspace 换掉的临时配置
        $cfg.UserWorkspace = (Resolve-Path -LiteralPath $WorkspaceOverride).Path
        $tempConfig = Join-Path $env:TEMP "ros2ci-$Stamp.config.psd1"
        $body = $cfg.GetEnumerator() | ForEach-Object {
            $v = $_.Value
            $rendered = if ($v -is [bool]) { if ($v) { '$true' } else { '$false' } }
            elseif ($v -is [string]) { "'" + ($v -replace "'", "''") + "'" }
            elseif ($v -is [array]) { '@(' + (($v | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', ') + ')' }
            else { "$v" }
            "    $($_.Key) = $rendered"
        }
        "@{`n$($body -join "`n")`n}" | Set-Content -LiteralPath $tempConfig -Encoding utf8
        $ConfigPath = $tempConfig
        Write-Host "  临时配置  : $ConfigPath（UserWorkspace 覆盖为 $($cfg.UserWorkspace)）" -ForegroundColor Yellow
    }

    $Workspace = $cfg.UserWorkspace
    $VenvPython = Join-Path $Workspace '.venv\Scripts\python.exe'
    $Ruff = Join-Path $Workspace '.venv\Scripts\ruff.exe'
    $OutDir = Join-Path $Workspace "log\ci\$Stamp"

    # ---------------------------------------------------------------- 构建
    if (-not $SkipBuild -and $Stage -in @('all', 'build')) {
        Invoke-Stage '构建（colcon build）' {
            & $BuildScript -ConfigPath $ConfigPath | ForEach-Object { Write-Host "  $_" }
        }
    }

    # ---------------------------------------------------------------- 测试
    if ($Stage -in @('all', 'test')) {
        Invoke-Stage '测试（colcon test）' {
            & $TestScript -ConfigPath $ConfigPath | ForEach-Object { Write-Host "  $_" }
        }
    }

    # ---------------------------------------------------------------- Python
    if ($Stage -in @('all', 'python')) {
        Invoke-Stage 'Python（ruff check / format / pytest）' {
            if (-not (Test-Path -LiteralPath $VenvPython)) {
                if (-not $Bootstrap) {
                    throw "没有 .venv：先跑 $Workspace\tools\Setup-Ros2PyEnv.ps1（或给本脚本加 -Bootstrap）"
                }
                $setup = Join-Path $Workspace 'tools\Setup-Ros2PyEnv.ps1'
                Write-Host "  .venv 不存在，先跑 $setup" -ForegroundColor Yellow
                & $setup | ForEach-Object { Write-Host "  $_" }
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython)) {
                    throw '.venv 初始化失败'
                }
            }
            Push-Location $Workspace
            try {
                & $Ruff check . 2>&1 | ForEach-Object { Write-Host "  $_" }
                if ($LASTEXITCODE -ne 0) { throw 'ruff check 未通过' }

                & $Ruff format --check . 2>&1 | ForEach-Object { Write-Host "  $_" }
                if ($LASTEXITCODE -ne 0) { throw 'ruff format --check 未通过' }

                & $VenvPython -m pytest -q 2>&1 | ForEach-Object { Write-Host "  $_" }
                if ($LASTEXITCODE -ne 0) { throw 'pytest 未通过' }
            }
            finally {
                Pop-Location
            }
        }
    }
}

# ---------------------------------------------------------------- 汇总
$failed = $results.Where({ -not $_.Ok })
$totalSeconds = [math]::Round(($results | Measure-Object -Property Seconds -Sum).Sum, 1)

Write-Host ''
Write-Host '================ 汇总 ================' -ForegroundColor Cyan
$results | Format-Table -AutoSize -Property @{ n = '阶段'; e = { $_.Stage } }, @{ n = '结果'; e = { if ($_.Ok) { 'PASS' } else { 'FAIL' } } }, @{ n = '秒'; e = { $_.Seconds } } | Out-String | Write-Host
if ($failed) {
    Write-Host "失败阶段：" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.Stage, $_.Error) -ForegroundColor Red }
}
Write-Host ("总计 {0} 秒；{1}/{2} 阶段通过" -f $totalSeconds, ($results.Count - $failed.Count), $results.Count) -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })

# 落盘：CI 里当 artifact 收，本地排障也方便
$null = New-Item -ItemType Directory -Force -Path $OutDir
$summary = @(
    '# CI 结果'
    ''
    "| 阶段 | 结果 | 秒 |"
    '|---|---|---|'
    $results | ForEach-Object { "| $($_.Stage) | $(if ($_.Ok) { 'PASS' } else { 'FAIL' }) | $($_.Seconds) |" }
    ''
    "总计：$totalSeconds 秒，$($results.Count - $failed.Count)/$($results.Count) 通过"
    ''
    "配置：$ConfigPath"
    "工作区：$Workspace"
)
Set-Content -LiteralPath (Join-Path $OutDir 'summary.md') -Value ($summary -join "`n") -Encoding utf8
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding utf8
Write-Host "报告：$OutDir" -ForegroundColor Gray

if ($failed) { exit 1 }
exit 0
