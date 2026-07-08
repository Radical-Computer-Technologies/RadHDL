library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library radif;

-- Self-checking or stimulus-focused testbench for axi4 axis dma.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radif_axi4_axis_dma is
end entity;

architecture sim of tb_radif_axi4_axis_dma is
  signal clk          : std_logic := '0';
  signal rstn         : std_logic := '0';
  signal reg_wr_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_rd_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_wr_en    : std_logic := '0';
  signal reg_rd_en    : std_logic := '0';
  signal reg_din      : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_dout     : std_logic_vector(31 downto 0);
  signal reg_wr_rdy   : std_logic;
  signal reg_rd_rdy   : std_logic;
  signal reg_wr_valid : std_logic;
  signal reg_rd_valid : std_logic;
  signal reg_error    : std_logic;
  signal irq          : std_logic;

  signal awaddr       : std_logic_vector(31 downto 0);
  signal awlen        : std_logic_vector(7 downto 0);
  signal awsize       : std_logic_vector(2 downto 0);
  signal awburst      : std_logic_vector(1 downto 0);
  signal awvalid      : std_logic;
  signal awready      : std_logic := '1';
  signal wdata        : std_logic_vector(31 downto 0);
  signal wstrb        : std_logic_vector(3 downto 0);
  signal wlast        : std_logic;
  signal wvalid       : std_logic;
  signal wready       : std_logic := '1';
  signal bresp        : std_logic_vector(1 downto 0) := "00";
  signal bvalid       : std_logic := '0';
  signal bready       : std_logic;
  signal araddr       : std_logic_vector(31 downto 0);
  signal arlen        : std_logic_vector(7 downto 0);
  signal arsize       : std_logic_vector(2 downto 0);
  signal arburst      : std_logic_vector(1 downto 0);
  signal arvalid      : std_logic;
  signal arready      : std_logic := '1';
  signal rdata        : std_logic_vector(31 downto 0) := (others => '0');
  signal rresp        : std_logic_vector(1 downto 0) := "00";
  signal rlast        : std_logic := '1';
  signal rvalid       : std_logic := '0';
  signal rready       : std_logic;
  signal m_tdata      : std_logic_vector(31 downto 0);
  signal m_tvalid     : std_logic;
  signal m_tready     : std_logic := '1';
  signal m_tlast      : std_logic;
  signal s_tdata      : std_logic_vector(31 downto 0) := (others => '0');
  signal s_tvalid     : std_logic := '0';
  signal s_tready     : std_logic;
  signal s_tlast      : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  u_dut : entity radif.radif_axi4_axis_dma
    generic map (
      FIFO_DEPTH => 16,
      FIFO_FWFT => true
    )
    port map (
      clk => clk,
      rstn => rstn,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_din,
      reg_data_out => reg_dout,
      reg_wr_rdy => reg_wr_rdy,
      reg_rd_rdy => reg_rd_rdy,
      reg_wr_valid => reg_wr_valid,
      reg_rd_valid => reg_rd_valid,
      reg_error => reg_error,
      irq_o => irq,
      m_axi_awaddr => awaddr,
      m_axi_awlen => awlen,
      m_axi_awsize => awsize,
      m_axi_awburst => awburst,
      m_axi_awvalid => awvalid,
      m_axi_awready => awready,
      m_axi_wdata => wdata,
      m_axi_wstrb => wstrb,
      m_axi_wlast => wlast,
      m_axi_wvalid => wvalid,
      m_axi_wready => wready,
      m_axi_bresp => bresp,
      m_axi_bvalid => bvalid,
      m_axi_bready => bready,
      m_axi_araddr => araddr,
      m_axi_arlen => arlen,
      m_axi_arsize => arsize,
      m_axi_arburst => arburst,
      m_axi_arvalid => arvalid,
      m_axi_arready => arready,
      m_axi_rdata => rdata,
      m_axi_rresp => rresp,
      m_axi_rlast => rlast,
      m_axi_rvalid => rvalid,
      m_axi_rready => rready,
      m_axis_tdata => m_tdata,
      m_axis_tvalid => m_tvalid,
      m_axis_tready => m_tready,
      m_axis_tlast => m_tlast,
      s_axis_tdata => s_tdata,
      s_axis_tvalid => s_tvalid,
      s_axis_tready => s_tready,
      s_axis_tlast => s_tlast
    );

  process
    procedure reg_write(
      constant word_index : in natural;
      constant data       : in std_logic_vector(31 downto 0)
    ) is
    begin
      reg_wr_addr <= std_logic_vector(to_unsigned(word_index * 4, reg_wr_addr'length));
      reg_din <= data;
      reg_wr_en <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      assert reg_wr_valid = '1' and reg_error = '0' report "DMA register write failed" severity failure;
      reg_wr_en <= '0';
      wait until rising_edge(clk);
    end procedure;
  begin
    wait for 60 ns;
    rstn <= '1';
    wait until rising_edge(clk);

    reg_write(2, x"00000100");
    reg_write(4, x"00000108");
    reg_write(6, x"00000004");
    reg_write(0, x"00000001");

    for i in 0 to 40 loop
      exit when arvalid = '1';
      wait until rising_edge(clk);
    end loop;
    assert arvalid = '1' and araddr = x"00000100" report "MM2S read address failed" severity failure;

    wait until rising_edge(clk);
    for i in 0 to 40 loop
      exit when rready = '1';
      wait until rising_edge(clk);
    end loop;
    assert rready = '1' report "MM2S read data channel not ready" severity failure;
    rdata <= x"ABCDEF01";
    rvalid <= '1';
    wait until rising_edge(clk);
    rvalid <= '0';

    for i in 0 to 80 loop
      exit when m_tvalid = '1';
      wait until rising_edge(clk);
    end loop;
    assert m_tvalid = '1' and m_tdata = x"ABCDEF01" and m_tlast = '1' report "MM2S AXIS output failed" severity failure;
    wait until rising_edge(clk);

    reg_write(7, x"00000200");
    reg_write(9, x"00000208");
    reg_write(11, x"00000004");
    reg_write(0, x"00000100");

    for i in 0 to 40 loop
      exit when s_tready = '1';
      wait until rising_edge(clk);
    end loop;
    assert s_tready = '1' report "S2MM AXIS input not ready" severity failure;
    s_tdata <= x"12345678";
    s_tlast <= '1';
    s_tvalid <= '1';
    wait until rising_edge(clk);
    s_tvalid <= '0';
    s_tlast <= '0';

    for i in 0 to 80 loop
      exit when awvalid = '1' and wvalid = '1';
      wait until rising_edge(clk);
    end loop;
    assert awvalid = '1' and awaddr = x"00000200" report "S2MM write address failed" severity failure;
    assert wvalid = '1' and wdata = x"12345678" and wlast = '1' report "S2MM write data failed" severity failure;
    wait until rising_edge(clk);

    bvalid <= '1';
    wait until rising_edge(clk);
    bvalid <= '0';

    report "PASS tb_radif_axi4_axis_dma";
    std.env.finish;
    wait;
  end process;
end architecture;
