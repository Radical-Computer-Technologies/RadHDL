# RadHDL Core Synthesis Reports

This directory stores measured synthesis summaries for real RadHDL cores. Reports
are generated with RadBuild and are intended for datasheet fields such as LUTs,
flip-flops, BRAM, DSPs, and post-synthesis timing slack.

Protocol record smoke tops and documentation-only helpers are intentionally not
included. Add modules here only when they represent a synthesizable library core.

Regenerate the current matrix from the RadHDL repository root:

```sh
python3 projects/synth_reports/run_core_synth_reports.py --jobs 2 --skip-existing
```

Set `RADBUILD_CLI` to use a different RadBuild entrypoint:

```sh
RADBUILD_CLI=/path/to/radbuild.py python3 projects/synth_reports/run_core_synth_reports.py
```

The current matrix targets representative 7-series, Zynq-7000, and
UltraScale+ parts/speed grades:

- `xc7z020clg400-1`, `xc7z020clg400-2`, `xc7z020clg400-3`
- `xczu3eg-sfvc784-1-e`, `xczu3eg-sfvc784-2-e`
- `xc7a35tcsg324-1`, `xc7a35tcsg324-2`

The checked summaries represent the completed portion of the matrix. Interrupted
or failed runs should not be checked in unless their status and logs are useful
for an explicit issue.
