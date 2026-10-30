// Copyright 2026 dev
// Minimal publisher for cpp_counter/msg/Counter.
// Verifies: rosidl code generation + rclcpp + same-package typesupport linking.

#include <chrono>
#include <functional>
#include <memory>

#include "rclcpp/rclcpp.hpp"

#include "cpp_counter/msg/counter.hpp"

using namespace std::chrono_literals;

class CounterTalker : public rclcpp::Node
{
public:
  CounterTalker()
  : Node("counter_talker")
  {
    publisher_ = create_publisher<cpp_counter::msg::Counter>("counter", 10);
    max_count_ = declare_parameter<int>("max_count", 5);
    timer_ = create_wall_timer(500ms, std::bind(&CounterTalker::on_timer, this));
    RCLCPP_INFO(
      get_logger(), "counter_talker started, publishing %d messages", max_count_);
  }

private:
  void on_timer()
  {
    if (sent_ >= max_count_) {
      RCLCPP_INFO(get_logger(), "published %d messages, shutting down", sent_);
      rclcpp::shutdown();
      return;
    }

    cpp_counter::msg::Counter message;
    message.count = sent_;
    message.label = "cpp_counter";
    publisher_->publish(message);

    RCLCPP_INFO(get_logger(), "published count=%d label=%s", message.count, message.label.c_str());
    ++sent_;
  }

  rclcpp::Publisher<cpp_counter::msg::Counter>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
  int max_count_ = 5;
  int sent_ = 0;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<CounterTalker>());
  rclcpp::shutdown();
  return 0;
}
