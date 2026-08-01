library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity colorlight_i9_primitive_smoke_top is
  port (
    clk_25m_i   : in  std_logic;
    spi_sclk_i  : in  std_logic;
    spi_cs_n_i  : in  std_logic;
    spi_mosi_i  : in  std_logic;
    spi_miso_o  : out std_logic;
    led_o       : out std_logic
  );
end entity;

architecture rtl of colorlight_i9_primitive_smoke_top is
  signal rst_shift   : std_logic_vector(7 downto 0) := (others => '0');
  signal rst         : std_logic := '1';
  signal counter     : unsigned(17 downto 0) := (others => '0');
  signal a_s         : signed(17 downto 0);
  signal b_s         : signed(17 downto 0);
  signal mul_valid   : std_logic;
  signal mul_last    : std_logic;
  signal mul_p       : signed(47 downto 0);
  signal unused_sub  : std_logic;
  signal ram_dout_a  : std_logic_vector(17 downto 0);
  signal ram_dout_b  : std_logic_vector(17 downto 0);
  signal fifo_dout   : std_logic_vector(17 downto 0);
  signal fifo_empty  : std_logic;
  signal fifo_full   : std_logic;
  signal fifo_valid  : std_logic;
begin
  rst <= not rst_shift(rst_shift'high);
  spi_miso_o <= spi_sclk_i xor spi_cs_n_i xor spi_mosi_i xor mul_p(0);
  led_o <= mul_valid xor mul_last xor mul_p(12) xor ram_dout_a(0) xor ram_dout_b(1) xor fifo_dout(0) xor fifo_valid;

  a_s <= signed(counter);
  b_s <= signed(not counter);

  process(clk_25m_i)
  begin
    if rising_edge(clk_25m_i) then
      rst_shift <= rst_shift(rst_shift'high - 1 downto 0) & '1';
      if rst = '1' then
        counter <= (others => '0');
      else
        counter <= counter + 1;
      end if;
    end if;
  end process;

  u_mul : entity work.raddsp_mul
    generic map (
      VENDOR => "lattice",
      DEVICE_FAMILY => "ecp5",
      A_WIDTH => 18,
      B_WIDTH => 18
    )
    port map (
      clk => clk_25m_i,
      rst => rst,
      valid_i => '1',
      subtract_i => '0',
      last_i => counter(0),
      a_i => a_s,
      b_i => b_s,
      valid_o => mul_valid,
      subtract_o => unused_sub,
      last_o => mul_last,
      p_o => mul_p
    );

  u_ram : entity work.radhdl_ram
    generic map (
      VENDOR => "lattice",
      DEVICE_FAMILY => "ecp5",
      MODE => "tdp",
      MEMORY_KIND => "bram",
      DATA_WIDTH => 18,
      ADDR_WIDTH => 10,
      DEPTH => 1024,
      CLOCKING_MODE => "common_clock"
    )
    port map (
      clka => clk_25m_i,
      rsta => rst,
      a_addr => std_logic_vector(counter(9 downto 0)),
      a_din => std_logic_vector(counter),
      a_dout => ram_dout_a,
      a_we => '1',
      clkb => clk_25m_i,
      rstb => rst,
      b_addr => std_logic_vector(counter(9 downto 0) - 1),
      b_din => std_logic_vector(not counter),
      b_dout => ram_dout_b,
      b_we => '0'
    );

  u_fifo : entity work.radhdl_fifo
    generic map (
      VENDOR => "lattice",
      DEVICE_FAMILY => "ecp5",
      FIFO_MODE => "sync",
      FIFO_WRITE_DEPTH => 16,
      WRITE_DATA_WIDTH => 18,
      READ_DATA_WIDTH => 18,
      READ_MODE => "std",
      FIFO_READ_LATENCY => 1,
      WR_DATA_COUNT_WIDTH => 5,
      RD_DATA_COUNT_WIDTH => 5
    )
    port map (
      almost_empty => open,
      almost_full => open,
      data_valid => fifo_valid,
      dbiterr => open,
      dout => fifo_dout,
      empty => fifo_empty,
      full => fifo_full,
      overflow => open,
      prog_empty => open,
      prog_full => open,
      rd_data_count => open,
      rd_rst_busy => open,
      sbiterr => open,
      underflow => open,
      wr_ack => open,
      wr_data_count => open,
      wr_rst_busy => open,
      din => std_logic_vector(counter),
      injectdbiterr => '0',
      injectsbiterr => '0',
      rd_en => counter(1) and not fifo_empty,
      rst => rst,
      sleep => '0',
      wr_clk => clk_25m_i,
      wr_en => counter(0) and not fifo_full
    );

end architecture;
