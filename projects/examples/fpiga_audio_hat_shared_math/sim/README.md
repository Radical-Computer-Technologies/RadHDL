# FPiGA Audio Hat Shared-Math Top Simulation

This simulation exercises `radhdl_fpiga_audio_top` with a 50 MHz clock, a
behavioral Gowin PLL/primitive model set, a lightweight RadIF I2C master BFM,
and codec/RPi I2S BFMs.

Run it from the project or repository checkout. The default run captures 960
frames, which is 0.02 seconds at 48 kHz. That is one full 50 Hz cycle and gives
useful quick-look plots:

```bash
projects/examples/fpiga_audio_hat_shared_math/sim/run_audio_hat_shared_math_top_ghdl.sh
```

For a fast 12-frame logic smoke instead:

```bash
RADHDL_AUDIO_FAST_SMOKE=1 \
  projects/examples/fpiga_audio_hat_shared_math/sim/run_audio_hat_shared_math_top_ghdl.sh
```

For a 75 Hz ADC ramp stimulus instead:

```bash
RADHDL_AUDIO_WAVE_HZ=75 \
  projects/examples/fpiga_audio_hat_shared_math/sim/run_audio_hat_shared_math_top_ghdl.sh
```

You can override the capture length directly with
`RADHDL_AUDIO_CAPTURE_FRAMES=<frames>`. You can also select a plot/capture
window in seconds with `RADHDL_AUDIO_PLOT_SECONDS=<seconds>`; for example,
`RADHDL_AUDIO_PLOT_SECONDS=0.01` captures 480 frames at 48 kHz.

The runner writes raw little-endian signed 32-bit stereo captures to:

```text
projects/examples/fpiga_audio_hat_shared_math/build/sim/audio_hat_shared_math_top/
```

Each `.s32le` file is interleaved `left,right,left,right...` at 48 kHz. The
same directory includes `manifest.json`, which the notebook uses to discover
and explain the available captures.

Quick-look PNGs are generated automatically into:

```text
projects/examples/fpiga_audio_hat_shared_math/build/sim/audio_hat_shared_math_top/plots/
```

The BFMs are intentionally modular: new scenarios should reuse the existing
clocking, I2C register helpers, codec I2S driver/capture, RPi I2S
driver/capture, and binary writer rather than duplicating them.

The codec/DAC scenarios and RPi-facing slave-mode I2S capture are hard
assertions in the smoke.

`RADHDL_AUDIO_DEBUG_I2C_SMOKE=1` enables the optional RadDebugHub I2C readback
smoke through the debug bridge at address `0x42`. It is kept off by default
while live bring-up validates the board-level debug read path.

The focused `tb_raddsp_audio_poly_synth` bench can be compiled into the same
GHDL work directory when debugging the polyphonic synth core directly. It
programs the core config interface, verifies direct config readback, and
asserts that a gated voice produces nonzero samples before the full top-level
I2S path is involved.
