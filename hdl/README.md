# RadHDL Library Include

`radhdl_library.tcl` is the generated source manifest for projects that want to consume RadHDL without copying HDL into the project tree.

Refresh it after adding or moving reusable HDL:

```sh
python3 scripts/generate_radhdl_library.py
```

Vivado usage:

```tcl
source /path/to/RadHDL/hdl/radhdl_library.tcl

add_files -norecurse [::RadHDL::require_files debug.radila]
add_files -norecurse [::RadHDL::require_files dsp.raw]

# Or consume generated XCI wrappers.
add_files -norecurse [::RadHDL::require_files dsp.xci]
generate_target all [get_ips]
add_files -norecurse [::RadHDL::require_files dsp.xci_vhdl]
```

Optional IP repository paths are available for flows that need packaged IP:

```tcl
set_property ip_repo_paths [::RadHDL::ip_repo_paths dsp] [current_project]
update_ip_catalog
```
