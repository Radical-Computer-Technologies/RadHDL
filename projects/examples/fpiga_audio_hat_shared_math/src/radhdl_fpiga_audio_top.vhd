library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library gw5a;
use gw5a.components.all;

use work.radif_pkg.all;

entity radhdl_fpiga_audio_top is
  port (
    CLK_50M        : in    std_logic;
    SDA_IN         : inout std_logic;
    SCL_IN         : inout std_logic;
    I2S_SDA_IN_RPI : in    std_logic;
    I2S_BCK_RPI    : out   std_logic;
    I2S_DOUT_PI    : out   std_logic;
    I2S_LRCK_RPI   : out   std_logic;
    MCLKXCO_OUT    : out   std_logic;
    I2S_BCK        : in    std_logic;
    I2S_LRCK_DAC   : in    std_logic;
    I2S_LRCK_ADC   : in    std_logic;
    I2S_SDA_DAC    : out   std_logic;
    I2S_SDA_ADC    : in    std_logic;
    MUTEEN         : out   std_logic;
    FPGA67         : out   std_logic;
    FPGA75         : out   std_logic;
    FPGA77         : out   std_logic;
    FPGA71         : out   std_logic
  );
end entity;

architecture rtl of radhdl_fpiga_audio_top is
  constant C_UNITY_GAIN : std_logic_vector(17 downto 0) := std_logic_vector(to_signed(32767, 18));
  constant C_CTRL_SLAVE_COUNT : integer := 3;
  constant C_CTRL_LOW_RW_REG_COUNT : integer := 16;
  constant C_CTRL_HIGH_RW_REG_COUNT : integer := 16;
  constant C_CTRL_RO_REG_COUNT : integer := 8;
  constant C_REG_CONTROL       : natural := 0;
  constant C_REG_DSP_CONTROL   : natural := 1;
  constant C_REG_FREQ0         : natural := 2;
  constant C_REG_FREQ1         : natural := 3;
  constant C_REG_FREQ2         : natural := 4;
  constant C_REG_FREQ3         : natural := 5;
  constant C_REG_LEFT_GAIN     : natural := 6;
  constant C_REG_RIGHT_GAIN    : natural := 7;
  constant C_REG_OSC0_GAIN     : natural := 8;
  constant C_REG_OSC1_GAIN     : natural := 9;
  constant C_REG_OSC2_GAIN     : natural := 10;
  constant C_REG_OSC3_GAIN     : natural := 11;
  constant C_REG_WAVE_CONTROL  : natural := 12;
  constant C_REG_OSC_PAN       : natural := 13;
  constant C_REG_GLOBAL_PAN    : natural := 14;
  constant C_REG_WAVE_DATA     : natural := 15;
  constant C_POLY_VOICES       : natural := 16;
  constant C_POLY_FREQ_BASE    : natural := 16;
  constant C_POLY_CTRL_BASE    : natural := 32;
  constant C_POLY_VOL_BASE     : natural := 48;
  constant C_POLY_ADSR_BASE    : natural := 64;
  constant C_REG_LFO_CONTROL   : natural := 80;
  constant C_LFO_FREQ_BASE     : natural := 81;
  constant C_LFO_DEPTH_BASE    : natural := 85;
  constant C_REG_LFO_WAVE_CONTROL : natural := 89;
  constant C_REG_LFO_WAVE_DATA : natural := 90;
  constant C_REG_EQ_CONTROL    : natural := 91;
  constant C_REG_EQ_COEFF_ADDR : natural := 92;
  constant C_REG_EQ_COEFF_DATA : natural := 93;
  constant C_REG_EQ_SMOOTH     : natural := 94;
  constant C_REG_SCOPE_CONTROL : natural := 95;
  constant C_RPI_BCLK_DIV      : natural := 0;
  constant C_RPI_LRCK_BITS     : natural := 32;
  constant C_RPI_MARKER_PREFIX : std_logic_vector(3 downto 0) := x"A";
  constant C_HIGH_REG_LFO_CONTROL : natural := C_REG_LFO_CONTROL - 80;
  constant C_HIGH_LFO_FREQ_BASE : natural := C_LFO_FREQ_BASE - 80;
  constant C_HIGH_LFO_DEPTH_BASE : natural := C_LFO_DEPTH_BASE - 80;
  constant C_HIGH_REG_LFO_WAVE_CONTROL : natural := C_REG_LFO_WAVE_CONTROL - 80;
  constant C_HIGH_REG_LFO_WAVE_DATA : natural := C_REG_LFO_WAVE_DATA - 80;
  constant C_HIGH_REG_EQ_CONTROL : natural := C_REG_EQ_CONTROL - 80;
  constant C_HIGH_REG_EQ_COEFF_ADDR : natural := C_REG_EQ_COEFF_ADDR - 80;
  constant C_HIGH_REG_EQ_COEFF_DATA : natural := C_REG_EQ_COEFF_DATA - 80;
  constant C_HIGH_REG_EQ_SMOOTH : natural := C_REG_EQ_SMOOTH - 80;
  constant C_HIGH_REG_SCOPE_CONTROL : natural := C_REG_SCOPE_CONTROL - 80;

  signal sysclk_i       : std_logic := '0';
  signal mclk_i         : std_logic := '0';
  signal clocks_locked  : std_logic := '0';
  signal fabric_rstn    : std_logic := '0';
  signal rstn_i         : std_logic := '0';
  signal rst_i          : std_logic := '1';
  signal rpi_i2s_rstn_pipe : std_logic_vector(1 downto 0) := (others => '0');
  signal adc_i2s_rstn_pipe : std_logic_vector(1 downto 0) := (others => '0');
  signal dac_i2s_rstn_pipe : std_logic_vector(1 downto 0) := (others => '0');
  signal rpi_i2s_rstn  : std_logic := '0';
  signal adc_i2s_rstn  : std_logic := '0';
  signal dac_i2s_rstn  : std_logic := '0';
  signal sys_rst_count  : unsigned(5 downto 0) := (others => '0');
  signal clkfb_unused   : std_logic;
  signal clkout1_unused : std_logic;
  signal mdrdo_unused   : std_logic_vector(7 downto 0);

  signal i2c_sda_oen    : std_logic := '1';
  signal ctrl_reg_wr_addr : std_logic_vector(15 downto 0);
  signal ctrl_reg_rd_addr : std_logic_vector(15 downto 0);
  signal ctrl_reg_wr_en   : std_logic;
  signal ctrl_reg_rd_en   : std_logic;
  signal ctrl_reg_data_in : std_logic_vector(31 downto 0);
  signal ctrl_reg_data_out : std_logic_vector(31 downto 0);
  signal ctrl_reg_wr_rdy  : std_logic;
  signal ctrl_reg_rd_rdy  : std_logic;
  signal ctrl_reg_wr_valid : std_logic;
  signal ctrl_reg_rd_valid : std_logic;
  signal ctrl_reg_error   : std_logic;
  signal ctrl_low_rw_regs : radif_reg_array_t(0 to C_CTRL_LOW_RW_REG_COUNT - 1)(31 downto 0);
  signal ctrl_low_ro_dummy : radif_reg_array_t(0 to 0)(31 downto 0);
  signal ctrl_high_rw_regs : radif_reg_array_t(0 to C_CTRL_HIGH_RW_REG_COUNT - 1)(31 downto 0);
  signal ctrl_ro_regs     : radif_reg_array_t(0 to C_CTRL_RO_REG_COUNT - 1)(31 downto 0);
  signal ctrl_s_wr_addr   : std_logic_vector((C_CTRL_SLAVE_COUNT * 16) - 1 downto 0);
  signal ctrl_s_rd_addr   : std_logic_vector((C_CTRL_SLAVE_COUNT * 16) - 1 downto 0);
  signal ctrl_s_wr_en     : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal ctrl_s_rd_en     : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal ctrl_s_data_in   : std_logic_vector((C_CTRL_SLAVE_COUNT * 32) - 1 downto 0);
  signal ctrl_s_data_out  : std_logic_vector((C_CTRL_SLAVE_COUNT * 32) - 1 downto 0);
  signal ctrl_s_wr_rdy    : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal ctrl_s_rd_rdy    : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal ctrl_s_wr_valid  : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal ctrl_s_rd_valid  : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal ctrl_s_error     : std_logic_vector(C_CTRL_SLAVE_COUNT - 1 downto 0);
  signal dbg_sda_oen    : std_logic := '1';
  signal control_reg    : std_logic_vector(31 downto 0);
  signal dsp_control_reg : std_logic_vector(31 downto 0);
  signal reset_hold     : std_logic;
  signal dac_enable     : std_logic;
  signal dsp_mode       : std_logic_vector(7 downto 0);
  signal wave_select    : std_logic_vector(7 downto 0);
  signal dsp_control    : std_logic_vector(7 downto 0);
  signal freq0          : unsigned(23 downto 0);
  signal freq1          : unsigned(23 downto 0);
  signal freq2          : unsigned(23 downto 0);
  signal freq3          : unsigned(23 downto 0);
  signal lvol           : std_logic_vector(23 downto 0);
  signal rvol           : std_logic_vector(23 downto 0);
  signal osc0vol        : std_logic_vector(23 downto 0);
  signal osc1vol        : std_logic_vector(23 downto 0);
  signal osc2vol        : std_logic_vector(23 downto 0);
  signal osc3vol        : std_logic_vector(23 downto 0);
  signal osc_pan_reg    : std_logic_vector(31 downto 0);
  signal global_pan_reg : std_logic_vector(31 downto 0);
  signal lfo_control_reg : std_logic_vector(31 downto 0);
  signal lfo_enable_mask : std_logic_vector(3 downto 0);
  signal lfo_wave_select : std_logic_vector(7 downto 0);
  signal lfo_target_word : std_logic_vector(7 downto 0);
  signal osc0_pan       : std_logic_vector(7 downto 0);
  signal osc1_pan       : std_logic_vector(7 downto 0);
  signal osc2_pan       : std_logic_vector(7 downto 0);
  signal osc3_pan       : std_logic_vector(7 downto 0);
  signal global_pan     : std_logic_vector(7 downto 0);
  signal global_pan_mod : std_logic_vector(7 downto 0);
  signal lfo_freq0      : unsigned(23 downto 0);
  signal lfo_freq1      : unsigned(23 downto 0);
  signal lfo_freq2      : unsigned(23 downto 0);
  signal lfo_freq3      : unsigned(23 downto 0);
  signal lfo_depth0     : std_logic_vector(17 downto 0);
  signal lfo_depth1     : std_logic_vector(17 downto 0);
  signal lfo_depth2     : std_logic_vector(17 downto 0);
  signal lfo_depth3     : std_logic_vector(17 downto 0);
  signal lfo_table_wr_en : std_logic := '0';
  signal lfo_table_wr_addr : std_logic_vector(10 downto 0) := (others => '0');
  signal lfo_table_wr_data : std_logic_vector(15 downto 0) := (others => '0');
  signal lfo_table_init_done : std_logic;
  signal lfo_busy       : std_logic;
  signal lfo_valid      : std_logic;
  signal lfo0_sample    : std_logic_vector(23 downto 0);
  signal lfo1_sample    : std_logic_vector(23 downto 0);
  signal lfo2_sample    : std_logic_vector(23 downto 0);
  signal lfo3_sample    : std_logic_vector(23 downto 0);
  signal lfo0_last      : std_logic_vector(23 downto 0) := (others => '0');
  signal lfo1_last      : std_logic_vector(23 downto 0) := (others => '0');
  signal lfo2_last      : std_logic_vector(23 downto 0) := (others => '0');
  signal lfo3_last      : std_logic_vector(23 downto 0) := (others => '0');
  signal lfo_freq_mod_sum : signed(23 downto 0) := (others => '0');
  signal lfo_pan_mod_sum  : signed(23 downto 0) := (others => '0');
  signal lfo_freq_acc   : signed(25 downto 0) := (others => '0');
  signal lfo_pan_acc    : signed(25 downto 0) := (others => '0');
  signal lfo_sum_idx    : integer range 0 to 4 := 4;
  signal lfo_sum_finalize : std_logic := '0';
  signal wave_wr_count  : unsigned(9 downto 0) := (others => '0');
  signal wave_table_wr_en : std_logic := '0';
  signal wave_table_wr_addr : std_logic_vector(9 downto 0) := (others => '0');
  signal wave_table_wr_data : std_logic_vector(15 downto 0) := (others => '0');
  signal wave_table_init_done : std_logic;
  signal wave_table_busy : std_logic;

  signal rpi_cfg_wr_en  : std_logic := '0';
  signal rpi_cfg_count  : unsigned(2 downto 0) := (others => '0');
  signal adc_cfg_wr_en  : std_logic := '0';
  signal dac_cfg_wr_en  : std_logic := '0';
  signal cfg_count      : unsigned(2 downto 0) := (others => '0');
  signal rpi_reg_rd     : std_logic_vector(31 downto 0);
  signal adc_reg_rd     : std_logic_vector(31 downto 0);
  signal dac_reg_rd     : std_logic_vector(31 downto 0);
  signal rpi_reg_wv     : std_logic;
  signal rpi_reg_rv     : std_logic;
  signal adc_reg_wv     : std_logic;
  signal adc_reg_rv     : std_logic;
  signal dac_reg_wv     : std_logic;
  signal dac_reg_rv     : std_logic;
  signal rpi_reg_err    : std_logic;
  signal adc_reg_err    : std_logic;
  signal dac_reg_err    : std_logic;

  signal rpi_axis_data  : std_logic_vector(63 downto 0);
  signal rpi_axis_valid : std_logic;
  signal rpi_axis_last  : std_logic;
  signal rpi_tx_axis_data  : std_logic_vector(63 downto 0);
  signal rpi_tx_axis_valid : std_logic;
  signal rpi_tx_axis_ready : std_logic;
  signal rpi_tx_lane       : std_logic := '0';
  signal rpi_rx_lane       : std_logic := '0';
  signal rpi_tx_lane_sync  : std_logic_vector(2 downto 0) := (others => '0');
  signal rpi_rx_lane_sync  : std_logic_vector(2 downto 0) := (others => '0');
  signal rpi_tx_frame_sys  : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_scope_frame_sys : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_tx_toggle_sys : std_logic := '0';
  signal rpi_tx_toggle_mclk_sync : std_logic_vector(2 downto 0) := (others => '0');
  signal rpi_tx_toggle_mclk_seen : std_logic := '0';
  signal rpi_tx_frame_mclk : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_scope_frame_mclk : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_rx_lane0_mclk : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_rx_lane1_mclk : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_rx_lane0_toggle_mclk : std_logic := '0';
  signal rpi_rx_lane0_toggle_sys_sync : std_logic_vector(2 downto 0) := (others => '0');
  signal rpi_rx_lane0_toggle_sys_seen : std_logic := '0';
  signal rpi_rx_lane0_pulse_sys : std_logic := '0';
  signal dac_enable_mclk_sync : std_logic_vector(2 downto 0) := (others => '0');
  signal rpi_lane0_frame   : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_lane1_frame   : std_logic_vector(63 downto 0) := (others => '0');
  signal rpi_bclk          : std_logic := '0';
  signal rpi_lrck          : std_logic := '0';
  signal rpi_sdata         : std_logic := '0';
  signal adc_axis_data  : std_logic_vector(63 downto 0);
  signal adc_axis_valid : std_logic;
  signal adc_axis_last  : std_logic;
  signal dac_axis_data  : std_logic_vector(63 downto 0);
  signal dac_axis_valid : std_logic;
  signal dac_axis_ready : std_logic;
  signal dac_sdata      : std_logic := '0';

  signal rpi_last_frame : std_logic_vector(63 downto 0) := (others => '0');
  signal adc_last_frame : std_logic_vector(63 downto 0) := (others => '0');
  signal selected_left  : std_logic_vector(23 downto 0) := (others => '0');
  signal selected_right : std_logic_vector(23 downto 0) := (others => '0');
  signal gain_left      : std_logic_vector(23 downto 0);
  signal gain_right     : std_logic_vector(23 downto 0);
  signal gain_valid     : std_logic;
  signal eq_left        : std_logic_vector(23 downto 0);
  signal eq_right       : std_logic_vector(23 downto 0);
  signal eq_valid       : std_logic;
  signal eq_busy        : std_logic;
  signal eq_smoothing   : std_logic;
  signal eq_coeff_wr_en : std_logic := '0';
  signal eq_commit      : std_logic := '0';
  signal eq_control_reg : std_logic_vector(31 downto 0);
  signal scope_control_reg : std_logic_vector(31 downto 0);
  signal scope_left     : std_logic_vector(23 downto 0) := (others => '0');
  signal scope_right    : std_logic_vector(23 downto 0) := (others => '0');
  signal pan_left       : std_logic_vector(23 downto 0);
  signal pan_right      : std_logic_vector(23 downto 0);
  signal pan_valid      : std_logic;
  signal left_gain      : std_logic_vector(17 downto 0);
  signal right_gain     : std_logic_vector(17 downto 0);
  signal global_left_gain : std_logic_vector(17 downto 0);
  signal global_right_gain : std_logic_vector(17 downto 0);

  signal osc0_sample    : std_logic_vector(23 downto 0);
  signal osc1_sample    : std_logic_vector(23 downto 0);
  signal osc2_sample    : std_logic_vector(23 downto 0);
  signal osc3_sample    : std_logic_vector(23 downto 0);
  signal osc_quad_valid  : std_logic;
  signal osc_quad_busy   : std_logic;
  signal osc0_gain      : std_logic_vector(17 downto 0);
  signal osc1_gain      : std_logic_vector(17 downto 0);
  signal osc2_gain      : std_logic_vector(17 downto 0);
  signal osc3_gain      : std_logic_vector(17 downto 0);
  signal osc0_freq_mod  : std_logic_vector(23 downto 0);
  signal osc1_freq_mod  : std_logic_vector(23 downto 0);
  signal osc2_freq_mod  : std_logic_vector(23 downto 0);
  signal osc3_freq_mod  : std_logic_vector(23 downto 0);
  signal osc_valid      : std_logic_vector(3 downto 0);
  signal osc_all_valid  : std_logic;
  signal synth_pan_left : std_logic_vector(23 downto 0);
  signal synth_pan_right : std_logic_vector(23 downto 0);
  signal synth_pan_valid : std_logic;
  signal synth_pan_busy : std_logic;
  signal global_pan_busy : std_logic;
  signal synth_left     : std_logic_vector(23 downto 0) := (others => '0');
  signal synth_right    : std_logic_vector(23 downto 0) := (others => '0');
  signal poly_cfg_wr_en : std_logic := '0';
  signal poly_cfg_addr  : std_logic_vector(7 downto 0) := (others => '0');
  signal poly_cfg_rd_en : std_logic := '0';
  signal poly_cfg_rd_addr : std_logic_vector(7 downto 0) := (others => '0');
  signal poly_cfg_rd_data : std_logic_vector(31 downto 0);
  signal poly_cfg_wr_valid : std_logic := '0';
  signal poly_cfg_rd_valid : std_logic;
  signal poly_cfg_error : std_logic;
  signal poly_sample    : std_logic_vector(23 downto 0);
  signal poly_valid     : std_logic;
  signal poly_busy      : std_logic;
  signal poly_table_init_done : std_logic;
  signal poly_last_sample : std_logic_vector(23 downto 0) := (others => '0');
  signal dbg_reg_wr_addr : std_logic_vector(15 downto 0) := (others => '0');
  signal dbg_reg_rd_addr : std_logic_vector(15 downto 0) := (others => '0');
  signal dbg_reg_wr_en  : std_logic := '0';
  signal dbg_reg_rd_en  : std_logic := '0';
  signal dbg_reg_data_in : std_logic_vector(31 downto 0) := (others => '0');
  signal dbg_reg_data_out : std_logic_vector(31 downto 0);
  signal dbg_reg_wr_rdy : std_logic;
  signal dbg_reg_rd_rdy : std_logic;
  signal dbg_reg_wr_valid : std_logic;
  signal dbg_reg_rd_valid : std_logic;
  signal dbg_reg_error : std_logic;
  signal dbg_irq       : std_logic;
  signal dbg_sample    : std_logic_vector(63 downto 0);
  signal dbg_event     : std_logic_vector(7 downto 0);

  function pack_frame(left_sample : std_logic_vector(23 downto 0); right_sample : std_logic_vector(23 downto 0))
    return std_logic_vector is
    variable frame : std_logic_vector(63 downto 0) := (others => '0');
  begin
    frame(55 downto 32) := left_sample;
    frame(23 downto 0) := right_sample;
    return frame;
  end function;

  function frame_left(frame : std_logic_vector(63 downto 0)) return std_logic_vector is
  begin
    return frame(55 downto 32);
  end function;

  function frame_right(frame : std_logic_vector(63 downto 0)) return std_logic_vector is
  begin
    return frame(23 downto 0);
  end function;

  function pack_pi_frame(left_sample : std_logic_vector(23 downto 0);
                         right_sample : std_logic_vector(23 downto 0);
                         lane : std_logic) return std_logic_vector is
    variable frame : std_logic_vector(63 downto 0) := (others => '0');
    variable marker : std_logic_vector(7 downto 0);
  begin
    marker := C_RPI_MARKER_PREFIX & "000" & lane;
    frame(63 downto 32) := left_sample & marker;
    frame(31 downto 0) := right_sample & marker;
    return frame;
  end function;

  function rpi_marker_lane(frame : std_logic_vector(63 downto 0);
                           fallback_lane : std_logic) return std_logic is
    variable left_marker : std_logic_vector(7 downto 0);
    variable right_marker : std_logic_vector(7 downto 0);
  begin
    left_marker := frame(39 downto 32);
    right_marker := frame(7 downto 0);
    if left_marker(7 downto 4) = C_RPI_MARKER_PREFIX and
       right_marker(7 downto 4) = C_RPI_MARKER_PREFIX and
       left_marker(0) = right_marker(0) then
      return left_marker(0);
    elsif left_marker(7 downto 4) = C_RPI_MARKER_PREFIX then
      return left_marker(0);
    elsif right_marker(7 downto 4) = C_RPI_MARKER_PREFIX then
      return right_marker(0);
    end if;
    return fallback_lane;
  end function;

  function gain_or_unity(value : std_logic_vector(23 downto 0)) return std_logic_vector is
  begin
    if value = x"000000" then
      return C_UNITY_GAIN;
    end if;
    return value(23 downto 6);
  end function;

  function lfo_target(idx : natural; packed : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    case idx is
      when 0 => return packed(1 downto 0);
      when 1 => return packed(3 downto 2);
      when 2 => return packed(5 downto 4);
      when others => return packed(7 downto 6);
    end case;
  end function;

  function lfo_sample(idx : natural; s0 : std_logic_vector; s1 : std_logic_vector; s2 : std_logic_vector; s3 : std_logic_vector)
    return signed is
  begin
    case idx is
      when 0 => return signed(s0);
      when 1 => return signed(s1);
      when 2 => return signed(s2);
      when others => return signed(s3);
    end case;
  end function;

  function add_lfo_to_freq(base_freq : unsigned(23 downto 0); mod_value : signed(23 downto 0))
    return std_logic_vector is
    variable sum_v : signed(24 downto 0);
  begin
    sum_v := signed('0' & std_logic_vector(base_freq)) + resize(mod_value, 25);
    if sum_v < 0 then
      return std_logic_vector(to_unsigned(0, 24));
    elsif sum_v > to_signed((2 ** 24) - 1, 25) then
      return std_logic_vector(to_unsigned((2 ** 24) - 1, 24));
    end if;
    return std_logic_vector(sum_v(23 downto 0));
  end function;

  function add_lfo_to_pan(base_pan : std_logic_vector(7 downto 0); mod_value : signed(23 downto 0))
    return std_logic_vector is
    variable sum_v : signed(9 downto 0);
    variable base_v : std_logic_vector(9 downto 0);
  begin
    base_v := "00" & base_pan;
    sum_v := signed(base_v) + resize(mod_value(23 downto 16), 10);
    if sum_v < 0 then
      return x"00";
    elsif sum_v > to_signed(255, 10) then
      return x"ff";
    end if;
    return std_logic_vector(sum_v(7 downto 0));
  end function;

begin
  SCL_IN <= 'Z';
  SDA_IN <= '0' when i2c_sda_oen = '0' or dbg_sda_oen = '0' else 'Z';

  MUTEEN <= control_reg(1);
  I2S_BCK_RPI <= rpi_bclk;
  I2S_DOUT_PI <= rpi_sdata;
  I2S_LRCK_RPI <= rpi_lrck;
  I2S_SDA_DAC <= dac_sdata;
  FPGA75 <= I2S_BCK;
  FPGA77 <= rpi_sdata;
  FPGA71 <= I2S_LRCK_DAC;
  FPGA67 <= adc_axis_valid;
  dbg_sample <= rpi_lane0_frame(15 downto 0) & adc_axis_data(15 downto 0) &
                selected_left(15 downto 0) & selected_right(15 downto 0);
  dbg_event <= rpi_rx_lane0_pulse_sys & adc_axis_valid & dac_axis_valid & dac_axis_ready &
               rpi_rx_lane_sync(2) & rpi_tx_lane_sync(2) & dsp_control(3) & dsp_control(1);

  reset_hold <= control_reg(0);
  dac_enable <= control_reg(8);
  rstn_i <= fabric_rstn and not reset_hold;
  rst_i <= not rstn_i;
  rpi_i2s_rstn <= rpi_i2s_rstn_pipe(1);
  adc_i2s_rstn <= adc_i2s_rstn_pipe(1);
  dac_i2s_rstn <= dac_i2s_rstn_pipe(1);
  control_reg <= ctrl_low_rw_regs(C_REG_CONTROL);
  dsp_control_reg <= ctrl_low_rw_regs(C_REG_DSP_CONTROL);
  dsp_mode <= dsp_control_reg(7 downto 0);
  dsp_control <= dsp_control_reg(15 downto 8);
  wave_select <= dsp_control_reg(23 downto 16);
  freq0 <= unsigned(ctrl_low_rw_regs(C_REG_FREQ0)(23 downto 0));
  freq1 <= unsigned(ctrl_low_rw_regs(C_REG_FREQ1)(23 downto 0));
  freq2 <= unsigned(ctrl_low_rw_regs(C_REG_FREQ2)(23 downto 0));
  freq3 <= unsigned(ctrl_low_rw_regs(C_REG_FREQ3)(23 downto 0));
  lvol <= ctrl_low_rw_regs(C_REG_LEFT_GAIN)(23 downto 0);
  rvol <= ctrl_low_rw_regs(C_REG_RIGHT_GAIN)(23 downto 0);
  osc0vol <= ctrl_low_rw_regs(C_REG_OSC0_GAIN)(23 downto 0);
  osc1vol <= ctrl_low_rw_regs(C_REG_OSC1_GAIN)(23 downto 0);
  osc2vol <= ctrl_low_rw_regs(C_REG_OSC2_GAIN)(23 downto 0);
  osc3vol <= ctrl_low_rw_regs(C_REG_OSC3_GAIN)(23 downto 0);
  osc_pan_reg <= ctrl_low_rw_regs(C_REG_OSC_PAN);
  global_pan_reg <= ctrl_low_rw_regs(C_REG_GLOBAL_PAN);
  lfo_control_reg <= ctrl_high_rw_regs(C_HIGH_REG_LFO_CONTROL);
  eq_control_reg <= ctrl_high_rw_regs(C_HIGH_REG_EQ_CONTROL);
  scope_control_reg <= ctrl_high_rw_regs(C_HIGH_REG_SCOPE_CONTROL);
  lfo_enable_mask <= lfo_control_reg(3 downto 0);
  lfo_wave_select <= lfo_control_reg(15 downto 8);
  lfo_target_word <= lfo_control_reg(23 downto 16);
  lfo_freq0 <= unsigned(ctrl_high_rw_regs(C_HIGH_LFO_FREQ_BASE + 0)(23 downto 0));
  lfo_freq1 <= unsigned(ctrl_high_rw_regs(C_HIGH_LFO_FREQ_BASE + 1)(23 downto 0));
  lfo_freq2 <= unsigned(ctrl_high_rw_regs(C_HIGH_LFO_FREQ_BASE + 2)(23 downto 0));
  lfo_freq3 <= unsigned(ctrl_high_rw_regs(C_HIGH_LFO_FREQ_BASE + 3)(23 downto 0));
  lfo_depth0 <= ctrl_high_rw_regs(C_HIGH_LFO_DEPTH_BASE + 0)(17 downto 0) when lfo_enable_mask(0) = '1' else (others => '0');
  lfo_depth1 <= ctrl_high_rw_regs(C_HIGH_LFO_DEPTH_BASE + 1)(17 downto 0) when lfo_enable_mask(1) = '1' else (others => '0');
  lfo_depth2 <= ctrl_high_rw_regs(C_HIGH_LFO_DEPTH_BASE + 2)(17 downto 0) when lfo_enable_mask(2) = '1' else (others => '0');
  lfo_depth3 <= ctrl_high_rw_regs(C_HIGH_LFO_DEPTH_BASE + 3)(17 downto 0) when lfo_enable_mask(3) = '1' else (others => '0');
  osc0_pan <= osc_pan_reg(7 downto 0);
  osc1_pan <= osc_pan_reg(15 downto 8);
  osc2_pan <= osc_pan_reg(23 downto 16);
  osc3_pan <= osc_pan_reg(31 downto 24);
  global_pan <= global_pan_reg(7 downto 0);
  wave_wr_count <= unsigned(ctrl_low_rw_regs(C_REG_WAVE_CONTROL)(9 downto 0));
  left_gain <= gain_or_unity(lvol);
  right_gain <= gain_or_unity(rvol);
  osc0_gain <= gain_or_unity(osc0vol);
  osc1_gain <= gain_or_unity(osc1vol);
  osc2_gain <= gain_or_unity(osc2vol);
  osc3_gain <= gain_or_unity(osc3vol);
  osc_all_valid <= '1' when osc_valid = "1111" else '0';
  wave_table_busy <= osc_quad_busy;
  ctrl_ro_regs(0) <= x"46504741";
  ctrl_ro_regs(1) <= x"00000202";
  ctrl_ro_regs(2) <= x"0000" & "0" & lfo_table_init_done & lfo_busy & lfo_valid &
                     poly_table_init_done & wave_table_init_done & wave_table_busy &
                     eq_smoothing & eq_busy & poly_busy & poly_valid & clocks_locked & fabric_rstn &
                     rstn_i & dac_axis_ready & dac_axis_valid;
  ctrl_ro_regs(3) <= (31 downto 10 => '0') & std_logic_vector(wave_wr_count);
  ctrl_ro_regs(4) <= x"000000" & dbg_irq & dbg_reg_error & ctrl_reg_error & "00000";
  ctrl_ro_regs(5) <= rpi_lane0_frame(31 downto 0);
  ctrl_ro_regs(6) <= adc_axis_data(31 downto 0);
  ctrl_ro_regs(7) <= scope_control_reg;
  ctrl_low_ro_dummy(0) <= (others => '0');
  poly_cfg_wr_en <= ctrl_s_wr_en(1);
  poly_cfg_addr <= "00" & ctrl_s_wr_addr(23 downto 18);
  poly_cfg_rd_en <= ctrl_s_rd_en(1);
  poly_cfg_rd_addr <= "00" & ctrl_s_rd_addr(23 downto 18);
  ctrl_s_wr_rdy(1) <= '1';
  ctrl_s_rd_rdy(1) <= '1';
  ctrl_s_wr_valid(1) <= poly_cfg_wr_valid;
  ctrl_s_rd_valid(1) <= poly_cfg_rd_valid;
  ctrl_s_error(1) <= poly_cfg_error;
  ctrl_s_data_out(63 downto 32) <= poly_cfg_rd_data;

  process(all)
    variable wr_word : unsigned(13 downto 0);
  begin
    wr_word := unsigned(ctrl_reg_wr_addr(15 downto 2));
    eq_coeff_wr_en <= '0';
    eq_commit <= '0';
    wave_table_wr_en <= '0';
    wave_table_wr_addr <= ctrl_low_rw_regs(C_REG_WAVE_CONTROL)(9 downto 0);
    wave_table_wr_data <= ctrl_reg_data_in(15 downto 0);
    lfo_table_wr_en <= '0';
    lfo_table_wr_addr <= ctrl_high_rw_regs(C_HIGH_REG_LFO_WAVE_CONTROL)(10 downto 0);
    lfo_table_wr_data <= ctrl_reg_data_in(15 downto 0);

    if ctrl_reg_wr_en = '1' then
      if wr_word = to_unsigned(C_REG_WAVE_DATA, wr_word'length) then
        wave_table_wr_en <= '1';
      elsif wr_word = to_unsigned(C_REG_LFO_WAVE_DATA, wr_word'length) then
        lfo_table_wr_en <= '1';
      elsif wr_word = to_unsigned(C_REG_EQ_COEFF_DATA, wr_word'length) then
        eq_coeff_wr_en <= '1';
      elsif wr_word = to_unsigned(C_REG_EQ_CONTROL, wr_word'length) and ctrl_reg_data_in(8) = '1' then
        eq_commit <= '1';
      end if;
    end if;
  end process;

  process(sysclk_i)
  begin
    if rising_edge(sysclk_i) then
      poly_cfg_wr_valid <= '0';
      if fabric_rstn = '0' then
        poly_cfg_wr_valid <= '0';
      elsif ctrl_s_wr_en(1) = '1' then
        poly_cfg_wr_valid <= '1';
      end if;
    end if;
  end process;

  u_mclk_forward : ODDR
    generic map (
      INIT => '0',
      TXCLK_POL => '0'
    )
    port map (
      Q0 => MCLKXCO_OUT,
      Q1 => open,
      D0 => '1',
      D1 => '0',
      TX => '0',
      CLK => mclk_i
    );

  u_pll : PLLA
    generic map (
      FCLKIN => "50",
      IDIV_SEL => 1,
      FBDIV_SEL => 1,
      ODIV0_SEL => 81,
      ODIV0_FRAC_SEL => 3,
      ODIV1_SEL => 40,
      ODIV2_SEL => 10,
      ODIV3_SEL => 8,
      ODIV4_SEL => 8,
      ODIV5_SEL => 8,
      ODIV6_SEL => 8,
      MDIV_SEL => 20,
      CLKOUT0_EN => "TRUE",
      CLKOUT1_EN => "FALSE",
      CLKOUT2_EN => "TRUE",
      CLKOUT3_EN => "FALSE",
      CLKOUT4_EN => "FALSE",
      CLKOUT5_EN => "FALSE",
      CLKOUT6_EN => "FALSE",
      CLKFB_SEL => "INTERNAL"
    )
    port map (
      CLKIN => CLK_50M,
      CLKFB => '0',
      RESET => '0',
      PLLPWD => '0',
      RESET_I => '0',
      RESET_O => '0',
      PSSEL => "000",
      PSDIR => '0',
      PSPULSE => '0',
      SSCPOL => '0',
      SSCON => '0',
      SSCMDSEL => "0000000",
      SSCMDSEL_FRAC => "000",
      MDCLK => '0',
      MDOPC => "00",
      MDAINC => '0',
      MDWDI => "00000000",
      MDRDO => mdrdo_unused,
      LOCK => clocks_locked,
      CLKOUT0 => mclk_i,
      CLKOUT1 => clkout1_unused,
      CLKOUT2 => sysclk_i,
      CLKOUT3 => open,
      CLKOUT4 => open,
      CLKOUT5 => open,
      CLKOUT6 => open,
      CLKFBOUT => clkfb_unused
    );

  process(sysclk_i)
  begin
    if rising_edge(sysclk_i) then
      if clocks_locked = '0' then
        fabric_rstn <= '0';
        sys_rst_count <= (others => '0');
      elsif sys_rst_count < to_unsigned(50, sys_rst_count'length) then
        fabric_rstn <= '0';
        sys_rst_count <= sys_rst_count + 1;
      else
        fabric_rstn <= '1';
      end if;
    end if;
  end process;

  process(sysclk_i)
  begin
    if rising_edge(sysclk_i) then
      if rstn_i = '0' then
        adc_i2s_rstn_pipe <= (others => '0');
        dac_i2s_rstn_pipe <= (others => '0');
      else
        adc_i2s_rstn_pipe <= adc_i2s_rstn_pipe(0) & '1';
        dac_i2s_rstn_pipe <= dac_i2s_rstn_pipe(0) & '1';
      end if;
    end if;
  end process;

  process(mclk_i)
  begin
    if rising_edge(mclk_i) then
      if rstn_i = '0' then
        rpi_i2s_rstn_pipe <= (others => '0');
      else
        rpi_i2s_rstn_pipe <= rpi_i2s_rstn_pipe(0) & '1';
      end if;
    end if;
  end process;

  u_i2c_reg_bridge : entity work.radif_i2c_slave_to_reg
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      I2C_ADDR => "0010010",
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => fabric_rstn,
      i2c_scl_i => SCL_IN,
      i2c_sda_i => SDA_IN,
      i2c_sda_oen => i2c_sda_oen,
      reg_wr_addr => ctrl_reg_wr_addr,
      reg_rd_addr => ctrl_reg_rd_addr,
      reg_wr_en => ctrl_reg_wr_en,
      reg_rd_en => ctrl_reg_rd_en,
      reg_data_in => ctrl_reg_data_in,
      reg_data_out => ctrl_reg_data_out,
      reg_wr_rdy => ctrl_reg_wr_rdy,
      reg_rd_rdy => ctrl_reg_rd_rdy,
      reg_wr_valid => ctrl_reg_wr_valid,
      reg_rd_valid => ctrl_reg_rd_valid,
      reg_error => ctrl_reg_error
    );

  u_ctrl_interconnect : entity work.radif_reg_interconnect
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      SLAVE_COUNT => C_CTRL_SLAVE_COUNT,
      SLAVE_BASE_ADDRS => x"014000400000",
      SLAVE_ADDR_MASKS => x"FFC0FF00FFC0",
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => fabric_rstn,
      wr_addr_i => ctrl_reg_wr_addr,
      rd_addr_i => ctrl_reg_rd_addr,
      wr_en_i => ctrl_reg_wr_en,
      rd_en_i => ctrl_reg_rd_en,
      data_in_i => ctrl_reg_data_in,
      data_out_o => ctrl_reg_data_out,
      wr_rdy_o => ctrl_reg_wr_rdy,
      rd_rdy_o => ctrl_reg_rd_rdy,
      wr_valid_o => ctrl_reg_wr_valid,
      rd_valid_o => ctrl_reg_rd_valid,
      error_o => ctrl_reg_error,
      s_wr_addr_o => ctrl_s_wr_addr,
      s_rd_addr_o => ctrl_s_rd_addr,
      s_wr_en_o => ctrl_s_wr_en,
      s_rd_en_o => ctrl_s_rd_en,
      s_data_in_o => ctrl_s_data_in,
      s_data_out_i => ctrl_s_data_out,
      s_wr_rdy_i => ctrl_s_wr_rdy,
      s_rd_rdy_i => ctrl_s_rd_rdy,
      s_wr_valid_i => ctrl_s_wr_valid,
      s_rd_valid_i => ctrl_s_rd_valid,
      s_error_i => ctrl_s_error
    );

  u_ctrl_low_regs : entity work.radif_reg_bank
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      READ_ONLY_REG_COUNT => 1,
      READ_WRITE_REG_COUNT => C_CTRL_LOW_RW_REG_COUNT,
      PIPELINED_READ => true,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => fabric_rstn,
      wr_addr => ctrl_s_wr_addr(15 downto 0),
      rd_addr => ctrl_s_rd_addr(15 downto 0),
      wr_en => ctrl_s_wr_en(0),
      rd_en => ctrl_s_rd_en(0),
      data_in => ctrl_s_data_in(31 downto 0),
      data_out => ctrl_s_data_out(31 downto 0),
      read_only_regs_i => ctrl_low_ro_dummy,
      read_write_regs_o => ctrl_low_rw_regs,
      wr_rdy => ctrl_s_wr_rdy(0),
      rd_rdy => ctrl_s_rd_rdy(0),
      wr_valid => ctrl_s_wr_valid(0),
      rd_valid => ctrl_s_rd_valid(0),
      error => ctrl_s_error(0)
    );

  u_ctrl_high_regs : entity work.radif_reg_bank
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      READ_ONLY_REG_COUNT => C_CTRL_RO_REG_COUNT,
      READ_WRITE_REG_COUNT => C_CTRL_HIGH_RW_REG_COUNT,
      PIPELINED_READ => true,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => fabric_rstn,
      wr_addr => ctrl_s_wr_addr(47 downto 32),
      rd_addr => ctrl_s_rd_addr(47 downto 32),
      wr_en => ctrl_s_wr_en(2),
      rd_en => ctrl_s_rd_en(2),
      data_in => ctrl_s_data_in(95 downto 64),
      data_out => ctrl_s_data_out(95 downto 64),
      read_only_regs_i => ctrl_ro_regs,
      read_write_regs_o => ctrl_high_rw_regs,
      wr_rdy => ctrl_s_wr_rdy(2),
      rd_rdy => ctrl_s_rd_rdy(2),
      wr_valid => ctrl_s_wr_valid(2),
      rd_valid => ctrl_s_rd_valid(2),
      error => ctrl_s_error(2)
    );

  u_dbg_i2c_reg_bridge : entity work.radif_i2c_slave_to_reg
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      I2C_ADDR => "1000010",
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => fabric_rstn,
      i2c_scl_i => SCL_IN,
      i2c_sda_i => SDA_IN,
      i2c_sda_oen => dbg_sda_oen,
      reg_wr_addr => dbg_reg_wr_addr,
      reg_rd_addr => dbg_reg_rd_addr,
      reg_wr_en => dbg_reg_wr_en,
      reg_rd_en => dbg_reg_rd_en,
      reg_data_in => dbg_reg_data_in,
      reg_data_out => dbg_reg_data_out,
      reg_wr_rdy => dbg_reg_wr_rdy,
      reg_rd_rdy => dbg_reg_rd_rdy,
      reg_wr_valid => dbg_reg_wr_valid,
      reg_rd_valid => dbg_reg_rd_valid,
      reg_error => dbg_reg_error
    );

  u_debug_hub : entity work.RadDebugHub
    generic map (
      DATA_WIDTH => 32,
      REG_ADDR_WIDTH => 16,
      SAMPLE_WIDTH => 64,
      EVENT_WIDTH => 8,
      DEPTH => 256,
      ADDR_WIDTH => 8,
      CMD_LANES => 4,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      sample_clk => sysclk_i,
      sample_rstn => rstn_i,
      sample_i => dbg_sample,
      event_i => dbg_event,
      irq_o => dbg_irq,
      reg_clk => sysclk_i,
      reg_rstn => rstn_i,
      reg_wr_addr => dbg_reg_wr_addr,
      reg_rd_addr => dbg_reg_rd_addr,
      reg_wr_en => dbg_reg_wr_en,
      reg_rd_en => dbg_reg_rd_en,
      reg_data_in => dbg_reg_data_in,
      reg_data_out => dbg_reg_data_out,
      reg_wr_rdy => dbg_reg_wr_rdy,
      reg_rd_rdy => dbg_reg_rd_rdy,
      reg_wr_valid => dbg_reg_wr_valid,
      reg_rd_valid => dbg_reg_rd_valid,
      reg_error => dbg_reg_error
    );

  process(sysclk_i)
  begin
    if rising_edge(sysclk_i) then
      if rstn_i = '0' then
        cfg_count <= (others => '0');
        adc_cfg_wr_en <= '0';
        dac_cfg_wr_en <= '0';
      else
        adc_cfg_wr_en <= '0';
        dac_cfg_wr_en <= '0';
        if cfg_count = to_unsigned(0, cfg_count'length) then
          adc_cfg_wr_en <= '1';
          dac_cfg_wr_en <= '1';
          cfg_count <= cfg_count + 1;
        elsif cfg_count < to_unsigned(7, cfg_count'length) then
          cfg_count <= cfg_count + 1;
        end if;
      end if;
    end if;
  end process;

  process(mclk_i)
  begin
    if rising_edge(mclk_i) then
      if rpi_i2s_rstn = '0' then
        rpi_cfg_count <= (others => '0');
        rpi_cfg_wr_en <= '0';
      else
        rpi_cfg_wr_en <= '0';
        if rpi_cfg_count = to_unsigned(0, rpi_cfg_count'length) then
          rpi_cfg_wr_en <= '1';
          rpi_cfg_count <= rpi_cfg_count + 1;
        elsif rpi_cfg_count < to_unsigned(7, rpi_cfg_count'length) then
          rpi_cfg_count <= rpi_cfg_count + 1;
        end if;
      end if;
    end if;
  end process;

  process(mclk_i)
  begin
    if rising_edge(mclk_i) then
      if rpi_i2s_rstn = '0' then
        rpi_rx_lane <= '0';
        rpi_tx_lane <= '0';
        rpi_tx_toggle_mclk_sync <= (others => '0');
        rpi_tx_toggle_mclk_seen <= '0';
        rpi_tx_frame_mclk <= (others => '0');
        rpi_scope_frame_mclk <= (others => '0');
        rpi_rx_lane0_mclk <= (others => '0');
        rpi_rx_lane1_mclk <= (others => '0');
        rpi_rx_lane0_toggle_mclk <= '0';
        dac_enable_mclk_sync <= (others => '0');
      else
        dac_enable_mclk_sync <= dac_enable_mclk_sync(1 downto 0) & dac_enable;
        rpi_tx_toggle_mclk_sync <= rpi_tx_toggle_mclk_sync(1 downto 0) & rpi_tx_toggle_sys;

        if rpi_tx_toggle_mclk_sync(2) /= rpi_tx_toggle_mclk_seen then
          rpi_tx_toggle_mclk_seen <= rpi_tx_toggle_mclk_sync(2);
          rpi_tx_frame_mclk <= rpi_tx_frame_sys;
          rpi_scope_frame_mclk <= rpi_scope_frame_sys;
        end if;

        if rpi_axis_valid = '1' then
          if rpi_marker_lane(rpi_axis_data, rpi_rx_lane) = '0' then
            rpi_rx_lane0_mclk <= rpi_axis_data;
            rpi_rx_lane0_toggle_mclk <= not rpi_rx_lane0_toggle_mclk;
          else
            rpi_rx_lane1_mclk <= rpi_axis_data;
          end if;
          rpi_rx_lane <= not rpi_rx_lane;
        end if;

        if rpi_tx_axis_valid = '1' and rpi_tx_axis_ready = '1' then
          rpi_tx_lane <= not rpi_tx_lane;
        end if;
      end if;
    end if;
  end process;

  process(all)
    variable left_sel : std_logic_vector(3 downto 0);
    variable right_sel : std_logic_vector(3 downto 0);
  begin
    left_sel := scope_control_reg(3 downto 0);
    right_sel := scope_control_reg(7 downto 4);

    case left_sel is
      when x"1" => scope_left <= frame_left(rpi_lane0_frame);
      when x"2" => scope_left <= frame_left(rpi_lane1_frame);
      when x"3" => scope_left <= frame_left(adc_last_frame);
      when x"4" => scope_left <= selected_left;
      when x"5" => scope_left <= gain_left;
      when x"6" => scope_left <= synth_left;
      when x"7" => scope_left <= poly_last_sample;
      when x"8" => scope_left <= lfo0_last;
      when x"9" => scope_left <= lfo1_last;
      when x"A" => scope_left <= lfo2_last;
      when x"B" => scope_left <= lfo3_last;
      when others => scope_left <= (others => '0');
    end case;

    case right_sel is
      when x"1" => scope_right <= frame_right(rpi_lane0_frame);
      when x"2" => scope_right <= frame_right(rpi_lane1_frame);
      when x"3" => scope_right <= frame_right(adc_last_frame);
      when x"4" => scope_right <= selected_right;
      when x"5" => scope_right <= gain_right;
      when x"6" => scope_right <= synth_right;
      when x"7" => scope_right <= poly_last_sample;
      when x"8" => scope_right <= lfo0_last;
      when x"9" => scope_right <= lfo1_last;
      when x"A" => scope_right <= lfo2_last;
      when x"B" => scope_right <= lfo3_last;
      when others => scope_right <= (others => '0');
    end case;
  end process;

  u_rpi_i2s : entity work.radif_i2s_axis
    generic map (
      SAMPLE_WIDTH => 32,
      AXIS_DATA_WIDTH => 64,
      REG_DATA_WIDTH => 32,
      REG_ADDR_WIDTH => 16,
      DEFAULT_BCLK_DIV => C_RPI_BCLK_DIV,
      DEFAULT_LRCK_BITS => C_RPI_LRCK_BITS,
      USE_EXTERNAL_MCLK => false,
      NO_MCLK => true,
      USE_EXTERNAL_BCLK => false,
      ENABLE_I2S_TO_AXIS => true,
      ENABLE_AXIS_TO_I2S => true,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => mclk_i,
      rstn => rpi_i2s_rstn,
      reg_wr_addr => (others => '0'),
      reg_rd_addr => (others => '0'),
      reg_wr_en => rpi_cfg_wr_en,
      reg_rd_en => '0',
      reg_data_in => x"00000003",
      reg_data_out => rpi_reg_rd,
      reg_wr_rdy => open,
      reg_rd_rdy => open,
      reg_wr_valid => rpi_reg_wv,
      reg_rd_valid => rpi_reg_rv,
      reg_error => rpi_reg_err,
      i2s_mclk_i => mclk_i,
      i2s_mclk_o => open,
      i2s_mclk_oe => open,
      i2s_bclk_i => '0',
      i2s_bclk_o => rpi_bclk,
      i2s_bclk_oe => open,
      i2s_lrck_i => '0',
      i2s_lrck_o => rpi_lrck,
      i2s_lrck_oe => open,
      i2s_sdata_i => I2S_SDA_IN_RPI,
      i2s_sdata_o => rpi_sdata,
      i2s_sdata_oe => open,
      m_axis_tdata => rpi_axis_data,
      m_axis_tvalid => rpi_axis_valid,
      m_axis_tready => '1',
      m_axis_tlast => rpi_axis_last,
      s_axis_tdata => rpi_tx_axis_data,
      s_axis_tvalid => rpi_tx_axis_valid,
      s_axis_tready => rpi_tx_axis_ready,
      s_axis_tlast => '1'
    );

  u_dac_i2s : entity work.radif_i2s_axis
    generic map (
      SAMPLE_WIDTH => 24,
      AXIS_DATA_WIDTH => 64,
      REG_DATA_WIDTH => 32,
      REG_ADDR_WIDTH => 16,
      USE_EXTERNAL_MCLK => false,
      NO_MCLK => true,
      USE_EXTERNAL_BCLK => true,
      ENABLE_I2S_TO_AXIS => false,
      ENABLE_AXIS_TO_I2S => true,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => dac_i2s_rstn,
      reg_wr_addr => (others => '0'),
      reg_rd_addr => (others => '0'),
      reg_wr_en => dac_cfg_wr_en,
      reg_rd_en => '0',
      reg_data_in => x"00000002",
      reg_data_out => dac_reg_rd,
      reg_wr_rdy => open,
      reg_rd_rdy => open,
      reg_wr_valid => dac_reg_wv,
      reg_rd_valid => dac_reg_rv,
      reg_error => dac_reg_err,
      i2s_mclk_i => mclk_i,
      i2s_mclk_o => open,
      i2s_mclk_oe => open,
      i2s_bclk_i => I2S_BCK,
      i2s_bclk_o => open,
      i2s_bclk_oe => open,
      i2s_lrck_i => I2S_LRCK_DAC,
      i2s_lrck_o => open,
      i2s_lrck_oe => open,
      i2s_sdata_i => '0',
      i2s_sdata_o => dac_sdata,
      i2s_sdata_oe => open,
      m_axis_tdata => open,
      m_axis_tvalid => open,
      m_axis_tready => '1',
      m_axis_tlast => open,
      s_axis_tdata => dac_axis_data,
      s_axis_tvalid => dac_axis_valid,
      s_axis_tready => dac_axis_ready,
      s_axis_tlast => '1'
    );

  u_adc_i2s : entity work.radif_i2s_axis
    generic map (
      SAMPLE_WIDTH => 24,
      AXIS_DATA_WIDTH => 64,
      REG_DATA_WIDTH => 32,
      REG_ADDR_WIDTH => 16,
      USE_EXTERNAL_MCLK => false,
      NO_MCLK => true,
      USE_EXTERNAL_BCLK => true,
      ENABLE_I2S_TO_AXIS => true,
      ENABLE_AXIS_TO_I2S => false,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => adc_i2s_rstn,
      reg_wr_addr => (others => '0'),
      reg_rd_addr => (others => '0'),
      reg_wr_en => adc_cfg_wr_en,
      reg_rd_en => '0',
      reg_data_in => x"00000001",
      reg_data_out => adc_reg_rd,
      reg_wr_rdy => open,
      reg_rd_rdy => open,
      reg_wr_valid => adc_reg_wv,
      reg_rd_valid => adc_reg_rv,
      reg_error => adc_reg_err,
      i2s_mclk_i => mclk_i,
      i2s_mclk_o => open,
      i2s_mclk_oe => open,
      i2s_bclk_i => I2S_BCK,
      i2s_bclk_o => open,
      i2s_bclk_oe => open,
      i2s_lrck_i => I2S_LRCK_ADC,
      i2s_lrck_o => open,
      i2s_lrck_oe => open,
      i2s_sdata_i => I2S_SDA_ADC,
      i2s_sdata_o => open,
      i2s_sdata_oe => open,
      m_axis_tdata => adc_axis_data,
      m_axis_tvalid => adc_axis_valid,
      m_axis_tready => '1',
      m_axis_tlast => adc_axis_last,
      s_axis_tdata => (others => '0'),
      s_axis_tvalid => '0',
      s_axis_tready => open,
      s_axis_tlast => '0'
    );

  u_lfo : entity work.raddsp_audio_quad_lfo_wavetable
    generic map (
      SAMPLE_WIDTH => 24,
      WAVE_WIDTH => 16,
      PHASE_WIDTH => 24,
      TABLE_ADDR_WIDTH => 9,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15
    )
    port map (
      clk => sysclk_i,
      rst => rst_i,
      sample_ce_i => dac_axis_ready,
      phase_inc0_i => std_logic_vector(lfo_freq0),
      phase_inc1_i => std_logic_vector(lfo_freq1),
      phase_inc2_i => std_logic_vector(lfo_freq2),
      phase_inc3_i => std_logic_vector(lfo_freq3),
      wave_select_i => lfo_wave_select,
      depth0_i => lfo_depth0,
      depth1_i => lfo_depth1,
      depth2_i => lfo_depth2,
      depth3_i => lfo_depth3,
      table_wr_en_i => lfo_table_wr_en,
      table_wr_addr_i => lfo_table_wr_addr,
      table_wr_data_i => lfo_table_wr_data,
      lfo0_o => lfo0_sample,
      lfo1_o => lfo1_sample,
      lfo2_o => lfo2_sample,
      lfo3_o => lfo3_sample,
      valid_o => lfo_valid,
      init_done_o => lfo_table_init_done,
      busy_o => lfo_busy
    );

  u_wavetable_osc : entity work.raddsp_audio_quad_wavetable_oscillator
    generic map (
      SAMPLE_WIDTH => 24,
      WAVE_WIDTH => 16,
      PHASE_WIDTH => 24,
      TABLE_ADDR_WIDTH => 8,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15
    )
    port map (
      clk => sysclk_i,
      rst => rst_i,
      sample_ce_i => dac_axis_ready,
      phase_inc0_i => osc0_freq_mod,
      phase_inc1_i => osc1_freq_mod,
      phase_inc2_i => osc2_freq_mod,
      phase_inc3_i => osc3_freq_mod,
      wave_select_i => wave_select,
      gain0_i => osc0_gain,
      gain1_i => osc1_gain,
      gain2_i => osc2_gain,
      gain3_i => osc3_gain,
      table_wr_en_i => wave_table_wr_en,
      table_wr_addr_i => wave_table_wr_addr,
      table_wr_data_i => wave_table_wr_data,
      sample0_o => osc0_sample,
      sample1_o => osc1_sample,
      sample2_o => osc2_sample,
      sample3_o => osc3_sample,
      valid_o => osc_quad_valid,
      init_done_o => wave_table_init_done,
      busy_o => osc_quad_busy
    );

  osc_valid <= (others => osc_quad_valid);

  u_synth_pan_mixer : entity work.raddsp_audio_quad_osc_pan_mixer
    generic map (
      SAMPLE_WIDTH => 24,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15
    )
    port map (
      clk => sysclk_i,
      rst => rst_i,
      sample0_i => osc0_sample,
      sample1_i => osc1_sample,
      sample2_i => osc2_sample,
      sample3_i => osc3_sample,
      valid_i => osc_all_valid,
      pan_word_i => osc_pan_reg,
      left_o => synth_pan_left,
      right_o => synth_pan_right,
      valid_o => synth_pan_valid,
      busy_o => synth_pan_busy
    );

  u_poly_synth : entity work.raddsp_audio_poly_synth
    generic map (
      VOICE_COUNT => C_POLY_VOICES,
      SAMPLE_WIDTH => 24,
      WAVE_WIDTH => 16,
      PHASE_WIDTH => 24,
      TABLE_ADDR_WIDTH => 8,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15,
      RESET_CONFIG_REGS => false
    )
    port map (
      clk => sysclk_i,
      rst => rst_i,
      sample_ce_i => dac_axis_ready,
      cfg_wr_en_i => poly_cfg_wr_en,
      cfg_addr_i => poly_cfg_addr,
      cfg_data_i => ctrl_s_data_in(63 downto 32),
      cfg_rd_en_i => poly_cfg_rd_en,
      cfg_rd_addr_i => poly_cfg_rd_addr,
      cfg_data_o => poly_cfg_rd_data,
      cfg_rd_valid_o => poly_cfg_rd_valid,
      cfg_error_o => poly_cfg_error,
      table_wr_en_i => wave_table_wr_en,
      table_wr_addr_i => wave_table_wr_addr,
      table_wr_data_i => wave_table_wr_data,
      sample_o => poly_sample,
      valid_o => poly_valid,
      table_init_done_o => poly_table_init_done,
      busy_o => poly_busy
    );

  u_shared_pg_eq : entity work.raddsp_audio_stereo_shared_pg_eq_tdm
    generic map (
      SAMPLE_WIDTH => 24,
      SECTION_COUNT => 5,
      COEFF_FRAC_BITS => 28
    )
    port map (
      clk => sysclk_i,
      rst => rst_i,
      eq_enable_i => eq_control_reg(0),
      left_i => selected_left,
      right_i => selected_right,
      valid_i => '1',
      pan_i => global_pan_mod,
      left_gain_i => left_gain,
      right_gain_i => right_gain,
      coeff_wr_en_i => eq_coeff_wr_en,
      coeff_index_i => ctrl_high_rw_regs(C_HIGH_REG_EQ_COEFF_ADDR)(7 downto 0),
      coeff_data_i => ctrl_reg_data_in,
      commit_i => eq_commit,
      left_o => gain_left,
      right_o => gain_right,
      valid_o => gain_valid,
      busy_o => eq_busy,
      commit_busy_o => eq_smoothing
    );

  process(sysclk_i)
    variable lfo_step_sample_v : signed(23 downto 0);
    variable freq_acc_v        : signed(25 downto 0);
    variable pan_acc_v         : signed(25 downto 0);
  begin
    if rising_edge(sysclk_i) then
      if rstn_i = '0' then
        rpi_last_frame <= (others => '0');
        rpi_lane0_frame <= (others => '0');
        rpi_lane1_frame <= (others => '0');
        rpi_tx_lane_sync <= (others => '0');
        rpi_rx_lane_sync <= (others => '0');
        rpi_tx_frame_sys <= (others => '0');
        rpi_scope_frame_sys <= (others => '0');
        rpi_tx_toggle_sys <= '0';
        rpi_rx_lane0_toggle_sys_sync <= (others => '0');
        rpi_rx_lane0_toggle_sys_seen <= '0';
        rpi_rx_lane0_pulse_sys <= '0';
        adc_last_frame <= (others => '0');
        synth_left <= (others => '0');
        synth_right <= (others => '0');
        poly_last_sample <= (others => '0');
        lfo0_last <= (others => '0');
        lfo1_last <= (others => '0');
        lfo2_last <= (others => '0');
        lfo3_last <= (others => '0');
        lfo_freq_mod_sum <= (others => '0');
        lfo_pan_mod_sum <= (others => '0');
        lfo_freq_acc <= (others => '0');
        lfo_pan_acc <= (others => '0');
        lfo_sum_idx <= 4;
        lfo_sum_finalize <= '0';
        global_pan_mod <= (others => '0');
        osc0_freq_mod <= (others => '0');
        osc1_freq_mod <= (others => '0');
        osc2_freq_mod <= (others => '0');
        osc3_freq_mod <= (others => '0');
      else
        rpi_tx_lane_sync <= rpi_tx_lane_sync(1 downto 0) & rpi_tx_lane;
        rpi_rx_lane_sync <= rpi_rx_lane_sync(1 downto 0) & rpi_rx_lane;
        rpi_rx_lane0_toggle_sys_sync <= rpi_rx_lane0_toggle_sys_sync(1 downto 0) & rpi_rx_lane0_toggle_mclk;
        rpi_rx_lane0_pulse_sys <= '0';

        global_pan_mod <= add_lfo_to_pan(global_pan, lfo_pan_mod_sum);
        osc0_freq_mod <= add_lfo_to_freq(freq0, lfo_freq_mod_sum);
        osc1_freq_mod <= add_lfo_to_freq(freq1, lfo_freq_mod_sum);
        osc2_freq_mod <= add_lfo_to_freq(freq2, lfo_freq_mod_sum);
        osc3_freq_mod <= add_lfo_to_freq(freq3, lfo_freq_mod_sum);

        if rpi_rx_lane0_toggle_sys_sync(2) /= rpi_rx_lane0_toggle_sys_seen then
          rpi_rx_lane0_toggle_sys_seen <= rpi_rx_lane0_toggle_sys_sync(2);
          rpi_lane0_frame <= rpi_rx_lane0_mclk;
          rpi_lane1_frame <= rpi_rx_lane1_mclk;
          rpi_last_frame <= rpi_rx_lane0_mclk;
          rpi_rx_lane0_pulse_sys <= '1';
        end if;

        if dac_axis_ready = '1' then
          if dsp_mode = x"02" then
            rpi_tx_frame_sys <= pack_frame(poly_last_sample, poly_last_sample);
          elsif dsp_mode = x"01" then
            rpi_tx_frame_sys <= pack_frame(synth_left, synth_right);
          else
            rpi_tx_frame_sys <= (others => '0');
          end if;
          rpi_scope_frame_sys <= pack_frame(scope_left, scope_right);
          rpi_tx_toggle_sys <= not rpi_tx_toggle_sys;
        end if;

        if adc_axis_valid = '1' then
          adc_last_frame <= adc_axis_data;
        end if;

        if synth_pan_valid = '1' then
          synth_left <= synth_pan_left;
          synth_right <= synth_pan_right;
        end if;
        if poly_valid = '1' then
          poly_last_sample <= poly_sample;
        end if;
        if lfo_valid = '1' then
          lfo0_last <= lfo0_sample;
          lfo1_last <= lfo1_sample;
          lfo2_last <= lfo2_sample;
          lfo3_last <= lfo3_sample;
          lfo_freq_acc <= (others => '0');
          lfo_pan_acc <= (others => '0');
          lfo_sum_idx <= 0;
          lfo_sum_finalize <= '0';
        elsif lfo_sum_idx < 4 then
          freq_acc_v := lfo_freq_acc;
          pan_acc_v := lfo_pan_acc;
          lfo_step_sample_v := lfo_sample(lfo_sum_idx, lfo0_last, lfo1_last, lfo2_last, lfo3_last);
          if lfo_enable_mask(lfo_sum_idx) = '1' then
            if lfo_target(lfo_sum_idx, lfo_target_word) = "01" then
              freq_acc_v := freq_acc_v + resize(lfo_step_sample_v, freq_acc_v'length);
            elsif lfo_target(lfo_sum_idx, lfo_target_word) = "10" then
              pan_acc_v := pan_acc_v + resize(lfo_step_sample_v, pan_acc_v'length);
            end if;
          end if;

          lfo_freq_acc <= freq_acc_v;
          lfo_pan_acc <= pan_acc_v;
          if lfo_sum_idx = 3 then
            lfo_sum_idx <= 4;
            lfo_sum_finalize <= '1';
          else
            lfo_sum_idx <= lfo_sum_idx + 1;
          end if;
        elsif lfo_sum_finalize = '1' then
            if lfo_freq_acc > to_signed((2 ** 23) - 1, lfo_freq_acc'length) then
              lfo_freq_mod_sum <= to_signed((2 ** 23) - 1, lfo_freq_mod_sum'length);
            elsif lfo_freq_acc < to_signed(-(2 ** 23), lfo_freq_acc'length) then
              lfo_freq_mod_sum <= to_signed(-(2 ** 23), lfo_freq_mod_sum'length);
            else
              lfo_freq_mod_sum <= resize(lfo_freq_acc, lfo_freq_mod_sum'length);
            end if;

            if lfo_pan_acc > to_signed((2 ** 23) - 1, lfo_pan_acc'length) then
              lfo_pan_mod_sum <= to_signed((2 ** 23) - 1, lfo_pan_mod_sum'length);
            elsif lfo_pan_acc < to_signed(-(2 ** 23), lfo_pan_acc'length) then
              lfo_pan_mod_sum <= to_signed(-(2 ** 23), lfo_pan_mod_sum'length);
            else
              lfo_pan_mod_sum <= resize(lfo_pan_acc, lfo_pan_mod_sum'length);
            end if;
            lfo_sum_finalize <= '0';
        end if;
      end if;
    end if;
  end process;

  rpi_tx_axis_data <= pack_pi_frame(frame_left(rpi_tx_frame_mclk),
                                    frame_right(rpi_tx_frame_mclk),
                                    '0') when rpi_tx_lane = '0' else
                      pack_pi_frame(frame_left(rpi_scope_frame_mclk),
                                    frame_right(rpi_scope_frame_mclk),
                                    '1');
  rpi_tx_axis_valid <= dac_enable_mclk_sync(2);

  process(all)
    variable rpi_l : signed(23 downto 0);
    variable rpi_r : signed(23 downto 0);
    variable adc_l : signed(23 downto 0);
    variable adc_r : signed(23 downto 0);
    variable sum_l : signed(24 downto 0);
    variable sum_r : signed(24 downto 0);
  begin
    rpi_l := signed(frame_left(rpi_last_frame));
    rpi_r := signed(frame_right(rpi_last_frame));
    adc_l := signed(frame_left(adc_last_frame));
    adc_r := signed(frame_right(adc_last_frame));
    sum_l := resize(rpi_l, 25) + resize(adc_l, 25);
    sum_r := resize(rpi_r, 25) + resize(adc_r, 25);

    if dsp_mode = x"02" and dsp_control(3) = '1' then
      selected_left <= frame_left(rpi_lane0_frame);
      selected_right <= frame_right(rpi_lane0_frame);
    elsif dsp_mode = x"02" then
      selected_left <= poly_last_sample;
      selected_right <= poly_last_sample;
    elsif dsp_mode = x"01" and dsp_control(3) = '1' then
      selected_left <= frame_left(rpi_lane0_frame);
      selected_right <= frame_right(rpi_lane0_frame);
    elsif dsp_mode = x"01" then
      selected_left <= synth_left;
      selected_right <= synth_right;
    elsif dsp_control(2) = '1' then
      selected_left <= std_logic_vector(resize(sum_l, 24));
      selected_right <= std_logic_vector(resize(sum_r, 24));
    elsif dsp_control(1) = '1' then
      selected_left <= frame_left(adc_last_frame);
      selected_right <= frame_right(adc_last_frame);
    else
      selected_left <= frame_left(rpi_last_frame);
      selected_right <= frame_right(rpi_last_frame);
    end if;
  end process;

  dac_axis_data <= pack_frame(gain_left, gain_right);
  dac_axis_valid <= gain_valid when dac_enable = '1' else '0';
end architecture;
