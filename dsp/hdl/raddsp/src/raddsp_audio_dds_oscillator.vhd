library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Audio DDS oscillator with explicit Gowin multiplier-backed gain.
entity raddsp_audio_dds_oscillator is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    WAVE_WIDTH      : positive := 16;
    PHASE_WIDTH     : positive := 24;
    COEFF_WIDTH     : positive := 18;
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    enable_i      : in  std_logic;
    phase_inc_i   : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    wave_select_i : in  std_logic_vector(1 downto 0);
    gain_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    sample_o      : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o       : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_dds_oscillator is
  constant RAW_TO_OUTPUT_LATENCY : natural := 3;
  signal phase_r      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal raw_sample_r : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_r     : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r      : std_logic := '0';
  signal valid_pipe   : std_logic_vector(RAW_TO_OUTPUT_LATENCY - 1 downto 0) := (others => '0');
  signal mult_a       : std_logic_vector(26 downto 0);
  signal mult_p       : std_logic_vector(44 downto 0);

  function dds_wave(phase : unsigned; wave_id : std_logic_vector(1 downto 0)) return signed is
    variable phase_top : std_logic_vector(WAVE_WIDTH - 1 downto 0);
    variable ramp      : signed(WAVE_WIDTH - 1 downto 0);
  begin
    phase_top := std_logic_vector(phase(PHASE_WIDTH - 1 downto PHASE_WIDTH - WAVE_WIDTH));
    ramp := signed(phase_top);
    case wave_id is
      when "00" =>
        return ramp;
      when "01" =>
        if phase(PHASE_WIDTH - 1) = '1' then
          return to_signed(2 ** (WAVE_WIDTH - 1) - 1, WAVE_WIDTH);
        end if;
        return to_signed(-2 ** (WAVE_WIDTH - 1), WAVE_WIDTH);
      when "10" =>
        if phase(PHASE_WIDTH - 1) = '1' then
          return signed(not phase_top);
        end if;
        return ramp;
      when others =>
        return -ramp;
    end case;
  end function;
begin
  sample_o <= sample_r;
  valid_o <= valid_r;
  mult_a <= std_logic_vector(resize(raw_sample_r, 27));

  u_gain_mult : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => mult_a,
      b_i => gain_i,
      p_o => mult_p
    );

  process(clk)
    variable next_phase_v : unsigned(PHASE_WIDTH - 1 downto 0);
    variable scaled_v     : signed(44 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase_r <= (others => '0');
        raw_sample_r <= (others => '0');
        sample_r <= (others => '0');
        valid_r <= '0';
        valid_pipe <= (others => '0');
      else
        valid_pipe <= valid_pipe(valid_pipe'high - 1 downto 0) & enable_i;

        if enable_i = '1' then
          next_phase_v := phase_r + unsigned(phase_inc_i);
          phase_r <= next_phase_v;
          raw_sample_r <= dds_wave(next_phase_v, wave_select_i);
        end if;

        valid_r <= valid_pipe(valid_pipe'high);
        if valid_pipe(valid_pipe'high) = '1' then
          scaled_v := signed(mult_p);
          sample_r <= std_logic_vector(
            raddsp_sat_signed_vec(
              shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
              SAMPLE_WIDTH
            )
          );
        end if;
      end if;
    end if;
  end process;
end architecture;
