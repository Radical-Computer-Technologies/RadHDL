set script_dir [file normalize [file dirname [info script]]]
set hdl_dir [file normalize [file dirname $script_dir]]

if {![info exists radila_part]} {
    if {[info exists ::env(RADBUILD_VIVADO_PART)] && $::env(RADBUILD_VIVADO_PART) ne ""} {
        set radila_part $::env(RADBUILD_VIVADO_PART)
    } else {
        set radila_part xc7a35tcsg324-1
    }
}
if {![info exists radila_ip_repo_dir]} {
    if {[info exists ::env(RADBUILD_IP_REPO_DIR)] && $::env(RADBUILD_IP_REPO_DIR) ne ""} {
        set radila_ip_repo_dir $::env(RADBUILD_IP_REPO_DIR)
    } else {
        set radila_ip_repo_dir [file join $hdl_dir iprepo]
    }
}

set project_dir [file join $script_dir .vivado_ip_packager]
set ip_root_dir [file join $radila_ip_repo_dir radila_1.0]
set bd_tcl_file [file join $script_dir bd bd.tcl]
set automation_tcl_file [file join $script_dir rad_debug_hub_bd.tcl]

proc find_bus_interface_ci {core wanted_name} {
    foreach bus_if [ipx::get_bus_interfaces -of_objects $core] {
        if {[string equal -nocase [get_property name $bus_if] $wanted_name]} {
            return $bus_if
        }
    }
    return ""
}

file mkdir $radila_ip_repo_dir
if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force radila_ip_packager $project_dir -part $radila_part
set_property target_language VHDL [current_project]

set rtl_files [list \
    [file join $script_dir radila_core.vhd] \
    [file join $script_dir raddebughub.vhd] \
]
add_files -norecurse $rtl_files
set_property library work [get_files $rtl_files]
set_property file_type {VHDL 2008} [get_files $rtl_files]
set_property top RadDebugHub [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
    -force \
    -root_dir $ip_root_dir \
    -vendor user.org \
    -library user \
    -taxonomy {/UserIP} \
    -import_files

set core [ipx::current_core]
set_property name raddebughub $core
set_property display_name {RadDebugHub RADIF Capture Core} $core
set_property description {HDL-only RADIF register-target capture buffer with event trigger and BRAM readback} $core
set_property version 1.0 $core
set_property vendor_display_name {RCT} $core
set_property supported_families {zynquplus Production zynq Production} $core

if {[file exists $bd_tcl_file]} {
    file mkdir [file join $ip_root_dir bd]
    file copy -force $bd_tcl_file [file join $ip_root_dir bd bd.tcl]
    set bd_file_group [ipx::get_file_groups xilinx_blockdiagram -of_objects $core]
    if {$bd_file_group eq ""} {
        set bd_file_group [ipx::add_file_group -type xilinx_blockdiagram "" $core]
    }
    set bd_file [ipx::add_file [file join $ip_root_dir bd bd.tcl] $bd_file_group]
    set_property type tclSource $bd_file
}

ipx::infer_bus_interface sample_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface reg_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface sample_rstn xilinx.com:signal:reset_rtl:1.0 $core
ipx::infer_bus_interface reg_rstn xilinx.com:signal:reset_rtl:1.0 $core
foreach rst_name {sample_rstn reg_rstn} {
    set rst_bus [find_bus_interface_ci $core $rst_name]
    if {$rst_bus ne ""} {
        set pol [ipx::get_bus_parameters POLARITY -of_objects $rst_bus]
        if {$pol ne ""} {
            set_property value ACTIVE_LOW $pol
        }
    }
}

foreach port_name {
    sample_i event_i irq_o
    reg_wr_addr reg_rd_addr reg_wr_en reg_rd_en reg_data_in reg_data_out
    reg_wr_rdy reg_rd_rdy reg_wr_valid reg_rd_valid reg_error
} {
    set port [ipx::get_ports $port_name -of_objects $core]
    if {$port ne ""} {
        set_property enablement_dependency {} $port
    }
}

foreach {param_name display_name description} {
    DATA_WIDTH {Register Data Width} {Width of RADIF register data words}
    REG_ADDR_WIDTH {Register Address Width} {Width of RADIF byte addresses}
    SAMPLE_WIDTH {Sample Width} {Total captured sample bus width in bits}
    EVENT_WIDTH {Event Width} {Total trigger/event bus width in bits}
    DEPTH {Capture Depth} {Number of samples stored in the RadILA dual-port capture RAM}
    ADDR_WIDTH {Capture Address Width} {Address width for the RadILA capture RAM}
    CMD_LANES {Command Link Width} {Narrow command link width between RadDebugHub and RadILA}
    VENDOR_TAG {Vendor Tag} {Vendor selector used by generate blocks for vendor-specific primitives}
    PRODUCT_SERIES_TAG {Product Series Tag} {Device-family selector used by generate blocks for primitive choices}
} {
    set user_param [ipx::get_user_parameters $param_name -of_objects $core]
    if {$user_param ne ""} {
        catch {set_property display_name $display_name $user_param}
        catch {set_property description $description $user_param}
    }
}

ipx::check_integrity $core
ipx::save_core $core
if {[file exists $automation_tcl_file]} {
    file mkdir [file join $ip_root_dir tcl]
    file copy -force $automation_tcl_file [file join $ip_root_dir tcl rad_debug_hub_bd.tcl]
}
set_property ip_repo_paths $radila_ip_repo_dir [current_project]
update_ip_catalog
puts "Packaged user.org:user:raddebughub:1.0"
