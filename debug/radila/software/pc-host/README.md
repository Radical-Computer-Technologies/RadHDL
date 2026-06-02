# RadDebug Releases

This folder is for RadDebug release notes, packaging notes, and installer-facing documentation.

Desktop application source should live in a separate tool-source repository. The installable RadFPGA Debug Hub payload is under:

```text
installers/linux-x86_64/radfpga-debug-hub/v0.1.0/
```

The current installer payload contains:

- `radfpga_debug_hub`: Qt desktop UI.
- `radfpga_debug_hubd`: local daemon/service endpoint used by the UI.

The daemon supports RadBuild connection settings through `RADBUILD_ROOT`, `RADBUILD_RADCLIENT`, and `RADBUILD_SERVER_CONFIG`.
