cmake_minimum_required(VERSION 3.16)
project(cpp_counter)

# SDK 是 Release 构建，C++ 标准必须与之一致（C++17）
if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rosidl_default_generators REQUIRED)

# 生成 msg/Counter.msg 对应的 C++ 类型
rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/Counter.msg"
)

add_executable(counter_talker src/counter_talker.cpp)
add_executable(counter_listener src/counter_listener.cpp)
add_executable(minimal_probe src/minimal_probe.cpp)
target_link_libraries(minimal_probe rclcpp::rclcpp)

# 同包内使用自己生成的接口：必须链接 typesupport 目标，否则运行期找不到类型支持
rosidl_get_typesupport_target(cpp_typesupport_target ${PROJECT_NAME} "rosidl_typesupport_cpp")
target_link_libraries(counter_talker rclcpp::rclcpp "${cpp_typesupport_target}")
target_link_libraries(counter_listener rclcpp::rclcpp "${cpp_typesupport_target}")

install(TARGETS counter_talker counter_listener minimal_probe
  DESTINATION lib/${PROJECT_NAME}
)

# 让工作区被 source 时自动设置 ROS_LOG_DIR（见 env-hooks/ros_log_dir.bat 里的说明）
ament_environment_hooks("${CMAKE_CURRENT_SOURCE_DIR}/env-hooks/ros_log_dir.bat")

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  # 只保留 cpplint / cppcheck / lint_cmake；格式化与版权头暂不纳入基线
  set(AMENT_LINT_AUTO_EXCLUDE
    ament_cmake_uncrustify
    ament_cmake_clang_format
    ament_cmake_copyright
  )
  ament_lint_auto_find_test_dependencies()

  find_package(ament_cmake_gtest REQUIRED)
  ament_add_gtest(test_counter test/test_counter.cpp)
  if(TARGET test_counter)
    target_link_libraries(test_counter "${cpp_typesupport_target}")
  endif()

  # 端到端：真实起 talker + listener，验证 DDS 收发与正常退出
  find_package(launch_testing_ament_cmake REQUIRED)
  add_launch_test(test/test_counter_launch.py TIMEOUT 90)
endif()

ament_package()
