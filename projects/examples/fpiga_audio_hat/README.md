# FPiGA Audio Hat Gowin Port

This project tracks the RadHDL/RadBuild port of the FPiGA Audio Hat board
design. The board source of truth remains the FPiGA Audio Hat repository; this
example records how RadHDL consumes that platform and what RadBuild needs to
drive Gowin EDA reproducibly.

## Source Repositories

- Board source: `/media/jvincent/Kingspec512/repos/FPiGA-Audio-Hat`
- Aggregate platform repo: `/media/jvincent/Kingspec512/repos/FPiGA`
- Gowin install used for validation: `/home/jvincent/gowin`

The port intentionally preserves the FPiGA board constraint file:

- `hw_rev1_0/source/hdl/i2c_25k.cst`
- `hw_rev1_0/source/hdl/clks.sdc`

The successful headless Gowin build depends on the board's use of `E2` as
`CLK_50M`. In the GW5A MBGA121N package this pin has `CPU/SSPI` alternate
functions, so the generated project must set:

- `set_option -use_sspi_as_gpio 1`
- `set_option -use_cpu_as_gpio 1`

## Validated Build

Run from the FPiGA Audio Hat HDL directory:

```sh
./build_gowin.sh
```

Validated result:

- Tool: Gowin EDA V1.9.11.03 Education
- Part: `GW5A-LV25MG121NC1/I0`
- Device version: `A`
- Bitstream: `hw_rev1_0/source/hdl/build/gowin/fpiga_audio/impl/pnr/fpiga_audio.fs`
- Binary: `hw_rev1_0/source/hdl/build/gowin/fpiga_audio/impl/pnr/fpiga_audio.bin`
- PnR report: `hw_rev1_0/source/hdl/build/gowin/fpiga_audio/impl/pnr/fpiga_audio.rpt.txt`

Current routed utilization:

- Logic: 1454/23040, 7%
- LUT: 1287
- ALU: 167
- Registers: 1521/23280, 7%
- BSRAM: 1/56, 2%
- DSP: 2/28, 8%
- I/O ports: 17/86, 20%
- PLLA: 1/6, 17%

## Clocking

The board uses a 50 MHz input oscillator on `CLK_50M`. The Gowin wrapper
generates:

- `MCLKXCO_OUT`: approximately 12.288786 MHz for the SSM2603 audio codec
- `sysclk_i`: 100 MHz internal DSP/register clock

The software initializes the codec for 48 kHz audio and 24-bit I2S words. The
HDL also references the codec/Raspberry Pi I2S bit clocks and frame clocks from
the board pins.

## Software Contract

The userspace library talks to the FPGA over `/dev/i2c-1` at address `0x12`.
It also configures the SSM2603 codec at address `0x1b`.

Key FPGA registers:

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `ID` | R | FPGA design ID. Current HDL default is `0x01`. |
| `0x01` | `SOFT_RST` | R/W | Board reset control. The software releases reset with `0x01`. |
| `0x02` | `SOFT_EN` | R/W | General enable control. The software enables the design with `0x01`. |
| `0x03` | `CONF0` | R/W | I2S/audio routing mode. `0x01` is 48 kHz pass-through, `0x02` test, `0x03` DSP pass-through. |
| `0x04` | `DSP_MODE` | R/W | DSP mode. `0x00` pass, `0x01` synth, `0x02` wavetable load. |
| `0x05`-`0x07` | `FREQ0` | R/W | Oscillator 0 phase increment, little-endian 24-bit value. |
| `0x08`-`0x0a` | `FREQ1` | R/W | Oscillator 1 phase increment, little-endian 24-bit value. |
| `0x0b`-`0x0d` | `FREQ2` | R/W | Oscillator 2 phase increment, little-endian 24-bit value. |
| `0x0e`-`0x10` | `FREQ3` | R/W | Oscillator 3 phase increment, little-endian 24-bit value. |
| `0x11` | `OSC_WAVE_SELECT` | R/W | Four 2-bit wavetable selectors packed as oscillator 0 through 3. |
| `0x12`-`0x13` | `VOICE_GATE` | R/W | 16-bit voice gate bitmap. |
| `0x14` | `WAVE_STATUS/WAVE_CONTROL` | R/W | Read returns wavetable ready status. Write bit 0 pulses wavetable write enable and bits 2:1 select wavetable. |
| `0x15`-`0x17` | `WAVE_DATA` | R/W | Little-endian 24-bit wavetable sample write data. |
| `0x18` | `DSP_CONTROL` | R/W | DSP control flags. Bit 2 enables the mixer path in current software. |
| `0x19`-`0x1b` | `LEFT_VOLUME` | R/W | Little-endian 24-bit left mixer volume. |
| `0x1c`-`0x1e` | `RIGHT_VOLUME` | R/W | Little-endian 24-bit right mixer volume. |
| `0x1f`-`0x21` | `OSC0_VOLUME` | R/W | Little-endian 24-bit oscillator 0 volume. |
| `0x22`-`0x24` | `OSC1_VOLUME` | R/W | Little-endian 24-bit oscillator 1 volume. |
| `0x25`-`0x27` | `OSC2_VOLUME` | R/W | Little-endian 24-bit oscillator 2 volume. |
| `0x28`-`0x2a` | `OSC3_VOLUME` | R/W | Little-endian 24-bit oscillator 3 volume. |

## Porting Notes

The current board HDL references generated Gowin blocks by entity name:
`fpiga_clks`, `WaveTableBram`, and `AUD_DSP_MULT`. The FPiGA port supplies
source-controlled GW5A wrappers for those entities so the design can be built
from command line without relying on opaque IDE-generated files.

Future RadHDL work should move the reusable parts into vendor-aware RadHDL
interfaces and keep the FPiGA board project as the integration example.
