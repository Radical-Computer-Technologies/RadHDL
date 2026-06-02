# RadFPGA Debug Hub Source and Releases

This folder contains RadFPGA Debug Hub source and installable payloads for RadILA/RadDebugHub.

Desktop and daemon source lives under:

```text
source/radfpga-debug-hub/
```

The lightweight Python waveform browser lives at:

```text
source/radila_waveview.py
```

The Linux x86_64 installable payload is under:

```text
linux-x86_64/radfpga-debug-hub/v0.1.0/
```

The current installer payload contains:

- `radfpga_debug_hub`: Qt desktop UI.
- `radfpga_debug_hubd`: local daemon/service endpoint used by the UI.

The daemon supports RadBuild connection settings through `RADBUILD_ROOT`, `RADBUILD_RADCLIENT`, and `RADBUILD_SERVER_CONFIG`.

RadTools may package compiled installers, but RadHDL is the source owner for the RadILA viewer and bridge interfaces.
