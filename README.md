# RadHDL

RadHDL contains reusable HDL IP, board-independent driver source, host-tool source, and bridge firmware for the RadTools ecosystem.

## Contents

- `debug/radila/hdl/radila`: RadILA capture core and RadDebugHub AXI-Lite wrapper.
- `debug/radila/software/drivers`: Linux/PetaLinux driver source for RadILA access.
- `debug/radila/software/pc-host/source`: RadFPGA Debug Hub desktop/daemon source for RadILA.
- `debug/radila/software/bridges`: SPI/I2C-to-serial/TCP bridge sources for MCU and Linux bridge targets.
- `hdl/radhdl_library.tcl`: generated Vivado source manifest for `RadHDL.debug` and `RadHDL.dsp`.
- `dsp/hdl/raddsp`: reusable DSP HDL source and Vivado packaging scripts.
- `dsp/hdl/xci`: generated Xilinx XCI wrappers used by RadBuild projects that need the packaged DSP blocks.

RadTools is responsible for compiled release installers. RadHDL is the source tree those installers should be built from.
