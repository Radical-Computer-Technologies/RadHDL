#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
vivado_settings="${VIVADO_SETTINGS:-/home/jvincent/xilinx/Vivado/2023.1/settings64.sh}"
mode="${1:-impl}"
shift || true

if [[ -f "${vivado_settings}" ]]; then
  # shellcheck disable=SC1090
  source "${vivado_settings}"
fi

boards=(
  zynq_7020
  zynq_usplus_zu3eg
)

for board in "${boards[@]}"; do
  vivado -mode batch -nojournal -nolog \
    -source "${root_dir}/projects/dsp_timing_smoke/scripts/synth_dsp_axi_smoke.tcl" \
    -tclargs "${board}" "${mode}" "$@"
done
