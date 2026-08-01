library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- TDM four-oscillator mono-to-stereo pan/mix stage.
-- Uses one explicit Gowin multiplier to compute eight pan products across
-- several sysclk cycles after each audio sample tick.
entity raddsp_audio_quad_osc_pan_mixer is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    COEFF_WIDTH     : positive := 18;
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    sample0_i : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    sample1_i : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    sample2_i : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    sample3_i : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_i   : in  std_logic;
    pan_word_i : in std_logic_vector(31 downto 0);
    left_o    : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_o   : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o   : out std_logic;
    busy_o    : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_quad_osc_pan_mixer is
  type state_t is (IDLE, LAUNCH, WAIT_0, WAIT_1, ACCUM, DONE);

  signal state     : state_t := IDLE;
  signal osc_idx   : natural range 0 to 3 := 0;
  signal side_idx  : std_logic := '0';
  signal left_acc  : signed(SAMPLE_WIDTH + 3 downto 0) := (others => '0');
  signal right_acc : signed(SAMPLE_WIDTH + 3 downto 0) := (others => '0');
  signal left_r    : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal right_r   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r   : std_logic := '0';
  signal mult_a    : std_logic_vector(26 downto 0) := (others => '0');
  signal mult_b    : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal mult_p    : std_logic_vector(44 downto 0);

  function pan_or_center(pan : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    if pan = x"00" then
      return x"80";
    end if;
    return pan;
  end function;

  function select_sample(
    idx : natural;
    s0  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    s1  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    s2  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    s3  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0)
  ) return std_logic_vector is
  begin
    case idx is
      when 0 => return s0;
      when 1 => return s1;
      when 2 => return s2;
      when others => return s3;
    end case;
  end function;

  function select_pan(idx : natural; pan_word : std_logic_vector(31 downto 0)) return std_logic_vector is
  begin
    case idx is
      when 0 => return pan_or_center(pan_word(7 downto 0));
      when 1 => return pan_or_center(pan_word(15 downto 8));
      when 2 => return pan_or_center(pan_word(23 downto 16));
      when others => return pan_or_center(pan_word(31 downto 24));
    end case;
  end function;

  function pan_coeff(pan : std_logic_vector(7 downto 0); right_side : boolean) return std_logic_vector is
    variable pan_u   : unsigned(7 downto 0);
    variable amount  : unsigned(7 downto 0);
    variable coeff_u : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  begin
    pan_u := unsigned(pan);
    if right_side then
      amount := pan_u;
    else
      amount := 255 - pan_u;
    end if;
    coeff_u(COEFF_FRAC_BITS - 1 downto COEFF_FRAC_BITS - 8) := amount;
    return std_logic_vector(coeff_u);
  end function;
begin
  left_o <= left_r;
  right_o <= right_r;
  valid_o <= valid_r;
  busy_o <= '1' when state /= IDLE else '0';

  u_pan_mult : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => mult_a,
      b_i => mult_b,
      p_o => mult_p
    );

  process(clk)
    variable product_v : signed(44 downto 0);
    variable scaled_v  : signed(SAMPLE_WIDTH + 3 downto 0);
  begin
    if rising_edge(clk) then
      valid_r <= '0';
      if rst = '1' then
        state <= IDLE;
        osc_idx <= 0;
        side_idx <= '0';
        left_acc <= (others => '0');
        right_acc <= (others => '0');
        left_r <= (others => '0');
        right_r <= (others => '0');
      else
        case state is
          when IDLE =>
            if valid_i = '1' then
              osc_idx <= 0;
              side_idx <= '0';
              left_acc <= (others => '0');
              right_acc <= (others => '0');
              state <= LAUNCH;
            end if;

          when LAUNCH =>
            mult_a <= std_logic_vector(resize(signed(select_sample(osc_idx, sample0_i, sample1_i, sample2_i, sample3_i)), 27));
            mult_b <= pan_coeff(select_pan(osc_idx, pan_word_i), side_idx = '1');
            state <= WAIT_0;

          when WAIT_0 =>
            state <= WAIT_1;

          when WAIT_1 =>
            state <= ACCUM;

          when ACCUM =>
            product_v := signed(mult_p);
            scaled_v := resize(shift_right(product_v, COEFF_FRAC_BITS), scaled_v'length);
            if side_idx = '0' then
              left_acc <= left_acc + scaled_v;
              side_idx <= '1';
              state <= LAUNCH;
            else
              right_acc <= right_acc + scaled_v;
              side_idx <= '0';
              if osc_idx = 3 then
                state <= DONE;
              else
                osc_idx <= osc_idx + 1;
                state <= LAUNCH;
              end if;
            end if;

          when DONE =>
            left_r <= std_logic_vector(raddsp_sat_signed_vec(left_acc, SAMPLE_WIDTH));
            right_r <= std_logic_vector(raddsp_sat_signed_vec(right_acc, SAMPLE_WIDTH));
            valid_r <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
