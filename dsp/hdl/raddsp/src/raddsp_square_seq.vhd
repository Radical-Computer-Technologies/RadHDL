library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Vendor-selected sequential square helper backed by RAD hard multiplier wrappers.
entity raddsp_square_seq is
  generic (
    VENDOR        : string := "xilinx";
    DEVICE_FAMILY : string := "7series";
    WIDTH         : positive := 32
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start_i : in  std_logic;
    x_i     : in  signed(WIDTH - 1 downto 0);
    busy_o  : out std_logic;
    valid_o : out std_logic;
    y_o     : out unsigned((2 * WIDTH) - 1 downto 0)
  );
end entity;

architecture rtl of raddsp_square_seq is
  signal mul_valid : std_logic := '0';
  signal mul_done  : std_logic;
  signal mul_p     : signed((2 * WIDTH) - 1 downto 0);
begin
  busy_o <= mul_valid;
  valid_o <= mul_done;
  y_o <= unsigned(mul_p);

  mul_i : entity work.raddsp_wide_mul
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      A_WIDTH => WIDTH,
      B_WIDTH => WIDTH,
      PRODUCT_WIDTH => 2 * WIDTH
    )
    port map (
      clk => clk,
      rst => rst,
      valid_i => start_i,
      a_i => x_i,
      b_i => x_i,
      valid_o => mul_done,
      p_o => mul_p
    );

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        mul_valid <= '0';
      elsif start_i = '1' then
        mul_valid <= '1';
      elsif mul_done = '1' then
        mul_valid <= '0';
      end if;
    end if;
  end process;
end architecture;
