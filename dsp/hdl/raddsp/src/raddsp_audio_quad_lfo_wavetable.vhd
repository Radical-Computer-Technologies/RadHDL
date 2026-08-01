library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Four TDM LFOs sharing one 4-page, 512-point half-period wavetable. The
-- table uses two explicit Gowin DPB blocks, reconstructs the opposite half by
-- sign inversion, and linearly interpolates between adjacent points.
entity raddsp_audio_quad_lfo_wavetable is
  generic (
    SAMPLE_WIDTH     : positive := 24;
    WAVE_WIDTH       : positive := 16;
    PHASE_WIDTH      : positive := 24;
    TABLE_ADDR_WIDTH : positive := 9;
    COEFF_WIDTH      : positive := 18;
    COEFF_FRAC_BITS  : natural  := 15
  );
  port (
    clk             : in  std_logic;
    rst             : in  std_logic;
    sample_ce_i     : in  std_logic;
    phase_inc0_i    : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    phase_inc1_i    : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    phase_inc2_i    : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    phase_inc3_i    : in  std_logic_vector(PHASE_WIDTH - 1 downto 0);
    wave_select_i   : in  std_logic_vector(7 downto 0);
    depth0_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    depth1_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    depth2_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    depth3_i        : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    table_wr_en_i   : in  std_logic;
    table_wr_addr_i : in  std_logic_vector(TABLE_ADDR_WIDTH + 1 downto 0);
    table_wr_data_i : in  std_logic_vector(WAVE_WIDTH - 1 downto 0);
    lfo0_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    lfo1_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    lfo2_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    lfo3_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o         : out std_logic;
    init_done_o     : out std_logic;
    busy_o          : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_quad_lfo_wavetable is
  type state_t is (
    INIT,
    IDLE,
    PREP_LFO,
    READ_SAMPLE_A,
    WAIT_SAMPLE_A,
    READ_SAMPLE_B,
    WAIT_SAMPLE_B,
    LAUNCH_INTERP,
    ISSUE_INTERP,
    WAIT_INTERP_0,
    WAIT_INTERP_1,
    LAUNCH_DEPTH,
    WAIT_DEPTH_0,
    WAIT_DEPTH_1,
    STORE_LFO,
    DONE
  );

  constant C_TOTAL_TABLE_ADDR_WIDTH : positive := TABLE_ADDR_WIDTH + 2;
  constant C_TABLE_SIZE             : positive := 2 ** C_TOTAL_TABLE_ADDR_WIDTH;
  constant C_INTERP_FRAC_BITS       : natural := PHASE_WIDTH - TABLE_ADDR_WIDTH - 1;
  constant C_BANK_ADDR_WIDTH        : positive := 10;

  signal state       : state_t := INIT;
  signal init_addr   : unsigned(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal init_done_r : std_logic := '0';
  signal lfo_idx     : integer range 0 to 3 := 0;
  signal lfo_last_r  : std_logic := '0';
  signal phase0      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase1      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase2      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal phase3      : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal cur_phase_r : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal cur_inc_r   : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal cur_wave_r  : std_logic_vector(1 downto 0) := (others => '0');
  signal cur_depth_r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');

  signal wr_en0      : std_logic := '0';
  signal wr_en1      : std_logic := '0';
  signal wr_addr     : std_logic_vector(C_BANK_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal wr_data     : std_logic_vector(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal rd_addr     : std_logic_vector(C_BANK_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_bank_r   : std_logic := '0';
  signal rd_data0    : std_logic_vector(WAVE_WIDTH - 1 downto 0);
  signal rd_data1    : std_logic_vector(WAVE_WIDTH - 1 downto 0);
  signal rd_data     : std_logic_vector(WAVE_WIDTH - 1 downto 0);

  signal sample_a_r    : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_b_r    : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal interp_frac_r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal sample_a_neg_r : std_logic := '0';
  signal sample_b_neg_r : std_logic := '0';
  signal lfo0_r       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal lfo1_r       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal lfo2_r       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal lfo3_r       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r      : std_logic := '0';

  signal mult_a       : std_logic_vector(26 downto 0) := (others => '0');
  signal mult_b       : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal mult_p       : std_logic_vector(44 downto 0);

  function bank_addr(addr : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0))
    return std_logic_vector is
  begin
    return addr(C_BANK_ADDR_WIDTH - 1 downto 0);
  end function;

  function bank_sel(addr : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0))
    return std_logic is
  begin
    return addr(C_TOTAL_TABLE_ADDR_WIDTH - 1);
  end function;

  function phase_inc_for(
    idx : integer;
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

  function phase_for(idx : integer; p0 : unsigned; p1 : unsigned; p2 : unsigned; p3 : unsigned)
    return unsigned is
  begin
    case idx is
      when 0 => return p0;
      when 1 => return p1;
      when 2 => return p2;
      when others => return p3;
    end case;
  end function;

  function wave_for(idx : integer; packed : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    case idx is
      when 0 => return packed(1 downto 0);
      when 1 => return packed(3 downto 2);
      when 2 => return packed(5 downto 4);
      when others => return packed(7 downto 6);
    end case;
  end function;

  function depth_for(
    idx : integer;
    d0  : std_logic_vector(COEFF_WIDTH - 1 downto 0);
    d1  : std_logic_vector(COEFF_WIDTH - 1 downto 0);
    d2  : std_logic_vector(COEFF_WIDTH - 1 downto 0);
    d3  : std_logic_vector(COEFF_WIDTH - 1 downto 0)
  ) return std_logic_vector is
  begin
    case idx is
      when 0 => return d0;
      when 1 => return d1;
      when 2 => return d2;
      when others => return d3;
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
    variable ramp      : signed(WAVE_WIDTH - 1 downto 0);
  begin
    page := std_logic_vector(addr(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto TABLE_ADDR_WIDTH));
    sample_ix := addr(TABLE_ADDR_WIDTH - 1 downto 0);
    phase_top := (others => '0');
    phase_top(WAVE_WIDTH - 1 downto WAVE_WIDTH - TABLE_ADDR_WIDTH) := std_logic_vector(sample_ix);
    ramp := signed(phase_top);
    case page is
      when "00" =>
        if sample_ix(TABLE_ADDR_WIDTH - 1) = '1' then
          return not phase_top;
        end if;
        return phase_top;
      when "01" =>
        return std_logic_vector(to_signed((2 ** (WAVE_WIDTH - 1)) - 1, WAVE_WIDTH));
      when "10" =>
        if sample_ix(TABLE_ADDR_WIDTH - 1) = '1' then
          return not phase_top;
        end if;
        return phase_top;
      when others =>
        return std_logic_vector(shift_right(ramp, 1));
    end case;
  end function;
begin
  assert C_TOTAL_TABLE_ADDR_WIDTH = C_BANK_ADDR_WIDTH + 1
    report "raddsp_audio_quad_lfo_wavetable expects two 1024x16 Gowin DPB banks"
    severity failure;
  assert C_INTERP_FRAC_BITS <= COEFF_FRAC_BITS
    report "raddsp_audio_quad_lfo_wavetable interpolation fraction must fit multiplier coefficient scaling"
    severity failure;

  rd_data <= rd_data1 when rd_bank_r = '1' else rd_data0;
  lfo0_o <= lfo0_r;
  lfo1_o <= lfo1_r;
  lfo2_o <= lfo2_r;
  lfo3_o <= lfo3_r;
  valid_o <= valid_r;
  init_done_o <= init_done_r;
  busy_o <= '1' when state /= IDLE else '0';

  u_table0 : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_BANK_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => wr_en0,
      wr_addr => wr_addr,
      wr_data => wr_data,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => rd_addr,
      rd_data => rd_data0
    );

  u_table1 : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_BANK_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => wr_en1,
      wr_addr => wr_addr,
      wr_data => wr_data,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => rd_addr,
      rd_data => rd_data1
    );

  u_depth_mult : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => mult_a,
      b_i => mult_b,
      p_o => mult_p
    );

  process(clk)
    variable next_phase_v   : unsigned(PHASE_WIDTH - 1 downto 0);
    variable full_addr_v    : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0);
    variable index_v        : unsigned(TABLE_ADDR_WIDTH - 1 downto 0);
    variable wave_v         : std_logic_vector(1 downto 0);
    variable interp_delta_v : signed(WAVE_WIDTH downto 0);
    variable interp_step_v  : signed(WAVE_WIDTH downto 0);
    variable scaled_v       : signed(44 downto 0);
    variable sample_v       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      valid_r <= '0';
      wr_en0 <= '0';
      wr_en1 <= '0';

      if rst = '1' then
        state <= INIT;
        init_addr <= (others => '0');
        init_done_r <= '0';
        lfo_idx <= 0;
        lfo_last_r <= '0';
        phase0 <= (others => '0');
        phase1 <= (others => '0');
        phase2 <= (others => '0');
        phase3 <= (others => '0');
        cur_phase_r <= (others => '0');
        cur_inc_r <= (others => '0');
        cur_wave_r <= (others => '0');
        cur_depth_r <= (others => '0');
        sample_a_r <= (others => '0');
        sample_b_r <= (others => '0');
        interp_frac_r <= (others => '0');
        sample_a_neg_r <= '0';
        sample_b_neg_r <= '0';
        lfo0_r <= (others => '0');
        lfo1_r <= (others => '0');
        lfo2_r <= (others => '0');
        lfo3_r <= (others => '0');
      else
        if table_wr_en_i = '1' and init_done_r = '1' then
          wr_addr <= bank_addr(table_wr_addr_i);
          wr_data <= table_wr_data_i;
          if bank_sel(table_wr_addr_i) = '1' then
            wr_en1 <= '1';
          else
            wr_en0 <= '1';
          end if;
        end if;

        case state is
          when INIT =>
            wr_addr <= bank_addr(std_logic_vector(init_addr));
            wr_data <= default_wave(init_addr);
            if init_addr(init_addr'high) = '1' then
              wr_en1 <= '1';
            else
              wr_en0 <= '1';
            end if;
            if init_addr = to_unsigned(C_TABLE_SIZE - 1, init_addr'length) then
              init_done_r <= '1';
              state <= IDLE;
            else
              init_addr <= init_addr + 1;
            end if;

          when IDLE =>
            if sample_ce_i = '1' and init_done_r = '1' then
              lfo_idx <= 0;
              state <= PREP_LFO;
            end if;

          when PREP_LFO =>
            cur_phase_r <= phase_for(lfo_idx, phase0, phase1, phase2, phase3);
            cur_inc_r <= phase_inc_for(lfo_idx, phase_inc0_i, phase_inc1_i, phase_inc2_i, phase_inc3_i);
            cur_wave_r <= wave_for(lfo_idx, wave_select_i);
            cur_depth_r <= depth_for(lfo_idx, depth0_i, depth1_i, depth2_i, depth3_i);
            if lfo_idx = 3 then
              lfo_last_r <= '1';
            else
              lfo_last_r <= '0';
            end if;
            state <= READ_SAMPLE_A;

          when READ_SAMPLE_A =>
            next_phase_v := cur_phase_r + cur_inc_r;
            case lfo_idx is
              when 0 => phase0 <= next_phase_v;
              when 1 => phase1 <= next_phase_v;
              when 2 => phase2 <= next_phase_v;
              when others => phase3 <= next_phase_v;
            end case;
            index_v := half_index_for_phase(next_phase_v);
            wave_v := cur_wave_r;
            full_addr_v := wave_v & std_logic_vector(index_v);
            rd_addr <= bank_addr(full_addr_v);
            rd_bank_r <= bank_sel(full_addr_v);
            sample_a_neg_r <= next_phase_v(PHASE_WIDTH - 1);
            sample_b_neg_r <= next_phase_v(PHASE_WIDTH - 1);
            if index_v = to_unsigned((2 ** TABLE_ADDR_WIDTH) - 1, TABLE_ADDR_WIDTH) then
              sample_b_neg_r <= not next_phase_v(PHASE_WIDTH - 1);
            end if;
            interp_frac_r <= interp_frac_for_phase(next_phase_v);
            state <= WAIT_SAMPLE_A;

          when WAIT_SAMPLE_A =>
            state <= READ_SAMPLE_B;

          when READ_SAMPLE_B =>
            sample_a_r <= signed_or_inverted(rd_data, sample_a_neg_r);
            rd_addr(TABLE_ADDR_WIDTH - 1 downto 0) <=
              std_logic_vector(unsigned(rd_addr(TABLE_ADDR_WIDTH - 1 downto 0)) + 1);
            state <= WAIT_SAMPLE_B;

          when WAIT_SAMPLE_B =>
            state <= LAUNCH_INTERP;

          when LAUNCH_INTERP =>
            sample_b_r <= signed_or_inverted(rd_data, sample_b_neg_r);
            state <= ISSUE_INTERP;

          when ISSUE_INTERP =>
            interp_delta_v := resize(sample_b_r, WAVE_WIDTH + 1) - resize(sample_a_r, WAVE_WIDTH + 1);
            mult_a <= std_logic_vector(resize(interp_delta_v, 27));
            mult_b <= interp_frac_r;
            state <= WAIT_INTERP_0;

          when WAIT_INTERP_0 =>
            state <= WAIT_INTERP_1;

          when WAIT_INTERP_1 =>
            state <= LAUNCH_DEPTH;

          when LAUNCH_DEPTH =>
            interp_step_v := resize(shift_right(signed(mult_p), COEFF_FRAC_BITS), WAVE_WIDTH + 1);
            mult_a <= std_logic_vector(resize(resize(sample_a_r, WAVE_WIDTH + 1) + interp_step_v, 27));
            mult_b <= cur_depth_r;
            state <= WAIT_DEPTH_0;

          when WAIT_DEPTH_0 =>
            state <= WAIT_DEPTH_1;

          when WAIT_DEPTH_1 =>
            state <= STORE_LFO;

          when STORE_LFO =>
            scaled_v := signed(mult_p);
            sample_v := std_logic_vector(
              raddsp_sat_signed_vec(
                shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
                SAMPLE_WIDTH
              )
            );
            case lfo_idx is
              when 0 => lfo0_r <= sample_v;
              when 1 => lfo1_r <= sample_v;
              when 2 => lfo2_r <= sample_v;
              when others => lfo3_r <= sample_v;
            end case;
            if lfo_last_r = '1' then
              state <= DONE;
            else
              lfo_idx <= lfo_idx + 1;
              state <= PREP_LFO;
            end if;

          when DONE =>
            valid_r <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
