# raddsp VHDL IP Project

`raddsp` packages the reusable DSP blocks used by the Neuma calibration DSP flow:

- Zadoff-Chu/chirp frame detector
- CORDIC `atan2` phase estimator
- RAM-backed radix-2 FFT batch core

This copy is vendored into `neural_machine_os` so the `neuma-ad936x-3eg-s21-dsp` project can build without depending on a separate external workspace tree.

The current release path is Vivado IP packaging plus generated `.xci` instances. IEEE-1735 encryption is intentionally not used for now because this Vivado install found the AMD public key but is not licensed for encryption.

## RadTools Context

The parent `neural_machine_os` workspace is built with RadTools/RadBuild. Install
and register the workspace with the current RadTools release before running the
full project flow:

```text
https://github.com/Radical-Computer-Technologies/RadTools/tree/main
```

Standalone commands below are for focused raddsp IP verification and packaging.
Use the Vivado settings script for the tool version declared by the consuming
project, currently Vivado `2023.1`.

## Verify Internal RTL

```bash
source <vivado-2023.1-settings64.sh>
vivado -mode batch -source hdl/raddsp/scripts/build_raddsp_plain.tcl -nojournal -nolog
```

Expected result:

```text
PASS raddsp plaintext library testbenches
```

## Package Vivado IP and Generate XCI

```bash
source <vivado-2023.1-settings64.sh>
vivado -mode batch -source hdl/raddsp/scripts/package_raddsp_ip.tcl -nojournal -nolog
rm -rf hdl/xci hdl/build/xci_project
vivado -mode batch -source hdl/raddsp/scripts/create_raddsp_xci.tcl -nojournal -nolog
```

Generated IP repository:

```text
hdl/iprepo/
```

Generated XCI instances:

```text
hdl/xci/raddsp_cordic_atan2_0/raddsp_cordic_atan2_0.xci
hdl/xci/raddsp_fft_radix2_batch_core_0/raddsp_fft_radix2_batch_core_0.xci
hdl/xci/raddsp_zc_chirp_frame_detector_0/raddsp_zc_chirp_frame_detector_0.xci
```

Default XCI configuration:

- CORDIC: 32-bit input, 32-bit phase output, 24 iterations
- FFT: 32 points, 16-bit input/twiddle, 32-bit output, UltraScale+ defaults
- ZC detector: 1024-frame samples, 512 chirp samples, 16-bit IQ, 40-bit accumulator

## Consume From Neuma DSP

The Neuma DSP package scripts look for this sibling project by default:

```text
../raddsp-vhdl/hdl/iprepo
../raddsp-vhdl/hdl/xci
```

Override paths if needed:

```bash
export RADDSP_IP_REPO_DIR=/path/to/raddsp-vhdl/hdl/iprepo
export RADDSP_XCI_DIR=/path/to/raddsp-vhdl/hdl/xci
```

Then run from the Neuma DSP project:

```bash
source <vivado-2023.1-settings64.sh>
vivado -mode batch -source hdl/neuema_dsp/synth_neuma_dsp_ooc.tcl -nojournal -nolog
vivado -mode batch -source hdl/neuema_dsp/package_neuma_dsp_ip.tcl -nojournal -nolog
```

## IP Protection Caveat

`.xci` packaging is not encryption and should not be represented as source hiding. It packages the cores as Vivado IP artifacts and keeps Neuma integration from directly referencing the original `hdl/raddsp/src` library files. Generated XCI output directories still contain generated implementation VHDL and copied IP source files. For stronger customer-release protection later, use an IEEE-1735 encryption-capable Vivado license or a netlist/checkpoint-only delivery flow.
