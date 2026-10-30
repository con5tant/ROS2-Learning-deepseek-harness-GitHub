from setuptools import setup

package_name = "py_hello"

setup(
    name=package_name,
    version="0.1.0",
    packages=[package_name],
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
    ],
    install_requires=["setuptools"],
    tests_require=["pytest"],
    zip_safe=True,
    maintainer="dev",
    maintainer_email="dev@example.com",
    description="最小可构建示例包",
    license="Apache-2.0",
    entry_points={
        "console_scripts": [
            "hello = py_hello.hello:main",
        ],
    },
)
