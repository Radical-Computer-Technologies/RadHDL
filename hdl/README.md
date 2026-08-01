# RadHDL Library Include

`radhdl_library.tcl` is the generated source manifest for projects that want to consume RadHDL without copying HDL into the project tree. The public logical library is `radhdl`; older `raddsp`, `radif`, and `radila` library names remain compatibility paths for existing projects.

Refresh it after adding or moving reusable HDL:

```sh
python3 scripts/generate_radhdl_library.py
```

VHDL usage:

```vhdl
library radhdl;
use radhdl.dsp.all;
use radhdl.interfaces.all;
use radhdl.debug.all;

-- Narrower packages are available when a design wants a smaller import surface:
-- use radhdl.dsp_transform.all;
-- use radhdl.dsp_matrix.all;
-- use radhdl.dsp_filter.all;
-- use radhdl.dsp_detection.all;
-- use radhdl.interfaces_axi.all;
-- use radhdl.interfaces_i2c.all;
-- use radhdl.interfaces_regbank.all;
-- use radhdl.interfaces_smi.all;
-- use radhdl.interfaces_spi.all;
```

Vivado usage:

```tcl
source /path/to/RadHDL/hdl/radhdl_library.tcl

set files [::RadHDL::require_files radhdl.all]
add_files -norecurse $files
set_property library radhdl [get_files $files]

# Compatibility paths are still available:
# add_files -norecurse [::RadHDL::require_files debug.radila]
# add_files -norecurse [::RadHDL::require_files dsp.raw]

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

## Primitive Boundary

New code should instantiate the public RadHDL wrappers instead of directly instantiating vendor primitives:

- `radhdl_ram` for block/distributed/UltraRAM-style memory selection.
- `radhdl_fifo`, `radhdl_fifo_sync`, and `radhdl_fifo_async` for FIFO selection.
- `rad_cdc_*` primitives from `radcdc.vhd` for CDC-safe portable logic.

Vendor-specific primitive names should remain below these boundaries. Xilinx wrappers bind to XPM, ECP5 wrappers bind to explicit Lattice primitive wrappers where hardware is targeted, and Gowin wrappers bind to Gowin EDA primitive/IP wrappers where available.

For release checks, use `scripts/radhdl_sim_matrix.py` from the repository root. GHDL is the default portable simulator; Vivado/xsim remains the authoritative simulator for Xilinx XPM behavior because the XPM implementation bodies are SystemVerilog.
