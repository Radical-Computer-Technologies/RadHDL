set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_name "radhdl_fpiga_audio_shared"

if {[info exists ::env(RADHDL_ROOT)]} {
    set radhdl_root [file normalize $::env(RADHDL_ROOT)]
} else {
    set radhdl_root [file normalize [file join $project_dir ../../..]]
}

if {[info exists ::env(FPIGA_AUDIO_HAT_REPO)]} {
    set fpiga_repo [file normalize $::env(FPIGA_AUDIO_HAT_REPO)]
} else {
    set fpiga_repo "/media/jvincent/Kingspec512/repos/FPiGA-Audio-Hat"
}

if {[info exists ::env(FPIGA_GOWIN_BUILD_DIR)]} {
    set build_dir [file normalize $::env(FPIGA_GOWIN_BUILD_DIR)]
} else {
    set build_dir [file normalize [file join $project_dir build gowin]]
}

if {[info exists ::env(FPIGA_GOWIN_PART)]} {
    set part_number $::env(FPIGA_GOWIN_PART)
} else {
    set part_number "GW5A-LV25MG121NC1/I0"
}

if {[info exists ::env(FPIGA_GOWIN_DEVICE_VERSION)]} {
    set device_version $::env(FPIGA_GOWIN_DEVICE_VERSION)
} else {
    set device_version "A"
}

set fpiga_hdl_dir [file join $fpiga_repo hw_rev1_0 source hdl]
file mkdir $build_dir
create_project -name $project_name -dir $build_dir -pn $part_number -device_version $device_version -force

set source_files [list \
    [file join $radhdl_root interfaces hdl radif src radif_pkg.vhd] \
    [file join $radhdl_root interfaces hdl radif src radif_i2c_slave_to_reg.vhd] \
    [file join $radhdl_root interfaces hdl radif src radif_reg_bank.vhd] \
    [file join $radhdl_root interfaces hdl radif src radif_reg_interconnect.vhd] \
    [file join $radhdl_root interfaces hdl radif src radif_i2s_axis.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_axis_pkg.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_gowin_multalu27x18_mul.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_gowin_multalu27x32_mul.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_gowin_dpb16.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_quad_wavetable_oscillator.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_quad_lfo_wavetable.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_poly_synth.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_quad_osc_pan_mixer.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_stereo_balance_tdm.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_stereo_biquad_eq_tdm.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_stereo_shared_pg_eq_tdm.vhd] \
    [file join $radhdl_root dsp hdl raddsp src raddsp_audio_stereo_gain.vhd] \
    [file join $radhdl_root debug radila hdl radila radila_gowin_dpb_ram.vhd] \
    [file join $radhdl_root debug radila hdl radila radila_core.vhd] \
    [file join $radhdl_root debug radila hdl radila raddebughub.vhd] \
    [file join $project_dir src radhdl_fpiga_audio_top.vhd] \
]

foreach source_file $source_files {
    add_file -type vhdl $source_file
}

add_file -type cst [file join $project_dir gowin fpiga_audio_hat_pi_i2s.cst]
add_file -type sdc [file join $project_dir gowin fpiga_audio_hat_timing.sdc]

set_option -top_module radhdl_fpiga_audio_top
set_option -vhdl_std vhd2008
set_option -pipe 1
set_option -retiming 1
set_option -maxfan 64
set_option -place_option 2
set_option -route_option 1
set_option -route_maxfan 16
set_option -cst_warn_to_error 1
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
run all
run close
