set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. build]]
set report_dir [file normalize [file join $script_dir .. reports]]
file mkdir $project_dir
file mkdir $report_dir

create_project -force radfft_xfft_1024_k26 $project_dir -part xck26-sfvc784-2LV-c

create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name radfft_xfft_1024
set_property -dict [list \
  CONFIG.transform_length {1024} \
  CONFIG.implementation_options {pipelined_streaming_io} \
  CONFIG.throttle_scheme {realtime} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {32} \
  CONFIG.phase_factor_width {24} \
  CONFIG.scaling_options {scaled} \
  CONFIG.rounding_modes {truncation} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.memory_options_data {block_ram} \
  CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} \
  CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
  CONFIG.aclken {true} \
  CONFIG.aresetn {true} \
  CONFIG.target_clock_frequency {100} \
  CONFIG.target_data_throughput {100} \
] [get_ips radfft_xfft_1024]

generate_target {instantiation_template synthesis simulation} [get_ips radfft_xfft_1024]
export_ip_user_files -of_objects [get_ips radfft_xfft_1024] -no_script -sync -force -quiet
synth_ip [get_ips radfft_xfft_1024]

set ip [get_ips radfft_xfft_1024]
set fp [open [file join $report_dir radfft_xfft_1024_k26_config.txt] w]
puts $fp "part=xck26-sfvc784-2LV-c"
puts $fp "clock_mhz=100"
puts $fp "transform_length=[get_property CONFIG.transform_length $ip]"
puts $fp "implementation_options=[get_property CONFIG.implementation_options $ip]"
puts $fp "throttle_scheme=[get_property CONFIG.throttle_scheme $ip]"
puts $fp "input_width=[get_property CONFIG.input_width $ip]"
puts $fp "phase_factor_width=[get_property CONFIG.phase_factor_width $ip]"
puts $fp "scaling_options=[get_property CONFIG.scaling_options $ip]"
puts $fp "output_ordering=[get_property CONFIG.output_ordering $ip]"
puts $fp "memory_options_data=[get_property CONFIG.memory_options_data $ip]"
puts $fp "complex_mult_type=[get_property CONFIG.complex_mult_type $ip]"
puts $fp "butterfly_type=[get_property CONFIG.butterfly_type $ip]"
close $fp

set dcp_file [file join $project_dir radfft_xfft_1024_k26.gen sources_1 ip radfft_xfft_1024 radfft_xfft_1024.dcp]
open_checkpoint $dcp_file
report_utilization -file [file join $report_dir radfft_xfft_1024_k26_utilization.rpt]
report_timing_summary -file [file join $report_dir radfft_xfft_1024_k26_timing_summary.rpt]
report_clock_utilization -file [file join $report_dir radfft_xfft_1024_k26_clock_utilization.rpt]

exit
