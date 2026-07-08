library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- FFT twiddle-factor package for RadDSP transform cores.
-- Provides constants and lookup helpers for fixed-point sine/cosine coefficients used by RadFFT implementations.
package raddsp_fft_twiddle_pkg is
  function radfft_twiddle_re(points : positive; exponent : natural; width : positive) return integer;
  function radfft_twiddle_im(points : positive; exponent : natural; width : positive; inverse_fft : boolean) return integer;
end package;

package body raddsp_fft_twiddle_pkg is
  function cos_q14(index : natural) return integer is
  begin
    case index mod 64 is
      when 0 => return 16384;
      when 1 => return 16305;
      when 2 => return 16069;
      when 3 => return 15679;
      when 4 => return 15137;
      when 5 => return 14449;
      when 6 => return 13623;
      when 7 => return 12665;
      when 8 => return 11585;
      when 9 => return 10394;
      when 10 => return 9102;
      when 11 => return 7723;
      when 12 => return 6270;
      when 13 => return 4756;
      when 14 => return 3196;
      when 15 => return 1606;
      when 16 => return 0;
      when 17 => return -1606;
      when 18 => return -3196;
      when 19 => return -4756;
      when 20 => return -6270;
      when 21 => return -7723;
      when 22 => return -9102;
      when 23 => return -10394;
      when 24 => return -11585;
      when 25 => return -12665;
      when 26 => return -13623;
      when 27 => return -14449;
      when 28 => return -15137;
      when 29 => return -15679;
      when 30 => return -16069;
      when 31 => return -16305;
      when 32 => return -16384;
      when 33 => return -16305;
      when 34 => return -16069;
      when 35 => return -15679;
      when 36 => return -15137;
      when 37 => return -14449;
      when 38 => return -13623;
      when 39 => return -12665;
      when 40 => return -11585;
      when 41 => return -10394;
      when 42 => return -9102;
      when 43 => return -7723;
      when 44 => return -6270;
      when 45 => return -4756;
      when 46 => return -3196;
      when 47 => return -1606;
      when 48 => return 0;
      when 49 => return 1606;
      when 50 => return 3196;
      when 51 => return 4756;
      when 52 => return 6270;
      when 53 => return 7723;
      when 54 => return 9102;
      when 55 => return 10394;
      when 56 => return 11585;
      when 57 => return 12665;
      when 58 => return 13623;
      when 59 => return 14449;
      when 60 => return 15137;
      when 61 => return 15679;
      when 62 => return 16069;
      when others => return 16305;
    end case;
  end function;

  function sin_neg_q14(index : natural) return integer is
  begin
    case index mod 64 is
      when 0 => return 0;
      when 1 => return -1606;
      when 2 => return -3196;
      when 3 => return -4756;
      when 4 => return -6270;
      when 5 => return -7723;
      when 6 => return -9102;
      when 7 => return -10394;
      when 8 => return -11585;
      when 9 => return -12665;
      when 10 => return -13623;
      when 11 => return -14449;
      when 12 => return -15137;
      when 13 => return -15679;
      when 14 => return -16069;
      when 15 => return -16305;
      when 16 => return -16384;
      when 17 => return -16305;
      when 18 => return -16069;
      when 19 => return -15679;
      when 20 => return -15137;
      when 21 => return -14449;
      when 22 => return -13623;
      when 23 => return -12665;
      when 24 => return -11585;
      when 25 => return -10394;
      when 26 => return -9102;
      when 27 => return -7723;
      when 28 => return -6270;
      when 29 => return -4756;
      when 30 => return -3196;
      when 31 => return -1606;
      when 32 => return 0;
      when 33 => return 1606;
      when 34 => return 3196;
      when 35 => return 4756;
      when 36 => return 6270;
      when 37 => return 7723;
      when 38 => return 9102;
      when 39 => return 10394;
      when 40 => return 11585;
      when 41 => return 12665;
      when 42 => return 13623;
      when 43 => return 14449;
      when 44 => return 15137;
      when 45 => return 15679;
      when 46 => return 16069;
      when 47 => return 16305;
      when 48 => return 16384;
      when 49 => return 16305;
      when 50 => return 16069;
      when 51 => return 15679;
      when 52 => return 15137;
      when 53 => return 14449;
      when 54 => return 13623;
      when 55 => return 12665;
      when 56 => return 11585;
      when 57 => return 10394;
      when 58 => return 9102;
      when 59 => return 7723;
      when 60 => return 6270;
      when 61 => return 4756;
      when 62 => return 3196;
      when others => return 1606;
    end case;
  end function;

  function table_index(points : positive; exponent : natural) return natural is
    variable idx : natural := exponent mod points;
    variable scale : positive;
  begin
    if points >= 64 then
      scale := points / 64;
      while scale > 1 loop
        idx := idx / 2;
        scale := scale / 2;
      end loop;
      return idx;
    end if;

    scale := 64 / points;
    while scale > 1 loop
      idx := idx + idx;
      scale := scale / 2;
    end loop;
    return idx mod 64;
  end function;

  function scaled_q14(value : integer; width : positive) return integer is
    variable result : integer := value;
  begin
    if width > 16 then
      for i in 17 to width loop
        result := result + result;
      end loop;
    elsif width < 16 then
      for i in width to 15 loop
        result := result / 2;
      end loop;
    end if;
    return result;
  end function;

  function radfft_twiddle_re(points : positive; exponent : natural; width : positive) return integer is
  begin
    return scaled_q14(cos_q14(table_index(points, exponent)), width);
  end function;

  function radfft_twiddle_im(points : positive; exponent : natural; width : positive; inverse_fft : boolean) return integer is
    variable value : integer;
  begin
    value := scaled_q14(sin_neg_q14(table_index(points, exponent)), width);
    if inverse_fft then
      return -value;
    end if;
    return value;
  end function;
end package body;
