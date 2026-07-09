library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- AXI-stream AM IQ demodulator.
-- Computes the magnitude envelope sqrt(I^2 + Q^2) from packed signed I/Q
-- samples. The low input word is I and the high input word is Q.
entity raddsp_axis_am_iq_demodulator is
  generic (
    -- Signed I/Q sample width.
    SAMPLE_WIDTH : positive := 16;
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
    m_axis_tlast    : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_am_iq_demodulator is
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal ready_i     : std_logic;

  function isqrt(value : natural) return natural is
    variable root : natural := 0;
  begin
    while (root + 1) * (root + 1) <= value loop
      root := root + 1;
    end loop;
    return root;
  end function;

  function abs_int(value : integer) return natural is
  begin
    if value < 0 then
      return natural(-value);
    end if;
    return natural(value);
  end function;
begin
  assert SAMPLE_WIDTH <= 16
    report "raddsp_axis_am_iq_demodulator portable magnitude path supports SAMPLE_WIDTH <= 16"
    severity failure;

  ready_i <= (not out_valid_r) or m_axis_tready;
  s_axis_tready <= ready_i;
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_last_r;

  process(clk)
    variable i_v : integer;
    variable q_v : integer;
    variable mag_sq_v : natural;
    variable mag_v : natural;
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
          i_v := to_integer(signed(s_axis_tdata(SAMPLE_WIDTH - 1 downto 0)));
          q_v := to_integer(signed(s_axis_tdata((2 * SAMPLE_WIDTH) - 1 downto SAMPLE_WIDTH)));
          mag_sq_v := (abs_int(i_v) * abs_int(i_v)) + (abs_int(q_v) * abs_int(q_v));
          mag_v := isqrt(mag_sq_v);
          if mag_v > raddsp_max_int(SAMPLE_WIDTH) then
            out_data_r <= std_logic_vector(to_unsigned(raddsp_max_int(SAMPLE_WIDTH), SAMPLE_WIDTH));
          else
            out_data_r <= std_logic_vector(to_unsigned(mag_v, SAMPLE_WIDTH));
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
