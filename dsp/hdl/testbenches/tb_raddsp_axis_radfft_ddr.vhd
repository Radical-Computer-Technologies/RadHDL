library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

library raddsp;
use raddsp.raddsp_fft_twiddle_pkg.all;

-- Self-checking or stimulus-focused testbench for axis radfft ddr.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_radfft_ddr is
end entity;

architecture sim of tb_raddsp_axis_radfft_ddr is
  constant C_AXI_ADDR_WIDTH : positive := 32;
  constant C_AXI_DATA_WIDTH : positive := 64;
  constant C_AXI_BYTES      : positive := C_AXI_DATA_WIDTH / 8;

  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';

  signal s_axi_awaddr  : std_logic_vector(15 downto 0) := (others => '0');
  signal s_axi_awprot  : std_logic_vector(2 downto 0) := (others => '0');
  signal s_axi_awvalid : std_logic := '0';
  signal s_axi_awready : std_logic;
  signal s_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal s_axi_wstrb   : std_logic_vector(3 downto 0) := (others => '1');
  signal s_axi_wvalid  : std_logic := '0';
  signal s_axi_wready  : std_logic;
  signal s_axi_bresp   : std_logic_vector(1 downto 0);
  signal s_axi_bvalid  : std_logic;
  signal s_axi_bready  : std_logic := '0';
  signal s_axi_araddr  : std_logic_vector(15 downto 0) := (others => '0');
  signal s_axi_arprot  : std_logic_vector(2 downto 0) := (others => '0');
  signal s_axi_arvalid : std_logic := '0';
  signal s_axi_arready : std_logic;
  signal s_axi_rdata   : std_logic_vector(31 downto 0);
  signal s_axi_rresp   : std_logic_vector(1 downto 0);
  signal s_axi_rvalid  : std_logic;
  signal s_axi_rready  : std_logic := '0';

  signal m_axi_awaddr  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
  signal m_axi_awlen   : std_logic_vector(7 downto 0);
  signal m_axi_awsize  : std_logic_vector(2 downto 0);
  signal m_axi_awburst : std_logic_vector(1 downto 0);
  signal m_axi_awvalid : std_logic;
  signal m_axi_awready : std_logic := '0';
  signal m_axi_wdata   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
  signal m_axi_wstrb   : std_logic_vector(C_AXI_BYTES - 1 downto 0);
  signal m_axi_wlast   : std_logic;
  signal m_axi_wvalid  : std_logic;
  signal m_axi_wready  : std_logic := '0';
  signal m_axi_bresp   : std_logic_vector(1 downto 0) := "00";
  signal m_axi_bvalid  : std_logic := '0';
  signal m_axi_bready  : std_logic;
  signal m_axi_araddr  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
  signal m_axi_arlen   : std_logic_vector(7 downto 0);
  signal m_axi_arsize  : std_logic_vector(2 downto 0);
  signal m_axi_arburst : std_logic_vector(1 downto 0);
  signal m_axi_arvalid : std_logic;
  signal m_axi_arready : std_logic := '0';
  signal m_axi_rdata   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal m_axi_rresp   : std_logic_vector(1 downto 0) := "00";
  signal m_axi_rlast   : std_logic := '0';
  signal m_axi_rvalid  : std_logic := '0';
  signal m_axi_rready  : std_logic;

  signal s_axis_tdata  : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal s_axis_tvalid : std_logic := '0';
  signal s_axis_tready : std_logic;
  signal s_axis_tlast  : std_logic := '0';
  signal m_axis_tdata  : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal m_axis_tlast  : std_logic;
  signal irq           : std_logic;
  signal tb_mem_we     : std_logic := '0';
  signal tb_mem_addr   : natural range 0 to 255 := 0;
  signal tb_mem_data   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');

  type memory_t is array (0 to 255) of std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
  signal mem : memory_t := (others => (others => '0'));
  type sample_array_t is array (0 to 15) of integer;
  constant C_ZC_A_RE : sample_array_t := (16, 9, -11, -13, -16, 13, -11, -9, 16, -9, -11, 13, -16, -13, -11, 9);
  constant C_ZC_A_IM : sample_array_t := (0, -13, 11, -9, 0, 9, 11, 13, 0, 13, 11, 9, 0, -9, 11, -13);
  constant C_ZC_B_RE : sample_array_t := (-13, -11, 9, 16, 9, -11, -13, -16, 13, -11, -9, 16, -9, -11, 13, -16);
  constant C_ZC_B_IM : sample_array_t := (-9, 11, -13, 0, -13, 11, -9, 0, 9, 11, 13, 0, 13, 11, 9, 0);

  impure function word_addr(addr : std_logic_vector) return natural is
  begin
    return to_integer(shift_right(unsigned(addr), 3)) mod mem'length;
  end function;

  function twiddle_word(index : natural) return std_logic_vector is
    variable packed : std_logic_vector(31 downto 0);
  begin
    packed := std_logic_vector(to_signed(radfft_twiddle_re(16, index, 16), 16)) &
              std_logic_vector(to_signed(radfft_twiddle_im(16, index, 16, false), 16));
    return x"00000000" & packed;
  end function;

  function sample_word(re_value : integer; im_value : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(re_value, 32)) & std_logic_vector(to_signed(im_value, 32));
  end function;

  function high_i(value : std_logic_vector) return integer is
  begin
    return to_integer(signed(value(value'left downto value'length / 2)));
  end function;

  function low_i(value : std_logic_vector) return integer is
  begin
    return to_integer(signed(value((value'length / 2) - 1 downto 0)));
  end function;
begin
  clk <= not clk after 5 ns;

  u_dut : entity raddsp.raddsp_axis_radfft_ddr
    generic map (
      G_AXI_ADDR_WIDTH => C_AXI_ADDR_WIDTH,
      G_AXI_DATA_WIDTH => C_AXI_DATA_WIDTH,
      G_AXIS_DATA_WIDTH => C_AXI_DATA_WIDTH,
      G_FIFO_DEPTH => 32,
      G_FIFO_FWFT => true,
      G_MAX_BURST_BEATS => 4,
      G_FFT_POINTS => 16,
      G_FFT_RADIX => 2,
      G_FFT_INPUT_WIDTH => 32,
      G_FFT_TWIDDLE_WIDTH => 16,
      G_FFT_OUTPUT_WIDTH => 32,
      G_FFT_SCALE_EACH_STAGE => true,
      G_FFT_TWIDDLE_INIT_FILE => "../../mem/radfft_twiddle_16_16_fft.mem"
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
      irq_o => irq
    );

  axi_mem_write : process(clk)
    variable base_index : natural := 0;
    variable beat_index : natural := 0;
    variable burst_beats : natural := 0;
    variable active : boolean := false;
  begin
    if rising_edge(clk) then
      m_axi_awready <= '1';
      m_axi_wready <= '1';
      if rstn = '0' then
        m_axi_bvalid <= '0';
        active := false;
        beat_index := 0;
      else
        if tb_mem_we = '1' then
          mem(tb_mem_addr) <= tb_mem_data;
        end if;

        if m_axi_bvalid = '1' and m_axi_bready = '1' then
          m_axi_bvalid <= '0';
        end if;

        if m_axi_awvalid = '1' and m_axi_awready = '1' then
          assert m_axi_awburst = "01" report "AXI write burst is not INCR" severity failure;
          assert m_axi_awsize = "011" report "AXI write size is not 64 bit" severity failure;
          assert m_axi_awlen = x"03" or m_axi_awlen = x"00"
            report "AXI write did not use an expected burst length" severity failure;
          base_index := word_addr(m_axi_awaddr);
          burst_beats := to_integer(unsigned(m_axi_awlen)) + 1;
          beat_index := 0;
          active := true;
        end if;

        if active and m_axi_wvalid = '1' and m_axi_wready = '1' then
          mem((base_index + beat_index) mod mem'length) <= m_axi_wdata;
          if beat_index = burst_beats - 1 then
            assert m_axi_wlast = '1' report "AXI write burst missed WLAST" severity failure;
            active := false;
            m_axi_bvalid <= '1';
          else
            assert m_axi_wlast = '0' report "AXI write burst asserted WLAST early" severity failure;
            beat_index := beat_index + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  axi_mem_read : process(clk)
    variable base_index : natural := 0;
    variable beat_index : natural := 0;
    variable burst_beats : natural := 0;
    variable active : boolean := false;
  begin
    if rising_edge(clk) then
      m_axi_arready <= '1';
      if rstn = '0' then
        m_axi_rvalid <= '0';
        m_axi_rlast <= '0';
        active := false;
        beat_index := 0;
      else
        if m_axi_arvalid = '1' and m_axi_arready = '1' then
          assert m_axi_arburst = "01" report "AXI read burst is not INCR" severity failure;
          assert m_axi_arsize = "011" report "AXI read size is not 64 bit" severity failure;
          assert m_axi_arlen = x"03" or m_axi_arlen = x"00"
            report "AXI read did not use an expected burst length" severity failure;
          base_index := word_addr(m_axi_araddr);
          burst_beats := to_integer(unsigned(m_axi_arlen)) + 1;
          beat_index := 0;
          active := true;
          m_axi_rvalid <= '1';
          m_axi_rdata <= mem(base_index);
          m_axi_rlast <= '1' when burst_beats = 1 else '0';
        elsif active and m_axi_rvalid = '1' and m_axi_rready = '1' then
          if beat_index = burst_beats - 1 then
            m_axi_rvalid <= '0';
            m_axi_rlast <= '0';
            active := false;
          else
            beat_index := beat_index + 1;
            m_axi_rdata <= mem((base_index + beat_index) mod mem'length);
            m_axi_rlast <= '1' when beat_index = burst_beats - 1 else '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  stim : process
    variable rd : std_logic_vector(31 downto 0);
    file fa : text open write_mode is "radfft_ddr_xcorr_zc_a.csv";
    file fb : text open write_mode is "radfft_ddr_xcorr_zc_b.csv";
    file fy : text open write_mode is "radfft_ddr_xcorr_zc_hdl.csv";
    file fm_a : text open write_mode is "radfft_ddr_xcorr_zc_mem_a.csv";
    file fm_b : text open write_mode is "radfft_ddr_xcorr_zc_mem_b.csv";
    file fs_a : text open write_mode is "radfft_ddr_xcorr_zc_spectrum_a.csv";
    file fs_p : text open write_mode is "radfft_ddr_xcorr_zc_product.csv";
    variable row : line;

    procedure axil_write(
      constant word_index : in natural;
      constant data       : in std_logic_vector(31 downto 0)
    ) is
    begin
      s_axi_awaddr <= std_logic_vector(to_unsigned(word_index * 4, s_axi_awaddr'length));
      s_axi_wdata <= data;
      s_axi_awvalid <= '1';
      s_axi_wvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axi_awready = '1' and s_axi_wready = '1';
      end loop;
      s_axi_awvalid <= '0';
      s_axi_wvalid <= '0';
      s_axi_bready <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axi_bvalid = '1';
      end loop;
      assert s_axi_bresp = "00" report "AXI-Lite write failed" severity failure;
      s_axi_bready <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure axil_read(
      constant word_index : in natural;
      variable data       : out std_logic_vector(31 downto 0)
    ) is
    begin
      s_axi_araddr <= std_logic_vector(to_unsigned(word_index * 4, s_axi_araddr'length));
      s_axi_arvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axi_arready = '1';
      end loop;
      s_axi_arvalid <= '0';
      s_axi_rready <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axi_rvalid = '1';
      end loop;
      assert s_axi_rresp = "00" report "AXI-Lite read failed" severity failure;
      data := s_axi_rdata;
      s_axi_rready <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure axis_send(
      constant data : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
      constant last : in std_logic
    ) is
    begin
      s_axis_tdata <= data;
      s_axis_tlast <= last;
      s_axis_tvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when s_axis_tready = '1';
      end loop;
      s_axis_tvalid <= '0';
      s_axis_tlast <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure axis_expect(
      constant data : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
      constant last : in std_logic
    ) is
      variable seen : boolean := false;
    begin
      for i in 0 to 1200 loop
        wait until rising_edge(clk);
        if m_axis_tvalid = '1' then
          seen := true;
          exit;
        end if;
      end loop;
      assert seen report "DDR-to-AXIS output timed out" severity failure;
      assert m_axis_tdata = data report "DDR-to-AXIS data mismatch" severity failure;
      assert m_axis_tlast = last report "DDR-to-AXIS TLAST mismatch" severity failure;
    end procedure;

    procedure mem_poke(
      constant index : in natural;
      constant data  : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
    ) is
    begin
      tb_mem_addr <= index;
      tb_mem_data <= data;
      tb_mem_we <= '1';
      wait until rising_edge(clk);
      tb_mem_we <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure axis_send_zc_a is
      variable index : natural := 0;
    begin
      while index < 16 loop
        s_axis_tdata <= sample_word(C_ZC_A_RE(index), C_ZC_A_IM(index));
        s_axis_tlast <= '1' when index = 15 else '0';
        s_axis_tvalid <= '1';
        wait until rising_edge(clk);
        if s_axis_tready = '1' then
          index := index + 1;
        end if;
      end loop;
      s_axis_tvalid <= '0';
      s_axis_tlast <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure axis_send_zc_b is
      variable index : natural := 0;
    begin
      while index < 16 loop
        s_axis_tdata <= sample_word(C_ZC_B_RE(index), C_ZC_B_IM(index));
        s_axis_tlast <= '1' when index = 15 else '0';
        s_axis_tvalid <= '1';
        wait until rising_edge(clk);
        if s_axis_tready = '1' then
          index := index + 1;
        end if;
      end loop;
      s_axis_tvalid <= '0';
      s_axis_tlast <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure csv_header(file f : text) is
      variable l : line;
    begin
      write(l, string'("index,re,im"));
      writeline(f, l);
    end procedure;

    procedure csv_row(file f : text; constant index : in natural; constant re_value : in integer; constant im_value : in integer) is
      variable l : line;
    begin
      write(l, index);
      write(l, string'(","));
      write(l, re_value);
      write(l, string'(","));
      write(l, im_value);
      writeline(f, l);
    end procedure;
  begin
    wait for 80 ns;
    rstn <= '1';
    wait until rising_edge(clk);

    axil_write(2, x"00000100");
    axil_write(6, x"00000020");
    axil_write(9, x"00000004");
    axil_write(0, x"00000101");

    axis_send(x"0000000000001001", '0');
    axis_send(x"0000000000001002", '0');
    axis_send(x"0000000000001003", '0');
    axis_send(x"0000000000001004", '1');

    for i in 0 to 120 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "AXIS-to-DDR operation did not complete" severity failure;
    assert mem(32) = x"0000000000001001"
      report "DDR write word 0 mismatch: " & integer'image(to_integer(unsigned(mem(32)(15 downto 0)))) severity failure;
    assert mem(33) = x"0000000000001002"
      report "DDR write word 1 mismatch: " & integer'image(to_integer(unsigned(mem(33)(15 downto 0)))) severity failure;
    assert mem(34) = x"0000000000001003"
      report "DDR write word 2 mismatch: " & integer'image(to_integer(unsigned(mem(34)(15 downto 0)))) severity failure;
    assert mem(35) = x"0000000000001004"
      report "DDR write word 3 mismatch: " & integer'image(to_integer(unsigned(mem(35)(15 downto 0)))) severity failure;

    axil_write(0, x"80000000");
    axil_write(0, x"00000111");

    axis_expect(x"0000000000001001", '0');
    axis_expect(x"0000000000001002", '0');
    axis_expect(x"0000000000001003", '0');
    axis_expect(x"0000000000001004", '1');

    for i in 0 to 120 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "DDR-to-AXIS operation did not complete" severity failure;

    axil_write(0, x"80000000");
    axil_write(2, x"00000600");
    axil_write(6, x"00000080");
    axil_write(9, x"00000004");
    axil_write(0, x"00000101");

    for i in 0 to 14 loop
      axis_send(twiddle_word(i), '0');
    end loop;
    axis_send(twiddle_word(15), '1');

    for i in 0 to 240 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "FFT twiddle preload did not complete" severity failure;

    axil_write(0, x"80000000");
    axil_write(2, x"00000200");
    axil_write(6, x"00000080");
    axil_write(9, x"00000004");
    axil_write(0, x"00000101");

    axis_send(x"0000001000000000", '0');
    for i in 1 to 14 loop
      axis_send((others => '0'), '0');
    end loop;
    axis_send((others => '0'), '1');

    for i in 0 to 240 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "FFT input preload did not complete" severity failure;

    axil_write(0, x"80000000");
    axil_write(2, x"00000200");
    axil_write(4, x"00000400");
    axil_write(6, x"00000080");
    axil_write(8, x"00000004");
    axil_write(9, x"00000004");
    axil_write(12, x"00000600");
    axil_write(0, x"00000121");

    for i in 0 to 800 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "DDR FFT operation did not complete" severity failure;
    assert rd(2) = '0' report "DDR FFT operation reported error" severity failure;

    for i in 0 to 15 loop
      assert mem(128 + i) = x"0000000100000000"
        report "DDR FFT impulse output mismatch at " & integer'image(i) severity failure;
    end loop;

    axil_write(0, x"80000000");
    axil_write(6, x"00000080");
    axil_write(8, x"00000004");
    axil_write(9, x"00000004");
    axil_write(12, x"00000600");
    axil_write(14, x"00002230");
    axil_write(0, x"00000121");

    axis_send(x"0000001000000000", '0');
    for i in 1 to 14 loop
      axis_send((others => '0'), '0');
    end loop;
    axis_send((others => '0'), '1');

    for i in 0 to 14 loop
      axis_expect(x"0000000100000000", '0');
    end loop;
    axis_expect(x"0000000100000000", '1');

    for i in 0 to 800 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "AXIS FFT operation did not complete" severity failure;
    assert rd(2) = '0' report "AXIS FFT operation reported error" severity failure;

    axil_write(0, x"80000000");
    axil_write(6, x"00000080");
    axil_write(8, x"00000004");
    axil_write(9, x"00000004");
    axil_write(12, x"00000600");
    axil_write(14, x"00002231");
    axil_write(0, x"00000121");

    axis_send(x"0000001000000000", '0');
    for i in 1 to 14 loop
      axis_send((others => '0'), '0');
    end loop;
    axis_send((others => '0'), '1');

    for i in 0 to 14 loop
      axis_expect(x"0000000100000000", '0');
    end loop;
    axis_expect(x"0000000100000000", '1');

    for i in 0 to 800 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "AXIS radix-4 FFT operation did not complete" severity failure;
    assert rd(2) = '0' report "AXIS radix-4 FFT operation reported error" severity failure;

    csv_header(fa);
    csv_header(fb);
    csv_header(fy);
    csv_header(fm_a);
    csv_header(fm_b);
    csv_header(fs_a);
    csv_header(fs_p);

    axil_write(0, x"80000000");

    for i in 0 to 15 loop
      csv_row(fa, i, C_ZC_A_RE(i), C_ZC_A_IM(i));
      mem_poke(i, sample_word(C_ZC_A_RE(i), C_ZC_A_IM(i)));
    end loop;

    axil_write(0, x"80000000");

    for i in 0 to 15 loop
      csv_row(fb, i, C_ZC_B_RE(i), C_ZC_B_IM(i));
      mem_poke(16 + i, sample_word(C_ZC_B_RE(i), C_ZC_B_IM(i)));
    end loop;

    axil_write(0, x"80000000");
    axil_write(2, x"00000000");
    axil_write(4, x"00000200");
    axil_write(6, x"00000080");
    axil_write(8, x"00000004");
    axil_write(9, x"00000004");
    axil_write(12, x"00000600");
    axil_write(14, x"00002240");
    axil_write(22, x"00000080");
    axil_write(24, x"00000100");
    axil_write(0, x"00000121");

    for i in 0 to 2400 loop
      axil_read(1, rd);
      exit when rd(1) = '1';
      wait until rising_edge(clk);
    end loop;
    assert rd(1) = '1' report "DDR FFT cross-correlation operation did not complete" severity failure;
    assert rd(2) = '0' report "DDR FFT cross-correlation operation reported error" severity failure;
    for i in 0 to 15 loop
      csv_row(fm_a, i, high_i(mem(i)(63 downto 0)), low_i(mem(i)(63 downto 0)));
      csv_row(fm_b, i, high_i(mem(16 + i)(63 downto 0)), low_i(mem(16 + i)(63 downto 0)));
      csv_row(fs_a, i, high_i(mem(32 + i)(63 downto 0)), low_i(mem(32 + i)(63 downto 0)));
      csv_row(fs_p, i, high_i(mem(48 + i)(63 downto 0)), low_i(mem(48 + i)(63 downto 0)));
      csv_row(fy, i, high_i(mem(64 + i)(63 downto 0)), low_i(mem(64 + i)(63 downto 0)));
    end loop;

    report "PASS tb_raddsp_axis_radfft_ddr";
    finish;
  end process;
end architecture;
