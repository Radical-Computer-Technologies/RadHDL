library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI-stream fixed-point to floating-point conversion stage.
-- Converts signed fixed-width sample lanes into floating-point representations for mixed numeric pipelines.
entity raddsp_axis_fixed_to_float is
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
    s_axis_tdata  : in  std_logic_vector((CHANNEL_COUNT * FIXED_WIDTH) - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector((CHANNEL_COUNT * 32) - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_fixed_to_float is
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector((CHANNEL_COUNT * 32) - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal ready_i     : std_logic;

  function fixed_word_at(data : std_logic_vector; index : natural) return signed is
    variable lo : natural := index * FIXED_WIDTH;
  begin
    return signed(data(lo + FIXED_WIDTH - 1 downto lo));
  end function;

  function convert_one(x : signed(FIXED_WIDTH - 1 downto 0)) return std_logic_vector is
    variable sign_v      : std_logic := x(FIXED_WIDTH - 1);
    variable x_ext       : signed(63 downto 0) := resize(x, 64);
    variable mag_v       : unsigned(63 downto 0) := (others => '0');
    variable leading_v   : integer := -1;
    variable exponent_v  : integer;
    variable shift_v     : integer;
    variable norm_v      : unsigned(63 downto 0) := (others => '0');
    variable result_v    : std_logic_vector(31 downto 0) := (others => '0');
  begin
    if x = 0 then
      return result_v;
    end if;

    if sign_v = '1' then
      mag_v := unsigned(-x_ext);
    else
      mag_v := unsigned(x_ext);
    end if;

    for bit_i in 0 to 63 loop
      if mag_v(bit_i) = '1' then
        leading_v := bit_i;
      end if;
    end loop;

    exponent_v := leading_v - integer(FIXED_FRAC_BITS) + 127;
    result_v(31) := sign_v;
    if exponent_v <= 0 then
      return result_v;
    elsif exponent_v >= 255 then
      result_v(30 downto 23) := (others => '1');
      return result_v;
    end if;

    shift_v := 23 - leading_v;
    if shift_v >= 0 then
      norm_v := shift_left(mag_v, shift_v);
    else
      norm_v := shift_right(mag_v, -shift_v);
    end if;

    result_v(30 downto 23) := std_logic_vector(to_unsigned(exponent_v, 8));
    result_v(22 downto 0) := std_logic_vector(norm_v(22 downto 0));
    return result_v;
  end function;
begin
  assert FIXED_WIDTH <= 48 report "fixed_to_float FIXED_WIDTH currently supports up to 48 bits" severity failure;
  assert FIXED_FRAC_BITS < 48 report "fixed_to_float FIXED_FRAC_BITS must be less than 48" severity failure;

  ready_i <= '1' when out_valid_r = '0' or m_axis_tready = '1' else '0';
  s_axis_tready <= ready_i;
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_last_r;

  process(clk)
    variable out_v : std_logic_vector((CHANNEL_COUNT * 32) - 1 downto 0);
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
            out_v(((channel + 1) * 32) - 1 downto channel * 32) :=
              convert_one(fixed_word_at(s_axis_tdata, channel));
          end loop;
          out_data_r <= out_v;
        end if;
      end if;
    end if;
  end process;
end architecture;
