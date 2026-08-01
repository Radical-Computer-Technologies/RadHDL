library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Time-division polyphonic audio synth for register-controlled board designs.
-- A host writes per-voice configuration through cfg_* while explicit Gowin
-- multipliers are reused for wavetable interpolation, waveform-volume, and
-- envelope scaling. Each waveform page stores a positive half period; the
-- opposite half is reconstructed by sign inversion.
-- Voice control bit 20 enables the per-voice one-pole filter; bits [17:2]
-- carry its unsigned Q1.15 coefficient. Bits 1 and 0 remain voice enable/gate.
entity raddsp_audio_poly_synth is
  generic (
    VOICE_COUNT     : positive := 16;
    SAMPLE_WIDTH    : positive := 24;
    WAVE_WIDTH      : positive := 16;
    PHASE_WIDTH     : positive := 24;
    TABLE_ADDR_WIDTH : positive := 8;
    COEFF_WIDTH     : positive := 18;
    COEFF_FRAC_BITS : natural  := 15;
    RESET_CONFIG_REGS : boolean := true
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    sample_ce_i   : in  std_logic;
    cfg_wr_en_i   : in  std_logic;
    cfg_addr_i    : in  std_logic_vector(7 downto 0);
    cfg_data_i    : in  std_logic_vector(31 downto 0);
    cfg_rd_en_i   : in  std_logic := '0';
    cfg_rd_addr_i : in  std_logic_vector(7 downto 0) := (others => '0');
    cfg_data_o    : out std_logic_vector(31 downto 0);
    cfg_rd_valid_o : out std_logic;
    cfg_error_o   : out std_logic;
    table_wr_en_i   : in  std_logic;
    table_wr_addr_i : in  std_logic_vector(TABLE_ADDR_WIDTH + 1 downto 0);
    table_wr_data_i : in  std_logic_vector(WAVE_WIDTH - 1 downto 0);
    sample_o      : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o       : out std_logic;
    table_init_done_o : out std_logic;
    busy_o        : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_poly_synth is
  type state_t is (
    INIT_TABLE,
    IDLE,
    HOST_CFG_CAPTURE,
    PREP_VOICE,
    LOAD_FREQ,
    LOAD_CTRL,
    LOAD_VOLS,
    LOAD_ADSR,
    UPDATE_PHASE,
    UPDATE_ENV_SELECT,
    UPDATE_ENV_APPLY,
    COMMIT_ENV,
    WAVE_PIPE,
    WAIT_ENV_0,
    WAIT_ENV_1,
    ACCUM_VOICE,
    WAIT_FILTER_0,
    WAIT_FILTER_1,
    APPLY_FILTER,
    ACCUM_FILTER,
    DONE
  );

  subtype sample_t is signed(SAMPLE_WIDTH - 1 downto 0);
  type phase_array_t is array (natural range <>) of unsigned(PHASE_WIDTH - 1 downto 0);
  type coeff_array_t is array (natural range <>) of unsigned(COEFF_WIDTH - 1 downto 0);
  type slv32_array_t is array (natural range <>) of std_logic_vector(31 downto 0);
  type adsr_state_array_t is array (natural range <>) of std_logic_vector(1 downto 0);
  type wave_sample_array_t is array (0 to 3) of signed(WAVE_WIDTH - 1 downto 0);
  type env_action_t is (ENV_HOLD, ENV_CLEAR, ENV_ATTACK, ENV_DECAY, ENV_RELEASE);

  constant C_ENV_MAX   : unsigned(COEFF_WIDTH - 1 downto 0) := to_unsigned((2 ** (COEFF_WIDTH - 1)) - 1, COEFF_WIDTH);
  constant C_ENV_SHIFT : natural := COEFF_FRAC_BITS - 7;
  constant C_TOTAL_TABLE_ADDR_WIDTH : positive := TABLE_ADDR_WIDTH + 2;
  constant C_TABLE_SIZE : positive := 2 ** C_TOTAL_TABLE_ADDR_WIDTH;
  constant C_INTERP_FRAC_BITS : natural := PHASE_WIDTH - TABLE_ADDR_WIDTH - 1;
  constant C_CONFIG_ADDR_WIDTH : positive := 6;
  constant C_FILTER_ENABLE_BIT : natural := 20;

  signal state       : state_t := INIT_TABLE;
  signal init_addr   : unsigned(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal table_init_done_r : std_logic := '0';
  signal table_wr_en : std_logic := '0';
  signal table_wr_addr : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal table_wr_data : std_logic_vector(15 downto 0) := (others => '0');
  signal table_rd_addr : std_logic_vector(C_TOTAL_TABLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal table_rd_data : std_logic_vector(15 downto 0);
  signal phases      : phase_array_t(0 to VOICE_COUNT - 1) := (others => (others => '0'));
  signal env_levels  : coeff_array_t(0 to VOICE_COUNT - 1) := (others => (others => '0'));
  signal adsr_states : adsr_state_array_t(0 to VOICE_COUNT - 1) := (others => "00");
  signal cfgmem_wr_en : std_logic := '0';
  signal cfgmem_wr_addr : std_logic_vector(C_CONFIG_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal cfgmem_wr_lo : std_logic_vector(15 downto 0) := (others => '0');
  signal cfgmem_wr_hi : std_logic_vector(15 downto 0) := (others => '0');
  signal cfgmem_rd_addr : std_logic_vector(C_CONFIG_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal cfgmem_rd_lo : std_logic_vector(15 downto 0);
  signal cfgmem_rd_hi : std_logic_vector(15 downto 0);
  signal cfgmem_rd_data : std_logic_vector(31 downto 0);
  signal cfgmem_rst : std_logic := '0';
  signal filtermem_wr_en : std_logic := '0';
  signal filtermem_wr_addr : std_logic_vector(3 downto 0) := (others => '0');
  signal filtermem_wr_lo : std_logic_vector(15 downto 0) := (others => '0');
  signal filtermem_wr_hi : std_logic_vector(15 downto 0) := (others => '0');
  signal filtermem_rd_addr : std_logic_vector(3 downto 0) := (others => '0');
  signal filtermem_rd_lo : std_logic_vector(15 downto 0);
  signal filtermem_rd_hi : std_logic_vector(15 downto 0);
  signal cfg_rd_pending_r : std_logic := '0';
  signal cfg_rd_addr_r : std_logic_vector(7 downto 0) := (others => '0');

  attribute syn_ramstyle : string;
  attribute syn_ramstyle of phases      : signal is "registers";
  attribute syn_ramstyle of env_levels  : signal is "registers";
  attribute syn_ramstyle of adsr_states : signal is "registers";

  signal voice_idx   : natural range 0 to VOICE_COUNT - 1 := 0;
  signal wave_idx    : natural range 0 to 3 := 0;
  signal wave_pipe_cycle : natural range 0 to 23 := 0;
  signal cur_freq    : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal cur_phase   : unsigned(PHASE_WIDTH - 1 downto 0) := (others => '0');
  signal cur_env     : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal cur_ctrl    : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_vols    : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_adsr    : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_adsr_state : std_logic_vector(1 downto 0) := "00";
  signal cur_filter_state : sample_t := (others => '0');
  signal env_action  : env_action_t := ENV_HOLD;
  signal env_step_r  : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal env_sustain_r : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal env_next_r  : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal adsr_state_next_r : std_logic_vector(1 downto 0) := "00";
  signal voice_mix   : signed(SAMPLE_WIDTH + 3 downto 0) := (others => '0');
  signal total_mix   : signed(SAMPLE_WIDTH + 7 downto 0) := (others => '0');
  signal sample_r    : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r     : std_logic := '0';
  signal cfg_data_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal cfg_rd_valid_r : std_logic := '0';
  signal cfg_error_r : std_logic := '0';
  signal sample_a_r   : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_b_r   : signed(WAVE_WIDTH - 1 downto 0) := (others => '0');
  signal wave_sample_a : wave_sample_array_t := (others => (others => '0'));
  signal interp_r     : signed(WAVE_WIDTH downto 0) := (others => '0');
  signal interp_frac_r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal sample_a_neg_r : std_logic := '0';
  signal sample_b_neg_r : std_logic := '0';
  signal interp_mult_a : std_logic_vector(26 downto 0) := (others => '0');
  signal interp_mult_b : std_logic_vector(17 downto 0) := (others => '0');
  signal interp_mult_p : std_logic_vector(44 downto 0);
  signal wave_mult_a   : std_logic_vector(26 downto 0) := (others => '0');
  signal wave_mult_b   : std_logic_vector(17 downto 0) := (others => '0');
  signal wave_mult_p   : std_logic_vector(44 downto 0);
  signal voice_out_r    : sample_t := (others => '0');

  function cfg_voice_index(addr : std_logic_vector(7 downto 0)) return natural is
  begin
    return to_integer(unsigned(addr(3 downto 0)));
  end function;

  function cfg_page(addr : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    return addr(7 downto 4);
  end function;

  function cfg_mem_addr(addr : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    return addr(C_CONFIG_ADDR_WIDTH - 1 downto 0);
  end function;

  function cfg_addr_valid(addr : std_logic_vector(7 downto 0)) return boolean is
  begin
    return addr(7 downto C_CONFIG_ADDR_WIDTH) = "00" and cfg_voice_index(addr) < VOICE_COUNT;
  end function;

  function coeff_from_byte(v : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  begin
    r(COEFF_FRAC_BITS downto C_ENV_SHIFT) := v;
    return r;
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

  function env_step(step_byte : std_logic_vector(7 downto 0)) return unsigned is
    variable r : unsigned(COEFF_WIDTH - 1 downto 0) := (others => '0');
  begin
    r(COEFF_FRAC_BITS downto C_ENV_SHIFT) := unsigned(step_byte);
    return r;
  end function;

  function wave_coeff(volumes : std_logic_vector(31 downto 0); index : natural) return std_logic_vector is
  begin
    case index is
      when 0 => return coeff_from_byte(volumes(7 downto 0));
      when 1 => return coeff_from_byte(volumes(15 downto 8));
      when 2 => return coeff_from_byte(volumes(23 downto 16));
      when others => return coeff_from_byte(volumes(31 downto 24));
    end case;
  end function;

  function filter_enabled(ctrl : std_logic_vector(31 downto 0)) return boolean is
  begin
    return ctrl(C_FILTER_ENABLE_BIT) = '1';
  end function;

  function filter_coeff(ctrl : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(COEFF_WIDTH - 1 downto 0) := (others => '0');
  begin
    r(COEFF_FRAC_BITS downto 0) := ctrl(COEFF_FRAC_BITS + 2 downto 2);
    return r;
  end function;

  function filter_hi_word(value : sample_t) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0);
  begin
    r := (others => value(SAMPLE_WIDTH - 1));
    r(7 downto 0) := std_logic_vector(value(SAMPLE_WIDTH - 1 downto 16));
    return r;
  end function;

  function filter_rd_sample(hi_word : std_logic_vector(15 downto 0); lo_word : std_logic_vector(15 downto 0)) return sample_t is
    variable r : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
  begin
    r := hi_word(7 downto 0) & lo_word;
    return signed(r);
  end function;
begin
  assert C_INTERP_FRAC_BITS <= COEFF_FRAC_BITS
    report "raddsp_audio_poly_synth interpolation fraction must fit multiplier coefficient scaling"
    severity failure;
  assert VOICE_COUNT <= 16
    report "raddsp_audio_poly_synth register config address map supports at most 16 voices"
    severity failure;

  sample_o <= sample_r;
  valid_o <= valid_r;
  cfg_data_o <= cfg_data_r;
  cfg_rd_valid_o <= cfg_rd_valid_r;
  cfg_error_o <= cfg_error_r;
  table_init_done_o <= table_init_done_r;
  busy_o <= '1' when state /= IDLE else '0';
  cfgmem_wr_en <= cfg_wr_en_i when cfg_addr_valid(cfg_addr_i) else '0';
  cfgmem_wr_addr <= cfg_mem_addr(cfg_addr_i);
  cfgmem_wr_lo <= cfg_data_i(15 downto 0);
  cfgmem_wr_hi <= cfg_data_i(31 downto 16);
  cfgmem_rd_data <= cfgmem_rd_hi & cfgmem_rd_lo;
  cfgmem_rst <= rst when RESET_CONFIG_REGS else '0';

  u_table : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_TOTAL_TABLE_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => table_wr_en,
      wr_addr => table_wr_addr,
      wr_data => table_wr_data,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => table_rd_addr,
      rd_data => table_rd_data
    );

  u_cfg_lo : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_CONFIG_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => cfgmem_rst,
      wr_en => cfgmem_wr_en,
      wr_addr => cfgmem_wr_addr,
      wr_data => cfgmem_wr_lo,
      rd_clk => clk,
      rd_rst => cfgmem_rst,
      rd_addr => cfgmem_rd_addr,
      rd_data => cfgmem_rd_lo
    );

  u_cfg_hi : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => C_CONFIG_ADDR_WIDTH
    )
    port map (
      wr_clk => clk,
      wr_rst => cfgmem_rst,
      wr_en => cfgmem_wr_en,
      wr_addr => cfgmem_wr_addr,
      wr_data => cfgmem_wr_hi,
      rd_clk => clk,
      rd_rst => cfgmem_rst,
      rd_addr => cfgmem_rd_addr,
      rd_data => cfgmem_rd_hi
    );

  u_filter_lo : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => 4
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => filtermem_wr_en,
      wr_addr => filtermem_wr_addr,
      wr_data => filtermem_wr_lo,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => filtermem_rd_addr,
      rd_data => filtermem_rd_lo
    );

  u_filter_hi : entity work.raddsp_gowin_dpb16
    generic map (
      ADDR_WIDTH => 4
    )
    port map (
      wr_clk => clk,
      wr_rst => rst,
      wr_en => filtermem_wr_en,
      wr_addr => filtermem_wr_addr,
      wr_data => filtermem_wr_hi,
      rd_clk => clk,
      rd_rst => rst,
      rd_addr => filtermem_rd_addr,
      rd_data => filtermem_rd_hi
    );

  u_interp_mult : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => interp_mult_a,
      b_i => interp_mult_b,
      p_o => interp_mult_p
    );

  u_wave_mult : entity work.raddsp_gowin_multalu27x18_mul
    port map (
      clk => clk,
      rst => rst,
      ce => '1',
      a_i => wave_mult_a,
      b_i => wave_mult_b,
      p_o => wave_mult_p
    );

  process(clk)
    variable phase_next_v  : unsigned(PHASE_WIDTH - 1 downto 0);
    variable env_v         : unsigned(COEFF_WIDTH - 1 downto 0);
    variable sustain_v     : unsigned(COEFF_WIDTH - 1 downto 0);
    variable step_v        : unsigned(COEFF_WIDTH - 1 downto 0);
    variable adsr_state_v  : std_logic_vector(1 downto 0);
    variable scaled_v      : signed(44 downto 0);
    variable env_scaled_v  : signed(44 downto 0);
    variable total_next_v  : signed(SAMPLE_WIDTH + 7 downto 0);
    variable voice_mix_next_v : signed(SAMPLE_WIDTH + 3 downto 0);
    variable wave_index_v  : unsigned(TABLE_ADDR_WIDTH - 1 downto 0);
    variable sample_b_v    : signed(WAVE_WIDTH - 1 downto 0);
    variable interp_delta_v : signed(WAVE_WIDTH downto 0);
    variable interp_step_v : signed(WAVE_WIDTH downto 0);
    variable env_sample_v  : sample_t;
    variable filter_next_v : sample_t;
    variable filter_delta_v : signed(SAMPLE_WIDTH downto 0);
  begin
    if rising_edge(clk) then
      valid_r <= '0';
      cfg_rd_valid_r <= '0';
      cfg_error_r <= '0';
      table_wr_en <= '0';
      filtermem_wr_en <= '0';

      if rst = '1' then
        phases <= (others => (others => '0'));
        env_levels <= (others => (others => '0'));
        adsr_states <= (others => "00");
        cfg_rd_pending_r <= '0';
        cfg_rd_addr_r <= (others => '0');
        state <= INIT_TABLE;
        init_addr <= (others => '0');
        table_init_done_r <= '0';
        voice_idx <= 0;
        wave_idx <= 0;
        wave_pipe_cycle <= 0;
        cur_freq <= (others => '0');
        cur_phase <= (others => '0');
        cur_env <= (others => '0');
        cur_ctrl <= (others => '0');
        cur_vols <= (others => '0');
        cur_adsr <= (others => '0');
        cur_adsr_state <= "00";
        cur_filter_state <= (others => '0');
        env_action <= ENV_HOLD;
        env_step_r <= (others => '0');
        env_sustain_r <= (others => '0');
        env_next_r <= (others => '0');
        adsr_state_next_r <= "00";
        voice_mix <= (others => '0');
        total_mix <= (others => '0');
        sample_r <= (others => '0');
        cfg_data_r <= (others => '0');
        cfg_rd_valid_r <= '0';
        cfg_error_r <= '0';
        sample_a_r <= (others => '0');
        sample_b_r <= (others => '0');
        wave_sample_a <= (others => (others => '0'));
        interp_r <= (others => '0');
        interp_frac_r <= (others => '0');
        sample_a_neg_r <= '0';
        sample_b_neg_r <= '0';
        interp_mult_a <= (others => '0');
        interp_mult_b <= (others => '0');
        wave_mult_a <= (others => '0');
        wave_mult_b <= (others => '0');
        voice_out_r <= (others => '0');
        filtermem_wr_addr <= (others => '0');
        filtermem_wr_lo <= (others => '0');
        filtermem_wr_hi <= (others => '0');
        filtermem_rd_addr <= (others => '0');
      else
        if table_wr_en_i = '1' and table_init_done_r = '1' then
          table_wr_en <= '1';
          table_wr_addr <= table_wr_addr_i;
          table_wr_data <= table_wr_data_i;
        end if;

        if cfg_rd_en_i = '1' then
          cfg_rd_addr_r <= cfg_rd_addr_i;
          cfg_rd_pending_r <= '1';
        end if;

        if cfg_rd_pending_r = '1' and state = IDLE then
          if cfg_addr_valid(cfg_rd_addr_r) then
            cfgmem_rd_addr <= cfg_mem_addr(cfg_rd_addr_r);
            state <= HOST_CFG_CAPTURE;
          else
            cfg_data_r <= (others => '0');
            cfg_rd_valid_r <= '1';
            cfg_error_r <= '1';
            cfg_rd_pending_r <= '0';
          end if;
        else
        case state is
          when INIT_TABLE =>
            table_wr_en <= '1';
            table_wr_addr <= std_logic_vector(init_addr);
            table_wr_data <= default_wave(init_addr);
            if init_addr = to_unsigned(C_TABLE_SIZE - 1, init_addr'length) then
              table_init_done_r <= '1';
              state <= IDLE;
            else
              init_addr <= init_addr + 1;
            end if;

          when IDLE =>
            if sample_ce_i = '1' and table_init_done_r = '1' then
              voice_idx <= 0;
              wave_idx <= 0;
              total_mix <= (others => '0');
              voice_mix <= (others => '0');
              cfgmem_rd_addr <= "00" & std_logic_vector(to_unsigned(0, 4));
              filtermem_rd_addr <= std_logic_vector(to_unsigned(0, 4));
              state <= PREP_VOICE;
            end if;

          when HOST_CFG_CAPTURE =>
            cfg_data_r <= cfgmem_rd_data;
            cfg_rd_valid_r <= '1';
            cfg_rd_pending_r <= '0';
            state <= IDLE;

          when PREP_VOICE =>
            cur_phase <= phases(voice_idx);
            cur_env <= env_levels(voice_idx);
            cur_adsr_state <= adsr_states(voice_idx);
            cur_filter_state <= filter_rd_sample(filtermem_rd_hi, filtermem_rd_lo);
            state <= LOAD_FREQ;

          when LOAD_FREQ =>
            cur_freq <= unsigned(cfgmem_rd_data(PHASE_WIDTH - 1 downto 0));
            cfgmem_rd_addr <= "01" & std_logic_vector(to_unsigned(voice_idx, 4));
            state <= LOAD_CTRL;

          when LOAD_CTRL =>
            cur_ctrl <= cfgmem_rd_data;
            cfgmem_rd_addr <= "10" & std_logic_vector(to_unsigned(voice_idx, 4));
            state <= LOAD_VOLS;

          when LOAD_VOLS =>
            cur_vols <= cfgmem_rd_data;
            cfgmem_rd_addr <= "11" & std_logic_vector(to_unsigned(voice_idx, 4));
            state <= LOAD_ADSR;

          when LOAD_ADSR =>
            cur_adsr <= cfgmem_rd_data;
            state <= UPDATE_PHASE;

          when UPDATE_PHASE =>
            phase_next_v := cur_phase + cur_freq;
            phases(voice_idx) <= phase_next_v;
            cur_phase <= phase_next_v;
            state <= UPDATE_ENV_SELECT;

          when UPDATE_ENV_SELECT =>
            env_step_r <= (others => '0');
            env_sustain_r <= env_step(cur_adsr(23 downto 16));
            env_action <= ENV_HOLD;
            adsr_state_next_r <= cur_adsr_state;
            if cur_ctrl(1) = '0' then
              env_action <= ENV_CLEAR;
              adsr_state_next_r <= "00";
            elsif cur_ctrl(0) = '1' then
              if cur_adsr_state = "10" then
                env_action <= ENV_DECAY;
                env_step_r <= env_step(cur_adsr(15 downto 8));
                adsr_state_next_r <= "10";
              else
                env_action <= ENV_ATTACK;
                env_step_r <= env_step(cur_adsr(7 downto 0));
                adsr_state_next_r <= "01";
              end if;
            else
              env_action <= ENV_RELEASE;
              env_step_r <= env_step(cur_adsr(31 downto 24));
              adsr_state_next_r <= "11";
            end if;
            state <= UPDATE_ENV_APPLY;

          when UPDATE_ENV_APPLY =>
            env_v := cur_env;
            step_v := env_step_r;
            sustain_v := env_sustain_r;
            adsr_state_v := adsr_state_next_r;
            case env_action is
              when ENV_CLEAR =>
                env_v := (others => '0');
                adsr_state_v := "00";
              when ENV_ATTACK =>
                if C_ENV_MAX - cur_env <= step_v then
                  env_v := C_ENV_MAX;
                  adsr_state_v := "10";
                else
                  env_v := cur_env + step_v;
                end if;
              when ENV_DECAY =>
                if cur_env <= sustain_v or cur_env - sustain_v <= step_v then
                  env_v := sustain_v;
                else
                  env_v := cur_env - step_v;
                end if;
                adsr_state_v := "10";
              when ENV_RELEASE =>
                if cur_env <= step_v then
                  env_v := (others => '0');
                  adsr_state_v := "00";
                else
                  env_v := cur_env - step_v;
                end if;
              when ENV_HOLD =>
                null;
            end case;
            env_next_r <= env_v;
            adsr_state_next_r <= adsr_state_v;
            state <= COMMIT_ENV;

          when COMMIT_ENV =>
            env_levels(voice_idx) <= env_next_r;
            adsr_states(voice_idx) <= adsr_state_next_r;
            cur_env <= env_next_r;
            cur_adsr_state <= adsr_state_next_r;
            wave_idx <= 0;
            wave_pipe_cycle <= 0;
            voice_mix <= (others => '0');
            state <= WAVE_PIPE;

          when WAVE_PIPE =>
            wave_index_v := half_index_for_phase(cur_phase);
            interp_frac_r <= interp_frac_for_phase(cur_phase);
            sample_a_neg_r <= cur_phase(PHASE_WIDTH - 1);
            sample_b_neg_r <= cur_phase(PHASE_WIDTH - 1);
            if wave_index_v = to_unsigned((2 ** TABLE_ADDR_WIDTH) - 1, TABLE_ADDR_WIDTH) then
              sample_b_neg_r <= not cur_phase(PHASE_WIDTH - 1);
            end if;

            case wave_pipe_cycle is
              when 0 =>
                table_rd_addr <= "00" & std_logic_vector(wave_index_v);
              when 2 =>
                sample_a_r <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                wave_sample_a(0) <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                table_rd_addr <= "00" & std_logic_vector(wave_index_v + 1);
              when 4 =>
                sample_b_v := signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_b_neg_r);
                sample_b_r <= sample_b_v;
                table_rd_addr <= "01" & std_logic_vector(wave_index_v);
              when 5 =>
                interp_delta_v := resize(sample_b_r, WAVE_WIDTH + 1) - resize(wave_sample_a(0), WAVE_WIDTH + 1);
                interp_mult_a <= std_logic_vector(resize(interp_delta_v, 27));
                interp_mult_b <= interp_frac_r;
              when 6 =>
                sample_a_r <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                wave_sample_a(1) <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                table_rd_addr <= "01" & std_logic_vector(wave_index_v + 1);
              when 8 =>
                interp_step_v := resize(shift_right(signed(interp_mult_p), COEFF_FRAC_BITS), WAVE_WIDTH + 1);
                interp_r <= resize(wave_sample_a(0), WAVE_WIDTH + 1) + interp_step_v;
                wave_mult_a <= std_logic_vector(resize(resize(wave_sample_a(0), WAVE_WIDTH + 1) + interp_step_v, 27));
                wave_mult_b <= wave_coeff(cur_vols, 0);
                sample_b_v := signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_b_neg_r);
                sample_b_r <= sample_b_v;
                table_rd_addr <= "10" & std_logic_vector(wave_index_v);
              when 9 =>
                interp_delta_v := resize(sample_b_r, WAVE_WIDTH + 1) - resize(wave_sample_a(1), WAVE_WIDTH + 1);
                interp_mult_a <= std_logic_vector(resize(interp_delta_v, 27));
                interp_mult_b <= interp_frac_r;
              when 10 =>
                scaled_v := signed(wave_mult_p);
                voice_mix <= voice_mix + resize(
                  shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
                  voice_mix'length
                );
                sample_a_r <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                wave_sample_a(2) <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                table_rd_addr <= "10" & std_logic_vector(wave_index_v + 1);
              when 12 =>
                interp_step_v := resize(shift_right(signed(interp_mult_p), COEFF_FRAC_BITS), WAVE_WIDTH + 1);
                interp_r <= resize(wave_sample_a(1), WAVE_WIDTH + 1) + interp_step_v;
                wave_mult_a <= std_logic_vector(resize(resize(wave_sample_a(1), WAVE_WIDTH + 1) + interp_step_v, 27));
                wave_mult_b <= wave_coeff(cur_vols, 1);
                sample_b_v := signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_b_neg_r);
                sample_b_r <= sample_b_v;
                table_rd_addr <= "11" & std_logic_vector(wave_index_v);
              when 13 =>
                interp_delta_v := resize(sample_b_r, WAVE_WIDTH + 1) - resize(wave_sample_a(2), WAVE_WIDTH + 1);
                interp_mult_a <= std_logic_vector(resize(interp_delta_v, 27));
                interp_mult_b <= interp_frac_r;
              when 14 =>
                scaled_v := signed(wave_mult_p);
                voice_mix <= voice_mix + resize(
                  shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
                  voice_mix'length
                );
                sample_a_r <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                wave_sample_a(3) <= signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_a_neg_r);
                table_rd_addr <= "11" & std_logic_vector(wave_index_v + 1);
              when 16 =>
                interp_step_v := resize(shift_right(signed(interp_mult_p), COEFF_FRAC_BITS), WAVE_WIDTH + 1);
                interp_r <= resize(wave_sample_a(2), WAVE_WIDTH + 1) + interp_step_v;
                wave_mult_a <= std_logic_vector(resize(resize(wave_sample_a(2), WAVE_WIDTH + 1) + interp_step_v, 27));
                wave_mult_b <= wave_coeff(cur_vols, 2);
                sample_b_v := signed_or_inverted(table_rd_data(WAVE_WIDTH - 1 downto 0), sample_b_neg_r);
                sample_b_r <= sample_b_v;
              when 17 =>
                interp_delta_v := resize(sample_b_r, WAVE_WIDTH + 1) - resize(wave_sample_a(3), WAVE_WIDTH + 1);
                interp_mult_a <= std_logic_vector(resize(interp_delta_v, 27));
                interp_mult_b <= interp_frac_r;
              when 18 =>
                scaled_v := signed(wave_mult_p);
                voice_mix <= voice_mix + resize(
                  shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
                  voice_mix'length
                );
              when 20 =>
                interp_step_v := resize(shift_right(signed(interp_mult_p), COEFF_FRAC_BITS), WAVE_WIDTH + 1);
                interp_r <= resize(wave_sample_a(3), WAVE_WIDTH + 1) + interp_step_v;
                wave_mult_a <= std_logic_vector(resize(resize(wave_sample_a(3), WAVE_WIDTH + 1) + interp_step_v, 27));
                wave_mult_b <= wave_coeff(cur_vols, 3);
              when 23 =>
                scaled_v := signed(wave_mult_p);
                voice_mix_next_v := voice_mix + resize(
                  shift_left(shift_right(scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH - WAVE_WIDTH),
                  voice_mix'length
                );
                voice_mix <= voice_mix_next_v;
                interp_mult_a <= std_logic_vector(resize(voice_mix_next_v, 27));
                interp_mult_b <= std_logic_vector(cur_env);
                state <= WAIT_ENV_0;
              when others =>
                null;
            end case;

            if wave_pipe_cycle < 23 then
              wave_pipe_cycle <= wave_pipe_cycle + 1;
            end if;

          when WAIT_ENV_0 =>
            state <= WAIT_ENV_1;

          when WAIT_ENV_1 =>
            state <= ACCUM_VOICE;

          when ACCUM_VOICE =>
            env_scaled_v := signed(interp_mult_p);
            env_sample_v := raddsp_sat_signed_vec(shift_right(env_scaled_v, COEFF_FRAC_BITS), SAMPLE_WIDTH);
            voice_out_r <= env_sample_v;
            if filter_enabled(cur_ctrl) then
              filter_delta_v := resize(env_sample_v, SAMPLE_WIDTH + 1) - resize(cur_filter_state, SAMPLE_WIDTH + 1);
              interp_mult_a <= std_logic_vector(resize(filter_delta_v, 27));
              interp_mult_b <= filter_coeff(cur_ctrl);
              state <= WAIT_FILTER_0;
            else
              filtermem_wr_en <= '1';
              filtermem_wr_addr <= std_logic_vector(to_unsigned(voice_idx, 4));
              filtermem_wr_lo <= std_logic_vector(env_sample_v(15 downto 0));
              filtermem_wr_hi <= filter_hi_word(env_sample_v);
              state <= ACCUM_FILTER;
            end if;

          when WAIT_FILTER_0 =>
            state <= WAIT_FILTER_1;

          when WAIT_FILTER_1 =>
            state <= APPLY_FILTER;

          when APPLY_FILTER =>
            env_scaled_v := signed(interp_mult_p);
            filter_next_v := raddsp_sat_signed_vec(
              resize(cur_filter_state, 45) + shift_right(env_scaled_v, COEFF_FRAC_BITS),
              SAMPLE_WIDTH
            );
            voice_out_r <= filter_next_v;
            filtermem_wr_en <= '1';
            filtermem_wr_addr <= std_logic_vector(to_unsigned(voice_idx, 4));
            filtermem_wr_lo <= std_logic_vector(filter_next_v(15 downto 0));
            filtermem_wr_hi <= filter_hi_word(filter_next_v);
            state <= ACCUM_FILTER;

          when ACCUM_FILTER =>
            total_next_v := total_mix + resize(voice_out_r, total_mix'length);
            total_mix <= total_next_v;
            if voice_idx = VOICE_COUNT - 1 then
              sample_r <= std_logic_vector(raddsp_sat_signed_vec(total_next_v, SAMPLE_WIDTH));
              valid_r <= '1';
              state <= DONE;
            else
              voice_idx <= voice_idx + 1;
              cfgmem_rd_addr <= "00" & std_logic_vector(to_unsigned(voice_idx + 1, 4));
              filtermem_rd_addr <= std_logic_vector(to_unsigned(voice_idx + 1, 4));
              state <= PREP_VOICE;
            end if;

          when DONE =>
            state <= IDLE;
        end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
