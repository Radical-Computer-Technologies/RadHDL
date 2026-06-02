set raddsp_script_dir [file normalize [file dirname [info script]]]
set raddsp_hdl_dir [file normalize [file join $raddsp_script_dir .. ..]]
set raddsp_src_dir [file join $raddsp_hdl_dir raddsp src]
set raddsp_wrapper_dir [file join $raddsp_hdl_dir raddsp wrappers]
set raddsp_release_dir [file join $raddsp_hdl_dir release raddsp]
set raddsp_iprepo_dir [file join $raddsp_hdl_dir iprepo]
set raddsp_xci_dir [file join $raddsp_hdl_dir xci]

set raddsp_src_files [list \
    [file join $raddsp_src_dir zc_reference_pkg.vhd] \
    [file join $raddsp_src_dir cordic_atan_pkg.vhd] \
    [file join $raddsp_src_dir fft_tdp_ram.vhd] \
    [file join $raddsp_src_dir zc_cross_correlator.vhd] \
    [file join $raddsp_src_dir zc_peak_detector.vhd] \
    [file join $raddsp_src_dir zc_chirp_frame_detector.vhd] \
    [file join $raddsp_src_dir cordic_atan2.vhd] \
    [file join $raddsp_src_dir fft_radix2_batch_core.vhd] \
]

set raddsp_release_files [list \
    [file join $raddsp_release_dir zc_reference_pkg.vhd.enc] \
    [file join $raddsp_release_dir cordic_atan_pkg.vhd.enc] \
    [file join $raddsp_release_dir fft_tdp_ram.vhd.enc] \
    [file join $raddsp_release_dir zc_cross_correlator.vhd.enc] \
    [file join $raddsp_release_dir zc_peak_detector.vhd.enc] \
    [file join $raddsp_release_dir zc_chirp_frame_detector.vhd.enc] \
    [file join $raddsp_release_dir cordic_atan2.vhd.enc] \
    [file join $raddsp_release_dir fft_radix2_batch_core.vhd.enc] \
]

proc raddsp_check_files {files} {
    foreach f $files {
        if {![file exists $f]} {
            error "Missing raddsp file: $f"
        }
    }
}

set raddsp_cordic_ip_files [list \
    [file join $raddsp_src_dir cordic_atan_pkg.vhd] \
    [file join $raddsp_src_dir cordic_atan2.vhd] \
    [file join $raddsp_wrapper_dir raddsp_cordic_atan2.vhd] \
]

set raddsp_fft_ip_files [list \
    [file join $raddsp_src_dir fft_tdp_ram.vhd] \
    [file join $raddsp_src_dir fft_radix2_batch_core.vhd] \
    [file join $raddsp_wrapper_dir raddsp_fft_radix2_batch_core.vhd] \
]

set raddsp_zc_ip_files [list \
    [file join $raddsp_src_dir zc_reference_pkg.vhd] \
    [file join $raddsp_src_dir zc_chirp_frame_detector.vhd] \
    [file join $raddsp_wrapper_dir raddsp_zc_chirp_frame_detector.vhd] \
]
