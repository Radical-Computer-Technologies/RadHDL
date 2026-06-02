cmake_minimum_required(VERSION 3.16)

project(radila_linux_bridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(radila_linux_bridge
    radila_linux_bridge.c
    ../common/radila_bridge_protocol.c
)

target_include_directories(radila_linux_bridge PRIVATE
    ../common
)

target_compile_options(radila_linux_bridge PRIVATE -Wall -Wextra -Wpedantic)
