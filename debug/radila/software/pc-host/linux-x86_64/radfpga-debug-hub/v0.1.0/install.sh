#!/usr/bin/env bash
set -euo pipefail

prefix="${HOME}/.local/opt/radfpga-debug-hub"
bindir="${HOME}/.local/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      prefix="$2"
      shift 2
      ;;
    --bindir)
      bindir="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./install.sh [--prefix PATH] [--bindir PATH]

Defaults:
  --prefix $HOME/.local/opt/radfpga-debug-hub
  --bindir $HOME/.local/bin

For system install:
  sudo ./install.sh --prefix /opt/radtools/radfpga-debug-hub --bindir /usr/local/bin
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
payload_dir="${script_dir}/payload"

for exe in radfpga_debug_hub radfpga_debug_hubd; do
  if [[ ! -x "${payload_dir}/bin/${exe}" ]]; then
    echo "missing payload executable: ${payload_dir}/bin/${exe}" >&2
    exit 1
  fi
done

if ! ldconfig -p 2>/dev/null | grep -q 'libQt5SerialPort.so.5'; then
  cat >&2 <<'WARN'
warning: libQt5SerialPort.so.5 was not found in ldconfig.
On Ubuntu 22.04 install dependencies with:
  sudo apt-get install -y libqt5widgets5 libqt5network5 libqt5serialport5
WARN
fi

install -d "${prefix}/bin" "${bindir}"
install -m 0755 "${payload_dir}/bin/radfpga_debug_hub" "${prefix}/bin/radfpga_debug_hub"
install -m 0755 "${payload_dir}/bin/radfpga_debug_hubd" "${prefix}/bin/radfpga_debug_hubd"

ln -sfn "${prefix}/bin/radfpga_debug_hub" "${bindir}/radfpga_debug_hub"
ln -sfn "${prefix}/bin/radfpga_debug_hubd" "${bindir}/radfpga_debug_hubd"

cat <<EOF
Installed RadFPGA Debug Hub:
  ${prefix}/bin/radfpga_debug_hub
  ${prefix}/bin/radfpga_debug_hubd

Symlinks:
  ${bindir}/radfpga_debug_hub
  ${bindir}/radfpga_debug_hubd
EOF
