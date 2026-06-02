cmake_minimum_required(VERSION 3.16)

include(pico_sdk_import.cmake OPTIONAL)

project(radila_pico_bridge C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

if (PICO_SDK_PATH)
    pico_sdk_init()
else()
    message(FATAL_ERROR "Set PICO_SDK_PATH to build radila_pico_bridge")
endif()

set(RADILA_PICO_BUS "spi" CACHE STRING "RadILA downstream bus: spi or i2c")
set(RADILA_PICO_ENABLE_TCP OFF CACHE BOOL "Enable optional Pico W TCP listener")

add_executable(radila_pico_bridge
    radila_pico_bridge.c
    ../../common/radila_bridge_protocol.c
)

target_include_directories(radila_pico_bridge PRIVATE
    ../../common
)

target_compile_definitions(radila_pico_bridge PRIVATE
    RADILA_PICO_BUS_${RADILA_PICO_BUS}=1
    RADILA_PICO_ENABLE_TCP=$<BOOL:${RADILA_PICO_ENABLE_TCP}>
)

target_link_libraries(radila_pico_bridge PRIVATE
    pico_stdlib
    hardware_spi
    hardware_i2c
    hardware_uart
)

if (RADILA_PICO_ENABLE_TCP)
    target_link_libraries(radila_pico_bridge PRIVATE
        pico_cyw43_arch_lwip_threadsafe_background
    )
endif()

pico_enable_stdio_usb(radila_pico_bridge 1)
pico_enable_stdio_uart(radila_pico_bridge 0)
pico_add_extra_outputs(radila_pico_bridge)
