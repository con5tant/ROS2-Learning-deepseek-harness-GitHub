#Requires -Version 7.0
<#
.SYNOPSIS
    创建 / 刷新工作区的 Python 环境：.venv + ROS 2 适配层（让普通 python 直接 import rclpy）。

.DESCRIPTION
    做四件事（可重复执行，幂等）：
      1. 若 .venv 不存在，用 SDK 自带的 Python 3.12 建一个 --system-site-packages 的 venv；
      2. 写 tools\pyenv\ros2py.config.json（SDK 路径的唯一来源）；
      3. 写 .venv\Lib\site-packages\ros2py.pth（两行：挂载适配层目录 + import 适配层）；
      4. 往 venv 装 ruff / pyright（-SkipTools 可跳过），最后自检 import rclpy。

    为什么不用 `pip install -e` 一类的做法：ROS 的 Python 包不在 venv 里，而在
    <SDK>\Lib\site-packages，且 rclpy 的 pyd 依赖 <SDK>\bin 下的 DLL。适配层按需注入，
    见 tools\pyenv\ros2py_bootstrap.py。

.PARAMETER SdkRoot
    ROS 2 SDK 根目录。默认从 D:\deepseek project\config\ros2.config.psd1 读 InstallRoot，
    读不到则用 D:\ros2\lyrical。

.PARAMETER Check
    只检查不修改，适合 CI / 排障。

.EXAMPLE
    pwsh -NoProfile -File .\tools\Setup-Ros2PyEnv.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tools\Setup-Ros2PyEnv.ps1 -Check
#>
[CmdletBinding()]
param(
    [string]$SdkRoot,
    [string]$VenvPath = (Join-Path $PSScriptRoot '..\.venv'),
    [switch]$SkipTools,
    [switch]$Check,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ToolsDir = Join-Path $PSScriptRoot 'pyenv'
$ConfigJson = Join-Path $ToolsDir 'ros2py.config.json'
$VenvPath = [System.IO.Path]::GetFullPath($VenvPath)
$VenvPython = Join-Path $VenvPath 'Scripts\python.exe'
$PthFile = Join-Path $VenvPath 'Lib\site-packages\ros2py.pth'

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "    OK  $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "    !!  $Text" -ForegroundColor Yellow }

# Fast DDS 在受限会话里创建共享内存段会失败并回退 UDP，属预期噪音，成功时不必刷屏
function Show-Output([object[]]$Lines) {
    $Lines |
        Where-Object { $_ -notmatch 'RTPS_TRANSPORT_SHM|RTPS_PARTICIPANT|SharedMemManager|SharedSegment' } |
        ForEach-Object { Write-Ok $_ }
}

function Resolve-SdkRoot {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    if ($env:ROS2PY_SDK_ROOT) { return $env:ROS2PY_SDK_ROOT }

    $cfgPath = 'D:\deepseek project\config\ros2.config.psd1'
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $cfg = Import-PowerShellDataFile -Path $cfgPath
            if ($cfg.InstallRoot) { return $cfg.InstallRoot }
        } catch {
            Write-Warn2 "读取 $cfgPath 失败，退回默认路径：$($_.Exception.Message)"
        }
    }
    return 'D:\ros2\lyrical'
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# ---------------------------------------------------------------- 解析 SDK
$SdkRoot = (Resolve-SdkRoot -Explicit $SdkRoot).TrimEnd('\')
$BasePython = Join-Path $SdkRoot '.pixi\envs\default\python.exe'
$RosSitePackages = Join-Path $SdkRoot 'Lib\site-packages'
$RosBin = Join-Path $SdkRoot 'bin'

Write-Step "SDK = $SdkRoot"
foreach ($p in @($BasePython, (Join-Path $SdkRoot 'local_setup.bat'), $RosSitePackages, $RosBin)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "找不到 $p —— SDK 不完整或被移动了（SDK 不可重定位，见 AGENTS.md §2）" }
}
Write-Ok "SDK 结构完整（python / local_setup.bat / Lib\site-packages / bin）"

# ---------------------------------------------------------------- 只检查
if ($Check) {
    $fail = 0
    Write-Step '检查 .venv'
    if (Test-Path -LiteralPath $VenvPython) { Write-Ok $VenvPython } else { Write-Warn2 '缺少 .venv（跑不带 -Check 的同一条命令即可创建）'; $fail++ }

    Write-Step '检查 ros2py.pth'
    if (Test-Path -LiteralPath $PthFile) { Write-Ok $PthFile } else { Write-Warn2 '缺少 ros2py.pth'; $fail++ }

    if (Test-Path -LiteralPath $VenvPython) {
        Write-Step '检查 import rclpy + 起一个节点'
        $out = & $VenvPython -c "import rclpy; from rclpy.node import Node; rclpy.init(); n=Node('ros2py_check'); n.destroy_node(); rclpy.shutdown(); print('node lifecycle OK')" 2>&1
        if ($LASTEXITCODE -eq 0) { Show-Output $out } else { Write-Warn2 ($out -join ' '); $fail++ }

        Write-Step '检查工具链'
        $tools = & $VenvPython -c "import importlib.util as u; print(' '.join(m for m in ('ruff','pyright','pytest') if u.find_spec(m)))" 2>&1
        $found = ($tools -join ' ').Trim()
        Write-Ok "可用：$found"
        foreach ($need in @('ruff', 'pyright', 'pytest')) {
            if ($found -notmatch "\b$need\b") { Write-Warn2 "缺少 $need（跑不带 -Check 的同一条命令即可补装）"; $fail++ }
        }
    }

    if ($fail -gt 0) { Write-Host "检查未通过（$fail 项）" -ForegroundColor Red; exit 1 }
    Write-Host '检查全部通过' -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- 建/验 venv
if ($Force -and (Test-Path -LiteralPath $VenvPath)) {
    Write-Step "删除旧 venv（-Force）"
    Remove-Item -LiteralPath $VenvPath -Recurse -Force
}

if (-not (Test-Path -LiteralPath $VenvPython)) {
    Write-Step "创建 venv（基于 $BasePython）"
    & $BasePython -m venv --system-site-packages $VenvPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython)) { throw '创建 venv 失败' }
    Write-Ok $VenvPath
} else {
    Write-Ok "复用已有 venv：$VenvPath"
}

# ---------------------------------------------------------------- 配置 + 适配层挂载
Write-Step '写 ros2py.config.json'
$config = [ordered]@{
    sdk_root    = $SdkRoot
    python_paths = @('Lib\site-packages')
    # bin 给 rclpy 的 pyd，pixi 的 Library\bin 给 RMW / 日志插件
    dll_dirs    = @('bin', '.pixi\envs\default\Library\bin')
    path_dirs   = @('bin', '.pixi\envs\default\Library\bin', '.pixi\envs\default')
    env         = [ordered]@{ ROS_DISTRO = (Split-Path $SdkRoot -Leaf) }
    ros_log_dir = (Join-Path $WorkspaceRoot '.ros\log')
    _comment    = '由 tools\Setup-Ros2PyEnv.ps1 生成；换 SDK 位置后重跑该脚本，或临时用环境变量 ROS2PY_SDK_ROOT 覆盖。'
}
Write-Utf8NoBom -Path $ConfigJson -Content ($config | ConvertTo-Json -Depth 4)
Write-Ok $ConfigJson

Write-Step '写 ros2py.pth（挂载适配层）'
Write-Utf8NoBom -Path $PthFile -Content ("$ToolsDir`nimport ros2py_bootstrap`n")
Write-Ok $PthFile

# ---------------------------------------------------------------- 工具链
if (-not $SkipTools) {
    Write-Step '安装 ruff / pyright（已装则跳过）'
    & $VenvPython -m pip install --disable-pip-version-check -q --upgrade ruff pyright
    if ($LASTEXITCODE -ne 0) { Write-Warn2 'pip 安装失败（离线？可用 -SkipTools 跳过）' } else { Write-Ok 'ruff / pyright 就绪' }
}

# ---------------------------------------------------------------- 自检
Write-Step '自检 import rclpy + 节点生命周期'
$checkOut = & $VenvPython -c "import rclpy; from rclpy.node import Node; rclpy.init(); n=Node('ros2py_selftest'); n.get_logger().info('adapter ok'); n.destroy_node(); rclpy.shutdown(); import numpy; print('rclpy + node OK, numpy', numpy.__version__)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn2 ($checkOut -join "`n")
    Write-Host '导入失败。常见原因：SDK 被移动（重跑 20-Install-Ros2.ps1）或 bin 目录被删。' -ForegroundColor Red
    exit 1
}
Show-Output $checkOutWrite-Host "环境就绪：$VenvPython" -ForegroundColor Green
Write-Host "提示：VS Code 里执行 >Python: Select Interpreter 选 ${WorkspaceRoot}\.venv\Scripts\python.exe" -ForegroundColor Gray
