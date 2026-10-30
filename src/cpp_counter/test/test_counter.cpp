// Copyright 2026 dev
// Field-level test for the generated interface type.
// If rosidl generation or typesupport linking is broken, this fails to build rather than
// failing at runtime, which is exactly the signal we want from a toolchain probe.

#include <string>

#include "gtest/gtest.h"

#include "cpp_counter/msg/counter.hpp"

TEST(CounterMessage, DefaultsAreZeroAndEmpty)
{
  cpp_counter::msg::Counter message;
  EXPECT_EQ(message.count, 0);
  EXPECT_TRUE(message.label.empty());
}

TEST(CounterMessage, FieldsRoundTrip)
{
  cpp_counter::msg::Counter message;
  message.count = 7;
  message.label = "cpp_counter";

  EXPECT_EQ(message.count, 7);
  EXPECT_EQ(message.label, std::string("cpp_counter"));
}
