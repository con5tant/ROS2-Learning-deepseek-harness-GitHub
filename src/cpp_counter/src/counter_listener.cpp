// Copyright 2026 dev
// Minimal subscriber for cpp_counter/msg/Counter.
// Prints every received message; max_messages > 0 makes it exit after N messages so the
// smoke test can wait for a clean shutdown instead of killing the process.

#include <memory>

#include "rclcpp/rclcpp.hpp"

#include "cpp_counter/msg/counter.hpp"

class CounterListener : public rclcpp::Node
{
public:
  CounterListener()
  : Node("counter_listener")
  {
    max_messages_ = declare_parameter<int>("max_messages", 0);
    subscription_ = create_subscription<cpp_counter::msg::Counter>(
      "counter", 10,
      [this](const cpp_counter::msg::Counter & message) {
        ++received_;
        RCLCPP_INFO(
          get_logger(), "received count=%d label=%s total=%d",
          message.count, message.label.c_str(), received_);
        if (max_messages_ > 0 && received_ >= max_messages_) {
          RCLCPP_INFO(get_logger(), "reached max_messages=%d, shutting down", max_messages_);
          rclcpp::shutdown();
        }
      });
  }

private:
  rclcpp::Subscription<cpp_counter::msg::Counter>::SharedPtr subscription_;
  int max_messages_ = 0;
  int received_ = 0;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<CounterListener>());
  rclcpp::shutdown();
  return 0;
}
