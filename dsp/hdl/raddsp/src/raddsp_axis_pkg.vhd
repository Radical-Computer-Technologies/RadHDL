library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Shared RadDSP AXI-stream helper package.
-- Defines fixed-point saturation, packing, arithmetic, and stream utility functions used by RadDSP sample-processing cores.
package raddsp_axis_pkg is
  function raddsp_clog2(value : positive) return natural;
  function raddsp_max_int(width : positive) return integer;
  function raddsp_min_int(width : positive) return integer;
  function raddsp_sat_signed(value : integer; width : positive) return signed;
  function raddsp_sat_signed_vec(value : signed; width : positive) return signed;
  function raddsp_abs_int(value : integer) return integer;
end package;

package body raddsp_axis_pkg is
  function raddsp_clog2(value : positive) return natural is
    variable v : natural := value - 1;
    variable r : natural := 0;
  begin
    while v > 0 loop
      v := v / 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function raddsp_max_int(width : positive) return integer is
    variable result : integer := 1;
  begin
    for i in 1 to width - 1 loop
      result := result * 2;
    end loop;
    return result - 1;
  end function;

  function raddsp_min_int(width : positive) return integer is
    variable result : integer := 1;
  begin
    for i in 1 to width - 1 loop
      result := result * 2;
    end loop;
    return -result;
  end function;

  function raddsp_sat_signed(value : integer; width : positive) return signed is
    variable result : signed(width - 1 downto 0);
    variable clipped : integer;
  begin
    clipped := value;
    if clipped > raddsp_max_int(width) then
      clipped := raddsp_max_int(width);
    elsif clipped < raddsp_min_int(width) then
      clipped := raddsp_min_int(width);
    end if;
    result := to_signed(clipped, width);
    return result;
  end function;

  function raddsp_sat_signed_vec(value : signed; width : positive) return signed is
    variable v        : signed(value'length - 1 downto 0) := value;
    variable result   : signed(width - 1 downto 0) := (others => '0');
    variable overflow : boolean := false;
  begin
    if value'length <= width then
      return resize(v, width);
    end if;

    if v(v'high) = '0' then
      if v(width - 1) = '1' then
        overflow := true;
      end if;
      for i in v'high downto width loop
        if v(i) = '1' then
          overflow := true;
        end if;
      end loop;
      if overflow then
        result := (others => '1');
        result(result'high) := '0';
        return result;
      end if;
    else
      if v(width - 1) = '0' then
        overflow := true;
      end if;
      for i in v'high downto width loop
        if v(i) = '0' then
          overflow := true;
        end if;
      end loop;
      if overflow then
        result := (others => '0');
        result(result'high) := '1';
        return result;
      end if;
    end if;

    result := v(width - 1 downto 0);
    return result;
  end function;

  function raddsp_abs_int(value : integer) return integer is
  begin
    if value < 0 then
      return -value;
    end if;
    return value;
  end function;
end package body;
