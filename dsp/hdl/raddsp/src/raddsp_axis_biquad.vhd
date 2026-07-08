library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- Multi-channel AXI-stream biquad IIR filter.
-- Applies configurable fixed-point second-order-section coefficients to each channel while preserving ready/valid and frame metadata.
entity raddsp_axis_biquad is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets the bit width for COEFF WIDTH values carried by this module.
    COEFF_WIDTH     : positive := 18;
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
    -- Input b0 i signal for this module.
    b0_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input b1 i signal for this module.
    b1_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input b2 i signal for this module.
    b2_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input a1 i signal for this module.
    a1_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    -- Input a2 i signal for this module.
    a2_i          : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
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

architecture rtl of raddsp_axis_biquad is
  constant C_PRODUCT_WIDTH : positive := DATA_WIDTH + COEFF_WIDTH;
  constant C_ACC_WIDTH     : positive := C_PRODUCT_WIDTH + 4;
  type sample_array_t is array (natural range <>) of signed(DATA_WIDTH - 1 downto 0);
  type coeff_array_t is array (natural range <>) of signed(COEFF_WIDTH - 1 downto 0);
  type product_array_t is array (natural range <>) of signed(47 downto 0);
begin
  assert COEFF_FRAC_BITS < C_ACC_WIDTH
    report "COEFF_FRAC_BITS is too large"
    severity failure;

  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
  begin
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
  begin
  end generate;

  gen_parallel : if IMPLEMENTATION = "parallel" generate
    signal x1_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x2_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y1_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y2_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
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
      variable x_v       : signed(DATA_WIDTH - 1 downto 0);
      variable p_b0_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable p_b1_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable p_b2_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable p_a1_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable p_a2_v    : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable acc_v     : signed(C_ACC_WIDTH - 1 downto 0);
      variable scaled_v  : signed(C_ACC_WIDTH - 1 downto 0);
      variable y_next_v  : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          x1_r <= (others => '0');
          x2_r <= (others => '0');
          y1_r <= (others => '0');
          y2_r <= (others => '0');
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        else
          if clear_i = '1' then
            x1_r <= (others => '0');
            x2_r <= (others => '0');
            y1_r <= (others => '0');
            y2_r <= (others => '0');
          end if;

          if ready_i = '1' then
            out_valid_r <= s_axis_tvalid;
            out_last_r <= s_axis_tlast;

            if s_axis_tvalid = '1' then
              x_v := signed(s_axis_tdata);
              p_b0_v := x_v * signed(b0_i);
              p_b1_v := x1_r * signed(b1_i);
              p_b2_v := x2_r * signed(b2_i);
              p_a1_v := y1_r * signed(a1_i);
              p_a2_v := y2_r * signed(a2_i);
              acc_v := resize(p_b0_v, C_ACC_WIDTH)
                     + resize(p_b1_v, C_ACC_WIDTH)
                     + resize(p_b2_v, C_ACC_WIDTH)
                     - resize(p_a1_v, C_ACC_WIDTH)
                     - resize(p_a2_v, C_ACC_WIDTH);
              scaled_v := shift_right(acc_v, COEFF_FRAC_BITS);
              y_next_v := raddsp_sat_signed_vec(scaled_v, DATA_WIDTH);

              x2_r <= x1_r;
              x1_r <= x_v;
              y2_r <= y1_r;
              y1_r <= y_next_v;
              out_data_r <= std_logic_vector(y_next_v);
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_parallel_dsp_xilinx : if (IMPLEMENTATION = "parallel_dsp" or (IMPLEMENTATION = "sequential_mac" and DSP_LANES >= 5)) and (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    type state_t is (ST_IDLE, ST_WAIT_PRODUCTS);

    signal state_r       : state_t := ST_IDLE;
    signal x1_r          : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x2_r          : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y1_r          : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y2_r          : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x_work_r      : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal last_work_r   : std_logic := '0';
    signal out_valid_r   : std_logic := '0';
    signal out_data_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r    : std_logic := '0';
    signal ready_i       : std_logic;
    signal mul_valid     : std_logic_vector(0 to 4) := (others => '0');
    signal mul_sub       : std_logic_vector(0 to 4) := (others => '0');
    signal mul_a         : sample_array_t(0 to 4) := (others => (others => '0'));
    signal mul_b         : coeff_array_t(0 to 4) := (others => (others => '0'));
    signal mul_p         : product_array_t(0 to 4);
    signal mul_p_valid   : std_logic_vector(0 to 4);
    signal unused_sub    : std_logic_vector(0 to 4);
    signal unused_last   : std_logic_vector(0 to 4);
  begin
    assert C_ACC_WIDTH <= 48
      report "DSP48 parallel biquad accumulator must fit in 48 bits"
      severity failure;
    assert DATA_WIDTH <= 25
      report "DSP48 parallel biquad supports DATA_WIDTH <= 25"
      severity failure;
    assert COEFF_WIDTH <= 18
      report "DSP48 parallel biquad supports COEFF_WIDTH <= 18"
      severity failure;

    ready_i <= '1' when state_r = ST_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    gen_mul_lanes : for lane in 0 to 4 generate
    begin
      dsp_mul_i: entity raddsp.raddsp_xilinx_dsp48_mul
        generic map (
          DEVICE_FAMILY => DEVICE_FAMILY,
          A_WIDTH => DATA_WIDTH,
          B_WIDTH => COEFF_WIDTH
        )
        port map (
          clk => clk,
          rst => rst,
          valid_i => mul_valid(lane),
          subtract_i => mul_sub(lane),
          last_i => '0',
          a_i => mul_a(lane),
          b_i => mul_b(lane),
          valid_o => mul_p_valid(lane),
          subtract_o => unused_sub(lane),
          last_o => unused_last(lane),
          p_o => mul_p(lane)
        );
    end generate;

    process(clk)
      variable x_v       : signed(DATA_WIDTH - 1 downto 0);
      variable acc_v     : signed(C_ACC_WIDTH - 1 downto 0);
      variable scaled_v  : signed(C_ACC_WIDTH - 1 downto 0);
      variable y_next_v  : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          state_r <= ST_IDLE;
          x1_r <= (others => '0');
          x2_r <= (others => '0');
          y1_r <= (others => '0');
          y2_r <= (others => '0');
          x_work_r <= (others => '0');
          last_work_r <= '0';
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          mul_valid <= (others => '0');
          mul_sub <= (others => '0');
          mul_a <= (others => (others => '0'));
          mul_b <= (others => (others => '0'));
        else
          mul_valid <= (others => '0');
          mul_sub <= (others => '0');

          if clear_i = '1' then
            state_r <= ST_IDLE;
            x1_r <= (others => '0');
            x2_r <= (others => '0');
            y1_r <= (others => '0');
            y2_r <= (others => '0');
            x_work_r <= (others => '0');
            last_work_r <= '0';
            out_valid_r <= '0';
            out_data_r <= (others => '0');
            out_last_r <= '0';
          else
            if out_valid_r = '1' and m_axis_tready = '1' then
              out_valid_r <= '0';
            end if;

            case state_r is
              when ST_IDLE =>
                if s_axis_tvalid = '1' and ready_i = '1' then
                  x_v := signed(s_axis_tdata);
                  x_work_r <= x_v;
                  last_work_r <= s_axis_tlast;

                  mul_valid <= (others => '1');
                  mul_sub <= "00011";
                  mul_a(0) <= x_v;
                  mul_a(1) <= x1_r;
                  mul_a(2) <= x2_r;
                  mul_a(3) <= y1_r;
                  mul_a(4) <= y2_r;
                  mul_b(0) <= signed(b0_i);
                  mul_b(1) <= signed(b1_i);
                  mul_b(2) <= signed(b2_i);
                  mul_b(3) <= signed(a1_i);
                  mul_b(4) <= signed(a2_i);
                  state_r <= ST_WAIT_PRODUCTS;
                end if;

              when ST_WAIT_PRODUCTS =>
                if mul_p_valid = "11111" then
                  acc_v := resize(mul_p(0), C_ACC_WIDTH)
                         + resize(mul_p(1), C_ACC_WIDTH)
                         + resize(mul_p(2), C_ACC_WIDTH)
                         - resize(mul_p(3), C_ACC_WIDTH)
                         - resize(mul_p(4), C_ACC_WIDTH);
                  scaled_v := shift_right(acc_v, COEFF_FRAC_BITS);
                  y_next_v := raddsp_sat_signed_vec(scaled_v, DATA_WIDTH);

                  x2_r <= x1_r;
                  x1_r <= x_work_r;
                  y2_r <= y1_r;
                  y1_r <= y_next_v;
                  out_data_r <= std_logic_vector(y_next_v);
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

  gen_sequential_mac_xilinx : if IMPLEMENTATION = "sequential_mac" and DSP_LANES < 5 and (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    type state_t is (ST_IDLE, ST_RUN);

    signal state_r      : state_t := ST_IDLE;
    signal x1_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x2_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y1_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y2_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x_work_r     : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal last_work_r  : std_logic := '0';
    signal issue_idx_r  : natural range 0 to 5 := 0;
    signal collect_cnt_r : natural range 0 to 5 := 0;
    signal acc_r        : signed(C_ACC_WIDTH - 1 downto 0) := (others => '0');
    signal out_valid_r  : std_logic := '0';
    signal out_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r   : std_logic := '0';
    signal ready_i      : std_logic;
    signal mul_valid    : std_logic := '0';
    signal mul_sub      : std_logic := '0';
    signal mul_last     : std_logic := '0';
    signal mul_a        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_b        : signed(COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal mul_p        : signed(47 downto 0);
    signal mul_p_valid  : std_logic;
    signal mul_p_sub    : std_logic;
    signal mul_p_last   : std_logic;
  begin
    assert C_ACC_WIDTH <= 48
      report "DSP48 sequential biquad accumulator must fit in 48 bits"
      severity failure;

    ready_i <= '1' when state_r = ST_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    dsp_mul_i: entity raddsp.raddsp_xilinx_dsp48_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => DATA_WIDTH,
        B_WIDTH => COEFF_WIDTH
      )
      port map (
        clk => clk,
        rst => rst,
        valid_i => mul_valid,
        subtract_i => mul_sub,
        last_i => mul_last,
        a_i => mul_a,
        b_i => mul_b,
        valid_o => mul_p_valid,
        subtract_o => mul_p_sub,
        last_o => mul_p_last,
        p_o => mul_p
      );

    process(clk)
      variable x_v       : signed(DATA_WIDTH - 1 downto 0);
      variable product_v : signed(C_ACC_WIDTH - 1 downto 0);
      variable acc_v     : signed(C_ACC_WIDTH - 1 downto 0);
      variable scaled_v  : signed(C_ACC_WIDTH - 1 downto 0);
      variable y_next_v  : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          state_r <= ST_IDLE;
          x1_r <= (others => '0');
          x2_r <= (others => '0');
          y1_r <= (others => '0');
          y2_r <= (others => '0');
          x_work_r <= (others => '0');
          last_work_r <= '0';
          issue_idx_r <= 0;
          collect_cnt_r <= 0;
          acc_r <= (others => '0');
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          mul_valid <= '0';
          mul_sub <= '0';
          mul_last <= '0';
          mul_a <= (others => '0');
          mul_b <= (others => '0');
        else
          mul_valid <= '0';
          mul_sub <= '0';
          mul_last <= '0';

          if clear_i = '1' then
            state_r <= ST_IDLE;
            x1_r <= (others => '0');
            x2_r <= (others => '0');
            y1_r <= (others => '0');
            y2_r <= (others => '0');
            x_work_r <= (others => '0');
            last_work_r <= '0';
            issue_idx_r <= 0;
            collect_cnt_r <= 0;
            acc_r <= (others => '0');
            out_valid_r <= '0';
            out_data_r <= (others => '0');
            out_last_r <= '0';
          else
            if out_valid_r = '1' and m_axis_tready = '1' then
              out_valid_r <= '0';
            end if;

            if mul_p_valid = '1' then
              product_v := resize(mul_p, C_ACC_WIDTH);
              if mul_p_sub = '1' then
                acc_v := acc_r - product_v;
              else
                acc_v := acc_r + product_v;
              end if;
              acc_r <= acc_v;

              if mul_p_last = '1' then
                scaled_v := shift_right(acc_v, COEFF_FRAC_BITS);
                y_next_v := raddsp_sat_signed_vec(scaled_v, DATA_WIDTH);
                x2_r <= x1_r;
                x1_r <= x_work_r;
                y2_r <= y1_r;
                y1_r <= y_next_v;
                out_data_r <= std_logic_vector(y_next_v);
                out_last_r <= last_work_r;
                out_valid_r <= '1';
                collect_cnt_r <= 0;
                state_r <= ST_IDLE;
              else
                collect_cnt_r <= collect_cnt_r + 1;
              end if;
            end if;

            case state_r is
              when ST_IDLE =>
                if s_axis_tvalid = '1' and ready_i = '1' then
                  x_v := signed(s_axis_tdata);
                  x_work_r <= x_v;
                  last_work_r <= s_axis_tlast;
                  issue_idx_r <= 1;
                  collect_cnt_r <= 0;
                  acc_r <= (others => '0');
                  mul_valid <= '1';
                  mul_sub <= '0';
                  mul_last <= '0';
                  mul_a <= x_v;
                  mul_b <= signed(b0_i);
                  state_r <= ST_RUN;
                end if;

              when ST_RUN =>
                if issue_idx_r < 5 then
                  mul_valid <= '1';
                  case issue_idx_r is
                    when 1 =>
                      mul_sub <= '0';
                      mul_last <= '0';
                      mul_a <= x1_r;
                      mul_b <= signed(b1_i);
                    when 2 =>
                      mul_sub <= '0';
                      mul_last <= '0';
                      mul_a <= x2_r;
                      mul_b <= signed(b2_i);
                    when 3 =>
                      mul_sub <= '1';
                      mul_last <= '0';
                      mul_a <= y1_r;
                      mul_b <= signed(a1_i);
                    when others =>
                      mul_sub <= '1';
                      mul_last <= '1';
                      mul_a <= y2_r;
                      mul_b <= signed(a2_i);
                  end case;
                  issue_idx_r <= issue_idx_r + 1;
                end if;
            end case;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_sequential_mac_rtl : if IMPLEMENTATION = "sequential_mac" and not (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    type state_t is (ST_IDLE, ST_B1, ST_B2, ST_A1, ST_A2);

    signal state_r      : state_t := ST_IDLE;
    signal x1_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x2_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y1_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal y2_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal x_work_r     : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal last_work_r  : std_logic := '0';
    signal acc_r        : signed(C_ACC_WIDTH - 1 downto 0) := (others => '0');
    signal out_valid_r  : std_logic := '0';
    signal out_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r   : std_logic := '0';
    signal ready_i      : std_logic;

    attribute use_dsp : string;
    attribute use_dsp of acc_r : signal is "yes";
  begin
    ready_i <= '1' when state_r = ST_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable x_v       : signed(DATA_WIDTH - 1 downto 0);
      variable product_v : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable acc_v     : signed(C_ACC_WIDTH - 1 downto 0);
      variable scaled_v  : signed(C_ACC_WIDTH - 1 downto 0);
      variable y_next_v  : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          state_r <= ST_IDLE;
          x1_r <= (others => '0');
          x2_r <= (others => '0');
          y1_r <= (others => '0');
          y2_r <= (others => '0');
          x_work_r <= (others => '0');
          last_work_r <= '0';
          acc_r <= (others => '0');
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        else
          if clear_i = '1' then
            state_r <= ST_IDLE;
            x1_r <= (others => '0');
            x2_r <= (others => '0');
            y1_r <= (others => '0');
            y2_r <= (others => '0');
            x_work_r <= (others => '0');
            last_work_r <= '0';
            acc_r <= (others => '0');
            out_valid_r <= '0';
            out_data_r <= (others => '0');
            out_last_r <= '0';
          else
            if out_valid_r = '1' and m_axis_tready = '1' then
              out_valid_r <= '0';
            end if;

            case state_r is
              when ST_IDLE =>
                if s_axis_tvalid = '1' and ready_i = '1' then
                  x_v := signed(s_axis_tdata);
                  product_v := x_v * signed(b0_i);
                  x_work_r <= x_v;
                  last_work_r <= s_axis_tlast;
                  acc_r <= resize(product_v, C_ACC_WIDTH);
                  state_r <= ST_B1;
                end if;

              when ST_B1 =>
                product_v := x1_r * signed(b1_i);
                acc_r <= acc_r + resize(product_v, C_ACC_WIDTH);
                state_r <= ST_B2;

              when ST_B2 =>
                product_v := x2_r * signed(b2_i);
                acc_r <= acc_r + resize(product_v, C_ACC_WIDTH);
                state_r <= ST_A1;

              when ST_A1 =>
                product_v := y1_r * signed(a1_i);
                acc_r <= acc_r - resize(product_v, C_ACC_WIDTH);
                state_r <= ST_A2;

              when ST_A2 =>
                product_v := y2_r * signed(a2_i);
                acc_v := acc_r - resize(product_v, C_ACC_WIDTH);
                scaled_v := shift_right(acc_v, COEFF_FRAC_BITS);
                y_next_v := raddsp_sat_signed_vec(scaled_v, DATA_WIDTH);

                x2_r <= x1_r;
                x1_r <= x_work_r;
                y2_r <= y1_r;
                y1_r <= y_next_v;
                acc_r <= acc_v;
                out_data_r <= std_logic_vector(y_next_v);
                out_last_r <= last_work_r;
                out_valid_r <= '1';
                state_r <= ST_IDLE;
            end case;
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
