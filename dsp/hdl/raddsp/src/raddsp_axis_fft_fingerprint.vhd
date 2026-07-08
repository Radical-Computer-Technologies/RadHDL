library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- AXI-stream spectral fingerprint extraction core.
-- Condenses FFT output into compact bin-energy features that can be compared against stored fingerprints.
entity raddsp_axis_fft_fingerprint is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR             : string := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY      : string := "generic";
    -- Sets the bit width for FFT DATA WIDTH values carried by this module.
    FFT_DATA_WIDTH     : positive := 16;
    -- Sets the bit width for HASH WIDTH values carried by this module.
    HASH_WIDTH         : positive := 64;
    -- Sets the bit width for BIN INDEX WIDTH values carried by this module.
    BIN_INDEX_WIDTH    : positive := 16;
    -- Sets the bit width for AXI ADDR WIDTH values carried by this module.
    AXI_ADDR_WIDTH     : positive := 8;
    -- Sets the bit width for AXI DATA WIDTH values carried by this module.
    AXI_DATA_WIDTH     : positive := 32;
    -- Configures DEFAULT FRAME BINS for this instance.
    DEFAULT_FRAME_BINS : positive := 1024
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst           : in  std_logic;

    -- Input AXI-stream valid qualifier for the current sample beat.
    s_axis_tvalid : in  std_logic;
    -- Input AXI-stream ready response indicating this block can accept a beat.
    s_axis_tready : out std_logic;
    -- Input AXI-stream payload containing packed sample or feature lanes.
    s_axis_tdata  : in  std_logic_vector((2 * FFT_DATA_WIDTH) - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;

    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector(HASH_WIDTH + 64 - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic;

    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awaddr  : in  std_logic_vector(AXI_ADDR_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awprot  : in  std_logic_vector(2 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awvalid : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awready : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wdata   : in  std_logic_vector(AXI_DATA_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wstrb   : in  std_logic_vector((AXI_DATA_WIDTH / 8) - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wvalid  : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wready  : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bvalid  : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bready  : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_araddr  : in  std_logic_vector(AXI_ADDR_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arprot  : in  std_logic_vector(2 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arvalid : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arready : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rdata   : out std_logic_vector(AXI_DATA_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rvalid  : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rready  : in  std_logic
  );
end entity;

architecture rtl of raddsp_axis_fft_fingerprint is
  constant C_REG_CTRL          : natural := 16#00#;
  constant C_REG_FRAME_BINS    : natural := 16#04#;
  constant C_REG_BIN_OFFSET    : natural := 16#08#;
  constant C_REG_BIN_STRIDE    : natural := 16#0C#;
  constant C_REG_MAG_SHIFT     : natural := 16#10#;
  constant C_REG_HASH_SEED_LO  : natural := 16#14#;
  constant C_REG_HASH_SEED_HI  : natural := 16#18#;
  constant C_REG_STATUS        : natural := 16#1C#;
  constant C_REG_LAST_HASH_LO  : natural := 16#20#;
  constant C_REG_LAST_HASH_HI  : natural := 16#24#;
  constant C_REG_LAST_PEAK_BIN : natural := 16#28#;
  constant C_REG_LAST_PEAK_MAG : natural := 16#2C#;
  constant C_REG_LAST_SELECTED : natural := 16#30#;
  constant C_REG_FRAME_COUNT   : natural := 16#34#;
  constant C_REG_PAIR_GAP      : natural := 16#38#;
  constant C_REG_LAST_DELTA    : natural := 16#3C#;

  constant C_MAG_WIDTH : positive := (2 * FFT_DATA_WIDTH) + 1;
  type peak_bin_array_t is array (0 to 3) of unsigned(15 downto 0);
  type peak_mag_array_t is array (0 to 3) of unsigned(31 downto 0);
  type peak_bin_history_t is array (0 to 15) of peak_bin_array_t;
  type peak_mag_history_t is array (0 to 15) of peak_mag_array_t;
  type pair_state_t is (PAIR_CAPTURE_A, PAIR_WAIT_GAP, PAIR_CAPTURE_B);

  signal enable_r       : std_logic := '0';
  signal use_tlast_r    : std_logic := '1';
  signal pair_mode_r    : std_logic := '0';
  signal magnitude_only_r : std_logic := '1';
  signal frame_bins_r   : unsigned(BIN_INDEX_WIDTH - 1 downto 0) := to_unsigned(DEFAULT_FRAME_BINS, BIN_INDEX_WIDTH);
  signal bin_offset_r   : unsigned(BIN_INDEX_WIDTH - 1 downto 0) := (others => '0');
  signal bin_stride_r   : unsigned(BIN_INDEX_WIDTH - 1 downto 0) := to_unsigned(1, BIN_INDEX_WIDTH);
  signal mag_shift_r    : unsigned(4 downto 0) := (others => '0');
  signal hash_seed_r    : unsigned(HASH_WIDTH - 1 downto 0) := (others => '0');
  signal pair_gap_r     : unsigned(15 downto 0) := (others => '0');

  signal hash_r         : unsigned(HASH_WIDTH - 1 downto 0) := (others => '0');
  signal bin_idx_r      : unsigned(BIN_INDEX_WIDTH - 1 downto 0) := (others => '0');
  signal stride_count_r : unsigned(BIN_INDEX_WIDTH - 1 downto 0) := (others => '0');
  signal selected_r     : unsigned(15 downto 0) := (others => '0');
  signal peak_bin_r     : unsigned(15 downto 0) := (others => '0');
  signal peak_mag_r     : unsigned(31 downto 0) := (others => '0');
  signal frame_count_r  : unsigned(31 downto 0) := (others => '0');
  signal pair_state_r   : pair_state_t := PAIR_CAPTURE_A;
  signal pair_wait_r    : unsigned(15 downto 0) := (others => '0');
  signal pair_delta_r   : unsigned(15 downto 0) := (others => '0');
  signal cur_peak_bin_r : peak_bin_array_t := (others => (others => '0'));
  signal cur_peak_mag_r : peak_mag_array_t := (others => (others => '0'));
  signal cur_peak_feat_r : peak_mag_array_t := (others => (others => '0'));
  signal a_peak_bin_r   : peak_bin_array_t := (others => (others => '0'));
  signal a_peak_mag_r   : peak_mag_array_t := (others => (others => '0'));
  signal b_peak_bin_r   : peak_bin_array_t := (others => (others => '0'));
  signal b_peak_mag_r   : peak_mag_array_t := (others => (others => '0'));
  signal hist_peak_bin_r : peak_bin_history_t := (others => (others => (others => '0')));
  signal hist_peak_mag_r : peak_mag_history_t := (others => (others => (others => '0')));
  signal hist_peak_feat_r : peak_mag_history_t := (others => (others => (others => '0')));

  signal last_hash_r    : unsigned(HASH_WIDTH - 1 downto 0) := (others => '0');
  signal last_peak_bin_r : unsigned(15 downto 0) := (others => '0');
  signal last_peak_mag_r : unsigned(31 downto 0) := (others => '0');
  signal last_selected_r : unsigned(15 downto 0) := (others => '0');
  signal last_delta_r    : unsigned(15 downto 0) := (others => '0');

  signal out_valid_r    : std_logic := '0';
  signal out_data_r     : std_logic_vector(HASH_WIDTH + 64 - 1 downto 0) := (others => '0');
  signal busy_r         : std_logic := '0';

  signal awready_r      : std_logic := '0';
  signal wready_r       : std_logic := '0';
  signal bvalid_r       : std_logic := '0';
  signal arready_r      : std_logic := '0';
  signal rvalid_r       : std_logic := '0';
  signal rdata_r        : std_logic_vector(AXI_DATA_WIDTH - 1 downto 0) := (others => '0');

  function axi_word_addr(addr : std_logic_vector) return natural is
    variable a : unsigned(addr'length - 1 downto 0) := unsigned(addr);
  begin
    return to_integer(a(a'high downto 2) & "00");
  end function;

  function abs_signed_to_unsigned(value : signed) return unsigned is
    variable v : signed(value'length - 1 downto 0) := value;
  begin
    if v(v'high) = '1' then
      return unsigned(-v);
    end if;
    return unsigned(v);
  end function;

  function rol_hash(value : unsigned; count : natural) return unsigned is
    variable result : unsigned(value'length - 1 downto 0);
    variable idx    : natural;
  begin
    for i in 0 to value'length - 1 loop
      idx := (i + value'length - (count mod value'length)) mod value'length;
      result(i) := value(idx);
    end loop;
    return result;
  end function;

  function hash_mix(
    old_hash : unsigned;
    bin_idx  : unsigned;
    mag      : unsigned
  ) return unsigned is
    variable mixed : unsigned(old_hash'length - 1 downto 0);
    variable word  : unsigned(old_hash'length - 1 downto 0) := (others => '0');
  begin
    word(mag'length - 1 downto 0) := mag;
    if old_hash'length > bin_idx'length + 16 then
      word(bin_idx'length + 15 downto 16) := bin_idx;
    else
      word(old_hash'length - 1 downto 16) := resize(bin_idx, old_hash'length - 16);
    end if;
    mixed := rol_hash(old_hash, 5) xor word xor rol_hash(word, 17);
    return mixed + resize(unsigned'(x"9E3779B9"), old_hash'length);
  end function;

  function fold_peak_hash(
    seed : unsigned;
    bins : peak_bin_array_t;
    mags : peak_mag_array_t;
    tag  : unsigned
  ) return unsigned is
    variable h : unsigned(seed'length - 1 downto 0) := seed;
  begin
    h := hash_mix(h, resize(tag, BIN_INDEX_WIDTH), resize(tag, 32));
    for i in 0 to 3 loop
      h := hash_mix(h, resize(bins(i), BIN_INDEX_WIDTH), mags(i));
    end loop;
    return h;
  end function;

  function low_word(value : unsigned) return std_logic_vector is
    variable result : std_logic_vector(31 downto 0) := (others => '0');
  begin
    if value'length >= 32 then
      result := std_logic_vector(value(31 downto 0));
    else
      result(value'length - 1 downto 0) := std_logic_vector(value);
    end if;
    return result;
  end function;

  function high_word(value : unsigned) return std_logic_vector is
    variable result : std_logic_vector(31 downto 0) := (others => '0');
  begin
    if value'length > 32 then
      if value'length >= 64 then
        result := std_logic_vector(value(63 downto 32));
      else
        result(value'length - 33 downto 0) := std_logic_vector(value(value'length - 1 downto 32));
      end if;
    end if;
    return result;
  end function;

begin
  assert HASH_WIDTH = 32 or HASH_WIDTH = 64
    report "raddsp_axis_fft_fingerprint HASH_WIDTH must be 32 or 64"
    severity failure;
  assert AXI_DATA_WIDTH = 32
    report "raddsp_axis_fft_fingerprint currently supports 32-bit AXI-Lite data"
    severity failure;

  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
  begin
  end generate;

  s_axis_tready <= '1' when enable_r = '1' and out_valid_r = '0' else '0';
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_valid_r;

  s_axi_awready <= awready_r;
  s_axi_wready <= wready_r;
  s_axi_bresp <= "00";
  s_axi_bvalid <= bvalid_r;
  s_axi_arready <= arready_r;
  s_axi_rdata <= rdata_r;
  s_axi_rresp <= "00";
  s_axi_rvalid <= rvalid_r;

  process(clk)
    variable wr_addr     : natural;
    variable rd_addr     : natural;
    variable i_v         : signed(FFT_DATA_WIDTH - 1 downto 0);
    variable q_v         : signed(FFT_DATA_WIDTH - 1 downto 0);
    variable mag_v       : unsigned(C_MAG_WIDTH - 1 downto 0);
    variable mag_shifted : unsigned(C_MAG_WIDTH - 1 downto 0);
    variable mag32_v     : unsigned(31 downto 0);
    variable feature32_v : unsigned(31 downto 0);
    variable i16_v       : signed(15 downto 0);
    variable q16_v       : signed(15 downto 0);
    variable sample_end  : boolean;
    variable selected_v  : boolean;
    variable next_hash   : unsigned(HASH_WIDTH - 1 downto 0);
    variable next_sel    : unsigned(15 downto 0);
    variable next_peak_bin : unsigned(15 downto 0);
    variable next_peak_mag : unsigned(31 downto 0);
    variable next_cur_bins : peak_bin_array_t;
    variable next_cur_mags : peak_mag_array_t;
    variable next_cur_feats : peak_mag_array_t;
    variable hash_final_v  : unsigned(HASH_WIDTH - 1 downto 0);
    variable pair_hash_v   : unsigned(HASH_WIDTH - 1 downto 0);
    variable zero_tag_v    : unsigned(15 downto 0);
    variable one_tag_v     : unsigned(15 downto 0);
    variable two_tag_v     : unsigned(15 downto 0);
    variable gap_idx_v     : natural;
    variable delta_v       : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      awready_r <= '0';
      wready_r <= '0';
      arready_r <= '0';

      if rst = '1' then
        enable_r <= '0';
        use_tlast_r <= '1';
        pair_mode_r <= '0';
        magnitude_only_r <= '1';
        frame_bins_r <= to_unsigned(DEFAULT_FRAME_BINS, BIN_INDEX_WIDTH);
        bin_offset_r <= (others => '0');
        bin_stride_r <= to_unsigned(1, BIN_INDEX_WIDTH);
        mag_shift_r <= (others => '0');
        hash_seed_r <= (others => '0');
        hash_r <= (others => '0');
        bin_idx_r <= (others => '0');
        stride_count_r <= (others => '0');
        selected_r <= (others => '0');
        peak_bin_r <= (others => '0');
        peak_mag_r <= (others => '0');
        frame_count_r <= (others => '0');
        pair_gap_r <= (others => '0');
        pair_state_r <= PAIR_CAPTURE_A;
        pair_wait_r <= (others => '0');
        pair_delta_r <= (others => '0');
        cur_peak_bin_r <= (others => (others => '0'));
        cur_peak_mag_r <= (others => (others => '0'));
        cur_peak_feat_r <= (others => (others => '0'));
        a_peak_bin_r <= (others => (others => '0'));
        a_peak_mag_r <= (others => (others => '0'));
        b_peak_bin_r <= (others => (others => '0'));
        b_peak_mag_r <= (others => (others => '0'));
        hist_peak_bin_r <= (others => (others => (others => '0')));
        hist_peak_mag_r <= (others => (others => (others => '0')));
        hist_peak_feat_r <= (others => (others => (others => '0')));
        last_hash_r <= (others => '0');
        last_peak_bin_r <= (others => '0');
        last_peak_mag_r <= (others => '0');
        last_selected_r <= (others => '0');
        last_delta_r <= (others => '0');
        out_valid_r <= '0';
        out_data_r <= (others => '0');
        busy_r <= '0';
        bvalid_r <= '0';
        rvalid_r <= '0';
        rdata_r <= (others => '0');
      else
        if bvalid_r = '1' and s_axi_bready = '1' then
          bvalid_r <= '0';
        end if;
        if rvalid_r = '1' and s_axi_rready = '1' then
          rvalid_r <= '0';
        end if;

        if s_axi_awvalid = '1' and s_axi_wvalid = '1' and bvalid_r = '0' then
          awready_r <= '1';
          wready_r <= '1';
          bvalid_r <= '1';
          wr_addr := axi_word_addr(s_axi_awaddr);
          case wr_addr is
            when C_REG_CTRL =>
              enable_r <= s_axi_wdata(0);
              use_tlast_r <= s_axi_wdata(2);
              pair_mode_r <= s_axi_wdata(3);
              magnitude_only_r <= s_axi_wdata(4);
              if s_axi_wdata(1) = '1' then
                hash_r <= hash_seed_r;
                bin_idx_r <= (others => '0');
                stride_count_r <= (others => '0');
                selected_r <= (others => '0');
                peak_bin_r <= (others => '0');
                peak_mag_r <= (others => '0');
                pair_state_r <= PAIR_CAPTURE_A;
                pair_wait_r <= (others => '0');
                pair_delta_r <= (others => '0');
                cur_peak_bin_r <= (others => (others => '0'));
                cur_peak_mag_r <= (others => (others => '0'));
                cur_peak_feat_r <= (others => (others => '0'));
                a_peak_bin_r <= (others => (others => '0'));
                a_peak_mag_r <= (others => (others => '0'));
                b_peak_bin_r <= (others => (others => '0'));
                b_peak_mag_r <= (others => (others => '0'));
                hist_peak_bin_r <= (others => (others => (others => '0')));
                hist_peak_mag_r <= (others => (others => (others => '0')));
                hist_peak_feat_r <= (others => (others => (others => '0')));
                out_valid_r <= '0';
                busy_r <= '0';
              end if;
            when C_REG_FRAME_BINS =>
              frame_bins_r <= resize(unsigned(s_axi_wdata), BIN_INDEX_WIDTH);
            when C_REG_BIN_OFFSET =>
              bin_offset_r <= resize(unsigned(s_axi_wdata), BIN_INDEX_WIDTH);
            when C_REG_BIN_STRIDE =>
              if unsigned(s_axi_wdata) = 0 then
                bin_stride_r <= to_unsigned(1, BIN_INDEX_WIDTH);
              else
                bin_stride_r <= resize(unsigned(s_axi_wdata), BIN_INDEX_WIDTH);
              end if;
            when C_REG_MAG_SHIFT =>
              mag_shift_r <= unsigned(s_axi_wdata(4 downto 0));
            when C_REG_HASH_SEED_LO =>
              hash_seed_r(31 downto 0) <= unsigned(s_axi_wdata);
              if hash_r = 0 then
                hash_r(31 downto 0) <= unsigned(s_axi_wdata);
              end if;
            when C_REG_HASH_SEED_HI =>
              if HASH_WIDTH > 32 then
                hash_seed_r(HASH_WIDTH - 1 downto 32) <= resize(unsigned(s_axi_wdata), HASH_WIDTH - 32);
                if hash_r = 0 then
                  hash_r(HASH_WIDTH - 1 downto 32) <= resize(unsigned(s_axi_wdata), HASH_WIDTH - 32);
                end if;
              end if;
            when C_REG_PAIR_GAP =>
              pair_gap_r <= unsigned(s_axi_wdata(15 downto 0));
            when others =>
              null;
          end case;
        end if;

        if s_axi_arvalid = '1' and rvalid_r = '0' then
          arready_r <= '1';
          rd_addr := axi_word_addr(s_axi_araddr);
          rdata_r <= (others => '0');
          case rd_addr is
            when C_REG_CTRL =>
              rdata_r(0) <= enable_r;
              rdata_r(2) <= use_tlast_r;
              rdata_r(3) <= pair_mode_r;
              rdata_r(4) <= magnitude_only_r;
            when C_REG_FRAME_BINS =>
              rdata_r <= low_word(frame_bins_r);
            when C_REG_BIN_OFFSET =>
              rdata_r <= low_word(bin_offset_r);
            when C_REG_BIN_STRIDE =>
              rdata_r <= low_word(bin_stride_r);
            when C_REG_MAG_SHIFT =>
              rdata_r(4 downto 0) <= std_logic_vector(mag_shift_r);
            when C_REG_HASH_SEED_LO =>
              rdata_r <= low_word(hash_seed_r);
            when C_REG_HASH_SEED_HI =>
              rdata_r <= high_word(hash_seed_r);
            when C_REG_STATUS =>
              rdata_r(0) <= busy_r;
              rdata_r(1) <= out_valid_r;
            when C_REG_LAST_HASH_LO =>
              rdata_r <= low_word(last_hash_r);
            when C_REG_LAST_HASH_HI =>
              rdata_r <= high_word(last_hash_r);
            when C_REG_LAST_PEAK_BIN =>
              rdata_r(15 downto 0) <= std_logic_vector(last_peak_bin_r);
            when C_REG_LAST_PEAK_MAG =>
              rdata_r <= std_logic_vector(last_peak_mag_r);
            when C_REG_LAST_SELECTED =>
              rdata_r(15 downto 0) <= std_logic_vector(last_selected_r);
            when C_REG_FRAME_COUNT =>
              rdata_r <= std_logic_vector(frame_count_r);
            when C_REG_PAIR_GAP =>
              rdata_r(15 downto 0) <= std_logic_vector(pair_gap_r);
            when C_REG_LAST_DELTA =>
              rdata_r(15 downto 0) <= std_logic_vector(last_delta_r);
            when others =>
              null;
          end case;
          rvalid_r <= '1';
        end if;

        if out_valid_r = '1' and m_axis_tready = '1' then
          out_valid_r <= '0';
        end if;

        if enable_r = '1' and out_valid_r = '0' and s_axis_tvalid = '1' then
          busy_r <= '1';
          i_v := signed(s_axis_tdata((2 * FFT_DATA_WIDTH) - 1 downto FFT_DATA_WIDTH));
          q_v := signed(s_axis_tdata(FFT_DATA_WIDTH - 1 downto 0));
          mag_v := resize(abs_signed_to_unsigned(i_v), C_MAG_WIDTH) +
                   resize(abs_signed_to_unsigned(q_v), C_MAG_WIDTH);
          mag_shifted := shift_right(mag_v, to_integer(mag_shift_r));
          mag32_v := resize(mag_shifted, 32);
          i16_v := resize(i_v, 16);
          q16_v := resize(q_v, 16);
          if magnitude_only_r = '1' then
            feature32_v := mag32_v;
          else
            feature32_v := unsigned(std_logic_vector(i16_v) & std_logic_vector(q16_v));
          end if;

          selected_v := false;
          if bin_idx_r >= bin_offset_r then
            if stride_count_r = 0 then
              selected_v := true;
            end if;
          end if;

          next_hash := hash_r;
          next_sel := selected_r;
          next_peak_bin := peak_bin_r;
          next_peak_mag := peak_mag_r;
          next_cur_bins := cur_peak_bin_r;
          next_cur_mags := cur_peak_mag_r;
          next_cur_feats := cur_peak_feat_r;
          zero_tag_v := (others => '0');
          one_tag_v := to_unsigned(1, 16);
          two_tag_v := to_unsigned(2, 16);
          if selected_v then
            next_hash := hash_mix(hash_r, bin_idx_r, feature32_v);
            next_sel := selected_r + 1;
            if mag32_v > peak_mag_r then
              next_peak_mag := mag32_v;
              next_peak_bin := resize(bin_idx_r, 16);
            end if;
            if mag32_v > next_cur_mags(0) then
              next_cur_mags(3) := next_cur_mags(2);
              next_cur_bins(3) := next_cur_bins(2);
              next_cur_mags(2) := next_cur_mags(1);
              next_cur_bins(2) := next_cur_bins(1);
              next_cur_mags(1) := next_cur_mags(0);
              next_cur_bins(1) := next_cur_bins(0);
              next_cur_feats(3) := next_cur_feats(2);
              next_cur_feats(2) := next_cur_feats(1);
              next_cur_feats(1) := next_cur_feats(0);
              next_cur_mags(0) := mag32_v;
              next_cur_bins(0) := resize(bin_idx_r, 16);
              next_cur_feats(0) := feature32_v;
            elsif mag32_v > next_cur_mags(1) then
              next_cur_mags(3) := next_cur_mags(2);
              next_cur_bins(3) := next_cur_bins(2);
              next_cur_mags(2) := next_cur_mags(1);
              next_cur_bins(2) := next_cur_bins(1);
              next_cur_feats(3) := next_cur_feats(2);
              next_cur_feats(2) := next_cur_feats(1);
              next_cur_mags(1) := mag32_v;
              next_cur_bins(1) := resize(bin_idx_r, 16);
              next_cur_feats(1) := feature32_v;
            elsif mag32_v > next_cur_mags(2) then
              next_cur_mags(3) := next_cur_mags(2);
              next_cur_bins(3) := next_cur_bins(2);
              next_cur_feats(3) := next_cur_feats(2);
              next_cur_mags(2) := mag32_v;
              next_cur_bins(2) := resize(bin_idx_r, 16);
              next_cur_feats(2) := feature32_v;
            elsif mag32_v > next_cur_mags(3) then
              next_cur_mags(3) := mag32_v;
              next_cur_bins(3) := resize(bin_idx_r, 16);
              next_cur_feats(3) := feature32_v;
            end if;
          end if;

          hash_r <= next_hash;
          selected_r <= next_sel;
          peak_bin_r <= next_peak_bin;
          peak_mag_r <= next_peak_mag;
          cur_peak_bin_r <= next_cur_bins;
          cur_peak_mag_r <= next_cur_mags;
          cur_peak_feat_r <= next_cur_feats;

          if bin_idx_r >= bin_offset_r then
            if stride_count_r = 0 then
              if bin_stride_r <= 1 then
                stride_count_r <= (others => '0');
              else
                stride_count_r <= bin_stride_r - 1;
              end if;
            else
              stride_count_r <= stride_count_r - 1;
            end if;
          end if;

          sample_end := false;
          if use_tlast_r = '1' and s_axis_tlast = '1' then
            sample_end := true;
          elsif use_tlast_r = '0' and (bin_idx_r + 1) >= frame_bins_r then
            sample_end := true;
          end if;

          if sample_end then
            last_peak_bin_r <= next_peak_bin;
            last_peak_mag_r <= next_peak_mag;
            last_selected_r <= next_sel;
            frame_count_r <= frame_count_r + 1;
            if pair_mode_r = '0' then
              hash_final_v := fold_peak_hash(hash_seed_r, next_cur_bins, next_cur_feats, zero_tag_v);
              last_hash_r <= hash_final_v;
              last_delta_r <= (others => '0');
              out_data_r <= std_logic_vector(hash_final_v) &
                            std_logic_vector(next_peak_bin) &
                            std_logic_vector(next_peak_mag) &
                            std_logic_vector(next_sel);
              out_valid_r <= '1';
            else
              if pair_gap_r > 15 then
                gap_idx_v := 15;
              else
                gap_idx_v := to_integer(pair_gap_r);
              end if;
              delta_v := to_unsigned(gap_idx_v + 1, 16);
              if frame_count_r > resize(pair_gap_r, frame_count_r'length) then
                pair_hash_v := fold_peak_hash(hash_seed_r, hist_peak_bin_r(gap_idx_v), hist_peak_feat_r(gap_idx_v), one_tag_v);
                pair_hash_v := fold_peak_hash(pair_hash_v, next_cur_bins, next_cur_feats, two_tag_v);
                pair_hash_v := hash_mix(pair_hash_v, resize(delta_v, BIN_INDEX_WIDTH), resize(delta_v, 32));
                last_hash_r <= pair_hash_v;
                last_delta_r <= delta_v;
                out_data_r <= std_logic_vector(pair_hash_v) &
                              std_logic_vector(delta_v) &
                              std_logic_vector(next_cur_bins(0)) &
                              std_logic_vector(hist_peak_bin_r(gap_idx_v)(0)) &
                              std_logic_vector(next_sel);
                out_valid_r <= '1';
              end if;
              for i in 15 downto 1 loop
                hist_peak_bin_r(i) <= hist_peak_bin_r(i - 1);
                hist_peak_mag_r(i) <= hist_peak_mag_r(i - 1);
                hist_peak_feat_r(i) <= hist_peak_feat_r(i - 1);
              end loop;
              hist_peak_bin_r(0) <= next_cur_bins;
              hist_peak_mag_r(0) <= next_cur_mags;
              hist_peak_feat_r(0) <= next_cur_feats;
            end if;
            hash_r <= hash_seed_r;
            bin_idx_r <= (others => '0');
            stride_count_r <= (others => '0');
            selected_r <= (others => '0');
            peak_bin_r <= (others => '0');
            peak_mag_r <= (others => '0');
            cur_peak_bin_r <= (others => (others => '0'));
            cur_peak_mag_r <= (others => (others => '0'));
            cur_peak_feat_r <= (others => (others => '0'));
            busy_r <= '0';
          else
            bin_idx_r <= bin_idx_r + 1;
          end if;
        elsif enable_r = '0' then
          busy_r <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
