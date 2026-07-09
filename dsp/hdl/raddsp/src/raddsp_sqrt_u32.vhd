library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Portable unsigned square-root primitive for control-rate DSP calculations.
-- Computes floor(sqrt(x_i)) combinationally for widths that fit in the VHDL
-- integer range. Streaming DSP blocks can replace this with a pipelined CORDIC
-- or non-restoring implementation when higher throughput is required.
entity raddsp_sqrt_u32 is
  generic (
    -- Width of the unsigned radicand.
    INPUT_WIDTH  : positive := 32;
    -- Width of the unsigned square-root result.
    OUTPUT_WIDTH : positive := 16
  );
  port (
    -- Unsigned input value.
    x_i     : in  std_logic_vector(INPUT_WIDTH - 1 downto 0);
    -- Floor square-root result.
    root_o  : out std_logic_vector(OUTPUT_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of raddsp_sqrt_u32 is
  function isqrt(value : natural) return natural is
    variable root : natural := 0;
  begin
    while (root + 1) * (root + 1) <= value loop
      root := root + 1;
    end loop;
    return root;
  end function;
begin
  assert INPUT_WIDTH <= 31
    report "raddsp_sqrt_u32 INPUT_WIDTH must fit in VHDL natural range"
    severity failure;

  process(all)
    variable value_v : natural;
    variable root_v  : natural;
  begin
    value_v := to_integer(unsigned(x_i));
    root_v := isqrt(value_v);
    root_o <= std_logic_vector(to_unsigned(root_v, OUTPUT_WIDTH));
  end process;
end architecture;
