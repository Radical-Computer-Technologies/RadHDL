# RadILA / RadDebugHub HDL

This folder contains the current RadILA debug capture HDL and RADIF register-target debug hub.

## Files

- `radila_core.vhd`: `RadILA` capture core.
- `raddebughub.vhd`: `RadDebugHub` RADIF register interface and command bridge.
- `register_maps/RadDebugHub.map.json`: software-visible register map for host tooling and generated datasheets.
- `package_radila_ip.tcl`: Vivado IP packaging helper.
- `testbenches/tb_radila_core.vhd`: focused simulation for RADIF register command flow and capture readback.

## Current Design Notes

- Capture RAM is true dual-port in the Xilinx branch through XPM memory.
- `VENDOR_TAG` and `PRODUCT_SERIES_TAG` generics select vendor/family implementation paths.
- The hub-to-core command path is narrow and parameterized with `CMD_LANES`.
- `RadILA` is the single capture engine. `RadDebugHub` wraps it with the shared RADIF register interface.
- AXI-Lite, SPI, I2C, and SMI access should be provided by RADIF bridge modules connected to the same register pins.

## Simulation

The focused testbench exercises register reads, writes, capture arming, trigger completion, capture-buffer readback, and clear behavior.
