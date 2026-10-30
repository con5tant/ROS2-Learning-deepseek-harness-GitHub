# AGENTS.md —— ROS 2 工作区记忆文件

> **这是本工作区的"记忆"。任何新会话、新同事、新工具接手前，先读完这一份，再动手。**
> 建立：2026-10-30 ｜ 对应环境：ROS 2 Lyrical on Windows 11 ｜ 状态：环境可用，待办清零

---

## 0. 先搞清楚边界

| 位置 | 角色 | 能不能动 |
|---|---|---|
| `D:\ros2\ws`（**这里**） | 你的开发工作区：`src\` 放包，`build\`/`install\`/`log\` 是生成物 | ✅ 随便改 |
| `D:\ros2\lyrical` | ROS 2 SDK 安装目录（官方二进制 + pixi 环境，4.15 GB） | ❌ **不要手改**，升级走安装脚本 |
| `D:\ros2\_cache` | 安装包缓存（0.51 GB，`ros2-lyrical-2026-08-07-windows-AMD64.zip`） | ⚠️ 只想省空间可整个删，重装会重新下载 |
| `D:\deepseek project` | 环境配置工作区：安装/验证脚本、调研与计划文档、执行证据 | 改配置改这里 |

配置与安装的完整来龙去脉在 `D:\deepseek project\docs\`（调研报告 / 环境配置计划 / 执行手册）。
本文件只负责"在 `D:\ros2\ws` 里怎么干活"。

---

## 1. 三十秒上手

```powershell
# 进环境（子 shell，exit 离开；ROS_DOMAIN_ID / PYTHONUTF8 已自动注入）
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Shell.ps1'

# 不建 shell，跑一条命令就返回
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Run.ps1' -Command "ros2 topic list"

# 编译本工作区（自动装配 MSVC 环境 + ROS 环境，默认 --merge-install Release）
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Build.ps1'
```

> 脚本不在本目录，在 `D:\deepseek project\scripts\`。这些是绝对路径，从任何目录调用都行。
> **git 不在 PATH 上**，在 pixi 环境里：`D:\ros2\lyrical\.pixi\envs\default\Library\cmd\git.exe`（2.55）。

---

## 2. 环境事实（2026-10-30 实测，非推测）

| 项目 | 值 |
|---|---|
| 系统 | Windows 11 25H2，Build 26200.8655，AMD64 |
| 发行版 | ROS 2 **Lyrical**（官方唯一声明支持 Windows 11 的发行版） |
| 发布版本 | `release-lyrical-20260807` = Lyrical Patch Release 2（2026-08-07） |
| 安装包 SHA256 | `ab3305fc9961848072d0665e7a7f2a772d4ae5a9499a3ac4c902e9d6f9f6bc5c` |
| SDK 路径 | `D:\ros2\lyrical`（短路径、无空格，刻意为之） |
| 依赖后端 | conda-forge，前端 pixi **0.81.0**（`%LOCALAPPDATA%\pixi\bin\pixi.exe`） |
| 包数量 | **353** 个（`ros2 pkg list`） |
| 中间件 | 默认 Fast DDS（`rmw_fastrtps_cpp`）；RTI Connext 缺失警告属正常 |
| ROS_DOMAIN_ID | 0（多机/多实例时改 `D:\deepseek project\config\ros2.config.psd1`） |
| 编译链 | VS 2022 Build Tools 17.12.3（`Desktop development with C++`），x64 |
| 构建类型 | Release（官方二进制是 Release，下游必须 Release/RelWithDebInfo，否则 ABI 崩） |
| 长路径 | `LongPathsEnabled = 1`（已开） |
| 安装方式 | 官方二进制 zip + `pixi install` + `preinstall_setup_windows.py`（路径已就地修正，不可搬迁） |

**⚠️ SDK 不可重定位**：官方 zip 里的绝对路径已被 `preinstall_setup_windows.py` 写死成 `D:\ros2\lyrical`。把这个目录剪切到别处会直接坏掉，要换位置就重跑安装脚本。

---

## 3. 目录约定

```
D:\ros2\ws\
├─ AGENTS.md          ← 本文件（记忆，随代码一起提交）
├─ README.md          简短导航
├─ .gitignore         忽略 build/ install/ log/ .venv/ .ros/
├─ pyproject.toml     ruff / pytest 配置
├─ pyrightconfig.json pyright / Pylance 配置（含 SDK 的 extraPaths）
├─ .vscode\           解释器、保存格式化、pytest、调试配置（提交共享部分）
├─ .github\workflows\ci.yml  GitHub Actions 门禁（self-hosted Windows runner）
├─ .venv\             Python 环境（生成物，不提交；跑 tools\Setup-Ros2PyEnv.ps1 重建）
├─ tools\
│  ├─ Setup-Ros2PyEnv.ps1        建/刷新 .venv 与适配层（幂等，-Check 只检查）
│  ├─ ros2-env.bat               项目脚本统一调用的环境装配（SDK + 工作区 + C++ PATH 修补）
│  ├─ ci\
│  │  ├─ Run-Ci.ps1              CI 门禁本体（预检→构建→测试→Python），本地/CI 同一入口
│  │  └─ README.md               runner 要求与接法
│  └─ pyenv\                     适配层本体：ros2py_bootstrap.py + ros2py.config.json
├─ tests\             pytest 用例（根级；colcon test 仍看各包自己的 test/）
├─ src\
│  ├─ py_hello\       ament_python 探针（验证 Python 链路 + pytest 基线）
│  └─ cpp_counter\    ament_cmake 探针：自定义 msg/Counter.msg + 发布/订阅 + gtest + cpplint
├─ build\             生成物，不提交
├─ install\           合并安装产物（--merge-install，Windows 路径长度友好），不提交
└─ log\               构建日志，不提交
```

- 包一律放 `src\<包名>`，一个目录一个包（`package.xml` 在包根）。
- 构建**总是** `--merge-install`：`install\` 下不再为每个包开子目录，能显著少踩 260 字符限制。
- 不提交 `build/`、`install/`、`log/`（`.gitignore` 已配）。

---

## 4. 构建 / 运行 / 验证

**构建**（`Ros2-Build.ps1` 做的事：定位 `VsDevCmd.bat -arch=amd64` → `call local_setup.bat` → `colcon build --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release`）

```powershell
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Build.ps1'
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Build.ps1' -PackageSelect py_hello
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Build.ps1' -DebugBuild   # 慎用，见下方 ABI 说明
```

**运行**（`Ros2-Run.ps1` 会 `call tools\ros2-env.bat`，里面已经 source 了 SDK + 工作区）

```powershell
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Run.ps1' -Command 'ros2 run py_hello hello'
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Run.ps1' -Command 'ros2 run cpp_counter counter_talker'
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Run.ps1' -Command 'ros2 run cpp_counter counter_listener --ros-args -p max_messages:=5'
```

**测试**（`colcon test` 必须在工作区目录里跑，否则会把 SDK 的 361 个包一起测）

```powershell
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Test.ps1'
pwsh -NoProfile -File 'D:\deepseek project\scripts\Ros2-Test.ps1' -PackageSelect cpp_counter
```

当前基线：**27 tests / 0 failures / 4 skipped**（约 14 秒）。构成：

| 套件 | 数量 | 说明 |
|---|---|---|
| `test_counter.gtest` | 2 | 生成类型的字段默认值 / 往返 |
| `test_counter_launch.py` | 3 | **端到端**：真实起 talker + listener，断言 5/5 收发与退出码 |
| `cpplint` / `lint_cmake` / `xmllint` / `flake8` / `pep257` | 4+1+1+1+1 | lint（`cppcheck` 4 条因未安装而 skipped） |
| `py_hello` pytest | 2 | 入口函数行为 |

`src\` 里的 Python 走 ROS 风格（flake8 要单引号、pep257 要英文 docstring），由 `colcon test` 检查；
根目录 ruff 只管 `tools\` 与 `tests\`（见 `pyproject.toml` 的 `extend-exclude`）。

**CI 门禁**（一条命令 = 预检 → 构建 → colcon test → ruff/pytest，全跑完再汇总；退出码即结论）

```powershell
pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1              # 全量，约 22 秒
pwsh -NoProfile -File .\tools\ci\Run-Ci.ps1 -Stage python # 只跑静态检查，约 2 秒
```

报告写到 `log\ci\<时间戳>\`（`summary.md` + `result.json`）。GitHub Actions 见 `.github\workflows\ci.yml`，
runner 要求见 [`tools/ci/README.md`](tools/ci/README.md)。

**冒烟验证**（包列表 / DDS 多播 / C++↔Python 互通，3 项）

```powershell
pwsh -NoProfile -File 'D:\deepseek project\scripts\30-Verify-Install.ps1'
```

---

## 5. 必须知道的坑（都踩过，别重复踩）

完整版见 `D:\deepseek project\docs\03-执行手册.md` §10。这里只留会反复咬人的七条：

1. **引号三层转义**：路径要穿过 PowerShell → pixi(Rust) → `cmd`，写成 `cmd /c "call \"D:\...\x.bat\""` 必坏。
   做法：路径放环境变量 `ROS2_SETUP_BAT`（值自带引号），命令里只写 `call %ROS2_SETUP_BAT%`。
2. **`set X=1 && ...` 会带尾随空格**（值变成 `"1 "`）。做法：环境变量用 PowerShell 的 `$env:X = '1'`，子进程继承。
3. **中文 Windows 默认 GBK**：`colcon` 用默认编码读 `setup.py`，文件里有中文就 `UnicodeDecodeError`。
   做法：构建前 `$env:PYTHONUTF8 = '1'`（`Ros2-Build.ps1` 已内置）。所以新包的 `setup.py` 可以放心写中文。
4. **ABI**：官方 SDK 是 Release 构建。自己编的节点必须 `Release` 或 `RelWithDebInfo`，用 `-DebugBuild` 编出来的包跟 SDK 链接会崩。
5. **`ros2 run` 找不到包**：八成是没 `call install\setup.bat`，或构建时没加 `--merge-install`。
6. **写 `src\` 报 `Access denied`**：`D:\ros2` 根带 **Low 完整性标记**，而 `src`/`build`/`install`/`log` 是安装脚本早期建的、没继承该标记（= Medium），受限进程一律写不进。
   已用管理员 `icacls <目录> /setintegritylevel "(OI)(CI)Low" /T` 补齐（2026-10-30）；此后新建目录会自动继承。再遇到就先 `icacls <目录> | findstr Mandatory` 看标记。
7. **自编 C++ 节点起不来（本机特有，已修）**：两个叠加问题，都在 `Ros2-Run/Shell/Build/Test` 里处理了，别改回去：
   - `rcl_logging_spdlog.dll` 在 `<SDK>\bin`，但 `local_setup.bat` 不把该目录加进 PATH → `LoadLibrary error 126` 后崩；`<ws>\install\bin` 同样要加（自定义 msg 的 typesupport 插件在里面）。
   - `ROS_LOG_DIR` 指向 **C:** 时 `rclcpp::init` 直接 `0xC0000409`（同一二进制指向 D: 就正常，复现 3/3）→ 日志目录固定到 `ws\.ros\log`。
   - 两个修补都必须在 **setup.bat 之后、且逐行执行**：单行 `&&` 里的 `%PATH%` 是解析时展开的，会把 setup.bat 加的 `Scripts` 覆盖掉（`ros2` 直接消失）。所以统一由 [`tools\ros2-env.bat`](tools/ros2-env.bat) 分两步做，四个脚本只负责 `call %ROS2_ENV_BAT%`；在父进程里前置 PATH 则会搞坏 pixi 子环境。
   - `ros2-env.bat` 末尾必须 `exit /b 0`：setup 脚本常留下非零 ERRORLEVEL，而调用方用 `&&` 串联。

---

## 6. 当前状态

- ✅ 环境：`D:\ros2\lyrical` 安装完成，`local_setup.bat` 就位，pixi 环境可用
- ✅ 验证：3/3 通过（353 包 / 多播通 / C++ talker ↔ Python listener 互通）
- ✅ 工作区：`src\py_hello` 构建成功，`ros2 run py_hello hello` 输出 `hello from py_hello`
- ✅ 长路径已开启，MSVC 就绪
- ✅ Python：`.venv` + 适配层就位，`python -m pytest -q` 3 passed，`ruff check` / `format --check` 全绿
- ✅ C++：`src\cpp_counter` 构建成功（自定义 msg + 发布/订阅），双进程端到端 5/5 消息收到
- ✅ 测试：`Ros2-Test.ps1` → 27 tests / 0 failures / 4 skipped（含 launch_testing 端到端 3 条）
- ✅ CI：`tools\ci\Run-Ci.ps1` 全量门禁 4/4 阶段 PASS（约 22 秒），GitHub Actions 配置就位（等 runner）
- 待办：**无**

`py_hello` 与 `cpp_counter` 都是"工具链探针"，不是业务代码：前者验证 ament_python 链路，后者验证 MSVC + ament_cmake + rosidl 生成。确认无误后都可以删。

---

## 7. Python 开发环境（.venv + ROS 适配层）

**一句话**：普通 `python` 不用 `source` 就能 `import rclpy`，还能 `rclpy.init()` 起节点。

```powershell
# 建/刷新（幂等；换过 SDK 位置或重装 SDK 后重跑）
pwsh -NoProfile -File .\tools\Setup-Ros2PyEnv.ps1

# 只体检，不改任何东西（CI 里也能用）
pwsh -NoProfile -File .\tools\Setup-Ros2PyEnv.ps1 -Check

# 日常
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check . --fix
```

| 项 | 值 |
|---|---|
| 解释器 | `D:\ros2\ws\.venv\Scripts\python.exe`（Python 3.12.3，`--system-site-packages` 继承 SDK 的 pytest / mypy / numpy） |
| 适配层 | `tools\pyenv\ros2py_bootstrap.py`，通过 `.venv\Lib\site-packages\ros2py.pth` 挂载 |
| 配置单一来源 | `tools\pyenv\ros2py.config.json`（SDK 路径、DLL 目录、ROS_LOG_DIR）；临时覆盖用环境变量 `ROS2PY_SDK_ROOT` |
| 工具 | ruff 0.17.3（lint + format）、pytest；pyright 已装但 **CLI 需要 Node.js**（IDE 里的 Pylance 自带运行时，不受影响） |
| 日志 | 适配层把 `ROS_LOG_DIR` 指到 `ws\.ros\log`（用户目录不可写时 rclpy 会直接 init 失败） |

**适配层到底做了什么**（四件事，缺一件就在某个阶段炸）：

1. `sys.path` 追加 `<SDK>\Lib\site-packages` —— rclpy / `*_msgs` / launch 都在这；
2. `os.add_dll_directory` 加 `<SDK>\bin` 和 `<SDK>\.pixi\envs\default\Library\bin` —— 前者给 `_rclpy_pybind11`，后者给 RMW / 日志插件（**Python 3.8+ 不用 PATH 解析扩展模块依赖，只加 PYTHONPATH 必然 `DLL load failed`**）；
3. 设 `AMENT_PREFIX_PATH=<SDK>` —— 不设则 `failed to load any RMW implementations`；
4. `PATH` 前置 SDK 的 bin / pixi 目录 —— `ros2 run`、launch 起的子进程靠它找 DLL 和 exe。

以上全部**懒加载**：只有进程第一次真的要 import 一个 ROS 模块时才注入，所以 `import numpy` 或无关脚本完全不受 `<SDK>\bin` 里那堆 Qt、zlib 影响。

**已知边界**：

- Fast DDS 的共享内存传输在 Windows 上建段会失败并回退 UDP；它的错误串是 **GBK**，会让按 UTF-8 解
  码输出的工具（典型：`launch_testing`）直接抛 `UnicodeDecodeError`。所以 `tools\ros2-env.bat` 统一设
  `FASTDDS_BUILTIN_TRANSPORTS=UDPv4`（行为等价，少噪音、少坑）。Python 适配层没设这个变量，裸 `python`
  跑节点时仍可能看到 `RTPS_TRANSPORT_SHM Error` —— 噪音，不影响功能。
- `ros2` CLI、多节点联调仍建议走 `Ros2-Shell.ps1` / `Ros2-Run.ps1`：那套还额外设了 `ROS_DOMAIN_ID`、`RMW_IMPLEMENTATION` 等。
- 别在 `lyrical` 里建 venv（SDK 不可重定位）；`.venv` 必须带 `--system-site-packages`，否则看不到 SDK 自带的 pytest/mypy/numpy。

---

## 8. 下一步建议（按性价比排序）

1. **把 CI 接到远端**：仓库已 `git init` + 首次提交（本地 `main`，无远端）。下一步是建远端（GitHub/GitLab）、
   `git remote add` + `push`，再注册 self-hosted runner（标签 `windows,ros2-lyrical`）；之后 push/PR 自动跑
   `tools\ci\Run-Ci.ps1`。runner 要求见 [`tools/ci/README.md`](tools/ci/README.md)。
2. **扩展 launch_testing**：现在只断言"收到最后一条 + 干净退出"，可以再加消息内容断言、QoS 场景、
   "listener 晚加入"的用例（验证丢包策略），把运行时行为也纳入门禁。
3. **确认是否需要仿真**：Gazebo / 完整 `desktop` 包在此 SDK 里没有。需要就另开 WSL2 分支（Ubuntu 24.04 + `ros-jazzy-desktop`），**不要**在 Windows 原生上硬凑。
4. **清理缓存**：`D:\ros2\_cache`（0.51 GB）确认不再重装后可以删。
5. **装 cppcheck**：那 4 个 skipped 就能变实跑（`pixi global install cppcheck` 或 conda）。

---

## 9. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-30 | 建立本记忆文件；环境安装完成并 3/3 验证通过；长路径开启 |
| 2026-10-30 | 配置 Python 开发环境：`.venv`（3.12.3，system-site-packages）+ `tools\pyenv` 懒加载适配层（sys.path / DLL 目录 / AMENT_PREFIX_PATH / PATH / ROS_LOG_DIR）；普通 python 可直接 import rclpy 并起节点；加 ruff+pytest 配置与 `tests\` 冒烟用例；补 `.vscode` 解释器与调试配置 |
| 2026-10-30 | 修文件权限：`D:\ros2`、`ws` 补 `WRITE_OWNER`；`ws`/`src`/`build`/`install`/`log` 补 Low 完整性标记（管理员 `icacls`）。复测：`src` 可写、`colcon build` 成功（3.5 s）、`ros2 run py_hello hello` → `hello from py_hello` |
| 2026-10-30 | 补 C++ 链路：新增 `src\cpp_counter`（`msg/Counter.msg` + talker/listener + `minimal_probe` 探针 + gtest + cpplint），`rosidl_get_typesupport_target` 链接自己生成的接口；双进程端到端收到 5/5 消息 |
| 2026-10-30 | 建 `colcon test` 基线：`Ros2-Test.ps1`（新增）+ py_hello 的 pytest 用例 → 19 tests / 0 failures / 4 skipped |
| 2026-10-30 | 修 C++ 运行期环境：新增 `tools\ros2-env.bat`（SDK + 工作区 overlay + `<SDK>\bin`、`<ws>\install\bin` 进 PATH），`Ros2-Run/Shell/Build/Test` 统一改用它；`ROS_LOG_DIR` 固定到 `ws\.ros\log`（本机 C: 路径会让 `rclcpp::init` 崩）。复测：`ros2 run` 双进程 5/5 消息、构建与测试全绿 |
| 2026-10-30 | 接 CI：新增 `tools\ci\Run-Ci.ps1`（预检→构建→测试→ruff/pytest，全跑完再汇总，退出码即结论，报告落 `log\ci\`）+ `.github\workflows\ci.yml`（self-hosted Windows runner）+ `tools\ci\README.md`；支持 `-Workspace` 让 checkout 到任意目录也能跑。本机全量 4/4 PASS，22 秒 |
| 2026-10-30 | 初始化 git 仓库（`main`，本地身份 `dev <dev@example.com>`，换行策略见 `.gitattributes`），首次提交 33 个文件；CI 加 `-Bootstrap`，全新 checkout 会自动建 `.venv`；**修 `Ros2-Test.ps1` 漏写 `colcon`**（命令实际是 `test --merge-install`，测试从未真正执行，之前看到的 19 tests 是旧结果），并加"没有 test_* 日志即失败"防止 CI 假绿 |
| 2026-10-30 | 加 `launch_testing` 端到端用例：`cpp_counter/test/test_counter_launch.py`（listener 先起、2 s 后再起 talker，断言 5/5 收发 + 退出码），接入 `add_launch_test`；环境里加 `FASTDDS_BUILTIN_TRANSPORTS=UDPv4`——Windows 上 SHM 建段失败会输出 **GBK** 错误串，把按 UTF-8 解码的 `launch_testing` 直接搞崩；ruff 只管 `tools\`/`tests\`，`src\` 交给 ament_flake8/pep257。基线 19 → **27 tests / 0 failures** |

> 后续每次动过环境、改过构建方式、加了重要包，都在这里补一行 —— 下一个接手的人（或下一个你）靠这个对齐。
