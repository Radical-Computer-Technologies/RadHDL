library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity radila_v1_0 is
  generic (
    C_S00_AXI_DATA_WIDTH : integer := 32;
    C_S00_AXI_ADDR_WIDTH : integer := 6;
    SAMPLE_WIDTH         : integer := 32;
    EVENT_WIDTH          : integer := 8;
    DEPTH                : integer := 1024;
    ADDR_WIDTH           : integer := 10;
    CMD_LANES            : integer := 4;
    VENDOR_TAG           : string  := "XILINX";
    PRODUCT_SERIES_TAG   : string  := "7SERIES";
    G_DEBUG_BUS          : string  := "AXI_LITE"
  );
  port (
    sample_i       : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    event_i        : in  std_logic_vector(EVENT_WIDTH - 1 downto 0);
    irq_o          : out std_logic;
    s00_axi_aclk   : in  std_logic;
    s00_axi_aresetn: in  std_logic;
    s00_axi_awaddr : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
    s00_axi_awprot : in  std_logic_vector(2 downto 0);
    s00_axi_awvalid: in  std_logic;
    s00_axi_awready: out std_logic;
    s00_axi_wdata  : in  std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
    s00_axi_wstrb  : in  std_logic_vector((C_S00_AXI_DATA_WIDTH / 8) - 1 downto 0);
    s00_axi_wvalid : in  std_logic;
    s00_axi_wready : out std_logic;
    s00_axi_bresp  : out std_logic_vector(1 downto 0);
    s00_axi_bvalid : out std_logic;
    s00_axi_bready : in  std_logic;
    s00_axi_araddr : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
    s00_axi_arprot : in  std_logic_vector(2 downto 0);
    s00_axi_arvalid: in  std_logic;
    s00_axi_arready: out std_logic;
    s00_axi_rdata  : out std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
    s00_axi_rresp  : out std_logic_vector(1 downto 0);
    s00_axi_rvalid : out std_logic;
    s00_axi_rready : in  std_logic
  );
end entity;

architecture rtl of radila_v1_0 is
begin
  u_rad_debug_hub : entity work.RadDebugHub
    generic map (
      C_S_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH,
      SAMPLE_WIDTH       => SAMPLE_WIDTH,
      EVENT_WIDTH        => EVENT_WIDTH,
      DEPTH              => DEPTH,
      ADDR_WIDTH         => ADDR_WIDTH,
      CMD_LANES          => CMD_LANES,
      VENDOR_TAG         => VENDOR_TAG,
      PRODUCT_SERIES_TAG => PRODUCT_SERIES_TAG,
      G_DEBUG_BUS        => G_DEBUG_BUS
    )
    port map (
      sample_clk     => s00_axi_aclk,
      sample_rstn    => s00_axi_aresetn,
      sample_i       => sample_i,
      event_i        => event_i,
      irq_o          => irq_o,
      S_AXI_ACLK     => s00_axi_aclk,
      S_AXI_ARESETN  => s00_axi_aresetn,
      S_AXI_AWADDR   => s00_axi_awaddr,
      S_AXI_AWPROT   => s00_axi_awprot,
      S_AXI_AWVALID  => s00_axi_awvalid,
      S_AXI_AWREADY  => s00_axi_awready,
      S_AXI_WDATA    => s00_axi_wdata,
      S_AXI_WSTRB    => s00_axi_wstrb,
      S_AXI_WVALID   => s00_axi_wvalid,
      S_AXI_WREADY   => s00_axi_wready,
      S_AXI_BRESP    => s00_axi_bresp,
      S_AXI_BVALID   => s00_axi_bvalid,
      S_AXI_BREADY   => s00_axi_bready,
      S_AXI_ARADDR   => s00_axi_araddr,
      S_AXI_ARPROT   => s00_axi_arprot,
      S_AXI_ARVALID  => s00_axi_arvalid,
      S_AXI_ARREADY  => s00_axi_arready,
      S_AXI_RDATA    => s00_axi_rdata,
      S_AXI_RRESP    => s00_axi_rresp,
      S_AXI_RVALID   => s00_axi_rvalid,
      S_AXI_RREADY   => s00_axi_rready
    );
end architecture;
