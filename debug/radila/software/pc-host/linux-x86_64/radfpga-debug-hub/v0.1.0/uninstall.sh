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
Usage: ./uninstall.sh [--prefix PATH] [--bindir PATH]
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

rm -f "${bindir}/radfpga_debug_hub" "${bindir}/radfpga_debug_hubd"
rm -rf "${prefix}"

echo "Removed RadFPGA Debug Hub from ${prefix}"
