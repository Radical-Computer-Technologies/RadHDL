set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set radhdl_root [file normalize [file join $project_dir .. ..]]

set board_name "kria_k26"
set memory_style "block"
set radix 2
set word_samples 4
set write_bitstream 0
foreach arg $argv {
    if {[regexp {^(--)?memory[-_]style=(block|ultra)$} $arg -> _ value]} {
        set memory_style $value
    } elseif {[regexp {^(--)?radix=([24])$} $arg -> _ value]} {
        set radix $value
    } elseif {[regexp {^(--)?word[-_]samples=([124])$} $arg -> _ value]} {
        set word_samples $value
    } elseif {$arg eq "--bitstream"} {
        set write_bitstream 1
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

if {$memory_style eq "ultra"} {
    if {![info exists RADHDL_HAS_URAM] || !$RADHDL_HAS_URAM} {
        error "Board target '$board_name' is not marked as URAM-capable."
    }
}

set build_variant [format "%s_radix%s_%s" $RADHDL_BOARD_NAME $radix $memory_style]
set build_root [file join $radhdl_root projects build radfft_1024_util $build_variant]
set report_dir [file join $build_root reports]
set artifact_dir [file join $build_root artifacts]
set twiddle_mem_file [file normalize [file join $radhdl_root dsp hdl raddsp mem radfft_twiddle_1024_16_fft.mem]]
file mkdir $report_dir
file mkdir $artifact_dir
file mkdir [file dirname $twiddle_mem_file]

if {![file exists $twiddle_mem_file]} {
    exec python3 [file join $radhdl_root dsp hdl raddsp scripts generate_radfft_twiddles.py] \
        --points 1024 \
        --width 16 \
        --output $twiddle_mem_file
}

if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force "radfft_1024_util_${build_variant}" $build_root -part $RADHDL_PART
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

set radfft_files [list \
    [file join $radhdl_root dsp hdl raddsp src raddsp_fft_twiddle_pkg.vhd] \
    [file join $radhdl_root dsp hdl raddsp src fft_tdp_ram.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_fft_twiddle_rom.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_xilinx_dsp48_mul.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_lattice_mul.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_mul.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_xilinx_dsp48_wide_mul.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_axis_radfft_radix2_tdp.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_axis_radfft_radix4_tdp.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_axis_radfft_streaming.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_axis_radfft.vhd] \
]
foreach f $radfft_files {
    if {![file exists $f]} {
        error "Missing RADFFT file: $f"
    }
}
read_vhdl -vhdl2008 -library raddsp $radfft_files
read_vhdl -vhdl2008 [file join $project_dir src radhdl_radfft_1024_util_top.vhd]
add_files -norecurse $twiddle_mem_file
update_compile_order -fileset sources_1
set_property top radhdl_radfft_1024_util_top [current_fileset]

if {$write_bitstream} {
    error "radfft_1024_util is an out-of-context utilization/timing target. Add a board XDC top before requesting a bitstream."
}

synth_design \
    -top radhdl_radfft_1024_util_top \
    -part $RADHDL_PART \
    -mode out_of_context \
    -generic DEVICE_FAMILY=$RADHDL_DSP48_FAMILY \
    -generic FFT_RADIX=$radix \
    -generic FFT_MEMORY_STYLE=$memory_style \
    -generic FFT_TWIDDLE_MEMORY_STYLE=block \
    -generic FFT_TWIDDLE_INIT_FILE=$twiddle_mem_file \
    -generic FFT_WORD_SAMPLES=$word_samples \
    -flatten_hierarchy rebuilt

create_clock -name clk -period $RADHDL_CLOCK_PERIOD_NS [get_ports clk]
check_timing -file [file join $report_dir post_synth_check_timing.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing_summary.rpt]
report_utilization -hierarchical -file [file join $report_dir post_synth_utilization.rpt]
if {[llength [info commands report_dsp_utilization]] > 0} {
    report_dsp_utilization -file [file join $report_dir post_synth_dsp_utilization.rpt]
}

opt_design
place_design
phys_opt_design
route_design
phys_opt_design
report_timing_summary -file [file join $report_dir post_route_timing_summary.rpt]
report_utilization -hierarchical -file [file join $report_dir post_route_utilization.rpt]
if {[llength [info commands report_dsp_utilization]] > 0} {
    report_dsp_utilization -file [file join $report_dir post_route_dsp_utilization.rpt]
}
write_checkpoint -force [file join $artifact_dir radfft_1024_util_post_route.dcp]

if {$write_bitstream} {
    set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
    set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
    write_bitstream -force [file join $artifact_dir radfft_1024_util.bit]
}

set summary_path [file join $build_root BUILD_SUMMARY.md]
set fh [open $summary_path w]
puts $fh "# RADFFT 1024 Utilization Build"
puts $fh ""
puts $fh "Board: `$RADHDL_BOARD_DISPLAY_NAME` (`$RADHDL_PART`)"
puts $fh ""
puts $fh "Clock period: `$RADHDL_CLOCK_PERIOD_NS ns`"
puts $fh ""
puts $fh "Radix: `$radix`"
puts $fh ""
puts $fh "Memory style: `$memory_style`"
puts $fh ""
puts $fh "Twiddle ROM init: `$twiddle_mem_file`"
puts $fh ""
puts $fh "Samples per memory word: `$word_samples`"
puts $fh ""
puts $fh "Bitstream requested: `$write_bitstream`"
puts $fh ""
puts $fh "Reports: `reports/`"
puts $fh ""
puts $fh "Artifacts: `artifacts/`"
close $fh

puts "PASS radfft_1024_util $RADHDL_BOARD_DISPLAY_NAME ($RADHDL_PART)"
puts "Memory style: $memory_style"
puts "Radix: $radix"
puts "Samples per memory word: $word_samples"
puts "Reports: $report_dir"
puts "Artifacts: $artifact_dir"
