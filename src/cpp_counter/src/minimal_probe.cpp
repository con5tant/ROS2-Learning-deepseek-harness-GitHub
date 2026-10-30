// Copyright 2026 dev
// Toolchain probe: bare rclcpp init/shutdown in this workspace's build.
// No logging before init, no argv — narrows any startup failure to rclcpp itself.

#include <memory>

#include "rclcpp/rclcpp.hpp"

int main(int argc, char ** argv)
{
  (void)argc;
  (void)argv;

  rclcpp::init(0, nullptr);

  auto node = std::make_shared<rclcpp::Node>("minimal_probe");
  RCLCPP_INFO(node->get_logger(), "node constructed: %s", node->get_name());

  rclcpp::shutdown();
  RCLCPP_INFO(rclcpp::get_logger("probe"), "after rclcpp::shutdown");
  return 0;
}
