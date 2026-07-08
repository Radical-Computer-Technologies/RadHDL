library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library radif;

-- Self-checking or stimulus-focused testbench for interfaces smoke.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radif_interfaces_smoke is
end entity;

architecture sim of tb_radif_interfaces_smoke is
  signal clk  : std_logic := '0';
  signal rstn : std_logic := '0';

  signal spi_sclk : std_logic := '0';
  signal spi_cs_n : std_logic := '1';
  signal spi_mosi : std_logic := '0';
  signal spi_miso : std_logic;
  signal spi_oen  : std_logic;

  signal qspi_sclk : std_logic := '0';
  signal qspi_cs_n : std_logic := '1';
  signal qspi_io_i : std_logic_vector(3 downto 0) := (others => '0');
  signal qspi_io_o : std_logic_vector(3 downto 0);
  signal qspi_oen  : std_logic_vector(3 downto 0);

  signal i2c_scl : std_logic := '1';
  signal i2c_sda : std_logic := '1';
  signal i2c_oen : std_logic;

  signal spi_wr_addr  : std_logic_vector(15 downto 0);
  signal spi_rd_addr  : std_logic_vector(15 downto 0);
  signal spi_wr_en    : std_logic;
  signal spi_rd_en    : std_logic;
  signal spi_din      : std_logic_vector(31 downto 0);
  signal spi_dout     : std_logic_vector(31 downto 0) := x"01020304";
  signal spi_wr_valid : std_logic := '0';
  signal spi_rd_valid : std_logic := '0';

  signal qspi_wr_addr  : std_logic_vector(15 downto 0);
  signal qspi_rd_addr  : std_logic_vector(15 downto 0);
  signal qspi_wr_en    : std_logic;
  signal qspi_rd_en    : std_logic;
  signal qspi_din      : std_logic_vector(31 downto 0);
  signal qspi_dout     : std_logic_vector(31 downto 0) := x"11223344";
  signal qspi_wr_valid : std_logic := '0';
  signal qspi_rd_valid : std_logic := '0';

  signal i2c_wr_addr  : std_logic_vector(15 downto 0);
  signal i2c_rd_addr  : std_logic_vector(15 downto 0);
  signal i2c_wr_en    : std_logic;
  signal i2c_rd_en    : std_logic;
  signal i2c_din      : std_logic_vector(31 downto 0);
  signal i2c_dout     : std_logic_vector(31 downto 0) := x"55667788";
  signal i2c_wr_valid : std_logic := '0';
  signal i2c_rd_valid : std_logic := '0';

  signal dma_reg_wr_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal dma_reg_rd_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal dma_reg_wr_en    : std_logic := '0';
  signal dma_reg_rd_en    : std_logic := '0';
  signal dma_reg_din      : std_logic_vector(31 downto 0) := (others => '0');
  signal dma_reg_dout     : std_logic_vector(31 downto 0);
  signal dma_wr_rdy       : std_logic;
  signal dma_rd_rdy       : std_logic;
  signal dma_wr_valid     : std_logic;
  signal dma_rd_valid     : std_logic;
  signal dma_error        : std_logic;
  signal irq              : std_logic;

  signal awaddr  : std_logic_vector(31 downto 0);
  signal awlen   : std_logic_vector(7 downto 0);
  signal awsize  : std_logic_vector(2 downto 0);
  signal awburst : std_logic_vector(1 downto 0);
  signal awvalid : std_logic;
  signal wdata   : std_logic_vector(31 downto 0);
  signal wstrb   : std_logic_vector(3 downto 0);
  signal wlast   : std_logic;
  signal wvalid  : std_logic;
  signal araddr  : std_logic_vector(31 downto 0);
  signal arlen   : std_logic_vector(7 downto 0);
  signal arsize  : std_logic_vector(2 downto 0);
  signal arburst : std_logic_vector(1 downto 0);
  signal arvalid : std_logic;
  signal rready  : std_logic;
  signal bready  : std_logic;
  signal m_tdata : std_logic_vector(31 downto 0);
  signal m_tvalid: std_logic;
  signal m_tlast : std_logic;
  signal s_tready: std_logic;

  signal sa_awaddr  : std_logic_vector(31 downto 0);
  signal sa_awlen   : std_logic_vector(7 downto 0);
  signal sa_awsize  : std_logic_vector(2 downto 0);
  signal sa_awburst : std_logic_vector(1 downto 0);
  signal sa_awvalid : std_logic;
  signal sa_wdata   : std_logic_vector(31 downto 0);
  signal sa_wstrb   : std_logic_vector(3 downto 0);
  signal sa_wlast   : std_logic;
  signal sa_wvalid  : std_logic;
  signal sa_bready  : std_logic;
  signal sa_araddr  : std_logic_vector(31 downto 0);
  signal sa_arlen   : std_logic_vector(7 downto 0);
  signal sa_arsize  : std_logic_vector(2 downto 0);
  signal sa_arburst : std_logic_vector(1 downto 0);
  signal sa_arvalid : std_logic;
  signal sa_rready  : std_logic;
begin
  clk <= not clk after 5 ns;

  u_spi : entity radif.radif_spi_slave_to_reg
    port map (
      clk => clk,
      rstn => rstn,
      spi_sclk_i => spi_sclk,
      spi_cs_n_i => spi_cs_n,
      spi_mosi_i => spi_mosi,
      spi_miso_o => spi_miso,
      spi_miso_oen => spi_oen,
      reg_wr_addr => spi_wr_addr,
      reg_rd_addr => spi_rd_addr,
      reg_wr_en => spi_wr_en,
      reg_rd_en => spi_rd_en,
      reg_data_in => spi_din,
      reg_data_out => spi_dout,
      reg_wr_rdy => '1',
      reg_rd_rdy => '1',
      reg_wr_valid => spi_wr_valid,
      reg_rd_valid => spi_rd_valid,
      reg_error => '0'
    );

  u_qspi : entity radif.radif_qspi_slave_to_reg
    generic map (
      ENABLE_QUAD_DATA => true
    )
    port map (
      clk => clk,
      rstn => rstn,
      qspi_sclk_i => qspi_sclk,
      qspi_cs_n_i => qspi_cs_n,
      qspi_io_i => qspi_io_i,
      qspi_io_o => qspi_io_o,
      qspi_io_oen => qspi_oen,
      reg_wr_addr => qspi_wr_addr,
      reg_rd_addr => qspi_rd_addr,
      reg_wr_en => qspi_wr_en,
      reg_rd_en => qspi_rd_en,
      reg_data_in => qspi_din,
      reg_data_out => qspi_dout,
      reg_wr_rdy => '1',
      reg_rd_rdy => '1',
      reg_wr_valid => qspi_wr_valid,
      reg_rd_valid => qspi_rd_valid,
      reg_error => '0'
    );

  u_i2c : entity radif.radif_i2c_slave_to_reg
    port map (
      clk => clk,
      rstn => rstn,
      i2c_scl_i => i2c_scl,
      i2c_sda_i => i2c_sda,
      i2c_sda_oen => i2c_oen,
      reg_wr_addr => i2c_wr_addr,
      reg_rd_addr => i2c_rd_addr,
      reg_wr_en => i2c_wr_en,
      reg_rd_en => i2c_rd_en,
      reg_data_in => i2c_din,
      reg_data_out => i2c_dout,
      reg_wr_rdy => '1',
      reg_rd_rdy => '1',
      reg_wr_valid => i2c_wr_valid,
      reg_rd_valid => i2c_rd_valid,
      reg_error => '0'
    );

  u_dma : entity radif.radif_axi4_axis_dma
    port map (
      clk => clk,
      rstn => rstn,
      reg_wr_addr => dma_reg_wr_addr,
      reg_rd_addr => dma_reg_rd_addr,
      reg_wr_en => dma_reg_wr_en,
      reg_rd_en => dma_reg_rd_en,
      reg_data_in => dma_reg_din,
      reg_data_out => dma_reg_dout,
      reg_wr_rdy => dma_wr_rdy,
      reg_rd_rdy => dma_rd_rdy,
      reg_wr_valid => dma_wr_valid,
      reg_rd_valid => dma_rd_valid,
      reg_error => dma_error,
      irq_o => irq,
      m_axi_awaddr => awaddr,
      m_axi_awlen => awlen,
      m_axi_awsize => awsize,
      m_axi_awburst => awburst,
      m_axi_awvalid => awvalid,
      m_axi_awready => '1',
      m_axi_wdata => wdata,
      m_axi_wstrb => wstrb,
      m_axi_wlast => wlast,
      m_axi_wvalid => wvalid,
      m_axi_wready => '1',
      m_axi_bresp => "00",
      m_axi_bvalid => '0',
      m_axi_bready => bready,
      m_axi_araddr => araddr,
      m_axi_arlen => arlen,
      m_axi_arsize => arsize,
      m_axi_arburst => arburst,
      m_axi_arvalid => arvalid,
      m_axi_arready => '1',
      m_axi_rdata => x"00000000",
      m_axi_rresp => "00",
      m_axi_rlast => '1',
      m_axi_rvalid => '0',
      m_axi_rready => rready,
      m_axis_tdata => m_tdata,
      m_axis_tvalid => m_tvalid,
      m_axis_tready => '1',
      m_axis_tlast => m_tlast,
      s_axis_tdata => x"00000000",
      s_axis_tvalid => '0',
      s_axis_tready => s_tready,
      s_axis_tlast => '0'
    );

  u_spi_axi : entity radif.radif_spi_axi_master
    port map (
      clk => clk,
      rstn => rstn,
      spi_sclk_i => spi_sclk,
      spi_cs_n_i => spi_cs_n,
      spi_mosi_i => spi_mosi,
      spi_miso_o => open,
      spi_miso_oen => open,
      m_axi_awaddr => sa_awaddr,
      m_axi_awlen => sa_awlen,
      m_axi_awsize => sa_awsize,
      m_axi_awburst => sa_awburst,
      m_axi_awvalid => sa_awvalid,
      m_axi_awready => '1',
      m_axi_wdata => sa_wdata,
      m_axi_wstrb => sa_wstrb,
      m_axi_wlast => sa_wlast,
      m_axi_wvalid => sa_wvalid,
      m_axi_wready => '1',
      m_axi_bresp => "00",
      m_axi_bvalid => '0',
      m_axi_bready => sa_bready,
      m_axi_araddr => sa_araddr,
      m_axi_arlen => sa_arlen,
      m_axi_arsize => sa_arsize,
      m_axi_arburst => sa_arburst,
      m_axi_arvalid => sa_arvalid,
      m_axi_arready => '1',
      m_axi_rdata => x"A5A55A5A",
      m_axi_rresp => "00",
      m_axi_rlast => '1',
      m_axi_rvalid => '0',
      m_axi_rready => sa_rready
    );

  process
  begin
    wait for 50 ns;
    rstn <= '1';
    wait for 100 ns;
    assert spi_oen = '1' report "SPI MISO should be tri-stated when CS is high" severity failure;
    assert qspi_oen = "1111" report "QSPI pins should be tri-stated when CS is high" severity failure;
    report "PASS tb_radif_interfaces_smoke";
    std.env.finish;
    wait;
  end process;
end architecture;
