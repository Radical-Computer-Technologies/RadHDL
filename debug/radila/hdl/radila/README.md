# RadILA / RadDebugHub HDL

This folder contains the current RadILA debug capture HDL and AXI-Lite debug hub wrapper.

## Files

- `radila_core.vhd`: `RadILA` capture core.
- `raddebughub_axi.vhd`: `RadDebugHub` AXI-Lite register interface and command bridge.
- `radila_axi_top.vhd`: compatibility wrapper for existing Vivado IP packaging.
- `package_radila_ip.tcl`: Vivado IP packaging helper.
- `testbenches/tb_radila_core.vhd`: focused simulation for AXI command flow and capture readback.

## Current Design Notes

- Capture RAM is true dual-port in the Xilinx branch through XPM memory.
- `VENDOR_TAG` and `PRODUCT_SERIES_TAG` generics select vendor/family implementation paths.
- The hub-to-core command path is narrow and parameterized with `CMD_LANES`.
- The AXI-side interface remains AXI-Lite compatible for integration with LitePCIe, PetaLinux, or other register bridges.

## Simulation

The source checkout test was run with Vivado 2023.1 `xvhdl`, `xelab`, and `xsim`; the focused testbench completed with `tb_radila_core passed`.
