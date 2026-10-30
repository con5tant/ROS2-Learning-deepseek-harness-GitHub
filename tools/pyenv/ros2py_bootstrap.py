"""ROS 2 的 Python 适配层（懒加载）。

让普通 Python 进程（VS Code 调试器、pytest、REPL、脚本）不用先
``call local_setup.bat`` 就能 ``import rclpy``，并且能真正 ``rclpy.init()`` 起节点。

四件必须同时做的事（缺一条就会在某个阶段报错）：

1. **sys.path** —— ROS 的 Python 包（rclpy / *_msgs / launch …）不在 venv 里，而在
   ``<SDK>\\Lib\\site-packages``；
2. **DLL 搜索目录** —— ``_rclpy_pybind11`` 依赖 ``<SDK>\\bin``，而 RMW / 日志插件
   （rmw_fastrtps_cpp、rcl_logging_spdlog）还依赖 pixi 环境的 ``Library\\bin``。
   Python 3.8+ 不再用 PATH 解析扩展模块依赖，必须 ``os.add_dll_directory``；
3. **AMENT_PREFIX_PATH** —— rcl 通过 ament index 找 RMW 实现，不设就报
   ``failed to load any RMW implementations``；
4. **PATH** —— ``ros2 run`` / launch 起的子进程（node 可执行文件、pixi 里的工具）
   靠 PATH 找 DLL 和 exe。

为什么懒加载：``<SDK>\\bin`` 里除了 ROS 还有 Qt、zlib、openssl 等，提前加进搜索路径
会影响无关进程（numpy / PyQt / matplotlib 可能加载到错误版本）。这里只在"第一次真的
要 import 一个 ROS 模块"时才注入并改写环境变量，所以 ``import numpy`` 完全不受影响。

挂载方式：venv 的 ``Lib\\site-packages\\ros2py.pth`` 两行——
    第 1 行把本目录加入 sys.path
    第 2 行 ``import ros2py_bootstrap``
由 ``tools\\Setup-Ros2PyEnv.ps1`` 生成；换 SDK 位置或重装 SDK 后重跑该脚本即可。
"""

from __future__ import annotations

import contextlib
import importlib.abc
import json
import os
import sys
from typing import Any

__all__ = ["activate", "deactivate", "status"]

_HERE = os.path.dirname(os.path.abspath(__file__))
_CONFIG_FILE = os.path.join(_HERE, "ros2py.config.json")

_DEFAULT_CONFIG: dict[str, Any] = {
    "sdk_root": r"D:\ros2\lyrical",
    "python_paths": ["Lib\\site-packages"],
    "dll_dirs": ["bin", ".pixi\\envs\\default\\Library\\bin"],
    "path_dirs": ["bin", ".pixi\\envs\\default\\Library\\bin", ".pixi\\envs\\default"],
    "env": {"ROS_DISTRO": "lyrical"},
}

# handles 必须一直持有：os.add_dll_directory 返回的句柄一旦被回收，目录就会从搜索
# 路径里移除（CPython 的 _AddedDllDirectory.__del__）。
_state: dict[str, Any] = {
    "activated": False,
    "handles": [],
    "sdk_root": None,
    "python_paths": [],
    "dll_dirs": [],
    "path_dirs": [],
    "env_applied": [],
    "warnings": [],
}


def _load_config() -> dict[str, Any]:
    """读配置；环境变量 ROS2PY_SDK_ROOT 可临时覆盖 SDK 根目录。"""
    cfg: dict[str, Any] = dict(_DEFAULT_CONFIG)
    try:
        with open(_CONFIG_FILE, encoding="utf-8") as fh:
            cfg.update(json.load(fh))
    except FileNotFoundError:
        pass
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"[ros2py] 读取 {_CONFIG_FILE} 失败，用默认配置：{exc}\n")

    override = os.environ.get("ROS2PY_SDK_ROOT")
    if override:
        cfg["sdk_root"] = override
    return cfg


def _join(root: str, parts: Any) -> list[str]:
    return [os.path.join(root, p) for p in parts or [] if p]


def _prepend_path(entries: list[str]) -> list[str]:
    current = os.environ.get("PATH", "")
    existing = [p for p in current.split(os.pathsep) if p]
    existing_lower = {p.rstrip("\\/").lower() for p in existing}
    added = [e for e in entries if e and e.rstrip("\\/").lower() not in existing_lower]
    if added:
        os.environ["PATH"] = os.pathsep.join(added + existing)
    return added


def _ensure_ament(sdk_root: str) -> None:
    current = os.environ.get("AMENT_PREFIX_PATH", "")
    if not current:
        os.environ["AMENT_PREFIX_PATH"] = sdk_root
        _state["env_applied"].append("AMENT_PREFIX_PATH")
        return
    known = {p.rstrip("\\/").lower() for p in current.split(os.pathsep) if p}
    if sdk_root.rstrip("\\/").lower() not in known:
        os.environ["AMENT_PREFIX_PATH"] = current + os.pathsep + sdk_root
        _state["env_applied"].append("AMENT_PREFIX_PATH(append)")


def _ensure_log_dir(cfg: dict[str, Any]) -> None:
    """日志目录：默认放在工作区里（用户目录不可写时 rclpy 会直接 init 失败）。"""
    log_dir = cfg.get("ros_log_dir")
    if not log_dir or os.environ.get("ROS_LOG_DIR"):
        return
    try:
        os.makedirs(log_dir, exist_ok=True)
        os.environ["ROS_LOG_DIR"] = log_dir
        _state["env_applied"].append("ROS_LOG_DIR")
    except OSError as exc:
        _state["warnings"].append(f"无法创建日志目录 {log_dir}：{exc}")


def activate() -> list[str]:
    """接上 ROS 的 sys.path / DLL 目录 / 环境变量；重复调用幂等。"""
    if _state["activated"]:
        return _state["python_paths"]

    cfg = _load_config()
    sdk_root = cfg.get("sdk_root") or ""
    _state["sdk_root"] = sdk_root

    added: list[str] = []
    for path in _join(sdk_root, cfg.get("python_paths")):
        if os.path.isdir(path) and path not in sys.path:
            sys.path.append(path)  # append：永远让 venv / 标准库优先
            added.append(path)
    _state["python_paths"] = added

    if os.name == "nt":
        for dll_dir in _join(sdk_root, cfg.get("dll_dirs")):
            if not os.path.isdir(dll_dir):
                continue
            try:
                _state["handles"].append(os.add_dll_directory(dll_dir))
                _state["dll_dirs"].append(dll_dir)
            except OSError as exc:
                _state["warnings"].append(f"add_dll_directory({dll_dir}) 失败：{exc}")

    _state["path_dirs"] = _prepend_path(_join(sdk_root, cfg.get("path_dirs")))

    if sdk_root:
        _ensure_ament(sdk_root)
    for key, value in (cfg.get("env") or {}).items():
        if key and key not in os.environ:
            os.environ[key] = str(value)
            _state["env_applied"].append(key)
    _ensure_log_dir(cfg)

    if not added:
        _state["warnings"].append(
            f"在 {sdk_root} 下没找到 Lib\\site-packages，SDK 可能被移动了（SDK 不可重定位，见 AGENTS.md §2）"
        )

    _state["activated"] = True
    _remove_finder()
    return added


def _remove_finder() -> None:
    for finder in list(sys.meta_path):
        if isinstance(finder, _RosModuleFinder):
            with contextlib.suppress(ValueError):
                sys.meta_path.remove(finder)


class _RosModuleFinder(importlib.abc.MetaPathFinder):
    """只在顶层模块名确实存在于 ROS site-packages 时才触发激活。"""

    def __init__(self, site_dirs: list[str]) -> None:
        self._site_dirs = site_dirs

    def find_spec(self, fullname: str, path=None, target=None):
        if path is None and "." not in fullname and self._is_ros_module(fullname):
            activate()
        return None  # 交给后面的正常 finder 去加载

    def _is_ros_module(self, name: str) -> bool:
        for site_dir in self._site_dirs:
            if os.path.isdir(os.path.join(site_dir, name)):
                return True
            if os.path.isfile(os.path.join(site_dir, name + ".py")):
                return True
        return False


def status() -> dict[str, Any]:
    """给 --check / 排障用：不触发激活，只报告配置和已生效的部分。"""
    cfg = _load_config()
    sdk_root = cfg.get("sdk_root") or ""
    return {
        "config_file": _CONFIG_FILE,
        "sdk_root": sdk_root,
        "sdk_exists": os.path.isdir(sdk_root),
        "python_paths": _join(sdk_root, cfg.get("python_paths")),
        "dll_dirs": _join(sdk_root, cfg.get("dll_dirs")),
        "activated": _state["activated"],
        "active_python_paths": _state["python_paths"],
        "active_dll_dirs": _state["dll_dirs"],
        "path_prepended": _state["path_dirs"],
        "env_applied": _state["env_applied"],
        "warnings": _state["warnings"],
        "python": sys.executable,
    }


def deactivate() -> None:
    """撤销 activate 的改动（主要给测试用；环境变量不回滚）。"""
    for handle in _state["handles"]:
        with contextlib.suppress(OSError):
            handle.close()
    _state["handles"].clear()
    for path in _state["python_paths"]:
        if path in sys.path:
            sys.path.remove(path)
    _state["activated"] = False


def _install() -> None:
    if _state["activated"]:
        return
    try:
        site_dirs = _join(_load_config().get("sdk_root"), _DEFAULT_CONFIG["python_paths"])
        sys.meta_path.insert(0, _RosModuleFinder(site_dirs))
    except Exception as exc:  # 永远不要因为适配层把解释器启动搞挂
        sys.stderr.write(f"[ros2py] 安装 finder 失败：{exc}\n")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="ROS 2 Python 适配层自检")
    parser.add_argument("--check", action="store_true", help="打印配置与状态")
    parser.add_argument("--init", action="store_true", help="真实 rclpy.init() 起一个节点再退出")
    ns = parser.parse_args()

    if ns.init:
        import rclpy
        from rclpy.node import Node

        rclpy.init()
        node = Node("ros2py_selftest")
        node.get_logger().info("ros2py bootstrap: node lifecycle ok")
        node.destroy_node()
        rclpy.shutdown()
        print("NODE LIFECYCLE OK")

    print(json.dumps(status(), indent=2, ensure_ascii=False))
else:
    _install()
