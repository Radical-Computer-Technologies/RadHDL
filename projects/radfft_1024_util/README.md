# RADFFT 1024 Utilization

This project builds a self-contained 1024-point RADFFT utilization target. It is
intended for routed resource/timing comparison between BRAM and UltraRAM memory
styles. The default build uses radix-2 and packs 4 complex samples per memory
word so each TDP memory access is wider than one sample.

The default target is `kria_k26`, a Zynq UltraScale+ SOM target with UltraRAM
available. This project is intentionally built out-of-context so the reports
measure the FFT core instead of unconstrained board IO placement. Bitstream
generation belongs in a board-level design with real XDC constraints.

Run BRAM:

```sh
source /home/jvincent/xilinx/Vivado/2023.1/settings64.sh
vivado -mode batch -source projects/radfft_1024_util/scripts/build_radfft_1024_util.tcl \
  -tclargs kria_k26 --memory-style=block --word-samples=4
```

Run UltraRAM:

```sh
vivado -mode batch -source projects/radfft_1024_util/scripts/build_radfft_1024_util.tcl \
  -tclargs kria_k26 --memory-style=ultra --word-samples=4
```

Reports are written under
`projects/build/radfft_1024_util/<board>_radix<N>_<memory>/reports`.
Post-route checkpoints are written under the sibling `artifacts` directory.
