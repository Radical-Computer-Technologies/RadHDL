# RadHDL Core Synthesis Reports

This directory stores measured synthesis summaries for real RadHDL cores. Reports
are generated with RadBuild and are intended for datasheet fields such as LUTs,
flip-flops, BRAM, DSPs, and post-synthesis timing slack.

Protocol record smoke tops and documentation-only helpers are intentionally not
included. Add modules here only when they represent a synthesizable library core.

Regenerate the current matrix from the RadHDL repository root:

```sh
python3 projects/synth_reports/run_core_synth_reports.py
```

Set `RADBUILD_CLI` to use a different RadBuild entrypoint:

```sh
RADBUILD_CLI=/path/to/radbuild.py python3 projects/synth_reports/run_core_synth_reports.py
```
