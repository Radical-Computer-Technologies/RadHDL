# RadHDL Simulation

The release simulation flow is intentionally split by authority:

- GHDL runs portable VHDL primitive tests by default.
- Vivado xsim runs Xilinx XPM tests against the real `xpm_VCOMP.vhd` declarations and `xpm_*.sv` bodies from the installed Vivado tree.
- Verilator probes XPM SystemVerilog bodies for future GHDL co-simulation bridge work. Probe failures are reported as `xsim-required`.

Run the current matrix from the repository root:

```sh
scripts/radhdl_sim_matrix.py --mode all --vivado-version 2024.1
```

The runner writes transient logs and `summary.json` under `.radmeta/sim-matrix/`, which is ignored by Git.
