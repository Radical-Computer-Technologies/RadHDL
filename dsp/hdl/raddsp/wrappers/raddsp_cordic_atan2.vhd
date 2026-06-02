library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity raddsp_cordic_atan2 is
  generic (
    G_INPUT_WIDTH : positive := 16;
    G_PHASE_WIDTH : positive := 32;
    G_ITERATIONS  : positive := 24
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    input_valid  : in  std_logic;
    x_in         : in  std_logic_vector(G_INPUT_WIDTH - 1 downto 0);
    y_in         : in  std_logic_vector(G_INPUT_WIDTH - 1 downto 0);
    input_ready  : out std_logic;
    busy         : out std_logic;
    phase_valid  : out std_logic;
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
