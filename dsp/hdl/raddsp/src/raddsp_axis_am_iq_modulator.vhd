library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- AXI-stream AM IQ modulator.
-- Multiplies a signed envelope stream by externally supplied carrier cosine
-- and sine samples to produce packed I/Q output. The low word is I and the high
-- word is Q, both signed fixed-point values.
entity raddsp_axis_am_iq_modulator is
  generic (
    -- Sample width for envelope, carrier, and I/Q output lanes.
    SAMPLE_WIDTH : positive := 16;
    -- Number of fractional bits used by carrier and envelope fixed-point values.
    FRAC_BITS    : natural := 14;
    -- Vendor selector retained for generated package consistency.
    VENDOR       : string := "GENERIC";
    -- Device-family selector retained for generated package consistency.
    DEVICE_FAMILY: string := "GENERIC"
  );
  port (
    -- Stream clock.
    clk             : in  std_logic;
    -- Active-high synchronous reset.
    rst             : in  std_logic;
    -- Signed fixed-point carrier cosine sample.
    carrier_i_i     : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    -- Signed fixed-point carrier sine sample.
    carrier_q_i     : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    -- Envelope stream valid.
    s_axis_tvalid   : in  std_logic;
    -- Envelope stream ready.
    s_axis_tready   : out std_logic;
    -- Signed fixed-point envelope sample.
    s_axis_tdata    : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    -- Envelope stream frame marker.
    s_axis_tlast    : in  std_logic;
    -- Packed I/Q output valid.
    m_axis_tvalid   : out std_logic;
    -- Packed I/Q output ready.
    m_axis_tready   : in  std_logic;
    -- Packed I/Q output, I in bits SAMPLE_WIDTH-1:0 and Q above it.
    m_axis_tdata    : out std_logic_vector((2 * SAMPLE_WIDTH) - 1 downto 0);
    -- Output frame marker aligned with output sample.
    m_axis_tlast    : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_am_iq_modulator is
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector((2 * SAMPLE_WIDTH) - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal ready_i     : std_logic;
begin
  assert FRAC_BITS < (2 * SAMPLE_WIDTH)
    report "raddsp_axis_am_iq_modulator FRAC_BITS is too large"
    severity failure;

  ready_i <= (not out_valid_r) or m_axis_tready;
  s_axis_tready <= ready_i;
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_last_r;

  process(clk)
    variable env_v : signed(SAMPLE_WIDTH - 1 downto 0);
    variable ci_v  : signed(SAMPLE_WIDTH - 1 downto 0);
    variable cq_v  : signed(SAMPLE_WIDTH - 1 downto 0);
    variable prod_i : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable prod_q : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable scaled_i : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
    variable scaled_q : signed((2 * SAMPLE_WIDTH) - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        out_valid_r <= '0';
        out_data_r <= (others => '0');
        out_last_r <= '0';
      elsif ready_i = '1' then
        out_valid_r <= s_axis_tvalid;
        out_last_r <= s_axis_tlast;
        if s_axis_tvalid = '1' then
          env_v := signed(s_axis_tdata);
          ci_v := signed(carrier_i_i);
          cq_v := signed(carrier_q_i);
          prod_i := env_v * ci_v;
          prod_q := env_v * cq_v;
          scaled_i := shift_right(prod_i, FRAC_BITS);
          scaled_q := shift_right(prod_q, FRAC_BITS);
          out_data_r(SAMPLE_WIDTH - 1 downto 0) <=
            std_logic_vector(raddsp_sat_signed_vec(scaled_i, SAMPLE_WIDTH));
          out_data_r((2 * SAMPLE_WIDTH) - 1 downto SAMPLE_WIDTH) <=
            std_logic_vector(raddsp_sat_signed_vec(scaled_q, SAMPLE_WIDTH));
        end if;
      end if;
    end if;
  end process;
end architecture;
