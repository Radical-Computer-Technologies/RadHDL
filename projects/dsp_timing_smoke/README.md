# DSP AXI Timing Smoke

This project synthesizes a small SoC-facing design that exercises RADIF AXI4-Lite
control, a RADIF AXI4/AXIS DMA path, generated RADFpga address maps, and
representative RADDsp AXI4-Stream blocks in one timing boundary.

The top-level AXI4-Lite slave is intended to connect to:

- Zynq-7000 `M_AXI_GP0`
- Zynq UltraScale+ `M_AXI_HPM*_FPD` or `M_AXI_HPM*_LPD`

The AXI4/AXIS DMA datapath is width-generic. Board defaults are 64-bit for the
Zynq-7000 target and 128-bit for the Zynq UltraScale+ target. Override with
`--dma-width=32`, `--dma-width=64`, or `--dma-width=128` when running sweeps.

Run synthesis for the default Zynq-7000 target:

```sh
source /home/jvincent/xilinx/Vivado/2023.1/settings64.sh
vivado -mode batch -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl
```

Run a specific board target:

```sh
vivado -mode batch -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl -tclargs zynq_usplus_zu3eg
```

Run full implementation for the minimum-area DSP profile:

```sh
vivado -mode batch -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl \
  -tclargs zynq_7020 --fir-lanes=1 --biquad-lanes=1 impl
```

Run full implementation for the current higher-throughput DSP profile:

```sh
vivado -mode batch -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl \
  -tclargs zynq_usplus_zu3eg --dma-width=128 --fir-lanes=2 --biquad-lanes=5 impl
```

Reports are written under
`projects/build/dsp_timing_smoke/<board>_dma<W>_fir<N>_biquad<N>/reports`.
Generated maps and future board-wrapper artifacts are written under
`projects/build/dsp_timing_smoke/<board>_dma<W>_fir<N>_biquad<N>/artifacts`.
Each build also emits `BUILD_SUMMARY.md` in the variant build directory.

Run both known-good board regression targets:

```sh
projects/scripts/run_board_regressions.sh impl
```

The timing regression is built out-of-context because AXI/AXIS are integration
boundaries, not package pins. A package bitstream should be generated from a
board wrapper or block design that connects these ports into PS/PL fabric.

Requesting bitstream mode documents that intent but skips `write_bitstream`
until such a wrapper exists:

```sh
vivado -mode batch -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl \
  -tclargs zynq_7020 bitstream
```

See `TIMING.md` for current routed timing status and the DSP lane tradeoffs.

The project address map source is
`address_map/dsp_axi_smoke.map.json`. The synthesis script regenerates:

- `generated/dsp_axi_smoke.radlib.json`: RADLib/RADFpga-readable map
- `generated/dsp_axi_smoke.addresses.txt`: human review map
