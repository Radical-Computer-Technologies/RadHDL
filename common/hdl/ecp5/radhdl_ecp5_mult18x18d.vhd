library ieee;
use ieee.std_logic_1164.all;

-- RAD-owned VHDL vector wrapper around the ECP5 MULT18X18D hard multiplier.
-- The public ports match raddsp_lattice_mul's tiled multiplier needs.
entity radhdl_ecp5_mult18x18d is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    ce  : in  std_logic;
    a   : in  std_logic_vector(17 downto 0);
    b   : in  std_logic_vector(17 downto 0);
    p   : out std_logic_vector(35 downto 0)
  );
end entity;

architecture rtl of radhdl_ecp5_mult18x18d is
  component MULT18X18D is
    generic (
      REG_INPUTA_CLK   : string := "NONE";
      REG_INPUTB_CLK   : string := "NONE";
      REG_INPUTC_CLK   : string := "NONE";
      REG_PIPELINE_CLK : string := "NONE";
      REG_OUTPUT_CLK   : string := "NONE";
      GSR              : string := "AUTO"
    );
    port (
      A0 : in std_logic; A1 : in std_logic; A2 : in std_logic; A3 : in std_logic;
      A4 : in std_logic; A5 : in std_logic; A6 : in std_logic; A7 : in std_logic;
      A8 : in std_logic; A9 : in std_logic; A10 : in std_logic; A11 : in std_logic;
      A12 : in std_logic; A13 : in std_logic; A14 : in std_logic; A15 : in std_logic;
      A16 : in std_logic; A17 : in std_logic;
      B0 : in std_logic; B1 : in std_logic; B2 : in std_logic; B3 : in std_logic;
      B4 : in std_logic; B5 : in std_logic; B6 : in std_logic; B7 : in std_logic;
      B8 : in std_logic; B9 : in std_logic; B10 : in std_logic; B11 : in std_logic;
      B12 : in std_logic; B13 : in std_logic; B14 : in std_logic; B15 : in std_logic;
      B16 : in std_logic; B17 : in std_logic;
      C0 : in std_logic; C1 : in std_logic; C2 : in std_logic; C3 : in std_logic;
      C4 : in std_logic; C5 : in std_logic; C6 : in std_logic; C7 : in std_logic;
      C8 : in std_logic; C9 : in std_logic; C10 : in std_logic; C11 : in std_logic;
      C12 : in std_logic; C13 : in std_logic; C14 : in std_logic; C15 : in std_logic;
      C16 : in std_logic; C17 : in std_logic;
      SIGNEDA : in std_logic; SIGNEDB : in std_logic; SOURCEA : in std_logic; SOURCEB : in std_logic;
      P0 : out std_logic; P1 : out std_logic; P2 : out std_logic; P3 : out std_logic;
      P4 : out std_logic; P5 : out std_logic; P6 : out std_logic; P7 : out std_logic;
      P8 : out std_logic; P9 : out std_logic; P10 : out std_logic; P11 : out std_logic;
      P12 : out std_logic; P13 : out std_logic; P14 : out std_logic; P15 : out std_logic;
      P16 : out std_logic; P17 : out std_logic; P18 : out std_logic; P19 : out std_logic;
      P20 : out std_logic; P21 : out std_logic; P22 : out std_logic; P23 : out std_logic;
      P24 : out std_logic; P25 : out std_logic; P26 : out std_logic; P27 : out std_logic;
      P28 : out std_logic; P29 : out std_logic; P30 : out std_logic; P31 : out std_logic;
      P32 : out std_logic; P33 : out std_logic; P34 : out std_logic; P35 : out std_logic
    );
  end component;

  signal unused_i : std_logic;
begin
  unused_i <= clk xor rst xor ce;

  u_mult : MULT18X18D
    generic map (
      REG_INPUTA_CLK => "NONE",
      REG_INPUTB_CLK => "NONE",
      REG_INPUTC_CLK => "NONE",
      REG_PIPELINE_CLK => "NONE",
      REG_OUTPUT_CLK => "NONE",
      GSR => "AUTO"
    )
    port map (
      A0 => a(0), A1 => a(1), A2 => a(2), A3 => a(3), A4 => a(4), A5 => a(5),
      A6 => a(6), A7 => a(7), A8 => a(8), A9 => a(9), A10 => a(10), A11 => a(11),
      A12 => a(12), A13 => a(13), A14 => a(14), A15 => a(15), A16 => a(16), A17 => a(17),
      B0 => b(0), B1 => b(1), B2 => b(2), B3 => b(3), B4 => b(4), B5 => b(5),
      B6 => b(6), B7 => b(7), B8 => b(8), B9 => b(9), B10 => b(10), B11 => b(11),
      B12 => b(12), B13 => b(13), B14 => b(14), B15 => b(15), B16 => b(16), B17 => b(17),
      C0 => '0', C1 => '0', C2 => '0', C3 => '0', C4 => '0', C5 => '0',
      C6 => '0', C7 => '0', C8 => '0', C9 => '0', C10 => '0', C11 => '0',
      C12 => '0', C13 => '0', C14 => '0', C15 => '0', C16 => '0', C17 => '0',
      SIGNEDA => '1', SIGNEDB => '1', SOURCEA => '0', SOURCEB => '0',
      P0 => p(0), P1 => p(1), P2 => p(2), P3 => p(3), P4 => p(4), P5 => p(5),
      P6 => p(6), P7 => p(7), P8 => p(8), P9 => p(9), P10 => p(10), P11 => p(11),
      P12 => p(12), P13 => p(13), P14 => p(14), P15 => p(15), P16 => p(16), P17 => p(17),
      P18 => p(18), P19 => p(19), P20 => p(20), P21 => p(21), P22 => p(22), P23 => p(23),
      P24 => p(24), P25 => p(25), P26 => p(26), P27 => p(27), P28 => p(28), P29 => p(29),
      P30 => p(30), P31 => p(31), P32 => p(32), P33 => p(33), P34 => p(34), P35 => p(35)
    );
end architecture;
