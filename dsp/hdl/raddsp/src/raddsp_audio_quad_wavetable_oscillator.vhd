library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Four phase-accumulator oscillators sharing one loadable 16-bit wavetable and
-- one explicit Gowin multiplier for interpolation and per-oscillator gain. Each
-- waveform page stores a positive half period; the second half is reconstructed
-- by sign inversion and adjacent samples are linearly interpolated.
entity raddsp_audio_quad_wavetable_oscillator is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    WAVE_WIDTH      : positive := 16;
    PHASE_WIDTH     : positive := 24;
    TABLE_ADDR_WIDTH : positive := 8;
    COEFF_WIDTH     : positive := 18;
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;
    sample_ce_i    : in  std_logic;
    phase_inc0_i   : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    phase_inc1_i   : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    phase_inc2_i   : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    phase_inc3_i   : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    wave_select_i  : in  std_logic_vector(7 downto 0);
    gain0_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    gain1_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    gain2_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    gain3_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    table_wr_en_i  : in  std_logic;
    table_wr_addr_i : in std_logic_vector(TABLE_ADDR_WIDTH + 1 downto 0);
    table_wr_data_i : in std_logic_vector(WAVE_WIDTH - 1 downto 0);
    sample0_o      : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    sample1_o      : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    sample2_o      : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    sample3_o      : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o        : out std_logic;
    init_done_o    : out std_logic;
    busy_o         : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_quad_wavetable_oscillator is
  type state_t is (
    INIT,
    IDLE,
    READ_SAMPLE_A,
    WAIT_SAMPLE_A,
    READ_SAMPLE_B,
    WAIT_SAMPLE_B,
    LAUNCH_INTERP,
    ISSUE_INTERP,
    WAIT_INTERP_0,
    WAIT_INTERP_1,
    LAUNCH_GAIN,
    WAIT_GAIN_0,
    WAIT_GAIN_1,
    STORE_SAMPLE,
    DONE
  );

  constant C_TOTAL_TABLE_ADDR_WIDTH : positive := TABLE_ADDR_WIDTH + 2;
  constant C_TABLE_SIZE : positive := 2 ** C_TOTAL_TABLE_ADDR_WIDTH;
  constant C_INTERP_FRAC_BITS : natural := PHASE_WIDTH - TABLE_ADDR_WIDTH - 1;
  type integer_lut_t is array (natural range <>) of integer;
  constant C_SINE_HALF_Q15 : integer_lut_t(0 to 255) := (
    0, 402, 804, 1206, 1608, 2009, 2410, 2811,
    3212, 3612, 4011, 4410, 4808, 5205, 5602, 5998,
    6393, 6786, 7179, 7571, 7962, 8351, 8739, 9126,
    9512, 9896, 10278, 10659, 11039, 11417, 11793, 12167,
    12539, 12910, 13279, 13645, 14010, 14372, 14732, 15090,
    15446, 15800, 16151, 16499, 16846, 17189, 17530, 17869,
    18204, 18537, 18868, 19195, 19519, 19841, 20159, 20475,
    20787, 21096, 21403, 21705, 22005, 22301, 22594, 22884,
    23170, 23452, 23731, 24007, 24279, 24547, 24811, 25072,
    25329, 25582, 25832, 26077, 26319, 26556, 26790, 27019,
    27245, 27466, 27683, 27896, 28105, 28310, 28510, 28706,
    28898, 29085, 29268, 29447, 29621, 29791, 29956, 30117,
    30273, 30424, 30571, 30714, 30852, 30985, 31113, 31237,
    31356, 31470, 31580, 31685, 31785, 31880, 31971, 32057,
    32137, 32213, 32285, 32351, 32412, 32469, 32521, 32567,
    32609, 32646, 32678, 32705, 32728, 32745, 32757, 32765,
    32767, 32765, 32757, 32745, 32728, 32705, 32678, 32646,
    32609, 32567, 32521, 32469, 32412, 32351, 32285, 32213,
    32137, 32057, 31971, 31880, 31785, 31685, 31580, 31470,
    31356, 31237, 31113, 30985, 30852, 30714, 30571, 30424,
    30273, 30117, 29956, 29791, 29621, 29447, 29268, 29085,
    28898, 28706, 28510, 28310, 28105, 27896, 27683, 27466,
    27245, 27019, 26790, 26556, 26319, 26077, 25832, 25582,
    25329, 25072, 24811, 24547, 24279, 24007, 23731, 23452,
    23170, 22884, 22594, 22301, 22005, 21705, 21403, 21096,
    20787, 20475, 20159, 19841, 19519, 19195, 18868, 18537,
    18204, 17869, 17530, 17189, 16846, 16499, 16151, 15800,
    15446, 15090, 14732, 14372, 14010, 13645, 13279, 12910,
    12539, 12167, 11793, 11417, 11039, 10659, 10278, 9896,
    9512, 9126, 8739, 8351, 7962, 7571, 7179, 6786,
    6393, 5998, 5602, 5205, 4808, 4410, 4011, 3612,
    3212, 2811, 2410, 2009, 1608, 1206, 804, 402
  );

  signal state       : state_t := INIT;
  signal init_addr   : unsigned(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal init_done_r : std_logic := '0';
  signal osc_idx     : natural range 0 to 3 := 0;
  signal phase0      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase1      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase2      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase3      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal rd_addr     : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_data     : std_logic_vector(15 downto 0);
  signal wr_en       : std_logic := '0';
  signal wr_addr     : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal wr_data     : std_logic_vector(15 downto 0) := (others => '0');
  signal sample0_r   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample1_r   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample2_r   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample3_r   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r     : std_logic := '0';
  signal sample_a_r   : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_b_r   : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal interp_r     : signed(WAVE_WIDTH downto 0) := (others => '0');
  signal interp_frac_r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal sample_a_neg_r : std_logic := '0';
  signal sample_b_neg_r : std_logic := '0';
  signal mult_a      : std_logic_vector(26 downto 0) := (others => '0');
  signal mult_b      : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal mult_p      : std_logic_vector(44 downto 0);

  function phase_inc_for(
    idx : natural;
    f0  : std_logic_vector(PHASE_WIDTH - 1 downto 0);
    f1  : std_logic_vector(PHASE_WIDTH - 1 downto 0);
    f2  : std_logic_vector(PHASE_WIDTH - 1 downto 0);
    f3  : std_logic_vector(PHASE_WIDTH - 1 downto 0)
  ) return unsigned is
  begin
    case idx is
      when 0 => return unsigned(f0);
      when 1 => return unsigned(f1);
      when 2 => return unsigned(f2);
      when others => return unsigned(f3);
    end case;
  end function;

  function phase_for(idx : natural; p0 : unsigned; p1 : unsigned; p2 : unsigned; p3 : unsigned) return unsigned is
  begin
    case idx is
      when 0 => return p0;
      when 1 => return p1;
      when 2 => return p2;
      when others => return p3;
    end case;
  end function;

  function wave_for(idx : natural; packed : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    case idx is
      when 0 => return packed(1 downto 0);
      when 1 => return packed(3 downto 2);
      when 2 => return packed(5 downto 4);
      when others => return packed(7 downto 6);
    end case;
  end function;

  function gain_for(
    idx : natural;
    g0  : std_logic_vector(COEFF_WIDTH - 1 downto 0);
    g1  : std_logic_vector(COEFF_WIDTH - 1 downto 0);
    g2  : std_logic_vector(COEFF_WIDTH - 1 downto 0);
    g3  : std_logic_vector(COEFF_WIDTH - 1 downto 0)
  ) return std_logic_vector is
  begin
    case idx is
      when 0 => return g0;
      when 1 => return g1;
      when 2 => return g2;
      when others => return g3;
    end case;
  end function;

  function signed_or_inverted(v : std_logic_vector; invert : std_logic) return signed is
    variable s : signed(v'length - 1 downto 0);
  begin
    s := signed(v);
    if invert = '1' then
      return -s;
    end if;
    return s;
  end function;

  function half_index_for_phase(p : unsigned(PHASE_WIDTH - 1 downto 0)) return unsigned is
  begin
    return p(PHASE_WIDTH - 2 downto PHASE_WIDTH - TABLE_ADDR_WIDTH - 1);
  end function;

  function interp_frac_for_phase(p : unsigned(PHASE_WIDTH - 1 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  begin
    r(C_INTERP_FRAC_BITS - 1 downto 0) := std_logic_vector(p(C_INTERP_FRAC_BITS - 1 downto 0));
    return r;
  end function;

  function default_wave(addr : unsigned(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0)) return std_logic_vector is
    variable page      : std_logic_vector(1 downto 0);
    variable sample_ix : unsigned(TABLE_ADDR_WIDTH - 1 downto 0);
    variable phase_top : std_logic_vector(WAVE_WIDTH - 1 downto 0);
    variable ramp_pos  : unsigned(WAVE_WIDTH - 1 downto 0);
    variable ramp      : signed(WAVE_WIDTH - 1 downto 0);
  begin
    page := std_logic_vector(addr(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto TABLE_ADDR_WIDTH));
    sample_ix := addr(TABLE_ADDR_WIDTH - 1 downto 0);
    phase_top := (others => '0');
    phase_top(WAVE_WIDTH - 1 downto WAVE_WIDTH - TABLE_ADDR_WIDTH) := std_logic_vector(sample_ix);
    ramp_pos := (others => '0');
    ramp_pos(WAVE_WIDTH - 2 downto WAVE_WIDTH - TABLE_ADDR_WIDTH - 1) := sample_ix;
    ramp := signed(phase_top);
    case page is
      when "00" =>
        return std_logic_vector(to_signed(C_SINE_HALF_Q15(to_integer(sample_ix)), WAVE_WIDTH));
      when "01" =>
        return std_logic_vector(to_signed((2 ** (WAVE_WIDTH - 1)) - 1, WAVE_WIDTH));
      when "10" =>
        if sample_ix(TABLE_ADDR_WIDTH - 1) = '1' then
          return not phase_top;
        end if;
        return phase_top;
      when others =>
        return std_logic_vector(ramp_pos);
    end case;
  end function;
begin
  assert C_INTERP_FRAC_BITS <= COEFF_FRAC_BITS
    report "raddsp_audio_quad_wavetable_oscillator interpolation fraction must fit multiplier coefficient scaling"
    severity failure;

  sample0_o <= sample0_r;
  sample1_o <= sample1_r;
  sample2_o <= sample2_r;
  sample3_o <= sample3_r;
  valid_o <= valid_r;
  init_done_o <= init_done_r;
  busy_o <= '1' when state /= IDLE else '0';

  u_table : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_TOTAL_TABLE_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => wr_en,
      wr_addr => wr_addr,
      wr_data => wr_data,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => rd_addr,
      rd_data => rd_data
    );

  u_gain_mult : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => mult_a,
      b_i => mult_b,
      p_o => mult_p
    );

  process(clk)
    variable next_phase_v : unsigned(PHASE_WIDTH - 1 downto 0);
    variable index_v      : unsigned(TABLE_ADDR_WIDTH - 1 downto 0);
    variable next_index_v : unsigned(TABLE_ADDR_WIDTH - 1 downto 0);
    variable wave_v       : std_logic_vector(1 downto 0);
    variable scaled_v     : signed(44 downto 0);
    variable interp_delta_v : signed(WAVE_WIDTH downto 0);
    variable interp_step_v  : signed(WAVE_WIDTH downto 0);
    variable sample_v     : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      valid_r <= '0';
      wr_en <= '0';

      if rst = '1' then
        state <= INIT;
        init_addr <= (others => '0');
        init_done_r <= '0';
        osc_idx <= 0;
        phase0 <= (others => '0');
        phase1 <= (others => '0');
        phase2 <= (others => '0');
        phase3 <= (others => '0');
        sample0_r <= (others => '0');
        sample1_r <= (others => '0');
        sample2_r <= (others => '0');
        sample3_r <= (others => '0');
        sample_a_r <= (others => '0');
        sample_b_r <= (others => '0');
        interp_r <= (others => '0');
        interp_frac_r <= (others => '0');
        sample_a_neg_r <= '0';
        sample_b_neg_r <= '0';
      else
        if table_wr_en_i = '1' and init_done_r = '1' then
          wr_en <= '1';
          wr_addr <= table_wr_addr_i;
          wr_data <= table_wr_data_i;
        end if;

        case state is
          when INIT =>
            wr_en <= '1';
            wr_addr <= std_logic_vector(init_addr);
            wr_data <= default_wave(init_addr);
            if init_addr = to_unsigned(C_TABLE_SIZE - 1, init_addr'length) then
              init_done_r <= '1';
              state <= IDLE;
            else
              init_addr <= init_addr + 1;
            end if;

          when IDLE =>
            if sample_ce_i = '1' and init_done_r = '1' then
              osc_idx <= 0;
              state <= READ_SAMPLE_A;
            end if;

          when READ_SAMPLE_A =>
            next_phase_v := phase_for(osc_idx, phase0, phase1, phase2, phase3) +
                            phase_inc_for(osc_idx, phase_inc0_i, phase_inc1_i, phase_inc2_i, phase_inc3_i);
            case osc_idx is
              when 0 => phase0 <= next_phase_v;
              when 1 => phase1 <= next_phase_v;
              when 2 => phase2 <= next_phase_v;
              when others => phase3 <= next_phase_v;
            end case;
            index_v := half_index_for_phase(next_phase_v);
            wave_v := wave_for(osc_idx, wave_select_i);
            rd_addr <= wave_v & std_logic_vector(index_v);
            sample_a_neg_r <= next_phase_v(PHASE_WIDTH - 1);
            sample_b_neg_r <= next_phase_v(PHASE_WIDTH - 1);
            next_index_v := index_v + 1;
            if index_v = to_unsigned((2 ** TABLE_ADDR_WIDTH) - 1, TABLE_ADDR_WIDTH) then
              sample_b_neg_r <= not next_phase_v(PHASE_WIDTH - 1);
            end if;
            interp_frac_r <= interp_frac_for_phase(next_phase_v);
            state <= WAIT_SAMPLE_A;

          when WAIT_SAMPLE_A =>
            state <= READ_SAMPLE_B;

          when READ_SAMPLE_B =>
            sample_a_r <= signed_or_inverted(rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
            rd_addr(TABLE_ADDR_WIDTH - 1 downto 0) <= std_logic_vector(unsigned(rd_addr(TABLE_ADDR_WIDTH - 1 downto 0)) + 1);
            state <= WAIT_SAMPLE_B;

          when WAIT_SAMPLE_B =>
            state <= LAUNCH_INTERP;

          when LAUNCH_INTERP =>
            sample_b_r <= signed_or_inverted(rd_data(WAVE_WIDTH - 1 downto 0), sample_b_neg_r);
            state <= ISSUE_INTERP;

          when ISSUE_INTERP =>
            interp_delta_v := resize(sample_b_r, WAVE_WIDTH + 1) - resize(sample_a_r, WAVE_WIDTH + 1);
            mult_a <= std_logic_vector(resize(interp_delta_v, 27));
            mult_b <= interp_frac_r;
            state <= WAIT_INTERP_0;

          when WAIT_INTERP_0 =>
            state <= WAIT_INTERP_1;

          when WAIT_INTERP_1 =>
            state <= LAUNCH_GAIN;

          when LAUNCH_GAIN =>
            interp_step_v := resize(shift_right(signed(mult_p), COEFF_FRAC_BITS), WAVE_WIDTH + 1);
            interp_r <= resize(sample_a_r, WAVE_WIDTH + 1) + interp_step_v;
            mult_a <= std_logic_vector(resize(resize(sample_a_r, WAVE_WIDTH + 1) + interp_step_v, 27));
            mult_b <= gain_for(osc_idx, gain0_i, gain1_i, gain2_i, gain3_i);
            state <= WAIT_GAIN_0;

          when WAIT_GAIN_0 =>
            state <= WAIT_GAIN_1;

          when WAIT_GAIN_1 =>
            state <= STORE_SAMPLE;

          when STORE_SAMPLE =>
            scaled_v := signed(mult_p);
            sample_v := std_logic_vector(
              raddsp_sat_signed_vec(
                shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
                SAMPLE_WIDTH
              )
            );
            case osc_idx is
              when 0 => sample0_r <= sample_v;
              when 1 => sample1_r <= sample_v;
              when 2 => sample2_r <= sample_v;
              when others => sample3_r <= sample_v;
            end case;
            if osc_idx = 3 then
              state <= DONE;
            else
              osc_idx <= osc_idx + 1;
              state <= READ_SAMPLE_A;
            end if;

          when DONE =>
            valid_r <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
