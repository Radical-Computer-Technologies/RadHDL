library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- AXI-stream one-pole low-pass filter.
-- Implements a lightweight recursive smoothing stage for control, envelope, and slowly varying DSP signals.
entity raddsp_axis_one_pole_lowpass is
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
    -- Input alpha i signal for this module.
    alpha_i       : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
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

architecture rtl of raddsp_axis_one_pole_lowpass is
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
  signal y_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal ready_i     : std_logic;
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
    variable x_v      : signed(DATA_WIDTH - 1 downto 0);
    variable delta_v  : signed(DATA_WIDTH downto 0);
    variable prod_v   : signed(DATA_WIDTH + COEFF_WIDTH + 1 downto 0);
    variable step_v   : signed(DATA_WIDTH + COEFF_WIDTH + 1 downto 0);
    variable next_int : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        out_valid_r <= '0';
        out_data_r <= (others => '0');
        out_last_r <= '0';
        y_r <= (others => '0');
      else
        if clear_i = '1' then
          y_r <= (others => '0');
        end if;

        if ready_i = '1' then
          out_valid_r <= s_axis_tvalid;
          out_last_r <= s_axis_tlast;
          if s_axis_tvalid = '1' then
            x_v := signed(s_axis_tdata);
            delta_v := resize(x_v, DATA_WIDTH + 1) - resize(y_r, DATA_WIDTH + 1);
            prod_v := delta_v * signed('0' & alpha_i);
            step_v := shift_right(prod_v, COEFF_FRAC_BITS);
            next_int := to_integer(y_r) + to_integer(step_v);
            y_r <= raddsp_sat_signed(next_int, DATA_WIDTH);
            out_data_r <= std_logic_vector(raddsp_sat_signed(next_int, DATA_WIDTH));
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
