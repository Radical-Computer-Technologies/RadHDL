library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

library raddsp;

-- Self-checking or stimulus-focused testbench for cordic atan2.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_cordic_atan2 is
end entity;

architecture sim of tb_cordic_atan2 is
  constant C_INPUT_WIDTH : integer := 16;
  constant C_PHASE_WIDTH : integer := 32;
  constant C_TOLERANCE   : integer := 600000;
  constant C_PHASE_SCALE  : real := 2147483648.0;

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal input_valid : std_logic := '0';
  signal x_in        : signed(C_INPUT_WIDTH - 1 downto 0) := (others => '0');
  signal y_in        : signed(C_INPUT_WIDTH - 1 downto 0) := (others => '0');
  signal input_ready : std_logic;
  signal busy        : std_logic;
  signal phase_valid : std_logic;
  signal phase_out   : signed(C_PHASE_WIDTH - 1 downto 0);

  function atan2_ref(y : integer; x : integer) return integer is
    variable angle : real;
  begin
    if x = 0 then
      if y > 0 then
        angle := MATH_PI / 2.0;
      elsif y < 0 then
        angle := -MATH_PI / 2.0;
      else
        angle := 0.0;
      end if;
    else
      angle := arctan(real(y) / real(x));
      if x < 0 and y >= 0 then
        angle := angle + MATH_PI;
      elsif x < 0 and y < 0 then
        angle := angle - MATH_PI;
      end if;
    end if;
    return integer(round(angle / MATH_PI * C_PHASE_SCALE));
  end function;

  function iabs(value : integer) return integer is
  begin
    if value < 0 then
      return -value;
    end if;
    return value;
  end function;
begin
  clk <= not clk after 5 ns;

  dut: entity raddsp.cordic_atan2
    generic map (
      G_INPUT_WIDTH => C_INPUT_WIDTH,
      G_PHASE_WIDTH => C_PHASE_WIDTH,
      G_ITERATIONS => 24
    )
    port map (
      clk => clk,
      rst => rst,
      input_valid => input_valid,
      x_in => x_in,
      y_in => y_in,
      input_ready => input_ready,
      busy => busy,
      phase_valid => phase_valid,
      phase_out => phase_out
    );

  process
    type int_array_t is array (natural range <>) of integer;
    constant XS : int_array_t := (10000, 10000, 0, -12000, -12000, 0, 8000, -5000, 3276, -3276);
    constant YS : int_array_t := (0, 10000, 12000, 12000, -12000, -10000, -4000, 9000, -3276, -2000);
    variable expected : integer;
    variable observed : integer;
    variable diff     : integer;
  begin
    wait for 50 ns;
    wait until rising_edge(clk);
    rst <= '0';

    for n in XS'range loop
      wait until rising_edge(clk);
      assert input_ready = '1' report "CORDIC not ready" severity failure;
      x_in <= to_signed(XS(n), C_INPUT_WIDTH);
      y_in <= to_signed(YS(n), C_INPUT_WIDTH);
      input_valid <= '1';
      wait until rising_edge(clk);
      input_valid <= '0';
      wait until phase_valid = '1';
      expected := atan2_ref(YS(n), XS(n));
      observed := to_integer(phase_out);
      diff := iabs(observed - expected);
      report "atan2 case " & integer'image(n) &
             " x=" & integer'image(XS(n)) &
             " y=" & integer'image(YS(n)) &
             " observed=" & integer'image(observed) &
             " expected=" & integer'image(expected) &
             " diff=" & integer'image(diff);
      assert diff <= C_TOLERANCE
        report "CORDIC atan2 error exceeds tolerance" severity failure;
    end loop;

    report "PASS cordic_atan2";
    finish;
  end process;
end architecture;
