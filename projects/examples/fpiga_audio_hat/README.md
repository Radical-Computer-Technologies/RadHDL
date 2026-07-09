# FPiGA Audio Hat RadHDL Gowin Port

This project is the RadHDL-native port of the FPiGA Audio Hat board design. It
uses the board pinout and constraints from the FPiGA Audio Hat repository, but
the synthesized top is `radhdl_fpiga_audio_top` and its hierarchy is built from
RADIF/RADDSP modules plus Gowin clock/output primitives.

## Build

Run from the RadHDL repository root:

```sh
projects/examples/fpiga_audio_hat/build_gowin.sh
```

The script creates a Gowin project from RadHDL sources and imports:

- `/media/jvincent/Kingspec512/repos/FPiGA-Audio-Hat/hw_rev1_0/source/hdl/i2c_25k.cst`
- `/media/jvincent/Kingspec512/repos/FPiGA-Audio-Hat/hw_rev1_0/source/hdl/clks.sdc`

The board uses `E2` for `CLK_50M`. On the GW5A MBGA121N package that pin has
CPU/SSPI alternate functions, so the generated project sets:

- `set_option -use_sspi_as_gpio 1`
- `set_option -use_cpu_as_gpio 1`

## Validated Gowin Build

The RadHDL-native top has been synthesized and placed/routed with Gowin EDA
V1.9.11.03 Education for `GW5A-LV25MG121NC1/I0`.

Generated artifacts:

| Artifact | Path | Size |
| --- | --- | --- |
| Bitstream | `build/gowin/radhdl_fpiga_audio/impl/pnr/radhdl_fpiga_audio.fs` | 5,948,235 bytes |
| Binary | `build/gowin/radhdl_fpiga_audio/impl/pnr/radhdl_fpiga_audio.bin` | 742,063 bytes |
| PnR report | `build/gowin/radhdl_fpiga_audio/impl/pnr/radhdl_fpiga_audio.rpt.txt` | 32,811 bytes |

Resource usage:

| Resource | Usage | Utilization |
| --- | --- | --- |
| Logic | 1,244 / 23,040 | 6% |
| LUT | 1,035 | - |
| ALU | 209 | - |
| Register | 990 / 23,280 | 5% |
| CLS | 1,078 / 11,520 | 10% |
| I/O Port | 17 / 86 | 20% |
| IOLOGIC | 1 / 80 | 2% |
| DSP | 6 / 28 | 22% |
| PLLA | 1 / 6 | 17% |

The ADC interface is included in the placed design:

| Signal | Pin | Direction | Purpose |
| --- | --- | --- | --- |
| `I2S_BCK` | `J1` | Input | Shared I2S bit clock from the codec/Raspberry Pi path. |
| `I2S_LRCK_ADC` | `L1` | Input | Codec ADC left/right clock. |
| `I2S_SDA_ADC` | `L2` | Input | Codec ADC serial sample data into RadHDL. |

## RadHDL Replacement Map

The port replaces the board-local control/audio modules with RadHDL-owned
building blocks:

| Board function | RadHDL implementation |
| --- | --- |
| Raspberry Pi byte-register I2C control | `radif_i2c_byte_slave` |
| Software-visible byte register map | `radhdl_fpiga_audio_top` register process |
| Raspberry Pi I2S playback capture | `radif_i2s_axis` |
| Codec ADC I2S capture | `radif_i2s_axis` |
| Codec DAC I2S transmit | `radif_i2s_axis` |
| Output gain | `raddsp_audio_stereo_gain` |
| Synth mode | RadHDL-native phase accumulator in the board top |
| MCLK/sysclk generation | Gowin `PLLA` primitive in the board top |
| MCLK forwarding | Gowin `ODDR` primitive in the board top |

The codec ADC path is wired into the design. `DSP_CONTROL[1]` selects ADC
monitoring to the DAC path, and `DSP_CONTROL[2]` mixes codec ADC samples with
Raspberry Pi playback before output gain.

## Software Contract

The existing userspace library talks to the FPGA over `/dev/i2c-1` at address
`0x12`. The RadHDL top preserves the byte register transaction style used by
that software: write one register address byte followed by data bytes, or write
one register address byte and then read back sequential bytes.

Key FPGA registers:

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `ID` | R | FPGA design ID. The RadHDL-native top returns `0x01`. |
| `0x01` | `SOFT_RST` | R/W | Bit 0 releases the system datapath after PLL lock. |
| `0x02` | `SOFT_EN` | R/W | Bit 0 drives board mute-enable. |
| `0x03` | `CONF0` | R/W | Nonzero values enable DAC stream output. |
| `0x04` | `DSP_MODE` | R/W | `0x00` passes Pi playback, `0x01` selects synth. |
| `0x05`-`0x10` | `FREQ0..FREQ3` | R/W | Four 24-bit oscillator phase increments. |
| `0x11` | `OSC_WAVE_SELECT` | R/W | Four packed 2-bit waveform selectors. |
| `0x14` | `WAVE_STATUS/WAVE_CONTROL` | R/W | Read returns ready; writes preserve load sequencing. |
| `0x18` | `DSP_CONTROL` | R/W | Bit 1 selects ADC monitor; bit 2 mixes ADC with Pi playback. |
| `0x19`-`0x1e` | `LEFT_VOLUME`, `RIGHT_VOLUME` | R/W | 24-bit output gain coefficients. Zero maps to unity. |
| `0x1f`-`0x2a` | `OSC0_VOLUME..OSC3_VOLUME` | R/W | 24-bit oscillator gain coefficients. |

## Scope

This project is the board-level RadHDL port. The historical FPiGA HDL remains
in the FPiGA Audio Hat repository as source/reference material, but this
example build does not instantiate the board-local HDL modules.
