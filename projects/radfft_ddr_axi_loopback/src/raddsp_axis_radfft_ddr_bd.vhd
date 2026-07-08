library ieee;
use ieee.std_logic_1164.all;

-- Block-design wrapper for the DDR-backed RadFFT loopback reference design.
-- Presents the RadFFT DDR accelerator through generated Vivado block-design integration signals.
entity raddsp_axis_radfft_ddr_bd is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR                  : string := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY           : string := "ultrascaleplus";
    -- Sets the bit width for G AXI ADDR WIDTH values carried by this module.
    G_AXI_ADDR_WIDTH        : positive := 40;
    -- Sets the bit width for G AXI DATA WIDTH values carried by this module.
    G_AXI_DATA_WIDTH        : positive := 128;
    -- Sets the bit width for G AXIS DATA WIDTH values carried by this module.
    G_AXIS_DATA_WIDTH       : positive := 128;
    -- Sets the bit width for G AXI LITE ADDR WIDTH values carried by this module.
    G_AXI_LITE_ADDR_WIDTH   : positive := 16;
    -- Sets the storage depth, frame length, or number of buffered samples used internally.
    G_FIFO_DEPTH            : positive := 1024;
    -- Configures G FIFO FWFT for this instance.
    G_FIFO_FWFT             : boolean := true;
    -- Configures G MAX BURST BEATS for this instance.
    G_MAX_BURST_BEATS       : positive := 64;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_POINTS            : positive := 1024;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_RADIX             : positive := 2;
    -- Sets the bit width for G FFT INPUT WIDTH values carried by this module.
    G_FFT_INPUT_WIDTH       : positive := 32;
    -- Sets the bit width for G FFT TWIDDLE WIDTH values carried by this module.
    G_FFT_TWIDDLE_WIDTH     : positive := 16;
    -- Sets the bit width for G FFT OUTPUT WIDTH values carried by this module.
    G_FFT_OUTPUT_WIDTH      : positive := 32;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_SCALE_EACH_STAGE  : boolean := true;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_MEMORY_STYLE      : string := "block";
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_TWIDDLE_INIT_FILE : string := "../../mem/radfft_twiddle_1024_16_fft.mem";
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_INVERSE           : boolean := false;
    -- Sets the number of parallel sample lanes processed per handshake beat.
    G_MAX_MULTIPLIER_LANES  : positive := 16;
    -- Configures G DEFAULT REGION BYTES for this instance.
    G_DEFAULT_REGION_BYTES  : natural := 67108864
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk            : in  std_logic;
    -- Active-low reset for this clock domain.
    rstn           : in  std_logic;

    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awaddr   : in  std_logic_vector(G_AXI_LITE_ADDR_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awprot   : in  std_logic_vector(2 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awvalid  : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awready  : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wdata    : in  std_logic_vector(31 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wstrb    : in  std_logic_vector(3 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wvalid   : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wready   : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bresp    : out std_logic_vector(1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bvalid   : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bready   : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_araddr   : in  std_logic_vector(G_AXI_LITE_ADDR_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arprot   : in  std_logic_vector(2 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arvalid  : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arready  : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rdata    : out std_logic_vector(31 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rresp    : out std_logic_vector(1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rvalid   : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rready   : in  std_logic;

    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awaddr   : out std_logic_vector(G_AXI_ADDR_WIDTH - 1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awlen    : out std_logic_vector(7 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awsize   : out std_logic_vector(2 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awburst  : out std_logic_vector(1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awlock   : out std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awcache  : out std_logic_vector(3 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awprot   : out std_logic_vector(2 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awqos    : out std_logic_vector(3 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awvalid  : out std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_awready  : in  std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_wdata    : out std_logic_vector(G_AXI_DATA_WIDTH - 1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_wstrb    : out std_logic_vector((G_AXI_DATA_WIDTH / 8) - 1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_wlast    : out std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_wvalid   : out std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_wready   : in  std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_bresp    : in  std_logic_vector(1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_bvalid   : in  std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_bready   : out std_logic;

    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_araddr   : out std_logic_vector(G_AXI_ADDR_WIDTH - 1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arlen    : out std_logic_vector(7 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arsize   : out std_logic_vector(2 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arburst  : out std_logic_vector(1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arlock   : out std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arcache  : out std_logic_vector(3 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arprot   : out std_logic_vector(2 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arqos    : out std_logic_vector(3 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arvalid  : out std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_arready  : in  std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_rdata    : in  std_logic_vector(G_AXI_DATA_WIDTH - 1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_rresp    : in  std_logic_vector(1 downto 0);
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_rlast    : in  std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_rvalid   : in  std_logic;
    -- AXI master-channel signal used for memory-mapped transfer generation.
    m_axi_rready   : out std_logic;

    -- Input AXI-stream payload containing packed sample or feature lanes.
    s_axis_tdata   : in  std_logic_vector(G_AXIS_DATA_WIDTH - 1 downto 0);
    -- Input AXI-stream valid qualifier for the current sample beat.
    s_axis_tvalid  : in  std_logic;
    -- Input AXI-stream ready response indicating this block can accept a beat.
    s_axis_tready  : out std_logic;
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast   : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata   : out std_logic_vector(G_AXIS_DATA_WIDTH - 1 downto 0);
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid  : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready  : in  std_logic;
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast   : out std_logic;

    -- Output irq o signal generated by this module.
    irq_o          : out std_logic
  );

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_PARAMETER of clk : signal is "ASSOCIATED_BUSIF S_AXI:M_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET rstn, FREQ_HZ 100000000";
  attribute X_INTERFACE_INFO of rstn : signal is "xilinx.com:signal:reset:1.0 rstn RST";
  attribute X_INTERFACE_PARAMETER of rstn : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of irq_o : signal is "xilinx.com:signal:interrupt:1.0 irq_o INTERRUPT";
  attribute X_INTERFACE_PARAMETER of irq_o : signal is "SENSITIVITY LEVEL_HIGH";

  attribute X_INTERFACE_INFO of s_axi_awaddr : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWADDR";
  attribute X_INTERFACE_INFO of s_axi_awprot : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWPROT";
  attribute X_INTERFACE_INFO of s_axi_awvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWVALID";
  attribute X_INTERFACE_INFO of s_axi_awready : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWREADY";
  attribute X_INTERFACE_INFO of s_axi_wdata : signal is "xilinx.com:interface:aximm:1.0 S_AXI WDATA";
  attribute X_INTERFACE_INFO of s_axi_wstrb : signal is "xilinx.com:interface:aximm:1.0 S_AXI WSTRB";
  attribute X_INTERFACE_INFO of s_axi_wvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI WVALID";
  attribute X_INTERFACE_INFO of s_axi_wready : signal is "xilinx.com:interface:aximm:1.0 S_AXI WREADY";
  attribute X_INTERFACE_INFO of s_axi_bresp : signal is "xilinx.com:interface:aximm:1.0 S_AXI BRESP";
  attribute X_INTERFACE_INFO of s_axi_bvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI BVALID";
  attribute X_INTERFACE_INFO of s_axi_bready : signal is "xilinx.com:interface:aximm:1.0 S_AXI BREADY";
  attribute X_INTERFACE_INFO of s_axi_araddr : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARADDR";
  attribute X_INTERFACE_INFO of s_axi_arprot : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARPROT";
  attribute X_INTERFACE_INFO of s_axi_arvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARVALID";
  attribute X_INTERFACE_INFO of s_axi_arready : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARREADY";
  attribute X_INTERFACE_INFO of s_axi_rdata : signal is "xilinx.com:interface:aximm:1.0 S_AXI RDATA";
  attribute X_INTERFACE_INFO of s_axi_rresp : signal is "xilinx.com:interface:aximm:1.0 S_AXI RRESP";
  attribute X_INTERFACE_INFO of s_axi_rvalid : signal is "xilinx.com:interface:aximm:1.0 S_AXI RVALID";
  attribute X_INTERFACE_INFO of s_axi_rready : signal is "xilinx.com:interface:aximm:1.0 S_AXI RREADY";
  attribute X_INTERFACE_PARAMETER of s_axi_awaddr : signal is "XIL_INTERFACENAME S_AXI, DATA_WIDTH 32, PROTOCOL AXI4LITE, FREQ_HZ 100000000, ADDR_WIDTH 16";

  attribute X_INTERFACE_INFO of m_axi_awaddr : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWADDR";
  attribute X_INTERFACE_INFO of m_axi_awlen : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWLEN";
  attribute X_INTERFACE_INFO of m_axi_awsize : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE";
  attribute X_INTERFACE_INFO of m_axi_awburst : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWBURST";
  attribute X_INTERFACE_INFO of m_axi_awlock : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK";
  attribute X_INTERFACE_INFO of m_axi_awcache : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE";
  attribute X_INTERFACE_INFO of m_axi_awprot : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWPROT";
  attribute X_INTERFACE_INFO of m_axi_awqos : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWQOS";
  attribute X_INTERFACE_INFO of m_axi_awvalid : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWVALID";
  attribute X_INTERFACE_INFO of m_axi_awready : signal is "xilinx.com:interface:aximm:1.0 M_AXI AWREADY";
  attribute X_INTERFACE_INFO of m_axi_wdata : signal is "xilinx.com:interface:aximm:1.0 M_AXI WDATA";
  attribute X_INTERFACE_INFO of m_axi_wstrb : signal is "xilinx.com:interface:aximm:1.0 M_AXI WSTRB";
  attribute X_INTERFACE_INFO of m_axi_wlast : signal is "xilinx.com:interface:aximm:1.0 M_AXI WLAST";
  attribute X_INTERFACE_INFO of m_axi_wvalid : signal is "xilinx.com:interface:aximm:1.0 M_AXI WVALID";
  attribute X_INTERFACE_INFO of m_axi_wready : signal is "xilinx.com:interface:aximm:1.0 M_AXI WREADY";
  attribute X_INTERFACE_INFO of m_axi_bresp : signal is "xilinx.com:interface:aximm:1.0 M_AXI BRESP";
  attribute X_INTERFACE_INFO of m_axi_bvalid : signal is "xilinx.com:interface:aximm:1.0 M_AXI BVALID";
  attribute X_INTERFACE_INFO of m_axi_bready : signal is "xilinx.com:interface:aximm:1.0 M_AXI BREADY";
  attribute X_INTERFACE_INFO of m_axi_araddr : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARADDR";
  attribute X_INTERFACE_INFO of m_axi_arlen : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARLEN";
  attribute X_INTERFACE_INFO of m_axi_arsize : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE";
  attribute X_INTERFACE_INFO of m_axi_arburst : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARBURST";
  attribute X_INTERFACE_INFO of m_axi_arlock : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK";
  attribute X_INTERFACE_INFO of m_axi_arcache : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE";
  attribute X_INTERFACE_INFO of m_axi_arprot : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARPROT";
  attribute X_INTERFACE_INFO of m_axi_arqos : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARQOS";
  attribute X_INTERFACE_INFO of m_axi_arvalid : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARVALID";
  attribute X_INTERFACE_INFO of m_axi_arready : signal is "xilinx.com:interface:aximm:1.0 M_AXI ARREADY";
  attribute X_INTERFACE_INFO of m_axi_rdata : signal is "xilinx.com:interface:aximm:1.0 M_AXI RDATA";
  attribute X_INTERFACE_INFO of m_axi_rresp : signal is "xilinx.com:interface:aximm:1.0 M_AXI RRESP";
  attribute X_INTERFACE_INFO of m_axi_rlast : signal is "xilinx.com:interface:aximm:1.0 M_AXI RLAST";
  attribute X_INTERFACE_INFO of m_axi_rvalid : signal is "xilinx.com:interface:aximm:1.0 M_AXI RVALID";
  attribute X_INTERFACE_INFO of m_axi_rready : signal is "xilinx.com:interface:aximm:1.0 M_AXI RREADY";
  attribute X_INTERFACE_PARAMETER of m_axi_awaddr : signal is "XIL_INTERFACENAME M_AXI, DATA_WIDTH 128, PROTOCOL AXI4, FREQ_HZ 100000000";

  attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 S_AXIS TDATA";
  attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 S_AXIS TVALID";
  attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 S_AXIS TREADY";
  attribute X_INTERFACE_INFO of s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 S_AXIS TLAST";
  attribute X_INTERFACE_PARAMETER of s_axis_tdata : signal is "XIL_INTERFACENAME S_AXIS, TDATA_NUM_BYTES 16, FREQ_HZ 100000000";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 M_AXIS TDATA";
  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 M_AXIS TVALID";
  attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 M_AXIS TREADY";
  attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 M_AXIS TLAST";
  attribute X_INTERFACE_PARAMETER of m_axis_tdata : signal is "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 16, FREQ_HZ 100000000";
end entity;

architecture rtl of raddsp_axis_radfft_ddr_bd is
begin
  m_axi_awlock <= '0';
  m_axi_awcache <= "0011";
  m_axi_awprot <= "000";
  m_axi_awqos <= "0000";
  m_axi_arlock <= '0';
  m_axi_arcache <= "0011";
  m_axi_arprot <= "000";
  m_axi_arqos <= "0000";

  core_i: entity work.raddsp_axis_radfft_ddr
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      G_AXI_ADDR_WIDTH => G_AXI_ADDR_WIDTH,
      G_AXI_DATA_WIDTH => G_AXI_DATA_WIDTH,
      G_AXIS_DATA_WIDTH => G_AXIS_DATA_WIDTH,
      G_AXI_LITE_ADDR_WIDTH => G_AXI_LITE_ADDR_WIDTH,
      G_FIFO_DEPTH => G_FIFO_DEPTH,
      G_FIFO_FWFT => G_FIFO_FWFT,
      G_MAX_BURST_BEATS => G_MAX_BURST_BEATS,
      G_FFT_POINTS => G_FFT_POINTS,
      G_FFT_RADIX => G_FFT_RADIX,
      G_FFT_INPUT_WIDTH => G_FFT_INPUT_WIDTH,
      G_FFT_TWIDDLE_WIDTH => G_FFT_TWIDDLE_WIDTH,
      G_FFT_OUTPUT_WIDTH => G_FFT_OUTPUT_WIDTH,
      G_FFT_SCALE_EACH_STAGE => G_FFT_SCALE_EACH_STAGE,
      G_FFT_MEMORY_STYLE => G_FFT_MEMORY_STYLE,
      G_FFT_TWIDDLE_INIT_FILE => G_FFT_TWIDDLE_INIT_FILE,
      G_FFT_INVERSE => G_FFT_INVERSE,
      G_MAX_MULTIPLIER_LANES => G_MAX_MULTIPLIER_LANES,
      G_DEFAULT_REGION_BYTES => G_DEFAULT_REGION_BYTES
    )
    port map (
      clk => clk,
      rstn => rstn,
      s_axi_awaddr => s_axi_awaddr,
      s_axi_awprot => s_axi_awprot,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata => s_axi_wdata,
      s_axi_wstrb => s_axi_wstrb,
      s_axi_wvalid => s_axi_wvalid,
      s_axi_wready => s_axi_wready,
      s_axi_bresp => s_axi_bresp,
      s_axi_bvalid => s_axi_bvalid,
      s_axi_bready => s_axi_bready,
      s_axi_araddr => s_axi_araddr,
      s_axi_arprot => s_axi_arprot,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata => s_axi_rdata,
      s_axi_rresp => s_axi_rresp,
      s_axi_rvalid => s_axi_rvalid,
      s_axi_rready => s_axi_rready,
      m_axi_awaddr => m_axi_awaddr,
      m_axi_awlen => m_axi_awlen,
      m_axi_awsize => m_axi_awsize,
      m_axi_awburst => m_axi_awburst,
      m_axi_awvalid => m_axi_awvalid,
      m_axi_awready => m_axi_awready,
      m_axi_wdata => m_axi_wdata,
      m_axi_wstrb => m_axi_wstrb,
      m_axi_wlast => m_axi_wlast,
      m_axi_wvalid => m_axi_wvalid,
      m_axi_wready => m_axi_wready,
      m_axi_bresp => m_axi_bresp,
      m_axi_bvalid => m_axi_bvalid,
      m_axi_bready => m_axi_bready,
      m_axi_araddr => m_axi_araddr,
      m_axi_arlen => m_axi_arlen,
      m_axi_arsize => m_axi_arsize,
      m_axi_arburst => m_axi_arburst,
      m_axi_arvalid => m_axi_arvalid,
      m_axi_arready => m_axi_arready,
      m_axi_rdata => m_axi_rdata,
      m_axi_rresp => m_axi_rresp,
      m_axi_rlast => m_axi_rlast,
      m_axi_rvalid => m_axi_rvalid,
      m_axi_rready => m_axi_rready,
      s_axis_tdata => s_axis_tdata,
      s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      s_axis_tlast => s_axis_tlast,
      m_axis_tdata => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast => m_axis_tlast,
      irq_o => irq_o
    );
end architecture;
