source [file join [file dirname [info script]] raddsp_files.tcl]

set part_name xczu3eg-sfvc784-1-e
if {[info exists ::env(RADBUILD_VIVADO_PART)] && $::env(RADBUILD_VIVADO_PART) ne ""} {
    set part_name $::env(RADBUILD_VIVADO_PART)
}

set project_dir [file join $raddsp_hdl_dir build xci_project]
file mkdir $raddsp_xci_dir

if {[llength [get_projects -quiet]] > 0} {
    close_project
}

create_project -force raddsp_xci $project_dir -part $part_name
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
set_property ip_repo_paths [list $raddsp_iprepo_dir] [current_project]
update_ip_catalog

proc raddsp_create_xci {ip_name module_name xci_dir config_dict} {
    create_ip -vendor rct.local -library raddsp -name $ip_name -version 1.0 -module_name $module_name -dir $xci_dir
    set ip_obj [get_ips $module_name]
    if {[llength $config_dict] > 0} {
        set_property -dict $config_dict $ip_obj
    }
    generate_target all $ip_obj
    export_ip_user_files -of_objects $ip_obj -no_script -sync -force -quiet
}

raddsp_create_xci raddsp_cordic_atan2 raddsp_cordic_atan2_0 $raddsp_xci_dir [list \
    CONFIG.G_INPUT_WIDTH {32} \
    CONFIG.G_PHASE_WIDTH {32} \
    CONFIG.G_ITERATIONS {24} \
]
raddsp_create_xci raddsp_fft_radix2_batch_core raddsp_fft_radix2_batch_core_0 $raddsp_xci_dir [list \
    CONFIG.VENDOR {xilinx} \
    CONFIG.DEVICE_FAMILY {ultrascale+} \
    CONFIG.G_POINTS {32} \
    CONFIG.G_MAX_POINTS {32} \
    CONFIG.G_INPUT_WIDTH {16} \
    CONFIG.G_TWIDDLE_WIDTH {16} \
    CONFIG.G_OUTPUT_WIDTH {32} \
    CONFIG.G_SCALE_EACH_STAGE {true} \
]
raddsp_create_xci raddsp_zc_chirp_frame_detector raddsp_zc_chirp_frame_detector_0 $raddsp_xci_dir [list \
    CONFIG.G_SAMPLE_WIDTH {16} \
    CONFIG.G_ACC_WIDTH {40} \
    CONFIG.G_FRAME_SAMPLES {1024} \
    CONFIG.G_CHIRP_LEN {512} \
    CONFIG.G_CHIRP_AFTER_PEAK {160} \
    CONFIG.G_PRODUCT_SHIFT {15} \
]

puts "PASS raddsp XCI instances generated in $raddsp_xci_dir"
