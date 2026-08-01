# FPiGA Audio Hat Shared-Math RadHDL Gowin Experiment

This copied project is an A/B experiment for sharing multiplier resources in
the FPiGA Audio Hat RadHDL port. It uses the same board pinout and constraints
as the baseline project, but folds global pan, five-band EQ, and output gain
into one deterministic TDM scheduler: `raddsp_audio_stereo_shared_pg_eq_tdm`.

## Build

Run from the RadHDL repository root:

```sh
projects/examples/fpiga_audio_hat_shared_math/build_gowin.sh
```

The script creates a Gowin project from RadHDL sources and imports complete
project-local constraints:

- `gowin/fpiga_audio_hat_pi_i2s.cst`
- `gowin/fpiga_audio_hat_timing.sdc`

The local CST mirrors the board pinout and enables `I2S_DOUT_PI` on `H1`, which
the original board CST left commented. The local SDC names the audio `MCLK`
domain and the 100 MHz fabric domain explicitly and marks them asynchronous;
the crossing between those domains is handled by toggle synchronizers and
stable frame buses in the top-level RTL. The `MCLK` constraint uses the PLLA
fractional-divider intent from the original FPiGA clock wrapper:
`ODIV0_SEL=81`, `ODIV0_FRAC_SEL=3`, or `1000 MHz / 81.375 = 12.288786 MHz`.

The board uses `E2` for `CLK_50M`. On the GW5A MBGA121N package that pin has
CPU/SSPI alternate functions, so the generated project sets:

- `set_option -use_sspi_as_gpio 1`
- `set_option -use_cpu_as_gpio 1`

The build also enables the timing-oriented Gowin switches that were useful on
this design:

- `set_option -pipe 1`
- `set_option -retiming 1`
- `set_option -maxfan 64`
- `set_option -place_option 2`
- `set_option -route_option 1`
- `set_option -route_maxfan 16`

## Validated Gowin Build

The RadHDL-native top has been synthesized and placed/routed with Gowin EDA
V1.9.11.03 Education for `GW5A-LV25MG121NC1/I0`.

Generated artifacts:

| Artifact | Path | Size |
| --- | --- | --- |
| Bitstream | `build/gowin/radhdl_fpiga_audio_shared/impl/pnr/radhdl_fpiga_audio_shared.fs` | 6,538,355 bytes |
| Binary | `build/gowin/radhdl_fpiga_audio_shared/impl/pnr/radhdl_fpiga_audio_shared.bin` | 815,474 bytes |
| PnR report | `build/gowin/radhdl_fpiga_audio_shared/impl/pnr/radhdl_fpiga_audio_shared.rpt.txt` | 33,672 bytes |

Timing:

| Clock | Constraint | Actual Fmax | Worst setup slack |
| --- | --- | --- | --- |
| `AUDIO_MCLK` | 12.288786 MHz intended, 12.346 MHz Gowin generated-clock model | 148.024 MHz | clean |
| `FABRIC_100M` | 100.000 MHz | 129.214 MHz | +2.261 ns |

Gowin emits `TA1123` because its generated-clock report models
`u_pll/CLKOUT0` as an 81.000 ns / 12.346 MHz clock, while the explicit SDC uses
the PLLA fractional divider as 81.375 ns / 12.288786 MHz. The original FPiGA
Gowin build shows the same 12.346 MHz generated-clock report for the same
`ODIV0_SEL=81`, `ODIV0_FRAC_SEL=3` settings, so this is a tool timing-model
mismatch around the fractional divider, not a new RadHDL clocking change.

Resource usage:

| Resource | Usage | Utilization |
| --- | --- | --- |
| Logic | 6,592 / 23,040 | 29% |
| LUT | 5,527 | - |
| ALU | 1,065 | - |
| Register | 6,671 / 23,280 | 29% |
| CLS | 6,265 / 11,520 | 55% |
| I/O Port | 18 / 86 | 21% |
| IOLOGIC | 1 / 80 | 2% |
| BSRAM | 12 / 56 | 22% |
| DPB | 12 | - |
| DSP | 9 / 28 | 33% |
| MULTALU27X18 | 9 | - |
| MULT12X12 | 0 | - |
| PLLA | 1 / 6 | 17% |

This run keeps the polyphonic synth host configuration out of the datapath reset
path with `RESET_CONFIG_REGS => false` and stores the 64-word per-voice config
space in two explicit Gowin DPBs. I2C writes use the config-memory write port,
while the synth scheduler reads frequency/control/volume/ADSR through the read
port at the start of each voice. That drops `u_poly_synth` from 2,566 registers
/ 1,688 LUTs in the earlier register-backed design to 1,241 registers / 1,038
LUTs while adding a second polyphonic synth `MULTALU27X18`. The polyphonic synth
phase and envelope updates are split into separate scheduler states, including a
pipelined ADSR select/apply/commit sequence. The four waveform lanes now run
through a fixed tap pipeline that overlaps table reads, interpolation products,
waveform-volume products, and lane accumulation. A registered B-sample tap keeps
the wavetable DPB output out of the interpolation-subtract critical path. The
LFO frequency/pan modulation boundary is registered before the oscillator and
shared output scheduler, and LFO accumulate/finalize are split so clamp logic
does not sit on the summation index path.

The main I2C register path now routes through `radif_reg_interconnect` into two
small `radif_reg_bank` windows plus the direct poly synth config target. Both
bank windows use `PIPELINED_READ => true` so slow I2C readback waits one extra
fabric clock instead of forcing the bridge read address through a large register
mux in one cycle. The RPI and ADC I2S blocks also receive locally staged reset
release signals so their internal reset fanout does not sit directly on the
global board reset route.

The shared pan/EQ/gain scheduler now stores its five-section EQ coefficients in
a banked Gowin DPB pair instead of flip-flop coefficient arrays. Software writes
the inactive bank, then `EQ_CONTROL[8]` requests an atomic active-bank flip when
the scheduler reaches `IDLE`. The banked coefficient fetch adds roughly 50
clocks to the EQ-enabled output path, but drops the shared scheduler from 3,200
registers / 2,467 LUTs to 1,653 registers / 1,466 LUTs. Combined with the split
register fabric and DPB-backed poly config store, total CLS drops from 9,613 /
84% to 6,265 / 55%. The explicit coefficient address mapping also keeps Gowin
from inferring a stray `MULT12X12` address multiplier.

The design passes the 100 MHz constraint with 1.567 ns of setup slack. The
current worst setup path is in the shared EQ scheduler, from
`u_shared_pg_eq/section_idx_1_s1/Q` to `u_shared_pg_eq/section_in_12_s1/D`.
The Raspberry Pi I2S bridge is clocked by the PLL audio `MCLK` domain with
`DEFAULT_BCLK_DIV => 0`, producing `MCLK/2` BCLK for the 96 kHz two-lane Pi
stream when `MCLK` is 12.288786 MHz. The Pi bridge shifts 32-bit slots: the
upper 24 bits are audio and the low byte is a lane marker. FPGA RX accepts
driver markers `0xA0`/`0xA1` and uses them to classify lane 0 versus lane 1,
falling back to alternating lane order only when a marker is missing. FPGA TX
inserts `0xA0` on lane 0 and `0xA1` on lane 1 so the Linux driver can align
captured logical ALSA channels. The codec ADC/DAC bridges remain in the 100 MHz
fabric domain and synchronize the external codec BCLK/LRCK inputs.

Expected scheduler budget at a 100 MHz fabric clock:

| Stage | Estimated clocks | Time |
| --- | ---: | ---: |
| 16-voice poly synth | ~576 | ~5.76 us |
| Shared output stage, EQ disabled | ~10 | ~0.10 us |
| Shared output stage, 5-band stereo EQ enabled | ~238 | ~2.38 us |
| Poly synth plus enabled EQ | ~814 | ~8.14 us |

The ADC interface is included in the placed design:

| Signal | Pin | Direction | Purpose |
| --- | --- | --- | --- |
| `I2S_BCK` | `J1` | Input | Shared I2S bit clock from the codec/Raspberry Pi path. |
| `I2S_LRCK_ADC` | `L1` | Input | Codec ADC left/right clock. |
| `I2S_SDA_ADC` | `L2` | Input | Codec ADC serial sample data into RadHDL. |
| `I2S_BCK_RPI` | `G4` | Output | PLL-MCLK-derived Raspberry Pi I2S bit clock at `MCLK/2`. |
| `I2S_LRCK_RPI` | `H2` | Output | Raspberry Pi 96 kHz I2S left/right clock. |
| `I2S_SDA_IN_RPI` | `H4` | Input | Raspberry Pi serial audio into FPGA. |
| `I2S_DOUT_PI` | `H1` | Output | FPGA synth/audio serial return to Raspberry Pi. |

## RadHDL Replacement Map

The port replaces the board-local control/audio modules with RadHDL-owned
building blocks:

| Board function | RadHDL implementation |
| --- | --- |
| Raspberry Pi 32-bit I2C register control | `radif_i2c_slave_to_reg` |
| Software-visible control/status storage | `radif_reg_interconnect` feeding two small `radif_reg_bank` windows plus the direct poly synth config target |
| Debug I2C register bridge | `radif_i2c_slave_to_reg` at address `0x42` into `RadDebugHub` |
| Raspberry Pi 96 kHz I2S send/receive | `radif_i2s_axis` in the PLL `MCLK` domain using 32-bit Pi slots, low-byte lane markers, and lane-0/lane-1 frame handoff to the 100 MHz fabric domain |
| Codec ADC I2S capture | `radif_i2s_axis` |
| Codec DAC I2S transmit | `radif_i2s_axis` |
| Shared output pan/EQ/gain | `raddsp_audio_stereo_shared_pg_eq_tdm`, two 27x32 product engines using four Gowin `MULTALU27X18` blocks |
| Four-oscillator synth mode | `raddsp_audio_quad_wavetable_oscillator`, four 256-sample 16-bit half-period wavetable pages in one Gowin DPB with sign reconstruction and linear interpolation |
| Four-oscillator pan/mix | `raddsp_audio_quad_osc_pan_mixer`, one TDM shared `MULTALU27X18` |
| Quad LFO modulation | `raddsp_audio_quad_lfo_wavetable`, four assignable LFOs using a 512-sample half-period table across two Gowin DPBs |
| Polyphonic synth mode | `raddsp_audio_poly_synth` with 16 register-controlled voices, explicit two-DPB config storage, a two-multiplier waveform pipeline, and the same half-period wavetable/interpolation model |
| Global stereo balance/pan | Folded into the shared output pipeline |
| Global stereo EQ | Folded into the shared output pipeline as five 32-bit-coefficient biquad sections |
| MCLK/sysclk generation | Gowin `PLLA` primitive in the board top |
| MCLK forwarding | Gowin `ODDR` primitive in the board top |

The codec ADC path is wired into the design. `DSP_CONTROL[1]` selects ADC
monitoring to the DAC path, and `DSP_CONTROL[2]` mixes codec ADC samples with
Raspberry Pi playback before output gain. In synth modes, `DSP_CONTROL[3]`
selects Raspberry Pi lane-0 playback as the codec DAC source instead of direct
FPGA synth output; when clear, the selected synth is sent directly to the codec
DAC. The FPGA-to-Pi return stream sends current synth output on Pi lane 0 with
marker `0xA0` and zeros on lane 1 with marker `0xA1`.

## Software Contract

The main FPGA control path uses `/dev/i2c-1` at address `0x12`. The current
RadHDL-native design exposes 16-bit byte addresses and 32-bit little-endian
register words through `radif_i2c_slave_to_reg`, `radif_reg_interconnect`, and
the selected register/config target.

`RadDebugHub` is exposed separately at I2C address `0x42` through the same
RadIF register bridge protocol.

Key FPGA registers:

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x0000` | `CONTROL` | R/W | Bit 0 holds datapath reset, bit 1 drives `MUTEEN`, bit 8 enables DAC output. |
| `0x0004` | `DSP_CONTROL` | R/W | Bits `[7:0]` select mode: `0x00` Pi playback, `0x01` four-oscillator synth, `0x02` poly synth. Bits `[15:8]` hold routing flags: bit 1 selects ADC monitor, bit 2 mixes ADC with Pi playback, and bit 3 selects Pi lane-0 playback as DAC source during synth modes. Bits `[23:16]` hold packed four-oscillator waveform selectors. |
| `0x0008`-`0x0014` | `FREQ0..FREQ3` | R/W | Four 24-bit wavetable oscillator phase increments. |
| `0x0018`-`0x001c` | `LEFT_GAIN`, `RIGHT_GAIN` | R/W | 24-bit output gain coefficients. Zero maps to unity. |
| `0x0020`-`0x002c` | `OSC0_GAIN..OSC3_GAIN` | R/W | Four-oscillator synth gain coefficients. |
| `0x0030` | `WAVE_CONTROL` | R/W | Loadable wavetable address. Bits `[9:8]` select waveform page 0-3; bits `[7:0]` select the 256-sample positive half-period index. |
| `0x0034` | `OSC_PAN` | R/W | Packed four-oscillator pan controls. Bytes 0-3 control oscillators 0-3. `0x80` is center; unwritten `0x00` is treated as center. |
| `0x0038` | `GLOBAL_PAN` | R/W | Selected-output global stereo balance/pan. Byte 0 uses `0x80` as center; unwritten `0x00` is treated as center. |
| `0x003c` | `WAVE_DATA` | R/W | Write bits `[15:0]` to store one signed half-period wavetable sample at `WAVE_CONTROL[9:0]`. Playback reconstructs the opposite half by sign inversion and linearly interpolates between adjacent samples. |
| `0x0040`-`0x007c` | `POLY_FREQ0..15` | R/W | Sixteen 24-bit poly synth voice phase increments. |
| `0x0080`-`0x00bc` | `POLY_CTRL0..15` | R/W | Sixteen poly synth control words. Bit 0 is gate and bit 1 enables the voice. |
| `0x00c0`-`0x00fc` | `POLY_VOLUME0..15` | R/W | Four packed 8-bit waveform volumes per voice: ramp, square, triangle, inverted ramp. |
| `0x0100`-`0x013c` | `POLY_ADSR0..15` | R/W | Packed ADSR bytes per voice: attack, decay, sustain, release. |
| `0x0140` | `LFO_CONTROL` | R/W | Bits `[3:0]` enable LFOs 0-3. Bits `[15:8]` hold packed 2-bit waveform selectors. Bits `[23:16]` hold packed 2-bit targets: `00` off, `01` oscillator frequency modulation, `10` global pan modulation. |
| `0x0144`-`0x0150` | `LFO_FREQ0..3` | R/W | Four 24-bit LFO phase increments. |
| `0x0154`-`0x0160` | `LFO_DEPTH0..3` | R/W | Four 18-bit LFO depth coefficients. Zero disables amplitude contribution. |
| `0x0164` | `LFO_WAVE_CONTROL` | R/W | Loadable LFO table address. Bits `[10:9]` select waveform page 0-3; bits `[8:0]` select the 512-sample positive half-period index. |
| `0x0168` | `LFO_WAVE_DATA` | R/W | Write bits `[15:0]` to store one signed LFO half-period table sample at `LFO_WAVE_CONTROL[10:0]`. |
| `0x016c` | `EQ_CONTROL` | R/W | Bit 0 enables the global stereo EQ. Writing bit 8 requests a shadow-to-active coefficient commit. |
| `0x0170` | `EQ_COEFF_ADDR` | R/W | EQ coefficient index for indirect writes. Five sections use 25 indices: section `n` uses `n*5+0..4` for `b0`, `b1`, `b2`, `a1`, `a2`. |
| `0x0174` | `EQ_COEFF_DATA` | W | Write a signed Q3.28 coefficient to the shadow coefficient selected by `EQ_COEFF_ADDR`. After all coefficients are written, set `EQ_CONTROL[8]` to commit. |
| `0x0178` | `EQ_SMOOTH` | R/W | Reserved for future coefficient slew/crossfade control. Current hardware writes coefficients into the inactive DPB bank and flips the active bank on commit. |
| `0x0180` | `RO_ID` | R | ASCII `FPGA`. |
| `0x0184` | `RO_VERSION` | R | Design version `0x00000202`. |
| `0x0188` | `RO_STATUS` | R | PLL, reset, DAC, EQ, LFO, wavetable, and poly synth status bits. |
| `0x018c` | `RO_WAVE_COUNT` | R | Wave-control write count mirror. |
| `0x0190` | `RO_DEBUG_STATUS` | R | RadDebugHub IRQ and register bridge error bits. |
| `0x0194` | `RO_RPI_SAMPLE` | R | Lower 32 bits of the last captured Raspberry Pi lane-0 I2S frame. |
| `0x0198` | `RO_ADC_SAMPLE` | R | Lower 32 bits of the last captured codec ADC I2S frame. |

## Scope

This project is the board-level RadHDL port. The historical FPiGA HDL remains
in the FPiGA Audio Hat repository as source/reference material, but this
example build does not instantiate the board-local HDL modules.
