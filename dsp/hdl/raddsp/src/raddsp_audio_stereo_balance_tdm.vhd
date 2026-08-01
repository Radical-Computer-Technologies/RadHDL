library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- TDM global stereo balance/pan stage using one explicit Gowin multiplier.
-- pan_i uses 0x80 as center. An unwritten 0x00 pan register is treated as center.
entity raddsp_audio_stereo_balance_tdm is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    COEFF_WIDTH     : positive := 18;
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    left_i   : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_i  : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_i  : in  std_logic;
    pan_i    : in  std_logic_vector(7 downto 0);
    left_o   : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_o  : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o  : out std_logic;
    busy_o   : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_stereo_balance_tdm is
  type state_t is (IDLE, LAUNCH_LEFT, WAIT_LEFT_0, WAIT_LEFT_1, ACCUM_LEFT, LAUNCH_RIGHT, WAIT_RIGHT_0, WAIT_RIGHT_1, DONE);

  signal state     : state_t := IDLE;
  signal left_hold : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal right_hold : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal left_r    : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal right_r   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r   : std_logic := '0';
  signal mult_a    : std_logic_vector(26 downto 0) := (others => '0');
  signal mult_b    : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal mult_p    : std_logic_vector(44 downto 0);

  function pan_or_center(pan : std_logic_vector(7 downto 0)) return unsigned is
  begin
    if pan = x"00" then
      return to_unsigned(128, 8);
    end if;
    return unsigned(pan);
  end function;

  function unity_coeff return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(32767, COEFF_WIDTH));
  end function;

  function balance_coeff(pan : std_logic_vector(7 downto 0); right_side : boolean) return std_logic_vector is
    variable pan_u   : unsigned(7 downto 0);
    variable amount  : unsigned(7 downto 0);
    variable coeff_u : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  begin
    pan_u := pan_or_center(pan);
    if pan_u = to_unsigned(128, pan_u'length) then
      return unity_coeff;
    elsif right_side then
      if pan_u > to_unsigned(128, pan_u'length) then
        return unity_coeff;
      end if;
      amount := pan_u(7 downto 0);
    else
      if pan_u < to_unsigned(128, pan_u'length) then
        return unity_coeff;
      end if;
      amount := 255 - pan_u;
    end if;
    coeff_u(COEFF_FRAC_BITS downto COEFF_FRAC_BITS - 7) := amount;
    return std_logic_vector(coeff_u);
  end function;
begin
  left_o <= left_r;
  right_o <= right_r;
  valid_o <= valid_r;
  busy_o <= '1' when state /= IDLE else '0';

  u_balance_mult : entity work.raddsp_gowin_multalu27x18_mul
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
  begin
    if rising_edge(clk) then
      valid_r <= '0';
      if rst = '1' then
        state <= IDLE;
        left_hold <= (others => '0');
        right_hold <= (others => '0');
        left_r <= (others => '0');
        right_r <= (others => '0');
      else
        case state is
          when IDLE =>
            if valid_i = '1' then
              left_hold <= left_i;
              right_hold <= right_i;
              state <= LAUNCH_LEFT;
            end if;

          when LAUNCH_LEFT =>
            mult_a <= std_logic_vector(resize(signed(left_hold), 27));
            mult_b <= balance_coeff(pan_i, false);
            state <= WAIT_LEFT_0;

          when WAIT_LEFT_0 =>
            state <= WAIT_LEFT_1;

          when WAIT_LEFT_1 =>
            state <= ACCUM_LEFT;

          when ACCUM_LEFT =>
            product_v := signed(mult_p);
            left_r <= std_logic_vector(raddsp_sat_signed_vec(shift_right(product_v, COEFF_FRAC_BITS), SAMPLE_WIDTH));
            state <= LAUNCH_RIGHT;

          when LAUNCH_RIGHT =>
            mult_a <= std_logic_vector(resize(signed(right_hold), 27));
            mult_b <= balance_coeff(pan_i, true);
            state <= WAIT_RIGHT_0;

          when WAIT_RIGHT_0 =>
            state <= WAIT_RIGHT_1;

          when WAIT_RIGHT_1 =>
            state <= DONE;

          when DONE =>
            product_v := signed(mult_p);
            right_r <= std_logic_vector(raddsp_sat_signed_vec(shift_right(product_v, COEFF_FRAC_BITS), SAMPLE_WIDTH));
            valid_r <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
