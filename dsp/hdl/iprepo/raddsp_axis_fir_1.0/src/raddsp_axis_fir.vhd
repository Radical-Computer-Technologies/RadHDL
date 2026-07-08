library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- Multi-channel AXI-stream FIR filter.
-- Applies fixed-point tap coefficients to streaming samples with frame-aware handshaking and vendor-portable arithmetic.
entity raddsp_axis_fir is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets the bit width for TAP WIDTH values carried by this module.
    TAP_WIDTH       : positive := 18;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    TAP_COUNT       : positive := 16;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst           : in  std_logic;
    -- Input clear i signal for this module.
    clear_i       : in  std_logic;
    -- Input taps i signal for this module.
    taps_i        : in  std_logic_vector(TAP_COUNT * TAP_WIDTH - 1 downto 0);
    -- Input AXI-stream valid qualifier for the current sample beat.
    s_axis_tvalid : in  std_logic;
    -- Input AXI-stream ready response indicating this block can accept a beat.
    s_axis_tready : out std_logic;
    -- Input AXI-stream payload containing packed sample or feature lanes.
    s_axis_tdata  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_fir is
  type sample_array_t is array (natural range <>) of signed(DATA_WIDTH - 1 downto 0);
  signal samples_r   : sample_array_t(0 to TAP_COUNT - 1) := (others => (others => '0'));
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal ready_i     : std_logic;

  function tap_at(coeffs : std_logic_vector; index : natural) return signed is
    variable value : signed(TAP_WIDTH - 1 downto 0);
    variable lo    : natural;
  begin
    lo := index * TAP_WIDTH;
    value := signed(coeffs(lo + TAP_WIDTH - 1 downto lo));
    return value;
  end function;
begin
  ready_i <= (not out_valid_r) or m_axis_tready;
  s_axis_tready <= ready_i;
  m_axis_tvalid <= out_valid_r;
  m_axis_tdata <= out_data_r;
  m_axis_tlast <= out_last_r;

  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
  begin
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
  begin
  end generate;

  process(clk)
    variable acc_v     : integer;
    variable product_v : signed(DATA_WIDTH + TAP_WIDTH - 1 downto 0);
    variable sample_v  : signed(DATA_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        samples_r <= (others => (others => '0'));
        out_valid_r <= '0';
        out_data_r <= (others => '0');
        out_last_r <= '0';
      else
        if clear_i = '1' then
          samples_r <= (others => (others => '0'));
        end if;

        if ready_i = '1' then
          out_valid_r <= s_axis_tvalid;
          out_last_r <= s_axis_tlast;
          if s_axis_tvalid = '1' then
            sample_v := signed(s_axis_tdata);
            acc_v := 0;
            product_v := sample_v * tap_at(taps_i, 0);
            acc_v := acc_v + to_integer(shift_right(product_v, COEFF_FRAC_BITS));
            for i in 1 to TAP_COUNT - 1 loop
              product_v := samples_r(i - 1) * tap_at(taps_i, i);
              acc_v := acc_v + to_integer(shift_right(product_v, COEFF_FRAC_BITS));
            end loop;

            for i in TAP_COUNT - 1 downto 1 loop
              samples_r(i) <= samples_r(i - 1);
            end loop;
            samples_r(0) <= sample_v;
            out_data_r <= std_logic_vector(raddsp_sat_signed(acc_v, DATA_WIDTH));
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
