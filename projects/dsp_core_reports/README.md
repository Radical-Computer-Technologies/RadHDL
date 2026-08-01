# RADDsp Core Reports

This project routes individual RADDsp cores with representative area-first
generics and writes timing/utilization reports for each core.

Run the default Zynq-7000 report set:

```sh
source /home/jvincent/xilinx/Vivado/2023.1/settings64.sh
vivado -mode batch -nojournal -nolog \
  -source projects/dsp_core_reports/scripts/synth_raddsp_core_reports.tcl
```

Run a specific board target:

```sh
vivado -mode batch -nojournal -nolog \
  -source projects/dsp_core_reports/scripts/synth_raddsp_core_reports.tcl \
  -tclargs zynq_usplus_zu3eg
```

Run a single core:

```sh
vivado -mode batch -nojournal -nolog \
  -source projects/dsp_core_reports/scripts/synth_raddsp_core_reports.tcl \
  -tclargs zynq_7020 --core=raddsp_axis_fir
```

Reports are written under
`projects/build/dsp_core_reports/<board>/<core>/reports`.

The script also writes:

- `projects/build/dsp_core_reports/<board>/summary.csv`
- `projects/build/dsp_core_reports/<board>/SUMMARY.md`

The summary files are updated after each core so a late implementation failure
does not leave a stale report.
