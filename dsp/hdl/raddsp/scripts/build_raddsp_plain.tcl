source [file join [file dirname [info script]] raddsp_files.tcl]

set build_dir [file join $raddsp_hdl_dir build plain_project]
file mkdir [file dirname $build_dir]

if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force raddsp_plain $build_dir -part xczu3eg-sfvc784-1-e
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]

raddsp_check_files $raddsp_src_files
read_vhdl -vhdl2008 -library raddsp $raddsp_src_files

read_vhdl -vhdl2008 [list \
    [file join $raddsp_hdl_dir testbenches iqcal_capture_pkg.vhd] \
    [file join $raddsp_hdl_dir testbenches tb_cordic_atan2.vhd] \
    [file join $raddsp_hdl_dir testbenches tb_zc_chirp_frame_detector_iqcal.vhd] \
]

update_compile_order -fileset sources_1
set_property top tb_cordic_atan2 [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

set_property top tb_zc_chirp_frame_detector_iqcal [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

puts "PASS raddsp plaintext library testbenches"
