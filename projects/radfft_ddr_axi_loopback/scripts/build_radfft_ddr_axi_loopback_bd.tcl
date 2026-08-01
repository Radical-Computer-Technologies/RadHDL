set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set radhdl_root [file normalize [file join $project_dir .. ..]]

set board_name "zynq_usplus_zu3eg"
set impl 1
set write_bitstream 0
set fft_points 1024
set fft_memory_style "block"
set max_multiplier_lanes 64
set axi_addr_width 40
foreach arg $argv {
    if {[regexp {^(--)?fft[-_]points=([0-9]+)$} $arg -> _ value]} {
        set fft_points $value
    } elseif {[regexp {^(--)?memory[-_]style=(block|ultra)$} $arg -> _ value]} {
        set fft_memory_style $value
    } elseif {[regexp {^(--)?max[-_]multiplier[-_]lanes=(16|32|64|128)$} $arg -> _ value]} {
        set max_multiplier_lanes $value
    } elseif {[regexp {^(--)?axi[-_]addr[-_]width=([0-9]+)$} $arg -> _ value]} {
        set axi_addr_width $value
    } elseif {$arg eq "--synth-only"} {
        set impl 0
    } elseif {$arg eq "--impl"} {
        set impl 1
    } elseif {$arg eq "--bitstream"} {
        set write_bitstream 1
        set impl 1
    } elseif {$arg eq "--no-bitstream"} {
        set write_bitstream 0
    } elseif {[string match -* $arg]} {
        continue
    } elseif {$arg ne ""} {
        set board_name $arg
    }
}

set board_file [file join $radhdl_root projects boards "${board_name}.tcl"]
if {![file exists $board_file]} {
    error "Unknown RadHDL board target '$board_name'. Expected $board_file"
}
source $board_file
source [file join $radhdl_root hdl radhdl_library.tcl]

if {$fft_memory_style eq "ultra"} {
    if {![info exists RADHDL_HAS_URAM] || !$RADHDL_HAS_URAM} {
        error "Board target '$board_name' is not marked as URAM-capable."
    }
}

set build_variant [format "%s_ps_bd_%s_%spt_%slane" $RADHDL_BOARD_NAME $fft_memory_style $fft_points $max_multiplier_lanes]
set build_root [file join $radhdl_root projects build radfft_ddr_axi_loopback $build_variant]
set report_dir [file join $build_root reports]
set artifact_dir [file join $build_root artifacts]
set bd_name "radfft_ddr_ps_bd"
set twiddle_mem_file [file normalize [file join $radhdl_root dsp hdl raddsp mem "radfft_twiddle_${fft_points}_16_fft.mem"]]
file mkdir $report_dir
file mkdir $artifact_dir
file mkdir [file dirname $twiddle_mem_file]

if {![file exists $twiddle_mem_file]} {
    exec python3 [file join $radhdl_root dsp hdl raddsp scripts generate_radfft_twiddles.py] \
        --points $fft_points \
        --width 16 \
        --output $twiddle_mem_file
}

proc set_cfg_if_present {obj key value} {
    set prop "CONFIG.$key"
    if {[lsearch -exact [list_property $obj] $prop] >= 0} {
        set_property $prop $value $obj
        return 1
    }
    return 0
}

proc set_ps_cfg_if_present {ps key value} {
    if {[lsearch -exact [list_property $ps] $key] >= 0} {
        set_property $key $value $ps
        return 1
    }
    return 0
}

proc first_existing_bd_pin {patterns label} {
    foreach pattern $patterns {
        set pins [get_bd_pins -quiet $pattern]
        if {[llength $pins] > 0} {
            return [lindex $pins 0]
        }
    }
    error "Unable to find $label. Tried: $patterns"
}

proc first_existing_bd_intf_pin {patterns label} {
    foreach pattern $patterns {
        set pins [get_bd_intf_pins -quiet $pattern]
        if {[llength $pins] > 0} {
            return [lindex $pins 0]
        }
    }
    error "Unable to find $label. Tried: $patterns"
}

if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force "radfft_ddr_axi_loopback_${build_variant}" $build_root -part $RADHDL_PART
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY XPM_FIFO} [current_project]

read_vhdl -vhdl2008 [::RadHDL::require_files dsp.raw]
read_vhdl [file join $project_dir src raddsp_axis_radfft_ddr_bd.vhd]
add_files -norecurse $twiddle_mem_file
update_compile_order -fileset sources_1

create_bd_design $bd_name

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps]
set_ps_cfg_if_present $ps CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 100
set_ps_cfg_if_present $ps CONFIG.PSU__PL_CLK0_BUF TRUE
set_ps_cfg_if_present $ps CONFIG.PSU__USE__M_AXI_GP0 1
set_ps_cfg_if_present $ps CONFIG.PSU__USE__S_AXI_GP0 1
set_ps_cfg_if_present $ps CONFIG.PSU__USE__IRQ0 1

set dut [create_bd_cell -type module -reference raddsp_axis_radfft_ddr_bd radfft_ddr_0]
set_cfg_if_present $dut VENDOR "xilinx"
set_cfg_if_present $dut DEVICE_FAMILY $RADHDL_DSP48_FAMILY
set_cfg_if_present $dut G_AXI_ADDR_WIDTH $axi_addr_width
set_cfg_if_present $dut G_AXI_DATA_WIDTH $RADHDL_DMA_DATA_WIDTH
set_cfg_if_present $dut G_AXIS_DATA_WIDTH $RADHDL_DMA_DATA_WIDTH
set_cfg_if_present $dut G_AXI_LITE_ADDR_WIDTH 16
set_cfg_if_present $dut G_FIFO_DEPTH 1024
set_cfg_if_present $dut G_FIFO_FWFT true
set_cfg_if_present $dut G_MAX_BURST_BEATS 64
set_cfg_if_present $dut G_FFT_POINTS $fft_points
set_cfg_if_present $dut G_FFT_RADIX 2
set_cfg_if_present $dut G_FFT_INPUT_WIDTH 32
set_cfg_if_present $dut G_FFT_TWIDDLE_WIDTH 16
set_cfg_if_present $dut G_FFT_OUTPUT_WIDTH 32
set_cfg_if_present $dut G_FFT_SCALE_EACH_STAGE true
set_cfg_if_present $dut G_FFT_MEMORY_STYLE $fft_memory_style
set_cfg_if_present $dut G_FFT_TWIDDLE_INIT_FILE $twiddle_mem_file
set_cfg_if_present $dut G_FFT_INVERSE false
set_cfg_if_present $dut G_MAX_MULTIPLIER_LANES $max_multiplier_lanes
set_cfg_if_present $dut G_DEFAULT_REGION_BYTES 67108864

set ctrl_sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_lite_sc]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $ctrl_sc
set data_sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_ddr_sc]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $data_sc

set rst_sync [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* ps_reset_0]
set_property -dict [list CONFIG.C_EXT_RESET_HIGH 0] $rst_sync
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* irq_concat]
set_property -dict [list CONFIG.NUM_PORTS 1] $irq_concat

set ps_clk [first_existing_bd_pin [list ps/pl_clk0] "PS PL clock"]
set ps_rstn [first_existing_bd_pin [list ps/pl_resetn0] "PS PL reset"]
set ps_clk_hz [get_property CONFIG.FREQ_HZ $ps_clk]
if {$ps_clk_hz eq ""} {
    set ps_clk_hz 99999001
}
connect_bd_net $ps_clk [get_bd_pins $dut/clk] [get_bd_pins $ctrl_sc/aclk] [get_bd_pins $data_sc/aclk] [get_bd_pins $rst_sync/slowest_sync_clk]
connect_bd_net $ps_rstn [get_bd_pins $rst_sync/ext_reset_in]
connect_bd_net [get_bd_pins $rst_sync/peripheral_aresetn] [get_bd_pins $dut/rstn] [get_bd_pins $ctrl_sc/aresetn] [get_bd_pins $data_sc/aresetn]
foreach ps_aclk [get_bd_pins -quiet ps/*aclk] {
    catch {connect_bd_net $ps_clk $ps_aclk}
}

set ps_hpm [first_existing_bd_intf_pin [list \
    ps/M_AXI_HPM0_FPD \
    ps/M_AXI_HPM1_FPD \
    ps/M_AXI_HPM0_LPD \
] "PS AXI master control port"]
set ps_ddr [first_existing_bd_intf_pin [list \
    ps/S_AXI_HPC0_FPD \
    ps/S_AXI_HPC1_FPD \
    ps/S_AXI_HP0_FPD \
    ps/S_AXI_HP1_FPD \
    ps/S_AXI_HP2_FPD \
    ps/S_AXI_HP3_FPD \
] "PS AXI DDR slave port"]

connect_bd_intf_net $ps_hpm [get_bd_intf_pins $ctrl_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $ctrl_sc/M00_AXI] [get_bd_intf_pins $dut/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $dut/M_AXI] [get_bd_intf_pins $data_sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $data_sc/M00_AXI] $ps_ddr

connect_bd_intf_net [get_bd_intf_pins $dut/M_AXIS] [get_bd_intf_pins $dut/S_AXIS]

set ps_irq [get_bd_pins -quiet ps/pl_ps_irq0]
if {[llength $ps_irq] > 0} {
    connect_bd_net [get_bd_pins $dut/irq_o] [get_bd_pins $irq_concat/In0]
    connect_bd_net [get_bd_pins $irq_concat/dout] [lindex $ps_irq 0]
}

foreach clk_pin [list [get_bd_pins $dut/clk] [get_bd_pins $ctrl_sc/aclk] [get_bd_pins $data_sc/aclk]] {
    catch {set_property CONFIG.FREQ_HZ $ps_clk_hz $clk_pin}
}
foreach intf_pin [list \
    [get_bd_intf_pins $dut/S_AXI] \
    [get_bd_intf_pins $dut/M_AXI] \
    [get_bd_intf_pins $dut/S_AXIS] \
    [get_bd_intf_pins $dut/M_AXIS] \
    [get_bd_intf_pins $ctrl_sc/S00_AXI] \
    [get_bd_intf_pins $ctrl_sc/M00_AXI] \
    [get_bd_intf_pins $data_sc/S00_AXI] \
    [get_bd_intf_pins $data_sc/M00_AXI] \
] {
    catch {set_property CONFIG.FREQ_HZ $ps_clk_hz $intf_pin}
}

assign_bd_address
validate_bd_design
save_bd_design

set bd_file [get_files -quiet "$bd_name.bd"]
generate_target all $bd_file
make_wrapper -files $bd_file -top -import
update_compile_order -fileset sources_1
set_property top "${bd_name}_wrapper" [current_fileset]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed with status: $synth_status"
}
open_run synth_1 -name synth_1
check_timing -file [file join $report_dir post_synth_check_timing.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing_summary.rpt]
report_utilization -hierarchical -file [file join $report_dir post_synth_utilization.rpt]
if {[llength [info commands report_dsp_utilization]] > 0} {
    report_dsp_utilization -file [file join $report_dir post_synth_dsp_utilization.rpt]
}

if {$impl} {
    if {$write_bitstream} {
        launch_runs impl_1 -to_step write_bitstream -jobs 4
    } else {
        launch_runs impl_1 -to_step route_design -jobs 4
    }
    wait_on_run impl_1
    set impl_status [get_property STATUS [get_runs impl_1]]
    if {![string match "*Complete*" $impl_status]} {
        error "impl_1 failed with status: $impl_status"
    }
    open_run impl_1 -name impl_1
    report_timing_summary -file [file join $report_dir post_route_timing_summary.rpt]
    report_route_status -file [file join $report_dir post_route_status.rpt]
    report_utilization -hierarchical -file [file join $report_dir post_route_utilization.rpt]
    if {[llength [info commands report_dsp_utilization]] > 0} {
        report_dsp_utilization -file [file join $report_dir post_route_dsp_utilization.rpt]
    }
    write_checkpoint -force [file join $artifact_dir radfft_ddr_axi_loopback_post_route.dcp]
} else {
    write_checkpoint -force [file join $artifact_dir radfft_ddr_axi_loopback_post_synth.dcp]
}

set summary_path [file join $build_root BUILD_SUMMARY.md]
set fh [open $summary_path w]
puts $fh "# RADFFT DDR AXI Loopback PS Block Design"
puts $fh ""
puts $fh "Board: `$RADHDL_BOARD_DISPLAY_NAME` (`$RADHDL_PART`)"
puts $fh ""
puts $fh "PS clock: `100 MHz pl_clk0`"
puts $fh ""
puts $fh "PS control master: `$ps_hpm`"
puts $fh ""
puts $fh "PS DDR slave port: `$ps_ddr`"
puts $fh ""
puts $fh "AXI data width: `$RADHDL_DMA_DATA_WIDTH`"
puts $fh ""
puts $fh "AXI address width: `$axi_addr_width`"
puts $fh ""
puts $fh "FFT points: `$fft_points`"
puts $fh ""
puts $fh "FFT memory style: `$fft_memory_style`"
puts $fh ""
puts $fh "Max multiplier lanes: `$max_multiplier_lanes`"
puts $fh ""
puts $fh "Implementation run: `$impl`"
puts $fh ""
puts $fh "Bitstream written: `$write_bitstream`"
puts $fh ""
puts $fh "Reports: `reports/`"
puts $fh ""
puts $fh "Artifacts: `artifacts/`"
close $fh

puts "PASS radfft_ddr_axi_loopback PS BD setup"
puts "Board: $RADHDL_BOARD_DISPLAY_NAME ($RADHDL_PART)"
puts "PS clock: 100 MHz"
puts "Control master: $ps_hpm"
puts "DDR slave port: $ps_ddr"
puts "Reports: $report_dir"
puts "Artifacts: $artifact_dir"
