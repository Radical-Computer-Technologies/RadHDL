library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Portable simulation model for the Xilinx DSP48 multiplier wrapper.
-- This model preserves the RadDSP handshake timing without requiring UNISIM.
entity raddsp_xilinx_dsp48_mul is
  generic (
    DEVICE_FAMILY : string := "7series";
    A_WIDTH       : positive := 16;
    B_WIDTH       : positive := 18
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    valid_i    : in  std_logic;
    subtract_i : in  std_logic;
    last_i     : in  std_logic;
    a_i        : in  signed(A_WIDTH - 1 downto 0);
    b_i        : in  signed(B_WIDTH - 1 downto 0);
    valid_o    : out std_logic;
    subtract_o : out std_logic;
    last_o     : out std_logic;
    p_o        : out signed(47 downto 0)
  );
end entity;

architecture sim of raddsp_xilinx_dsp48_mul is
  signal valid_pipe    : std_logic_vector(1 downto 0) := (others => '0');
  signal subtract_pipe : std_logic_vector(1 downto 0) := (others => '0');
  signal last_pipe     : std_logic_vector(1 downto 0) := (others => '0');
  signal product_pipe0 : signed(47 downto 0) := (others => '0');
  signal product_pipe1 : signed(47 downto 0) := (others => '0');
begin
  process(clk)
    variable product_v : signed(A_WIDTH + B_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        valid_pipe <= (others => '0');
        subtract_pipe <= (others => '0');
        last_pipe <= (others => '0');
        product_pipe0 <= (others => '0');
        product_pipe1 <= (others => '0');
      else
        product_v := a_i * b_i;
        product_pipe0 <= resize(product_v, 48);
        product_pipe1 <= product_pipe0;
        valid_pipe <= valid_pipe(0) & valid_i;
        subtract_pipe <= subtract_pipe(0) & subtract_i;
        last_pipe <= last_pipe(0) & last_i;
      end if;
    end if;
  end process;

  valid_o <= valid_pipe(1);
  subtract_o <= subtract_pipe(1);
  last_o <= last_pipe(1);
  p_o <= product_pipe1;
end architecture;
