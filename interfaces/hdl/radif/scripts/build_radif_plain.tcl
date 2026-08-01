source [file join [file dirname [info script]] radif_files.tcl]

set build_dir [file join $radif_hdl_dir build xsim_plain]
file delete -force $build_dir
file mkdir $build_dir

radif_check_files $radif_src_files
radif_check_files $radif_tb_files

set run_tcl [file join $build_dir run_all.tcl]
set fh [open $run_tcl w]
puts $fh "run all"
puts $fh "quit"
close $fh

set old_dir [pwd]
cd $build_dir

set analyze_cmd [list xvhdl --2008 -work radif]
foreach f [concat $radif_src_files $radif_tb_files] {
    lappend analyze_cmd $f
}
puts "Running: $analyze_cmd"
exec {*}$analyze_cmd >@ stdout 2>@ stderr

foreach tb {tb_radif_reg_bank tb_radif_reg_interconnect tb_radif_axi_lite_to_reg tb_radif_smi16_to_reg tb_radif_axi4_axis_dma tb_radif_interfaces_smoke} {
    set snap ${tb}_snap
    set elab_cmd [list xelab --relax --mt 8 \
        -L radif -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -L xpm \
        --snapshot $snap radif.$tb]
    puts "Running: $elab_cmd"
    exec {*}$elab_cmd >@ stdout 2>@ stderr

    set sim_log ${tb}.log
    set sim_cmd [list xsim $snap -tclbatch $run_tcl -log $sim_log]
    puts "Running: $sim_cmd"
    exec {*}$sim_cmd >@ stdout 2>@ stderr
    set fh [open $sim_log r]
    set sim_text [read $fh]
    close $fh
    if {[regexp -line {^(ERROR:|Failure:|Fatal:)} $sim_text]} {
        error "Simulation failed; see [file join $build_dir $sim_log]"
    }
}

cd $old_dir
puts "PASS radif plaintext library testbenches"
