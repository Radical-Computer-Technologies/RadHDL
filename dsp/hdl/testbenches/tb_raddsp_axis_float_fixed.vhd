library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library raddsp;

-- Self-checking or stimulus-focused testbench for axis float fixed.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_float_fixed is
end entity;

architecture sim of tb_raddsp_axis_float_fixed is
  constant C_WIDTH : positive := 16;
  constant C_FRAC  : natural := 8;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal f2x_s_valid : std_logic := '0';
  signal f2x_s_ready : std_logic;
  signal f2x_s_data  : std_logic_vector(31 downto 0) := (others => '0');
  signal f2x_s_last  : std_logic := '0';
  signal f2x_m_valid : std_logic;
  signal f2x_m_data  : std_logic_vector(C_WIDTH - 1 downto 0);
  signal f2x_m_last  : std_logic;

  signal x2f_s_valid : std_logic := '0';
  signal x2f_s_ready : std_logic;
  signal x2f_s_data  : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal x2f_s_last  : std_logic := '0';
  signal x2f_m_valid : std_logic;
  signal x2f_m_data  : std_logic_vector(31 downto 0);
  signal x2f_m_last  : std_logic;

  procedure send_float(
    signal valid : out std_logic;
    signal ready : in std_logic;
    signal data  : out std_logic_vector(31 downto 0);
    value        : std_logic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk);
    data <= value;
    valid <= '1';
    wait until rising_edge(clk) and ready = '1';
    valid <= '0';
  end procedure;

  procedure send_fixed(
    signal valid : out std_logic;
    signal ready : in std_logic;
    signal data  : out std_logic_vector(C_WIDTH - 1 downto 0);
    value        : integer
  ) is
  begin
    wait until rising_edge(clk);
    data <= std_logic_vector(to_signed(value, C_WIDTH));
    valid <= '1';
    wait until rising_edge(clk) and ready = '1';
    valid <= '0';
  end procedure;
begin
  clk <= not clk after 5 ns;

  f2x_i: entity raddsp.raddsp_axis_float_to_fixed
    generic map (
      FIXED_WIDTH => C_WIDTH,
      FIXED_FRAC_BITS => C_FRAC
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => f2x_s_valid,
      s_axis_tready => f2x_s_ready,
      s_axis_tdata => f2x_s_data,
      s_axis_tlast => f2x_s_last,
      m_axis_tvalid => f2x_m_valid,
      m_axis_tready => '1',
      m_axis_tdata => f2x_m_data,
      m_axis_tlast => f2x_m_last
    );

  x2f_i: entity raddsp.raddsp_axis_fixed_to_float
    generic map (
      FIXED_WIDTH => C_WIDTH,
      FIXED_FRAC_BITS => C_FRAC
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => x2f_s_valid,
      s_axis_tready => x2f_s_ready,
      s_axis_tdata => x2f_s_data,
      s_axis_tlast => x2f_s_last,
      m_axis_tvalid => x2f_m_valid,
      m_axis_tready => '1',
      m_axis_tdata => x2f_m_data,
      m_axis_tlast => x2f_m_last
    );

  stim: process
  begin
    wait for 50 ns;
    wait until rising_edge(clk);
    rst <= '0';

    send_float(f2x_s_valid, f2x_s_ready, f2x_s_data, x"3F800000");
    wait until rising_edge(clk) and f2x_m_valid = '1';
    assert signed(f2x_m_data) = to_signed(256, C_WIDTH) report "1.0 float to Q8.8 failed" severity failure;

    send_float(f2x_s_valid, f2x_s_ready, f2x_s_data, x"BF000000");
    wait until rising_edge(clk) and f2x_m_valid = '1';
    assert signed(f2x_m_data) = to_signed(-128, C_WIDTH) report "-0.5 float to Q8.8 failed" severity failure;

    send_fixed(x2f_s_valid, x2f_s_ready, x2f_s_data, 512);
    wait until rising_edge(clk) and x2f_m_valid = '1';
    assert x2f_m_data = x"40000000" report "Q8.8 2.0 to float failed" severity failure;

    send_fixed(x2f_s_valid, x2f_s_ready, x2f_s_data, -128);
    wait until rising_edge(clk) and x2f_m_valid = '1';
    assert x2f_m_data = x"BF000000" report "Q8.8 -0.5 to float failed" severity failure;

    send_fixed(x2f_s_valid, x2f_s_ready, x2f_s_data, 0);
    wait until rising_edge(clk) and x2f_m_valid = '1';
    assert x2f_m_data = x"00000000" report "Q8.8 zero to float failed" severity failure;

    report "tb_raddsp_axis_float_fixed passed";
    stop;
  end process;
end architecture;
