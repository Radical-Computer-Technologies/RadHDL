library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Shared RadIF register-interface package.
-- Defines register response constants, address/data records, and utility functions used by RadIF bridges and register banks.
package radif_pkg is
  type radif_reg_array_t is array (natural range <>) of std_logic_vector;

  constant RADIF_OP_NOP          : std_logic_vector(7 downto 0) := x"00";
  constant RADIF_OP_REG_WRITE    : std_logic_vector(7 downto 0) := x"01";
  constant RADIF_OP_REG_READ     : std_logic_vector(7 downto 0) := x"02";
  constant RADIF_OP_STREAM_WRITE : std_logic_vector(7 downto 0) := x"10";
  constant RADIF_OP_STREAM_READ  : std_logic_vector(7 downto 0) := x"11";
  constant RADIF_OP_CAPS         : std_logic_vector(7 downto 0) := x"7F";

  constant RADIF_STATUS_OK       : std_logic_vector(7 downto 0) := x"00";
  constant RADIF_STATUS_ERROR    : std_logic_vector(7 downto 0) := x"01";
  constant RADIF_STATUS_BAD_CRC  : std_logic_vector(7 downto 0) := x"02";
  constant RADIF_STATUS_BAD_OP   : std_logic_vector(7 downto 0) := x"03";

  function radif_crc16_step(
    crc_in  : std_logic_vector(15 downto 0);
    data_in : std_logic_vector(7 downto 0)
  ) return std_logic_vector;

  function radif_word_bytes(data : std_logic_vector) return natural;
end package;

package body radif_pkg is
  function radif_crc16_step(
    crc_in  : std_logic_vector(15 downto 0);
    data_in : std_logic_vector(7 downto 0)
  ) return std_logic_vector is
    variable crc : unsigned(15 downto 0) := unsigned(crc_in);
    variable dat : unsigned(7 downto 0) := unsigned(data_in);
    variable mix : std_logic;
  begin
    for i in 7 downto 0 loop
      mix := std_logic(crc(15)) xor std_logic(dat(i));
      crc := crc(14 downto 0) & '0';
      if mix = '1' then
        crc := crc xor x"1021";
      end if;
    end loop;
    return std_logic_vector(crc);
  end function;

  function radif_word_bytes(data : std_logic_vector) return natural is
  begin
    return (data'length + 7) / 8;
  end function;
end package body;
