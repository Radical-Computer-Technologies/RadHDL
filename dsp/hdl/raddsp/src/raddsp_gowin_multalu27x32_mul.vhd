library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Signed 27x32 multiply built from two Gowin GW5A MULTALU27X18 blocks.
-- The coefficient operand is split as signed high 18 bits plus unsigned low
-- 14 bits, preserving exact two's-complement reconstruction:
--   b32 = signed(b31:14) * 2^14 + unsigned(b13:0)
entity raddsp_gowin_multalu27x32_mul is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    ce  : in  std_logic;
    a_i : in  std_logic_vector(26 downto 0);
    b_i : in  std_logic_vector(31 downto 0);
    p_o : out std_logic_vector(63 downto 0)
  );
end entity;

architecture rtl of raddsp_gowin_multalu27x32_mul is
  signal b_hi_s : std_logic_vector(17 downto 0);
  signal b_lo_u : std_logic_vector(17 downto 0);
  signal p_hi_s : std_logic_vector(44 downto 0);
  signal p_lo_s : std_logic_vector(44 downto 0);
  signal p_r    : std_logic_vector(63 downto 0) := (others => '0');
begin
  b_hi_s <= b_i(31 downto 14);
  b_lo_u <= "0000" & b_i(13 downto 0);

  u_hi : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => ce,
      a_i => a_i,
      b_i => b_hi_s,
      p_o => p_hi_s
    );

  u_lo : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => ce,
      a_i => a_i,
      b_i => b_lo_u,
      p_o => p_lo_s
    );

  p_o <= p_r;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p_r <= (others => '0');
      elsif ce = '1' then
        p_r <= std_logic_vector(shift_left(resize(signed(p_hi_s), 64), 14) + resize(signed(p_lo_s), 64));
      end if;
    end if;
  end process;
end architecture;
