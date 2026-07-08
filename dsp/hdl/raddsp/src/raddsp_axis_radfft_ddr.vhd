library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_fft_twiddle_pkg.all;

-- DDR-backed AXI-stream RadFFT accelerator.
-- Uses external memory through AXI-style control/data paths for large FFT frames that exceed local block RAM budgets.
entity raddsp_axis_radfft_ddr is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR                : string := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY         : string := "ultrascaleplus";
    -- Sets the bit width for G AXI ADDR WIDTH values carried by this module.
    G_AXI_ADDR_WIDTH      : positive := 32;
    -- Sets the bit width for G AXI DATA WIDTH values carried by this module.
    G_AXI_DATA_WIDTH      : positive := 64;
    -- Sets the bit width for G AXIS DATA WIDTH values carried by this module.
    G_AXIS_DATA_WIDTH     : positive := 64;
    -- Sets the bit width for G AXI LITE ADDR WIDTH values carried by this module.
    G_AXI_LITE_ADDR_WIDTH : positive := 16;
    -- Sets the storage depth, frame length, or number of buffered samples used internally.
    G_FIFO_DEPTH          : positive := 1024;
    -- Configures G FIFO FWFT for this instance.
    G_FIFO_FWFT           : boolean := true;
    -- Configures G MAX BURST BEATS for this instance.
    G_MAX_BURST_BEATS     : positive := 64;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_POINTS          : positive := 1024;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_RADIX           : positive := 2;
    -- Sets the bit width for G FFT INPUT WIDTH values carried by this module.
    G_FFT_INPUT_WIDTH     : positive := 32;
    -- Sets the bit width for G FFT TWIDDLE WIDTH values carried by this module.
    G_FFT_TWIDDLE_WIDTH   : positive := 16;
    -- Sets the bit width for G FFT OUTPUT WIDTH values carried by this module.
    G_FFT_OUTPUT_WIDTH    : positive := 32;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_SCALE_EACH_STAGE : boolean := true;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_MEMORY_STYLE    : string := "block";
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_TWIDDLE_INIT_FILE : string := "../../mem/radfft_twiddle_1024_16_fft.mem";
    -- Sets the transform, frame, or vector size used by the datapath.
    G_FFT_INVERSE         : boolean := false;
    -- Sets the number of parallel sample lanes processed per handshake beat.
    G_MAX_MULTIPLIER_LANES : positive := 16;
    -- Configures G XCORR ENABLE for this instance.
    G_XCORR_ENABLE        : boolean := true;
    -- Sets the storage depth, frame length, or number of buffered samples used internally.
    G_XCORR_FRAME_DEPTH   : positive := 16384;
    -- Configures G XCORR MEMORY STYLE for this instance.
    G_XCORR_MEMORY_STYLE  : string := "block";
    -- Configures G DEFAULT REGION BYTES for this instance.
    G_DEFAULT_REGION_BYTES : natural := 67108864
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
end entity;

architecture rtl of raddsp_axis_radfft_ddr is
  component xpm_fifo_sync
    generic (
      -- Configures CASCADE HEIGHT for this instance.
      CASCADE_HEIGHT      : integer := 0;
      -- Configures DOUT RESET VALUE for this instance.
      DOUT_RESET_VALUE    : string  := "0";
      -- Configures ECC MODE for this instance.
      ECC_MODE            : string  := "no_ecc";
      -- Configures FIFO MEMORY TYPE for this instance.
      FIFO_MEMORY_TYPE    : string  := "auto";
      -- Configures FIFO READ LATENCY for this instance.
      FIFO_READ_LATENCY   : integer := 1;
      -- Sets the storage depth, frame length, or number of buffered samples used internally.
      FIFO_WRITE_DEPTH    : integer := 1024;
      -- Configures FULL RESET VALUE for this instance.
      FULL_RESET_VALUE    : integer := 0;
      -- Configures PROG EMPTY THRESH for this instance.
      PROG_EMPTY_THRESH   : integer := 10;
      -- Configures PROG FULL THRESH for this instance.
      PROG_FULL_THRESH    : integer := 10;
      -- Sets the bit width for RD DATA COUNT WIDTH values carried by this module.
      RD_DATA_COUNT_WIDTH : integer := 1;
      -- Sets the bit width for READ DATA WIDTH values carried by this module.
      READ_DATA_WIDTH     : integer := 32;
      -- Configures READ MODE for this instance.
      READ_MODE           : string  := "std";
      -- Configures SIM ASSERT CHK for this instance.
      SIM_ASSERT_CHK      : integer := 0;
      -- Configures USE ADV FEATURES for this instance.
      USE_ADV_FEATURES    : string  := "0707";
      -- Configures WAKEUP TIME for this instance.
      WAKEUP_TIME         : integer := 0;
      -- Sets the bit width for WRITE DATA WIDTH values carried by this module.
      WRITE_DATA_WIDTH    : integer := 32;
      -- Sets the bit width for WR DATA COUNT WIDTH values carried by this module.
      WR_DATA_COUNT_WIDTH : integer := 1
    );
    port (
      -- Almost empty interface signal.
      almost_empty  : out std_logic;
      -- Almost full interface signal.
      almost_full   : out std_logic;
      -- Data valid interface signal.
      data_valid    : out std_logic;
      -- Dbiterr interface signal.
      dbiterr       : out std_logic;
      -- Dout interface signal.
      dout          : out std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
      -- Empty interface signal.
      empty         : out std_logic;
      -- Full interface signal.
      full          : out std_logic;
      -- Overflow interface signal.
      overflow      : out std_logic;
      -- Prog empty interface signal.
      prog_empty    : out std_logic;
      -- Prog full interface signal.
      prog_full     : out std_logic;
      -- Readback control or data signal for host-visible captured state.
      rd_data_count : out std_logic_vector(RD_DATA_COUNT_WIDTH - 1 downto 0);
      -- Readback control or data signal for host-visible captured state.
      rd_rst_busy   : out std_logic;
      -- Sbiterr interface signal.
      sbiterr       : out std_logic;
      -- Underflow interface signal.
      underflow     : out std_logic;
      -- Wr ack interface signal.
      wr_ack        : out std_logic;
      -- Wr data count interface signal.
      wr_data_count : out std_logic_vector(WR_DATA_COUNT_WIDTH - 1 downto 0);
      -- Wr rst busy interface signal.
      wr_rst_busy   : out std_logic;
      -- Din interface signal.
      din           : in  std_logic_vector(WRITE_DATA_WIDTH - 1 downto 0);
      -- Injectdbiterr interface signal.
      injectdbiterr : in  std_logic;
      -- Injectsbiterr interface signal.
      injectsbiterr : in  std_logic;
      -- Readback control or data signal for host-visible captured state.
      rd_en         : in  std_logic;
      -- Active-high synchronous reset for this clock domain.
      rst           : in  std_logic;
      -- Sleep interface signal.
      sleep         : in  std_logic;
      -- Clock for the associated synchronous logic and handshake domain.
      wr_clk        : in  std_logic;
      -- Wr en interface signal.
      wr_en         : in  std_logic
    );
  end component;

  type op_t is (OP_IDLE, OP_AXIS_TO_DDR, OP_DDR_TO_AXIS, OP_DDR_FFT, OP_DDR_XCORR, OP_UNSUPPORTED_FFT);
  type wr_state_t is (WR_IDLE, WR_AW, WR_W, WR_B);
  type rd_state_t is (RD_IDLE, RD_AR, RD_R);
  type tw_state_t is (TW_IDLE, TW_AR, TW_R, TW_DONE);
  type fft_in_state_t is (FFT_IN_IDLE, FFT_IN_AR, FFT_IN_R, FFT_IN_DONE);
  type fft_out_state_t is (FFT_OUT_IDLE, FFT_OUT_AW, FFT_OUT_W, FFT_OUT_B, FFT_OUT_DONE);
  type xcorr_phase_t is (XCORR_FFT_A, XCORR_FFT_B, XCORR_PRODUCT, XCORR_IFFT);
  type prod_state_t is (
    PROD_IDLE,
    PROD_AR_A,
    PROD_R_A,
    PROD_AR_B,
    PROD_R_B,
    PROD_MUL_START,
    PROD_MUL_WAIT,
    PROD_AW,
    PROD_W,
    PROD_B,
    PROD_DONE
  );

  function ceil_log2(value : positive) return natural is
    variable v : natural := value - 1;
    variable r : natural := 0;
  begin
    while v > 0 loop
      v := v / 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function addr_width(depth : positive) return positive is
    variable w : natural := ceil_log2(depth);
  begin
    if w = 0 then
      return 1;
    end if;
    return w;
  end function;

  function is_power_of_four(value : positive) return boolean is
    variable v : positive := value;
  begin
    while (v mod 4) = 0 loop
      v := v / 4;
    end loop;
    return v = 1;
  end function;

  function width_from_code(code : std_logic_vector(2 downto 0)) return natural is
  begin
    case code is
      when "000" => return 16;
      when "001" => return 24;
      when "010" => return 32;
      when others => return 0;
    end case;
  end function;

  function lanes_from_code(code : std_logic_vector(1 downto 0)) return natural is
  begin
    case code is
      when "00" => return 8;
      when "01" => return 16;
      when "10" => return 32;
      when others => return 64;
    end case;
  end function;

  function point_count(log2_value : unsigned(7 downto 0)) return natural is
    variable ret : natural := 1;
    variable requested : natural := to_integer(log2_value);
  begin
    for i in 1 to ceil_log2(G_FFT_POINTS) loop
      if i <= requested then
        ret := ret * 2;
      end if;
    end loop;
    return ret;
  end function;

  function default_radix4 return std_logic is
  begin
    if G_FFT_RADIX = 4 then
      return '1';
    end if;
    return '0';
  end function;

  constant C_AXI_BYTES     : positive := G_AXI_DATA_WIDTH / 8;
  constant C_AXIS_BYTES    : positive := G_AXIS_DATA_WIDTH / 8;
  constant C_FIFO_WIDTH    : positive := G_AXIS_DATA_WIDTH + 1;
  constant C_MAX_BURST     : positive := G_MAX_BURST_BEATS;
  constant C_TW_ADDR_WIDTH : positive := addr_width(G_FFT_POINTS);
  constant C_TW_WORD_WIDTH : positive := 2 * G_FFT_TWIDDLE_WIDTH;
  constant C_FFT_INPUT_BITS : positive := 2 * G_FFT_INPUT_WIDTH;
  constant C_FFT_OUTPUT_BITS : positive := 2 * G_FFT_OUTPUT_WIDTH;
  constant C_FFT_FRAME_BYTES : positive := G_FFT_POINTS * C_AXI_BYTES;
  constant C_CORR_PRODUCT_WIDTH : positive := (2 * G_FFT_OUTPUT_WIDTH) + 4;

  subtype fft_input_word_t is std_logic_vector(C_FFT_INPUT_BITS - 1 downto 0);
  subtype fft_output_word_t is std_logic_vector(C_FFT_OUTPUT_BITS - 1 downto 0);

  signal control_r        : std_logic_vector(31 downto 0) := (others => '0');
  signal status_r         : std_logic_vector(31 downto 0) := (others => '0');
  signal base_addr_r      : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal out_addr_r       : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal corr_b_addr_r    : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal corr_scratch_addr_r : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal twiddle_addr_r   : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal region_bytes_r   : unsigned(31 downto 0) := to_unsigned(G_DEFAULT_REGION_BYTES, 32);
  signal length_bytes_r   : unsigned(31 downto 0) := (others => '0');
  signal batch_count_r    : unsigned(31 downto 0) := to_unsigned(1, 32);
  signal batch_total_r    : unsigned(31 downto 0) := to_unsigned(1, 32);
  signal batch_remaining_r : unsigned(31 downto 0) := (others => '0');
  signal batch_done_count_r : unsigned(31 downto 0) := (others => '0');
  signal src_stride_bytes_r : unsigned(31 downto 0) := (others => '0');
  signal dst_stride_bytes_r : unsigned(31 downto 0) := (others => '0');
  signal active_src_stride_r : unsigned(31 downto 0) := (others => '0');
  signal active_dst_stride_r : unsigned(31 downto 0) := (others => '0');
  signal fft_frame_bytes_r : unsigned(31 downto 0) := (others => '0');
  signal point_log2_r     : unsigned(7 downto 0) := to_unsigned(ceil_log2(G_FFT_POINTS), 8);
  signal burst_beats_r    : unsigned(7 downto 0) := to_unsigned(G_MAX_BURST_BEATS, 8);
  signal fft_config_r     : std_logic_vector(31 downto 0) := (others => '0');
  signal irq_enable_r     : std_logic := '1';

  signal op_r             : op_t := OP_IDLE;
  signal wr_state_r       : wr_state_t := WR_IDLE;
  signal rd_state_r       : rd_state_t := RD_IDLE;
  signal wr_addr_r        : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_addr_r        : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal wr_remaining_r   : unsigned(31 downto 0) := (others => '0');
  signal rd_remaining_r   : unsigned(31 downto 0) := (others => '0');
  signal wr_burst_beats_r : unsigned(8 downto 0) := (others => '0');
  signal rd_burst_beats_r : unsigned(8 downto 0) := (others => '0');
  signal wr_beat_index_r  : unsigned(8 downto 0) := (others => '0');
  signal rd_beat_index_r  : unsigned(8 downto 0) := (others => '0');
  signal wr_fifo_advance_r : std_logic := '0';
  signal tw_state_r       : tw_state_t := TW_IDLE;
  signal tw_addr_r        : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal tw_remaining_r   : unsigned(31 downto 0) := (others => '0');
  signal tw_burst_beats_r : unsigned(8 downto 0) := (others => '0');
  signal tw_beat_index_r  : unsigned(8 downto 0) := (others => '0');
  signal tw_load_index_r  : unsigned(C_TW_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal fft_in_state_r    : fft_in_state_t := FFT_IN_IDLE;
  signal fft_out_state_r   : fft_out_state_t := FFT_OUT_IDLE;
  signal fft_in_frame_base_r : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal fft_out_frame_base_r : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal fft_in_addr_r     : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal fft_out_addr_r    : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal fft_in_remaining_r : unsigned(31 downto 0) := (others => '0');
  signal fft_feed_remaining_r : unsigned(31 downto 0) := (others => '0');
  signal fft_out_remaining_r : unsigned(31 downto 0) := (others => '0');
  signal fft_in_burst_beats_r : unsigned(8 downto 0) := (others => '0');
  signal fft_out_burst_beats_r : unsigned(8 downto 0) := (others => '0');
  signal fft_in_beat_index_r : unsigned(8 downto 0) := (others => '0');
  signal fft_out_beat_index_r : unsigned(8 downto 0) := (others => '0');
  signal fft_runtime_inverse_r : std_logic := '0';

  signal xcorr_phase_r    : xcorr_phase_t := XCORR_FFT_A;
  signal prod_state_r     : prod_state_t := PROD_IDLE;
  signal prod_a_addr_r    : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal prod_b_addr_r    : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal prod_out_addr_r  : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal prod_remaining_r : unsigned(31 downto 0) := (others => '0');
  signal prod_a_word_r    : std_logic_vector(G_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal prod_b_word_r    : std_logic_vector(G_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal prod_valid_r     : std_logic := '0';
  signal prod_a_re_r      : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0) := (others => '0');
  signal prod_a_im_r      : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0) := (others => '0');
  signal prod_b_re_r      : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0) := (others => '0');
  signal prod_b_im_r      : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0) := (others => '0');
  signal prod_mul_a_r     : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0) := (others => '0');
  signal prod_mul_b_r     : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0) := (others => '0');
  signal prod_mul_p       : signed(C_CORR_PRODUCT_WIDTH - 1 downto 0);
  signal prod_done_s      : std_logic;
  signal prod_mul_phase_r : natural range 0 to 3 := 0;
  signal prod_re_acc_r    : signed(C_CORR_PRODUCT_WIDTH downto 0) := (others => '0');
  signal prod_im_acc_r    : signed(C_CORR_PRODUCT_WIDTH downto 0) := (others => '0');
  signal xcorr_fast_local_r : std_logic := '0';
  signal xcorr_store_index_r : natural range 0 to G_FFT_POINTS - 1 := 0;

  signal xcorr_a_fifo_din   : fft_output_word_t := (others => '0');
  signal xcorr_a_fifo_dout  : fft_output_word_t;
  signal xcorr_a_fifo_wr_en : std_logic := '0';
  signal xcorr_a_fifo_rd_en : std_logic := '0';
  signal xcorr_a_fifo_empty : std_logic;
  signal xcorr_a_fifo_full  : std_logic;
  signal xcorr_a_fifo_valid : std_logic;
  signal xcorr_a_advance_r : std_logic := '0';
  signal xcorr_a_wait_r : std_logic := '0';
  signal xcorr_b_skid_r : fft_output_word_t := (others => '0');
  signal xcorr_b_skid_valid_r : std_logic := '0';
  signal xcorr_b_skid_last_r : std_logic := '0';
  signal xcorr_p_fifo_din   : fft_input_word_t := (others => '0');
  signal xcorr_p_fifo_dout  : fft_input_word_t;
  signal xcorr_p_fifo_wr_en : std_logic := '0';
  signal xcorr_p_fifo_rd_en : std_logic := '0';
  signal xcorr_p_fifo_empty : std_logic;
  signal xcorr_p_fifo_full  : std_logic;
  signal xcorr_p_fifo_valid : std_logic;

  signal awvalid_r        : std_logic := '0';
  signal wvalid_r         : std_logic := '0';
  signal bready_r         : std_logic := '0';
  signal arvalid_r        : std_logic := '0';
  signal rready_r         : std_logic := '0';
  signal awaddr_r         : std_logic_vector(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal araddr_r         : std_logic_vector(G_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal awlen_r          : std_logic_vector(7 downto 0) := (others => '0');
  signal arlen_r          : std_logic_vector(7 downto 0) := (others => '0');
  signal wdata_r          : std_logic_vector(G_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wlast_r          : std_logic := '0';

  signal in_fifo_din      : std_logic_vector(C_FIFO_WIDTH - 1 downto 0);
  signal in_fifo_dout     : std_logic_vector(C_FIFO_WIDTH - 1 downto 0);
  signal in_fifo_wr_en    : std_logic;
  signal in_fifo_rd_en    : std_logic := '0';
  signal in_fifo_empty    : std_logic;
  signal in_fifo_full     : std_logic;
  signal in_fifo_valid    : std_logic;

  signal out_fifo_din     : std_logic_vector(C_FIFO_WIDTH - 1 downto 0);
  signal out_fifo_dout    : std_logic_vector(C_FIFO_WIDTH - 1 downto 0);
  signal out_fifo_wr_en   : std_logic := '0';
  signal out_fifo_rd_en   : std_logic := '0';
  signal out_fifo_empty   : std_logic;
  signal out_fifo_full    : std_logic;
  signal out_fifo_valid   : std_logic;
  signal out_word_valid_r : std_logic := '0';
  signal out_word_data_r  : std_logic_vector(G_AXIS_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal out_word_last_r  : std_logic := '0';
  signal fifo_rst         : std_logic;

  signal fft_in_fifo_din   : fft_input_word_t := (others => '0');
  signal fft_in_fifo_dout  : fft_input_word_t;
  signal fft_in_fifo_wr_en : std_logic := '0';
  signal fft_in_fifo_rd_en : std_logic := '0';
  signal fft_in_fifo_empty : std_logic;
  signal fft_in_fifo_full  : std_logic;
  signal fft_in_fifo_valid : std_logic;

  signal axil_awready_r   : std_logic := '0';
  signal axil_wready_r    : std_logic := '0';
  signal axil_bvalid_r    : std_logic := '0';
  signal axil_bresp_r     : std_logic_vector(1 downto 0) := "00";
  signal axil_arready_r   : std_logic := '0';
  signal axil_rvalid_r    : std_logic := '0';
  signal axil_rresp_r     : std_logic_vector(1 downto 0) := "00";
  signal axil_rdata_r     : std_logic_vector(31 downto 0) := (others => '0');

  signal fft_s_valid_r    : std_logic := '0';
  signal fft2_s_valid     : std_logic;
  signal fft4_s_valid     : std_logic;
  signal fftp_s_valid     : std_logic;
  signal fft_s_ready      : std_logic;
  signal fft2_s_ready     : std_logic;
  signal fft4_s_ready     : std_logic;
  signal fftp_s_ready     : std_logic;
  signal fft_s_data_r     : std_logic_vector(C_FFT_INPUT_BITS - 1 downto 0) := (others => '0');
  signal fft_s_last_r     : std_logic := '0';
  signal fft_m_valid      : std_logic;
  signal fft2_m_valid     : std_logic;
  signal fft4_m_valid     : std_logic;
  signal fftp_m_valid     : std_logic;
  signal fft_m_ready_r    : std_logic := '0';
  signal fft2_m_ready     : std_logic;
  signal fft4_m_ready     : std_logic;
  signal fftp_m_ready     : std_logic;
  signal fft_m_data       : std_logic_vector(C_FFT_OUTPUT_BITS - 1 downto 0);
  signal fft2_m_data      : std_logic_vector(C_FFT_OUTPUT_BITS - 1 downto 0);
  signal fft4_m_data      : std_logic_vector(C_FFT_OUTPUT_BITS - 1 downto 0);
  signal fftp_m_data      : std_logic_vector(C_FFT_OUTPUT_BITS - 1 downto 0);
  signal fft_m_last       : std_logic;
  signal fft2_m_last      : std_logic;
  signal fft4_m_last      : std_logic;
  signal fftp_m_last      : std_logic;
  signal fft_tw_addr      : std_logic_vector(31 downto 0);
  signal fft2_tw_addr     : std_logic_vector(31 downto 0);
  signal fft4_tw_addr     : std_logic_vector(31 downto 0);
  signal fftp_tw_addr     : std_logic_vector(31 downto 0);
  signal fft_tw_re        : std_logic_vector(G_FFT_TWIDDLE_WIDTH - 1 downto 0);
  signal fft_tw_im        : std_logic_vector(G_FFT_TWIDDLE_WIDTH - 1 downto 0);
  signal fft_frame_done   : std_logic;
  signal fft2_frame_done  : std_logic;
  signal fft4_frame_done  : std_logic;
  signal fftp_frame_done  : std_logic;
  signal fft_busy         : std_logic;
  signal fft2_busy        : std_logic;
  signal fft4_busy        : std_logic;
  signal fftp_busy        : std_logic;
  signal fft_radix4_active_r : std_logic := '0';
  signal fft_parallel_active_r : std_logic := '0';
  signal ifft_active_s     : std_logic;
  signal ifft_s_valid_r    : std_logic := '0';
  signal ifft_s_ready      : std_logic;
  signal ifft_s_data_r     : std_logic_vector(C_FFT_INPUT_BITS - 1 downto 0) := (others => '0');
  signal ifft_s_last_r     : std_logic := '0';
  signal ifft_m_valid      : std_logic;
  signal ifft_m_ready      : std_logic;
  signal ifft_m_data       : std_logic_vector(C_FFT_OUTPUT_BITS - 1 downto 0);
  signal ifft_m_last       : std_logic;
  signal ifft_tw_addr      : std_logic_vector(31 downto 0);
  signal ifft_frame_done   : std_logic;
  signal ifft_busy         : std_logic;
  signal ifft_in_remaining_r : unsigned(31 downto 0) := (others => '0');
  signal tw_cache_a_addr  : std_logic_vector(C_TW_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal tw_cache_a_din   : std_logic_vector(C_TW_WORD_WIDTH - 1 downto 0) := (others => '0');
  signal tw_cache_a_dout  : std_logic_vector(C_TW_WORD_WIDTH - 1 downto 0);
  signal tw_cache_a_we    : std_logic := '0';
  signal tw_cache_b_addr  : std_logic_vector(C_TW_ADDR_WIDTH - 1 downto 0);
  signal tw_cache_b_dout  : std_logic_vector(C_TW_WORD_WIDTH - 1 downto 0);

  function count_width(depth : positive) return natural is
  begin
    return ceil_log2(depth) + 1;
  end function;

  function fifo_read_mode return string is
  begin
    if G_FIFO_FWFT then
      return "fwft";
    end if;
    return "std";
  end function;

  function fifo_read_latency return integer is
  begin
    if G_FIFO_FWFT then
      return 0;
    end if;
    return 1;
  end function;

  function axi_size return std_logic_vector is
  begin
    case C_AXI_BYTES is
      when 1 => return "000";
      when 2 => return "001";
      when 4 => return "010";
      when 8 => return "011";
      when 16 => return "100";
      when 32 => return "101";
      when 64 => return "110";
      when others => return "011";
    end case;
  end function;

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(shift_right(unsigned(addr), 2));
  end function;

  function min_u32(a : unsigned; b : natural) return unsigned is
    variable bv : unsigned(a'range) := to_unsigned(b, a'length);
  begin
    if a < bv then
      return a;
    end if;
    return bv;
  end function;

  function addr_low(addr : unsigned) return std_logic_vector is
    variable ret : std_logic_vector(31 downto 0) := (others => '0');
  begin
    if addr'length >= 32 then
      ret := std_logic_vector(addr(31 downto 0));
    else
      ret(addr'length - 1 downto 0) := std_logic_vector(addr);
    end if;
    return ret;
  end function;

  function addr_high(addr : unsigned) return std_logic_vector is
    variable ret : std_logic_vector(31 downto 0) := (others => '0');
    variable high_width : natural;
  begin
    if addr'length > 32 then
      high_width := addr'length - 32;
      if high_width >= 32 then
        ret := std_logic_vector(addr(63 downto 32));
      else
        ret(high_width - 1 downto 0) := std_logic_vector(addr(addr'length - 1 downto 32));
      end if;
    end if;
    return ret;
  end function;

  function set_addr_low(old_addr : unsigned; data : std_logic_vector(31 downto 0)) return unsigned is
    variable ret : unsigned(old_addr'range) := old_addr;
  begin
    for bit_index in 0 to ret'length - 1 loop
      if bit_index <= 31 then
        ret(bit_index) := data(bit_index);
      end if;
    end loop;
    return ret;
  end function;

  function set_addr_high(old_addr : unsigned; data : std_logic_vector(31 downto 0)) return unsigned is
    variable ret : unsigned(old_addr'range) := old_addr;
  begin
    for bit_index in 32 to ret'length - 1 loop
      if bit_index - 32 <= 31 then
        ret(bit_index) := data(bit_index - 32);
      end if;
    end loop;
    return ret;
  end function;

  function bytes_to_beats(bytes : unsigned; max_beats : unsigned) return unsigned is
    variable max_bytes : natural := to_integer(max_beats) * C_AXI_BYTES;
    variable clipped   : unsigned(31 downto 0);
    variable beats     : unsigned(8 downto 0);
  begin
    clipped := min_u32(bytes, max_bytes);
    if clipped = 0 then
      beats := (others => '0');
    else
      beats := resize(shift_right(clipped + to_unsigned(C_AXI_BYTES - 1, clipped'length), ceil_log2(C_AXI_BYTES)), beats'length);
    end if;
    return beats;
  end function;

  function sample_re(value : std_logic_vector) return signed is
  begin
    return signed(value((2 * G_FFT_OUTPUT_WIDTH) - 1 downto G_FFT_OUTPUT_WIDTH));
  end function;

  function sample_im(value : std_logic_vector) return signed is
  begin
    return signed(value(G_FFT_OUTPUT_WIDTH - 1 downto 0));
  end function;

  function pack_fft_input(re_value : signed; im_value : signed) return std_logic_vector is
    variable ret : std_logic_vector(C_FFT_INPUT_BITS - 1 downto 0);
  begin
    ret(C_FFT_INPUT_BITS - 1 downto G_FFT_INPUT_WIDTH) := std_logic_vector(resize(re_value, G_FFT_INPUT_WIDTH));
    ret(G_FFT_INPUT_WIDTH - 1 downto 0) := std_logic_vector(resize(im_value, G_FFT_INPUT_WIDTH));
    return ret;
  end function;
begin
  assert G_AXI_DATA_WIDTH = G_AXIS_DATA_WIDTH
    report "raddsp_axis_radfft_ddr currently requires AXI and AXIS data widths to match"
    severity failure;
  assert G_AXI_DATA_WIDTH = 32 or G_AXI_DATA_WIDTH = 64 or G_AXI_DATA_WIDTH = 128
    report "raddsp_axis_radfft_ddr supports 32, 64, or 128 bit data paths"
    severity failure;
  assert G_MAX_BURST_BEATS <= 256
    report "AXI4 burst length must not exceed 256 beats"
    severity failure;
  assert G_FIFO_FWFT
    report "raddsp_axis_radfft_ddr currently requires FWFT FIFOs for sustained AXI burst streaming"
    severity failure;
  assert C_FFT_INPUT_BITS <= G_AXI_DATA_WIDTH and C_FFT_OUTPUT_BITS <= G_AXI_DATA_WIDTH
    report "raddsp_axis_radfft_ddr FFT word widths must fit within the AXI data width"
    severity failure;
  assert C_FFT_FRAME_BYTES <= G_DEFAULT_REGION_BYTES
    report "raddsp_axis_radfft_ddr default region is smaller than one FFT frame"
    severity warning;
  assert G_FFT_INPUT_WIDTH <= 32 and G_FFT_OUTPUT_WIDTH <= 32
    report "raddsp_axis_radfft_ddr supports runtime sample widths up to 32 bits per real/imag component"
    severity failure;
  assert G_MAX_MULTIPLIER_LANES = 8 or G_MAX_MULTIPLIER_LANES = 16 or G_MAX_MULTIPLIER_LANES = 32 or G_MAX_MULTIPLIER_LANES = 64 or G_MAX_MULTIPLIER_LANES = 128
    report "raddsp_axis_radfft_ddr G_MAX_MULTIPLIER_LANES must be 8, 16, 32, 64, or 128"
    severity failure;
  assert is_power_of_four(G_FFT_POINTS)
    report "raddsp_axis_radfft_ddr runtime radix-4 support requires G_FFT_POINTS to be a power of four"
    severity failure;
  assert (not G_XCORR_ENABLE) or G_XCORR_FRAME_DEPTH >= G_FFT_POINTS
    report "raddsp_axis_radfft_ddr G_XCORR_FRAME_DEPTH must hold at least one FFT frame"
    severity failure;

  fifo_rst <= not rstn;
  s_axi_awready <= axil_awready_r;
  s_axi_wready <= axil_wready_r;
  s_axi_bvalid <= axil_bvalid_r;
  s_axi_bresp <= axil_bresp_r;
  s_axi_arready <= axil_arready_r;
  s_axi_rvalid <= axil_rvalid_r;
  s_axi_rresp <= axil_rresp_r;
  s_axi_rdata <= axil_rdata_r;

  m_axi_awaddr <= awaddr_r;
  m_axi_awlen <= awlen_r;
  m_axi_awsize <= axi_size;
  m_axi_awburst <= "01";
  m_axi_awvalid <= awvalid_r;
  m_axi_wdata <= wdata_r;
  m_axi_wstrb <= (others => '1');
  m_axi_wlast <= wlast_r;
  m_axi_wvalid <= wvalid_r;
  m_axi_bready <= bready_r;
  m_axi_araddr <= araddr_r;
  m_axi_arlen <= arlen_r;
  m_axi_arsize <= axi_size;
  m_axi_arburst <= "01";
  m_axi_arvalid <= arvalid_r;
  m_axi_rready <= rready_r;

  in_fifo_din <= s_axis_tlast & s_axis_tdata;
  in_fifo_wr_en <= s_axis_tvalid and s_axis_tready;
  s_axis_tready <= '1' when (op_r = OP_AXIS_TO_DDR and in_fifo_full = '0') or
                            (op_r = OP_DDR_FFT and fft_config_r(4) = '1' and
                             tw_state_r = TW_DONE and fft_in_state_r /= FFT_IN_DONE and
                             fft_s_valid_r = '0' and fft_s_ready = '1') else '0';
  m_axis_tdata <= out_word_data_r;
  m_axis_tvalid <= out_word_valid_r;
  m_axis_tlast <= out_word_last_r;
  irq_o <= irq_enable_r and (status_r(1) or status_r(2));

  tw_cache_b_addr <= std_logic_vector(resize(unsigned(ifft_tw_addr), C_TW_ADDR_WIDTH)) when ifft_active_s = '1' else
                     std_logic_vector(resize(unsigned(fft_tw_addr), C_TW_ADDR_WIDTH));
  fft_tw_re <= tw_cache_b_dout(C_TW_WORD_WIDTH - 1 downto G_FFT_TWIDDLE_WIDTH);
  fft_tw_im <= tw_cache_b_dout(G_FFT_TWIDDLE_WIDTH - 1 downto 0);
  ifft_active_s <= '1' when xcorr_fast_local_r = '1' and xcorr_phase_r = XCORR_IFFT else '0';
  fft_s_ready <= fftp_s_ready when fft_parallel_active_r = '1' else fft2_s_ready;
  fft_m_valid <= ifft_m_valid when ifft_active_s = '1' else
                 fftp_m_valid when fft_parallel_active_r = '1' else fft2_m_valid;
  fft_m_data <= ifft_m_data when ifft_active_s = '1' else
                fftp_m_data when fft_parallel_active_r = '1' else fft2_m_data;
  fft_m_last <= ifft_m_last when ifft_active_s = '1' else
                fftp_m_last when fft_parallel_active_r = '1' else fft2_m_last;
  fft_tw_addr <= fftp_tw_addr when fft_parallel_active_r = '1' else fft2_tw_addr;
  fft_busy <= ifft_busy when ifft_active_s = '1' else
              fftp_busy when fft_parallel_active_r = '1' else fft2_busy;
  fft_frame_done <= ifft_frame_done when ifft_active_s = '1' else
                    fftp_frame_done when fft_parallel_active_r = '1' else fft2_frame_done;
  fft2_m_ready <= fft_m_ready_r when fft_parallel_active_r = '0' and ifft_active_s = '0' else '0';
  fftp_m_ready <= fft_m_ready_r when fft_parallel_active_r = '1' and ifft_active_s = '0' else '0';
  ifft_m_ready <= fft_m_ready_r when ifft_active_s = '1' else '0';
  fft4_m_ready <= '0';
  fft2_s_valid <= fft_s_valid_r when fft_parallel_active_r = '0' else '0';
  fftp_s_valid <= fft_s_valid_r when fft_parallel_active_r = '1' else '0';
  fft4_s_valid <= '0';

  tw_cache_i: entity work.fft_tdp_ram
    generic map (
      DEVICE_FAMILY => DEVICE_FAMILY,
      MEMORY_STYLE => G_FFT_MEMORY_STYLE,
      DATA_WIDTH => C_TW_WORD_WIDTH,
      ADDR_WIDTH => C_TW_ADDR_WIDTH,
      DEPTH => G_FFT_POINTS
    )
    port map (
      clk => clk,
      a_addr => tw_cache_a_addr,
      a_din => tw_cache_a_din,
      a_dout => tw_cache_a_dout,
      a_we => tw_cache_a_we,
      b_addr => tw_cache_b_addr,
      b_din => (others => '0'),
      b_dout => tw_cache_b_dout,
      b_we => '0'
    );

  fft_radix2_i: entity work.raddsp_axis_radfft_radix2_tdp
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      G_POINTS => G_FFT_POINTS,
      G_MAX_POINTS => G_FFT_POINTS,
      G_INVERSE_FFT => G_FFT_INVERSE,
      G_INPUT_WIDTH => G_FFT_INPUT_WIDTH,
      G_TWIDDLE_WIDTH => G_FFT_TWIDDLE_WIDTH,
      G_OUTPUT_WIDTH => G_FFT_OUTPUT_WIDTH,
      G_SCALE_EACH_STAGE => G_FFT_SCALE_EACH_STAGE,
      G_MEMORY_STYLE => G_FFT_MEMORY_STYLE,
      G_TWIDDLE_MEMORY_STYLE => "distributed",
      G_TWIDDLE_INIT_FILE => G_FFT_TWIDDLE_INIT_FILE,
      G_EXTERNAL_TWIDDLES => true,
      G_MEMORY_WORD_SAMPLES => 1
    )
    port map (
      clk => clk,
      rst => fifo_rst,
      s_axis_tvalid => fft2_s_valid,
      s_axis_tready => fft2_s_ready,
      s_axis_tdata => fft_s_data_r,
      s_axis_tlast => fft_s_last_r,
      m_axis_tvalid => fft2_m_valid,
      m_axis_tready => fft2_m_ready,
      m_axis_tdata => fft2_m_data,
      m_axis_tlast => fft2_m_last,
      runtime_inverse_i => fft_runtime_inverse_r,
      active_point_log2_i => std_logic_vector(point_log2_r),
      active_radix4_i => fft_radix4_active_r,
      active_input_width_i => fft_config_r(15 downto 8),
      active_output_width_i => fft_config_r(23 downto 16),
      twiddle_addr_o => fft2_tw_addr,
      twiddle_re_i => fft_tw_re,
      twiddle_im_i => fft_tw_im,
      busy_o => fft2_busy,
      frame_done_o => fft2_frame_done
    );

  fft_parallel8_i: entity work.raddsp_axis_radfft_parallel8
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      G_POINTS => G_FFT_POINTS,
      G_MAX_POINTS => G_FFT_POINTS,
      G_INVERSE_FFT => G_FFT_INVERSE,
      G_INPUT_WIDTH => G_FFT_INPUT_WIDTH,
      G_TWIDDLE_WIDTH => G_FFT_TWIDDLE_WIDTH,
      G_OUTPUT_WIDTH => G_FFT_OUTPUT_WIDTH,
      G_SCALE_EACH_STAGE => G_FFT_SCALE_EACH_STAGE,
      G_MULTIPLIER_LANES => G_MAX_MULTIPLIER_LANES
    )
    port map (
      clk => clk,
      rst => fifo_rst,
      s_axis_tvalid => fftp_s_valid,
      s_axis_tready => fftp_s_ready,
      s_axis_tdata => fft_s_data_r,
      s_axis_tlast => fft_s_last_r,
      m_axis_tvalid => fftp_m_valid,
      m_axis_tready => fftp_m_ready,
      m_axis_tdata => fftp_m_data,
      m_axis_tlast => fftp_m_last,
      runtime_inverse_i => fft_runtime_inverse_r,
      active_point_log2_i => std_logic_vector(point_log2_r),
      active_radix4_i => fft_radix4_active_r,
      active_input_width_i => fft_config_r(15 downto 8),
      active_output_width_i => fft_config_r(23 downto 16),
      twiddle_addr_o => fftp_tw_addr,
      twiddle_re_i => fft_tw_re,
      twiddle_im_i => fft_tw_im,
      busy_o => fftp_busy,
      frame_done_o => fftp_frame_done
    );

  ifft_xcorr_i: entity work.raddsp_axis_radfft_parallel8
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      G_POINTS => G_FFT_POINTS,
      G_MAX_POINTS => G_FFT_POINTS,
      G_INVERSE_FFT => false,
      G_INPUT_WIDTH => G_FFT_INPUT_WIDTH,
      G_TWIDDLE_WIDTH => G_FFT_TWIDDLE_WIDTH,
      G_OUTPUT_WIDTH => G_FFT_OUTPUT_WIDTH,
      G_SCALE_EACH_STAGE => G_FFT_SCALE_EACH_STAGE,
      G_MULTIPLIER_LANES => G_MAX_MULTIPLIER_LANES
    )
    port map (
      clk => clk,
      rst => fifo_rst,
      s_axis_tvalid => ifft_s_valid_r,
      s_axis_tready => ifft_s_ready,
      s_axis_tdata => ifft_s_data_r,
      s_axis_tlast => ifft_s_last_r,
      m_axis_tvalid => ifft_m_valid,
      m_axis_tready => ifft_m_ready,
      m_axis_tdata => ifft_m_data,
      m_axis_tlast => ifft_m_last,
      runtime_inverse_i => '1',
      active_point_log2_i => std_logic_vector(point_log2_r),
      active_radix4_i => '0',
      active_input_width_i => fft_config_r(15 downto 8),
      active_output_width_i => fft_config_r(23 downto 16),
      twiddle_addr_o => ifft_tw_addr,
      twiddle_re_i => fft_tw_re,
      twiddle_im_i => fft_tw_im,
      busy_o => ifft_busy,
      frame_done_o => ifft_frame_done
    );

  corr_product_mul_i: entity work.raddsp_xilinx_dsp48_wide_mul
    generic map (
      DEVICE_FAMILY => DEVICE_FAMILY,
      A_WIDTH => G_FFT_OUTPUT_WIDTH,
      B_WIDTH => G_FFT_OUTPUT_WIDTH,
      PRODUCT_WIDTH => C_CORR_PRODUCT_WIDTH
    )
    port map (
      clk => clk,
      rst => fifo_rst,
      valid_i => prod_valid_r,
      a_i => prod_mul_a_r,
      b_i => prod_mul_b_r,
      valid_o => prod_done_s,
      p_o => prod_mul_p
    );

  in_fifo_i: xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE => "block",
      FIFO_WRITE_DEPTH => G_FIFO_DEPTH,
      WRITE_DATA_WIDTH => C_FIFO_WIDTH,
      READ_DATA_WIDTH => C_FIFO_WIDTH,
      READ_MODE => fifo_read_mode,
      FIFO_READ_LATENCY => fifo_read_latency,
      WR_DATA_COUNT_WIDTH => count_width(G_FIFO_DEPTH),
      RD_DATA_COUNT_WIDTH => count_width(G_FIFO_DEPTH),
      USE_ADV_FEATURES => "0707"
    )
    port map (
      almost_empty => open, almost_full => open, data_valid => in_fifo_valid,
      dbiterr => open, dout => in_fifo_dout, empty => in_fifo_empty,
      full => in_fifo_full, overflow => open, prog_empty => open, prog_full => open,
      rd_data_count => open, rd_rst_busy => open, sbiterr => open, underflow => open,
      wr_ack => open, wr_data_count => open, wr_rst_busy => open, din => in_fifo_din,
      injectdbiterr => '0', injectsbiterr => '0', rd_en => in_fifo_rd_en,
      rst => fifo_rst, sleep => '0', wr_clk => clk, wr_en => in_fifo_wr_en
    );

  out_fifo_i: xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE => "block",
      FIFO_WRITE_DEPTH => G_FIFO_DEPTH,
      WRITE_DATA_WIDTH => C_FIFO_WIDTH,
      READ_DATA_WIDTH => C_FIFO_WIDTH,
      READ_MODE => fifo_read_mode,
      FIFO_READ_LATENCY => fifo_read_latency,
      WR_DATA_COUNT_WIDTH => count_width(G_FIFO_DEPTH),
      RD_DATA_COUNT_WIDTH => count_width(G_FIFO_DEPTH),
      USE_ADV_FEATURES => "0707"
    )
    port map (
      almost_empty => open, almost_full => open, data_valid => out_fifo_valid,
      dbiterr => open, dout => out_fifo_dout, empty => out_fifo_empty,
      full => out_fifo_full, overflow => open, prog_empty => open, prog_full => open,
      rd_data_count => open, rd_rst_busy => open, sbiterr => open, underflow => open,
      wr_ack => open, wr_data_count => open, wr_rst_busy => open, din => out_fifo_din,
      injectdbiterr => '0', injectsbiterr => '0', rd_en => out_fifo_rd_en,
      rst => fifo_rst, sleep => '0', wr_clk => clk, wr_en => out_fifo_wr_en
    );

  fft_input_fifo_i: xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE => G_XCORR_MEMORY_STYLE,
      FIFO_WRITE_DEPTH => G_XCORR_FRAME_DEPTH,
      WRITE_DATA_WIDTH => C_FFT_INPUT_BITS,
      READ_DATA_WIDTH => C_FFT_INPUT_BITS,
      READ_MODE => "fwft",
      FIFO_READ_LATENCY => 0,
      WR_DATA_COUNT_WIDTH => count_width(G_XCORR_FRAME_DEPTH),
      RD_DATA_COUNT_WIDTH => count_width(G_XCORR_FRAME_DEPTH),
      USE_ADV_FEATURES => "0707"
    )
    port map (
      almost_empty => open, almost_full => open, data_valid => fft_in_fifo_valid,
      dbiterr => open, dout => fft_in_fifo_dout, empty => fft_in_fifo_empty,
      full => fft_in_fifo_full, overflow => open, prog_empty => open, prog_full => open,
      rd_data_count => open, rd_rst_busy => open, sbiterr => open, underflow => open,
      wr_ack => open, wr_data_count => open, wr_rst_busy => open, din => fft_in_fifo_din,
      injectdbiterr => '0', injectsbiterr => '0', rd_en => fft_in_fifo_rd_en,
      rst => fifo_rst, sleep => '0', wr_clk => clk, wr_en => fft_in_fifo_wr_en
    );

  xcorr_a_fifo_i: xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE => G_XCORR_MEMORY_STYLE,
      FIFO_WRITE_DEPTH => G_XCORR_FRAME_DEPTH,
      WRITE_DATA_WIDTH => C_FFT_OUTPUT_BITS,
      READ_DATA_WIDTH => C_FFT_OUTPUT_BITS,
      READ_MODE => "fwft",
      FIFO_READ_LATENCY => 0,
      WR_DATA_COUNT_WIDTH => count_width(G_XCORR_FRAME_DEPTH),
      RD_DATA_COUNT_WIDTH => count_width(G_XCORR_FRAME_DEPTH),
      USE_ADV_FEATURES => "0707"
    )
    port map (
      almost_empty => open, almost_full => open, data_valid => xcorr_a_fifo_valid,
      dbiterr => open, dout => xcorr_a_fifo_dout, empty => xcorr_a_fifo_empty,
      full => xcorr_a_fifo_full, overflow => open, prog_empty => open, prog_full => open,
      rd_data_count => open, rd_rst_busy => open, sbiterr => open, underflow => open,
      wr_ack => open, wr_data_count => open, wr_rst_busy => open, din => xcorr_a_fifo_din,
      injectdbiterr => '0', injectsbiterr => '0', rd_en => xcorr_a_fifo_rd_en,
      rst => fifo_rst, sleep => '0', wr_clk => clk, wr_en => xcorr_a_fifo_wr_en
    );

  xcorr_product_fifo_i: xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE => G_XCORR_MEMORY_STYLE,
      FIFO_WRITE_DEPTH => G_XCORR_FRAME_DEPTH,
      WRITE_DATA_WIDTH => C_FFT_INPUT_BITS,
      READ_DATA_WIDTH => C_FFT_INPUT_BITS,
      READ_MODE => "fwft",
      FIFO_READ_LATENCY => 0,
      WR_DATA_COUNT_WIDTH => count_width(G_XCORR_FRAME_DEPTH),
      RD_DATA_COUNT_WIDTH => count_width(G_XCORR_FRAME_DEPTH),
      USE_ADV_FEATURES => "0707"
    )
    port map (
      almost_empty => open, almost_full => open, data_valid => xcorr_p_fifo_valid,
      dbiterr => open, dout => xcorr_p_fifo_dout, empty => xcorr_p_fifo_empty,
      full => xcorr_p_fifo_full, overflow => open, prog_empty => open, prog_full => open,
      rd_data_count => open, rd_rst_busy => open, sbiterr => open, underflow => open,
      wr_ack => open, wr_data_count => open, wr_rst_busy => open, din => xcorr_p_fifo_din,
      injectdbiterr => '0', injectsbiterr => '0', rd_en => xcorr_p_fifo_rd_en,
      rst => fifo_rst, sleep => '0', wr_clk => clk, wr_en => xcorr_p_fifo_wr_en
    );

  process(clk)
    variable idx : natural;
    variable next_beats : unsigned(8 downto 0);
    variable burst_bytes : unsigned(31 downto 0);
    variable active_points_v : natural;
    variable active_input_width_v : natural;
    variable active_output_width_v : natural;
    variable active_lanes_v : natural;
    variable active_frame_bytes_v : natural;
    variable active_batch_count_v : unsigned(31 downto 0);
    variable active_src_stride_v : unsigned(31 downto 0);
    variable active_dst_stride_v : unsigned(31 downto 0);
    variable next_in_base_v : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0);
    variable next_out_base_v : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0);
    variable scratch_product_base_v : unsigned(G_AXI_ADDR_WIDTH - 1 downto 0);
    variable corr_re_v : signed(C_CORR_PRODUCT_WIDTH downto 0);
    variable corr_im_v : signed(C_CORR_PRODUCT_WIDTH downto 0);
    variable corr_re_out_v : signed(G_FFT_INPUT_WIDTH - 1 downto 0);
    variable corr_im_out_v : signed(G_FFT_INPUT_WIDTH - 1 downto 0);
    variable fast_a_re_v : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0);
    variable fast_a_im_v : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0);
    variable fast_b_re_v : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0);
    variable fast_b_im_v : signed(G_FFT_OUTPUT_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      axil_awready_r <= '0';
      axil_wready_r <= '0';
      axil_arready_r <= '0';
      in_fifo_rd_en <= '0';
      out_fifo_wr_en <= '0';
      out_fifo_rd_en <= '0';
      fft_in_fifo_wr_en <= '0';
      fft_in_fifo_rd_en <= '0';
      xcorr_a_fifo_wr_en <= '0';
      xcorr_a_fifo_rd_en <= '0';
      xcorr_p_fifo_wr_en <= '0';
      xcorr_p_fifo_rd_en <= '0';
      tw_cache_a_we <= '0';
      prod_valid_r <= '0';
      if ifft_s_valid_r = '1' and ifft_s_ready = '1' then
        ifft_s_valid_r <= '0';
        ifft_s_last_r <= '0';
      end if;

      if rstn = '0' then
        control_r <= (others => '0');
        status_r <= (others => '0');
        base_addr_r <= (others => '0');
        out_addr_r <= (others => '0');
        corr_b_addr_r <= (others => '0');
        corr_scratch_addr_r <= (others => '0');
        twiddle_addr_r <= (others => '0');
        region_bytes_r <= to_unsigned(G_DEFAULT_REGION_BYTES, 32);
        length_bytes_r <= (others => '0');
        batch_count_r <= to_unsigned(1, 32);
        batch_total_r <= to_unsigned(1, 32);
        batch_remaining_r <= (others => '0');
        batch_done_count_r <= (others => '0');
        src_stride_bytes_r <= (others => '0');
        dst_stride_bytes_r <= (others => '0');
        active_src_stride_r <= (others => '0');
        active_dst_stride_r <= (others => '0');
        fft_frame_bytes_r <= (others => '0');
        point_log2_r <= to_unsigned(ceil_log2(G_FFT_POINTS), 8);
        burst_beats_r <= to_unsigned(G_MAX_BURST_BEATS, 8);
        fft_config_r <= (others => '0');
        fft_config_r(0) <= default_radix4;
        irq_enable_r <= '1';
        fft_radix4_active_r <= '0';
        fft_parallel_active_r <= '0';
        op_r <= OP_IDLE;
        wr_state_r <= WR_IDLE;
        rd_state_r <= RD_IDLE;
        wr_addr_r <= (others => '0');
        rd_addr_r <= (others => '0');
        wr_remaining_r <= (others => '0');
        rd_remaining_r <= (others => '0');
        wr_fifo_advance_r <= '0';
        tw_state_r <= TW_IDLE;
        tw_addr_r <= (others => '0');
        tw_remaining_r <= (others => '0');
        tw_load_index_r <= (others => '0');
        fft_in_state_r <= FFT_IN_IDLE;
        fft_out_state_r <= FFT_OUT_IDLE;
        fft_in_frame_base_r <= (others => '0');
        fft_out_frame_base_r <= (others => '0');
        fft_in_addr_r <= (others => '0');
        fft_out_addr_r <= (others => '0');
        fft_in_remaining_r <= (others => '0');
        fft_feed_remaining_r <= (others => '0');
        fft_out_remaining_r <= (others => '0');
        fft_s_valid_r <= '0';
        fft_s_last_r <= '0';
        ifft_s_valid_r <= '0';
        ifft_s_last_r <= '0';
        ifft_in_remaining_r <= (others => '0');
        fft_m_ready_r <= '0';
        fft_runtime_inverse_r <= '0';
        xcorr_phase_r <= XCORR_FFT_A;
        prod_state_r <= PROD_IDLE;
        prod_a_addr_r <= (others => '0');
        prod_b_addr_r <= (others => '0');
        prod_out_addr_r <= (others => '0');
        prod_remaining_r <= (others => '0');
        prod_a_word_r <= (others => '0');
        prod_b_word_r <= (others => '0');
        prod_a_re_r <= (others => '0');
        prod_a_im_r <= (others => '0');
        prod_b_re_r <= (others => '0');
        prod_b_im_r <= (others => '0');
        prod_mul_a_r <= (others => '0');
        prod_mul_b_r <= (others => '0');
        prod_mul_phase_r <= 0;
        prod_re_acc_r <= (others => '0');
        prod_im_acc_r <= (others => '0');
        xcorr_fast_local_r <= '0';
        xcorr_store_index_r <= 0;
        xcorr_a_advance_r <= '0';
        xcorr_a_wait_r <= '0';
        xcorr_b_skid_valid_r <= '0';
        xcorr_b_skid_last_r <= '0';
        awvalid_r <= '0';
        wvalid_r <= '0';
        bready_r <= '0';
        arvalid_r <= '0';
        rready_r <= '0';
        wlast_r <= '0';
        axil_bvalid_r <= '0';
        axil_rvalid_r <= '0';
        out_word_valid_r <= '0';
      else
        status_r(0) <= '1' when op_r /= OP_IDLE else '0';
        status_r(8) <= in_fifo_full;
        status_r(9) <= out_fifo_empty;
        status_r(10) <= out_fifo_full;

        if axil_bvalid_r = '1' and s_axi_bready = '1' then
          axil_bvalid_r <= '0';
        end if;

        if axil_rvalid_r = '1' and s_axi_rready = '1' then
          axil_rvalid_r <= '0';
        end if;

        if axil_bvalid_r = '0' and s_axi_awvalid = '1' and s_axi_wvalid = '1' then
          axil_awready_r <= '1';
          axil_wready_r <= '1';
          axil_bvalid_r <= '1';
          axil_bresp_r <= "00";
          idx := reg_index(s_axi_awaddr);
          case idx is
            when 0 =>
              control_r <= s_axi_wdata;
              irq_enable_r <= s_axi_wdata(8);
              if s_axi_wdata(31) = '1' then
                status_r(1) <= '0';
                status_r(2) <= '0';
                status_r(3) <= '0';
              end if;
              if s_axi_wdata(0) = '1' and op_r = OP_IDLE then
                status_r(1) <= '0';
                status_r(2) <= '0';
                status_r(3) <= '0';
                if s_axi_wdata(5 downto 4) = "00" then
                  op_r <= OP_AXIS_TO_DDR;
                  wr_state_r <= WR_IDLE;
                  wr_addr_r <= base_addr_r;
                  wr_remaining_r <= length_bytes_r;
                  wr_fifo_advance_r <= '0';
                elsif s_axi_wdata(5 downto 4) = "01" then
                  op_r <= OP_DDR_TO_AXIS;
                  rd_state_r <= RD_IDLE;
                  rd_addr_r <= base_addr_r;
                  rd_remaining_r <= length_bytes_r;
                elsif s_axi_wdata(5 downto 4) = "10" then
                  active_points_v := point_count(point_log2_r);
                  active_input_width_v := width_from_code(fft_config_r(10 downto 8));
                  active_output_width_v := width_from_code(fft_config_r(14 downto 12));
                  active_lanes_v := lanes_from_code(fft_config_r(17 downto 16));
                  active_frame_bytes_v := active_points_v * C_AXI_BYTES;
                  active_batch_count_v := batch_count_r;
                  if active_batch_count_v = 0 then
                    active_batch_count_v := to_unsigned(1, 32);
                  end if;
                  active_src_stride_v := src_stride_bytes_r;
                  if active_src_stride_v = 0 then
                    active_src_stride_v := to_unsigned(active_frame_bytes_v, 32);
                  end if;
                  active_dst_stride_v := dst_stride_bytes_r;
                  if active_dst_stride_v = 0 then
                    active_dst_stride_v := to_unsigned(active_frame_bytes_v, 32);
                  end if;
                  if active_points_v > G_FFT_POINTS or
                     active_input_width_v = 0 or active_input_width_v > G_FFT_INPUT_WIDTH or
                     active_output_width_v = 0 or active_output_width_v > G_FFT_OUTPUT_WIDTH or
                     active_lanes_v > G_MAX_MULTIPLIER_LANES or
                     length_bytes_r /= to_unsigned(active_frame_bytes_v, 32) or
                     twiddle_addr_r = 0 or
                     (fft_config_r(6) = '1' and
                      (fft_config_r(4) = '1' or fft_config_r(5) = '1' or
                       corr_b_addr_r = 0 or corr_scratch_addr_r = 0 or out_addr_r = 0)) then
                    op_r <= OP_UNSUPPORTED_FFT;
                    status_r(2) <= '1';
                    status_r(3) <= '1';
                  else
                    if fft_config_r(6) = '1' then
                      op_r <= OP_DDR_XCORR;
                      xcorr_phase_r <= XCORR_FFT_A;
                      report "RADFFT DDR xcorr start @" & time'image(now);
                    else
                      op_r <= OP_DDR_FFT;
                    end if;
                    fft_radix4_active_r <= fft_config_r(0);
                    fft_parallel_active_r <= '1' when active_lanes_v = 8 and fft_config_r(0) = '0' else '0';
                    xcorr_fast_local_r <= '1' when G_XCORR_ENABLE and fft_config_r(6) = '1' and active_lanes_v = 8 and fft_config_r(0) = '0' else '0';
                    xcorr_store_index_r <= 0;
                    xcorr_a_advance_r <= '0';
                    xcorr_a_wait_r <= '0';
                    xcorr_b_skid_valid_r <= '0';
                    xcorr_b_skid_last_r <= '0';
                    ifft_in_remaining_r <= (others => '0');
                    batch_total_r <= active_batch_count_v;
                    batch_remaining_r <= active_batch_count_v;
                    batch_done_count_r <= (others => '0');
                    active_src_stride_r <= active_src_stride_v;
                    active_dst_stride_r <= active_dst_stride_v;
                    fft_frame_bytes_r <= to_unsigned(active_frame_bytes_v, 32);
                    tw_state_r <= TW_IDLE;
                    tw_addr_r <= twiddle_addr_r;
                    tw_remaining_r <= to_unsigned(active_frame_bytes_v, 32);
                    tw_load_index_r <= (others => '0');
                    fft_in_state_r <= FFT_IN_IDLE;
                    fft_out_state_r <= FFT_OUT_IDLE;
                    fft_runtime_inverse_r <= '0';
                    prod_state_r <= PROD_IDLE;
                    prod_remaining_r <= (others => '0');
                    if fft_config_r(6) = '1' then
                      fft_in_frame_base_r <= base_addr_r;
                      fft_in_addr_r <= base_addr_r;
                      fft_out_frame_base_r <= corr_scratch_addr_r;
                      fft_out_addr_r <= corr_scratch_addr_r;
                    else
                      fft_in_frame_base_r <= base_addr_r;
                      fft_in_addr_r <= base_addr_r;
                      if out_addr_r = 0 then
                        fft_out_frame_base_r <= base_addr_r;
                        fft_out_addr_r <= base_addr_r;
                      else
                        fft_out_frame_base_r <= out_addr_r;
                        fft_out_addr_r <= out_addr_r;
                      end if;
                    end if;
                    fft_in_remaining_r <= to_unsigned(active_frame_bytes_v, 32);
                    fft_feed_remaining_r <= to_unsigned(active_frame_bytes_v, 32);
                    fft_out_remaining_r <= to_unsigned(active_frame_bytes_v, 32);
                    fft_s_valid_r <= '0';
                    fft_s_last_r <= '0';
                    fft_m_ready_r <= '0';
                  end if;
                else
                  op_r <= OP_UNSUPPORTED_FFT;
                  status_r(2) <= '1';
                  status_r(3) <= '1';
                end if;
              end if;
            when 2 => base_addr_r <= set_addr_low(base_addr_r, s_axi_wdata);
            when 3 => base_addr_r <= set_addr_high(base_addr_r, s_axi_wdata);
            when 4 => out_addr_r <= set_addr_low(out_addr_r, s_axi_wdata);
            when 5 => out_addr_r <= set_addr_high(out_addr_r, s_axi_wdata);
            when 6 => length_bytes_r <= unsigned(s_axi_wdata);
            when 7 => region_bytes_r <= unsigned(s_axi_wdata);
            when 8 => point_log2_r <= unsigned(s_axi_wdata(7 downto 0));
            when 9 =>
              if unsigned(s_axi_wdata(7 downto 0)) = 0 then
                burst_beats_r <= to_unsigned(1, 8);
              elsif unsigned(s_axi_wdata(7 downto 0)) > to_unsigned(G_MAX_BURST_BEATS, 8) then
                burst_beats_r <= to_unsigned(G_MAX_BURST_BEATS, 8);
              else
                burst_beats_r <= unsigned(s_axi_wdata(7 downto 0));
              end if;
            when 12 => twiddle_addr_r <= set_addr_low(twiddle_addr_r, s_axi_wdata);
            when 13 => twiddle_addr_r <= set_addr_high(twiddle_addr_r, s_axi_wdata);
            when 14 => fft_config_r <= s_axi_wdata;
            when 18 =>
              if s_axi_wdata = x"00000000" then
                batch_count_r <= to_unsigned(1, 32);
              else
                batch_count_r <= unsigned(s_axi_wdata);
              end if;
            when 19 => src_stride_bytes_r <= unsigned(s_axi_wdata);
            when 20 => dst_stride_bytes_r <= unsigned(s_axi_wdata);
            when 22 => corr_b_addr_r <= set_addr_low(corr_b_addr_r, s_axi_wdata);
            when 23 => corr_b_addr_r <= set_addr_high(corr_b_addr_r, s_axi_wdata);
            when 24 => corr_scratch_addr_r <= set_addr_low(corr_scratch_addr_r, s_axi_wdata);
            when 25 => corr_scratch_addr_r <= set_addr_high(corr_scratch_addr_r, s_axi_wdata);
            when others =>
              axil_bresp_r <= "10";
              status_r(2) <= '1';
          end case;
        end if;

        if axil_rvalid_r = '0' and s_axi_arvalid = '1' then
          axil_arready_r <= '1';
          axil_rvalid_r <= '1';
          axil_rresp_r <= "00";
          axil_rdata_r <= (others => '0');
          idx := reg_index(s_axi_araddr);
          case idx is
            when 0 => axil_rdata_r <= control_r;
            when 1 => axil_rdata_r <= status_r;
            when 2 => axil_rdata_r <= addr_low(base_addr_r);
            when 3 => axil_rdata_r <= addr_high(base_addr_r);
            when 4 => axil_rdata_r <= addr_low(out_addr_r);
            when 5 => axil_rdata_r <= addr_high(out_addr_r);
            when 6 => axil_rdata_r <= std_logic_vector(length_bytes_r);
            when 7 => axil_rdata_r <= std_logic_vector(region_bytes_r);
            when 8 =>
              axil_rdata_r(7 downto 0) <= std_logic_vector(point_log2_r);
              axil_rdata_r(23 downto 16) <= std_logic_vector(to_unsigned(C_AXI_BYTES, 8));
            when 9 => axil_rdata_r(7 downto 0) <= std_logic_vector(burst_beats_r);
            when 10 => axil_rdata_r <= std_logic_vector(resize(wr_addr_r, 32));
            when 11 => axil_rdata_r <= std_logic_vector(resize(rd_addr_r, 32));
            when 12 => axil_rdata_r <= addr_low(twiddle_addr_r);
            when 13 => axil_rdata_r <= addr_high(twiddle_addr_r);
            when 14 => axil_rdata_r <= fft_config_r;
            when 15 => axil_rdata_r <= x"52464444";
            when 16 =>
              axil_rdata_r(7 downto 0) <= std_logic_vector(to_unsigned(ceil_log2(G_FFT_POINTS), 8));
              axil_rdata_r(15 downto 8) <= std_logic_vector(to_unsigned(G_FFT_INPUT_WIDTH, 8));
              axil_rdata_r(23 downto 16) <= std_logic_vector(to_unsigned(G_FFT_OUTPUT_WIDTH, 8));
              axil_rdata_r(31 downto 24) <= std_logic_vector(to_unsigned(G_FFT_TWIDDLE_WIDTH, 8));
            when 17 =>
              axil_rdata_r(0) <= '1';
              axil_rdata_r(1) <= '1' when is_power_of_four(G_FFT_POINTS) else '0';
              axil_rdata_r(2) <= '1';
              axil_rdata_r(3) <= '1';
              axil_rdata_r(15 downto 8) <= std_logic_vector(to_unsigned(G_MAX_MULTIPLIER_LANES, 8));
              axil_rdata_r(23 downto 16) <= std_logic_vector(to_unsigned(C_AXI_BYTES, 8));
              axil_rdata_r(31 downto 24) <= std_logic_vector(to_unsigned(G_MAX_BURST_BEATS, 8));
            when 18 => axil_rdata_r <= std_logic_vector(batch_count_r);
            when 19 => axil_rdata_r <= std_logic_vector(src_stride_bytes_r);
            when 20 => axil_rdata_r <= std_logic_vector(dst_stride_bytes_r);
            when 21 => axil_rdata_r <= std_logic_vector(batch_done_count_r);
            when 22 => axil_rdata_r <= addr_low(corr_b_addr_r);
            when 23 => axil_rdata_r <= addr_high(corr_b_addr_r);
            when 24 => axil_rdata_r <= addr_low(corr_scratch_addr_r);
            when 25 => axil_rdata_r <= addr_high(corr_scratch_addr_r);
            when others =>
              axil_rresp_r <= "10";
              status_r(2) <= '1';
          end case;
        end if;

        if out_word_valid_r = '1' then
          if m_axis_tready = '1' then
            out_word_valid_r <= '0';
          end if;
        elsif G_FIFO_FWFT and out_fifo_empty = '0' then
          out_word_last_r <= out_fifo_dout(C_FIFO_WIDTH - 1);
          out_word_data_r <= out_fifo_dout(G_AXIS_DATA_WIDTH - 1 downto 0);
          out_word_valid_r <= '1';
          out_fifo_rd_en <= '1';
        elsif (not G_FIFO_FWFT) and out_fifo_empty = '0' then
          out_fifo_rd_en <= '1';
          if out_fifo_valid = '1' then
            out_word_last_r <= out_fifo_dout(C_FIFO_WIDTH - 1);
            out_word_data_r <= out_fifo_dout(G_AXIS_DATA_WIDTH - 1 downto 0);
            out_word_valid_r <= '1';
          end if;
        end if;

        case op_r is
          when OP_AXIS_TO_DDR =>
            case wr_state_r is
              when WR_IDLE =>
                if wr_remaining_r = 0 then
                  op_r <= OP_IDLE;
                  status_r(1) <= '1';
                elsif in_fifo_empty = '0' then
                  next_beats := bytes_to_beats(wr_remaining_r, resize(burst_beats_r, 9));
                  wr_burst_beats_r <= next_beats;
                  wr_beat_index_r <= (others => '0');
                  awaddr_r <= std_logic_vector(wr_addr_r);
                  awlen_r <= std_logic_vector(resize(next_beats - 1, 8));
                  awvalid_r <= '1';
                  wr_state_r <= WR_AW;
                end if;

              when WR_AW =>
                if m_axi_awready = '1' then
                  awvalid_r <= '0';
                  wr_state_r <= WR_W;
                end if;

              when WR_W =>
                if wr_fifo_advance_r = '1' then
                  wr_fifo_advance_r <= '0';
                elsif wvalid_r = '0' and in_fifo_empty = '0' then
                  wdata_r <= in_fifo_dout(G_AXI_DATA_WIDTH - 1 downto 0);
                  wlast_r <= '1' when wr_beat_index_r = wr_burst_beats_r - 1 else '0';
                  wvalid_r <= '1';
                elsif wvalid_r = '1' and m_axi_wready = '1' then
                  in_fifo_rd_en <= '1';
                  wvalid_r <= '0';
                  if wlast_r = '1' then
                    bready_r <= '1';
                    wr_state_r <= WR_B;
                  else
                    wr_beat_index_r <= wr_beat_index_r + 1;
                    wr_fifo_advance_r <= '1';
                  end if;
                end if;

              when WR_B =>
                if m_axi_bvalid = '1' then
                  bready_r <= '0';
                  if m_axi_bresp /= "00" then
                    status_r(2) <= '1';
                    status_r(3) <= '1';
                    op_r <= OP_IDLE;
                  else
                    burst_bytes := resize(wr_burst_beats_r, 32) sll ceil_log2(C_AXI_BYTES);
                    wr_addr_r <= wr_addr_r + resize(burst_bytes, wr_addr_r'length);
                    if wr_remaining_r <= burst_bytes then
                      wr_remaining_r <= (others => '0');
                    else
                      wr_remaining_r <= wr_remaining_r - burst_bytes;
                    end if;
                    wr_state_r <= WR_IDLE;
                  end if;
                end if;
            end case;

          when OP_DDR_TO_AXIS =>
            case rd_state_r is
              when RD_IDLE =>
                if rd_remaining_r = 0 then
                  op_r <= OP_IDLE;
                  status_r(1) <= '1';
                elsif out_fifo_full = '0' then
                  next_beats := bytes_to_beats(rd_remaining_r, resize(burst_beats_r, 9));
                  rd_burst_beats_r <= next_beats;
                  rd_beat_index_r <= (others => '0');
                  araddr_r <= std_logic_vector(rd_addr_r);
                  arlen_r <= std_logic_vector(resize(next_beats - 1, 8));
                  arvalid_r <= '1';
                  rd_state_r <= RD_AR;
                end if;

              when RD_AR =>
                if m_axi_arready = '1' then
                  arvalid_r <= '0';
                  rready_r <= '1';
                  rd_state_r <= RD_R;
                end if;

              when RD_R =>
                rready_r <= not out_fifo_full;
                if m_axi_rvalid = '1' and out_fifo_full = '0' then
                  out_fifo_din <= '0' & m_axi_rdata(G_AXIS_DATA_WIDTH - 1 downto 0);
                  if rd_remaining_r <= to_unsigned(C_AXI_BYTES, rd_remaining_r'length) or rd_beat_index_r = rd_burst_beats_r - 1 then
                    out_fifo_din(C_FIFO_WIDTH - 1) <= '1';
                  end if;
                  out_fifo_wr_en <= '1';
                  if m_axi_rresp /= "00" then
                    status_r(2) <= '1';
                    status_r(3) <= '1';
                    op_r <= OP_IDLE;
                    rready_r <= '0';
                  elsif rd_beat_index_r = rd_burst_beats_r - 1 or m_axi_rlast = '1' then
                    burst_bytes := resize(rd_burst_beats_r, 32) sll ceil_log2(C_AXI_BYTES);
                    rd_addr_r <= rd_addr_r + resize(burst_bytes, rd_addr_r'length);
                    if rd_remaining_r <= burst_bytes then
                      rd_remaining_r <= (others => '0');
                    else
                      rd_remaining_r <= rd_remaining_r - burst_bytes;
                    end if;
                    rready_r <= '0';
                    rd_state_r <= RD_IDLE;
                  else
                    rd_beat_index_r <= rd_beat_index_r + 1;
                  end if;
                end if;
            end case;

          when OP_DDR_FFT | OP_DDR_XCORR =>
            if fft_s_valid_r = '1' and fft_s_ready = '1' then
              fft_s_valid_r <= '0';
              fft_s_last_r <= '0';
            end if;

            case tw_state_r is
              when TW_IDLE =>
                if tw_remaining_r = 0 then
                  tw_state_r <= TW_DONE;
                  rready_r <= '0';
                else
                  next_beats := bytes_to_beats(tw_remaining_r, resize(burst_beats_r, 9));
                  tw_burst_beats_r <= next_beats;
                  tw_beat_index_r <= (others => '0');
                  araddr_r <= std_logic_vector(tw_addr_r);
                  arlen_r <= std_logic_vector(resize(next_beats - 1, 8));
                  arvalid_r <= '1';
                  tw_state_r <= TW_AR;
                end if;

              when TW_AR =>
                if m_axi_arready = '1' then
                  arvalid_r <= '0';
                  rready_r <= '1';
                  tw_state_r <= TW_R;
                end if;

              when TW_R =>
                rready_r <= '1';
                if m_axi_rvalid = '1' and rready_r = '1' then
                  tw_cache_a_addr <= std_logic_vector(tw_load_index_r);
                  tw_cache_a_din <= m_axi_rdata(C_TW_WORD_WIDTH - 1 downto 0);
                  tw_cache_a_we <= '1';
                  tw_load_index_r <= tw_load_index_r + 1;
                  if m_axi_rresp /= "00" then
                    status_r(2) <= '1';
                    status_r(3) <= '1';
                    op_r <= OP_IDLE;
                    rready_r <= '0';
                  elsif tw_beat_index_r = tw_burst_beats_r - 1 or m_axi_rlast = '1' then
                    burst_bytes := resize(tw_burst_beats_r, 32) sll ceil_log2(C_AXI_BYTES);
                    tw_addr_r <= tw_addr_r + resize(burst_bytes, tw_addr_r'length);
                    if tw_remaining_r <= burst_bytes then
                      tw_remaining_r <= (others => '0');
                    else
                      tw_remaining_r <= tw_remaining_r - burst_bytes;
                    end if;
                    rready_r <= '0';
                    tw_state_r <= TW_IDLE;
                  else
                    tw_beat_index_r <= tw_beat_index_r + 1;
                  end if;
                end if;

              when TW_DONE =>
                rready_r <= '0';
            end case;

            if op_r = OP_DDR_XCORR and xcorr_phase_r = XCORR_PRODUCT and tw_state_r = TW_DONE then
              case prod_state_r is
                when PROD_IDLE =>
                  if prod_remaining_r = 0 then
                    prod_state_r <= PROD_DONE;
                  else
                    araddr_r <= std_logic_vector(prod_a_addr_r);
                    arlen_r <= (others => '0');
                    arvalid_r <= '1';
                    prod_state_r <= PROD_AR_A;
                  end if;

                when PROD_AR_A =>
                  if m_axi_arready = '1' then
                    arvalid_r <= '0';
                    rready_r <= '1';
                    prod_state_r <= PROD_R_A;
                  end if;

                when PROD_R_A =>
                  rready_r <= '1';
                  if m_axi_rvalid = '1' and rready_r = '1' then
                    prod_a_word_r <= m_axi_rdata;
                    rready_r <= '0';
                    if m_axi_rresp /= "00" then
                      status_r(2) <= '1';
                      status_r(3) <= '1';
                      op_r <= OP_IDLE;
                    else
                      araddr_r <= std_logic_vector(prod_b_addr_r);
                      arlen_r <= (others => '0');
                      arvalid_r <= '1';
                      prod_state_r <= PROD_AR_B;
                    end if;
                  end if;

                when PROD_AR_B =>
                  if m_axi_arready = '1' then
                    arvalid_r <= '0';
                    rready_r <= '1';
                    prod_state_r <= PROD_R_B;
                  end if;

                when PROD_R_B =>
                  rready_r <= '1';
                  if m_axi_rvalid = '1' and rready_r = '1' then
                    prod_b_word_r <= m_axi_rdata;
                    rready_r <= '0';
                    if m_axi_rresp /= "00" then
                      status_r(2) <= '1';
                      status_r(3) <= '1';
                      op_r <= OP_IDLE;
                    else
                      prod_a_re_r <= sample_re(prod_a_word_r(C_FFT_OUTPUT_BITS - 1 downto 0));
                      prod_a_im_r <= sample_im(prod_a_word_r(C_FFT_OUTPUT_BITS - 1 downto 0));
                      prod_b_re_r <= sample_re(m_axi_rdata(C_FFT_OUTPUT_BITS - 1 downto 0));
                      prod_b_im_r <= sample_im(m_axi_rdata(C_FFT_OUTPUT_BITS - 1 downto 0));
                      prod_mul_a_r <= sample_re(prod_a_word_r(C_FFT_OUTPUT_BITS - 1 downto 0));
                      prod_mul_b_r <= sample_re(m_axi_rdata(C_FFT_OUTPUT_BITS - 1 downto 0));
                      prod_mul_phase_r <= 0;
                      prod_re_acc_r <= (others => '0');
                      prod_im_acc_r <= (others => '0');
                      prod_state_r <= PROD_MUL_START;
                    end if;
                  end if;

                when PROD_MUL_START =>
                  prod_valid_r <= '1';
                  prod_state_r <= PROD_MUL_WAIT;

                when PROD_MUL_WAIT =>
                  if prod_done_s = '1' then
                    case prod_mul_phase_r is
                      when 0 =>
                        prod_re_acc_r <= resize(prod_mul_p, prod_re_acc_r'length);
                        prod_mul_a_r <= prod_a_im_r;
                        prod_mul_b_r <= prod_b_im_r;
                        prod_mul_phase_r <= 1;
                        prod_state_r <= PROD_MUL_START;

                      when 1 =>
                        prod_re_acc_r <= prod_re_acc_r + resize(prod_mul_p, prod_re_acc_r'length);
                        prod_mul_a_r <= prod_a_im_r;
                        prod_mul_b_r <= prod_b_re_r;
                        prod_mul_phase_r <= 2;
                        prod_state_r <= PROD_MUL_START;

                      when 2 =>
                        prod_im_acc_r <= resize(prod_mul_p, prod_im_acc_r'length);
                        prod_mul_a_r <= prod_a_re_r;
                        prod_mul_b_r <= prod_b_im_r;
                        prod_mul_phase_r <= 3;
                        prod_state_r <= PROD_MUL_START;

                      when others =>
                        corr_re_v := prod_re_acc_r;
                        corr_im_v := prod_im_acc_r - resize(prod_mul_p, prod_im_acc_r'length);
                        corr_re_out_v := resize(corr_re_v, G_FFT_INPUT_WIDTH);
                        corr_im_out_v := resize(corr_im_v, G_FFT_INPUT_WIDTH);
                        wdata_r <= (others => '0');
                        wdata_r(C_FFT_INPUT_BITS - 1 downto G_FFT_INPUT_WIDTH) <= std_logic_vector(corr_re_out_v);
                        wdata_r(G_FFT_INPUT_WIDTH - 1 downto 0) <= std_logic_vector(corr_im_out_v);
                        awaddr_r <= std_logic_vector(prod_out_addr_r);
                        awlen_r <= (others => '0');
                        awvalid_r <= '1';
                        prod_state_r <= PROD_AW;
                    end case;
                  end if;

                when PROD_AW =>
                  if m_axi_awready = '1' then
                    awvalid_r <= '0';
                    wlast_r <= '1';
                    wvalid_r <= '1';
                    prod_state_r <= PROD_W;
                  end if;

                when PROD_W =>
                  if m_axi_wready = '1' and wvalid_r = '1' then
                    wvalid_r <= '0';
                    wlast_r <= '0';
                    bready_r <= '1';
                    prod_state_r <= PROD_B;
                  end if;

                when PROD_B =>
                  if m_axi_bvalid = '1' then
                    bready_r <= '0';
                    if m_axi_bresp /= "00" then
                      status_r(2) <= '1';
                      status_r(3) <= '1';
                      op_r <= OP_IDLE;
                    else
                      prod_a_addr_r <= prod_a_addr_r + to_unsigned(C_AXI_BYTES, prod_a_addr_r'length);
                      prod_b_addr_r <= prod_b_addr_r + to_unsigned(C_AXI_BYTES, prod_b_addr_r'length);
                      prod_out_addr_r <= prod_out_addr_r + to_unsigned(C_AXI_BYTES, prod_out_addr_r'length);
                      if prod_remaining_r <= to_unsigned(C_AXI_BYTES, prod_remaining_r'length) then
                        prod_remaining_r <= (others => '0');
                      else
                        prod_remaining_r <= prod_remaining_r - to_unsigned(C_AXI_BYTES, prod_remaining_r'length);
                      end if;
                      prod_state_r <= PROD_IDLE;
                    end if;
                  end if;

                when PROD_DONE =>
                  null;
              end case;
            elsif tw_state_r = TW_DONE and fft_config_r(4) = '1' then
              case fft_in_state_r is
                when FFT_IN_IDLE =>
                  if fft_in_remaining_r = 0 then
                    fft_in_state_r <= FFT_IN_DONE;
                  elsif fft_s_valid_r = '0' and s_axis_tvalid = '1' and s_axis_tready = '1' then
                    fft_s_data_r <= s_axis_tdata(C_FFT_INPUT_BITS - 1 downto 0);
                    fft_s_valid_r <= '1';
                    fft_s_last_r <= '1' when fft_in_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or s_axis_tlast = '1' else '0';
                    if fft_in_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or s_axis_tlast = '1' then
                      fft_in_remaining_r <= (others => '0');
                      fft_in_state_r <= FFT_IN_DONE;
                    else
                      fft_in_remaining_r <= fft_in_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                    end if;
                  end if;

                when FFT_IN_AR | FFT_IN_R =>
                  fft_in_state_r <= FFT_IN_IDLE;

                when FFT_IN_DONE =>
                  null;
              end case;
            elsif tw_state_r = TW_DONE then
              case fft_in_state_r is
                when FFT_IN_IDLE =>
                  if fft_in_remaining_r = 0 then
                    fft_in_state_r <= FFT_IN_DONE;
                    rready_r <= '0';
                  elsif fft_s_valid_r = '0' then
                    next_beats := bytes_to_beats(fft_in_remaining_r, resize(burst_beats_r, 9));
                    fft_in_burst_beats_r <= next_beats;
                    fft_in_beat_index_r <= (others => '0');
                    araddr_r <= std_logic_vector(fft_in_addr_r);
                    arlen_r <= std_logic_vector(resize(next_beats - 1, 8));
                    arvalid_r <= '1';
                    fft_in_state_r <= FFT_IN_AR;
                  end if;

                when FFT_IN_AR =>
                  if m_axi_arready = '1' then
                    arvalid_r <= '0';
                    rready_r <= '1';
                    fft_in_state_r <= FFT_IN_R;
                  end if;

                when FFT_IN_R =>
                  rready_r <= '1' when fft_s_valid_r = '0' else '0';
                  if m_axi_rvalid = '1' and rready_r = '1' then
                    fft_s_data_r <= m_axi_rdata(C_FFT_INPUT_BITS - 1 downto 0);
                    fft_s_valid_r <= '1';
                    fft_s_last_r <= '1' when fft_in_remaining_r <= to_unsigned(C_AXI_BYTES, 32) else '0';
                    if m_axi_rresp /= "00" then
                      status_r(2) <= '1';
                      status_r(3) <= '1';
                      op_r <= OP_IDLE;
                      rready_r <= '0';
                    elsif fft_in_beat_index_r = fft_in_burst_beats_r - 1 or m_axi_rlast = '1' then
                      burst_bytes := resize(fft_in_burst_beats_r, 32) sll ceil_log2(C_AXI_BYTES);
                      fft_in_addr_r <= fft_in_addr_r + resize(burst_bytes, fft_in_addr_r'length);
                    if fft_in_remaining_r <= burst_bytes then
                      fft_in_remaining_r <= (others => '0');
                    else
                        fft_in_remaining_r <= fft_in_remaining_r - burst_bytes;
                      end if;
                      rready_r <= '0';
                      fft_in_state_r <= FFT_IN_IDLE;
                    else
                      fft_in_beat_index_r <= fft_in_beat_index_r + 1;
                    end if;
                  end if;

                when FFT_IN_DONE =>
                  rready_r <= '0';
              end case;
            end if;

            if op_r = OP_DDR_XCORR and xcorr_fast_local_r = '1' and
               (xcorr_phase_r = XCORR_FFT_A or xcorr_phase_r = XCORR_FFT_B) then
              if xcorr_phase_r = XCORR_FFT_A then
                fft_m_ready_r <= not xcorr_a_fifo_full;
              else
                if xcorr_a_advance_r = '1' then
                  xcorr_a_fifo_rd_en <= '1';
                  xcorr_a_advance_r <= '0';
                  xcorr_a_wait_r <= '1';
                  fft_m_ready_r <= '0';
                  if fft_m_valid = '1' and fft_m_ready_r = '1' then
                    xcorr_b_skid_r <= fft_m_data;
                    xcorr_b_skid_valid_r <= '1';
                    xcorr_b_skid_last_r <= '1' when fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or xcorr_store_index_r = G_FFT_POINTS - 1 else '0';
                  end if;
                elsif xcorr_a_wait_r = '1' then
                  xcorr_a_wait_r <= '0';
                  fft_m_ready_r <= '0';
                else
                  fft_m_ready_r <= '1' when xcorr_b_skid_valid_r = '0' and
                                            xcorr_a_fifo_empty = '0' and
                                            (ifft_s_valid_r = '0' or ifft_s_ready = '1') else '0';
                end if;
              end if;
              if fft_out_remaining_r = 0 then
                fft_m_ready_r <= '0';
                fft_out_state_r <= FFT_OUT_DONE;
              elsif xcorr_phase_r = XCORR_FFT_B and xcorr_b_skid_valid_r = '1' and
                    xcorr_a_advance_r = '0' and xcorr_a_wait_r = '0' and
                    (ifft_s_valid_r = '0' or ifft_s_ready = '1') then
                fast_a_re_v := sample_re(xcorr_a_fifo_dout);
                fast_a_im_v := sample_im(xcorr_a_fifo_dout);
                fast_b_re_v := sample_re(xcorr_b_skid_r);
                fast_b_im_v := sample_im(xcorr_b_skid_r);
                corr_re_v := resize(fast_a_re_v * fast_b_re_v, corr_re_v'length) +
                             resize(fast_a_im_v * fast_b_im_v, corr_re_v'length);
                corr_im_v := resize(fast_a_im_v * fast_b_re_v, corr_im_v'length) -
                             resize(fast_a_re_v * fast_b_im_v, corr_im_v'length);
                ifft_s_data_r <= pack_fft_input(corr_re_v, corr_im_v);
                ifft_s_valid_r <= '1';
                ifft_s_last_r <= xcorr_b_skid_last_r;
                xcorr_b_skid_valid_r <= '0';
                if ifft_in_remaining_r <= to_unsigned(C_AXI_BYTES, 32) then
                  ifft_in_remaining_r <= (others => '0');
                else
                  ifft_in_remaining_r <= ifft_in_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                end if;

                if xcorr_b_skid_last_r = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or xcorr_store_index_r = G_FFT_POINTS - 1 then
                  fft_out_remaining_r <= (others => '0');
                  fft_out_state_r <= FFT_OUT_DONE;
                  fft_m_ready_r <= '0';
                  xcorr_store_index_r <= 0;
                else
                  fft_out_remaining_r <= fft_out_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                  xcorr_store_index_r <= xcorr_store_index_r + 1;
                  xcorr_a_advance_r <= '1';
                end if;
              elsif fft_m_valid = '1' and fft_m_ready_r = '1' and
                    not (xcorr_phase_r = XCORR_FFT_B and (xcorr_a_advance_r = '1' or xcorr_a_wait_r = '1')) then
                if xcorr_phase_r = XCORR_FFT_A then
                  xcorr_a_fifo_din <= fft_m_data;
                  xcorr_a_fifo_wr_en <= '1';
                  if fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or xcorr_store_index_r = G_FFT_POINTS - 1 then
                    fft_out_remaining_r <= (others => '0');
                    fft_out_state_r <= FFT_OUT_DONE;
                    fft_m_ready_r <= '0';
                    xcorr_store_index_r <= 0;
                  else
                    fft_out_remaining_r <= fft_out_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                    xcorr_store_index_r <= xcorr_store_index_r + 1;
                  end if;
                else
                  fast_a_re_v := sample_re(xcorr_a_fifo_dout);
                  fast_a_im_v := sample_im(xcorr_a_fifo_dout);
                  fast_b_re_v := sample_re(fft_m_data);
                  fast_b_im_v := sample_im(fft_m_data);
                  corr_re_v := resize(fast_a_re_v * fast_b_re_v, corr_re_v'length) +
                               resize(fast_a_im_v * fast_b_im_v, corr_re_v'length);
                  corr_im_v := resize(fast_a_im_v * fast_b_re_v, corr_im_v'length) -
                               resize(fast_a_re_v * fast_b_im_v, corr_im_v'length);
                  ifft_s_data_r <= pack_fft_input(corr_re_v, corr_im_v);
                  ifft_s_valid_r <= '1';
                  ifft_s_last_r <= '1' when fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or xcorr_store_index_r = G_FFT_POINTS - 1 else '0';
                  if ifft_in_remaining_r <= to_unsigned(C_AXI_BYTES, 32) then
                    ifft_in_remaining_r <= (others => '0');
                  else
                    ifft_in_remaining_r <= ifft_in_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                  end if;

                  if fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) or xcorr_store_index_r = G_FFT_POINTS - 1 then
                    fft_out_remaining_r <= (others => '0');
                    fft_out_state_r <= FFT_OUT_DONE;
                    fft_m_ready_r <= '0';
                    xcorr_store_index_r <= 0;
                  else
                    fft_out_remaining_r <= fft_out_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                    xcorr_store_index_r <= xcorr_store_index_r + 1;
                    xcorr_a_advance_r <= '1';
                  end if;
                end if;
              end if;

              if fft_in_state_r = FFT_IN_DONE and fft_out_state_r = FFT_OUT_DONE then
                scratch_product_base_v := corr_scratch_addr_r + resize(fft_frame_bytes_r, corr_scratch_addr_r'length);
                if xcorr_phase_r = XCORR_FFT_A then
                  report "RADFFT DDR xcorr FFT_A done @" & time'image(now);
                  xcorr_phase_r <= XCORR_FFT_B;
                  fft_runtime_inverse_r <= '0';
                  fft_in_frame_base_r <= corr_b_addr_r;
                  fft_in_addr_r <= corr_b_addr_r;
                  fft_out_frame_base_r <= scratch_product_base_v;
                  fft_out_addr_r <= scratch_product_base_v;
                  fft_in_remaining_r <= fft_frame_bytes_r;
                  fft_feed_remaining_r <= fft_frame_bytes_r;
                  ifft_in_remaining_r <= fft_frame_bytes_r;
                  fft_out_remaining_r <= fft_frame_bytes_r;
                  fft_in_state_r <= FFT_IN_IDLE;
                  fft_out_state_r <= FFT_OUT_IDLE;
                  fft_s_valid_r <= '0';
                  fft_s_last_r <= '0';
                  fft_m_ready_r <= '0';
                  xcorr_store_index_r <= 0;
                  xcorr_a_advance_r <= '0';
                  xcorr_a_wait_r <= '0';
                  xcorr_b_skid_valid_r <= '0';
                  xcorr_b_skid_last_r <= '0';
                elsif xcorr_phase_r = XCORR_FFT_B then
                  report "RADFFT DDR xcorr FFT_B/product/iFFT-load done @" & time'image(now);
                  xcorr_phase_r <= XCORR_IFFT;
                  fft_runtime_inverse_r <= '1';
                  fft_in_frame_base_r <= scratch_product_base_v;
                  fft_in_addr_r <= scratch_product_base_v;
                  fft_out_frame_base_r <= out_addr_r;
                  fft_out_addr_r <= out_addr_r;
                  fft_in_remaining_r <= fft_frame_bytes_r;
                  fft_out_remaining_r <= fft_frame_bytes_r;
                  fft_in_state_r <= FFT_IN_IDLE;
                  fft_out_state_r <= FFT_OUT_IDLE;
                  fft_s_valid_r <= '0';
                  fft_s_last_r <= '0';
                  fft_m_ready_r <= '0';
                  xcorr_store_index_r <= 0;
                  xcorr_a_advance_r <= '0';
                  xcorr_a_wait_r <= '0';
                  xcorr_b_skid_valid_r <= '0';
                  xcorr_b_skid_last_r <= '0';
                end if;
              end if;

            elsif not (op_r = OP_DDR_XCORR and xcorr_phase_r = XCORR_PRODUCT) then
            case fft_out_state_r is
              when FFT_OUT_IDLE =>
                fft_m_ready_r <= '0';
                if fft_out_remaining_r = 0 then
                  fft_out_state_r <= FFT_OUT_DONE;
                elsif fft_config_r(5) = '1' then
                  fft_out_state_r <= FFT_OUT_W;
                else
                  next_beats := bytes_to_beats(fft_out_remaining_r, resize(burst_beats_r, 9));
                  fft_out_burst_beats_r <= next_beats;
                  fft_out_beat_index_r <= (others => '0');
                  awaddr_r <= std_logic_vector(fft_out_addr_r);
                  awlen_r <= std_logic_vector(resize(next_beats - 1, 8));
                  awvalid_r <= '1';
                  fft_out_state_r <= FFT_OUT_AW;
                end if;

              when FFT_OUT_AW =>
                fft_m_ready_r <= '0';
                if m_axi_awready = '1' then
                  awvalid_r <= '0';
                  fft_out_state_r <= FFT_OUT_W;
                end if;

              when FFT_OUT_W =>
                if fft_config_r(5) = '1' then
                  fft_m_ready_r <= not out_fifo_full;
                  if fft_m_valid = '1' and out_fifo_full = '0' then
                    out_fifo_din <= '0' & std_logic_vector(resize(unsigned(fft_m_data), G_AXIS_DATA_WIDTH));
                    if fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) then
                      out_fifo_din(C_FIFO_WIDTH - 1) <= '1';
                    end if;
                    out_fifo_wr_en <= '1';
                    if fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) then
                      fft_out_remaining_r <= (others => '0');
                      fft_out_state_r <= FFT_OUT_DONE;
                    else
                      fft_out_remaining_r <= fft_out_remaining_r - to_unsigned(C_AXI_BYTES, 32);
                    end if;
                  end if;
                elsif wvalid_r = '1' and m_axi_wready = '1' then
                  wvalid_r <= '0';
                  fft_m_ready_r <= '0';
                  if wlast_r = '1' then
                    bready_r <= '1';
                    fft_out_state_r <= FFT_OUT_B;
                  else
                    fft_out_beat_index_r <= fft_out_beat_index_r + 1;
                  end if;
                elsif wvalid_r = '0' then
                  fft_m_ready_r <= '1';
                  if fft_m_valid = '1' and fft_m_ready_r = '1' then
                    wdata_r <= (others => '0');
                    wdata_r(C_FFT_OUTPUT_BITS - 1 downto 0) <= fft_m_data;
                    wlast_r <= '1' when fft_out_beat_index_r = fft_out_burst_beats_r - 1 or fft_m_last = '1' or fft_out_remaining_r <= to_unsigned(C_AXI_BYTES, 32) else '0';
                    wvalid_r <= '1';
                    fft_m_ready_r <= '0';
                  end if;
                end if;

              when FFT_OUT_B =>
                fft_m_ready_r <= '0';
                if m_axi_bvalid = '1' then
                  bready_r <= '0';
                  if m_axi_bresp /= "00" then
                    status_r(2) <= '1';
                    status_r(3) <= '1';
                    op_r <= OP_IDLE;
                  else
                    burst_bytes := resize(fft_out_burst_beats_r, 32) sll ceil_log2(C_AXI_BYTES);
                    fft_out_addr_r <= fft_out_addr_r + resize(burst_bytes, fft_out_addr_r'length);
                    if fft_out_remaining_r <= burst_bytes then
                      fft_out_remaining_r <= (others => '0');
                    else
                      fft_out_remaining_r <= fft_out_remaining_r - burst_bytes;
                    end if;
                    fft_out_state_r <= FFT_OUT_IDLE;
                  end if;
                end if;

              when FFT_OUT_DONE =>
                fft_m_ready_r <= '0';
            end case;

            if fft_in_state_r = FFT_IN_DONE and fft_out_state_r = FFT_OUT_DONE then
              if op_r = OP_DDR_XCORR then
                scratch_product_base_v := corr_scratch_addr_r + resize(fft_frame_bytes_r, corr_scratch_addr_r'length);
                if xcorr_phase_r = XCORR_FFT_A then
                  xcorr_phase_r <= XCORR_FFT_B;
                  fft_runtime_inverse_r <= '0';
                  fft_in_frame_base_r <= corr_b_addr_r;
                  fft_in_addr_r <= corr_b_addr_r;
                  fft_out_frame_base_r <= scratch_product_base_v;
                  fft_out_addr_r <= scratch_product_base_v;
                  fft_in_remaining_r <= fft_frame_bytes_r;
                  fft_feed_remaining_r <= fft_frame_bytes_r;
                  fft_out_remaining_r <= fft_frame_bytes_r;
                  fft_in_state_r <= FFT_IN_IDLE;
                  fft_out_state_r <= FFT_OUT_IDLE;
                  fft_s_valid_r <= '0';
                  fft_s_last_r <= '0';
                  fft_m_ready_r <= '0';
                  xcorr_store_index_r <= 0;
                  xcorr_a_advance_r <= '0';
                  xcorr_a_wait_r <= '0';
                  xcorr_b_skid_valid_r <= '0';
                  xcorr_b_skid_last_r <= '0';
                elsif xcorr_phase_r = XCORR_FFT_B then
                  if xcorr_fast_local_r = '1' then
                    xcorr_phase_r <= XCORR_IFFT;
                    fft_runtime_inverse_r <= '1';
                    fft_in_frame_base_r <= scratch_product_base_v;
                    fft_in_addr_r <= scratch_product_base_v;
                    fft_out_frame_base_r <= out_addr_r;
                    fft_out_addr_r <= out_addr_r;
                    fft_in_remaining_r <= fft_frame_bytes_r;
                    fft_out_remaining_r <= fft_frame_bytes_r;
                    fft_in_state_r <= FFT_IN_IDLE;
                    fft_out_state_r <= FFT_OUT_IDLE;
                    fft_s_valid_r <= '0';
                    fft_s_last_r <= '0';
                    fft_m_ready_r <= '0';
                    xcorr_store_index_r <= 0;
                    xcorr_a_advance_r <= '0';
                    xcorr_a_wait_r <= '0';
                    xcorr_b_skid_valid_r <= '0';
                    xcorr_b_skid_last_r <= '0';
                  else
                    xcorr_phase_r <= XCORR_PRODUCT;
                    prod_state_r <= PROD_IDLE;
                    prod_a_addr_r <= corr_scratch_addr_r;
                    prod_b_addr_r <= scratch_product_base_v;
                    prod_out_addr_r <= scratch_product_base_v;
                    prod_remaining_r <= fft_frame_bytes_r;
                    fft_s_valid_r <= '0';
                    fft_s_last_r <= '0';
                    fft_m_ready_r <= '0';
                  end if;
                elsif xcorr_phase_r = XCORR_IFFT then
              report "RADFFT DDR xcorr IFFT/output done @" & time'image(now);
              batch_remaining_r <= (others => '0');
              batch_done_count_r <= to_unsigned(1, batch_done_count_r'length);
              op_r <= OP_IDLE;
              status_r(1) <= '1';
                end if;
              elsif batch_remaining_r > to_unsigned(1, batch_remaining_r'length) then
                next_in_base_v := fft_in_frame_base_r + resize(active_src_stride_r, fft_in_frame_base_r'length);
                next_out_base_v := fft_out_frame_base_r + resize(active_dst_stride_r, fft_out_frame_base_r'length);
                fft_in_frame_base_r <= next_in_base_v;
                fft_out_frame_base_r <= next_out_base_v;
                fft_in_addr_r <= next_in_base_v;
                fft_out_addr_r <= next_out_base_v;
                fft_in_remaining_r <= fft_frame_bytes_r;
                fft_feed_remaining_r <= fft_frame_bytes_r;
                fft_out_remaining_r <= fft_frame_bytes_r;
                fft_in_state_r <= FFT_IN_IDLE;
                fft_out_state_r <= FFT_OUT_IDLE;
                fft_s_valid_r <= '0';
                fft_s_last_r <= '0';
                fft_m_ready_r <= '0';
                batch_remaining_r <= batch_remaining_r - 1;
                batch_done_count_r <= batch_done_count_r + 1;
              else
                batch_remaining_r <= (others => '0');
                if batch_total_r /= 0 then
                  batch_done_count_r <= batch_total_r;
                else
                  batch_done_count_r <= to_unsigned(1, batch_done_count_r'length);
                end if;
                op_r <= OP_IDLE;
                status_r(1) <= '1';
              end if;
            end if;
            end if;

            if op_r = OP_DDR_XCORR and xcorr_phase_r = XCORR_PRODUCT and prod_state_r = PROD_DONE then
              scratch_product_base_v := corr_scratch_addr_r + resize(fft_frame_bytes_r, corr_scratch_addr_r'length);
              xcorr_phase_r <= XCORR_IFFT;
              fft_runtime_inverse_r <= '1';
              fft_in_frame_base_r <= scratch_product_base_v;
              fft_in_addr_r <= scratch_product_base_v;
              fft_out_frame_base_r <= out_addr_r;
              fft_out_addr_r <= out_addr_r;
              fft_in_remaining_r <= fft_frame_bytes_r;
              fft_feed_remaining_r <= fft_frame_bytes_r;
              fft_out_remaining_r <= fft_frame_bytes_r;
              fft_in_state_r <= FFT_IN_IDLE;
              fft_out_state_r <= FFT_OUT_IDLE;
              fft_s_valid_r <= '0';
              fft_s_last_r <= '0';
              fft_m_ready_r <= '0';
              xcorr_a_advance_r <= '0';
              xcorr_a_wait_r <= '0';
              xcorr_b_skid_valid_r <= '0';
              xcorr_b_skid_last_r <= '0';
              prod_state_r <= PROD_IDLE;
            end if;

          when OP_UNSUPPORTED_FFT =>
            op_r <= OP_IDLE;

          when OP_IDLE =>
            null;
        end case;
      end if;
    end if;
  end process;
end architecture;
