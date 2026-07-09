library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library radif;
use radif.radhdl_spi_pkg.all;

-- Exercises the register-controlled 4-wire SPI master with a looped-back MISO/MOSI path.
-- The waveform shows software register writes, chip-select assertion, generated SCLK pulses, MOSI output shifting, MISO input sampling, and transaction completion status.
entity tb_radif_reg_to_spi_master is
end entity;

architecture sim of tb_radif_reg_to_spi_master is
  signal clk          : std_logic := '0';
  signal rstn         : std_logic := '0';
  signal reg_wr_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_rd_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_wr_en    : std_logic := '0';
  signal reg_rd_en    : std_logic := '0';
  signal reg_data_in  : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_data_out : std_logic_vector(31 downto 0);
  signal reg_wr_rdy   : std_logic;
  signal reg_rd_rdy   : std_logic;
  signal reg_wr_valid : std_logic;
  signal reg_rd_valid : std_logic;
  signal reg_error    : std_logic;
  signal spi_m_o      : spi_master_o_t := SPI_MASTER_O_IDLE;
  signal spi_m_i      : spi_master_i_t := SPI_MASTER_I_IDLE;
begin
  clk <= not clk after 5 ns;
  spi_m_i <= spi_master_i(spi_m_o.mosi);

  dut : entity radif.radif_reg_to_spi_master
    generic map (
      DEFAULT_SCLK_DIV => 1,
      DEFAULT_BIT_COUNT => 8
    )
    port map (
      clk => clk,
      rstn => rstn,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_data_in,
      reg_data_out => reg_data_out,
      reg_wr_rdy => reg_wr_rdy,
      reg_rd_rdy => reg_rd_rdy,
      reg_wr_valid => reg_wr_valid,
      reg_rd_valid => reg_rd_valid,
      reg_error => reg_error,
      spi_sclk_o => spi_m_o.sclk,
      spi_cs_n_o => spi_m_o.cs_n,
      spi_mosi_o => spi_m_o.mosi,
      spi_miso_i => spi_m_i.miso
    );

  process
    procedure reg_write(addr : std_logic_vector(15 downto 0); data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_wr_addr <= addr;
      reg_data_in <= data;
      reg_wr_en <= '1';
      wait until rising_edge(clk);
      reg_wr_en <= '0';
    end procedure;

    procedure reg_read(addr : std_logic_vector(15 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_rd_addr <= addr;
      reg_rd_en <= '1';
      wait until rising_edge(clk);
      reg_rd_en <= '0';
      wait until rising_edge(clk);
    end procedure;
  begin
    wait for 40 ns;
    rstn <= '1';

    reg_write(x"0008", x"00000001");
    reg_write(x"000C", x"00000800");
    reg_write(x"0010", x"A5000000");
    reg_write(x"0000", x"00000001");

    for i in 0 to 80 loop
      wait until rising_edge(clk);
      exit when spi_m_o.cs_n = '0';
    end loop;
    assert spi_m_o.cs_n = '0' report "SPI chip select did not assert" severity failure;

    for i in 0 to 120 loop
      wait until rising_edge(clk);
      exit when spi_m_o.cs_n = '1';
    end loop;

    reg_read(x"0004");
    assert reg_data_out(1) = '1' report "SPI transaction did not complete" severity failure;
    reg_read(x"0014");
    assert reg_data_out(7 downto 0) = x"A5" report "SPI MISO data was not captured into RX_DATA" severity failure;
    assert reg_error = '0' report "SPI register error asserted" severity failure;
    report "PASS tb_radif_reg_to_spi_master";
    finish;
  end process;
end architecture;
