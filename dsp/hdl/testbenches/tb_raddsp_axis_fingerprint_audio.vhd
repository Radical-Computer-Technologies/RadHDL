library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

library raddsp;

-- Self-checking or stimulus-focused testbench for axis fingerprint audio.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_fingerprint_audio is
end entity;

architecture sim of tb_raddsp_axis_fingerprint_audio is
  constant C_DATA_WIDTH  : positive := 16;
  constant C_HASH_WIDTH  : positive := 64;
  constant C_FP_WIDTH    : positive := C_HASH_WIDTH + 64;
  constant C_MATCH_WIDTH : positive := C_HASH_WIDTH + 32 + 32;
  constant C_MAX_IMPOSTORS : positive := 128;

  type integer_array_t is array (natural range <>) of integer;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal fp_s_valid : std_logic := '0';
  signal fp_s_ready : std_logic;
  signal fp_s_data  : std_logic_vector((2 * C_DATA_WIDTH) - 1 downto 0) := (others => '0');
  signal fp_s_last  : std_logic := '0';
  signal fp_m_valid : std_logic;
  signal fp_m_ready : std_logic;
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

  signal active_query : std_logic := '0';
  signal monitor_clear : std_logic := '0';
  signal match_count  : natural := 0;
  signal bad_match    : std_logic := '0';
  signal expected_track_id : integer := -1;

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

  procedure send_bin(
    signal valid : out std_logic;
    signal ready : in  std_logic;
    signal data  : out std_logic_vector;
    signal last  : out std_logic;
    re_value : integer;
    im_value : integer;
    is_last  : integer
  ) is
  begin
    wait until rising_edge(clk);
    data <= std_logic_vector(to_signed(re_value, C_DATA_WIDTH)) &
            std_logic_vector(to_signed(im_value, C_DATA_WIDTH));
    if is_last = 0 then
      last <= '0';
    else
      last <= '1';
    end if;
    valid <= '1';
    wait until rising_edge(clk) and ready = '1';
    valid <= '0';
    last <= '0';
  end procedure;

  procedure configure_fingerprinter(
    signal awaddr  : out std_logic_vector;
    signal awvalid : out std_logic;
    signal awready : in  std_logic;
    signal wdata   : out std_logic_vector;
    signal wvalid  : out std_logic;
    signal wready  : in  std_logic;
    signal bvalid  : in  std_logic;
    frame_bins : integer;
    pair_gap   : integer;
    seed_hi    : std_logic_vector(31 downto 0);
    seed_lo    : std_logic_vector(31 downto 0)
  ) is
  begin
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#04#, std_logic_vector(to_unsigned(frame_bins, 32)));
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#0C#, x"00000001");
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#14#, seed_lo);
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#18#, seed_hi);
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#38#, std_logic_vector(to_unsigned(pair_gap, 32)));
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#00#, x"0000001E");
    axil_write(awaddr, awvalid, awready, wdata, wvalid, wready, bvalid, 16#00#, x"0000001D");
  end procedure;

  procedure feed_query_file(
    signal valid : out std_logic;
    signal ready : in  std_logic;
    signal data  : out std_logic_vector;
    signal last  : out std_logic;
    file_name : string
  ) is
    file f : text;
    variable l : line;
    variable frames : integer;
    variable bins : integer;
    variable re_v : integer;
    variable im_v : integer;
    variable last_v : integer;
  begin
    file_open(f, file_name, read_mode);
    readline(f, l);
    read(l, frames);
    read(l, bins);
    for frame_i in 0 to frames - 1 loop
      for bin_i in 0 to bins - 1 loop
        readline(f, l);
        read(l, re_v);
        read(l, im_v);
        read(l, last_v);
        send_bin(valid, ready, data, last, re_v, im_v, last_v);
      end loop;
    end loop;
    file_close(f);
  end procedure;

begin
  clk <= not clk after 5 ns;

  fp_i: entity raddsp.raddsp_axis_fft_fingerprint
    generic map (
      VENDOR => "generic",
      FFT_DATA_WIDTH => C_DATA_WIDTH,
      HASH_WIDTH => C_HASH_WIDTH,
      DEFAULT_FRAME_BINS => 256
    )
    port map (
      clk => clk, rst => rst,
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
      TABLE_ADDR_WIDTH => 10
    )
    port map (
      clk => clk, rst => rst,
      s_axis_tvalid => fp_m_valid,
      s_axis_tready => fp_m_ready,
      s_axis_tdata => fp_m_data,
      s_axis_tlast => fp_m_last,
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

  monitor: process(clk)
    variable meta_v : unsigned(31 downto 0);
    variable track_v : integer;
  begin
    if rising_edge(clk) then
      if monitor_clear = '1' then
        match_count <= 0;
        bad_match <= '0';
      elsif active_query = '1' and ma_m_valid = '1' then
        match_count <= match_count + 1;
        meta_v := unsigned(ma_m_data(63 downto 32));
        track_v := to_integer(meta_v(31 downto 16));
        if expected_track_id >= 0 and track_v /= expected_track_id then
          bad_match <= '1';
        end if;
      end if;
    end if;
  end process;

  stim: process
    file cfg : text;
    file table_f : text;
    variable l : line;
    variable frame_bins : integer;
    variable table_addr_width : integer;
    variable pair_gap : integer;
    variable table_count : integer;
    variable match_frames : integer;
    variable impostor_frames : integer;
    variable expected_match : integer;
    variable expected_impostor : integer;
    variable impostor_count : integer;
    variable expected_impostors : integer_array_t(0 to C_MAX_IMPOSTORS - 1);
    variable observed_impostor_total : integer;
    variable seed_hi : std_logic_vector(31 downto 0);
    variable seed_lo : std_logic_vector(31 downto 0);
    variable bucket : integer;
    variable hash_hi : std_logic_vector(31 downto 0);
    variable hash_lo : std_logic_vector(31 downto 0);
    variable meta : std_logic_vector(31 downto 0);
  begin
    file_open(cfg, "vectors/config.txt", read_mode);
    readline(cfg, l);
    read(l, frame_bins);
    read(l, table_addr_width);
    read(l, pair_gap);
    read(l, table_count);
    read(l, match_frames);
    read(l, impostor_frames);
    read(l, expected_match);
    read(l, expected_impostor);
    read(l, impostor_count);
    readline(cfg, l);
    hread(l, seed_hi);
    hread(l, seed_lo);
    assert impostor_count <= C_MAX_IMPOSTORS report "too many impostors configured for TB" severity failure;
    for i in 0 to impostor_count - 1 loop
      readline(cfg, l);
      read(l, expected_impostors(i));
    end loop;
    file_close(cfg);

    assert table_addr_width = 10 report "audio fingerprint TB expects TABLE_ADDR_WIDTH=10" severity failure;

    wait for 100 ns;
    rst <= '0';

    configure_fingerprinter(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, frame_bins, pair_gap, seed_hi, seed_lo);
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#18#, x"FFFFFFFF");
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#1C#, x"FFFFFFFF");

    file_open(table_f, "vectors/table.txt", read_mode);
    for i in 0 to table_count - 1 loop
      readline(table_f, l);
      read(l, bucket);
      hread(l, hash_hi);
      hread(l, hash_lo);
      hread(l, meta);
      axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#04#, std_logic_vector(to_unsigned(bucket, 32)));
      axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#08#, hash_lo);
      axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#0C#, hash_hi);
      axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#10#, meta);
      axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#14#, x"00000001");
    end loop;
    file_close(table_f);
    axil_write(ma_awaddr, ma_awvalid, ma_awready, ma_wdata, ma_wvalid, ma_wready, ma_bvalid, 16#00#, x"00000003");

    monitor_clear <= '1';
    wait until rising_edge(clk);
    monitor_clear <= '0';
    expected_track_id <= 1;
    active_query <= '1';
    configure_fingerprinter(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, frame_bins, pair_gap, seed_hi, seed_lo);
    feed_query_file(fp_s_valid, fp_s_ready, fp_s_data, fp_s_last, "vectors/query_match_bins.txt");
    wait for 2000 ns;
    active_query <= '0';
    wait until rising_edge(clk);
    report "fingerprint matching query observed "
      & integer'image(match_count)
      & " matches, expected "
      & integer'image(expected_match);
    assert bad_match = '0' report "matching query returned a wrong track id" severity failure;
    assert match_count = expected_match report "matching query match count mismatch" severity failure;

    observed_impostor_total := 0;
    for i in 0 to impostor_count - 1 loop
      monitor_clear <= '1';
      wait until rising_edge(clk);
      monitor_clear <= '0';
      expected_track_id <= -1;
      active_query <= '1';
      configure_fingerprinter(fp_awaddr, fp_awvalid, fp_awready, fp_wdata, fp_wvalid, fp_wready, fp_bvalid, frame_bins, pair_gap, seed_hi, seed_lo);
      feed_query_file(
        fp_s_valid,
        fp_s_ready,
        fp_s_data,
        fp_s_last,
        "vectors/query_impostor_" & integer'image(i) & "_bins.txt"
      );
      wait for 2000 ns;
      active_query <= '0';
      wait until rising_edge(clk);
      observed_impostor_total := observed_impostor_total + match_count;
      report "fingerprint impostor query "
        & integer'image(i)
        & " observed "
        & integer'image(match_count)
        & " matches, expected "
        & integer'image(expected_impostors(i));
      assert match_count = expected_impostors(i) report "impostor query match count mismatch" severity failure;
    end loop;

    report "fingerprint impostor queries observed "
      & integer'image(observed_impostor_total)
      & " total matches, expected "
      & integer'image(expected_impostor);
    assert observed_impostor_total = expected_impostor report "impostor query total match count mismatch" severity failure;

    report "PASS tb_raddsp_axis_fingerprint_audio";
    finish;
  end process;
end architecture;
