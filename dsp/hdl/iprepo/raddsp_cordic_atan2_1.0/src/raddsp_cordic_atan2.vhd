library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI-stream wrapper around the fixed-point CORDIC atan2 engine.
-- Presents phase-estimation as a ready/valid streaming block for RadDSP dataflow pipelines.
entity raddsp_cordic_atan2 is
  generic (
    -- Sets the bit width for G INPUT WIDTH values carried by this module.
    G_INPUT_WIDTH : positive := 16;
    -- Sets the bit width for G PHASE WIDTH values carried by this module.
    G_PHASE_WIDTH : positive := 32;
    -- Configures G ITERATIONS for this instance.
    G_ITERATIONS  : positive := 24
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk          : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst          : in  std_logic;
    -- Input valid interface signal.
    input_valid  : in  std_logic;
    -- X in interface signal.
    x_in         : in  std_logic_vector(G_INPUT_WIDTH - 1 downto 0);
    -- Y in interface signal.
    y_in         : in  std_logic_vector(G_INPUT_WIDTH - 1 downto 0);
    -- Input ready interface signal.
    input_ready  : out std_logic;
    -- Busy interface signal.
    busy         : out std_logic;
    -- Phase valid interface signal.
    phase_valid  : out std_logic;
    -- Phase out interface signal.
    phase_out    : out std_logic_vector(G_PHASE_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of raddsp_cordic_atan2 is
  signal phase_out_s : signed(G_PHASE_WIDTH - 1 downto 0);
begin
  phase_out <= std_logic_vector(phase_out_s);

  core: entity work.cordic_atan2
    generic map (
      G_INPUT_WIDTH => G_INPUT_WIDTH,
      G_PHASE_WIDTH => G_PHASE_WIDTH,
      G_ITERATIONS => G_ITERATIONS
    )
    port map (
      clk => clk,
      rst => rst,
      input_valid => input_valid,
      x_in => signed(x_in),
      y_in => signed(y_in),
      input_ready => input_ready,
      busy => busy,
      phase_valid => phase_valid,
      phase_out => phase_out_s
    );
end architecture;
