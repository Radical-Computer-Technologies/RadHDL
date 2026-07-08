library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- Multi-channel AXI-stream FIR filter.
-- Applies fixed-point tap coefficients to streaming samples with frame-aware handshaking and vendor-portable arithmetic.
entity raddsp_axis_fir is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets the bit width for TAP WIDTH values carried by this module.
    TAP_WIDTH       : positive := 18;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    TAP_COUNT       : positive := 16;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    COEFF_FRAC_BITS : natural  := 15;
    -- Configures IMPLEMENTATION for this instance.
    IMPLEMENTATION  : string  := "parallel";
    -- Sets the number of parallel sample lanes processed per handshake beat.
    DSP_LANES       : positive := 1
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst           : in  std_logic;
    -- Input clear i signal for this module.
    clear_i       : in  std_logic;
    -- Input taps i signal for this module.
    taps_i        : in  std_logic_vector(TAP_COUNT * TAP_WIDTH - 1 downto 0);
    -- Input AXI-stream valid qualifier for the current sample beat.
    s_axis_tvalid : in  std_logic;
    -- Input AXI-stream ready response indicating this block can accept a beat.
    s_axis_tready : out std_logic;
    -- Input AXI-stream payload containing packed sample or feature lanes.
    s_axis_tdata  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_fir is
  type sample_array_t is array (natural range <>) of signed(DATA_WIDTH - 1 downto 0);
  constant C_ACC_WIDTH : positive := 48;

  function imin(a : positive; b : positive) return positive is
  begin
    if a < b then
      return a;
    end if;
    return b;
  end function;

  function tap_at(coeffs : std_logic_vector; index : natural) return signed is
    variable value : signed(TAP_WIDTH - 1 downto 0);
    variable lo    : natural;
  begin
    lo := index * TAP_WIDTH;
    value := signed(coeffs(lo + TAP_WIDTH - 1 downto lo));
    return value;
  end function;
begin
  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
  begin
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
  begin
  end generate;

  gen_parallel : if IMPLEMENTATION /= "sequential_mac" generate
    signal samples_r   : sample_array_t(0 to TAP_COUNT - 1) := (others => (others => '0'));
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable acc_v     : integer;
      variable product_v : signed(DATA_WIDTH + TAP_WIDTH - 1 downto 0);
      variable sample_v  : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          samples_r <= (others => (others => '0'));
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        else
          if clear_i = '1' then
            samples_r <= (others => (others => '0'));
          end if;

          if ready_i = '1' then
            out_valid_r <= s_axis_tvalid;
            out_last_r <= s_axis_tlast;
            if s_axis_tvalid = '1' then
              sample_v := signed(s_axis_tdata);
              acc_v := 0;
              product_v := sample_v * tap_at(taps_i, 0);
              acc_v := acc_v + to_integer(shift_right(product_v, COEFF_FRAC_BITS));
              for i in 1 to TAP_COUNT - 1 loop
                product_v := samples_r(i - 1) * tap_at(taps_i, i);
                acc_v := acc_v + to_integer(shift_right(product_v, COEFF_FRAC_BITS));
              end loop;

              for i in TAP_COUNT - 1 downto 1 loop
                samples_r(i) <= samples_r(i - 1);
              end loop;
              samples_r(0) <= sample_v;
              out_data_r <= std_logic_vector(raddsp_sat_signed(acc_v, DATA_WIDTH));
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_sequential_mac_xilinx : if IMPLEMENTATION = "sequential_mac" and (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    type state_t is (ST_IDLE, ST_RUN, ST_OUTPUT);
    constant C_DSP_LANES : positive := imin(DSP_LANES, TAP_COUNT);
    type lane_sample_array_t is array (natural range <>) of signed(DATA_WIDTH - 1 downto 0);
    type lane_tap_array_t is array (natural range <>) of signed(TAP_WIDTH - 1 downto 0);
    type lane_product_array_t is array (natural range <>) of signed(47 downto 0);

    signal samples_r    : sample_array_t(0 to TAP_COUNT - 1) := (others => (others => '0'));
    signal state_r      : state_t := ST_IDLE;
    signal issue_idx_r  : natural range 0 to TAP_COUNT := 0;
    signal x_work_r     : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal last_work_r  : std_logic := '0';
    signal acc_r        : signed(C_ACC_WIDTH - 1 downto 0) := (others => '0');
    signal out_valid_r  : std_logic := '0';
    signal out_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r   : std_logic := '0';
    signal ready_i      : std_logic;
    signal mul_valid    : std_logic_vector(0 to C_DSP_LANES - 1) := (others => '0');
    signal mul_last     : std_logic_vector(0 to C_DSP_LANES - 1) := (others => '0');
    signal mul_a        : lane_sample_array_t(0 to C_DSP_LANES - 1) := (others => (others => '0'));
    signal mul_b        : lane_tap_array_t(0 to C_DSP_LANES - 1) := (others => (others => '0'));
    signal mul_p        : lane_product_array_t(0 to C_DSP_LANES - 1);
    signal mul_p_valid  : std_logic_vector(0 to C_DSP_LANES - 1);
    signal unused_sub   : std_logic_vector(0 to C_DSP_LANES - 1);
    signal mul_p_last   : std_logic_vector(0 to C_DSP_LANES - 1);
  begin
    assert DATA_WIDTH <= 25
      report "DSP48 FIR direct multiplier supports DATA_WIDTH <= 25"
      severity failure;
    assert TAP_WIDTH <= 18
      report "DSP48 FIR direct multiplier supports TAP_WIDTH <= 18"
      severity failure;

    ready_i <= '1' when state_r = ST_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    gen_mul_lanes : for lane in 0 to C_DSP_LANES - 1 generate
    begin
      dsp_mul_i: entity raddsp.raddsp_xilinx_dsp48_mul
        generic map (
          DEVICE_FAMILY => DEVICE_FAMILY,
          A_WIDTH => DATA_WIDTH,
          B_WIDTH => TAP_WIDTH
        )
        port map (
          clk => clk,
          rst => rst,
          valid_i => mul_valid(lane),
          subtract_i => '0',
          last_i => mul_last(lane),
          a_i => mul_a(lane),
          b_i => mul_b(lane),
          valid_o => mul_p_valid(lane),
          subtract_o => unused_sub(lane),
          last_o => mul_p_last(lane),
          p_o => mul_p(lane)
        );
    end generate;

    process(clk)
      variable sample_v  : signed(DATA_WIDTH - 1 downto 0);
      variable tap_idx_v : natural;
      variable step_v    : signed(C_ACC_WIDTH - 1 downto 0);
      variable acc_v     : signed(C_ACC_WIDTH - 1 downto 0);
      variable out_v     : signed(DATA_WIDTH - 1 downto 0);
      variable done_v    : boolean;
    begin
      if rising_edge(clk) then
        if rst = '1' then
          samples_r <= (others => (others => '0'));
          state_r <= ST_IDLE;
          issue_idx_r <= 0;
          x_work_r <= (others => '0');
          last_work_r <= '0';
          acc_r <= (others => '0');
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          mul_valid <= (others => '0');
          mul_last <= (others => '0');
          mul_a <= (others => (others => '0'));
          mul_b <= (others => (others => '0'));
        else
          mul_valid <= (others => '0');
          mul_last <= (others => '0');

          if clear_i = '1' then
            samples_r <= (others => (others => '0'));
            state_r <= ST_IDLE;
            issue_idx_r <= 0;
            acc_r <= (others => '0');
            out_valid_r <= '0';
            out_data_r <= (others => '0');
            out_last_r <= '0';
          else
            if out_valid_r = '1' and m_axis_tready = '1' then
              out_valid_r <= '0';
            end if;

            acc_v := acc_r;
            done_v := false;
            for lane in 0 to C_DSP_LANES - 1 loop
              if mul_p_valid(lane) = '1' then
                step_v := shift_right(resize(mul_p(lane), C_ACC_WIDTH), COEFF_FRAC_BITS);
                acc_v := acc_v + step_v;
                if mul_p_last(lane) = '1' then
                  done_v := true;
                end if;
              end if;
            end loop;

            if acc_v /= acc_r or done_v then
              acc_r <= acc_v;

              if done_v then
                issue_idx_r <= 0;
                state_r <= ST_OUTPUT;
              end if;
            end if;

            case state_r is
              when ST_IDLE =>
                if s_axis_tvalid = '1' and ready_i = '1' then
                  sample_v := signed(s_axis_tdata);
                  x_work_r <= sample_v;
                  last_work_r <= s_axis_tlast;
                  acc_r <= (others => '0');
                  if C_DSP_LANES >= TAP_COUNT then
                    issue_idx_r <= TAP_COUNT;
                  else
                    issue_idx_r <= C_DSP_LANES;
                  end if;
                  for lane in 0 to C_DSP_LANES - 1 loop
                    if lane < TAP_COUNT then
                      mul_valid(lane) <= '1';
                      if lane = TAP_COUNT - 1 then
                        mul_last(lane) <= '1';
                      end if;
                      if lane = 0 then
                        mul_a(lane) <= sample_v;
                      else
                        mul_a(lane) <= samples_r(lane - 1);
                      end if;
                      mul_b(lane) <= tap_at(taps_i, lane);
                    end if;
                  end loop;
                  state_r <= ST_RUN;
                end if;

              when ST_RUN =>
                if issue_idx_r < TAP_COUNT then
                  for lane in 0 to C_DSP_LANES - 1 loop
                    tap_idx_v := issue_idx_r + lane;
                    if tap_idx_v < TAP_COUNT then
                      mul_valid(lane) <= '1';
                      if tap_idx_v = TAP_COUNT - 1 then
                        mul_last(lane) <= '1';
                      end if;
                      mul_a(lane) <= samples_r(tap_idx_v - 1);
                      mul_b(lane) <= tap_at(taps_i, tap_idx_v);
                    end if;
                  end loop;
                  if issue_idx_r + C_DSP_LANES >= TAP_COUNT then
                    issue_idx_r <= TAP_COUNT;
                  else
                    issue_idx_r <= issue_idx_r + C_DSP_LANES;
                  end if;
                end if;

              when ST_OUTPUT =>
                if out_valid_r = '0' or m_axis_tready = '1' then
                  out_v := raddsp_sat_signed_vec(acc_r, DATA_WIDTH);
                  for i in TAP_COUNT - 1 downto 1 loop
                    samples_r(i) <= samples_r(i - 1);
                  end loop;
                  samples_r(0) <= x_work_r;
                  out_data_r <= std_logic_vector(out_v);
                  out_last_r <= last_work_r;
                  out_valid_r <= '1';
                  state_r <= ST_IDLE;
                end if;
            end case;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_sequential_mac_rtl : if IMPLEMENTATION = "sequential_mac" and not (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    signal samples_r   : sample_array_t(0 to TAP_COUNT - 1) := (others => (others => '0'));
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable acc_v     : integer;
      variable product_v : signed(DATA_WIDTH + TAP_WIDTH - 1 downto 0);
      variable sample_v  : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          samples_r <= (others => (others => '0'));
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        else
          if clear_i = '1' then
            samples_r <= (others => (others => '0'));
          end if;

          if ready_i = '1' then
            out_valid_r <= s_axis_tvalid;
            out_last_r <= s_axis_tlast;
            if s_axis_tvalid = '1' then
              sample_v := signed(s_axis_tdata);
              acc_v := 0;
              product_v := sample_v * tap_at(taps_i, 0);
              acc_v := acc_v + to_integer(shift_right(product_v, COEFF_FRAC_BITS));
              for i in 1 to TAP_COUNT - 1 loop
                product_v := samples_r(i - 1) * tap_at(taps_i, i);
                acc_v := acc_v + to_integer(shift_right(product_v, COEFF_FRAC_BITS));
              end loop;

              for i in TAP_COUNT - 1 downto 1 loop
                samples_r(i) <= samples_r(i - 1);
              end loop;
              samples_r(0) <= sample_v;
              out_data_r <= std_logic_vector(raddsp_sat_signed(acc_v, DATA_WIDTH));
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
