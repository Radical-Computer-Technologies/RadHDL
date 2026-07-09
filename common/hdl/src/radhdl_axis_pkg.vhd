library ieee;
use ieee.std_logic_1164.all;

-- Shared RADHDL AXI-stream record package.
-- Provides fixed-width AXIS records for common payload widths and endpoint-specific
-- records that keep port directions synthesizer-friendly.
-- Vivado synthesis guidance: keep these records fixed-width, use them for
-- internal wiring or carefully validated VHDL-2008 wrappers, and keep external
-- IP-packaged ports scalar until the target Vivado/IP Integrator flow has been
-- checked. The helper constructors are pure combinational field packers.
package radhdl_axis_pkg is
  type axis8_intf_t is record
    aclk    : std_logic;
    aresetn : std_logic;
    tvalid  : std_logic;
    tready  : std_logic;
    tdata   : std_logic_vector(7 downto 0);
    tlast   : std_logic;
  end record;

  type axis16_intf_t is record
    aclk    : std_logic;
    aresetn : std_logic;
    tvalid  : std_logic;
    tready  : std_logic;
    tdata   : std_logic_vector(15 downto 0);
    tlast   : std_logic;
  end record;

  type axis32_intf_t is record
    aclk    : std_logic;
    aresetn : std_logic;
    tvalid  : std_logic;
    tready  : std_logic;
    tdata   : std_logic_vector(31 downto 0);
    tlast   : std_logic;
  end record;

  type axis64_intf_t is record
    aclk    : std_logic;
    aresetn : std_logic;
    tvalid  : std_logic;
    tready  : std_logic;
    tdata   : std_logic_vector(63 downto 0);
    tlast   : std_logic;
  end record;

  type axis128_intf_t is record
    aclk    : std_logic;
    aresetn : std_logic;
    tvalid  : std_logic;
    tready  : std_logic;
    tdata   : std_logic_vector(127 downto 0);
    tlast   : std_logic;
  end record;

  type axis8_saxis_i_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(7 downto 0);
    tlast  : std_logic;
  end record;

  type axis16_saxis_i_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(15 downto 0);
    tlast  : std_logic;
  end record;

  type axis32_saxis_i_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(31 downto 0);
    tlast  : std_logic;
  end record;

  type axis64_saxis_i_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(63 downto 0);
    tlast  : std_logic;
  end record;

  type axis128_saxis_i_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(127 downto 0);
    tlast  : std_logic;
  end record;

  type axis_saxis_o_t is record
    tready : std_logic;
  end record;

  subtype axis8_saxis_o_t is axis_saxis_o_t;
  subtype axis16_saxis_o_t is axis_saxis_o_t;
  subtype axis32_saxis_o_t is axis_saxis_o_t;
  subtype axis64_saxis_o_t is axis_saxis_o_t;
  subtype axis128_saxis_o_t is axis_saxis_o_t;

  type axis8_maxis_o_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(7 downto 0);
    tlast  : std_logic;
  end record;

  type axis16_maxis_o_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(15 downto 0);
    tlast  : std_logic;
  end record;

  type axis32_maxis_o_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(31 downto 0);
    tlast  : std_logic;
  end record;

  type axis64_maxis_o_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(63 downto 0);
    tlast  : std_logic;
  end record;

  type axis128_maxis_o_t is record
    tvalid : std_logic;
    tdata  : std_logic_vector(127 downto 0);
    tlast  : std_logic;
  end record;

  type axis_maxis_i_t is record
    tready : std_logic;
  end record;

  subtype axis8_maxis_i_t is axis_maxis_i_t;
  subtype axis16_maxis_i_t is axis_maxis_i_t;
  subtype axis32_maxis_i_t is axis_maxis_i_t;
  subtype axis64_maxis_i_t is axis_maxis_i_t;
  subtype axis128_maxis_i_t is axis_maxis_i_t;

  constant AXIS8_SAXIS_I_NULL   : axis8_saxis_i_t   := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS16_SAXIS_I_NULL  : axis16_saxis_i_t  := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS32_SAXIS_I_NULL  : axis32_saxis_i_t  := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS64_SAXIS_I_NULL  : axis64_saxis_i_t  := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS128_SAXIS_I_NULL : axis128_saxis_i_t := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS_SAXIS_O_NULL    : axis_saxis_o_t    := (tready => '0');

  constant AXIS8_MAXIS_O_NULL   : axis8_maxis_o_t   := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS16_MAXIS_O_NULL  : axis16_maxis_o_t  := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS32_MAXIS_O_NULL  : axis32_maxis_o_t  := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS64_MAXIS_O_NULL  : axis64_maxis_o_t  := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS128_MAXIS_O_NULL : axis128_maxis_o_t := (tvalid => '0', tdata => (others => '0'), tlast => '0');
  constant AXIS_MAXIS_I_NULL    : axis_maxis_i_t    := (tready => '0');

  function axis8_saxis_i(tvalid : std_logic; tdata : std_logic_vector(7 downto 0); tlast : std_logic) return axis8_saxis_i_t;
  function axis16_saxis_i(tvalid : std_logic; tdata : std_logic_vector(15 downto 0); tlast : std_logic) return axis16_saxis_i_t;
  function axis32_saxis_i(tvalid : std_logic; tdata : std_logic_vector(31 downto 0); tlast : std_logic) return axis32_saxis_i_t;
  function axis64_saxis_i(tvalid : std_logic; tdata : std_logic_vector(63 downto 0); tlast : std_logic) return axis64_saxis_i_t;
  function axis128_saxis_i(tvalid : std_logic; tdata : std_logic_vector(127 downto 0); tlast : std_logic) return axis128_saxis_i_t;

  function axis_saxis_o(tready : std_logic) return axis_saxis_o_t;

  function axis8_maxis_o(tvalid : std_logic; tdata : std_logic_vector(7 downto 0); tlast : std_logic) return axis8_maxis_o_t;
  function axis16_maxis_o(tvalid : std_logic; tdata : std_logic_vector(15 downto 0); tlast : std_logic) return axis16_maxis_o_t;
  function axis32_maxis_o(tvalid : std_logic; tdata : std_logic_vector(31 downto 0); tlast : std_logic) return axis32_maxis_o_t;
  function axis64_maxis_o(tvalid : std_logic; tdata : std_logic_vector(63 downto 0); tlast : std_logic) return axis64_maxis_o_t;
  function axis128_maxis_o(tvalid : std_logic; tdata : std_logic_vector(127 downto 0); tlast : std_logic) return axis128_maxis_o_t;

  function axis_maxis_i(tready : std_logic) return axis_maxis_i_t;

  function axis8_intf(aclk : std_logic; aresetn : std_logic; s : axis8_saxis_i_t; o : axis8_saxis_o_t) return axis8_intf_t;
  function axis16_intf(aclk : std_logic; aresetn : std_logic; s : axis16_saxis_i_t; o : axis16_saxis_o_t) return axis16_intf_t;
  function axis32_intf(aclk : std_logic; aresetn : std_logic; s : axis32_saxis_i_t; o : axis32_saxis_o_t) return axis32_intf_t;
  function axis64_intf(aclk : std_logic; aresetn : std_logic; s : axis64_saxis_i_t; o : axis64_saxis_o_t) return axis64_intf_t;
  function axis128_intf(aclk : std_logic; aresetn : std_logic; s : axis128_saxis_i_t; o : axis128_saxis_o_t) return axis128_intf_t;
end package;

package body radhdl_axis_pkg is
  function axis8_saxis_i(tvalid : std_logic; tdata : std_logic_vector(7 downto 0); tlast : std_logic) return axis8_saxis_i_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis16_saxis_i(tvalid : std_logic; tdata : std_logic_vector(15 downto 0); tlast : std_logic) return axis16_saxis_i_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis32_saxis_i(tvalid : std_logic; tdata : std_logic_vector(31 downto 0); tlast : std_logic) return axis32_saxis_i_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis64_saxis_i(tvalid : std_logic; tdata : std_logic_vector(63 downto 0); tlast : std_logic) return axis64_saxis_i_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis128_saxis_i(tvalid : std_logic; tdata : std_logic_vector(127 downto 0); tlast : std_logic) return axis128_saxis_i_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis_saxis_o(tready : std_logic) return axis_saxis_o_t is
  begin
    return (tready => tready);
  end function;

  function axis8_maxis_o(tvalid : std_logic; tdata : std_logic_vector(7 downto 0); tlast : std_logic) return axis8_maxis_o_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis16_maxis_o(tvalid : std_logic; tdata : std_logic_vector(15 downto 0); tlast : std_logic) return axis16_maxis_o_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis32_maxis_o(tvalid : std_logic; tdata : std_logic_vector(31 downto 0); tlast : std_logic) return axis32_maxis_o_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis64_maxis_o(tvalid : std_logic; tdata : std_logic_vector(63 downto 0); tlast : std_logic) return axis64_maxis_o_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis128_maxis_o(tvalid : std_logic; tdata : std_logic_vector(127 downto 0); tlast : std_logic) return axis128_maxis_o_t is
  begin
    return (tvalid => tvalid, tdata => tdata, tlast => tlast);
  end function;

  function axis_maxis_i(tready : std_logic) return axis_maxis_i_t is
  begin
    return (tready => tready);
  end function;

  function axis8_intf(aclk : std_logic; aresetn : std_logic; s : axis8_saxis_i_t; o : axis8_saxis_o_t) return axis8_intf_t is
  begin
    return (aclk => aclk, aresetn => aresetn, tvalid => s.tvalid, tready => o.tready, tdata => s.tdata, tlast => s.tlast);
  end function;

  function axis16_intf(aclk : std_logic; aresetn : std_logic; s : axis16_saxis_i_t; o : axis16_saxis_o_t) return axis16_intf_t is
  begin
    return (aclk => aclk, aresetn => aresetn, tvalid => s.tvalid, tready => o.tready, tdata => s.tdata, tlast => s.tlast);
  end function;

  function axis32_intf(aclk : std_logic; aresetn : std_logic; s : axis32_saxis_i_t; o : axis32_saxis_o_t) return axis32_intf_t is
  begin
    return (aclk => aclk, aresetn => aresetn, tvalid => s.tvalid, tready => o.tready, tdata => s.tdata, tlast => s.tlast);
  end function;

  function axis64_intf(aclk : std_logic; aresetn : std_logic; s : axis64_saxis_i_t; o : axis64_saxis_o_t) return axis64_intf_t is
  begin
    return (aclk => aclk, aresetn => aresetn, tvalid => s.tvalid, tready => o.tready, tdata => s.tdata, tlast => s.tlast);
  end function;

  function axis128_intf(aclk : std_logic; aresetn : std_logic; s : axis128_saxis_i_t; o : axis128_saxis_o_t) return axis128_intf_t is
  begin
    return (aclk => aclk, aresetn => aresetn, tvalid => s.tvalid, tready => o.tready, tdata => s.tdata, tlast => s.tlast);
  end function;
end package body;
