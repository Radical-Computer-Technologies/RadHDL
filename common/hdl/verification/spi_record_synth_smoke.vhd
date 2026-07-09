library ieee;
use ieee.std_logic_1164.all;

library radhdl;
use radhdl.radhdl_spi_pkg.all;

-- Synthesis smoke top for RADHDL SPI record helpers.
-- Keeps scalar top-level ports for Vivado/IP Integrator compatibility while
-- checking that the record constructors and full-interface bundle flatten cleanly.
entity spi_record_synth_smoke is
  port (
    sclk_i : in  std_logic;
    csn_i  : in  std_logic;
    mosi_i : in  std_logic;
    miso_i : in  std_logic;
    sclk_o : out std_logic;
    csn_o  : out std_logic;
    mosi_o : out std_logic;
    miso_o : out std_logic
  );
end entity;

architecture rtl of spi_record_synth_smoke is
  signal master_o : spi_master_o_t := SPI_MASTER_O_IDLE;
  signal master_i : spi_master_i_t := SPI_MASTER_I_IDLE;
  signal intf     : spi_intf_t;
begin
  master_o <= spi_master_o(sclk_i, csn_i, mosi_i);
  master_i <= spi_master_i(miso_i);
  intf <= spi_intf(master_o, master_i);

  sclk_o <= intf.sclk;
  csn_o <= intf.cs_n;
  mosi_o <= intf.mosi;
  miso_o <= intf.miso;
end architecture;
