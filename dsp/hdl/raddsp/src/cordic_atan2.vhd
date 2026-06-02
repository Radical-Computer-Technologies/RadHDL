library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cordic_atan_pkg.all;

entity cordic_atan2 is
  generic (
    G_INPUT_WIDTH  : integer := 16;
    G_PHASE_WIDTH  : integer := 32;
    G_ITERATIONS   : integer := 24
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    input_valid : in  std_logic;
    x_in        : in  signed(G_INPUT_WIDTH - 1 downto 0);
    y_in        : in  signed(G_INPUT_WIDTH - 1 downto 0);
    input_ready : out std_logic;
    busy        : out std_logic;
    phase_valid : out std_logic;
    phase_out   : out signed(G_PHASE_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of cordic_atan2 is
  -- Vectoring CORDIC magnitude grows by roughly 1.647. A few guard bits are
  -- enough for phase extraction; widening by the iteration count burns LUTs.
  constant C_WORK_WIDTH : integer := G_INPUT_WIDTH + 4;
  type work_pipe_t is array (0 to G_ITERATIONS) of signed(C_WORK_WIDTH - 1 downto 0);
  type phase_pipe_t is array (0 to G_ITERATIONS) of signed(G_PHASE_WIDTH - 1 downto 0);
  type valid_pipe_t is array (0 to G_ITERATIONS) of std_logic;

  signal x_pipe     : work_pipe_t := (others => (others => '0'));
  signal y_pipe     : work_pipe_t := (others => (others => '0'));
  signal z_pipe     : phase_pipe_t := (others => (others => '0'));
  signal valid_pipe : valid_pipe_t := (others => '0');

  function phase_const(index : integer) return signed is
    variable scaled : signed(31 downto 0);
  begin
    scaled := to_signed(CORDIC_ATAN(index), 32);
    return resize(shift_right(scaled, 32 - G_PHASE_WIDTH), G_PHASE_WIDTH);
  end function;

  function pi_const(positive : boolean) return signed is
    variable value : signed(31 downto 0);
  begin
    if positive then
      value := to_signed(CORDIC_PI_POS, 32);
    else
      value := to_signed(CORDIC_PI_NEG, 32);
    end if;
    return resize(shift_right(value, 32 - G_PHASE_WIDTH), G_PHASE_WIDTH);
  end function;

  function any_valid(value : valid_pipe_t) return std_logic is
    variable result : std_logic := '0';
  begin
    for i in value'range loop
      result := result or value(i);
    end loop;
    return result;
  end function;
begin
  input_ready <= '1';
  busy <= any_valid(valid_pipe);
  phase_valid <= valid_pipe(G_ITERATIONS);
  phase_out <= z_pipe(G_ITERATIONS);

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        x_pipe(0) <= (others => '0');
        y_pipe(0) <= (others => '0');
        z_pipe(0) <= (others => '0');
        valid_pipe(0) <= '0';
      else
        valid_pipe(0) <= input_valid;
        if input_valid = '1' then
          if x_in < 0 then
            x_pipe(0) <= resize(-x_in, C_WORK_WIDTH);
            y_pipe(0) <= resize(-y_in, C_WORK_WIDTH);
            if y_in >= 0 then
              z_pipe(0) <= pi_const(true);
            else
              z_pipe(0) <= pi_const(false);
            end if;
          else
            x_pipe(0) <= resize(x_in, C_WORK_WIDTH);
            y_pipe(0) <= resize(y_in, C_WORK_WIDTH);
            z_pipe(0) <= (others => '0');
          end if;
        else
          x_pipe(0) <= (others => '0');
          y_pipe(0) <= (others => '0');
          z_pipe(0) <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  cordic_pipeline: for i in 0 to G_ITERATIONS - 1 generate
    process(clk)
    begin
      if rising_edge(clk) then
        if rst = '1' then
          x_pipe(i + 1) <= (others => '0');
          y_pipe(i + 1) <= (others => '0');
          z_pipe(i + 1) <= (others => '0');
          valid_pipe(i + 1) <= '0';
        else
          valid_pipe(i + 1) <= valid_pipe(i);
          if valid_pipe(i) = '1' then
            if y_pipe(i) >= 0 then
              x_pipe(i + 1) <= x_pipe(i) + shift_right(y_pipe(i), i);
              y_pipe(i + 1) <= y_pipe(i) - shift_right(x_pipe(i), i);
              z_pipe(i + 1) <= z_pipe(i) + phase_const(i);
            else
              x_pipe(i + 1) <= x_pipe(i) - shift_right(y_pipe(i), i);
              y_pipe(i + 1) <= y_pipe(i) + shift_right(x_pipe(i), i);
              z_pipe(i + 1) <= z_pipe(i) - phase_const(i);
            end if;
          else
            x_pipe(i + 1) <= (others => '0');
            y_pipe(i + 1) <= (others => '0');
            z_pipe(i + 1) <= (others => '0');
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
