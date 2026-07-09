#!/usr/bin/env bash
set -euo pipefail

FPIGA_AUDIO_HAT_REPO="${FPIGA_AUDIO_HAT_REPO:-/media/jvincent/Kingspec512/repos/FPiGA-Audio-Hat}"
HDL_DIR="${FPIGA_AUDIO_HAT_REPO}/hw_rev1_0/source/hdl"

if [[ ! -x "${HDL_DIR}/build_gowin.sh" ]]; then
    echo "FPiGA Audio Hat Gowin build script not found: ${HDL_DIR}/build_gowin.sh" >&2
    exit 2
fi

cd "${HDL_DIR}"
exec ./build_gowin.sh
