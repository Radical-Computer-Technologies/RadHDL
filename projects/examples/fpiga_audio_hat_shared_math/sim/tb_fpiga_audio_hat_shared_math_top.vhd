library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.fpiga_audio_hat_tb_pkg.all;

entity tb_fpiga_audio_hat_shared_math_top is
  generic (
    G_CAPTURE_FRAMES : natural := 12;
    G_ADC_RAMP_PERIOD : positive := 960;
    G_ENABLE_DEBUG_I2C_SMOKE : boolean := false
  );
end entity;

architecture sim of tb_fpiga_audio_hat_shared_math_top is
  type scenario_t is (
    SCN_IDLE,
    SCN_ADC_ZERO,
    SCN_ADC_RAMP,
    SCN_RPI_LOOP,
    SCN_SYNTH_OSC,
    SCN_POLY_VOICE,
    SCN_MIX
  );

  constant C_CLK_50_HALF : time := 10 ns;
  constant C_I2C_HALF    : time := 80 ns;
  constant C_CAPTURE_FRAMES : natural := G_CAPTURE_FRAMES;

  signal clk_50m        : std_logic := '0';
  signal tb_sda_low     : std_logic := '0';
  signal tb_sda_z       : std_logic := '0';
  signal tb_scl_low     : std_logic := '0';
  signal sda_bus        : std_logic := '1';
  signal scl_bus        : std_logic := '1';
  signal mclkxco        : std_logic;
  signal i2s_sda_in_rpi : std_logic := '0';
  signal i2s_bck_rpi    : std_logic;
  signal i2s_dout_pi    : std_logic;
  signal i2s_lrck_rpi   : std_logic;
  signal i2s_bck        : std_logic := '0';
  signal i2s_lrck_dac   : std_logic := '0';
  signal i2s_lrck_adc   : std_logic := '0';
  signal i2s_sda_dac    : std_logic;
  signal i2s_sda_adc    : std_logic := '0';
  signal muteen         : std_logic;
  signal fpga67         : std_logic;
  signal fpga75         : std_logic;
  signal fpga77         : std_logic;
  signal fpga71         : std_logic;
  signal active_scenario : scenario_t := SCN_IDLE;
  signal adc_pattern     : scenario_t := SCN_ADC_ZERO;
  signal rpi_drive_en    : std_logic := '0';
  signal done            : std_logic := '0';
  signal mclk_seen       : std_logic := '0';
  signal codec_frame_idx : natural := 0;
  signal dac_capture_count : natural := 0;
  signal rpi_capture_count : natural := 0;
  signal dac_adc_ramp_nonzero : std_logic := '0';
  signal dac_synth_nonzero    : std_logic := '0';
  signal dac_poly_nonzero     : std_logic := '0';
  signal dac_mix_nonzero      : std_logic := '0';
  signal rpi_loop_nonzero     : std_logic := '0';

  file f_adc_ramp_input : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/adc_ramp_input.s32le";
  file f_adc_mix_input  : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/adc_mix_input.s32le";
  file f_dac_zero       : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/dac_zero.s32le";
  file f_dac_adc_ramp   : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/dac_adc_ramp.s32le";
  file f_rpi_loop       : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/rpi_loopback.s32le";
  file f_dac_synth      : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/dac_four_osc.s32le";
  file f_dac_poly       : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/dac_poly_voice.s32le";
  file f_dac_mix        : byte_file_t open write_mode is "build/sim/audio_hat_shared_math_top/dac_mix.s32le";
begin
  clk_50m <= not clk_50m after C_CLK_50_HALF when done = '0' else clk_50m;
  sda_bus <= '0' when tb_sda_low = '1' else 'Z' when tb_sda_z = '1' else '1';
  sda_bus <= 'H';
  scl_bus <= '0' when tb_scl_low = '1' else '1';

  dut : entity work.radhdl_fpiga_audio_top
    port map (
      CLK_50M => clk_50m,
      SDA_IN => sda_bus,
      SCL_IN => scl_bus,
      I2S_SDA_IN_RPI => i2s_sda_in_rpi,
      I2S_BCK_RPI => i2s_bck_rpi,
      I2S_DOUT_PI => i2s_dout_pi,
      I2S_LRCK_RPI => i2s_lrck_rpi,
      MCLKXCO_OUT => mclkxco,
      I2S_BCK => i2s_bck,
      I2S_LRCK_DAC => i2s_lrck_dac,
      I2S_LRCK_ADC => i2s_lrck_adc,
      I2S_SDA_DAC => i2s_sda_dac,
      I2S_SDA_ADC => i2s_sda_adc,
      MUTEEN => muteen,
      FPGA67 => fpga67,
      FPGA75 => fpga75,
      FPGA77 => fpga77,
      FPGA71 => fpga71
    );

  process
    variable bclk_div : natural := 0;
    variable lr_count : natural := 0;
  begin
    wait until rising_edge(mclkxco);
    mclk_seen <= '1';
    for i in 0 to 128 loop
      wait until rising_edge(mclkxco);
    end loop;

    loop
      wait until rising_edge(mclkxco);
      if bclk_div = 1 then
        bclk_div := 0;
        i2s_bck <= not i2s_bck;
        if i2s_bck = '0' then
          if lr_count = 31 then
            lr_count := 0;
            i2s_lrck_dac <= not i2s_lrck_dac;
            i2s_lrck_adc <= not i2s_lrck_adc;
          else
            lr_count := lr_count + 1;
          end if;
        end if;
      else
        bclk_div := bclk_div + 1;
      end if;
    end loop;
  end process;

  process
    variable bit_index : natural range 0 to 24 := 0;
    variable last_lrck : std_logic := '0';
    variable left_sample : std_logic_vector(23 downto 0) := (others => '0');
    variable right_sample : std_logic_vector(23 downto 0) := (others => '0');
    variable current_sample : std_logic_vector(23 downto 0) := (others => '0');
  begin
    wait until mclk_seen = '1';
    loop
      wait until falling_edge(i2s_bck);
      if i2s_lrck_adc /= last_lrck then
        last_lrck := i2s_lrck_adc;
        bit_index := 0;
        if adc_pattern = SCN_ADC_RAMP then
          left_sample := ramp_period_sample(codec_frame_idx, G_ADC_RAMP_PERIOD, 700000);
          right_sample := ramp_period_sample(codec_frame_idx, G_ADC_RAMP_PERIOD, 700000);
        elsif adc_pattern = SCN_MIX then
          left_sample := ramp_sample(codec_frame_idx, 700000);
          right_sample := sine_sample(codec_frame_idx, 64, 700000);
        else
          left_sample := (others => '0');
          right_sample := (others => '0');
        end if;
        if i2s_lrck_adc = '0' then
          current_sample := left_sample;
        else
          current_sample := right_sample;
          if active_scenario = SCN_ADC_RAMP then
            write_s32le_pair(f_adc_ramp_input, left_sample, right_sample);
          elsif active_scenario = SCN_MIX then
            write_s32le_pair(f_adc_mix_input, left_sample, right_sample);
          end if;
          codec_frame_idx <= codec_frame_idx + 1;
        end if;
      else
        if bit_index < 23 then
          bit_index := bit_index + 1;
        end if;
      end if;
      i2s_sda_adc <= current_sample(23 - bit_index);
    end loop;
  end process;

  process
    variable bit_index : natural range 0 to 24 := 0;
    variable last_lrck : std_logic := '0';
    variable left_shift : std_logic_vector(23 downto 0) := (others => '0');
    variable right_shift : std_logic_vector(23 downto 0) := (others => '0');
    variable next_count : natural;
  begin
    wait until mclk_seen = '1';
    loop
      wait until rising_edge(i2s_bck);
      if i2s_lrck_dac /= last_lrck then
        last_lrck := i2s_lrck_dac;
        bit_index := 0;
        if i2s_lrck_dac = '0' then
          left_shift := (others => '0');
        else
          right_shift := (others => '0');
        end if;
      else
        if bit_index < 24 then
          if i2s_lrck_dac = '0' then
            left_shift(23 - bit_index) := i2s_sda_dac;
          else
            right_shift(23 - bit_index) := i2s_sda_dac;
          end if;

          if bit_index = 23 then
            if i2s_lrck_dac = '1' then
              case active_scenario is
                when SCN_ADC_ZERO =>
                  write_s32le_pair(f_dac_zero, left_shift, right_shift);
                when SCN_ADC_RAMP =>
                  write_s32le_pair(f_dac_adc_ramp, left_shift, right_shift);
                  if left_shift /= x"000000" or right_shift /= x"000000" then
                    dac_adc_ramp_nonzero <= '1';
                  end if;
                when SCN_SYNTH_OSC =>
                  write_s32le_pair(f_dac_synth, left_shift, right_shift);
                  if left_shift /= x"000000" or right_shift /= x"000000" then
                    dac_synth_nonzero <= '1';
                  end if;
                when SCN_POLY_VOICE =>
                  write_s32le_pair(f_dac_poly, left_shift, right_shift);
                  if left_shift /= x"000000" or right_shift /= x"000000" then
                    dac_poly_nonzero <= '1';
                  end if;
                when SCN_MIX =>
                  write_s32le_pair(f_dac_mix, left_shift, right_shift);
                  if left_shift /= x"000000" or right_shift /= x"000000" then
                    dac_mix_nonzero <= '1';
                  end if;
                when others =>
                  null;
              end case;
              next_count := dac_capture_count + 1;
              dac_capture_count <= next_count;
            end if;
          end if;

          bit_index := bit_index + 1;
        end if;
      end if;
    end loop;
  end process;

  process
    variable bit_index : natural range 0 to 32 := 0;
    variable last_lrck : std_logic := '0';
    variable left_sample : std_logic_vector(31 downto 0) := (others => '0');
    variable right_sample : std_logic_vector(31 downto 0) := (others => '0');
    variable current_sample : std_logic_vector(31 downto 0) := (others => '0');
    variable frame : natural := 0;
  begin
    wait until mclk_seen = '1';
    loop
      wait until falling_edge(i2s_bck_rpi);
      if rpi_drive_en = '1' then
        if i2s_lrck_rpi /= last_lrck then
          last_lrck := i2s_lrck_rpi;
          bit_index := 0;
          left_sample := sine_sample(frame, G_ADC_RAMP_PERIOD, 700000)(23 downto 0) & x"A0";
          right_sample := sine_sample(frame + (G_ADC_RAMP_PERIOD / 4), G_ADC_RAMP_PERIOD, 700000)(23 downto 0) & x"A0";
          if i2s_lrck_rpi = '0' then
            current_sample := left_sample;
          else
            current_sample := right_sample;
            frame := frame + 1;
          end if;
        else
          if bit_index < 31 then
            bit_index := bit_index + 1;
          end if;
        end if;
        i2s_sda_in_rpi <= current_sample(31 - bit_index);
      else
        i2s_sda_in_rpi <= '0';
      end if;
    end loop;
  end process;

  process
    variable bit_index : natural range 0 to 32 := 0;
    variable last_lrck : std_logic := '0';
    variable left_shift : std_logic_vector(31 downto 0) := (others => '0');
    variable right_shift : std_logic_vector(31 downto 0) := (others => '0');
    variable seen_lrck : boolean := false;
  begin
    wait until mclk_seen = '1';
    loop
      wait until rising_edge(i2s_bck_rpi);
      if i2s_lrck_rpi /= last_lrck then
        if seen_lrck and last_lrck = '1' and active_scenario = SCN_RPI_LOOP then
          write_s32le_pair(f_rpi_loop, left_shift(31 downto 8), right_shift(31 downto 8));
          if left_shift(31 downto 8) /= x"000000" or right_shift(31 downto 8) /= x"000000" then
            rpi_loop_nonzero <= '1';
          end if;
          rpi_capture_count <= rpi_capture_count + 1;
        end if;
        seen_lrck := true;
        last_lrck := i2s_lrck_rpi;
        bit_index := 0;
        if i2s_lrck_rpi = '0' then
          left_shift := (others => '0');
        else
          right_shift := (others => '0');
        end if;
      else
        if bit_index < 32 then
          if i2s_lrck_rpi = '0' then
            left_shift(31 - bit_index) := i2s_dout_pi;
          else
            right_shift(31 - bit_index) := i2s_dout_pi;
          end if;
          bit_index := bit_index + 1;
        end if;
      end if;
    end loop;
  end process;

  process
    procedure i2c_start is
    begin
      tb_sda_z <= '0';
      tb_sda_low <= '0';
      tb_scl_low <= '0';
      wait for C_I2C_HALF;
      tb_sda_low <= '1';
      wait for C_I2C_HALF;
      tb_scl_low <= '1';
      wait for C_I2C_HALF;
    end procedure;

    procedure i2c_stop is
    begin
      tb_sda_z <= '0';
      tb_sda_low <= '1';
      wait for C_I2C_HALF;
      tb_scl_low <= '0';
      wait for C_I2C_HALF;
      tb_sda_low <= '0';
      wait for C_I2C_HALF;
    end procedure;

    procedure i2c_bit(bit_v : std_logic) is
    begin
      tb_sda_z <= '0';
      if bit_v = '0' then
        tb_sda_low <= '1';
      else
        tb_sda_low <= '0';
      end if;
      wait for C_I2C_HALF;
      tb_scl_low <= '0';
      wait for C_I2C_HALF;
      tb_scl_low <= '1';
      wait for C_I2C_HALF;
    end procedure;

    procedure i2c_byte(value : std_logic_vector(7 downto 0)) is
    begin
      for i in 7 downto 0 loop
        i2c_bit(value(i));
      end loop;
    end procedure;

    procedure i2c_read_byte(variable value : out std_logic_vector(7 downto 0)) is
    begin
      tb_sda_z <= '1';
      tb_sda_low <= '0';
      for i in 7 downto 0 loop
        wait for C_I2C_HALF;
        tb_scl_low <= '0';
        wait for C_I2C_HALF;
        if sda_bus = '0' then
          value(i) := '0';
        else
          value(i) := '1';
        end if;
        tb_scl_low <= '1';
        wait for C_I2C_HALF;
      end loop;
      tb_sda_z <= '0';
    end procedure;

    procedure i2c_write32_to(
      target : std_logic_vector(6 downto 0);
      addr : std_logic_vector(15 downto 0);
      data : std_logic_vector(31 downto 0)
    ) is
    begin
      i2c_start;
      i2c_byte(target & '0');
      i2c_byte(C_OP_REG_WRITE);
      i2c_byte(addr(15 downto 8));
      i2c_byte(addr(7 downto 0));
      i2c_byte(data(31 downto 24));
      i2c_byte(data(23 downto 16));
      i2c_byte(data(15 downto 8));
      i2c_byte(data(7 downto 0));
      i2c_stop;
      wait for 2 us;
    end procedure;

    procedure i2c_write32(addr : std_logic_vector(15 downto 0); data : std_logic_vector(31 downto 0)) is
    begin
      i2c_write32_to(C_I2C_AUDIO_ADDR, addr, data);
    end procedure;

    procedure i2c_read32_from(
      target : std_logic_vector(6 downto 0);
      addr : std_logic_vector(15 downto 0);
      variable data : out std_logic_vector(31 downto 0)
    ) is
      variable b0 : std_logic_vector(7 downto 0);
      variable b1 : std_logic_vector(7 downto 0);
      variable b2 : std_logic_vector(7 downto 0);
      variable b3 : std_logic_vector(7 downto 0);
    begin
      i2c_start;
      i2c_byte(target & '0');
      i2c_byte(C_OP_REG_READ);
      i2c_byte(addr(15 downto 8));
      i2c_byte(addr(7 downto 0));
      wait for 20 us;

      i2c_start;
      i2c_byte(target & '1');
      i2c_read_byte(b0);
      i2c_read_byte(b1);
      i2c_read_byte(b2);
      i2c_read_byte(b3);
      i2c_stop;
      wait for 2 us;

      data := b0 & b1 & b2 & b3;
    end procedure;

    procedure i2c_debug_write32(addr : std_logic_vector(15 downto 0); data : std_logic_vector(31 downto 0)) is
    begin
      i2c_write32_to(C_I2C_DEBUG_ADDR, addr, data);
    end procedure;

    procedure i2c_debug_read32(addr : std_logic_vector(15 downto 0); variable data : out std_logic_vector(31 downto 0)) is
    begin
      i2c_read32_from(C_I2C_DEBUG_ADDR, addr, data);
    end procedure;

    procedure configure_common is
    begin
      i2c_write32(C_REG_CONTROL, x"00000100");
      i2c_write32(C_REG_LEFT_GAIN, C_Q15_UNITY_WORD);
      i2c_write32(C_REG_RIGHT_GAIN, C_Q15_UNITY_WORD);
      i2c_write32(C_REG_OSC0_GAIN, C_Q15_UNITY_WORD);
      i2c_write32(C_REG_OSC1_GAIN, x"00000000");
      i2c_write32(C_REG_OSC2_GAIN, x"00000000");
      i2c_write32(C_REG_OSC3_GAIN, x"00000000");
      i2c_write32(C_REG_GLOBAL_PAN, x"00000080");
      i2c_write32(C_REG_OSC_PAN, x"80808080");
    end procedure;

    procedure load_wave_tables is
      variable addr_word : std_logic_vector(31 downto 0);
      variable idx : natural;
    begin
      for page in 0 to 3 loop
        for slot in 0 to 3 loop
          idx := slot * 64;
          addr_word := (others => '0');
          addr_word(9 downto 8) := std_logic_vector(to_unsigned(page, 2));
          addr_word(7 downto 0) := std_logic_vector(to_unsigned(idx, 8));
          i2c_write32(C_REG_WAVE_CONTROL, addr_word);
          i2c_write32(C_REG_WAVE_DATA, x"0000" & wave_table_value(page, idx));
        end loop;
      end loop;
    end procedure;

    procedure wait_dac_frames(start_count : natural; frame_count : natural) is
    begin
      for i in 0 to (frame_count * 96) + 6000 loop
        wait until rising_edge(i2s_bck);
        exit when dac_capture_count >= start_count + frame_count;
      end loop;
      assert dac_capture_count >= start_count + frame_count
        report "Timed out waiting for codec DAC captures"
        severity failure;
    end procedure;

    procedure wait_codec_preroll(frame_count : natural) is
    begin
      for i in 0 to (frame_count * 80) loop
        wait until rising_edge(i2s_bck);
      end loop;
    end procedure;

    procedure wait_rpi_preroll(frame_count : natural) is
    begin
      for i in 0 to (frame_count * 96) loop
        wait until rising_edge(i2s_bck_rpi);
      end loop;
    end procedure;

    variable start_count : natural;
    variable rpi_target_count : natural;
    variable dbg_id : std_logic_vector(31 downto 0);
    variable dbg_caps : std_logic_vector(31 downto 0);
    variable dbg_status : std_logic_vector(31 downto 0);
    variable dbg_event_now : std_logic_vector(31 downto 0);
    variable dbg_sample_now0 : std_logic_vector(31 downto 0);
    variable dbg_sample0 : std_logic_vector(31 downto 0);
    variable dbg_sample1 : std_logic_vector(31 downto 0);
  begin
    tb_sda_low <= '0';
    tb_scl_low <= '0';
    wait until mclk_seen = '1';
    wait for 30 us;

    assert mclkxco = '0' or mclkxco = '1' report "MCLK is not driven" severity failure;

    i2c_write32(C_REG_CONTROL, x"00000000");
    wait for 5 us;
    assert muteen = '0' report "MUTEEN did not clear from CONTROL[1]" severity failure;
    i2c_write32(C_REG_CONTROL, x"00000002");
    wait for 5 us;
    assert muteen = '1' report "MUTEEN did not set from CONTROL[1]" severity failure;

    configure_common;

    adc_pattern <= SCN_ADC_ZERO;
    i2c_write32(C_REG_DSP_CONTROL, x"00000200");
    active_scenario <= SCN_IDLE;
    wait_codec_preroll(4);
    active_scenario <= SCN_ADC_ZERO;
    start_count := dac_capture_count;
    wait_dac_frames(start_count, 2);

    adc_pattern <= SCN_ADC_RAMP;
    active_scenario <= SCN_IDLE;
    wait_codec_preroll(8);
    active_scenario <= SCN_ADC_RAMP;
    start_count := dac_capture_count;
    wait_dac_frames(start_count, C_CAPTURE_FRAMES);
    assert dac_adc_ramp_nonzero = '1' report "ADC monitor DAC capture stayed zero" severity failure;

    if G_ENABLE_DEBUG_I2C_SMOKE then
      i2c_debug_read32(C_DBG_REG_ID, dbg_id);
      assert dbg_id = x"52414449"
        report "Debug hub ID readback mismatch, got 0x" & to_hstring(dbg_id)
        severity failure;
      i2c_debug_read32(C_DBG_REG_CAPS, dbg_caps);
      assert dbg_caps = x"00400008"
        report "Debug hub caps readback mismatch, got 0x" & to_hstring(dbg_caps)
        severity failure;
      i2c_debug_read32(C_DBG_REG_EVENT_NOW, dbg_event_now);
      assert dbg_event_now(1) = '1' report "Debug hub live event did not see ADC-valid activity" severity failure;
      i2c_debug_read32(C_DBG_REG_SAMPLE_NOW0, dbg_sample_now0);
      assert dbg_sample_now0 /= x"00000000" report "Debug hub live sample stayed zero" severity failure;
      i2c_debug_write32(C_DBG_REG_POSTTRIG, x"00000008");
      i2c_debug_write32(C_DBG_REG_TRIG_MASK, x"00000002");
      i2c_debug_write32(C_DBG_REG_TRIG_VALUE, x"00000002");
      i2c_debug_write32(C_DBG_REG_CONTROL, x"00000001");
      for i in 0 to 2000 loop
        wait until rising_edge(clk_50m);
        i2c_debug_read32(C_DBG_REG_STATUS, dbg_status);
        exit when dbg_status(2) = '1';
      end loop;
      assert dbg_status(2) = '1' report "Debug hub capture did not complete" severity failure;
      assert unsigned(dbg_status(31 downto 16)) >= 8 report "Debug hub captured too few samples" severity failure;
      i2c_debug_write32(C_DBG_REG_DATA_INDEX, x"00000001");
      i2c_debug_read32(C_DBG_REG_SAMPLE_DATA0, dbg_sample0);
      i2c_debug_read32(C_DBG_REG_SAMPLE_DATA1, dbg_sample1);
      assert dbg_sample0 /= x"00000000" or dbg_sample1 /= x"00000000"
        report "Debug hub captured sample readback stayed zero"
        severity failure;
    end if;

    rpi_drive_en <= '1';
    i2c_write32(C_REG_DSP_CONTROL, x"00000000");
    active_scenario <= SCN_IDLE;
    wait_rpi_preroll(8);
    active_scenario <= SCN_RPI_LOOP;
    if C_CAPTURE_FRAMES > 32 then
      rpi_target_count := C_CAPTURE_FRAMES;
    else
      rpi_target_count := 32;
    end if;
    for i in 0 to 20000 loop
      wait until rising_edge(i2s_bck_rpi);
      exit when rpi_capture_count >= rpi_target_count and rpi_loop_nonzero = '1';
    end loop;
    assert rpi_capture_count >= rpi_target_count report "RPi I2S capture did not complete in the smoke window" severity failure;
    assert rpi_loop_nonzero = '1' report "RPi I2S loopback capture stayed zero" severity failure;
    active_scenario <= SCN_IDLE;
    rpi_drive_en <= '0';

    load_wave_tables;
    i2c_write32(C_REG_FREQ0, x"00" & phase_inc(440.0));
    i2c_write32(C_REG_OSC0_GAIN, C_Q15_UNITY_WORD);
    i2c_write32(C_REG_DSP_CONTROL, x"00000001");
    active_scenario <= SCN_IDLE;
    wait_codec_preroll(16);
    active_scenario <= SCN_SYNTH_OSC;
    start_count := dac_capture_count;
    wait_dac_frames(start_count, C_CAPTURE_FRAMES);
    assert dac_synth_nonzero = '1' report "Four-oscillator DAC capture stayed zero" severity failure;

    i2c_write32(C_REG_POLY_FREQ0, x"00" & phase_inc(659.25));
    i2c_write32(C_REG_POLY_VOLUME0, x"FFFFFFFF");
    i2c_write32(C_REG_POLY_ADSR0, x"01FFFFFF");
    i2c_write32(C_REG_POLY_CTRL0, x"00000003");
    i2c_write32(C_REG_DSP_CONTROL, x"00000002");
    active_scenario <= SCN_IDLE;
    wait_codec_preroll(16);
    active_scenario <= SCN_POLY_VOICE;
    start_count := dac_capture_count;
    wait_dac_frames(start_count, C_CAPTURE_FRAMES);
    assert dac_poly_nonzero = '1' report "Poly voice DAC capture stayed zero" severity failure;

    adc_pattern <= SCN_MIX;
    i2c_write32(C_REG_FREQ0, x"00" & phase_inc(523.25));
    i2c_write32(C_REG_FREQ1, x"00" & phase_inc(523.25));
    i2c_write32(C_REG_OSC0_GAIN, C_Q15_UNITY_WORD);
    i2c_write32(C_REG_OSC1_GAIN, x"00000040");
    i2c_write32(C_REG_OSC_PAN, x"808020E0");
    i2c_write32(C_REG_DSP_CONTROL, x"00000001");
    active_scenario <= SCN_IDLE;
    wait_codec_preroll(16);
    active_scenario <= SCN_MIX;
    start_count := dac_capture_count;
    wait_dac_frames(start_count, C_CAPTURE_FRAMES);
    assert dac_mix_nonzero = '1' report "Mix DAC capture stayed zero" severity failure;

    report "PASS tb_fpiga_audio_hat_shared_math_top";
    done <= '1';
    finish;
  end process;
end architecture;
