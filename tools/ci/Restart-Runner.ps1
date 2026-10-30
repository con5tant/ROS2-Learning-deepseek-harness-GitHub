#Requires -Version 7.0
<#
.SYNOPSIS
    重启 self-hosted runner，等它真的连上 GitHub，再（可选）立刻触发一次 workflow。

.DESCRIPTION
    这台机器到 GitHub Actions 的长连接很不稳（`BrokerServer … ResponseEnded` / `SocketException 995`）。
    runner 只有在“重连成功 → Listening for Jobs”的那段窗口里才接得到任务，否则页面上的 job 会一直排队。

    所以这个脚本把三件事连起来做，尽量压掉窗口：
      1. 杀掉旧 Runner.Listener（连坏了的进程不会自己恢复）；
      2. 重新启动 run.cmd，并轮询日志直到出现 `Listening for Jobs`；
      3. 加 -Trigger 时立刻推一个空提交，让 workflow 在连接还热的时候被接走。

.EXAMPLE
    pwsh -NoProfile -File .\tools\ci\Restart-Runner.ps1
    pwsh -NoProfile -File .\tools\ci\Restart-Runner.ps1 -Trigger
#>
[CmdletBinding()]
param(
    [string]$RunnerDir = 'D:\actions-runner',
    [int]$TimeoutSeconds = 120,
    [switch]$Trigger,
    [string]$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

function Get-LatestRunnerLog {
    Get-ChildItem -Path (Join-Path $RunnerDir '_diag') -Filter 'Runner_*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if (-not (Test-Path -LiteralPath (Join-Path $RunnerDir 'run.cmd'))) {
    throw "找不到 $RunnerDir\run.cmd —— runner 没装在这里？"
}

Write-Host '==> 停止旧 runner' -ForegroundColor Cyan
Get-Process -Name 'Runner.Listener', 'Runner.Worker' -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "    kill $($_.ProcessName) $($_.Id)" -ForegroundColor DarkGray; Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 2

Write-Host '==> 启动 runner' -ForegroundColor Cyan
Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'run.cmd' -WorkingDirectory $RunnerDir -WindowStyle Hidden | Out-Null

$connected = $false
$watch = [Diagnostics.Stopwatch]::StartNew()
while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    Start-Sleep -Seconds 5
    $log = Get-LatestRunnerLog
    if (-not $log) { continue }
    if (Select-String -Path $log.FullName -Pattern 'Listening for Jobs' -Quiet) {
        $connected = $true
        Write-Host "    已连接（$([int]$watch.Elapsed.TotalSeconds) 秒）：Listening for Jobs" -ForegroundColor Green
        break
    }
}

if (-not $connected) {
    Write-Host "    $TimeoutSeconds 秒内没连上。看日志：" -ForegroundColor Red
    (Get-LatestRunnerLog).FullName
    Write-Host '    如果日志里全是 BrokerServer … ResponseEnded，就需要代理（见 tools/ci/README.md）。' -ForegroundColor Yellow
    exit 1
}

if (-not $Trigger) {
    Write-Host '完成。要触发一次 workflow：加 -Trigger 重跑本脚本，或自己 push 一个空提交。' -ForegroundColor Gray
    exit 0
}

Write-Host '==> 触发 workflow（空提交）' -ForegroundColor Cyan
$git = 'D:\ros2\lyrical\.pixi\envs\default\Library\cmd\git.exe'
if (-not (Test-Path -LiteralPath $git)) { $git = 'git' }

Push-Location $RepoDir
try {
    & $git commit --allow-empty -q -m "ci: 重跑（Restart-Runner.ps1 -Trigger）"
    for ($i = 1; $i -le 3; $i++) {
        & $git push origin main 2>&1 | Select-Object -Last 2
        if ($LASTEXITCODE -eq 0) { Write-Host '    已推送' -ForegroundColor Green; break }
        Write-Host "    第 $i 次推送失败，重试" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}
finally {
    Pop-Location
}

Write-Host '去 https://github.com/con5tant/ROS2-Learning-deepseek-harness-GitHub/actions 看结果（约 3 分钟）。' -ForegroundColor Gray
