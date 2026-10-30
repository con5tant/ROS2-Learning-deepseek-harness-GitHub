"""适配层冒烟测试：验证「普通 python 进程能直接起 ROS 2 节点」。

这条测试本身就是环境是否配好的判据：
  .venv\\Scripts\\python.exe -m pytest -q
"""

import rclpy
from rclpy.node import Node


def test_import_rclpy():
    assert rclpy.__file__.lower().replace("/", "\\").startswith("d:\\ros2\\lyrical")


def test_bootstrap_status():
    import ros2py_bootstrap

    info = ros2py_bootstrap.status()
    assert info["sdk_exists"] is True
    assert info["activated"] is True, "import rclpy 之后适配层应已激活"
    assert info["active_python_paths"], "ROS 的 site-packages 应已注入 sys.path"


def test_node_lifecycle():
    rclpy.init()
    try:
        node = Node("pytest_smoke")
        assert node.get_name() == "pytest_smoke"
        node.destroy_node()
    finally:
        rclpy.shutdown()
