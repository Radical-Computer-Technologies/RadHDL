set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set radhdl_root [file normalize [file join $project_dir .. ..]]

set board_name "zynq_7020"
set selected_cores {}
foreach arg $argv {
    if {[string match "--core=*" $arg]} {
        lappend selected_cores [string range $arg 7 end]
    } elseif {$arg ne "" && ![string match -* $arg]} {
        set board_name $arg
    }
}

set board_file [file join $radhdl_root projects boards "${board_name}.tcl"]
if {![file exists $board_file]} {
    error "Unknown RadHDL board target '$board_name'. Expected $board_file"
}
source $board_file
source [file join $radhdl_root dsp hdl raddsp scripts raddsp_files.tcl]

set build_root [file join $radhdl_root projects build dsp_core_reports $RADHDL_BOARD_NAME]
file mkdir $build_root

set core_profiles [list \
    [list raddsp_axis_gain "AXIS gain, 1 channel" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COEFF_WIDTH=18 COEFF_FRAC_BITS=15 CHANNEL_COUNT=1]] \
    [list raddsp_axis_mix2 "AXIS two-input saturating mixer" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16]] \
    [list raddsp_axis_one_pole_lowpass "AXIS one-pole lowpass, sequential DSP" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COEFF_WIDTH=18 COEFF_FRAC_BITS=15 IMPLEMENTATION=sequential_mac]] \
    [list raddsp_axis_fir "AXIS FIR, 16 taps, 1 DSP lane" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 TAP_WIDTH=18 TAP_COUNT=16 COEFF_FRAC_BITS=15 IMPLEMENTATION=sequential_mac DSP_LANES=1]] \
    [list raddsp_axis_biquad "AXIS biquad, 1 DSP lane" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COEFF_WIDTH=18 COEFF_FRAC_BITS=15 IMPLEMENTATION=sequential_mac DSP_LANES=1]] \
    [list raddsp_axis_dds "AXIS DDS, 16-entry writable LUT" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 PHASE_WIDTH=32 LUT_ADDR_WIDTH=4 FRAME_LENGTH=16 MEM_INIT_FILE=dsp/hdl/raddsp/mem/sine_q15_16.mem]] \
    [list raddsp_axis_iq_magnitude_sq "AXIS IQ magnitude squared" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 MAG_WIDTH=32]] \
    [list raddsp_axis_frame_stats "AXIS frame stats" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COUNT_WIDTH=32 POWER_WIDTH=64]] \
    [list raddsp_axis_matrix_elementwise "AXIS matrix elementwise add/sub/multiply" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COEFF_FRAC_BITS=15]] \
    [list raddsp_axis_matrix_dot "AXIS matrix dot accumulator" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 ACC_WIDTH=48 COEFF_FRAC_BITS=15]] \
    [list raddsp_axis_fft_bin_product_latency "AXIS FFT bin product/correlation, 4 DSP latency optimized" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COEFF_FRAC_BITS=15 IMPLEMENTATION=latency_optimized]] \
    [list raddsp_axis_fft_bin_product_resource "AXIS FFT bin product/correlation, 1 DSP resource optimized" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY DATA_WIDTH=16 COEFF_FRAC_BITS=15 IMPLEMENTATION=resource_optimized]] \
    [list cordic_atan2 "CORDIC atan2" [list G_INPUT_WIDTH=16 G_PHASE_WIDTH=32 G_ITERATIONS=24]] \
    [list fft_radix2_batch_core "FFT batch core, radix-2, 16 point" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY G_POINTS=16 G_MAX_POINTS=16 G_RADIX=2 G_INPUT_WIDTH=16 G_TWIDDLE_WIDTH=16 G_OUTPUT_WIDTH=32 G_SCALE_EACH_STAGE=true]] \
    [list fft_radix4_batch_core "FFT batch core, radix-4, 16 point" [list VENDOR=xilinx DEVICE_FAMILY=$RADHDL_DSP48_FAMILY G_POINTS=16 G_MAX_POINTS=16 G_RADIX=4 G_INPUT_WIDTH=16 G_TWIDDLE_WIDTH=16 G_OUTPUT_WIDTH=32 G_SCALE_EACH_STAGE=true]] \
    [list zc_cross_correlator "Zadoff-Chu cross correlator" [list G_SAMPLE_WIDTH=16 G_ACC_WIDTH=40 G_PRODUCT_SHIFT=15]] \
    [list zc_peak_detector "Zadoff-Chu peak detector, 512 sample frame" [list G_SAMPLE_WIDTH=16 G_ACC_WIDTH=32 G_FRAME_SAMPLES=512 G_PRODUCT_SHIFT=15]] \
    [list zc_chirp_frame_detector "Zadoff-Chu chirp/frame detector, 512 sample frame" [list G_SAMPLE_WIDTH=16 G_ACC_WIDTH=32 G_FRAME_SAMPLES=512 G_CHIRP_LEN=128 G_CHIRP_AFTER_PEAK=64 G_PRODUCT_SHIFT=15]] \
]

proc write_summary_files {build_root rows board_display_name part clock_period} {
    set csv_path [file join $build_root summary.csv]
    set csv [open $csv_path w]
    puts $csv "core,description,status,setup_wns_ns,hold_whs_ns,luts,ffs,ramb18_equiv,dsp_blocks,generics,report_or_error"
    foreach row $rows {
        set escaped {}
        foreach field $row {
            set value [string map {\" \"\"} $field]
            lappend escaped "\"$value\""
        }
        puts $csv [join $escaped ","]
    }
    close $csv

    set md_path [file join $build_root SUMMARY.md]
    set md [open $md_path w]
    puts $md "# RADDsp Core Report Summary"
    puts $md ""
    puts $md "Target: `$board_display_name` (`$part`)"
    puts $md ""
    puts $md "Clock period: `${clock_period} ns`"
    puts $md ""
    puts $md "| Core | Status | Setup WNS | Hold WHS | LUTs | FFs | RAMB18 eq | DSPs |"
    puts $md "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
    foreach row $rows {
        puts $md [format "| `%s` | %s | %s | %s | %s | %s | %s | %s |" \
            [lindex $row 0] [lindex $row 2] [lindex $row 3] [lindex $row 4] \
            [lindex $row 5] [lindex $row 6] [lindex $row 7] [lindex $row 8]]
    }
    puts $md ""
    puts $md "Full reports are in each core's `reports` directory. The exact generic set is in `summary.csv`."
    close $md

    return [list $csv_path $md_path]
}

proc count_cells {pattern} {
    return [llength [get_cells -hier -quiet -filter "REF_NAME =~ $pattern"]]
}

proc trim_field {value} {
    return [string trim $value " \t"]
}

proc parse_post_route_utilization {report_path} {
    set fh [open $report_path r]
    set lines [split [read $fh] "\n"]
    close $fh

    foreach line $lines {
        if {![string match "| * |*" $line]} {
            continue
        }
        if {[string match "*Instance*" $line] || [string match "*---*" $line]} {
            continue
        }

        set fields [split $line "|"]
        if {[llength $fields] < 12} {
            continue
        }

        set instance [trim_field [lindex $fields 1]]
        set module [trim_field [lindex $fields 2]]
        if {$instance eq "" || $module ne "(top)"} {
            continue
        }

        set luts [trim_field [lindex $fields 3]]
        set ffs [trim_field [lindex $fields 7]]
        set ramb36 [trim_field [lindex $fields 8]]
        set ramb18 [trim_field [lindex $fields 9]]
        set dsp [trim_field [lindex $fields 11]]
        set ramb18_equiv [expr {int($ramb18) + (2 * int($ramb36))}]
        return [list $luts $ffs $ramb18_equiv $dsp]
    }

    error "Could not parse top utilization row from $report_path"
}

proc first_slack {delay_type} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1 -quiet]
    if {[llength $paths] == 0} {
        return "NA"
    }
    return [format %.3f [get_property SLACK [lindex $paths 0]]]
}

proc write_core_wrapper {core core_build device_family} {
    set top "${core}_report_top"
    set common_ports {
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;

entity @TOP@ is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    valid_i   : in  std_logic;
    last_i    : in  std_logic;
    ready_i   : in  std_logic;
    ctrl_i    : in  std_logic_vector(31 downto 0);
    data0_i   : in  std_logic_vector(15 downto 0);
    data1_i   : in  std_logic_vector(15 downto 0);
    status_o  : out std_logic_vector(31 downto 0);
    data0_o   : out std_logic_vector(63 downto 0);
    data1_o   : out std_logic_vector(63 downto 0)
  );
end entity;

}

    switch -- $core {
        raddsp_axis_gain {
            set body {
architecture rtl of @TOP@ is
  signal gain_s  : std_logic_vector(17 downto 0);
  signal ready_s : std_logic;
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(15 downto 0);
  signal last_s  : std_logic;
begin
  gain_s <= ctrl_i(17 downto 0);
  status_o <= (31 downto 4 => '0') & last_s & valid_s & ready_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_gain
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15,
      CHANNEL_COUNT => 1
    )
    port map (
      clk => clk,
      rst => rst,
      gain_i => gain_s,
      s_axis_tvalid => valid_i,
      s_axis_tready => ready_s,
      s_axis_tdata => data0_i,
      s_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_mix2 {
            set body {
architecture rtl of @TOP@ is
  signal s0_ready_s : std_logic;
  signal s1_ready_s : std_logic;
  signal valid_s    : std_logic;
  signal data_s     : std_logic_vector(15 downto 0);
  signal last_s     : std_logic;
begin
  status_o <= (31 downto 5 => '0') & last_s & valid_s & s1_ready_s & s0_ready_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_mix2
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16
    )
    port map (
      clk => clk,
      rst => rst,
      s0_axis_tvalid => valid_i,
      s0_axis_tready => s0_ready_s,
      s0_axis_tdata => data0_i,
      s0_axis_tlast => last_i,
      s1_axis_tvalid => ctrl_i(0),
      s1_axis_tready => s1_ready_s,
      s1_axis_tdata => data1_i,
      s1_axis_tlast => ctrl_i(1),
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_one_pole_lowpass {
            set body {
architecture rtl of @TOP@ is
  signal ready_s : std_logic;
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(15 downto 0);
  signal last_s  : std_logic;
begin
  status_o <= (31 downto 4 => '0') & last_s & valid_s & ready_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_one_pole_lowpass
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15,
      IMPLEMENTATION => "sequential_mac"
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => ctrl_i(31),
      alpha_i => ctrl_i(17 downto 0),
      s_axis_tvalid => valid_i,
      s_axis_tready => ready_s,
      s_axis_tdata => data0_i,
      s_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_fir {
            set body {
architecture rtl of @TOP@ is
  signal taps_s  : std_logic_vector((16 * 18) - 1 downto 0);
  signal ready_s : std_logic;
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(15 downto 0);
  signal last_s  : std_logic;
begin
  gen_taps : for i in 0 to 15 generate
  begin
    taps_s(((i + 1) * 18) - 1 downto i * 18) <=
      std_logic_vector(signed(ctrl_i(17 downto 0)) + to_signed(i, 18));
  end generate;

  status_o <= (31 downto 4 => '0') & last_s & valid_s & ready_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_fir
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      TAP_WIDTH => 18,
      TAP_COUNT => 16,
      COEFF_FRAC_BITS => 15,
      IMPLEMENTATION => "sequential_mac",
      DSP_LANES => 1
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => ctrl_i(31),
      taps_i => taps_s,
      s_axis_tvalid => valid_i,
      s_axis_tready => ready_s,
      s_axis_tdata => data0_i,
      s_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_biquad {
            set body {
architecture rtl of @TOP@ is
  signal b0_s    : std_logic_vector(17 downto 0);
  signal b1_s    : std_logic_vector(17 downto 0);
  signal b2_s    : std_logic_vector(17 downto 0);
  signal a1_s    : std_logic_vector(17 downto 0);
  signal a2_s    : std_logic_vector(17 downto 0);
  signal ready_s : std_logic;
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(15 downto 0);
  signal last_s  : std_logic;
begin
  b0_s <= ctrl_i(17 downto 0);
  b1_s <= std_logic_vector(resize(signed(data0_i), 18));
  b2_s <= std_logic_vector(resize(signed(data1_i), 18));
  a1_s <= std_logic_vector(signed(ctrl_i(17 downto 0)) + to_signed(1, 18));
  a2_s <= std_logic_vector(signed(ctrl_i(17 downto 0)) - to_signed(1, 18));
  status_o <= (31 downto 4 => '0') & last_s & valid_s & ready_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_biquad
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15,
      IMPLEMENTATION => "sequential_mac",
      DSP_LANES => 1
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => ctrl_i(31),
      b0_i => b0_s,
      b1_i => b1_s,
      b2_i => b2_s,
      a1_i => a1_s,
      a2_i => a2_s,
      s_axis_tvalid => valid_i,
      s_axis_tready => ready_s,
      s_axis_tdata => data0_i,
      s_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_dds {
            set body {
architecture rtl of @TOP@ is
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(15 downto 0);
  signal last_s  : std_logic;
  signal phase_s : std_logic_vector(31 downto 0);
  signal addr_s  : std_logic_vector(3 downto 0);
begin
  status_o <= (31 downto 7 => '0') & addr_s & last_s & valid_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (63 downto 32 => '0') & phase_s;

  dut_i: entity raddsp.raddsp_axis_dds
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      PHASE_WIDTH => 32,
      LUT_ADDR_WIDTH => 4,
      FRAME_LENGTH => 16,
      MEM_INIT_FILE => "dsp/hdl/raddsp/mem/sine_q15_16.mem"
    )
    port map (
      clk => clk,
      rst => rst,
      enable_i => valid_i,
      phase_reset_i => ctrl_i(31),
      phase_inc_i => ctrl_i,
      phase_offset_i => std_logic_vector(resize(unsigned(data0_i), 32)),
      wav_wr_en_i => ctrl_i(30),
      wav_wr_addr_i => ctrl_i(3 downto 0),
      wav_wr_data_i => data1_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s,
      phase_o => phase_s,
      lut_addr_o => addr_s
    );
end architecture;
}
        }
        raddsp_axis_iq_magnitude_sq {
            set body {
architecture rtl of @TOP@ is
  signal ready_s : std_logic;
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(31 downto 0);
  signal last_s  : std_logic;
begin
  status_o <= (31 downto 4 => '0') & last_s & valid_s & ready_s & ready_i;
  data0_o <= (63 downto 32 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_iq_magnitude_sq
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      MAG_WIDTH => 32
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => valid_i,
      s_axis_tready => ready_s,
      s_axis_tdata => data0_i & data1_i,
      s_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_frame_stats {
            set body {
architecture rtl of @TOP@ is
  signal ready_s : std_logic;
  signal valid_s : std_logic;
  signal data_s  : std_logic_vector(15 downto 0);
  signal last_s  : std_logic;
  signal stats_s : std_logic;
  signal peak_s  : std_logic_vector(15 downto 0);
  signal power_s : std_logic_vector(63 downto 0);
  signal count_s : std_logic_vector(31 downto 0);
begin
  status_o <= count_s(27 downto 0) & stats_s & last_s & valid_s & ready_s;
  data0_o <= power_s;
  data1_o <= (63 downto 48 => '0') & count_s & peak_s;

  dut_i: entity raddsp.raddsp_axis_frame_stats
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      COUNT_WIDTH => 32,
      POWER_WIDTH => 64
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => ctrl_i(31),
      s_axis_tvalid => valid_i,
      s_axis_tready => ready_s,
      s_axis_tdata => data0_i,
      s_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s,
      stats_valid_o => stats_s,
      peak_o => peak_s,
      sum_squares_o => power_s,
      sample_count_o => count_s
    );
end architecture;
}
        }
        raddsp_axis_matrix_elementwise {
            set body {
architecture rtl of @TOP@ is
  signal s0_ready_s : std_logic;
  signal s1_ready_s : std_logic;
  signal valid_s    : std_logic;
  signal data_s     : std_logic_vector(15 downto 0);
  signal last_s     : std_logic;
begin
  status_o <= (31 downto 5 => '0') & last_s & valid_s & s1_ready_s & s0_ready_s & ready_i;
  data0_o <= (63 downto 16 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_matrix_elementwise
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      COEFF_FRAC_BITS => 15
    )
    port map (
      clk => clk,
      rst => rst,
      op_i => ctrl_i(1 downto 0),
      s0_axis_tvalid => valid_i,
      s0_axis_tready => s0_ready_s,
      s0_axis_tdata => data0_i,
      s0_axis_tlast => last_i,
      s1_axis_tvalid => ctrl_i(2),
      s1_axis_tready => s1_ready_s,
      s1_axis_tdata => data1_i,
      s1_axis_tlast => ctrl_i(3),
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
        }
        raddsp_axis_matrix_dot {
            set body {
architecture rtl of @TOP@ is
  signal s0_ready_s : std_logic;
  signal s1_ready_s : std_logic;
  signal valid_s    : std_logic;
  signal data_s     : std_logic_vector(47 downto 0);
  signal last_s     : std_logic;
  signal count_s    : std_logic_vector(31 downto 0);
begin
  status_o <= count_s;
  data0_o <= (63 downto 48 => '0') & data_s;
  data1_o <= (63 downto 5 => '0') & last_s & valid_s & s1_ready_s & s0_ready_s & ready_i;

  dut_i: entity raddsp.raddsp_axis_matrix_dot
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      ACC_WIDTH => 48,
      COEFF_FRAC_BITS => 15
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => ctrl_i(31),
      s0_axis_tvalid => valid_i,
      s0_axis_tready => s0_ready_s,
      s0_axis_tdata => data0_i,
      s0_axis_tlast => last_i,
      s1_axis_tvalid => ctrl_i(0),
      s1_axis_tready => s1_ready_s,
      s1_axis_tdata => data1_i,
      s1_axis_tlast => ctrl_i(1),
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s,
      sample_count_o => count_s
    );
end architecture;
}
        }
        raddsp_axis_fft_bin_product_latency -
        raddsp_axis_fft_bin_product_resource {
            if {$core eq "raddsp_axis_fft_bin_product_resource"} {
                set fft_bin_impl "resource_optimized"
            } else {
                set fft_bin_impl "latency_optimized"
            }
            set body {
architecture rtl of @TOP@ is
  signal s0_ready_s : std_logic;
  signal s1_ready_s : std_logic;
  signal valid_s    : std_logic;
  signal data_s     : std_logic_vector(31 downto 0);
  signal last_s     : std_logic;
  signal a_data_s   : std_logic_vector(31 downto 0);
  signal b_data_s   : std_logic_vector(31 downto 0);
begin
  a_data_s <= data0_i & data1_i;
  b_data_s <= ctrl_i(15 downto 0) & ctrl_i(31 downto 16);
  status_o <= (31 downto 5 => '0') & last_s & valid_s & s1_ready_s & s0_ready_s & ready_i;
  data0_o <= (63 downto 32 => '0') & data_s;
  data1_o <= (others => '0');

  dut_i: entity raddsp.raddsp_axis_fft_bin_product
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      DATA_WIDTH => 16,
      COEFF_FRAC_BITS => 15,
      IMPLEMENTATION => "@FFT_BIN_IMPL@"
    )
    port map (
      clk => clk,
      rst => rst,
      correlate_i => ctrl_i(0),
      s0_axis_tvalid => valid_i,
      s0_axis_tready => s0_ready_s,
      s0_axis_tdata => a_data_s,
      s0_axis_tlast => last_i,
      s1_axis_tvalid => valid_i,
      s1_axis_tready => s1_ready_s,
      s1_axis_tdata => b_data_s,
      s1_axis_tlast => last_i,
      m_axis_tvalid => valid_s,
      m_axis_tready => ready_i,
      m_axis_tdata => data_s,
      m_axis_tlast => last_s
    );
end architecture;
}
            set body [string map [list @FFT_BIN_IMPL@ $fft_bin_impl] $body]
        }
        cordic_atan2 {
            set body {
architecture rtl of @TOP@ is
  signal input_ready_s : std_logic;
  signal busy_s        : std_logic;
  signal phase_valid_s : std_logic;
  signal phase_s       : signed(31 downto 0);
begin
  status_o <= (31 downto 3 => '0') & phase_valid_s & busy_s & input_ready_s;
  data0_o <= (63 downto 32 => '0') & std_logic_vector(phase_s);
  data1_o <= (others => '0');

  dut_i: entity raddsp.cordic_atan2
    generic map (
      G_INPUT_WIDTH => 16,
      G_PHASE_WIDTH => 32,
      G_ITERATIONS => 24
    )
    port map (
      clk => clk,
      rst => rst,
      input_valid => valid_i,
      x_in => signed(data0_i),
      y_in => signed(data1_i),
      input_ready => input_ready_s,
      busy => busy_s,
      phase_valid => phase_valid_s,
      phase_out => phase_s
    );
end architecture;
}
        }
        fft_radix2_batch_core -
        fft_radix4_batch_core {
            if {$core eq "fft_radix4_batch_core"} {
                set fft_radix 4
            } else {
                set fft_radix 2
            }
            set body {
architecture rtl of @TOP@ is
  signal sample_ready_s : std_logic;
  signal twiddle_addr_s : integer range 0 to 7;
  signal busy_s         : std_logic;
  signal done_s         : std_logic;
  signal output_valid_s : std_logic;
  signal output_index_s : integer range 0 to 15;
  signal output_re_s    : integer;
  signal output_im_s    : integer;
begin
  status_o <= std_logic_vector(to_unsigned(output_index_s, 16)) &
              std_logic_vector(to_unsigned(twiddle_addr_s, 12)) &
              output_valid_s & done_s & busy_s & sample_ready_s;
  data0_o <= (63 downto 32 => '0') & std_logic_vector(to_signed(output_re_s, 32));
  data1_o <= (63 downto 32 => '0') & std_logic_vector(to_signed(output_im_s, 32));

  dut_i: entity raddsp.fft_radix2_batch_core
    generic map (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "@DEVICE@",
      G_POINTS => 16,
      G_MAX_POINTS => 16,
      G_RADIX => @FFT_RADIX@,
      G_INPUT_WIDTH => 16,
      G_TWIDDLE_WIDTH => 16,
      G_OUTPUT_WIDTH => 32,
      G_SCALE_EACH_STAGE => true
    )
    port map (
      clk => clk,
      rst => rst,
      start_frame => ctrl_i(31),
      sample_valid => valid_i,
      sample_re => to_integer(signed(data0_i)),
      sample_im => to_integer(signed(data1_i)),
      sample_ready => sample_ready_s,
      twiddle_addr => twiddle_addr_s,
      twiddle_re => to_integer(signed(ctrl_i(15 downto 0))),
      twiddle_im => to_integer(signed(ctrl_i(31 downto 16))),
      busy => busy_s,
      done => done_s,
      output_valid => output_valid_s,
      output_index => output_index_s,
      output_re => output_re_s,
      output_im => output_im_s
    );
end architecture;
}
            set body [string map [list @FFT_RADIX@ $fft_radix] $body]
        }
        zc_cross_correlator {
            set body {
architecture rtl of @TOP@ is
  signal sample_ready_s : std_logic;
  signal busy_s         : std_logic;
  signal corr_valid_s   : std_logic;
  signal corr_i_s       : signed(39 downto 0);
  signal corr_q_s       : signed(39 downto 0);
  signal corr_mag_s     : unsigned(79 downto 0);
begin
  status_o <= (31 downto 3 => '0') & corr_valid_s & busy_s & sample_ready_s;
  data0_o <= std_logic_vector(resize(corr_i_s, 64));
  data1_o <= std_logic_vector(corr_mag_s(63 downto 0));

  dut_i: entity raddsp.zc_cross_correlator
    generic map (
      DEVICE_FAMILY => "@DEVICE@",
      G_SAMPLE_WIDTH => 16,
      G_ACC_WIDTH => 40,
      G_PRODUCT_SHIFT => 15
    )
    port map (
      clk => clk,
      rst => rst,
      block_start => ctrl_i(31),
      sample_valid => valid_i,
      sample_i => signed(data0_i),
      sample_q => signed(data1_i),
      sample_ready => sample_ready_s,
      busy => busy_s,
      corr_valid => corr_valid_s,
      corr_i => corr_i_s,
      corr_q => corr_q_s,
      corr_mag_sq => corr_mag_s
    );
end architecture;
}
        }
        zc_peak_detector {
            set body {
architecture rtl of @TOP@ is
  signal sample_ready_s : std_logic;
  signal busy_s         : std_logic;
  signal peak_valid_s   : std_logic;
  signal peak_index_s   : integer range 0 to 511;
  signal peak_i_s       : signed(31 downto 0);
  signal peak_q_s       : signed(31 downto 0);
  signal peak_mag_s     : unsigned(63 downto 0);
begin
  status_o <= std_logic_vector(to_unsigned(peak_index_s, 16)) &
              (15 downto 3 => '0') & peak_valid_s & busy_s & sample_ready_s;
  data0_o <= std_logic_vector(resize(peak_i_s, 64));
  data1_o <= std_logic_vector(peak_mag_s(63 downto 0));

  dut_i: entity raddsp.zc_peak_detector
    generic map (
      DEVICE_FAMILY => "@DEVICE@",
      G_SAMPLE_WIDTH => 16,
      G_ACC_WIDTH => 32,
      G_FRAME_SAMPLES => 512,
      G_PRODUCT_SHIFT => 15
    )
    port map (
      clk => clk,
      rst => rst,
      frame_start => ctrl_i(31),
      sample_valid => valid_i,
      sample_i => signed(data0_i),
      sample_q => signed(data1_i),
      sample_ready => sample_ready_s,
      busy => busy_s,
      peak_valid => peak_valid_s,
      peak_index => peak_index_s,
      peak_i => peak_i_s,
      peak_q => peak_q_s,
      peak_mag_sq => peak_mag_s
    );
end architecture;
}
        }
        zc_chirp_frame_detector {
            set body {
architecture rtl of @TOP@ is
  signal sample_ready_s : std_logic;
  signal processing_s   : std_logic;
  signal peak_valid_s   : std_logic;
  signal peak_index_s   : integer range 0 to 511;
  signal peak_i_s       : signed(31 downto 0);
  signal peak_q_s       : signed(31 downto 0);
  signal chirp_valid_s  : std_logic;
  signal chirp_index_s  : integer range 0 to 127;
  signal chirp_i_s      : signed(15 downto 0);
  signal chirp_q_s      : signed(15 downto 0);
  signal chirp_done_s   : std_logic;
begin
  status_o <= std_logic_vector(to_unsigned(peak_index_s, 16)) &
              std_logic_vector(to_unsigned(chirp_index_s, 10)) &
              chirp_done_s & chirp_valid_s & peak_valid_s & processing_s & sample_ready_s & ready_i;
  data0_o <= std_logic_vector(resize(peak_i_s, 64));
  data1_o <= (63 downto 32 => '0') & std_logic_vector(chirp_i_s) & std_logic_vector(chirp_q_s);

  dut_i: entity raddsp.zc_chirp_frame_detector
    generic map (
      DEVICE_FAMILY => "@DEVICE@",
      G_SAMPLE_WIDTH => 16,
      G_ACC_WIDTH => 32,
      G_FRAME_SAMPLES => 512,
      G_CHIRP_LEN => 128,
      G_CHIRP_AFTER_PEAK => 64,
      G_PRODUCT_SHIFT => 15
    )
    port map (
      clk => clk,
      rst => rst,
      frame_start => ctrl_i(31),
      sample_valid => valid_i,
      sample_i => signed(data0_i),
      sample_q => signed(data1_i),
      sample_ready => sample_ready_s,
      processing => processing_s,
      peak_valid => peak_valid_s,
      peak_index => peak_index_s,
      peak_i => peak_i_s,
      peak_q => peak_q_s,
      chirp_valid => chirp_valid_s,
      chirp_index => chirp_index_s,
      chirp_i => chirp_i_s,
      chirp_q => chirp_q_s,
      chirp_done => chirp_done_s
    );
end architecture;
}
        }
        default {
            error "No report wrapper template for $core"
        }
    }

    set wrapper_path [file join $core_build "${top}.vhd"]
    set fh [open $wrapper_path w]
    puts $fh [string map [list @TOP@ $top @DEVICE@ $device_family] "${common_ports}${body}"]
    close $fh
    return [list $top $wrapper_path]
}

proc run_core {radhdl_root build_root part clock_period core desc generics} {
    global raddsp_src_files RADHDL_BOARD_NAME RADHDL_DSP48_FAMILY

    set core_build [file join $build_root $core]
    set report_dir [file join $core_build reports]
    file mkdir $report_dir

    if {[llength [get_projects -quiet]] > 0} {
        close_project
    }

    create_project -force "raddsp_core_${core}_${RADHDL_BOARD_NAME}" $core_build -part $part
    set_property target_language VHDL [current_project]
    set_property simulator_language Mixed [current_project]
    set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]

    raddsp_check_files $raddsp_src_files
    read_vhdl -vhdl2008 -library raddsp $raddsp_src_files
    set wrapper_info [write_core_wrapper $core $core_build $RADHDL_DSP48_FAMILY]
    set report_top [lindex $wrapper_info 0]
    set wrapper_file [lindex $wrapper_info 1]
    read_vhdl -vhdl2008 $wrapper_file
    update_compile_order -fileset sources_1

    set synth_cmd [list synth_design -top $report_top -part $part -mode out_of_context -flatten_hierarchy rebuilt]
    {*}$synth_cmd

    if {[llength [get_ports -quiet clk]] > 0} {
        create_clock -name clk -period $clock_period [get_ports clk]
    }
    check_timing -file [file join $report_dir post_synth_check_timing.rpt]
    report_timing_summary -file [file join $report_dir post_synth_timing_summary.rpt]
    report_utilization -hierarchical -file [file join $report_dir post_synth_utilization.rpt]

    opt_design
    place_design
    phys_opt_design
    route_design

    report_timing_summary -file [file join $report_dir post_route_timing_summary.rpt]
    set post_route_utilization_path [file join $report_dir post_route_utilization.rpt]
    report_utilization -hierarchical -file $post_route_utilization_path
    write_checkpoint -force [file join $core_build ${core}_post_route.dcp]

    set setup_wns [first_slack max]
    set hold_whs [first_slack min]
    set utilization [parse_post_route_utilization $post_route_utilization_path]
    set luts [lindex $utilization 0]
    set ffs [lindex $utilization 1]
    set ramb18 [lindex $utilization 2]
    set dsp [lindex $utilization 3]
    set status PASS
    if {$setup_wns ne "NA" && [expr {double($setup_wns)}] < 0.0} {
        set status FAIL_TIMING
    }
    if {$hold_whs ne "NA" && [expr {double($hold_whs)}] < 0.0} {
        set status FAIL_TIMING
    }

    return [list $core $desc $status $setup_wns $hold_whs $luts $ffs $ramb18 $dsp [join $generics ";"] $report_dir]
}

set rows {}
foreach profile $core_profiles {
    set core [lindex $profile 0]
    set desc [lindex $profile 1]
    set generics [lindex $profile 2]
    if {[llength $selected_cores] > 0 && [lsearch -exact $selected_cores $core] < 0} {
        continue
    }
    puts "INFO: Running RADDsp core report for $core"
    if {[catch {
        set result [run_core $radhdl_root $build_root $RADHDL_PART $RADHDL_CLOCK_PERIOD_NS $core $desc $generics]
    } err opts]} {
        puts "ERROR: Core $core failed: $err"
        set result [list $core $desc FAIL NA NA NA NA NA NA [join $generics ";"] $err]
        if {[llength [get_projects -quiet]] > 0} {
            close_project
        }
    }
    lappend rows $result
    write_summary_files $build_root $rows $RADHDL_BOARD_DISPLAY_NAME $RADHDL_PART $RADHDL_CLOCK_PERIOD_NS
}

set summary_paths [write_summary_files $build_root $rows $RADHDL_BOARD_DISPLAY_NAME $RADHDL_PART $RADHDL_CLOCK_PERIOD_NS]
set csv_path [lindex $summary_paths 0]
set md_path [lindex $summary_paths 1]

set failed_rows {}
foreach row $rows {
    if {[lindex $row 2] ne "PASS"} {
        lappend failed_rows [lindex $row 0]
    }
}

if {[llength $failed_rows] > 0} {
    puts "FAIL raddsp core reports $RADHDL_BOARD_DISPLAY_NAME ($RADHDL_PART): [join $failed_rows {, }]"
} else {
    puts "PASS raddsp core reports $RADHDL_BOARD_DISPLAY_NAME ($RADHDL_PART)"
}
puts "Summary CSV: $csv_path"
puts "Summary Markdown: $md_path"

if {[llength $failed_rows] > 0} {
    exit 1
}
