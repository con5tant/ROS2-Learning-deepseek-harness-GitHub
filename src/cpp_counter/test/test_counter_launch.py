# Copyright 2026 dev
"""
End-to-end launch_testing case for the counter publisher/subscriber pair.

This covers what the gtest cannot reach: real process startup, DDS discovery, parameter passing
and a clean exit. It is the automated version of the manual two-process check.
"""

import unittest

import launch
import launch_ros.actions
import launch_testing
import launch_testing.actions
import launch_testing.asserts


def generate_test_description():
    """Launch the listener first, then the talker, and start testing."""
    listener = launch_ros.actions.Node(
        package='cpp_counter',
        executable='counter_listener',
        name='counter_listener',
        parameters=[{'max_messages': 5}],
        output='screen',
    )

    # Start the talker only after the listener is up: otherwise the first messages are lost to
    # DDS discovery and the test becomes flaky (the exact problem the manual check hit).
    talker = launch.actions.TimerAction(
        period=2.0,
        actions=[
            launch_ros.actions.Node(
                package='cpp_counter',
                executable='counter_talker',
                name='counter_talker',
                parameters=[{'max_count': 5}],
                output='screen',
            )
        ],
    )

    return (
        launch.LaunchDescription(
            [
                listener,
                talker,
                launch_testing.actions.ReadyToTest(),
            ]
        ),
        {},
    )


class TestCounterPubSub(unittest.TestCase):
    """Assertions on the captured console output of both nodes."""

    def test_talker_publishes_all(self, proc_output):
        """The talker publishes every message up to max_count."""
        proc_output.assertWaitFor('published count=4', timeout=30)

    def test_listener_receives_all(self, proc_output):
        """The listener receives the last message and stops at max_messages."""
        proc_output.assertWaitFor('received count=4', timeout=30)
        proc_output.assertWaitFor('reached max_messages=5', timeout=10)


@launch_testing.post_shutdown_test()
class TestCounterCleanExit(unittest.TestCase):
    """Both nodes must exit cleanly instead of crashing or being killed."""

    def test_exit_codes(self, proc_info):
        """Exit codes are zero for every launched process."""
        launch_testing.asserts.assertExitCodes(proc_info)
