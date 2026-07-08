library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library raddsp;

-- Self-checking or stimulus-focused testbench for axis fingerprint.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_fingerprint is
end entity;

architecture sim of tb_raddsp_axis_fingerprint is
  constant C_DATA_WIDTH : positive := 16;
  constant C_HASH_WIDTH : positive := 64;
  constant C_FP_WIDTH   : positive := C_HASH_WIDTH + 64;
  constant C_MATCH_WIDTH : positive := C_HASH_WIDTH + 32 + 32;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal fp_s_valid : std_logic := '0';
  signal fp_s_ready : std_logic;
  signal fp_s_data  : std_logic_vector((2 * C_DATA_WIDTH) - 1 downto 0) := (others => '0');
  signal fp_s_last  : std_logic := '0';
  signal fp_m_valid : std_logic;
  signal fp_m_ready : std_logic := '1';
  signal fp_m_data  : std_logic_vector(C_FP_WIDTH - 1 downto 0);
  signal fp_m_last  : std_logic;

  signal fp_awaddr  : std_logic_vector(7 downto 0) := (others => '0');
  signal fp_awvalid : std_logic := '0';
  signal fp_awready : std_logic;
  signal fp_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal fp_wvalid  : std_logic := '0';
  signal fp_wready  : std_logic;
  signal fp_bvalid  : std_logic;
  signal fp_bready  : std_logic := '1';
  signal fp_araddr  : std_logic_vector(7 downto 0) := (others => '0');
  signal fp_arvalid : std_logic := '0';
  signal fp_arready : std_logic;
  signal fp_rdata   : std_logic_vector(31 downto 0);
  signal fp_rvalid  : std_logic;
  signal fp_rready  : std_logic := '1';

  signal ma_s_valid : std_logic := '0';
  signal ma_s_ready : std_logic;
  signal ma_s_data  : std_logic_vector(C_FP_WIDTH - 1 downto 0) := (others => '0');
  signal ma_s_last  : std_logic := '0';
  signal ma_m_valid : std_logic;
  signal ma_m_ready : std_logic := '1';
  signal ma_m_data  : std_logic_vector(C_MATCH_WIDTH - 1 downto 0);
  signal ma_m_last  : std_logic;
  signal ma_irq     : std_logic;

  signal ma_awaddr  : std_logic_vector(7 downto 0) := (others => '0');
  signal ma_awvalid : std_logic := '0';
  signal ma_awready : std_logic;
  signal ma_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal ma_wvalid  : std_logic := '0';
  signal ma_wready  : std_logic;
  signal ma_bvalid  : std_logic;
  signal ma_bready  : std_logic := '1';
  signal ma_araddr  : std_logic_vector(7 downto 0) := (others => '0');
  signal ma_arvalid : std_logic := '0';
  signal ma_arready : std_logic;
  signal ma_rdata   : std_logic_vector(31 downto 0);
  signal ma_rvalid  : std_logic;
  signal ma_rready  : std_logic := '1';

  signal captured_fp : std_logic_vector(C_FP_WIDTH - 1 downto 0) := (others => '0');

  procedure axil_write(
    signal awaddr  : out std_logic_vector;
    signal awvalid : out std_logic;
    signal awready : in  std_logic;
    signal wdata   : out std_logic_vector;
    signal wvalid  : out std_logic;
    signal wready  : in  std_logic;
    signal bvalid  : in  std_logic;
    addr           : integer;
    data           : std_logic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk);
    awaddr <= std_logic_vector(to_unsigned(addr, awaddr'length));
    wdata <= data;
    awvalid <= '1';
    wvalid <= '1';
    wait until rising_edge(clk) and awready = '1' and wready = '1';
    awvalid <= '0';
    wvalid <= '0';
    wait until rising_edge(clk);
  end procedure;

  procedure send_fft_bin(
    signal valid : out std_logic;
    signal ready : in std_logic;
    signal data  : out std_logic_vector;
    signal last  : out std_logic;
    re_value : integer;
    im_value : integer;
    is_last  : std_logic
  ) is
  begin
    wait until rising_edge(clk);
    data <= std_logic_vector(to_signed(re_value, C_DATA_WIDTH)) &
            std_logic_vector(to_signed(im_value, C_DATA_WIDTH));
    last <= is_last;
    valid <= '1';
    wait until rising_edge(clk) and ready = '1';
    valid <= '0';
    last <= '0';
  end procedure;

begin
  clk <= not clk after 5 ns;

  fp_i: entity raddsp.raddsp_axis_fft_fingerprint
    generic map (
      VENDOR => "generic",
      FFT_DATA_WIDTH => C_DATA_WIDTH,
      HASH_WIDTH => C_HASH_WIDTH,
      DEFAULT_FRAME_BINS => 4
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => fp_s_valid,
      s_axis_tready => fp_s_ready,
      s_axis_tdata => fp_s_data,
      s_axis_tlast => fp_s_last,
      m_axis_tvalid => fp_m_valid,
      m_axis_tready => fp_m_ready,
      m_axis_tdata => fp_m_data,
      m_axis_tlast => fp_m_last,
      s_axi_awaddr => fp_awaddr,
      s_axi_awprot => "000",
      s_axi_awvalid => fp_awvalid,
      s_axi_awready => fp_awready,
      s_axi_wdata => fp_wdata,
      s_axi_wstrb => "1111",
      s_axi_wvalid => fp_wvalid,
      s_axi_wready => fp_wready,
      s_axi_bresp => open,
      s_axi_bvalid => fp_bvalid,
      s_axi_bready => fp_bready,
      s_axi_araddr => fp_araddr,
      s_axi_arprot => "000",
      s_axi_arvalid => fp_arvalid,
      s_axi_arready => fp_arready,
      s_axi_rdata => fp_rdata,
      s_axi_rresp => open,
      s_axi_rvalid => fp_rvalid,
      s_axi_rready => fp_rready
    );

  matcher_i: entity raddsp.raddsp_axis_fingerprint_matcher
    generic map (
      VENDOR => "generic",
      HASH_WIDTH => C_HASH_WIDTH,
      META_WIDTH => 32,
      TABLE_ADDR_WIDTH => 4
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => ma_s_valid,
      s_axis_tready => ma_s_ready,
      s_axis_tdata => ma_s_data,
      s_axis_tlast => ma_s_last,
      m_axis_tvalid => ma_m_valid,
      m_axis_tready => ma_m_ready,
      m_axis_tdata => ma_m_data,
      m_axis_tlast => ma_m_last,
      match_irq_o => ma_irq,
      s_axi_awaddr => ma_awaddr,
      s_axi_awprot => "000",
      s_axi_awvalid => ma_awvalid,
      s_axi_awready => ma_awready,
      s_axi_wdata => ma_wdata,
      s_axi_wstrb => "1111",
      s_axi_wvalid => ma_wvalid,
      s_axi_wready => ma_wready,
      s_axi_bresp => open,
      s_axi_bvalid => ma_bvalid,
      s_axi_bready => ma_bready,
      s_axi_araddr => ma_araddr,
      s_axi_arprot => "000",
      s_axi_arvalid => ma_arvalid,
      s_axi_arready => ma_arready,
      s_axi_rdata => ma_rdata,
      s_axi_rresp => open,
      s_axi_rvalid => ma_rvalid,
      s_axi_rready => ma_rready
    );

  stim: process
    variable hash_lo : std_logic_vector(31 downto 0);
    variable hash_hi : std_logic_vector(31 downto 0);
    variable bucket  : integer;
    variable captured_v : std_logic_vector(C_FP_WIDTH - 1 downto 0);
  begin
    wait for 100 ns;
    rst <= '0';

    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#04#, x"00000004");
    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#0C#, x"00000001");
    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#14#, x"12345678");
    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#18#, x"9ABCDEF0");
    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#00#, x"00000015");

    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 10, 1, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 3, -7, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 30, 2, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, -4, 5, '1');

    wait until rising_edge(clk) and fp_m_valid = '1';
    captured_v := fp_m_data;
    captured_fp <= fp_m_data;
    assert fp_m_last = '1' report "fingerprint tlast not asserted" severity failure;
    assert unsigned(captured_v(15 downto 0)) = 4 report "selected bin count mismatch" severity failure;
    assert unsigned(captured_v(63 downto 48)) = 2 report "peak bin mismatch" severity failure;
    assert unsigned(captured_v(47 downto 16)) = 32 report "peak magnitude mismatch" severity failure;

    hash_lo := captured_v(95 downto 64);
    hash_hi := captured_v(127 downto 96);
    bucket := to_integer(unsigned(hash_lo(3 downto 0)));

    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#04#, std_logic_vector(to_unsigned(bucket, 32)));
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#08#, hash_lo);
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#0C#, hash_hi);
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#10#, x"0000002A");
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#14#, x"00000001");
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#00#, x"00000003");

    wait until rising_edge(clk);
    ma_s_data <= captured_v;
    ma_s_last <= '1';
    ma_s_valid <= '1';
    wait until rising_edge(clk) and ma_s_ready = '1';
    ma_s_valid <= '0';
    ma_s_last <= '0';

    wait until rising_edge(clk) and ma_m_valid = '1';
    assert ma_irq = '1' report "matcher IRQ not asserted with IRQ enable" severity failure;
    assert ma_m_data(31 downto 0) = std_logic_vector(to_unsigned(bucket, 32)) report "matcher bucket mismatch" severity failure;
    assert ma_m_data(63 downto 32) = x"0000002A" report "matcher metadata mismatch" severity failure;

    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#00#, x"0000001E");
    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#38#, x"00000000");
    axil_write(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, 16#00#, x"0000001D");

    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 1, 1, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 2, 2, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 40, 3, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 5, 5, '1');
    wait for 80 ns;
    assert fp_m_valid = '0' report "pair fingerprint emitted before history was available" severity failure;

    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 3, 3, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 50, 1, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 2, 2, '0');
    send_fft_bin(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, 1, 1, '1');
    wait until rising_edge(clk) and fp_m_valid = '1';
    assert unsigned(fp_m_data(63 downto 48)) = 1 report "pair fingerprint delta mismatch" severity failure;
    assert unsigned(fp_m_data(47 downto 32)) = 1 report "pair fingerprint B peak bin mismatch" severity failure;
    assert unsigned(fp_m_data(31 downto 16)) = 2 report "pair fingerprint A peak bin mismatch" severity failure;

    report "PASS tb_raddsp_axis_fingerprint";
    finish;
  end process;
end architecture;
