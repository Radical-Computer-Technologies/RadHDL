library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- AXI-stream floating-point to fixed-point conversion stage.
-- Quantizes floating-point sample lanes into saturated fixed-point values for FPGA-efficient downstream processing.
entity raddsp_axis_float_to_fixed is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string := "generic";
    -- Sets the bit width for FIXED WIDTH values carried by this module.
    FIXED_WIDTH     : positive := 16;
    -- Sets the number of fractional bits used when scaling fixed-point arithmetic results.
    FIXED_FRAC_BITS : natural := 15;
    -- Sets the number of parallel sample lanes processed per handshake beat.
    CHANNEL_COUNT   : positive := 1
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
    s_axis_tdata  : in  std_logic_vector((CHANNEL_COUNT * 32) - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector((CHANNEL_COUNT * FIXED_WIDTH) - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_float_to_fixed is
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector((CHANNEL_COUNT * FIXED_WIDTH) - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal ready_i     : std_logic;

  function float_word_at(data : std_logic_vector; index : natural) return std_logic_vector is
    variable lo : natural := index * 32;
  begin
    return data(lo + 31 downto lo);
  end function;

  function convert_one(f : std_logic_vector(31 downto 0)) return signed is
    variable sign_v      : std_logic;
    variable exp_v       : integer;
    variable unbiased_v  : integer;
    variable shift_v     : integer;
    variable mant_v      : unsigned(63 downto 0) := (others => '0');
    variable mag_v       : signed(63 downto 0) := (others => '0');
    variable signed_v    : signed(63 downto 0) := (others => '0');
    variable zero_v      : signed(FIXED_WIDTH - 1 downto 0) := (others => '0');
    variable sat_v       : signed(63 downto 0) := (others => '0');
  begin
    sign_v := f(31);
    exp_v := to_integer(unsigned(f(30 downto 23)));
    if exp_v = 0 then
      return zero_v;
    end if;

    unbiased_v := exp_v - 127;
    shift_v := unbiased_v - 23 + integer(FIXED_FRAC_BITS);
    mant_v(23 downto 0) := unsigned('1' & f(22 downto 0));

    if shift_v > 39 then
      sat_v(62) := '1';
      if sign_v = '1' then
        return raddsp_sat_signed_vec(-sat_v, FIXED_WIDTH);
      end if;
      return raddsp_sat_signed_vec(sat_v, FIXED_WIDTH);
    elsif shift_v >= 0 then
      mag_v := signed(shift_left(mant_v, shift_v));
    else
      mag_v := signed(shift_right(mant_v, -shift_v));
    end if;

    if sign_v = '1' then
      signed_v := -mag_v;
    else
      signed_v := mag_v;
    end if;
    return raddsp_sat_signed_vec(signed_v, FIXED_WIDTH);
  end function;
begin
  assert FIXED_WIDTH <= 48 report "float_to_fixed FIXED_WIDTH currently supports up to 48 bits" severity failure;
  assert FIXED_FRAC_BITS < 48 report "float_to_fixed FIXED_FRAC_BITS must be less than 48" severity failure;

  ready_i <= '1' when out_valid_r = '0' or m_axis_tready = '1' else '0';
  s_axis_tready <= ready_i;
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_last_r;

  process(clk)
    variable out_v : std_logic_vector((CHANNEL_COUNT * FIXED_WIDTH) - 1 downto 0);
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
          out_v := (others => '0');
          for channel in 0 to CHANNEL_COUNT - 1 loop
            out_v(((channel + 1) * FIXED_WIDTH) - 1 downto channel * FIXED_WIDTH) :=
              std_logic_vector(convert_one(float_word_at(s_axis_tdata, channel)));
          end loop;
          out_data_r <= out_v;
        end if;
      end if;
    end if;
  end process;
end architecture;
