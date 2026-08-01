set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set radhdl_root [file normalize [file join $project_dir .. ..]]

set board_name "zynq_7020"
set run_impl 0
set write_bitstream 0
set fir_dsp_lanes 1
set biquad_dsp_lanes 1
set dma_data_width ""
foreach arg $argv {
    if {[regexp {^(--)?fir[-_]lanes=([0-9]+)$} $arg -> _ value]} {
        set fir_dsp_lanes $value
    } elseif {[regexp {^(--)?biquad[-_]lanes=([0-9]+)$} $arg -> _ value]} {
        set biquad_dsp_lanes $value
    } elseif {[regexp {^(--)?dma[-_]data[-_]width=([0-9]+)$} $arg -> _ value] || [regexp {^(--)?dma[-_]width=([0-9]+)$} $arg -> _ value]} {
        set dma_data_width $value
    } elseif {$arg eq "impl" || $arg eq "--impl"} {
        set run_impl 1
    } elseif {$arg eq "bitstream" || $arg eq "--bitstream"} {
        set run_impl 1
        set write_bitstream 1
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
if {$dma_data_width eq ""} {
    if {[info exists RADHDL_DMA_DATA_WIDTH]} {
        set dma_data_width $RADHDL_DMA_DATA_WIDTH
    } else {
        set dma_data_width 64
    }
}
if {[lsearch -exact {32 64 128} $dma_data_width] < 0} {
    error "Unsupported DMA data width '$dma_data_width'. Expected 32, 64, or 128."
}
source [file join $radhdl_root hdl radhdl_library.tcl]

set map_src [file join $project_dir address_map dsp_axi_smoke.map.json]
set generated_dir [file join $project_dir generated]
file mkdir $generated_dir
set radlib_map_path [file join $generated_dir dsp_axi_smoke.radlib.json]
set text_map_path [file join $generated_dir dsp_axi_smoke.addresses.txt]
exec python3 [file join $radhdl_root projects scripts generate_address_maps.py] \
    $map_src \
    --radlib-json $radlib_map_path \
    --text $text_map_path >@ stdout 2>@ stderr

set build_variant [format "%s_dma%s_fir%s_biquad%s" $RADHDL_BOARD_NAME $dma_data_width $fir_dsp_lanes $biquad_dsp_lanes]
set build_root [file join $radhdl_root projects build dsp_timing_smoke $build_variant]
set report_dir [file join $build_root reports]
set artifact_dir [file join $build_root artifacts]
file mkdir $report_dir
file mkdir $artifact_dir
file copy -force $radlib_map_path [file join $artifact_dir dsp_axi_smoke.radlib.json]
file copy -force $text_map_path [file join $artifact_dir dsp_axi_smoke.addresses.txt]

if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force "dsp_timing_smoke_${RADHDL_BOARD_NAME}" $build_root -part $RADHDL_PART
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]

read_vhdl -vhdl2008 -library raddsp [::RadHDL::require_files dsp.raw]
read_vhdl -vhdl2008 -library radif [::RadHDL::require_files interfaces]
read_vhdl -vhdl2008 [file join $project_dir src radhdl_dsp_axi_smoke_top.vhd]
update_compile_order -fileset sources_1

set top_name radhdl_dsp_axi_smoke_top
set_property top $top_name [current_fileset]

synth_design \
    -top $top_name \
    -part $RADHDL_PART \
    -mode out_of_context \
    -generic VENDOR_TAG=XILINX \
    -generic PRODUCT_SERIES_TAG=$RADHDL_PRODUCT_SERIES_TAG \
    -generic DSP48_FAMILY=$RADHDL_DSP48_FAMILY \
    -generic FIR_DSP_LANES=$fir_dsp_lanes \
    -generic BIQUAD_DSP_LANES=$biquad_dsp_lanes \
    -generic DMA_DATA_WIDTH=$dma_data_width \
    -flatten_hierarchy rebuilt

create_clock -name aclk -period $RADHDL_CLOCK_PERIOD_NS [get_ports aclk]
check_timing -file [file join $report_dir post_synth_check_timing.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing_summary.rpt]
report_utilization -hierarchical -file [file join $report_dir post_synth_utilization.rpt]
if {[llength [info commands report_dsp_utilization]] > 0} {
    report_dsp_utilization -file [file join $report_dir post_synth_dsp_utilization.rpt]
}

if {$run_impl} {
    opt_design
    place_design
    phys_opt_design
    route_design
    report_timing_summary -file [file join $report_dir post_route_timing_summary.rpt]
    report_utilization -hierarchical -file [file join $report_dir post_route_utilization.rpt]
    if {[llength [info commands report_dsp_utilization]] > 0} {
        report_dsp_utilization -file [file join $report_dir post_route_dsp_utilization.rpt]
    }
    write_checkpoint -force [file join $build_root dsp_timing_smoke_post_route.dcp]
    if {$write_bitstream} {
        puts "WARN: bitstream output is skipped for this out-of-context regression target. Add a board wrapper with PS/IO constraints for package bitstreams."
    }
} else {
    write_checkpoint -force [file join $build_root dsp_timing_smoke_post_synth.dcp]
}

set summary_path [file join $build_root BUILD_SUMMARY.md]
set fh [open $summary_path w]
puts $fh "# DSP AXI Smoke Board Build"
puts $fh ""
puts $fh "Board: `$RADHDL_BOARD_DISPLAY_NAME` (`$RADHDL_PART`)"
puts $fh ""
puts $fh "Clock period: `$RADHDL_CLOCK_PERIOD_NS ns`"
puts $fh ""
puts $fh "FIR DSP lanes: `$fir_dsp_lanes`"
puts $fh ""
puts $fh "Biquad DSP lanes: `$biquad_dsp_lanes`"
puts $fh ""
puts $fh "DMA data width: `$dma_data_width`"
puts $fh ""
puts $fh "Implementation: `$run_impl`"
puts $fh ""
puts $fh "Bitstream: `$write_bitstream`"
puts $fh ""
puts $fh "AXI master integration hint: `$RADHDL_AXI_MASTER_HINT`"
puts $fh ""
puts $fh "Reports: `reports/`"
puts $fh ""
puts $fh "Artifacts: `artifacts/`"
close $fh

puts "PASS dsp_timing_smoke $RADHDL_BOARD_DISPLAY_NAME ($RADHDL_PART)"
puts "DSP lane profile: FIR=$fir_dsp_lanes BIQUAD=$biquad_dsp_lanes"
puts "DMA data width: $dma_data_width"
puts "AXI master integration hint: $RADHDL_AXI_MASTER_HINT"
puts "Reports: $report_dir"
puts "Artifacts: $artifact_dir"
