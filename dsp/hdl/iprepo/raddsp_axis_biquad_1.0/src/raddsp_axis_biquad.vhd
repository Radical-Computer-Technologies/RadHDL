library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- Multi-channel AXI-stream biquad IIR filter.
-- Applies configurable fixed-point second-order-section coefficients to each channel while preserving ready/valid and frame metadata.
entity raddsp_axis_biquad is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets the bit width for COEFF WIDTH values carried by this module.
    COEFF_WIDTH     : positive := 18;
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
    -- Input b0 i signal for this module.
    b0_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input b1 i signal for this module.
    b1_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input b2 i signal for this module.
    b2_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input a1 i signal for this module.
    a1_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input a2 i signal for this module.
    a2_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
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

architecture rtl of raddsp_axis_biquad is
  constant C_PRODUCT_WIDTH : positive := DATA_WIDTH + COEFF_WIDTH;
  constant C_ACC_WIDTH     : positive := C_PRODUCT_WIDTH + 4;

  signal x1_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal x2_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal y1_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal y2_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal ready_i     : std_logic;
begin
  assert COEFF_FRAC_BITS < C_ACC_WIDTH
    report "COEFF_FRAC_BITS is too large"
    severity failure;

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
    variable x_v       : signed(DATA_WIDTH - 1 downto 0);
    variable p_b0_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
    variable p_b1_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
    variable p_b2_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
    variable p_a1_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
    variable p_a2_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
    variable acc_v     : signed(C_ACC_WIDTH - 1 downto 0);
    variable scaled_v  : signed(C_ACC_WIDTH - 1 downto 0);
    variable y_next_v  : signed(DATA_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        x1_r <= (others => '0');
        x2_r <= (others => '0');
        y1_r <= (others => '0');
        y2_r <= (others => '0');
        out_valid_r <= '0';
        out_data_r <= (others => '0');
        out_last_r <= '0';
      else
        if clear_i = '1' then
          x1_r <= (others => '0');
          x2_r <= (others => '0');
          y1_r <= (others => '0');
          y2_r <= (others => '0');
        end if;

        if ready_i = '1' then
          out_valid_r <= s_axis_tvalid;
          out_last_r <= s_axis_tlast;

          if s_axis_tvalid = '1' then
            x_v := signed(s_axis_tdata);
            p_b0_v := x_v * signed(b0_i);
            p_b1_v := x1_r * signed(b1_i);
            p_b2_v := x2_r * signed(b2_i);
            p_a1_v := y1_r * signed(a1_i);
            p_a2_v := y2_r * signed(a2_i);
            acc_v := resize(p_b0_v, C_ACC_WIDTH)
                   + resize(p_b1_v, C_ACC_WIDTH)
                   + resize(p_b2_v, C_ACC_WIDTH)
                   - resize(p_a1_v, C_ACC_WIDTH)
                   - resize(p_a2_v, C_ACC_WIDTH);
            scaled_v := shift_right(acc_v, COEFF_FRAC_BITS);
            y_next_v := raddsp_sat_signed_vec(scaled_v, DATA_WIDTH);

            x2_r <= x1_r;
            x1_r <= x_v;
            y2_r <= y1_r;
            y1_r <= y_next_v;
            out_data_r <= std_logic_vector(y_next_v);
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
