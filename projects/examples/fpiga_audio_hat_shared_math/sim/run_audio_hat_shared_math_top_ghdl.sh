#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$PROJECT_DIR/../../.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/sim/audio_hat_shared_math_top"
WORK_DIR="$BUILD_DIR/ghdl"

PLOT_SECONDS="${RADHDL_AUDIO_PLOT_SECONDS:-0.02}"
PLOT_FRAMES="$(python3 - "$PLOT_SECONDS" <<'PY'
import sys
seconds = float(sys.argv[1])
if seconds <= 0:
    raise SystemExit("RADHDL_AUDIO_PLOT_SECONDS must be positive")
print(max(1, round(48000.0 * seconds)))
PY
)"

CAPTURE_FRAMES="${RADHDL_AUDIO_CAPTURE_FRAMES:-$PLOT_FRAMES}"
if [[ "${RADHDL_AUDIO_FAST_SMOKE:-0}" == "1" && "${RADHDL_AUDIO_CAPTURE_FRAMES:-}" == "" ]]; then
  CAPTURE_FRAMES=12
fi
DEBUG_I2C_SMOKE=false
if [[ "${RADHDL_AUDIO_DEBUG_I2C_SMOKE:-0}" == "1" ]]; then
  DEBUG_I2C_SMOKE=true
fi

WAVE_HZ="${RADHDL_AUDIO_WAVE_HZ:-50}"
WAVE_PERIOD="$(python3 - "$WAVE_HZ" <<'PY'
import sys
freq = float(sys.argv[1])
if freq <= 0:
    raise SystemExit("RADHDL_AUDIO_WAVE_HZ must be positive")
period = max(1, round(48000.0 / freq))
print(period)
PY
)"

mkdir -p "$BUILD_DIR" "$WORK_DIR"
rm -f "$BUILD_DIR"/*.s32le "$BUILD_DIR"/manifest.json
rm -rf "$BUILD_DIR"/plots

if [[ -n "${GHDL:-}" ]]; then
  GHDL_BIN="$GHDL"
elif [[ -x /usr/bin/ghdl ]]; then
  GHDL_BIN=/usr/bin/ghdl
else
  GHDL_BIN=ghdl
fi
GHDL_FLAGS=(--std=08 -frelaxed-rules --workdir="$WORK_DIR" -P"$WORK_DIR")

analyze_gw5a() {
  "$GHDL_BIN" -a "${GHDL_FLAGS[@]}" --work=gw5a "$@"
}

analyze_work() {
  "$GHDL_BIN" -a "${GHDL_FLAGS[@]}" "$@"
}

cd "$REPO_DIR"

analyze_gw5a "$PROJECT_DIR/sim/gowin/gw5a_components_sim.vhd"

analyze_work \
  interfaces/hdl/radif/src/radif_pkg.vhd \
  dsp/hdl/raddsp/src/raddsp_axis_pkg.vhd \
  interfaces/hdl/radif/src/radif_i2c_slave_to_reg.vhd \
  interfaces/hdl/radif/src/radif_reg_interconnect.vhd \
  interfaces/hdl/radif/src/radif_reg_bank.vhd \
  interfaces/hdl/radif/src/radif_i2s_axis.vhd \
  common/hdl/src/radhdl_ram.vhd \
  debug/radila/hdl/radila/radila_gowin_dpb_ram.vhd \
  debug/radila/hdl/radila/radila_core.vhd \
  debug/radila/hdl/radila/raddebughub.vhd \
  dsp/hdl/raddsp/src/raddsp_gowin_multalu27x18_mul.vhd \
  dsp/hdl/raddsp/src/raddsp_gowin_multalu27x32_mul.vhd \
  dsp/hdl/raddsp/src/raddsp_gowin_dpb16.vhd \
  dsp/hdl/raddsp/src/raddsp_audio_dds_oscillator.vhd \
  dsp/hdl/raddsp/src/raddsp_audio_quad_lfo_wavetable.vhd \
  dsp/hdl/raddsp/src/raddsp_audio_quad_wavetable_oscillator.vhd \
  dsp/hdl/raddsp/src/raddsp_audio_quad_osc_pan_mixer.vhd \
  dsp/hdl/raddsp/src/raddsp_audio_poly_synth.vhd \
  dsp/hdl/raddsp/src/raddsp_audio_stereo_shared_pg_eq_tdm.vhd \
  "$PROJECT_DIR/sim/fpiga_audio_hat_tb_pkg.vhd" \
  "$PROJECT_DIR/src/radhdl_fpiga_audio_top.vhd" \
  "$PROJECT_DIR/sim/tb_fpiga_audio_hat_shared_math_top.vhd"

cd "$PROJECT_DIR"
"$GHDL_BIN" -e "${GHDL_FLAGS[@]}" tb_fpiga_audio_hat_shared_math_top
"$GHDL_BIN" -r "${GHDL_FLAGS[@]}" tb_fpiga_audio_hat_shared_math_top \
  -gG_CAPTURE_FRAMES="$CAPTURE_FRAMES" \
  -gG_ADC_RAMP_PERIOD="$WAVE_PERIOD" \
  -gG_ENABLE_DEBUG_I2C_SMOKE="$DEBUG_I2C_SMOKE" \
  --assert-level=error

cat > "$BUILD_DIR/manifest.json" <<JSON
{
  "format": {
    "sample_type": "s32le",
    "channels": 2,
    "layout": "interleaved_left_right",
    "sample_rate_hz": 48000
  },
  "run": {
    "capture_frames": $CAPTURE_FRAMES,
    "plot_seconds": $PLOT_SECONDS,
    "plot_frames": $PLOT_FRAMES,
    "adc_wave_hz": $WAVE_HZ,
    "adc_ramp_period_samples": $WAVE_PERIOD,
    "debug_i2c_smoke": $DEBUG_I2C_SMOKE
  },
  "scenarios": [
    {
      "name": "adc_ramp_input",
      "file": "adc_ramp_input.s32le",
      "description": "Configured stereo ramp stimulus driven into the emulated SSM2603 ADC pins during ADC monitor mode."
    },
    {
      "name": "adc_mix_input",
      "file": "adc_mix_input.s32le",
      "description": "Mixed-scenario ADC stimulus: left ramp and right sine."
    },
    {
      "name": "dac_zero",
      "file": "dac_zero.s32le",
      "description": "DAC output while ADC monitor mode receives zero input."
    },
    {
      "name": "dac_adc_ramp",
      "file": "dac_adc_ramp.s32le",
      "description": "DAC output in ADC monitor mode while ADC receives the stereo ramp stimulus."
    },
    {
      "name": "rpi_loopback",
      "file": "rpi_loopback.s32le",
      "description": "Captured Raspberry Pi-facing I2S loopback output from clean sine/cosine stimulus."
    },
    {
      "name": "dac_four_osc",
      "file": "dac_four_osc.s32le",
      "description": "DAC output from four-oscillator synth mode with a single enabled oscillator at A4."
    },
    {
      "name": "dac_poly_voice",
      "file": "dac_poly_voice.s32le",
      "description": "DAC output from one enabled/gated polyphonic voice at E5."
    },
    {
      "name": "dac_mix",
      "file": "dac_mix.s32le",
      "description": "DAC output from generated tone mix path with stereo pan/gain changes."
    }
  ]
}
JSON

echo "FPiGA audio shared-math top simulation outputs:"
echo "  $BUILD_DIR"
echo "  capture_frames=$CAPTURE_FRAMES plot_seconds=$PLOT_SECONDS adc_wave_hz=$WAVE_HZ adc_ramp_period_samples=$WAVE_PERIOD"

python3 "$PROJECT_DIR/sim/plot_audio_hat_shared_math_outputs.py"
