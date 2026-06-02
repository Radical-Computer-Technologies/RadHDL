cmake_minimum_required(VERSION 3.16)

project(RadFPGADebugHub LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC OFF)

find_package(Qt6 QUIET COMPONENTS Widgets Network)
if (Qt6_FOUND)
    set(QT_LIB_PREFIX Qt6)
else()
    find_package(Qt5 REQUIRED COMPONENTS Widgets Network)
    set(QT_LIB_PREFIX Qt5)
endif()

find_package(${QT_LIB_PREFIX} QUIET COMPONENTS SerialPort)

add_executable(radfpga_debug_hub
    main.cpp
)

target_link_libraries(radfpga_debug_hub PRIVATE
    ${QT_LIB_PREFIX}::Widgets
    ${QT_LIB_PREFIX}::Network
)

add_executable(radfpga_debug_hubd
    radfpga_debug_hubd.cpp
)

target_link_libraries(radfpga_debug_hubd PRIVATE
    ${QT_LIB_PREFIX}::Network
)

set_target_properties(radfpga_debug_hub radfpga_debug_hubd PROPERTIES
    BUILD_RPATH "$ORIGIN/../lib"
    INSTALL_RPATH "$ORIGIN/../lib"
)

if (TARGET ${QT_LIB_PREFIX}::SerialPort)
    target_compile_definitions(radfpga_debug_hubd PRIVATE RADFPGA_HAS_SERIALPORT=1)
    target_link_libraries(radfpga_debug_hubd PRIVATE ${QT_LIB_PREFIX}::SerialPort)
endif()
