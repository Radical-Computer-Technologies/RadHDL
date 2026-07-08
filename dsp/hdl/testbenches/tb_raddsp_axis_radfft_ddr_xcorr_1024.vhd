library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

library raddsp;

-- Self-checking or stimulus-focused testbench for axis radfft ddr xcorr 1024.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_radfft_ddr_xcorr_1024 is
end entity;

architecture sim of tb_raddsp_axis_radfft_ddr_xcorr_1024 is
  constant C_AXI_ADDR_WIDTH : positive := 32;
  constant C_AXI_DATA_WIDTH : positive := 64;
  constant C_AXI_BYTES      : positive := C_AXI_DATA_WIDTH / 8;
  constant C_POINTS         : positive := 1024;
  constant C_ADDR_A         : natural := 0;
  constant C_ADDR_B         : natural := 16#2000#;
  constant C_ADDR_SCRATCH   : natural := 16#4000#;
  constant C_ADDR_OUTPUT    : natural := 16#8000#;
  constant C_ADDR_TWIDDLE   : natural := 16#A000#;
  constant C_INDEX_A        : natural := C_ADDR_A / C_AXI_BYTES;
  constant C_INDEX_B        : natural := C_ADDR_B / C_AXI_BYTES;
  constant C_INDEX_SCRATCH  : natural := C_ADDR_SCRATCH / C_AXI_BYTES;
  constant C_INDEX_OUTPUT   : natural := C_ADDR_OUTPUT / C_AXI_BYTES;
  constant C_INDEX_TWIDDLE  : natural := C_ADDR_TWIDDLE / C_AXI_BYTES;

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

  type memory_t is array (0 to 8191) of std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
  signal mem : memory_t := (others => (others => '0'));
  signal tb_mem_we     : std_logic := '0';
  signal tb_mem_addr   : natural range 0 to 8191 := 0;
  signal tb_mem_data   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');

  impure function word_addr(addr : std_logic_vector) return natural is
  begin
    return to_integer(shift_right(unsigned(addr), 3)) mod mem'length;
  end function;

  function sample_word(re_value : integer; im_value : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_signed(re_value, 32)) & std_logic_vector(to_signed(im_value, 32));
  end function;

  function twiddle_word(re_value : integer; im_value : integer) return std_logic_vector is
  begin
    return x"00000000" & std_logic_vector(to_signed(re_value, 16)) & std_logic_vector(to_signed(im_value, 16));
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
      G_FIFO_DEPTH => 1024,
      G_FIFO_FWFT => true,
      G_MAX_BURST_BEATS => 64,
      G_FFT_POINTS => C_POINTS,
      G_FFT_RADIX => 2,
      G_FFT_INPUT_WIDTH => 32,
      G_FFT_TWIDDLE_WIDTH => 16,
      G_FFT_OUTPUT_WIDTH => 32,
      G_MAX_MULTIPLIER_LANES => 8,
      G_FFT_SCALE_EACH_STAGE => true,
      G_FFT_TWIDDLE_INIT_FILE => "../../mem/radfft_twiddle_1024_16_fft.mem"
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
    file fa : text open read_mode is "radfft_ddr_xcorr_1024_a_in.txt";
    file fb : text open read_mode is "radfft_ddr_xcorr_1024_b_in.txt";
    file ft : text open read_mode is "radfft_ddr_xcorr_1024_twiddles.txt";
    file fy : text open write_mode is "radfft_ddr_xcorr_1024_hdl.csv";
    variable l : line;
    variable re_value : integer;
    variable im_value : integer;
    variable rd : std_logic_vector(31 downto 0);
    variable xcorr_start_time : time;
    variable xcorr_stop_time : time;

    procedure axil_write(constant word_index : in natural; constant data : in std_logic_vector(31 downto 0)) is
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

    procedure axil_read(constant word_index : in natural; variable data : out std_logic_vector(31 downto 0)) is
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

    procedure mem_poke(constant index : in natural; constant data : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)) is
    begin
      tb_mem_addr <= index;
      tb_mem_data <= data;
      tb_mem_we <= '1';
      wait until rising_edge(clk);
      tb_mem_we <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure csv_row(file f : text; constant index : in natural; constant re_value : in integer; constant im_value : in integer) is
      variable row : line;
    begin
      write(row, index);
      write(row, string'(","));
      write(row, re_value);
      write(row, string'(","));
      write(row, im_value);
      writeline(f, row);
    end procedure;
  begin
    wait for 80 ns;
    rstn <= '1';
    wait until rising_edge(clk);

    for i in 0 to C_POINTS - 1 loop
      readline(fa, l);
      read(l, re_value);
      read(l, im_value);
      mem_poke(C_INDEX_A + i, sample_word(re_value, im_value));
    end loop;

    for i in 0 to C_POINTS - 1 loop
      readline(fb, l);
      read(l, re_value);
      read(l, im_value);
      mem_poke(C_INDEX_B + i, sample_word(re_value, im_value));
    end loop;

    for i in 0 to C_POINTS - 1 loop
      readline(ft, l);
      read(l, re_value);
      read(l, im_value);
      mem_poke(C_INDEX_TWIDDLE + i, twiddle_word(re_value, im_value));
    end loop;

    axil_write(0, x"80000000");
    axil_write(2, std_logic_vector(to_unsigned(C_ADDR_A, 32)));
    axil_write(4, std_logic_vector(to_unsigned(C_ADDR_OUTPUT, 32)));
    axil_write(6, x"00002000");
    axil_write(8, x"0000000A");
    axil_write(9, x"00000040");
    axil_write(12, std_logic_vector(to_unsigned(C_ADDR_TWIDDLE, 32)));
    axil_write(14, x"00002240");
    axil_write(22, std_logic_vector(to_unsigned(C_ADDR_B, 32)));
    axil_write(24, std_logic_vector(to_unsigned(C_ADDR_SCRATCH, 32)));
    xcorr_start_time := now;
    axil_write(0, x"00000121");

    for i in 0 to 200000 loop
      exit when irq = '1';
      wait until rising_edge(clk);
    end loop;
    xcorr_stop_time := now;
    axil_read(1, rd);
    assert rd(1) = '1' report "1024-point DDR FFT cross-correlation operation did not complete" severity failure;
    assert rd(2) = '0' report "1024-point DDR FFT cross-correlation operation reported error" severity failure;
    report "1024-point DDR FFT cross-correlation elapsed " & time'image(xcorr_stop_time - xcorr_start_time);

    write(l, string'("index,re,im"));
    writeline(fy, l);
    for i in 0 to C_POINTS - 1 loop
      csv_row(fy, i, high_i(mem(C_INDEX_OUTPUT + i)(63 downto 0)), low_i(mem(C_INDEX_OUTPUT + i)(63 downto 0)));
    end loop;

    report "PASS tb_raddsp_axis_radfft_ddr_xcorr_1024";
    finish;
  end process;
end architecture;
