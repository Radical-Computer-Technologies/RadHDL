library ieee;
use ieee.std_logic_1164.all;

-- Shared RADHDL AXI record package.
-- AXI interfaces are modeled as channel records first, then composed into full
-- interface records. This keeps VHDL readable as protocol-shaped objects:
-- axi.aw, axi.w, axi.b, axi.ar, axi.r.
--
-- Vivado synthesis guidance: keep public variants fixed-width and use scalar
-- top-level ports for packaged IP wrappers until the exact integration flow has
-- been checked. These records and constructors are pure combinational helpers.
package radhdl_axi_pkg is
  subtype axi_resp_t  is std_logic_vector(1 downto 0);
  subtype axi_prot_t  is std_logic_vector(2 downto 0);
  subtype axi_len_t   is std_logic_vector(7 downto 0);
  subtype axi_size_t  is std_logic_vector(2 downto 0);
  subtype axi_burst_t is std_logic_vector(1 downto 0);

  constant AXI_RESP_OKAY   : axi_resp_t := "00";
  constant AXI_RESP_EXOKAY : axi_resp_t := "01";
  constant AXI_RESP_SLVERR : axi_resp_t := "10";
  constant AXI_RESP_DECERR : axi_resp_t := "11";

  constant AXI_BURST_FIXED : axi_burst_t := "00";
  constant AXI_BURST_INCR  : axi_burst_t := "01";
  constant AXI_BURST_WRAP  : axi_burst_t := "10";

  type axilite_aw16_t is record
    addr  : std_logic_vector(15 downto 0);
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_aw32_t is record
    addr  : std_logic_vector(31 downto 0);
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_aw64_t is record
    addr  : std_logic_vector(63 downto 0);
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_ar16_t is record
    addr  : std_logic_vector(15 downto 0);
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_ar32_t is record
    addr  : std_logic_vector(31 downto 0);
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_ar64_t is record
    addr  : std_logic_vector(63 downto 0);
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_aw32_t is record
    addr  : std_logic_vector(31 downto 0);
    len   : axi_len_t;
    size  : axi_size_t;
    burst : axi_burst_t;
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_aw64_t is record
    addr  : std_logic_vector(63 downto 0);
    len   : axi_len_t;
    size  : axi_size_t;
    burst : axi_burst_t;
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_ar32_t is record
    addr  : std_logic_vector(31 downto 0);
    len   : axi_len_t;
    size  : axi_size_t;
    burst : axi_burst_t;
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_ar64_t is record
    addr  : std_logic_vector(63 downto 0);
    len   : axi_len_t;
    size  : axi_size_t;
    burst : axi_burst_t;
    prot  : axi_prot_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_w32_t is record
    data  : std_logic_vector(31 downto 0);
    strb  : std_logic_vector(3 downto 0);
    last  : std_logic;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_w64_t is record
    data  : std_logic_vector(63 downto 0);
    strb  : std_logic_vector(7 downto 0);
    last  : std_logic;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_w128_t is record
    data  : std_logic_vector(127 downto 0);
    strb  : std_logic_vector(15 downto 0);
    last  : std_logic;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_r32_t is record
    data  : std_logic_vector(31 downto 0);
    resp  : axi_resp_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_r64_t is record
    data  : std_logic_vector(63 downto 0);
    resp  : axi_resp_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axilite_r128_t is record
    data  : std_logic_vector(127 downto 0);
    resp  : axi_resp_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_r32_t is record
    data  : std_logic_vector(31 downto 0);
    resp  : axi_resp_t;
    last  : std_logic;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_r64_t is record
    data  : std_logic_vector(63 downto 0);
    resp  : axi_resp_t;
    last  : std_logic;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_r128_t is record
    data  : std_logic_vector(127 downto 0);
    resp  : axi_resp_t;
    last  : std_logic;
    valid : std_logic;
    ready : std_logic;
  end record;

  type axi_b_t is record
    resp  : axi_resp_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  constant AXILITE_AW16_NULL : axilite_aw16_t := (addr => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXILITE_AW32_NULL : axilite_aw32_t := (addr => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXILITE_AW64_NULL : axilite_aw64_t := (addr => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXILITE_AR16_NULL : axilite_ar16_t := (addr => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXILITE_AR32_NULL : axilite_ar32_t := (addr => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXILITE_AR64_NULL : axilite_ar64_t := (addr => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXI_AW32_NULL     : axi_aw32_t := (addr => (others => '0'), len => (others => '0'), size => (others => '0'), burst => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXI_AW64_NULL     : axi_aw64_t := (addr => (others => '0'), len => (others => '0'), size => (others => '0'), burst => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXI_AR32_NULL     : axi_ar32_t := (addr => (others => '0'), len => (others => '0'), size => (others => '0'), burst => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXI_AR64_NULL     : axi_ar64_t := (addr => (others => '0'), len => (others => '0'), size => (others => '0'), burst => (others => '0'), prot => (others => '0'), valid => '0', ready => '0');
  constant AXI_W32_NULL      : axi_w32_t := (data => (others => '0'), strb => (others => '0'), last => '0', valid => '0', ready => '0');
  constant AXI_W64_NULL      : axi_w64_t := (data => (others => '0'), strb => (others => '0'), last => '0', valid => '0', ready => '0');
  constant AXI_W128_NULL     : axi_w128_t := (data => (others => '0'), strb => (others => '0'), last => '0', valid => '0', ready => '0');
  constant AXILITE_R32_NULL  : axilite_r32_t := (data => (others => '0'), resp => AXI_RESP_OKAY, valid => '0', ready => '0');
  constant AXILITE_R64_NULL  : axilite_r64_t := (data => (others => '0'), resp => AXI_RESP_OKAY, valid => '0', ready => '0');
  constant AXILITE_R128_NULL : axilite_r128_t := (data => (others => '0'), resp => AXI_RESP_OKAY, valid => '0', ready => '0');
  constant AXI_R32_NULL      : axi_r32_t := (data => (others => '0'), resp => AXI_RESP_OKAY, last => '0', valid => '0', ready => '0');
  constant AXI_R64_NULL      : axi_r64_t := (data => (others => '0'), resp => AXI_RESP_OKAY, last => '0', valid => '0', ready => '0');
  constant AXI_R128_NULL     : axi_r128_t := (data => (others => '0'), resp => AXI_RESP_OKAY, last => '0', valid => '0', ready => '0');
  constant AXI_B_NULL        : axi_b_t := (resp => AXI_RESP_OKAY, valid => '0', ready => '0');

  type axilite32_a16_intf_t is record
    aw : axilite_aw16_t;
    w  : axi_w32_t;
    b  : axi_b_t;
    ar : axilite_ar16_t;
    r  : axilite_r32_t;
  end record;

  type axilite32_a32_intf_t is record
    aw : axilite_aw32_t;
    w  : axi_w32_t;
    b  : axi_b_t;
    ar : axilite_ar32_t;
    r  : axilite_r32_t;
  end record;

  type axilite64_a32_intf_t is record
    aw : axilite_aw32_t;
    w  : axi_w64_t;
    b  : axi_b_t;
    ar : axilite_ar32_t;
    r  : axilite_r64_t;
  end record;

  type axilite64_a64_intf_t is record
    aw : axilite_aw64_t;
    w  : axi_w64_t;
    b  : axi_b_t;
    ar : axilite_ar64_t;
    r  : axilite_r64_t;
  end record;

  type axilite128_a64_intf_t is record
    aw : axilite_aw64_t;
    w  : axi_w128_t;
    b  : axi_b_t;
    ar : axilite_ar64_t;
    r  : axilite_r128_t;
  end record;

  type axi4_32_a32_intf_t is record
    aw : axi_aw32_t;
    w  : axi_w32_t;
    b  : axi_b_t;
    ar : axi_ar32_t;
    r  : axi_r32_t;
  end record;

  type axi4_64_a32_intf_t is record
    aw : axi_aw32_t;
    w  : axi_w64_t;
    b  : axi_b_t;
    ar : axi_ar32_t;
    r  : axi_r64_t;
  end record;

  type axi4_64_a64_intf_t is record
    aw : axi_aw64_t;
    w  : axi_w64_t;
    b  : axi_b_t;
    ar : axi_ar64_t;
    r  : axi_r64_t;
  end record;

  type axi4_128_a64_intf_t is record
    aw : axi_aw64_t;
    w  : axi_w128_t;
    b  : axi_b_t;
    ar : axi_ar64_t;
    r  : axi_r128_t;
  end record;

  subtype axilite32_a16_slave_i_t is axilite32_a16_intf_t;
  subtype axilite32_a16_slave_o_t is axilite32_a16_intf_t;
  subtype axilite32_a32_slave_i_t is axilite32_a32_intf_t;
  subtype axilite32_a32_slave_o_t is axilite32_a32_intf_t;
  subtype axilite64_a32_slave_i_t is axilite64_a32_intf_t;
  subtype axilite64_a32_slave_o_t is axilite64_a32_intf_t;
  subtype axilite64_a64_slave_i_t is axilite64_a64_intf_t;
  subtype axilite64_a64_slave_o_t is axilite64_a64_intf_t;
  subtype axilite128_a64_slave_i_t is axilite128_a64_intf_t;
  subtype axilite128_a64_slave_o_t is axilite128_a64_intf_t;
  subtype axi4_32_a32_master_o_t is axi4_32_a32_intf_t;
  subtype axi4_32_a32_master_i_t is axi4_32_a32_intf_t;
  subtype axi4_64_a32_master_o_t is axi4_64_a32_intf_t;
  subtype axi4_64_a32_master_i_t is axi4_64_a32_intf_t;
  subtype axi4_64_a64_master_o_t is axi4_64_a64_intf_t;
  subtype axi4_64_a64_master_i_t is axi4_64_a64_intf_t;
  subtype axi4_128_a64_master_o_t is axi4_128_a64_intf_t;
  subtype axi4_128_a64_master_i_t is axi4_128_a64_intf_t;

  constant AXILITE32_A16_INTF_NULL  : axilite32_a16_intf_t  := (aw => AXILITE_AW16_NULL, w => AXI_W32_NULL, b => AXI_B_NULL, ar => AXILITE_AR16_NULL, r => AXILITE_R32_NULL);
  constant AXILITE32_A32_INTF_NULL  : axilite32_a32_intf_t  := (aw => AXILITE_AW32_NULL, w => AXI_W32_NULL, b => AXI_B_NULL, ar => AXILITE_AR32_NULL, r => AXILITE_R32_NULL);
  constant AXILITE64_A32_INTF_NULL  : axilite64_a32_intf_t  := (aw => AXILITE_AW32_NULL, w => AXI_W64_NULL, b => AXI_B_NULL, ar => AXILITE_AR32_NULL, r => AXILITE_R64_NULL);
  constant AXILITE64_A64_INTF_NULL  : axilite64_a64_intf_t  := (aw => AXILITE_AW64_NULL, w => AXI_W64_NULL, b => AXI_B_NULL, ar => AXILITE_AR64_NULL, r => AXILITE_R64_NULL);
  constant AXILITE128_A64_INTF_NULL : axilite128_a64_intf_t := (aw => AXILITE_AW64_NULL, w => AXI_W128_NULL, b => AXI_B_NULL, ar => AXILITE_AR64_NULL, r => AXILITE_R128_NULL);
  constant AXI4_32_A32_INTF_NULL    : axi4_32_a32_intf_t    := (aw => AXI_AW32_NULL, w => AXI_W32_NULL, b => AXI_B_NULL, ar => AXI_AR32_NULL, r => AXI_R32_NULL);
  constant AXI4_64_A32_INTF_NULL    : axi4_64_a32_intf_t    := (aw => AXI_AW32_NULL, w => AXI_W64_NULL, b => AXI_B_NULL, ar => AXI_AR32_NULL, r => AXI_R64_NULL);
  constant AXI4_64_A64_INTF_NULL    : axi4_64_a64_intf_t    := (aw => AXI_AW64_NULL, w => AXI_W64_NULL, b => AXI_B_NULL, ar => AXI_AR64_NULL, r => AXI_R64_NULL);
  constant AXI4_128_A64_INTF_NULL   : axi4_128_a64_intf_t   := (aw => AXI_AW64_NULL, w => AXI_W128_NULL, b => AXI_B_NULL, ar => AXI_AR64_NULL, r => AXI_R128_NULL);

  constant AXILITE32_A16_SLAVE_I_NULL  : axilite32_a16_slave_i_t  := AXILITE32_A16_INTF_NULL;
  constant AXILITE32_A16_SLAVE_O_NULL  : axilite32_a16_slave_o_t  := AXILITE32_A16_INTF_NULL;
  constant AXILITE32_A32_SLAVE_I_NULL  : axilite32_a32_slave_i_t  := AXILITE32_A32_INTF_NULL;
  constant AXILITE32_A32_SLAVE_O_NULL  : axilite32_a32_slave_o_t  := AXILITE32_A32_INTF_NULL;
  constant AXILITE64_A32_SLAVE_I_NULL  : axilite64_a32_slave_i_t  := AXILITE64_A32_INTF_NULL;
  constant AXILITE64_A32_SLAVE_O_NULL  : axilite64_a32_slave_o_t  := AXILITE64_A32_INTF_NULL;
  constant AXILITE64_A64_SLAVE_I_NULL  : axilite64_a64_slave_i_t  := AXILITE64_A64_INTF_NULL;
  constant AXILITE64_A64_SLAVE_O_NULL  : axilite64_a64_slave_o_t  := AXILITE64_A64_INTF_NULL;
  constant AXILITE128_A64_SLAVE_I_NULL : axilite128_a64_slave_i_t := AXILITE128_A64_INTF_NULL;
  constant AXILITE128_A64_SLAVE_O_NULL : axilite128_a64_slave_o_t := AXILITE128_A64_INTF_NULL;
  constant AXI4_32_A32_MASTER_O_NULL   : axi4_32_a32_master_o_t   := AXI4_32_A32_INTF_NULL;
  constant AXI4_32_A32_MASTER_I_NULL   : axi4_32_a32_master_i_t   := AXI4_32_A32_INTF_NULL;
  constant AXI4_64_A32_MASTER_O_NULL   : axi4_64_a32_master_o_t   := AXI4_64_A32_INTF_NULL;
  constant AXI4_64_A32_MASTER_I_NULL   : axi4_64_a32_master_i_t   := AXI4_64_A32_INTF_NULL;
  constant AXI4_64_A64_MASTER_O_NULL   : axi4_64_a64_master_o_t   := AXI4_64_A64_INTF_NULL;
  constant AXI4_64_A64_MASTER_I_NULL   : axi4_64_a64_master_i_t   := AXI4_64_A64_INTF_NULL;
  constant AXI4_128_A64_MASTER_O_NULL  : axi4_128_a64_master_o_t  := AXI4_128_A64_INTF_NULL;
  constant AXI4_128_A64_MASTER_I_NULL  : axi4_128_a64_master_i_t  := AXI4_128_A64_INTF_NULL;

  function axi_size_from_bytes(byte_count : positive) return axi_size_t;
  function axilite32_a32_intf(
    awaddr : std_logic_vector(31 downto 0); awvalid : std_logic; awready : std_logic;
    wdata : std_logic_vector(31 downto 0); wstrb : std_logic_vector(3 downto 0); wvalid : std_logic; wready : std_logic;
    bresp : axi_resp_t; bvalid : std_logic; bready : std_logic;
    araddr : std_logic_vector(31 downto 0); arvalid : std_logic; arready : std_logic;
    rdata : std_logic_vector(31 downto 0); rresp : axi_resp_t; rvalid : std_logic; rready : std_logic
  ) return axilite32_a32_intf_t;
  function axi4_32_a32_intf(
    awaddr : std_logic_vector(31 downto 0); awvalid : std_logic; awready : std_logic;
    wdata : std_logic_vector(31 downto 0); wstrb : std_logic_vector(3 downto 0); wlast : std_logic; wvalid : std_logic; wready : std_logic;
    bresp : axi_resp_t; bvalid : std_logic; bready : std_logic;
    araddr : std_logic_vector(31 downto 0); arvalid : std_logic; arready : std_logic;
    rdata : std_logic_vector(31 downto 0); rresp : axi_resp_t; rlast : std_logic; rvalid : std_logic; rready : std_logic
  ) return axi4_32_a32_intf_t;
end package;

package body radhdl_axi_pkg is
  function axi_size_from_bytes(byte_count : positive) return axi_size_t is
  begin
    case byte_count is
      when 1 => return "000";
      when 2 => return "001";
      when 4 => return "010";
      when 8 => return "011";
      when 16 => return "100";
      when 32 => return "101";
      when 64 => return "110";
      when 128 => return "111";
      when others => return "010";
    end case;
  end function;

  function axilite32_a32_intf(
    awaddr : std_logic_vector(31 downto 0); awvalid : std_logic; awready : std_logic;
    wdata : std_logic_vector(31 downto 0); wstrb : std_logic_vector(3 downto 0); wvalid : std_logic; wready : std_logic;
    bresp : axi_resp_t; bvalid : std_logic; bready : std_logic;
    araddr : std_logic_vector(31 downto 0); arvalid : std_logic; arready : std_logic;
    rdata : std_logic_vector(31 downto 0); rresp : axi_resp_t; rvalid : std_logic; rready : std_logic
  ) return axilite32_a32_intf_t is
  begin
    return (
      aw => (addr => awaddr, prot => (others => '0'), valid => awvalid, ready => awready),
      w => (data => wdata, strb => wstrb, last => '1', valid => wvalid, ready => wready),
      b => (resp => bresp, valid => bvalid, ready => bready),
      ar => (addr => araddr, prot => (others => '0'), valid => arvalid, ready => arready),
      r => (data => rdata, resp => rresp, valid => rvalid, ready => rready)
    );
  end function;

  function axi4_32_a32_intf(
    awaddr : std_logic_vector(31 downto 0); awvalid : std_logic; awready : std_logic;
    wdata : std_logic_vector(31 downto 0); wstrb : std_logic_vector(3 downto 0); wlast : std_logic; wvalid : std_logic; wready : std_logic;
    bresp : axi_resp_t; bvalid : std_logic; bready : std_logic;
    araddr : std_logic_vector(31 downto 0); arvalid : std_logic; arready : std_logic;
    rdata : std_logic_vector(31 downto 0); rresp : axi_resp_t; rlast : std_logic; rvalid : std_logic; rready : std_logic
  ) return axi4_32_a32_intf_t is
  begin
    return (
      aw => (addr => awaddr, len => (others => '0'), size => axi_size_from_bytes(4), burst => AXI_BURST_INCR, prot => (others => '0'), valid => awvalid, ready => awready),
      w => (data => wdata, strb => wstrb, last => wlast, valid => wvalid, ready => wready),
      b => (resp => bresp, valid => bvalid, ready => bready),
      ar => (addr => araddr, len => (others => '0'), size => axi_size_from_bytes(4), burst => AXI_BURST_INCR, prot => (others => '0'), valid => arvalid, ready => arready),
      r => (data => rdata, resp => rresp, last => rlast, valid => rvalid, ready => rready)
    );
  end function;
end package body;
