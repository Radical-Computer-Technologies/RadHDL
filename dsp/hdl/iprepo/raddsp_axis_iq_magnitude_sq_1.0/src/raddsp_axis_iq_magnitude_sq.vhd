library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI-stream complex magnitude-squared stage for IQ samples.
-- Computes I*I plus Q*Q energy values for detection, normalization, and spectral analysis pipelines.
entity raddsp_axis_iq_magnitude_sq is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR        : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH    : positive := 16;
    -- Sets the bit width for MAG WIDTH values carried by this module.
    MAG_WIDTH     : positive := 32
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
    s_axis_tdata  : in  std_logic_vector((2 * DATA_WIDTH) - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector(MAG_WIDTH - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_iq_magnitude_sq is
  signal out_valid_r : std_logic := '0';
  signal out_data_r  : std_logic_vector(MAG_WIDTH - 1 downto 0) := (others => '0');
  signal out_last_r  : std_logic := '0';
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
    variable i_v   : signed(DATA_WIDTH - 1 downto 0);
    variable q_v   : signed(DATA_WIDTH - 1 downto 0);
    variable ii_v  : signed((2 * DATA_WIDTH) - 1 downto 0);
    variable qq_v  : signed((2 * DATA_WIDTH) - 1 downto 0);
    variable sum_v : unsigned((2 * DATA_WIDTH) downto 0);
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
          i_v := signed(s_axis_tdata((2 * DATA_WIDTH) - 1 downto DATA_WIDTH));
          q_v := signed(s_axis_tdata(DATA_WIDTH - 1 downto 0));
          ii_v := i_v * i_v;
          qq_v := q_v * q_v;
          sum_v := resize(unsigned(ii_v), sum_v'length) + resize(unsigned(qq_v), sum_v'length);
          out_data_r <= std_logic_vector(resize(sum_v, MAG_WIDTH));
        end if;
      end if;
    end if;
  end process;
end architecture;
