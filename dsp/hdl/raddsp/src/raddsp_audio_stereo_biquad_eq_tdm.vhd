library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Stereo cascaded biquad EQ for audio streams.
-- Five sections are active by default for the FPiGA audio-hat path. Each
-- coefficient is signed Q3.28 and is loaded by software into a shadow bank.
-- A commit request slews the active bank toward the shadow bank at audio-idle
-- time; the audio datapath itself uses two 27x32 product engines, i.e. four
-- Gowin MULTALU27X18 blocks total.
entity raddsp_audio_stereo_biquad_eq_tdm is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    SECTION_COUNT   : positive := 5;
    COEFF_FRAC_BITS : natural  := 28
  );
  port (
    clk             : in  std_logic;
    rst             : in  std_logic;
    enable_i        : in  std_logic;
    left_i          : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_i         : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_i         : in  std_logic;
    coeff_wr_en_i   : in  std_logic;
    coeff_index_i   : in  std_logic_vector(7 downto 0);
    coeff_data_i    : in  std_logic_vector(31 downto 0);
    commit_i        : in  std_logic;
    smooth_shift_i  : in  std_logic_vector(3 downto 0);
    left_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_o         : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o         : out std_logic;
    busy_o          : out std_logic;
    smoothing_o     : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_stereo_biquad_eq_tdm is
  constant C_COEFFS_PER_SECTION : natural := 5;
  constant C_COEFF_COUNT        : natural := SECTION_COUNT * C_COEFFS_PER_SECTION;
  constant C_Q_UNITY            : signed(31 downto 0) := to_signed(2 ** COEFF_FRAC_BITS, 32);

  subtype sample_t is signed(SAMPLE_WIDTH - 1 downto 0);
  subtype coeff_t is signed(31 downto 0);
  subtype acc_t is signed(SAMPLE_WIDTH + 34 downto 0);

  type coeff_bank_t is array (0 to SECTION_COUNT - 1) of coeff_t;
  type sample_array_t is array (0 to SECTION_COUNT - 1) of sample_t;

  function init_b0_coeffs return coeff_bank_t is
    variable result : coeff_bank_t := (others => C_Q_UNITY);
  begin
    return result;
  end function;

  function init_zero_coeffs return coeff_bank_t is
    variable result : coeff_bank_t := (others => (others => '0'));
  begin
    return result;
  end function;

  type state_t is (
    IDLE,
    PREP_SECTION,
    LAUNCH_G0, WAIT_G0_0, WAIT_G0_1, WAIT_G0_2, ACC_G0,
    LAUNCH_G1, WAIT_G1_0, WAIT_G1_1, WAIT_G1_2, ACC_G1,
    LAUNCH_G2, WAIT_G2_0, WAIT_G2_1, WAIT_G2_2, ACC_G2, FINISH_SECTION,
    ADVANCE_SECTION
  );

  signal state       : state_t := IDLE;
  signal section_idx : integer range 0 to SECTION_COUNT - 1 := 0;
  signal section_sel : std_logic_vector(0 to SECTION_COUNT - 1) := (0 => '1', others => '0');
  signal section_last_r : std_logic := '0';
  signal channel_idx : integer range 0 to 1 := 0;
  signal section_in  : sample_t := (others => '0');
  signal next_section_in : sample_t := (others => '0');
  signal acc_r       : acc_t := (others => '0');
  signal b0_r        : coeff_t := C_Q_UNITY;
  signal b1_r        : coeff_t := (others => '0');
  signal b2_r        : coeff_t := (others => '0');
  signal a1_r        : coeff_t := (others => '0');
  signal a2_r        : coeff_t := (others => '0');
  signal x1_r        : sample_t := (others => '0');
  signal x2_r        : sample_t := (others => '0');
  signal y1_r        : sample_t := (others => '0');
  signal y2_r        : sample_t := (others => '0');

  signal active_b0 : coeff_bank_t := init_b0_coeffs;
  signal active_b1 : coeff_bank_t := init_zero_coeffs;
  signal active_b2 : coeff_bank_t := init_zero_coeffs;
  signal active_a1 : coeff_bank_t := init_zero_coeffs;
  signal active_a2 : coeff_bank_t := init_zero_coeffs;
  signal shadow_b0 : coeff_bank_t := init_b0_coeffs;
  signal shadow_b1 : coeff_bank_t := init_zero_coeffs;
  signal shadow_b2 : coeff_bank_t := init_zero_coeffs;
  signal shadow_a1 : coeff_bank_t := init_zero_coeffs;
  signal shadow_a2 : coeff_bank_t := init_zero_coeffs;
  signal smooth_idx   : integer range 0 to C_COEFF_COUNT - 1 := 0;
  signal commit_copy_r : std_logic := '0';
  signal commit_r : std_logic := '0';
  signal coeff_wr_en_r : std_logic := '0';
  signal coeff_index_r : std_logic_vector(7 downto 0) := (others => '0');
  signal coeff_data_r  : std_logic_vector(31 downto 0) := (others => '0');

  signal left_x1  : sample_array_t := (others => (others => '0'));
  signal left_x2  : sample_array_t := (others => (others => '0'));
  signal left_y1  : sample_array_t := (others => (others => '0'));
  signal left_y2  : sample_array_t := (others => (others => '0'));
  signal right_x1 : sample_array_t := (others => (others => '0'));
  signal right_x2 : sample_array_t := (others => (others => '0'));
  signal right_y1 : sample_array_t := (others => (others => '0'));
  signal right_y2 : sample_array_t := (others => (others => '0'));

  signal left_r  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal right_r : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r : std_logic := '0';

  signal mul0_a : std_logic_vector(26 downto 0) := (others => '0');
  signal mul1_a : std_logic_vector(26 downto 0) := (others => '0');
  signal mul0_b : std_logic_vector(31 downto 0) := (others => '0');
  signal mul1_b : std_logic_vector(31 downto 0) := (others => '0');
  signal mul0_p : std_logic_vector(63 downto 0);
  signal mul1_p : std_logic_vector(63 downto 0);

  function to_mul_a(value : sample_t) return std_logic_vector is
  begin
    return std_logic_vector(resize(value, 27));
  end function;

  function first_section_sel return std_logic_vector is
    variable result : std_logic_vector(0 to SECTION_COUNT - 1) := (others => '0');
  begin
    result(0) := '1';
    return result;
  end function;

  function next_section_sel(sel : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(sel'range) := (others => '0');
  begin
    for i in sel'low to sel'high - 1 loop
      result(i + 1) := sel(i);
    end loop;
    return result;
  end function;

  function section_state_by_sel(channel : integer; sel : std_logic_vector; l : sample_array_t; r : sample_array_t) return sample_t is
    variable result : sample_t := (others => '0');
  begin
    for i in 0 to SECTION_COUNT - 1 loop
      if sel(i) = '1' then
        if channel = 0 then
          result := l(i);
        else
          result := r(i);
        end if;
      end if;
    end loop;
    return result;
  end function;

begin
  left_o <= left_r;
  right_o <= right_r;
  valid_o <= valid_r;
  busy_o <= '1' when state /= IDLE else '0';
  smoothing_o <= commit_copy_r;

  u_mul0 : entity work.raddsp_gowin_multalu27x32_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => mul0_a,
      b_i => mul0_b,
      p_o => mul0_p
    );

  u_mul1 : entity work.raddsp_gowin_multalu27x32_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => mul1_a,
      b_i => mul1_b,
      p_o => mul1_p
    );

  process(clk)
    variable coeff_wr_idx_v : natural;
    variable coeff_section_v : natural;
    variable coeff_sel_v     : natural;
    variable y_v            : sample_t;
    variable shifted_v      : acc_t;
  begin
    if rising_edge(clk) then
      valid_r <= '0';

      if rst = '1' then
        state <= IDLE;
        section_idx <= 0;
        section_sel <= first_section_sel;
        section_last_r <= '0';
        channel_idx <= 0;
        section_in <= (others => '0');
        next_section_in <= (others => '0');
        acc_r <= (others => '0');
        b0_r <= C_Q_UNITY;
        b1_r <= (others => '0');
        b2_r <= (others => '0');
        a1_r <= (others => '0');
        a2_r <= (others => '0');
        x1_r <= (others => '0');
        x2_r <= (others => '0');
        y1_r <= (others => '0');
        y2_r <= (others => '0');
        active_b0 <= init_b0_coeffs;
        active_b1 <= init_zero_coeffs;
        active_b2 <= init_zero_coeffs;
        active_a1 <= init_zero_coeffs;
        active_a2 <= init_zero_coeffs;
        shadow_b0 <= init_b0_coeffs;
        shadow_b1 <= init_zero_coeffs;
        shadow_b2 <= init_zero_coeffs;
        shadow_a1 <= init_zero_coeffs;
        shadow_a2 <= init_zero_coeffs;
        smooth_idx <= 0;
        commit_copy_r <= '0';
        commit_r <= '0';
        coeff_wr_en_r <= '0';
        coeff_index_r <= (others => '0');
        coeff_data_r <= (others => '0');
        left_x1 <= (others => (others => '0'));
        left_x2 <= (others => (others => '0'));
        left_y1 <= (others => (others => '0'));
        left_y2 <= (others => (others => '0'));
        right_x1 <= (others => (others => '0'));
        right_x2 <= (others => (others => '0'));
        right_y1 <= (others => (others => '0'));
        right_y2 <= (others => (others => '0'));
        left_r <= (others => '0');
        right_r <= (others => '0');
        mul0_a <= (others => '0');
        mul1_a <= (others => '0');
        mul0_b <= (others => '0');
        mul1_b <= (others => '0');
      else
        commit_copy_r <= '0';
        commit_r <= commit_i;
        coeff_wr_en_r <= coeff_wr_en_i;
        coeff_index_r <= coeff_index_i;
        coeff_data_r <= coeff_data_i;

        if coeff_wr_en_r = '1' then
          coeff_wr_idx_v := to_integer(unsigned(coeff_index_r));
          if coeff_wr_idx_v < C_COEFF_COUNT then
            coeff_section_v := coeff_wr_idx_v / C_COEFFS_PER_SECTION;
            coeff_sel_v := coeff_wr_idx_v mod C_COEFFS_PER_SECTION;
            case coeff_sel_v is
              when 0 => shadow_b0(coeff_section_v) <= signed(coeff_data_r);
              when 1 => shadow_b1(coeff_section_v) <= signed(coeff_data_r);
              when 2 => shadow_b2(coeff_section_v) <= signed(coeff_data_r);
              when 3 => shadow_a1(coeff_section_v) <= signed(coeff_data_r);
              when others => shadow_a2(coeff_section_v) <= signed(coeff_data_r);
            end case;
          end if;
        end if;

        if commit_r = '1' and state = IDLE then
          active_b0 <= shadow_b0;
          active_b1 <= shadow_b1;
          active_b2 <= shadow_b2;
          active_a1 <= shadow_a1;
          active_a2 <= shadow_a2;
          commit_copy_r <= '1';
        end if;

        case state is
          when IDLE =>
            if valid_i = '1' then
              if enable_i = '0' then
                left_r <= left_i;
                right_r <= right_i;
                valid_r <= '1';
              else
                channel_idx <= 0;
                section_idx <= 0;
                section_sel <= first_section_sel;
                section_in <= signed(left_i);
                state <= PREP_SECTION;
              end if;
            end if;

          when PREP_SECTION =>
            if section_idx = SECTION_COUNT - 1 then
              section_last_r <= '1';
            else
              section_last_r <= '0';
            end if;
            b0_r <= active_b0(section_idx);
            b1_r <= active_b1(section_idx);
            b2_r <= active_b2(section_idx);
            a1_r <= active_a1(section_idx);
            a2_r <= active_a2(section_idx);
            x1_r <= section_state_by_sel(channel_idx, section_sel, left_x1, right_x1);
            x2_r <= section_state_by_sel(channel_idx, section_sel, left_x2, right_x2);
            y1_r <= section_state_by_sel(channel_idx, section_sel, left_y1, right_y1);
            y2_r <= section_state_by_sel(channel_idx, section_sel, left_y2, right_y2);
            state <= LAUNCH_G0;

          when LAUNCH_G0 =>
            mul0_a <= to_mul_a(section_in);
            mul0_b <= std_logic_vector(b0_r);
            mul1_a <= to_mul_a(x1_r);
            mul1_b <= std_logic_vector(b1_r);
            state <= WAIT_G0_0;

          when WAIT_G0_0 =>
            state <= WAIT_G0_1;

          when WAIT_G0_1 =>
            state <= WAIT_G0_2;

          when WAIT_G0_2 =>
            state <= ACC_G0;

          when ACC_G0 =>
            acc_r <= resize(signed(mul0_p), acc_r'length) + resize(signed(mul1_p), acc_r'length);
            state <= LAUNCH_G1;

          when LAUNCH_G1 =>
            mul0_a <= to_mul_a(x2_r);
            mul0_b <= std_logic_vector(b2_r);
            mul1_a <= to_mul_a(y1_r);
            mul1_b <= std_logic_vector(a1_r);
            state <= WAIT_G1_0;

          when WAIT_G1_0 =>
            state <= WAIT_G1_1;

          when WAIT_G1_1 =>
            state <= WAIT_G1_2;

          when WAIT_G1_2 =>
            state <= ACC_G1;

          when ACC_G1 =>
            acc_r <= acc_r + resize(signed(mul0_p), acc_r'length) - resize(signed(mul1_p), acc_r'length);
            state <= LAUNCH_G2;

          when LAUNCH_G2 =>
            mul0_a <= to_mul_a(y2_r);
            mul0_b <= std_logic_vector(a2_r);
            mul1_a <= (others => '0');
            mul1_b <= (others => '0');
            state <= WAIT_G2_0;

          when WAIT_G2_0 =>
            state <= WAIT_G2_1;

          when WAIT_G2_1 =>
            state <= WAIT_G2_2;

          when WAIT_G2_2 =>
            state <= ACC_G2;

          when ACC_G2 =>
            acc_r <= acc_r - resize(signed(mul0_p), acc_r'length);
            state <= FINISH_SECTION;

          when FINISH_SECTION =>
            shifted_v := shift_right(acc_r, COEFF_FRAC_BITS);
            y_v := raddsp_sat_signed_vec(shifted_v, SAMPLE_WIDTH);
            next_section_in <= y_v;

            if channel_idx = 0 then
              for i in 0 to SECTION_COUNT - 1 loop
                if section_sel(i) = '1' then
                  left_x2(i) <= left_x1(i);
                  left_x1(i) <= section_in;
                  left_y2(i) <= left_y1(i);
                  left_y1(i) <= y_v;
                end if;
              end loop;
            else
              for i in 0 to SECTION_COUNT - 1 loop
                if section_sel(i) = '1' then
                  right_x2(i) <= right_x1(i);
                  right_x1(i) <= section_in;
                  right_y2(i) <= right_y1(i);
                  right_y1(i) <= y_v;
                end if;
              end loop;
            end if;

            if section_last_r = '1' then
              if channel_idx = 0 then
                left_r <= std_logic_vector(y_v);
                channel_idx <= 1;
                section_idx <= 0;
                section_sel <= first_section_sel;
                section_in <= signed(right_i);
                state <= PREP_SECTION;
              else
                right_r <= std_logic_vector(y_v);
                valid_r <= '1';
                state <= IDLE;
              end if;
            else
              section_idx <= section_idx + 1;
              state <= ADVANCE_SECTION;
            end if;

          when ADVANCE_SECTION =>
            section_in <= next_section_in;
            section_sel <= next_section_sel(section_sel);
            state <= PREP_SECTION;
        end case;
      end if;
    end if;
  end process;
end architecture;
