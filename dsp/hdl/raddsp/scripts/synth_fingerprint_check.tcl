set script_dir [file normalize [file dirname [info script]]]
set raddsp_hdl_dir [file normalize [file join $script_dir .. ..]]
set repo_root [file normalize [file join $raddsp_hdl_dir .. ..]]
set src_dir [file join $raddsp_hdl_dir raddsp src]
set build_dir [file join $raddsp_hdl_dir raddsp build fingerprint_synth_check]

if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force fp_synth_check $build_dir -part xck26-sfvc784-2LV-c
set_property target_language VHDL [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

read_vhdl -vhdl2008 -library raddsp [list \
    [file join $src_dir raddsp_axis_pkg.vhd] \
    [file join $src_dir raddsp_axis_fft_fingerprint.vhd] \
    [file join $src_dir raddsp_axis_fingerprint_matcher.vhd] \
]

synth_design -mode out_of_context \
    -top raddsp_axis_fingerprint_matcher \
    -generic {VENDOR=xilinx MEMORY_STYLE=ultra TABLE_ADDR_WIDTH=10 HASH_WIDTH=64 META_WIDTH=32} \
    -part xck26-sfvc784-2LV-c

report_utilization -hierarchical -file [file join $build_dir matcher_uram_util.rpt]
report_timing_summary -file [file join $build_dir matcher_uram_timing_summary.rpt]

puts "PASS fingerprint matcher K26 URAM synthesis check"
