# colcon 工作区

**先读 [AGENTS.md](AGENTS.md) —— 那是本工作区的记忆文件（环境事实、构建方式、踩过的坑）。**

- 源码: src\（`py_hello` = Python 探针，`cpp_counter` = C++ 探针）
- 构建: `pwsh -File "D:\deepseek project\scripts\Ros2-Build.ps1"`
- 运行: `pwsh -File "D:\deepseek project\scripts\Ros2-Run.ps1" -Command "ros2 run cpp_counter counter_talker"`
- 测试: `pwsh -File "D:\deepseek project\scripts\Ros2-Test.ps1"`
- CI 门禁: `pwsh -File .\tools\ci\Run-Ci.ps1`（全量约 22 秒，退出码即结论）
- 验证: `pwsh -File "D:\deepseek project\scripts\30-Verify-Install.ps1"`

## Python 开发环境

`.venv` 里已挂好 ROS 2 适配层，**普通 python 不用 source 就能 `import rclpy` 并起节点**：

```powershell
pwsh -NoProfile -File .\tools\Setup-Ros2PyEnv.ps1        # 建/刷新（幂等）
pwsh -NoProfile -File .\tools\Setup-Ros2PyEnv.ps1 -Check # 只体检

.\.venv\Scripts\python.exe -m pytest -q                  # 冒烟用例
.\.venv\Scripts\python.exe -m ruff check . --fix          # lint + 自动修
.\.venv\Scripts\python.exe -m ruff format .               # 格式化
```

VS Code 打开本目录即用：解释器已指向 `.venv`，保存自动 ruff 格式化，测试面板跑 pytest，F5 直接调试当前文件。

原理与边界见 AGENTS.md §7。

环境与安装的完整记录在 D:\deepseek project\docs\。

> 骨架由 D:\deepseek project\scripts\40-Init-DevWorkspace.ps1 生成；AGENTS.md 之后为手工维护。
