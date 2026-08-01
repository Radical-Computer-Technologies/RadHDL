# DSP AXI Timing Smoke Results

Post-route timing is the source of truth for this project. The smoke design now
supports configurable FIR and biquad DSP lane counts so area and throughput can
be evaluated without editing HDL.

## Routed Profiles

| Target | Clock | FIR lanes | Biquad lanes | LUTs | FFs | RAMB18 | DSPs | Setup WNS | Hold WHS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `zynq_7020` | 100 MHz | 1 | 1 | 1587 | 2687 | 1 | 9 DSP48E1 | 1.847 ns | 0.071 ns |
| `zynq_7020` | 100 MHz | 2 | 5 | 1686 | 2809 | 1 | 14 DSP48E1 | 0.413 ns | 0.050 ns |
| `zynq_usplus_zu3eg` | 150 MHz | 1 | 1 | 1571 | 2688 | 1 | 9 DSP48E2 | 3.119 ns | 0.034 ns |

The `1/1` profile is the minimum-DSP profile for this smoke design while keeping
all currently instantiated Xilinx DSP arithmetic on explicit DSP48 primitives:

- gain: 1 DSP
- one-pole lowpass: 1 DSP
- FIR: 1 DSP
- biquad: 1 DSP
- IQ magnitude squared: 2 DSPs
- frame stats: 1 DSP
- matrix elementwise multiply: 1 DSP
- matrix dot: 1 DSP

## Recommendation

Use `--fir-lanes=1 --biquad-lanes=1` as the default area profile. It saves five
DSP48 slices versus the current higher-throughput profile and still routes with
comfortable slack on both tested Zynq families.

Use `--fir-lanes=2 --biquad-lanes=5` only when the surrounding stream path can
actually consume the higher FIR/biquad throughput. It is not needed for timing
closure in this smoke design.

## Commands

Minimum-area Zynq-7000 route:

```sh
source /home/jvincent/xilinx/Vivado/2023.1/settings64.sh
vivado -mode batch -nojournal -nolog \
  -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl \
  -tclargs zynq_7020 --fir-lanes=1 --biquad-lanes=1 impl
```

Higher-throughput Zynq-7000 route:

```sh
vivado -mode batch -nojournal -nolog \
  -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl \
  -tclargs zynq_7020 --fir-lanes=2 --biquad-lanes=5 impl
```

Minimum-area Zynq UltraScale+ route:

```sh
vivado -mode batch -nojournal -nolog \
  -source projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl \
  -tclargs zynq_usplus_zu3eg --fir-lanes=1 --biquad-lanes=1 impl
```
