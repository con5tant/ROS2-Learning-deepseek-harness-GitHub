"""py_hello 的 pytest 基线用例：包可导入、入口行为稳定。

colcon test 会以 ament_python 的方式发现并运行本目录下的 pytest。
"""

from py_hello.hello import main


def test_main_returns_zero():
    assert main() == 0


def test_main_prints_greeting(capsys):
    main()
    assert capsys.readouterr().out.strip() == "hello from py_hello"
