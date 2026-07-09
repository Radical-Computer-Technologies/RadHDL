library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library gw5a;
use gw5a.components.all;

entity radhdl_fpiga_audio_top is
  port (
    CLK_50M        : in    std_logic;
    SDA_IN         : inout std_logic;
    SCL_IN         : inout std_logic;
    I2S_SDA_IN_RPI : in    std_logic;
    I2S_BCK_RPI    : out   std_logic;
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
  subtype byte_t is std_logic_vector(7 downto 0);
  type byte_reg_array_t is array (0 to 42) of byte_t;

  constant C_UNITY_GAIN : std_logic_vector(17 downto 0) := std_logic_vector(to_signed(32767, 18));

  signal sysclk_i       : std_logic := '0';
  signal mclk_i         : std_logic := '0';
  signal clocks_locked  : std_logic := '0';
  signal rstn_i         : std_logic := '0';
  signal rst_i          : std_logic := '1';
  signal sys_rst_count  : unsigned(5 downto 0) := (others => '0');
  signal clkfb_unused   : std_logic;
  signal clkout1_unused : std_logic;
  signal mdrdo_unused   : std_logic_vector(7 downto 0);

  signal regs           : byte_reg_array_t := (others => (others => '0'));
  signal i2c_sda_oen    : std_logic := '1';
  signal i2c_wr_addr    : std_logic_vector(7 downto 0);
  signal i2c_wr_data    : std_logic_vector(7 downto 0);
  signal i2c_wr_en      : std_logic;
  signal i2c_rd_addr    : std_logic_vector(7 downto 0);
  signal i2c_rd_data    : std_logic_vector(7 downto 0);
  signal i2c_rd_en      : std_logic;
  signal i2c_read_done  : std_logic;

  signal soft_rst       : std_logic_vector(7 downto 0);
  signal soft_en        : std_logic_vector(7 downto 0);
  signal conf0          : std_logic_vector(7 downto 0);
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
  signal wave_wr_count  : unsigned(9 downto 0) := (others => '0');

  signal rpi_cfg_wr_en  : std_logic := '0';
  signal adc_cfg_wr_en  : std_logic := '0';
  signal cfg_count      : unsigned(2 downto 0) := (others => '0');
  signal rpi_reg_rd     : std_logic_vector(31 downto 0);
  signal adc_reg_rd     : std_logic_vector(31 downto 0);
  signal rpi_reg_wv     : std_logic;
  signal rpi_reg_rv     : std_logic;
  signal adc_reg_wv     : std_logic;
  signal adc_reg_rv     : std_logic;
  signal rpi_reg_err    : std_logic;
  signal adc_reg_err    : std_logic;

  signal rpi_axis_data  : std_logic_vector(63 downto 0);
  signal rpi_axis_valid : std_logic;
  signal rpi_axis_last  : std_logic;
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
  signal left_gain      : std_logic_vector(17 downto 0);
  signal right_gain     : std_logic_vector(17 downto 0);

  signal phase0         : unsigned(23 downto 0) := (others => '0');
  signal phase1         : unsigned(23 downto 0) := (others => '0');
  signal phase2         : unsigned(23 downto 0) := (others => '0');
  signal phase3         : unsigned(23 downto 0) := (others => '0');
  signal synth_left     : std_logic_vector(23 downto 0) := (others => '0');
  signal synth_right    : std_logic_vector(23 downto 0) := (others => '0');

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

  function byte3(lo : std_logic_vector(7 downto 0); mid : std_logic_vector(7 downto 0); hi : std_logic_vector(7 downto 0))
    return std_logic_vector is
  begin
    return hi & mid & lo;
  end function;

  function gain_or_unity(value : std_logic_vector(23 downto 0)) return std_logic_vector is
  begin
    if value = x"000000" then
      return C_UNITY_GAIN;
    end if;
    return value(23 downto 6);
  end function;

  function wave_sample(phase : unsigned(23 downto 0); wave_id : std_logic_vector(1 downto 0)) return signed is
    variable sample : signed(23 downto 0);
    variable ramp   : signed(23 downto 0);
  begin
    ramp := signed(std_logic_vector(phase));
    case wave_id is
      when "00" =>
        sample := ramp;
      when "01" =>
        if phase(23) = '1' then
          sample := to_signed(16#7FFFFF#, 24);
        else
          sample := to_signed(-16#800000#, 24);
        end if;
      when "10" =>
        if phase(23) = '1' then
          sample := signed(not std_logic_vector(phase));
        else
          sample := ramp;
        end if;
      when others =>
        sample := -ramp;
    end case;
    return sample;
  end function;

  function scale_sample(sample : signed(23 downto 0); volume : std_logic_vector(23 downto 0)) return signed is
    variable coeff   : signed(17 downto 0);
    variable product : signed(41 downto 0);
  begin
    if volume = x"000000" then
      coeff := signed(C_UNITY_GAIN);
    else
      coeff := signed(volume(23 downto 6));
    end if;
    product := sample * coeff;
    return resize(shift_right(product, 15), 24);
  end function;
begin
  SCL_IN <= 'Z';
  SDA_IN <= '0' when i2c_sda_oen = '0' else 'Z';

  MUTEEN <= soft_en(0);
  I2S_BCK_RPI <= I2S_BCK;
  I2S_LRCK_RPI <= I2S_LRCK_DAC;
  I2S_SDA_DAC <= dac_sdata;
  FPGA75 <= I2S_BCK;
  FPGA77 <= dac_sdata;
  FPGA71 <= I2S_LRCK_DAC;
  FPGA67 <= adc_axis_valid;

  rst_i <= not rstn_i;
  soft_rst <= regs(1);
  soft_en <= regs(2);
  conf0 <= regs(3);
  dsp_mode <= regs(4);
  freq0 <= unsigned(byte3(regs(5), regs(6), regs(7)));
  freq1 <= unsigned(byte3(regs(8), regs(9), regs(10)));
  freq2 <= unsigned(byte3(regs(11), regs(12), regs(13)));
  freq3 <= unsigned(byte3(regs(14), regs(15), regs(16)));
  wave_select <= regs(17);
  dsp_control <= regs(24);
  lvol <= byte3(regs(25), regs(26), regs(27));
  rvol <= byte3(regs(28), regs(29), regs(30));
  osc0vol <= byte3(regs(31), regs(32), regs(33));
  osc1vol <= byte3(regs(34), regs(35), regs(36));
  osc2vol <= byte3(regs(37), regs(38), regs(39));
  osc3vol <= byte3(regs(40), regs(41), regs(42));
  left_gain <= gain_or_unity(lvol);
  right_gain <= gain_or_unity(rvol);

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
        rstn_i <= '0';
        sys_rst_count <= (others => '0');
      elsif sys_rst_count < to_unsigned(50, sys_rst_count'length) then
        rstn_i <= '0';
        sys_rst_count <= sys_rst_count + 1;
      else
        rstn_i <= soft_rst(0);
      end if;
    end if;
  end process;

  u_i2c : entity work.radif_i2c_byte_slave
    generic map (
      I2C_ADDR => "0010010"
    )
    port map (
      clk => sysclk_i,
      rstn => rstn_i,
      scl_i => SCL_IN,
      sda_i => SDA_IN,
      sda_oen => i2c_sda_oen,
      wr_addr => i2c_wr_addr,
      wr_data => i2c_wr_data,
      wr_en => i2c_wr_en,
      rd_addr => i2c_rd_addr,
      rd_data => i2c_rd_data,
      rd_en => i2c_rd_en,
      read_done => i2c_read_done
    );

  process(all)
    variable idx : natural;
  begin
    idx := to_integer(unsigned(i2c_rd_addr));
    if idx = 0 then
      i2c_rd_data <= x"01";
    elsif idx = 20 then
      i2c_rd_data <= "00000" & '1' & "00";
    elsif idx <= 42 then
      i2c_rd_data <= regs(idx);
    else
      i2c_rd_data <= (others => '0');
    end if;
  end process;

  process(sysclk_i)
    variable wr_idx : natural;
  begin
    if rising_edge(sysclk_i) then
      if rstn_i = '0' then
        regs <= (others => (others => '0'));
        regs(1) <= x"01";
        regs(2) <= x"00";
        regs(3) <= x"01";
        regs(4) <= x"00";
        wave_wr_count <= (others => '0');
      else
        if i2c_wr_en = '1' then
          wr_idx := to_integer(unsigned(i2c_wr_addr));
          if wr_idx <= 42 then
            regs(wr_idx) <= i2c_wr_data;
          end if;
          if wr_idx = 20 and i2c_wr_data(0) = '1' then
            if wave_wr_count = 1023 then
              wave_wr_count <= (others => '0');
            else
              wave_wr_count <= wave_wr_count + 1;
            end if;
          elsif wr_idx = 4 then
            wave_wr_count <= (others => '0');
          end if;
        end if;
      end if;
    end if;
  end process;

  process(sysclk_i)
  begin
    if rising_edge(sysclk_i) then
      if rstn_i = '0' then
        cfg_count <= (others => '0');
        rpi_cfg_wr_en <= '0';
        adc_cfg_wr_en <= '0';
      else
        rpi_cfg_wr_en <= '0';
        adc_cfg_wr_en <= '0';
        if cfg_count = to_unsigned(0, cfg_count'length) then
          rpi_cfg_wr_en <= '1';
          adc_cfg_wr_en <= '1';
          cfg_count <= cfg_count + 1;
        elsif cfg_count < to_unsigned(7, cfg_count'length) then
          cfg_count <= cfg_count + 1;
        end if;
      end if;
    end if;
  end process;

  u_rpi_i2s : entity work.radif_i2s_axis
    generic map (
      SAMPLE_WIDTH => 24,
      AXIS_DATA_WIDTH => 64,
      REG_DATA_WIDTH => 32,
      REG_ADDR_WIDTH => 16,
      USE_EXTERNAL_MCLK => false,
      NO_MCLK => true,
      USE_EXTERNAL_BCLK => true,
      ENABLE_I2S_TO_AXIS => true,
      ENABLE_AXIS_TO_I2S => true,
      VENDOR_TAG => "GOWIN",
      PRODUCT_SERIES_TAG => "GW5A"
    )
    port map (
      clk => sysclk_i,
      rstn => rstn_i,
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
      i2s_bclk_i => I2S_BCK,
      i2s_bclk_o => open,
      i2s_bclk_oe => open,
      i2s_lrck_i => I2S_LRCK_DAC,
      i2s_lrck_o => open,
      i2s_lrck_oe => open,
      i2s_sdata_i => I2S_SDA_IN_RPI,
      i2s_sdata_o => dac_sdata,
      i2s_sdata_oe => open,
      m_axis_tdata => rpi_axis_data,
      m_axis_tvalid => rpi_axis_valid,
      m_axis_tready => '1',
      m_axis_tlast => rpi_axis_last,
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
      rstn => rstn_i,
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

  process(sysclk_i)
    variable osc0 : signed(23 downto 0);
    variable osc1 : signed(23 downto 0);
    variable osc2 : signed(23 downto 0);
    variable osc3 : signed(23 downto 0);
    variable mix_l : signed(24 downto 0);
    variable mix_r : signed(24 downto 0);
  begin
    if rising_edge(sysclk_i) then
      if rstn_i = '0' then
        rpi_last_frame <= (others => '0');
        adc_last_frame <= (others => '0');
        phase0 <= (others => '0');
        phase1 <= (others => '0');
        phase2 <= (others => '0');
        phase3 <= (others => '0');
        synth_left <= (others => '0');
        synth_right <= (others => '0');
      else
        if rpi_axis_valid = '1' then
          rpi_last_frame <= rpi_axis_data;
        end if;
        if adc_axis_valid = '1' then
          adc_last_frame <= adc_axis_data;
        end if;

        if dac_axis_ready = '1' then
          phase0 <= phase0 + freq0;
          phase1 <= phase1 + freq1;
          phase2 <= phase2 + freq2;
          phase3 <= phase3 + freq3;
          osc0 := scale_sample(wave_sample(phase0, wave_select(1 downto 0)), osc0vol);
          osc1 := scale_sample(wave_sample(phase1, wave_select(3 downto 2)), osc1vol);
          osc2 := scale_sample(wave_sample(phase2, wave_select(5 downto 4)), osc2vol);
          osc3 := scale_sample(wave_sample(phase3, wave_select(7 downto 6)), osc3vol);
          mix_l := resize(osc0, 25) + resize(osc2, 25);
          mix_r := resize(osc1, 25) + resize(osc3, 25);
          synth_left <= std_logic_vector(resize(mix_l, 24));
          synth_right <= std_logic_vector(resize(mix_r, 24));
        end if;
      end if;
    end if;
  end process;

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

    if dsp_mode = x"01" then
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

  u_gain : entity work.raddsp_audio_stereo_gain
    generic map (
      SAMPLE_WIDTH => 24,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15
    )
    port map (
      clk => sysclk_i,
      rst => rst_i,
      enable_i => '1',
      left_i => selected_left,
      right_i => selected_right,
      valid_i => '1',
      left_gain_i => left_gain,
      right_gain_i => right_gain,
      left_o => gain_left,
      right_o => gain_right,
      valid_o => gain_valid
    );

  dac_axis_data <= pack_frame(gain_left, gain_right);
  dac_axis_valid <= gain_valid when conf0 /= x"00" else '0';
end architecture;
