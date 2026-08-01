# RadHDL

RadHDL contains reusable HDL IP, board-independent driver source, host-tool source, and bridge firmware for the RadTools ecosystem.

Current release-prep branch target: `0.2.2-beta.1`.

## Contents

- `debug/radila/hdl/radila`: RadILA capture core and RadDebugHub AXI-Lite wrapper.
- `debug/radila/software/drivers`: Linux/PetaLinux driver source for RadILA access.
- `debug/radila/software/pc-host/source`: RadFPGA Debug Hub desktop/daemon source for RadILA.
- `debug/radila/software/bridges`: SPI/I2C-to-serial/TCP bridge sources for MCU and Linux bridge targets.
- `hdl/radhdl_library.tcl`: generated Vivado source manifest for `RadHDL.debug` and `RadHDL.dsp`.
- `dsp/hdl/raddsp`: reusable DSP HDL source and Vivado packaging scripts.
- `dsp/hdl/xci`: generated Xilinx XCI wrappers used by RadBuild projects that need the packaged DSP blocks.
- `common/hdl/src`: shared protocol and primitive wrappers, including vendor-neutral RAM/FIFO/CDC boundaries.
- `common/hdl/testbenches`: shared primitive equivalence testbenches for GHDL and vendor simulators.
- `scripts/radhdl_sim_matrix.py`: primitive simulation matrix runner for GHDL, Vivado/xsim, and XPM source probing.

RadTools is responsible for compiled release installers. RadHDL is the source tree those installers should be built from.

## Primitive Simulation Matrix

GHDL is the default simulator for portable VHDL primitive tests:

```sh
scripts/radhdl_sim_matrix.py --mode generic-ghdl
```

The Xilinx path compiles the real Vivado XPM VHDL declarations and SystemVerilog bodies from `/home/jvincent/xilinx/Vivado/<version>/data/ip/xpm`, then runs the same RAM/FIFO testbenches with Vivado xsim:

```sh
scripts/radhdl_sim_matrix.py --mode xilinx-xsim --vivado-version 2024.1
```

The XPM Verilator probe records whether a future GHDL/SystemVerilog co-simulation bridge can use a given XPM body directly. When a body cannot be compiled by Verilator, it is marked `xsim-required` rather than replaced with a hand-written behavioral model:

```sh
scripts/radhdl_sim_matrix.py --mode xpm-verilator-probe --vivado-version 2024.1
```

`scripts/radhdl_sim_matrix.py --mode all` runs all available checks and writes an ignored summary under `.radmeta/sim-matrix/summary.json`.
