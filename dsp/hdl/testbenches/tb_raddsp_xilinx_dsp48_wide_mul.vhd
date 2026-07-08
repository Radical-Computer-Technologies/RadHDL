library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

-- Self-checking or stimulus-focused testbench for xilinx dsp48 wide mul.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_xilinx_dsp48_wide_mul is
end entity;

architecture sim of tb_raddsp_xilinx_dsp48_wide_mul is
  constant C_AW : positive := 16;
  constant C_BW : positive := 16;
  constant C_PW : positive := 40;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal valid_i : std_logic := '0';
  signal a_i : signed(C_AW - 1 downto 0) := (others => '0');
  signal b_i : signed(C_BW - 1 downto 0) := (others => '0');
  signal valid_o : std_logic;
  signal p_o : signed(C_PW - 1 downto 0);
begin
  clk <= not clk after 5 ns;

  dut: entity work.raddsp_xilinx_dsp48_wide_mul
    generic map (
      DEVICE_FAMILY => "7series",
      A_WIDTH => C_AW,
      B_WIDTH => C_BW,
      PRODUCT_WIDTH => C_PW
    )
    port map (
      clk => clk,
      rst => rst,
      valid_i => valid_i,
      a_i => a_i,
      b_i => b_i,
      valid_o => valid_o,
      p_o => p_o
    );

  stim: process
  begin
    wait for 50 ns;
    wait until rising_edge(clk);
    rst <= '0';

    a_i <= to_signed(-900, C_AW);
    b_i <= to_signed(16384, C_BW);
    valid_i <= '1';
    wait until rising_edge(clk);
    valid_i <= '0';

    wait until rising_edge(clk);
    a_i <= to_signed(-763, C_AW);
    b_i <= to_signed(15137, C_BW);
    valid_i <= '1';
    wait until rising_edge(clk);
    valid_i <= '0';

    wait until rising_edge(clk);
    a_i <= to_signed(1155, C_AW);
    b_i <= to_signed(16384, C_BW);
    valid_i <= '1';
    wait until rising_edge(clk);
    valid_i <= '0';

    wait for 120 ns;
    stop;
  end process;

  capture: process(clk)
    file f : text open write_mode is "wide_mul.csv";
    variable l : line;
    variable wrote_header : boolean := false;
  begin
    if not wrote_header then
      write(l, string'("time,p"));
      writeline(f, l);
      wrote_header := true;
    end if;

    if rising_edge(clk) and valid_o = '1' then
      write(l, now / 1 ns);
      write(l, string'(","));
      write(l, to_integer(p_o));
      writeline(f, l);
    end if;
  end process;
end architecture;
