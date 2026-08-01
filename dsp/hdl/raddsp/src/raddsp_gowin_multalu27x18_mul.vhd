library ieee;
use ieee.std_logic_1164.all;

library gw5a;
use gw5a.components.all;

-- Signed 27x18 multiply backed by the Gowin GW5A MULTALU27X18 primitive.
entity raddsp_gowin_multalu27x18_mul is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    ce  : in  std_logic;
    a_i : in  std_logic_vector(26 downto 0);
    b_i : in  std_logic_vector(17 downto 0);
    p_o : out std_logic_vector(44 downto 0)
  );
end entity;

architecture rtl of raddsp_gowin_multalu27x18_mul is
  signal dout_s : std_logic_vector(47 downto 0);
begin
  p_o <= dout_s(44 downto 0);

  u_mult : MULTALU27X18
    generic map (
      AREG_CLK => "CLK0",
      AREG_CE => "CE0",
      AREG_RESET => "RESET0",
      BREG_CLK => "CLK0",
      BREG_CE => "CE0",
      BREG_RESET => "RESET0",
      OREG_CLK => "CLK0",
      OREG_CE => "CE0",
      OREG_RESET => "RESET0",
      MULT_RESET_MODE => "SYNC",
      C_SEL => '1',
      CASI_SEL => '0',
      ADD_SUB_0 => '0',
      ADD_SUB_1 => '0',
      MULT12X12_EN => "FALSE"
    )
    port map (
      A => a_i,
      SIA => (others => '0'),
      B => b_i,
      D => (others => '0'),
      C => (others => '0'),
      CASI => (others => '0'),
      ACCSEL => '0',
      PSEL => '0',
      ASEL => '0',
      PADDSUB => '0',
      CSEL => '1',
      CASISEL => '0',
      ADDSUB => "00",
      CE => '0' & ce,
      CLK => '0' & clk,
      RESET => '0' & rst,
      DOUT => dout_s,
      SOA => open,
      CASO => open
    );
end architecture;
