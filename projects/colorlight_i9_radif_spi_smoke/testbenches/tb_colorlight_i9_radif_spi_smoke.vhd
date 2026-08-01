library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_colorlight_i9_radif_spi_smoke is
end entity;

architecture sim of tb_colorlight_i9_radif_spi_smoke is
  signal clk_25m   : std_logic := '0';
  signal spi_sclk  : std_logic := '0';
  signal spi_cs_n  : std_logic := '1';
  signal spi_mosi  : std_logic := '0';
  signal spi_miso  : std_logic;
  signal led       : std_logic;
begin
  clk_25m <= not clk_25m after 20 ns;

  dut : entity work.colorlight_i9_radif_spi_smoke_top
    port map (
      clk_25m_i => clk_25m,
      spi_sclk_i => spi_sclk,
      spi_cs_n_i => spi_cs_n,
      spi_mosi_i => spi_mosi,
      spi_miso_o => spi_miso,
      led_o => led
    );

  process
    procedure spi_byte(tx : std_logic_vector(7 downto 0); variable rx : out std_logic_vector(7 downto 0)) is
      variable sample : std_logic_vector(7 downto 0) := (others => '0');
    begin
      for bit_index in 7 downto 0 loop
        spi_mosi <= tx(bit_index);
        wait for 500 ns;
        spi_sclk <= '1';
        wait for 500 ns;
        sample(bit_index) := spi_miso;
        spi_sclk <= '0';
        wait for 500 ns;
      end loop;
      rx := sample;
    end procedure;

    variable sink : std_logic_vector(7 downto 0) := (others => '0');
    variable rx_byte : std_logic_vector(7 downto 0) := (others => '0');
  begin
    wait for 1 us;
    assert led = '0' report "LED should reset low" severity failure;

    spi_cs_n <= '0';
    wait for 2 us;
    spi_byte(x"A5", rx_byte);
    spi_byte(x"01", rx_byte);
    spi_byte(x"00", rx_byte);
    spi_byte(x"00", rx_byte);
    spi_byte(x"00", rx_byte);
    spi_byte(x"00", rx_byte);
    spi_byte(x"00", rx_byte);
    spi_byte(x"01", rx_byte);
    wait for 2 us;
    spi_cs_n <= '1';
    wait for 10 us;
    assert led = '1' report "RADIF SPI write did not update control register LED bit" severity failure;

    spi_cs_n <= '0';
    wait for 2 us;
    spi_byte(x"A5", rx_byte);
    spi_byte(x"01", rx_byte);
    spi_byte(x"00", rx_byte);
    spi_byte(x"04", rx_byte);
    spi_byte(x"DE", rx_byte);
    spi_byte(x"AD", rx_byte);
    spi_byte(x"BE", rx_byte);
    spi_byte(x"EF", rx_byte);
    wait for 2 us;
    spi_cs_n <= '1';
    wait for 10 us;

    sink := rx_byte;
    report "PASS tb_colorlight_i9_radif_spi_smoke";
    finish;
  end process;
end architecture;
