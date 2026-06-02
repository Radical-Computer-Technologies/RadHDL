source [file join [file dirname [info script]] raddsp_files.tcl]

file mkdir $raddsp_iprepo_dir

proc raddsp_package_core {part iprepo_dir project_base name display_name description top files} {
    set project_dir [file join $project_base $name]
    set ip_root_dir [file join $iprepo_dir "${name}_1.0"]

    if {[llength [get_projects -quiet]] > 0} {
        close_project
    }

    create_project -force "${name}_packager" $project_dir -part $part
    set_property target_language VHDL [current_project]
    set_property simulator_language Mixed [current_project]
    set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]

    raddsp_check_files $files
    add_files -norecurse $files
    set_property file_type {VHDL 2008} [get_files $files]
    set_property top $top [current_fileset]
    update_compile_order -fileset sources_1

    ipx::package_project \
        -force \
        -root_dir $ip_root_dir \
        -vendor rct.local \
        -library raddsp \
        -taxonomy {/RADDSP} \
        -import_files

    set core [ipx::current_core]
    set_property name $name $core
    set_property display_name $display_name $core
    set_property description $description $core
    set_property version 1.0 $core
    set_property vendor_display_name {RCT} $core
    set_property company_url {https://example.local/raddsp} $core
    set_property supported_families {zynquplus Production zynq Production} $core
    ipx::check_integrity $core
    ipx::save_core $core
    close_project
}

set part_name xczu3eg-sfvc784-1-e
if {[info exists ::env(RADBUILD_VIVADO_PART)] && $::env(RADBUILD_VIVADO_PART) ne ""} {
    set part_name $::env(RADBUILD_VIVADO_PART)
}

set package_project_base [file join $raddsp_hdl_dir build ip_packager]
file mkdir $package_project_base

raddsp_package_core $part_name $raddsp_iprepo_dir $package_project_base \
    raddsp_cordic_atan2 \
    {raddsp CORDIC atan2} \
    {Pipelined CORDIC atan2 phase estimator with configurable input, phase width, and iteration count.} \
    raddsp_cordic_atan2 \
    $raddsp_cordic_ip_files

raddsp_package_core $part_name $raddsp_iprepo_dir $package_project_base \
    raddsp_fft_radix2_batch_core \
    {raddsp radix-2 batch FFT} \
    {RAM-backed radix-2 batch FFT primitive for raddsp DSP pipelines.} \
    raddsp_fft_radix2_batch_core \
    $raddsp_fft_ip_files

raddsp_package_core $part_name $raddsp_iprepo_dir $package_project_base \
    raddsp_zc_chirp_frame_detector \
    {raddsp ZC chirp frame detector} \
    {Zadoff-Chu cross-correlator and chirp replay detector for calibration captures.} \
    raddsp_zc_chirp_frame_detector \
    $raddsp_zc_ip_files

puts "PASS raddsp IP repository packaged at $raddsp_iprepo_dir"
