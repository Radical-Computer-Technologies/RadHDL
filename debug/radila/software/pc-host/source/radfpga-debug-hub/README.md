# RadFPGA Debug Hub Source

This is the RadILA/RadDebugHub desktop viewer and local daemon source.

Build with Qt 5 or Qt 6:

```sh
cmake -S . -B build
cmake --build build
```

Targets:

- `radfpga_debug_hub`: Qt waveform/debug viewer for RadILA captures.
- `radfpga_debug_hubd`: local daemon for RadILA transport access and RadBuild integration.

Compiled release installers are packaged by RadTools. This source tree should use RadILA/RadDebugHub executable and alias names.
