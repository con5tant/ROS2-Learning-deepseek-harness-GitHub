@echo off
rem Keep ROS logs inside the workspace.
rem Reason: on this machine rclcpp::init crash-fails (0xC0000409) when ROS_LOG_DIR
rem points to the C: drive, and works when it points to D:. ASCII only on purpose:
rem a non-ASCII .bat gets mangled by the GBK console code page.
rem %~dp0 = <ws>\install\share\cpp_counter\environment\
if "%ROS_LOG_DIR%"=="" set "ROS_LOG_DIR=%~dp0..\..\..\..\.ros\log"
