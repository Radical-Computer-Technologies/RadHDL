library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.finish;

library raddsp;

-- Verifies the register-controlled AM IQ modulator and demodulator with a
-- 2048-sample amplitude envelope. The test programs both internal DDS mixers
-- to the same carrier tuning word, streams a sinusoidal envelope through the
-- modulator, demodulates it back to baseband, and exposes plot_* signals for
-- datasheet analog plots.
entity tb_raddsp_axis_am_iq is
end entity;

architecture sim of tb_raddsp_axis_am_iq is
  constant C_WIDTH       : positive := 16;
  constant C_FRAC        : natural := 14;
  constant C_ONE         : integer := 2 ** C_FRAC;
  constant C_SAMPLES     : natural := 2048;
  constant C_PHASE_INC   : std_logic_vector(31 downto 0) := x"10000000";
  constant C_CONTROL_RUN : std_logic_vector(31 downto 0) := x"00000003";
  constant C_CONTROL_RST : std_logic_vector(31 downto 0) := x"0000000B";

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal carrier_i : std_logic_vector(C_WIDTH - 1 downto 0) := std_logic_vector(to_signed(C_ONE, C_WIDTH));
  signal carrier_q : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal in_data  : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal in_last  : std_logic := '0';
  signal iq_valid : std_logic;
  signal iq_ready : std_logic;
  signal iq_data  : std_logic_vector((2 * C_WIDTH) - 1 downto 0);
  signal iq_last  : std_logic;
  signal env_valid : std_logic;
  signal env_ready : std_logic := '1';
  signal env_data  : std_logic_vector(C_WIDTH - 1 downto 0);
  signal env_last  : std_logic;

  signal reg_wr_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_rd_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_wr_en    : std_logic := '0';
  signal reg_rd_en    : std_logic := '0';
  signal reg_data_in  : std_logic_vector(31 downto 0) := (others => '0');
  signal mod_reg_data : std_logic_vector(31 downto 0);
  signal dem_reg_data : std_logic_vector(31 downto 0);
  signal mod_wr_valid : std_logic;
  signal mod_rd_valid : std_logic;
  signal dem_wr_valid : std_logic;
  signal dem_rd_valid : std_logic;
  signal mod_error    : std_logic;
  signal dem_error    : std_logic;

  signal sent_count     : natural range 0 to C_SAMPLES := 0;
  signal received_count : natural range 0 to C_SAMPLES := 0;
  signal last_seen      : boolean := false;

  signal plot_index   : std_logic_vector(15 downto 0) := (others => '0');
  signal plot_env_in  : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal plot_i       : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal plot_q       : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal plot_env_out : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');

  function envelope_sample(index : natural) return integer is
    variable angle : real;
    variable value : real;
  begin
    angle := 2.0 * MATH_PI * real(index mod C_SAMPLES) / real(C_SAMPLES);
    value := 8192.0 + (4096.0 * sin(8.0 * angle)) + (1024.0 * cos(23.0 * angle));
    if value < 0.0 then
      return 0;
    elsif value > real((2 ** (C_WIDTH - 1)) - 1) then
      return (2 ** (C_WIDTH - 1)) - 1;
    end if;
    return integer(value);
  end function;
begin
  clk <= not clk after 5 ns;

  u_mod : entity raddsp.raddsp_axis_am_iq_modulator
    generic map (
      SAMPLE_WIDTH => C_WIDTH,
      FRAC_BITS => C_FRAC,
      DEFAULT_INTERNAL_DDS => true,
      DEFAULT_ENABLE => true,
      VENDOR => "GENERIC"
    )
    port map (
      clk => clk,
      rst => rst,
      carrier_i_i => carrier_i,
      carrier_q_i => carrier_q,
      s_axis_tvalid => in_valid,
      s_axis_tready => in_ready,
      s_axis_tdata => in_data,
      s_axis_tlast => in_last,
      m_axis_tvalid => iq_valid,
      m_axis_tready => iq_ready,
      m_axis_tdata => iq_data,
      m_axis_tlast => iq_last,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_data_in,
      reg_data_out => mod_reg_data,
      reg_wr_rdy => open,
      reg_rd_rdy => open,
      reg_wr_valid => mod_wr_valid,
      reg_rd_valid => mod_rd_valid,
      reg_error => mod_error
    );

  u_demod : entity raddsp.raddsp_axis_am_iq_demodulator
    generic map (
      SAMPLE_WIDTH => C_WIDTH,
      FRAC_BITS => C_FRAC,
      DEFAULT_INTERNAL_DDS => true,
      DEFAULT_ENABLE => true,
      VENDOR => "GENERIC"
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => iq_valid,
      s_axis_tready => iq_ready,
      s_axis_tdata => iq_data,
      s_axis_tlast => iq_last,
      m_axis_tvalid => env_valid,
      m_axis_tready => env_ready,
      m_axis_tdata => env_data,
      m_axis_tlast => env_last,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_data_in,
      reg_data_out => dem_reg_data,
      reg_wr_rdy => open,
      reg_rd_rdy => open,
      reg_wr_valid => dem_wr_valid,
      reg_rd_valid => dem_rd_valid,
      reg_error => dem_error
    );

  stim : process
    procedure write_reg(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_wr_addr <= std_logic_vector(to_unsigned(addr, reg_wr_addr'length));
      reg_data_in <= data;
      reg_wr_en <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      assert mod_wr_valid = '1' and dem_wr_valid = '1'
        report "AM IQ register write did not acknowledge"
        severity failure;
      assert mod_error = '0' and dem_error = '0'
        report "AM IQ register write reported an error"
        severity failure;
      reg_wr_en <= '0';
      reg_data_in <= (others => '0');
    end procedure;
  begin
    wait for 100 ns;
    rst <= '0';
    wait until rising_edge(clk);

    write_reg(16#08#, C_PHASE_INC);
    write_reg(16#00#, C_CONTROL_RST);
    write_reg(16#00#, C_CONTROL_RUN);

    for i in 0 to C_SAMPLES - 1 loop
      wait until rising_edge(clk);
      in_data <= std_logic_vector(to_signed(envelope_sample(i), C_WIDTH));
      if i = C_SAMPLES - 1 then
        in_last <= '1';
      else
        in_last <= '0';
      end if;
      in_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when in_ready = '1';
      end loop;
      sent_count <= i + 1;
      in_valid <= '0';
      in_last <= '0';
    end loop;

    loop
      wait until rising_edge(clk);
      exit when received_count = C_SAMPLES;
    end loop;

    assert last_seen report "AM IQ tlast was not preserved" severity failure;
    report "tb_raddsp_axis_am_iq passed" severity note;
    finish;
  end process;

  monitor : process(clk)
    variable expected : integer;
    variable observed : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        received_count <= 0;
        last_seen <= false;
      elsif env_valid = '1' and env_ready = '1' then
        expected := envelope_sample(received_count);
        observed := to_integer(unsigned(env_data));
        assert abs(observed - expected) <= 64
          report "AM IQ demodulated envelope mismatch"
          severity failure;
        plot_index <= std_logic_vector(to_unsigned(received_count, plot_index'length));
        plot_env_in <= std_logic_vector(to_signed(expected, C_WIDTH));
        plot_i <= iq_data(C_WIDTH - 1 downto 0);
        plot_q <= iq_data((2 * C_WIDTH) - 1 downto C_WIDTH);
        plot_env_out <= env_data;
        if env_last = '1' then
          last_seen <= true;
        end if;
        if received_count < C_SAMPLES then
          received_count <= received_count + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
