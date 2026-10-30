@echo off
rem Source the ROS 2 environment (SDK + workspace), then make C++ node DLLs resolvable.
rem
rem Why a separate file: PATH must be patched AFTER local_setup/setup has prepended its own
rem entries (Scripts, opt\...\bin). Doing it on one cmd line with && expands %PATH% at
rem parse time and silently drops those entries, so `ros2` itself disappears from PATH.
rem
rem Inputs (set by the caller, e.g. Ros2-Run.ps1):
rem   ROS2_SETUP_BAT  - quoted path to <SDK>\local_setup.bat
rem   ROS2_WORKSPACE  - workspace root, e.g. D:\ros2\ws
rem ASCII only: a non-ASCII .bat gets mangled by the GBK console code page.

call %ROS2_SETUP_BAT%

rem The workspace overlay is what registers cpp_counter/py_hello and puts install\bin on PATH.
if defined ROS2_WORKSPACE if exist "%ROS2_WORKSPACE%\install\setup.bat" call "%ROS2_WORKSPACE%\install\setup.bat"

for %%i in (%ROS2_SETUP_BAT%) do set "ROS2_SDK=%%~dpi"
if defined ROS2_WORKSPACE set "ROS2_WS_BIN=%ROS2_WORKSPACE%\install\bin"

set "PATH=%ROS2_SDK%bin;%ROS2_WS_BIN%;%PATH%"

rem Windows: Fast DDS shared-memory transport usually fails to create its segment here. It then
rem falls back to UDP anyway, but writes a GBK-encoded error line to stderr ("access denied" in
rem the ANSI code page), which breaks tools that decode captured output as UTF-8 - launch_testing
rem crashes on it. UDPv4 only: same result, no noise.
if not defined FASTDDS_BUILTIN_TRANSPORTS set "FASTDDS_BUILTIN_TRANSPORTS=UDPv4"

rem The sourced setup scripts often leave a non-zero ERRORLEVEL behind; the callers chain with
rem && , so force success here or every following command would be skipped.
exit /b 0
