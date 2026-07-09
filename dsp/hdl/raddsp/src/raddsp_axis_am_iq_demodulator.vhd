library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Register-controlled AXI-stream AM IQ demodulator.
-- Accepts packed signed I/Q samples, optionally rotates them by an internal
-- phase-accumulator DDS carrier for carrier-tuned demodulation, and emits the
-- recovered envelope magnitude. Register control covers enable, internal mixer
-- selection, bypass, phase reset, phase increment, and phase offset.
entity raddsp_axis_am_iq_demodulator is
  generic (
    -- Signed I/Q sample width.
    SAMPLE_WIDTH         : positive := 16;
    -- Number of fractional bits used by carrier and I/Q fixed-point values.
    FRAC_BITS            : natural := 14;
    -- Internal DDS phase accumulator width. The register interface supports up to 32 bits.
    PHASE_WIDTH          : positive := 32;
    -- Width of the RADIF register data path.
    REG_DATA_WIDTH       : positive := 32;
    -- Width of the RADIF byte address path.
    REG_ADDR_WIDTH       : positive := 16;
    -- Reset value for carrier phase increment.
    DEFAULT_PHASE_INC    : natural := 16#01000000#;
    -- Reset value for internal carrier-rotation selection.
    DEFAULT_INTERNAL_DDS : boolean := true;
    -- Reset value for stream processing enable.
    DEFAULT_ENABLE       : boolean := true;
    -- Vendor selector retained for generated package consistency.
    VENDOR               : string := "GENERIC";
    -- Device-family selector retained for generated package consistency.
    DEVICE_FAMILY        : string := "GENERIC"
  );
  port (
    -- Stream and register clock.
    clk             : in  std_logic;
    -- Active-high synchronous reset.
    rst             : in  std_logic;
    -- Packed I/Q input valid.
    s_axis_tvalid   : in  std_logic;
    -- Packed I/Q input ready.
    s_axis_tready   : out std_logic;
    -- Packed I/Q input, I in bits SAMPLE_WIDTH-1:0 and Q above it.
    s_axis_tdata    : in  std_logic_vector((2 * SAMPLE_WIDTH) - 1 downto 0);
    -- Input frame marker.
    s_axis_tlast    : in  std_logic;
    -- Envelope output valid.
    m_axis_tvalid   : out std_logic;
    -- Envelope output ready.
    m_axis_tready   : in  std_logic;
    -- Unsigned envelope magnitude in SAMPLE_WIDTH bits.
    m_axis_tdata    : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    -- Output frame marker aligned with envelope sample.
    m_axis_tlast    : out std_logic;
    -- Register write address.
    reg_wr_addr     : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- Register read address.
    reg_rd_addr     : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- One-cycle register write request.
    reg_wr_en       : in  std_logic;
    -- One-cycle register read request.
    reg_rd_en       : in  std_logic;
    -- Register write data.
    reg_data_in     : in  std_logic_vector(REG_DATA_WIDTH - 1 downto 0);
    -- Register read data.
    reg_data_out    : out std_logic_vector(REG_DATA_WIDTH - 1 downto 0);
    -- Register write ready.
    reg_wr_rdy      : out std_logic;
    -- Register read ready.
    reg_rd_rdy      : out std_logic;
    -- Register write response valid.
    reg_wr_valid    : out std_logic;
    -- Register read response valid.
    reg_rd_valid    : out std_logic;
    -- Register transaction error.
    reg_error       : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_am_iq_demodulator is
  constant C_REG_CONTROL      : natural := 16#00#;
  constant C_REG_STATUS       : natural := 16#04#;
  constant C_REG_PHASE_INC    : natural := 16#08#;
  constant C_REG_PHASE_OFFSET : natural := 16#0C#;
  constant C_REG_PHASE        : natural := 16#10#;
  constant C_REG_SAMPLE_COUNT : natural := 16#14#;

  type carrier_lut_t is array (0 to 15) of integer;
  constant C_COS_Q14 : carrier_lut_t := (
    16384, 15137, 11585, 6270,
    0, -6270, -11585, -15137,
    -16384, -15137, -11585, -6270,
    0, 6270, 11585, 15137
  );

  signal out_valid_r     : std_logic := '0';
  signal out_data_r      : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal out_last_r      : std_logic := '0';
  signal ready_i         : std_logic;
  signal enable_r        : std_logic := '1';
  signal internal_dds_r  : std_logic := '1';
  signal bypass_r        : std_logic := '0';
  signal phase_r         : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase_inc_r     : unsigned(PHASE_WIDTH - 1 downto 0) := to_unsigned(DEFAULT_PHASE_INC, PHASE_WIDTH);
  signal phase_offset_r  : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_count_r  : unsigned(REG_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal rd_data_r       : std_logic_vector(REG_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_valid_r      : std_logic := '0';
  signal rd_valid_r      : std_logic := '0';
  signal error_r         : std_logic := '0';

  function bool_sl(value : boolean) return std_logic is
  begin
    if value then
      return '1';
    end if;
    return '0';
  end function;

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

  function pad_phase(value : unsigned) return std_logic_vector is
    variable outv : std_logic_vector(REG_DATA_WIDTH - 1 downto 0) := (others => '0');
  begin
    outv(PHASE_WIDTH - 1 downto 0) := std_logic_vector(value);
    return outv;
  end function;

  function phase_index(value : unsigned) return natural is
  begin
    return to_integer(value(value'high downto value'high - 3));
  end function;

  function dds_carrier(value : unsigned; sine_offset : natural) return signed is
    variable idx : natural;
  begin
    idx := (phase_index(value) + sine_offset) mod 16;
    return to_signed(C_COS_Q14(idx), SAMPLE_WIDTH);
  end function;

  function isqrt(value : natural) return natural is
    variable root : natural := 0;
  begin
    while (root + 1) * (root + 1) <= value loop
      root := root + 1;
    end loop;
    return root;
  end function;
begin
  assert SAMPLE_WIDTH <= 16
    report "raddsp_axis_am_iq_demodulator portable magnitude path supports SAMPLE_WIDTH <= 16"
    severity failure;
  assert FRAC_BITS < (2 * SAMPLE_WIDTH)
    report "raddsp_axis_am_iq_demodulator FRAC_BITS is too large"
    severity failure;
  assert PHASE_WIDTH >= 4 and PHASE_WIDTH <= REG_DATA_WIDTH
    report "raddsp_axis_am_iq_demodulator requires 4 <= PHASE_WIDTH <= REG_DATA_WIDTH"
    severity failure;
  assert REG_ADDR_WIDTH >= 8
    report "raddsp_axis_am_iq_demodulator requires REG_ADDR_WIDTH >= 8"
    severity failure;

  ready_i <= (not out_valid_r) or m_axis_tready;
  s_axis_tready <= ready_i;
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_last_r;
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;

  process(clk)
    variable i_v         : signed(SAMPLE_WIDTH - 1 downto 0);
    variable q_v         : signed(SAMPLE_WIDTH - 1 downto 0);
    variable ci_v        : signed(SAMPLE_WIDTH - 1 downto 0);
    variable cq_v        : signed(SAMPLE_WIDTH - 1 downto 0);
    variable mix_i_prod0 : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable mix_i_prod1 : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable mix_q_prod0 : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable mix_q_prod1 : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable mix_i_full  : signed((2 * SAMPLE_WIDTH) downto 0);
    variable mix_q_full  : signed((2 * SAMPLE_WIDTH) downto 0);
    variable mix_i       : signed(SAMPLE_WIDTH - 1 downto 0);
    variable mix_q       : signed(SAMPLE_WIDTH - 1 downto 0);
    variable mag_sq_v    : natural;
    variable mag_v       : natural;
    variable idx         : natural;
    variable control_v   : std_logic_vector(REG_DATA_WIDTH - 1 downto 0);
    variable status_v    : std_logic_vector(REG_DATA_WIDTH - 1 downto 0);
    variable phase_now   : unsigned(PHASE_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';

      if rst = '1' then
        out_valid_r <= '0';
        out_data_r <= (others => '0');
        out_last_r <= '0';
        enable_r <= bool_sl(DEFAULT_ENABLE);
        internal_dds_r <= bool_sl(DEFAULT_INTERNAL_DDS);
        bypass_r <= '0';
        phase_r <= (others => '0');
        phase_inc_r <= to_unsigned(DEFAULT_PHASE_INC, PHASE_WIDTH);
        phase_offset_r <= (others => '0');
        sample_count_r <= (others => '0');
        rd_data_r <= (others => '0');
      else
        if reg_wr_en = '1' then
          wr_valid_r <= '1';
          idx := reg_index(reg_wr_addr);
          case idx is
            when C_REG_CONTROL =>
              enable_r <= reg_data_in(0);
              internal_dds_r <= reg_data_in(1);
              bypass_r <= reg_data_in(2);
              if reg_data_in(3) = '1' then
                phase_r <= (others => '0');
              end if;
            when C_REG_PHASE_INC =>
              phase_inc_r <= unsigned(reg_data_in(PHASE_WIDTH - 1 downto 0));
            when C_REG_PHASE_OFFSET =>
              phase_offset_r <= unsigned(reg_data_in(PHASE_WIDTH - 1 downto 0));
            when C_REG_SAMPLE_COUNT =>
              if reg_data_in(0) = '1' then
                sample_count_r <= (others => '0');
              end if;
            when others =>
              error_r <= '1';
          end case;
        end if;

        if reg_rd_en = '1' then
          rd_valid_r <= '1';
          idx := reg_index(reg_rd_addr);
          control_v := (others => '0');
          control_v(0) := enable_r;
          control_v(1) := internal_dds_r;
          control_v(2) := bypass_r;
          status_v := (others => '0');
          status_v(0) := out_valid_r;
          status_v(1) := ready_i;
          case idx is
            when C_REG_CONTROL =>
              rd_data_r <= control_v;
            when C_REG_STATUS =>
              rd_data_r <= status_v;
            when C_REG_PHASE_INC =>
              rd_data_r <= pad_phase(phase_inc_r);
            when C_REG_PHASE_OFFSET =>
              rd_data_r <= pad_phase(phase_offset_r);
            when C_REG_PHASE =>
              rd_data_r <= pad_phase(phase_r);
            when C_REG_SAMPLE_COUNT =>
              rd_data_r <= std_logic_vector(sample_count_r);
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;

        if ready_i = '1' then
          out_valid_r <= '0';
          out_last_r <= '0';
          if s_axis_tvalid = '1' and enable_r = '1' then
            i_v := signed(s_axis_tdata(SAMPLE_WIDTH - 1 downto 0));
            q_v := signed(s_axis_tdata((2 * SAMPLE_WIDTH) - 1 downto SAMPLE_WIDTH));

            if bypass_r = '1' then
              mix_i := i_v;
              mix_q := q_v;
            elsif internal_dds_r = '1' then
              phase_now := phase_r + phase_offset_r;
              ci_v := dds_carrier(phase_now, 0);
              cq_v := dds_carrier(phase_now, 12);
              mix_i_prod0 := i_v * ci_v;
              mix_i_prod1 := q_v * cq_v;
              mix_q_prod0 := q_v * ci_v;
              mix_q_prod1 := i_v * cq_v;
              mix_i_full := shift_right(resize(mix_i_prod0, mix_i_full'length) + resize(mix_i_prod1, mix_i_full'length), FRAC_BITS);
              mix_q_full := shift_right(resize(mix_q_prod0, mix_q_full'length) - resize(mix_q_prod1, mix_q_full'length), FRAC_BITS);
              mix_i := raddsp_sat_signed_vec(mix_i_full, SAMPLE_WIDTH);
              mix_q := raddsp_sat_signed_vec(mix_q_full, SAMPLE_WIDTH);
            else
              mix_i := i_v;
              mix_q := q_v;
            end if;

            mag_sq_v := (raddsp_abs_int(to_integer(mix_i)) * raddsp_abs_int(to_integer(mix_i))) +
                        (raddsp_abs_int(to_integer(mix_q)) * raddsp_abs_int(to_integer(mix_q)));
            mag_v := isqrt(mag_sq_v);
            if mag_v > raddsp_max_int(SAMPLE_WIDTH) then
              out_data_r <= std_logic_vector(to_unsigned(raddsp_max_int(SAMPLE_WIDTH), SAMPLE_WIDTH));
            else
              out_data_r <= std_logic_vector(to_unsigned(mag_v, SAMPLE_WIDTH));
            end if;

            out_valid_r <= '1';
            out_last_r <= s_axis_tlast;
            phase_r <= phase_r + phase_inc_r;
            sample_count_r <= sample_count_r + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
