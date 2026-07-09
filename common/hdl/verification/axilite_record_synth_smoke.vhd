library ieee;
use ieee.std_logic_1164.all;

library radhdl;
use radhdl.radhdl_axi_pkg.all;

-- Synthesis smoke top for RADHDL AXI4-Lite record helpers.
-- Keeps scalar boundary ports while exercising AXI-Lite fixed-width records
-- internally, matching Vivado/IP Integrator compatible wrapper usage.
entity axilite_record_synth_smoke is
  port (
    awaddr_i  : in  std_logic_vector(31 downto 0);
    awvalid_i : in  std_logic;
    wdata_i   : in  std_logic_vector(31 downto 0);
    wstrb_i   : in  std_logic_vector(3 downto 0);
    wvalid_i  : in  std_logic;
    bready_i  : in  std_logic;
    araddr_i  : in  std_logic_vector(31 downto 0);
    arvalid_i : in  std_logic;
    rready_i  : in  std_logic;
    awready_o : out std_logic;
    wready_o  : out std_logic;
    bresp_o   : out std_logic_vector(1 downto 0);
    bvalid_o  : out std_logic;
    arready_o : out std_logic;
    rdata_o   : out std_logic_vector(31 downto 0);
    rresp_o   : out std_logic_vector(1 downto 0);
    rvalid_o  : out std_logic
  );
end entity;

architecture rtl of axilite_record_synth_smoke is
  signal s : axilite32_a32_intf_t := AXILITE32_A32_INTF_NULL;
begin
  s <= axilite32_a32_intf(
    awaddr_i, awvalid_i, awvalid_i,
    wdata_i, wstrb_i, wvalid_i, wvalid_i,
    wstrb_i(1 downto 0), bready_i, bready_i,
    araddr_i, arvalid_i, arvalid_i,
    awaddr_i xor araddr_i xor wdata_i, wstrb_i(3 downto 2), rready_i, rready_i
  );

  awready_o <= s.aw.ready;
  wready_o <= s.w.ready;
  bresp_o <= s.b.resp;
  bvalid_o <= s.b.valid;
  arready_o <= s.ar.ready;
  rdata_o <= s.r.data;
  rresp_o <= s.r.resp;
  rvalid_o <= s.r.valid;
end architecture;
