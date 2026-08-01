library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Shared stereo pan, global EQ, and output gain pipeline.
-- This experimental board-level core replaces the standalone pan, EQ, and
-- gain stages with one deterministic TDM schedule using two 27x32 product
-- engines. Each product engine maps to two Gowin MULTALU27X18 blocks.
entity raddsp_audio_stereo_shared_pg_eq_tdm is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    SECTION_COUNT   : positive := 5;
    COEFF_FRAC_BITS : natural  := 28
  );
  port (
    clk             : in  std_logic;
    rst             : in  std_logic;
    eq_enable_i     : in  std_logic;
    left_i          : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_i         : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_i         : in  std_logic;
    pan_i           : in  std_logic_vector(7 downto 0);
    left_gain_i     : in  std_logic_vector(17 downto 0);
    right_gain_i    : in  std_logic_vector(17 downto 0);
    coeff_wr_en_i   : in  std_logic;
    coeff_index_i   : in  std_logic_vector(7 downto 0);
    coeff_data_i    : in  std_logic_vector(31 downto 0);
    commit_i        : in  std_logic;
    left_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_o         : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o         : out std_logic;
    busy_o          : out std_logic;
    commit_busy_o   : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_stereo_shared_pg_eq_tdm is
  constant C_COEFFS_PER_SECTION : natural := 5;
  constant C_COEFF_COUNT        : natural := SECTION_COUNT * C_COEFFS_PER_SECTION;
  constant C_Q_UNITY            : signed(31 downto 0) := to_signed(2 ** COEFF_FRAC_BITS, 32);
  constant C_SHADOW_ADDR_WIDTH  : natural := 6;

  subtype sample_t is signed(SAMPLE_WIDTH - 1 downto 0);
  subtype coeff_t is signed(31 downto 0);
  subtype acc_t is signed(63 downto 0);

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
    LAUNCH_PAN, WAIT_PAN_0, WAIT_PAN_1, WAIT_PAN_2, FINISH_PAN,
    PREP_SECTION, LOAD_COEFF_B0, LOAD_COEFF_B1, LOAD_COEFF_B2, LOAD_COEFF_A1, LOAD_COEFF_A2,
    LAUNCH_G0, WAIT_G0_0, WAIT_G0_1, WAIT_G0_2, ACC_G0,
    LAUNCH_G1, WAIT_G1_0, WAIT_G1_1, WAIT_G1_2, ACC_G1,
    LAUNCH_G2, WAIT_G2_0, WAIT_G2_1, WAIT_G2_2, ACC_G2, FINISH_SECTION,
    ADVANCE_SECTION,
    LAUNCH_GAIN, WAIT_GAIN_0, WAIT_GAIN_1, WAIT_GAIN_2, FINISH_GAIN
  );

  signal state       : state_t := IDLE;
  signal section_idx : integer range 0 to SECTION_COUNT - 1 := 0;
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

  signal active_coeff_bank_r : std_logic := '0';
  signal commit_pending_r : std_logic := '0';

  signal shadow_init_r      : std_logic := '1';
  signal shadow_init_idx    : integer range 0 to (2 * C_COEFF_COUNT) - 1 := 0;
  signal shadow_wr_en_r     : std_logic := '0';
  signal shadow_wr_addr_r   : std_logic_vector(C_SHADOW_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal shadow_wr_lo_r     : std_logic_vector(15 downto 0) := (others => '0');
  signal shadow_wr_hi_r     : std_logic_vector(15 downto 0) := (others => '0');
  signal shadow_rd_addr_r   : std_logic_vector(C_SHADOW_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal shadow_rd_lo       : std_logic_vector(15 downto 0);
  signal shadow_rd_hi       : std_logic_vector(15 downto 0);

  signal left_x1  : sample_array_t := (others => (others => '0'));
  signal left_x2  : sample_array_t := (others => (others => '0'));
  signal left_y1  : sample_array_t := (others => (others => '0'));
  signal left_y2  : sample_array_t := (others => (others => '0'));
  signal right_x1 : sample_array_t := (others => (others => '0'));
  signal right_x2 : sample_array_t := (others => (others => '0'));
  signal right_y1 : sample_array_t := (others => (others => '0'));
  signal right_y2 : sample_array_t := (others => (others => '0'));

  signal pan_left_r  : sample_t := (others => '0');
  signal pan_right_r : sample_t := (others => '0');
  signal eq_left_r   : sample_t := (others => '0');
  signal eq_right_r  : sample_t := (others => '0');
  signal left_out_r  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal right_out_r : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r     : std_logic := '0';

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

  function q15_to_q28(value : std_logic_vector(17 downto 0)) return coeff_t is
  begin
    return shift_left(resize(signed(value), 32), COEFF_FRAC_BITS - 15);
  end function;

  function pan_or_center(pan : std_logic_vector(7 downto 0)) return unsigned is
  begin
    if pan = x"00" then
      return to_unsigned(128, 8);
    end if;
    return unsigned(pan);
  end function;

  function balance_coeff(pan : std_logic_vector(7 downto 0); right_side : boolean) return coeff_t is
    variable pan_u   : unsigned(7 downto 0);
    variable amount  : unsigned(7 downto 0);
    variable coeff18 : std_logic_vector(17 downto 0) := (others => '0');
  begin
    pan_u := pan_or_center(pan);
    if pan_u = to_unsigned(128, pan_u'length) then
      return C_Q_UNITY;
    elsif right_side then
      if pan_u > to_unsigned(128, pan_u'length) then
        return C_Q_UNITY;
      end if;
      amount := pan_u;
    else
      if pan_u < to_unsigned(128, pan_u'length) then
        return C_Q_UNITY;
      end if;
      amount := 255 - pan_u;
    end if;
    coeff18(15 downto 8) := std_logic_vector(amount);
    return q15_to_q28(coeff18);
  end function;

  function state_x1(channel : integer; section : integer; l : sample_array_t; r : sample_array_t) return sample_t is
  begin
    if channel = 0 then
      return l(section);
    end if;
    return r(section);
  end function;

  function default_shadow_coeff(index : natural) return coeff_t is
    variable coeff_index_v : natural;
  begin
    coeff_index_v := index mod C_COEFF_COUNT;
    if (coeff_index_v mod C_COEFFS_PER_SECTION) = 0 then
      return C_Q_UNITY;
    end if;
    return (others => '0');
  end function;

  function coeff_index_for_section(section : integer; coeff_offset : natural) return natural is
  begin
    case section is
      when 0 => return coeff_offset;
      when 1 => return 5 + coeff_offset;
      when 2 => return 10 + coeff_offset;
      when 3 => return 15 + coeff_offset;
      when others => return 20 + coeff_offset;
    end case;
  end function;
begin
  assert SECTION_COUNT = 5
    report "raddsp_audio_stereo_shared_pg_eq_tdm banked coefficient address decode currently expects five sections"
    severity failure;

  assert (2 * C_COEFF_COUNT) <= 2 ** C_SHADOW_ADDR_WIDTH
    report "raddsp_audio_stereo_shared_pg_eq_tdm shadow coefficient memory address width is too small"
    severity failure;

  left_o <= left_out_r;
  right_o <= right_out_r;
  valid_o <= valid_r;
  busy_o <= '1' when state /= IDLE else '0';
  commit_busy_o <= commit_pending_r or shadow_init_r;

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

  u_shadow_lo : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_SHADOW_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => shadow_wr_en_r,
      wr_addr => shadow_wr_addr_r,
      wr_data => shadow_wr_lo_r,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => shadow_rd_addr_r,
      rd_data => shadow_rd_lo
    );

  u_shadow_hi : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_SHADOW_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => shadow_wr_en_r,
      wr_addr => shadow_wr_addr_r,
      wr_data => shadow_wr_hi_r,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => shadow_rd_addr_r,
      rd_data => shadow_rd_hi
    );

  process(clk)
    variable coeff_wr_idx_v  : natural;
    variable coeff_section_v : natural;
    variable coeff_sel_v     : natural;
    variable coeff_mem_v     : coeff_t;
    variable y_v             : sample_t;
    variable shifted_v       : acc_t;
  begin
    if rising_edge(clk) then
      valid_r <= '0';
      shadow_wr_en_r <= '0';

      if rst = '1' then
        state <= IDLE;
        section_idx <= 0;
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
        active_coeff_bank_r <= '0';
        commit_pending_r <= '0';
        shadow_init_r <= '1';
        shadow_init_idx <= 0;
        shadow_wr_addr_r <= (others => '0');
        shadow_wr_lo_r <= (others => '0');
        shadow_wr_hi_r <= (others => '0');
        shadow_rd_addr_r <= (others => '0');
        left_x1 <= (others => (others => '0'));
        left_x2 <= (others => (others => '0'));
        left_y1 <= (others => (others => '0'));
        left_y2 <= (others => (others => '0'));
        right_x1 <= (others => (others => '0'));
        right_x2 <= (others => (others => '0'));
        right_y1 <= (others => (others => '0'));
        right_y2 <= (others => (others => '0'));
        pan_left_r <= (others => '0');
        pan_right_r <= (others => '0');
        eq_left_r <= (others => '0');
        eq_right_r <= (others => '0');
        left_out_r <= (others => '0');
        right_out_r <= (others => '0');
        mul0_a <= (others => '0');
        mul1_a <= (others => '0');
        mul0_b <= (others => '0');
        mul1_b <= (others => '0');
      else
        if shadow_init_r = '1' then
          coeff_mem_v := default_shadow_coeff(shadow_init_idx);
          shadow_wr_en_r <= '1';
          shadow_wr_addr_r <= std_logic_vector(to_unsigned(shadow_init_idx, C_SHADOW_ADDR_WIDTH));
          shadow_wr_lo_r <= std_logic_vector(coeff_mem_v(15 downto 0));
          shadow_wr_hi_r <= std_logic_vector(coeff_mem_v(31 downto 16));
          if shadow_init_idx = (2 * C_COEFF_COUNT) - 1 then
            shadow_init_r <= '0';
            shadow_init_idx <= 0;
          else
            shadow_init_idx <= shadow_init_idx + 1;
          end if;
        elsif coeff_wr_en_i = '1' then
          coeff_wr_idx_v := to_integer(unsigned(coeff_index_i));
          if coeff_wr_idx_v < C_COEFF_COUNT then
            shadow_wr_en_r <= '1';
            shadow_wr_addr_r <= (not active_coeff_bank_r) &
                                std_logic_vector(to_unsigned(coeff_wr_idx_v, C_SHADOW_ADDR_WIDTH - 1));
            shadow_wr_lo_r <= coeff_data_i(15 downto 0);
            shadow_wr_hi_r <= coeff_data_i(31 downto 16);
          end if;
        end if;

        if commit_i = '1' then
          commit_pending_r <= '1';
        elsif state = IDLE and commit_pending_r = '1' and shadow_init_r = '0' then
          active_coeff_bank_r <= not active_coeff_bank_r;
          commit_pending_r <= '0';
        end if;

        case state is
          when IDLE =>
            if valid_i = '1' then
              mul0_a <= to_mul_a(signed(left_i));
              mul0_b <= std_logic_vector(balance_coeff(pan_i, false));
              mul1_a <= to_mul_a(signed(right_i));
              mul1_b <= std_logic_vector(balance_coeff(pan_i, true));
              state <= LAUNCH_PAN;
            end if;

          when LAUNCH_PAN =>
            state <= WAIT_PAN_0;

          when WAIT_PAN_0 =>
            state <= WAIT_PAN_1;

          when WAIT_PAN_1 =>
            state <= WAIT_PAN_2;

          when WAIT_PAN_2 =>
            state <= FINISH_PAN;

          when FINISH_PAN =>
            pan_left_r <= raddsp_sat_signed_vec(shift_right(signed(mul0_p), COEFF_FRAC_BITS), SAMPLE_WIDTH);
            pan_right_r <= raddsp_sat_signed_vec(shift_right(signed(mul1_p), COEFF_FRAC_BITS), SAMPLE_WIDTH);
            if eq_enable_i = '1' then
              channel_idx <= 0;
              section_idx <= 0;
              section_in <= raddsp_sat_signed_vec(shift_right(signed(mul0_p), COEFF_FRAC_BITS), SAMPLE_WIDTH);
              state <= PREP_SECTION;
            else
              eq_left_r <= raddsp_sat_signed_vec(shift_right(signed(mul0_p), COEFF_FRAC_BITS), SAMPLE_WIDTH);
              eq_right_r <= raddsp_sat_signed_vec(shift_right(signed(mul1_p), COEFF_FRAC_BITS), SAMPLE_WIDTH);
              state <= LAUNCH_GAIN;
            end if;

          when PREP_SECTION =>
            x1_r <= state_x1(channel_idx, section_idx, left_x1, right_x1);
            x2_r <= state_x1(channel_idx, section_idx, left_x2, right_x2);
            y1_r <= state_x1(channel_idx, section_idx, left_y1, right_y1);
            y2_r <= state_x1(channel_idx, section_idx, left_y2, right_y2);
            shadow_rd_addr_r <= active_coeff_bank_r &
                                std_logic_vector(to_unsigned(coeff_index_for_section(section_idx, 0),
                                                             C_SHADOW_ADDR_WIDTH - 1));
            state <= LOAD_COEFF_B0;

          when LOAD_COEFF_B0 =>
            b0_r <= signed(shadow_rd_hi & shadow_rd_lo);
            shadow_rd_addr_r <= active_coeff_bank_r &
                                std_logic_vector(to_unsigned(coeff_index_for_section(section_idx, 1),
                                                             C_SHADOW_ADDR_WIDTH - 1));
            state <= LOAD_COEFF_B1;

          when LOAD_COEFF_B1 =>
            b1_r <= signed(shadow_rd_hi & shadow_rd_lo);
            shadow_rd_addr_r <= active_coeff_bank_r &
                                std_logic_vector(to_unsigned(coeff_index_for_section(section_idx, 2),
                                                             C_SHADOW_ADDR_WIDTH - 1));
            state <= LOAD_COEFF_B2;

          when LOAD_COEFF_B2 =>
            b2_r <= signed(shadow_rd_hi & shadow_rd_lo);
            shadow_rd_addr_r <= active_coeff_bank_r &
                                std_logic_vector(to_unsigned(coeff_index_for_section(section_idx, 3),
                                                             C_SHADOW_ADDR_WIDTH - 1));
            state <= LOAD_COEFF_A1;

          when LOAD_COEFF_A1 =>
            a1_r <= signed(shadow_rd_hi & shadow_rd_lo);
            shadow_rd_addr_r <= active_coeff_bank_r &
                                std_logic_vector(to_unsigned(coeff_index_for_section(section_idx, 4),
                                                             C_SHADOW_ADDR_WIDTH - 1));
            state <= LOAD_COEFF_A2;

          when LOAD_COEFF_A2 =>
            a2_r <= signed(shadow_rd_hi & shadow_rd_lo);
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
            acc_r <= signed(mul0_p) + signed(mul1_p);
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
            acc_r <= acc_r + signed(mul0_p) - signed(mul1_p);
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
            acc_r <= acc_r - signed(mul0_p);
            state <= FINISH_SECTION;

          when FINISH_SECTION =>
            shifted_v := shift_right(acc_r, COEFF_FRAC_BITS);
            y_v := raddsp_sat_signed_vec(shifted_v, SAMPLE_WIDTH);
            next_section_in <= y_v;

            if channel_idx = 0 then
              left_x2(section_idx) <= left_x1(section_idx);
              left_x1(section_idx) <= section_in;
              left_y2(section_idx) <= left_y1(section_idx);
              left_y1(section_idx) <= y_v;
            else
              right_x2(section_idx) <= right_x1(section_idx);
              right_x1(section_idx) <= section_in;
              right_y2(section_idx) <= right_y1(section_idx);
              right_y1(section_idx) <= y_v;
            end if;

            if section_idx = SECTION_COUNT - 1 then
              if channel_idx = 0 then
                eq_left_r <= y_v;
                channel_idx <= 1;
                section_idx <= 0;
                section_in <= pan_right_r;
                state <= PREP_SECTION;
              else
                eq_right_r <= y_v;
                state <= LAUNCH_GAIN;
              end if;
            else
              section_idx <= section_idx + 1;
              state <= ADVANCE_SECTION;
            end if;

          when ADVANCE_SECTION =>
            section_in <= next_section_in;
            state <= PREP_SECTION;

          when LAUNCH_GAIN =>
            mul0_a <= to_mul_a(eq_left_r);
            mul0_b <= std_logic_vector(q15_to_q28(left_gain_i));
            mul1_a <= to_mul_a(eq_right_r);
            mul1_b <= std_logic_vector(q15_to_q28(right_gain_i));
            state <= WAIT_GAIN_0;

          when WAIT_GAIN_0 =>
            state <= WAIT_GAIN_1;

          when WAIT_GAIN_1 =>
            state <= WAIT_GAIN_2;

          when WAIT_GAIN_2 =>
            state <= FINISH_GAIN;

          when FINISH_GAIN =>
            left_out_r <= std_logic_vector(raddsp_sat_signed_vec(shift_right(signed(mul0_p), COEFF_FRAC_BITS), SAMPLE_WIDTH));
            right_out_r <= std_logic_vector(raddsp_sat_signed_vec(shift_right(signed(mul1_p), COEFF_FRAC_BITS), SAMPLE_WIDTH));
            valid_r <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
