library ieee;
use ieee.std_logic_1164.all;

library radhdl;
use radhdl.radhdl_axi_pkg.all;

-- Synthesis smoke top for RADHDL AXI4 full record helpers.
-- Uses scalar top-level ports and internal fixed-width records for a 32-bit
-- data, 32-bit address master endpoint.
entity axi4_record_synth_smoke is
  port (
    addr_i    : in  std_logic_vector(31 downto 0);
    data_i    : in  std_logic_vector(31 downto 0);
    strb_i    : in  std_logic_vector(3 downto 0);
    valid_i   : in  std_logic;
    ready_i   : in  std_logic;
    resp_i    : in  std_logic_vector(1 downto 0);
    last_i    : in  std_logic;
    awaddr_o  : out std_logic_vector(31 downto 0);
    awvalid_o : out std_logic;
    wdata_o   : out std_logic_vector(31 downto 0);
    wstrb_o   : out std_logic_vector(3 downto 0);
    wlast_o   : out std_logic;
    wvalid_o  : out std_logic;
    bready_o  : out std_logic;
    araddr_o  : out std_logic_vector(31 downto 0);
    arvalid_o : out std_logic;
    rready_o  : out std_logic;
    rdata_o   : out std_logic_vector(31 downto 0);
    rvalid_o  : out std_logic
  );
end entity;

architecture rtl of axi4_record_synth_smoke is
  signal m : axi4_32_a32_intf_t := AXI4_32_A32_INTF_NULL;
  signal resp_word : std_logic_vector(31 downto 0) := (others => '0');
begin
  m <= axi4_32_a32_intf(
    addr_i, valid_i, ready_i,
    data_i, strb_i, last_i, valid_i, ready_i,
    resp_i, valid_i, ready_i,
    addr_i, valid_i, ready_i,
    data_i, resp_i, last_i, valid_i, ready_i
  );

  awaddr_o <= m.aw.addr;
  awvalid_o <= m.aw.valid;
  wdata_o <= m.w.data;
  wstrb_o <= m.w.strb;
  wlast_o <= m.w.last;
  wvalid_o <= m.w.valid;
  bready_o <= m.b.ready;
  araddr_o <= m.ar.addr;
  arvalid_o <= m.ar.valid;
  rready_o <= m.r.ready;
  resp_word <= (31 downto 4 => '0') & m.b.resp & m.r.resp;
  rdata_o <= m.r.data xor resp_word;
  rvalid_o <= m.r.valid;
end architecture;
