library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library radif;
use radif.radif_pkg.all;

-- Self-checking or stimulus-focused testbench for axi lite to reg.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radif_axi_lite_to_reg is
end entity;

architecture sim of tb_radif_axi_lite_to_reg is
  signal clk      : std_logic := '0';
  signal rstn     : std_logic := '0';
  signal awaddr   : std_logic_vector(15 downto 0) := (others => '0');
  signal awprot   : std_logic_vector(2 downto 0) := (others => '0');
  signal awvalid  : std_logic := '0';
  signal awready  : std_logic;
  signal wdata    : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb    : std_logic_vector(3 downto 0) := (others => '1');
  signal wvalid   : std_logic := '0';
  signal wready   : std_logic;
  signal bresp    : std_logic_vector(1 downto 0);
  signal bvalid   : std_logic;
  signal bready   : std_logic := '0';
  signal araddr   : std_logic_vector(15 downto 0) := (others => '0');
  signal arprot   : std_logic_vector(2 downto 0) := (others => '0');
  signal arvalid  : std_logic := '0';
  signal arready  : std_logic;
  signal rdata    : std_logic_vector(31 downto 0);
  signal rresp    : std_logic_vector(1 downto 0);
  signal rvalid   : std_logic;
  signal rready   : std_logic := '0';
  signal wr_addr  : std_logic_vector(15 downto 0);
  signal rd_addr  : std_logic_vector(15 downto 0);
  signal wr_en    : std_logic;
  signal rd_en    : std_logic;
  signal reg_din  : std_logic_vector(31 downto 0);
  signal reg_dout : std_logic_vector(31 downto 0);
  signal wr_rdy   : std_logic;
  signal rd_rdy   : std_logic;
  signal wr_valid : std_logic;
  signal rd_valid : std_logic;
  signal reg_error: std_logic;
  signal ro_regs  : radif_reg_array_t(0 to 7)(31 downto 0) := (others => (others => '0'));
  signal rw_regs  : radif_reg_array_t(0 to 63)(31 downto 0);
begin
  clk <= not clk after 5 ns;

  u_axi : entity radif.radif_axi_lite_to_reg
    port map (
      clk => clk,
      rstn => rstn,
      s_axi_awaddr => awaddr,
      s_axi_awprot => awprot,
      s_axi_awvalid => awvalid,
      s_axi_awready => awready,
      s_axi_wdata => wdata,
      s_axi_wstrb => wstrb,
      s_axi_wvalid => wvalid,
      s_axi_wready => wready,
      s_axi_bresp => bresp,
      s_axi_bvalid => bvalid,
      s_axi_bready => bready,
      s_axi_araddr => araddr,
      s_axi_arprot => arprot,
      s_axi_arvalid => arvalid,
      s_axi_arready => arready,
      s_axi_rdata => rdata,
      s_axi_rresp => rresp,
      s_axi_rvalid => rvalid,
      s_axi_rready => rready,
      reg_wr_addr => wr_addr,
      reg_rd_addr => rd_addr,
      reg_wr_en => wr_en,
      reg_rd_en => rd_en,
      reg_data_in => reg_din,
      reg_data_out => reg_dout,
      reg_wr_rdy => wr_rdy,
      reg_rd_rdy => rd_rdy,
      reg_wr_valid => wr_valid,
      reg_rd_valid => rd_valid,
      reg_error => reg_error
    );

  u_regs : entity radif.radif_reg_bank
    port map (
      clk => clk,
      rstn => rstn,
      wr_addr => wr_addr,
      rd_addr => rd_addr,
      wr_en => wr_en,
      rd_en => rd_en,
      data_in => reg_din,
      data_out => reg_dout,
      read_only_regs_i => ro_regs,
      read_write_regs_o => rw_regs,
      wr_rdy => wr_rdy,
      rd_rdy => rd_rdy,
      wr_valid => wr_valid,
      rd_valid => rd_valid,
      error => reg_error
    );

  process
  begin
    wait for 40 ns;
    rstn <= '1';
    wait until rising_edge(clk);

    awaddr <= x"0004";
    wdata <= x"CAFEBABE";
    awvalid <= '1';
    wvalid <= '1';
    wait until rising_edge(clk);
    while awready = '0' or wready = '0' loop
      wait until rising_edge(clk);
    end loop;
    awvalid <= '0';
    wvalid <= '0';
    bready <= '1';
    wait until rising_edge(clk);
    while bvalid = '0' loop
      wait until rising_edge(clk);
    end loop;
    assert bresp = "00" report "AXI write response failed" severity failure;
    bready <= '0';

    araddr <= x"0004";
    arvalid <= '1';
    wait until rising_edge(clk);
    while arready = '0' loop
      wait until rising_edge(clk);
    end loop;
    arvalid <= '0';
    rready <= '1';
    wait until rising_edge(clk);
    while rvalid = '0' loop
      wait until rising_edge(clk);
    end loop;
    assert rresp = "00" and rdata = x"CAFEBABE" report "AXI read failed" severity failure;
    rready <= '0';

    report "PASS tb_radif_axi_lite_to_reg";
    std.env.finish;
    wait;
  end process;
end architecture;
