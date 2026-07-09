library ieee;
use ieee.std_logic_1164.all;

-- Shared RADHDL SPI record package.
-- Splits the 4-wire SPI bus into master/slave endpoint records so entity ports can
-- use a single direction per record while preserving standard SCLK/CS/MOSI/MISO names.
-- Vivado synthesis guidance: these records are fixed-width scalar bundles and
-- the helper functions are pure combinational field packers. Keep IP Integrator
-- boundary ports scalar until a wrapper has been checked in the exact target flow.
package radhdl_spi_pkg is
  type spi_intf_t is record
    sclk : std_logic;
    cs_n : std_logic;
    mosi : std_logic;
    miso : std_logic;
  end record;

  type spi_master_o_t is record
    sclk : std_logic;
    cs_n : std_logic;
    mosi : std_logic;
  end record;

  type spi_master_i_t is record
    miso : std_logic;
  end record;

  type spi_slave_i_t is record
    sclk : std_logic;
    cs_n : std_logic;
    mosi : std_logic;
  end record;

  type spi_slave_o_t is record
    miso : std_logic;
  end record;

  type spi_slave_oe_t is record
    miso_oen : std_logic;
  end record;

  constant SPI_MASTER_O_IDLE : spi_master_o_t := (sclk => '0', cs_n => '1', mosi => '0');
  constant SPI_MASTER_I_IDLE : spi_master_i_t := (miso => '0');
  constant SPI_SLAVE_I_IDLE  : spi_slave_i_t  := (sclk => '0', cs_n => '1', mosi => '0');
  constant SPI_SLAVE_O_IDLE  : spi_slave_o_t  := (miso => '0');
  constant SPI_SLAVE_OE_OFF  : spi_slave_oe_t := (miso_oen => '1');

  function spi_master_o(sclk : std_logic; cs_n : std_logic; mosi : std_logic) return spi_master_o_t;
  function spi_master_i(miso : std_logic) return spi_master_i_t;
  function spi_slave_i(sclk : std_logic; cs_n : std_logic; mosi : std_logic) return spi_slave_i_t;
  function spi_slave_o(miso : std_logic) return spi_slave_o_t;
  function spi_slave_oe(miso_oen : std_logic) return spi_slave_oe_t;

  function spi_intf(master_o : spi_master_o_t; master_i : spi_master_i_t) return spi_intf_t;
  function spi_master_o(intf : spi_intf_t) return spi_master_o_t;
  function spi_master_i(intf : spi_intf_t) return spi_master_i_t;
  function spi_slave_i(intf : spi_intf_t) return spi_slave_i_t;
  function spi_slave_o(intf : spi_intf_t) return spi_slave_o_t;
end package;

package body radhdl_spi_pkg is
  function spi_master_o(sclk : std_logic; cs_n : std_logic; mosi : std_logic) return spi_master_o_t is
  begin
    return (sclk => sclk, cs_n => cs_n, mosi => mosi);
  end function;

  function spi_master_i(miso : std_logic) return spi_master_i_t is
  begin
    return (miso => miso);
  end function;

  function spi_slave_i(sclk : std_logic; cs_n : std_logic; mosi : std_logic) return spi_slave_i_t is
  begin
    return (sclk => sclk, cs_n => cs_n, mosi => mosi);
  end function;

  function spi_slave_o(miso : std_logic) return spi_slave_o_t is
  begin
    return (miso => miso);
  end function;

  function spi_slave_oe(miso_oen : std_logic) return spi_slave_oe_t is
  begin
    return (miso_oen => miso_oen);
  end function;

  function spi_intf(master_o : spi_master_o_t; master_i : spi_master_i_t) return spi_intf_t is
  begin
    return (sclk => master_o.sclk, cs_n => master_o.cs_n, mosi => master_o.mosi, miso => master_i.miso);
  end function;

  function spi_master_o(intf : spi_intf_t) return spi_master_o_t is
  begin
    return (sclk => intf.sclk, cs_n => intf.cs_n, mosi => intf.mosi);
  end function;

  function spi_master_i(intf : spi_intf_t) return spi_master_i_t is
  begin
    return (miso => intf.miso);
  end function;

  function spi_slave_i(intf : spi_intf_t) return spi_slave_i_t is
  begin
    return (sclk => intf.sclk, cs_n => intf.cs_n, mosi => intf.mosi);
  end function;

  function spi_slave_o(intf : spi_intf_t) return spi_slave_o_t is
  begin
    return (miso => intf.miso);
  end function;
end package body;
