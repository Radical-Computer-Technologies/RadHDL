library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package fpiga_audio_hat_tb_pkg is
  constant C_I2C_AUDIO_ADDR : std_logic_vector(6 downto 0) := "0010010";
  constant C_I2C_DEBUG_ADDR : std_logic_vector(6 downto 0) := "1000010";
  constant C_OP_REG_WRITE   : std_logic_vector(7 downto 0) := x"01";
  constant C_OP_REG_READ    : std_logic_vector(7 downto 0) := x"02";

  constant C_REG_CONTROL       : std_logic_vector(15 downto 0) := x"0000";
  constant C_REG_DSP_CONTROL   : std_logic_vector(15 downto 0) := x"0004";
  constant C_REG_FREQ0         : std_logic_vector(15 downto 0) := x"0008";
  constant C_REG_FREQ1         : std_logic_vector(15 downto 0) := x"000C";
  constant C_REG_FREQ2         : std_logic_vector(15 downto 0) := x"0010";
  constant C_REG_FREQ3         : std_logic_vector(15 downto 0) := x"0014";
  constant C_REG_LEFT_GAIN     : std_logic_vector(15 downto 0) := x"0018";
  constant C_REG_RIGHT_GAIN    : std_logic_vector(15 downto 0) := x"001C";
  constant C_REG_OSC0_GAIN     : std_logic_vector(15 downto 0) := x"0020";
  constant C_REG_OSC1_GAIN     : std_logic_vector(15 downto 0) := x"0024";
  constant C_REG_OSC2_GAIN     : std_logic_vector(15 downto 0) := x"0028";
  constant C_REG_OSC3_GAIN     : std_logic_vector(15 downto 0) := x"002C";
  constant C_REG_WAVE_CONTROL  : std_logic_vector(15 downto 0) := x"0030";
  constant C_REG_OSC_PAN       : std_logic_vector(15 downto 0) := x"0034";
  constant C_REG_GLOBAL_PAN    : std_logic_vector(15 downto 0) := x"0038";
  constant C_REG_WAVE_DATA     : std_logic_vector(15 downto 0) := x"003C";
  constant C_REG_POLY_FREQ0    : std_logic_vector(15 downto 0) := x"0040";
  constant C_REG_POLY_CTRL0    : std_logic_vector(15 downto 0) := x"0080";
  constant C_REG_POLY_VOLUME0  : std_logic_vector(15 downto 0) := x"00C0";
  constant C_REG_POLY_ADSR0    : std_logic_vector(15 downto 0) := x"0100";
  constant C_REG_RO_ID         : std_logic_vector(15 downto 0) := x"0180";
  constant C_REG_RO_VERSION    : std_logic_vector(15 downto 0) := x"0184";

  constant C_DBG_REG_ID           : std_logic_vector(15 downto 0) := x"0000";
  constant C_DBG_REG_VERSION      : std_logic_vector(15 downto 0) := x"0004";
  constant C_DBG_REG_CONTROL      : std_logic_vector(15 downto 0) := x"0008";
  constant C_DBG_REG_STATUS       : std_logic_vector(15 downto 0) := x"000C";
  constant C_DBG_REG_TRIG_MASK    : std_logic_vector(15 downto 0) := x"0010";
  constant C_DBG_REG_TRIG_VALUE   : std_logic_vector(15 downto 0) := x"0014";
  constant C_DBG_REG_POSTTRIG     : std_logic_vector(15 downto 0) := x"001C";
  constant C_DBG_REG_DATA_INDEX   : std_logic_vector(15 downto 0) := x"0020";
  constant C_DBG_REG_SAMPLE_DATA0 : std_logic_vector(15 downto 0) := x"0024";
  constant C_DBG_REG_SAMPLE_NOW0  : std_logic_vector(15 downto 0) := x"0028";
  constant C_DBG_REG_EVENT_NOW    : std_logic_vector(15 downto 0) := x"002C";
  constant C_DBG_REG_CAPS         : std_logic_vector(15 downto 0) := x"0030";
  constant C_DBG_REG_SAMPLE_DATA1 : std_logic_vector(15 downto 0) := x"0034";

  constant C_SAMPLE_RATE_HZ    : real := 48000.0;
  constant C_Q15_UNITY         : std_logic_vector(17 downto 0) := std_logic_vector(to_signed(32767, 18));
  constant C_Q15_UNITY_WORD    : std_logic_vector(31 downto 0) := "00000000000000" & C_Q15_UNITY;

  type byte_file_t is file of character;

  function phase_inc(freq_hz : real) return std_logic_vector;
  function sample24(value : integer) return std_logic_vector;
  function ramp_sample(index : natural; amplitude : integer) return std_logic_vector;
  function ramp_period_sample(index : natural; period : positive; amplitude : integer) return std_logic_vector;
  function sine_sample(index : natural; period : natural; amplitude : integer) return std_logic_vector;
  function wave_table_value(page : natural; index : natural) return std_logic_vector;

  procedure write_s32le_pair(
    file f : byte_file_t;
    left_sample : std_logic_vector(23 downto 0);
    right_sample : std_logic_vector(23 downto 0)
  );
end package;

package body fpiga_audio_hat_tb_pkg is
  function phase_inc(freq_hz : real) return std_logic_vector is
    variable inc : integer;
  begin
    inc := integer((freq_hz * real(2 ** 24)) / C_SAMPLE_RATE_HZ + 0.5);
    if inc < 0 then
      inc := 0;
    elsif inc > (2 ** 24) - 1 then
      inc := (2 ** 24) - 1;
    end if;
    return std_logic_vector(to_unsigned(inc, 24));
  end function;

  function sample24(value : integer) return std_logic_vector is
    variable clipped : integer := value;
  begin
    if clipped > (2 ** 23) - 1 then
      clipped := (2 ** 23) - 1;
    elsif clipped < -(2 ** 23) then
      clipped := -(2 ** 23);
    end if;
    return std_logic_vector(to_signed(clipped, 24));
  end function;

  function ramp_sample(index : natural; amplitude : integer) return std_logic_vector is
    variable phase : integer;
    variable value : integer;
  begin
    phase := integer(index mod 64);
    value := ((2 * amplitude * phase) / 63) - amplitude;
    return sample24(value);
  end function;

  function ramp_period_sample(index : natural; period : positive; amplitude : integer) return std_logic_vector is
    variable phase : integer;
    variable denom : integer;
    variable value : integer;
  begin
    phase := integer(index mod period);
    denom := integer(period) - 1;
    if denom <= 0 then
      return sample24(-amplitude);
    end if;
    value := ((2 * amplitude * phase) / denom) - amplitude;
    return sample24(value);
  end function;

  function sine_sample(index : natural; period : natural; amplitude : integer) return std_logic_vector is
    variable angle : real;
    variable value : integer;
  begin
    angle := 2.0 * math_pi * real(index mod period) / real(period);
    value := integer(real(amplitude) * sin(angle));
    return sample24(value);
  end function;

  function wave_table_value(page : natural; index : natural) return std_logic_vector is
    variable angle : real;
    variable value : integer := 0;
    variable ix : integer := integer(index mod 256);
  begin
    case page is
      when 0 =>
        angle := math_pi * real(ix) / 255.0;
        value := integer(30000.0 * sin(angle));
      when 1 =>
        value := 30000;
      when 2 =>
        if ix < 128 then
          value := (30000 * ix) / 127;
        else
          value := (30000 * (255 - ix)) / 127;
        end if;
      when others =>
        value := (30000 * ix) / 255;
    end case;
    return std_logic_vector(to_signed(value, 16));
  end function;

  procedure write_byte(file f : byte_file_t; b : std_logic_vector(7 downto 0)) is
  begin
    write(f, character'val(to_integer(unsigned(b))));
  end procedure;

  procedure write_s32le_pair(
    file f : byte_file_t;
    left_sample : std_logic_vector(23 downto 0);
    right_sample : std_logic_vector(23 downto 0)
  ) is
    variable l32 : std_logic_vector(31 downto 0);
    variable r32 : std_logic_vector(31 downto 0);
  begin
    l32 := std_logic_vector(resize(signed(left_sample), 32));
    r32 := std_logic_vector(resize(signed(right_sample), 32));
    write_byte(f, l32(7 downto 0));
    write_byte(f, l32(15 downto 8));
    write_byte(f, l32(23 downto 16));
    write_byte(f, l32(31 downto 24));
    write_byte(f, r32(7 downto 0));
    write_byte(f, r32(15 downto 8));
    write_byte(f, r32(23 downto 16));
    write_byte(f, r32(31 downto 24));
  end procedure;
end package body;
