library ieee;
use ieee.std_logic_1164.all;

library radhdl;
use radhdl.radhdl_axis_pkg.all;

-- Synthesis smoke top for RADHDL AXI-stream record helpers.
-- Keeps scalar top-level ports while exercising record construction and field
-- extraction inside RTL, matching the intended Vivado-safe usage pattern.
entity axis_record_synth_smoke is
  port (
    clk     : in  std_logic;
    rstn    : in  std_logic;
    s_valid : in  std_logic;
    s_data  : in  std_logic_vector(15 downto 0);
    s_last  : in  std_logic;
    s_ready : out std_logic;
    m_valid : out std_logic;
    m_ready : in  std_logic;
    m_data  : out std_logic_vector(15 downto 0);
    m_last  : out std_logic
  );
end entity;

architecture rtl of axis_record_synth_smoke is
  signal s_i : axis16_saxis_i_t := AXIS16_SAXIS_I_NULL;
  signal s_o : axis16_saxis_o_t := AXIS_SAXIS_O_NULL;
  signal m_i : axis16_maxis_i_t := AXIS_MAXIS_I_NULL;
  signal m_o : axis16_maxis_o_t := AXIS16_MAXIS_O_NULL;
begin
  s_i <= axis16_saxis_i(s_valid, s_data, s_last);
  s_o <= axis_saxis_o(m_i.tready);
  m_i <= axis_maxis_i(m_ready);
  m_o <= axis16_maxis_o(s_i.tvalid, s_i.tdata, s_i.tlast);

  s_ready <= s_o.tready;
  m_valid <= m_o.tvalid;
  m_data <= m_o.tdata;
  m_last <= m_o.tlast;
end architecture;
