library ieee;
use ieee.std_logic_1164.all;

-- RAD-owned VHDL vector wrapper around one ECP5 DP16KD configured as
-- 18x1024 true dual-port RAM. Wider/deeper memories should bank this wrapper.
entity radhdl_ecp5_dp16kd_18x1024 is
  port (
    clka  : in  std_logic;
    wea   : in  std_logic;
    addra : in  std_logic_vector(9 downto 0);
    dia   : in  std_logic_vector(17 downto 0);
    doa   : out std_logic_vector(17 downto 0);
    clkb  : in  std_logic;
    web   : in  std_logic;
    addrb : in  std_logic_vector(9 downto 0);
    dib   : in  std_logic_vector(17 downto 0);
    dob   : out std_logic_vector(17 downto 0)
  );
end entity;

architecture rtl of radhdl_ecp5_dp16kd_18x1024 is
  component DP16KD is
    generic (
      DATA_WIDTH_A : integer := 18;
      DATA_WIDTH_B : integer := 18;
      REGMODE_A    : string  := "NOREG";
      REGMODE_B    : string  := "NOREG";
      RESETMODE    : string  := "SYNC";
      CSDECODE_A   : string  := "0b000";
      CSDECODE_B   : string  := "0b000";
      WRITEMODE_A  : string  := "NORMAL";
      WRITEMODE_B  : string  := "NORMAL";
      GSR          : string  := "AUTO"
    );
    port (
      CLKA : in std_logic; CEA : in std_logic; OCEA : in std_logic; WEA : in std_logic; RSTA : in std_logic;
      CSA0 : in std_logic; CSA1 : in std_logic; CSA2 : in std_logic;
      ADA0 : in std_logic; ADA1 : in std_logic; ADA2 : in std_logic; ADA3 : in std_logic;
      ADA4 : in std_logic; ADA5 : in std_logic; ADA6 : in std_logic; ADA7 : in std_logic;
      ADA8 : in std_logic; ADA9 : in std_logic; ADA10 : in std_logic; ADA11 : in std_logic;
      ADA12 : in std_logic; ADA13 : in std_logic;
      DIA0 : in std_logic; DIA1 : in std_logic; DIA2 : in std_logic; DIA3 : in std_logic;
      DIA4 : in std_logic; DIA5 : in std_logic; DIA6 : in std_logic; DIA7 : in std_logic;
      DIA8 : in std_logic; DIA9 : in std_logic; DIA10 : in std_logic; DIA11 : in std_logic;
      DIA12 : in std_logic; DIA13 : in std_logic; DIA14 : in std_logic; DIA15 : in std_logic;
      DIA16 : in std_logic; DIA17 : in std_logic;
      DOA0 : out std_logic; DOA1 : out std_logic; DOA2 : out std_logic; DOA3 : out std_logic;
      DOA4 : out std_logic; DOA5 : out std_logic; DOA6 : out std_logic; DOA7 : out std_logic;
      DOA8 : out std_logic; DOA9 : out std_logic; DOA10 : out std_logic; DOA11 : out std_logic;
      DOA12 : out std_logic; DOA13 : out std_logic; DOA14 : out std_logic; DOA15 : out std_logic;
      DOA16 : out std_logic; DOA17 : out std_logic;
      CLKB : in std_logic; CEB : in std_logic; OCEB : in std_logic; WEB : in std_logic; RSTB : in std_logic;
      CSB0 : in std_logic; CSB1 : in std_logic; CSB2 : in std_logic;
      ADB0 : in std_logic; ADB1 : in std_logic; ADB2 : in std_logic; ADB3 : in std_logic;
      ADB4 : in std_logic; ADB5 : in std_logic; ADB6 : in std_logic; ADB7 : in std_logic;
      ADB8 : in std_logic; ADB9 : in std_logic; ADB10 : in std_logic; ADB11 : in std_logic;
      ADB12 : in std_logic; ADB13 : in std_logic;
      DIB0 : in std_logic; DIB1 : in std_logic; DIB2 : in std_logic; DIB3 : in std_logic;
      DIB4 : in std_logic; DIB5 : in std_logic; DIB6 : in std_logic; DIB7 : in std_logic;
      DIB8 : in std_logic; DIB9 : in std_logic; DIB10 : in std_logic; DIB11 : in std_logic;
      DIB12 : in std_logic; DIB13 : in std_logic; DIB14 : in std_logic; DIB15 : in std_logic;
      DIB16 : in std_logic; DIB17 : in std_logic;
      DOB0 : out std_logic; DOB1 : out std_logic; DOB2 : out std_logic; DOB3 : out std_logic;
      DOB4 : out std_logic; DOB5 : out std_logic; DOB6 : out std_logic; DOB7 : out std_logic;
      DOB8 : out std_logic; DOB9 : out std_logic; DOB10 : out std_logic; DOB11 : out std_logic;
      DOB12 : out std_logic; DOB13 : out std_logic; DOB14 : out std_logic; DOB15 : out std_logic;
      DOB16 : out std_logic; DOB17 : out std_logic
    );
  end component;
begin
  u_ram : DP16KD
    generic map (
      DATA_WIDTH_A => 18,
      DATA_WIDTH_B => 18,
      REGMODE_A => "NOREG",
      REGMODE_B => "NOREG",
      RESETMODE => "SYNC",
      CSDECODE_A => "0b000",
      CSDECODE_B => "0b000",
      WRITEMODE_A => "NORMAL",
      WRITEMODE_B => "NORMAL",
      GSR => "AUTO"
    )
    port map (
      CLKA => clka, CEA => '1', OCEA => '1', WEA => wea, RSTA => '0',
      CSA0 => '0', CSA1 => '0', CSA2 => '0',
      ADA0 => '1', ADA1 => '1', ADA2 => addra(0), ADA3 => addra(1),
      ADA4 => addra(2), ADA5 => addra(3), ADA6 => addra(4), ADA7 => addra(5),
      ADA8 => addra(6), ADA9 => addra(7), ADA10 => addra(8), ADA11 => addra(9),
      ADA12 => '0', ADA13 => '0',
      DIA0 => dia(0), DIA1 => dia(1), DIA2 => dia(2), DIA3 => dia(3),
      DIA4 => dia(4), DIA5 => dia(5), DIA6 => dia(6), DIA7 => dia(7),
      DIA8 => dia(8), DIA9 => dia(9), DIA10 => dia(10), DIA11 => dia(11),
      DIA12 => dia(12), DIA13 => dia(13), DIA14 => dia(14), DIA15 => dia(15),
      DIA16 => dia(16), DIA17 => dia(17),
      DOA0 => doa(0), DOA1 => doa(1), DOA2 => doa(2), DOA3 => doa(3),
      DOA4 => doa(4), DOA5 => doa(5), DOA6 => doa(6), DOA7 => doa(7),
      DOA8 => doa(8), DOA9 => doa(9), DOA10 => doa(10), DOA11 => doa(11),
      DOA12 => doa(12), DOA13 => doa(13), DOA14 => doa(14), DOA15 => doa(15),
      DOA16 => doa(16), DOA17 => doa(17),
      CLKB => clkb, CEB => '1', OCEB => '1', WEB => web, RSTB => '0',
      CSB0 => '0', CSB1 => '0', CSB2 => '0',
      ADB0 => '1', ADB1 => '1', ADB2 => addrb(0), ADB3 => addrb(1),
      ADB4 => addrb(2), ADB5 => addrb(3), ADB6 => addrb(4), ADB7 => addrb(5),
      ADB8 => addrb(6), ADB9 => addrb(7), ADB10 => addrb(8), ADB11 => addrb(9),
      ADB12 => '0', ADB13 => '0',
      DIB0 => dib(0), DIB1 => dib(1), DIB2 => dib(2), DIB3 => dib(3),
      DIB4 => dib(4), DIB5 => dib(5), DIB6 => dib(6), DIB7 => dib(7),
      DIB8 => dib(8), DIB9 => dib(9), DIB10 => dib(10), DIB11 => dib(11),
      DIB12 => dib(12), DIB13 => dib(13), DIB14 => dib(14), DIB15 => dib(15),
      DIB16 => dib(16), DIB17 => dib(17),
      DOB0 => dob(0), DOB1 => dob(1), DOB2 => dob(2), DOB3 => dob(3),
      DOB4 => dob(4), DOB5 => dob(5), DOB6 => dob(6), DOB7 => dob(7),
      DOB8 => dob(8), DOB9 => dob(9), DOB10 => dob(10), DOB11 => dob(11),
      DOB12 => dob(12), DOB13 => dob(13), DOB14 => dob(14), DOB15 => dob(15),
      DOB16 => dob(16), DOB17 => dob(17)
    );
end architecture;
