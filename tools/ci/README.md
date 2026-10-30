# CI

门禁本体是 [`Run-Ci.ps1`](Run-Ci.ps1)：**预检 → 构建 → colcon test → ruff/pytest**，跑完所有阶段再汇总，
退出码 0 = 全绿、非 0 = 有阶段失败。GitHub Actions 只是薄壳（`.github/workflows/ci.yml`），
所以本地、GitLab、Jenkins 都能直接用同一个脚本。

## 本地跑

```powershell
# 全量（和 CI 完全一致）
pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1

# 全新 checkout：没有 .venv，让门禁先建
pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1 -Bootstrap

# 只跑静态检查（改 Python 时最快，约 2 秒）
pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1 -Stage python

# 跳过构建，只跑测试
pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1 -SkipBuild -Stage test
```

报告落在 `log\ci\<时间戳>\`：`summary.md`（人看）+ `result.json`（机器读）。
想当"提交前门禁"用，就挂到 `pre-push` 钩子或 VS Code 任务里。

## GitHub Actions

### 为什么是 self-hosted

ROS 2 Lyrical 的 Windows 发行版是 4.15 GB 的官方 zip + pixi 环境，每次 workflow 现装
既慢又容易失败；而且这台机器上的环境有实测过的特殊修补（见 `AGENTS.md` §5 第 7 条）。
所以 workflow 跑在**已经装好 SDK 的 Windows runner** 上。

### runner 要求

| 项 | 要求 |
|---|---|
| 系统 | Windows 11 x64（与开发机同构最省事） |
| SDK | `D:\ros2\lyrical` 已装好，`local_setup.bat` 存在 |
| 项目脚本 | `D:\deepseek project\scripts`（`Ros2-Build.ps1` / `Ros2-Test.ps1` 等） |
| 工具 | PowerShell 7、pixi（`%LOCALAPPDATA%\pixi\bin\pixi.exe`）、VS 2022 Build Tools |
| 标签 | `self-hosted`、`windows`、`ros2-lyrical` |

注册（在 runner 目录下执行，用仓库的 registration token）：

```powershell
.\config.cmd --url https://github.com/<org>/<repo> --token <TOKEN> --labels self-hosted,windows,ros2-lyrical --name ros2-win-01
.\run.cmd
```

### 工作流做了什么

1. `actions/checkout` 把仓库拉到 runner 的 `_work` 目录；
2. `Run-Ci.ps1 -Workspace <checkout>`：脚本生成一份**只替换 `UserWorkspace` 的临时配置**，
   所以门禁在 checkout 副本上跑，而不是改动 `D:\ros2\ws`；
3. 结果写进 Job Summary，并把 `log/ci/**` 与 `build/**/test_results/**` 作为 artifact 上传（保留 14 天）。

> 没配 runner 之前这个 workflow 会一直排队，属预期；本地 `Run-Ci.ps1` 不受影响。
