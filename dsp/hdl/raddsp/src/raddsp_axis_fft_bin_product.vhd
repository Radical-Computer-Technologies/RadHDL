library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- AXI-stream FFT-bin product stage for spectral comparison pipelines.
-- Multiplies selected complex frequency bins to support fingerprinting, correlation, and spectral feature extraction.
entity raddsp_axis_fft_bin_product is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    COEFF_FRAC_BITS : natural  := 15;
    -- Configures IMPLEMENTATION for this instance.
    IMPLEMENTATION  : string  := "latency_optimized"
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk             : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst             : in  std_logic;
    -- Input correlate i signal for this module.
    correlate_i     : in  std_logic;
    -- S0 axis tvalid interface signal.
    s0_axis_tvalid  : in  std_logic;
    -- S0 axis tready interface signal.
    s0_axis_tready  : out std_logic;
    -- S0 axis tdata interface signal.
    s0_axis_tdata   : in  std_logic_vector((2 * DATA_WIDTH) - 1 downto 0);
    -- S0 axis tlast interface signal.
    s0_axis_tlast   : in  std_logic;
    -- S1 axis tvalid interface signal.
    s1_axis_tvalid  : in  std_logic;
    -- S1 axis tready interface signal.
    s1_axis_tready  : out std_logic;
    -- S1 axis tdata interface signal.
    s1_axis_tdata   : in  std_logic_vector((2 * DATA_WIDTH) - 1 downto 0);
    -- S1 axis tlast interface signal.
    s1_axis_tlast   : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid   : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready   : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata    : out std_logic_vector((2 * DATA_WIDTH) - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast    : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_fft_bin_product is
  constant C_PRODUCT_WIDTH : positive := 48;

  function real_part(value : std_logic_vector) return signed is
  begin
    return signed(value((2 * DATA_WIDTH) - 1 downto DATA_WIDTH));
  end function;

  function imag_part(value : std_logic_vector) return signed is
  begin
    return signed(value(DATA_WIDTH - 1 downto 0));
  end function;

  function pack_complex(re_value : signed; im_value : signed) return std_logic_vector is
    variable result : std_logic_vector((2 * DATA_WIDTH) - 1 downto 0);
  begin
    result((2 * DATA_WIDTH) - 1 downto DATA_WIDTH) := std_logic_vector(raddsp_sat_signed_vec(re_value, DATA_WIDTH));
    result(DATA_WIDTH - 1 downto 0) := std_logic_vector(raddsp_sat_signed_vec(im_value, DATA_WIDTH));
    return result;
  end function;
begin
  assert DATA_WIDTH <= 18
    report "raddsp_axis_fft_bin_product supports DATA_WIDTH <= 18 for DSP48 direct multipliers"
    severity failure;

  gen_xilinx_latency : if (VENDOR = "xilinx" or VENDOR = "XILINX") and IMPLEMENTATION = "latency_optimized" generate
    type state_t is (S_IDLE, S_WAIT_DSP, S_OUTPUT);

    signal state_r      : state_t := S_IDLE;
    signal ready_i      : std_logic;
    signal out_valid_r  : std_logic := '0';
    signal out_data_r   : std_logic_vector((2 * DATA_WIDTH) - 1 downto 0) := (others => '0');
    signal out_last_r   : std_logic := '0';
    signal corr_r       : std_logic := '0';
    signal last_r       : std_logic := '0';

    signal ar_s         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal ai_s         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal br_s         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal bi_s         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_valid    : std_logic := '0';
    signal arbr_p       : signed(C_PRODUCT_WIDTH - 1 downto 0);
    signal aibi_p       : signed(C_PRODUCT_WIDTH - 1 downto 0);
    signal arbi_p       : signed(C_PRODUCT_WIDTH - 1 downto 0);
    signal aibr_p       : signed(C_PRODUCT_WIDTH - 1 downto 0);
    signal mul_done     : std_logic;
    signal unused_valid0 : std_logic;
    signal unused_valid1 : std_logic;
    signal unused_valid2 : std_logic;
    signal unused_sub0   : std_logic;
    signal unused_sub1   : std_logic;
    signal unused_sub2   : std_logic;
    signal unused_sub3   : std_logic;
    signal unused_last0  : std_logic;
    signal unused_last1  : std_logic;
    signal unused_last2  : std_logic;
    signal unused_last3  : std_logic;
  begin
    ready_i <= '1' when state_r = S_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s0_axis_tready <= ready_i and s1_axis_tvalid;
    s1_axis_tready <= ready_i and s0_axis_tvalid;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    arbr_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => DATA_WIDTH, B_WIDTH => DATA_WIDTH)
      port map (clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => last_r,
                a_i => ar_s, b_i => br_s, valid_o => mul_done, subtract_o => unused_sub0,
                last_o => unused_last0, p_o => arbr_p);

    aibi_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => DATA_WIDTH, B_WIDTH => DATA_WIDTH)
      port map (clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => last_r,
                a_i => ai_s, b_i => bi_s, valid_o => unused_valid0, subtract_o => unused_sub1,
                last_o => unused_last1, p_o => aibi_p);

    arbi_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => DATA_WIDTH, B_WIDTH => DATA_WIDTH)
      port map (clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => last_r,
                a_i => ar_s, b_i => bi_s, valid_o => unused_valid1, subtract_o => unused_sub2,
                last_o => unused_last2, p_o => arbi_p);

    aibr_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => DATA_WIDTH, B_WIDTH => DATA_WIDTH)
      port map (clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => last_r,
                a_i => ai_s, b_i => br_s, valid_o => unused_valid2, subtract_o => unused_sub3,
                last_o => unused_last3, p_o => aibr_p);

    process(clk)
      variable re_full : signed(C_PRODUCT_WIDTH downto 0);
      variable im_full : signed(C_PRODUCT_WIDTH downto 0);
      variable re_out  : signed(C_PRODUCT_WIDTH downto 0);
      variable im_out  : signed(C_PRODUCT_WIDTH downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          state_r <= S_IDLE;
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          corr_r <= '0';
          last_r <= '0';
          ar_s <= (others => '0');
          ai_s <= (others => '0');
          br_s <= (others => '0');
          bi_s <= (others => '0');
          mul_valid <= '0';
        else
          mul_valid <= '0';

          if out_valid_r = '1' and m_axis_tready = '1' then
            out_valid_r <= '0';
          end if;

          case state_r is
            when S_IDLE =>
              if s0_axis_tvalid = '1' and s1_axis_tvalid = '1' and ready_i = '1' then
                ar_s <= real_part(s0_axis_tdata);
                ai_s <= imag_part(s0_axis_tdata);
                br_s <= real_part(s1_axis_tdata);
                bi_s <= imag_part(s1_axis_tdata);
                corr_r <= correlate_i;
                last_r <= s0_axis_tlast or s1_axis_tlast;
                mul_valid <= '1';
                state_r <= S_WAIT_DSP;
              end if;

            when S_WAIT_DSP =>
              if mul_done = '1' then
                if corr_r = '1' then
                  re_full := resize(arbr_p, re_full'length) + resize(aibi_p, re_full'length);
                  im_full := resize(aibr_p, im_full'length) - resize(arbi_p, im_full'length);
                else
                  re_full := resize(arbr_p, re_full'length) - resize(aibi_p, re_full'length);
                  im_full := resize(arbi_p, im_full'length) + resize(aibr_p, im_full'length);
                end if;
                re_out := shift_right(re_full, COEFF_FRAC_BITS);
                im_out := shift_right(im_full, COEFF_FRAC_BITS);
                out_data_r <= pack_complex(re_out, im_out);
                out_last_r <= last_r;
                out_valid_r <= '1';
                state_r <= S_OUTPUT;
              end if;

            when S_OUTPUT =>
              if out_valid_r = '0' or m_axis_tready = '1' then
                state_r <= S_IDLE;
              end if;
          end case;
        end if;
      end if;
    end process;
  end generate;

  gen_xilinx_resource : if (VENDOR = "xilinx" or VENDOR = "XILINX") and IMPLEMENTATION /= "latency_optimized" generate
    type state_t is (
      S_IDLE,
      S_MUL_ARBR,
      S_WAIT_ARBR,
      S_MUL_AIBI,
      S_WAIT_AIBI,
      S_MUL_ARBI,
      S_WAIT_ARBI,
      S_MUL_AIBR,
      S_WAIT_AIBR,
      S_OUTPUT
    );

    signal state_r     : state_t := S_IDLE;
    signal ready_i     : std_logic;
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector((2 * DATA_WIDTH) - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal corr_r      : std_logic := '0';
    signal last_r      : std_logic := '0';
    signal ar_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal ai_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal br_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal bi_r        : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal arbr_r      : signed(C_PRODUCT_WIDTH - 1 downto 0) := (others => '0');
    signal aibi_r      : signed(C_PRODUCT_WIDTH - 1 downto 0) := (others => '0');
    signal arbi_r      : signed(C_PRODUCT_WIDTH - 1 downto 0) := (others => '0');
    signal mul_valid   : std_logic := '0';
    signal mul_a       : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_b       : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_done    : std_logic;
    signal mul_p       : signed(C_PRODUCT_WIDTH - 1 downto 0);
    signal unused_sub  : std_logic;
    signal unused_last : std_logic;
  begin
    ready_i <= '1' when state_r = S_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s0_axis_tready <= ready_i and s1_axis_tvalid;
    s1_axis_tready <= ready_i and s0_axis_tvalid;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    dsp_mul_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => DATA_WIDTH,
        B_WIDTH => DATA_WIDTH
      )
      port map (
        clk => clk,
        rst => rst,
        valid_i => mul_valid,
        subtract_i => '0',
        last_i => last_r,
        a_i => mul_a,
        b_i => mul_b,
        valid_o => mul_done,
        subtract_o => unused_sub,
        last_o => unused_last,
        p_o => mul_p
      );

    process(clk)
      variable re_full : signed(C_PRODUCT_WIDTH downto 0);
      variable im_full : signed(C_PRODUCT_WIDTH downto 0);
      variable re_out  : signed(C_PRODUCT_WIDTH downto 0);
      variable im_out  : signed(C_PRODUCT_WIDTH downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          state_r <= S_IDLE;
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          corr_r <= '0';
          last_r <= '0';
          ar_r <= (others => '0');
          ai_r <= (others => '0');
          br_r <= (others => '0');
          bi_r <= (others => '0');
          arbr_r <= (others => '0');
          aibi_r <= (others => '0');
          arbi_r <= (others => '0');
          mul_valid <= '0';
          mul_a <= (others => '0');
          mul_b <= (others => '0');
        else
          mul_valid <= '0';

          if out_valid_r = '1' and m_axis_tready = '1' then
            out_valid_r <= '0';
          end if;

          case state_r is
            when S_IDLE =>
              if s0_axis_tvalid = '1' and s1_axis_tvalid = '1' and ready_i = '1' then
                ar_r <= real_part(s0_axis_tdata);
                ai_r <= imag_part(s0_axis_tdata);
                br_r <= real_part(s1_axis_tdata);
                bi_r <= imag_part(s1_axis_tdata);
                corr_r <= correlate_i;
                last_r <= s0_axis_tlast or s1_axis_tlast;
                state_r <= S_MUL_ARBR;
              end if;

            when S_MUL_ARBR =>
              mul_a <= ar_r;
              mul_b <= br_r;
              mul_valid <= '1';
              state_r <= S_WAIT_ARBR;

            when S_WAIT_ARBR =>
              if mul_done = '1' then
                arbr_r <= mul_p;
                state_r <= S_MUL_AIBI;
              end if;

            when S_MUL_AIBI =>
              mul_a <= ai_r;
              mul_b <= bi_r;
              mul_valid <= '1';
              state_r <= S_WAIT_AIBI;

            when S_WAIT_AIBI =>
              if mul_done = '1' then
                aibi_r <= mul_p;
                state_r <= S_MUL_ARBI;
              end if;

            when S_MUL_ARBI =>
              mul_a <= ar_r;
              mul_b <= bi_r;
              mul_valid <= '1';
              state_r <= S_WAIT_ARBI;

            when S_WAIT_ARBI =>
              if mul_done = '1' then
                arbi_r <= mul_p;
                state_r <= S_MUL_AIBR;
              end if;

            when S_MUL_AIBR =>
              mul_a <= ai_r;
              mul_b <= br_r;
              mul_valid <= '1';
              state_r <= S_WAIT_AIBR;

            when S_WAIT_AIBR =>
              if mul_done = '1' then
                if corr_r = '1' then
                  re_full := resize(arbr_r, re_full'length) + resize(aibi_r, re_full'length);
                  im_full := resize(mul_p, im_full'length) - resize(arbi_r, im_full'length);
                else
                  re_full := resize(arbr_r, re_full'length) - resize(aibi_r, re_full'length);
                  im_full := resize(arbi_r, im_full'length) + resize(mul_p, im_full'length);
                end if;
                re_out := shift_right(re_full, COEFF_FRAC_BITS);
                im_out := shift_right(im_full, COEFF_FRAC_BITS);
                out_data_r <= pack_complex(re_out, im_out);
                out_last_r <= last_r;
                out_valid_r <= '1';
                state_r <= S_OUTPUT;
              end if;

            when S_OUTPUT =>
              if out_valid_r = '0' or m_axis_tready = '1' then
                state_r <= S_IDLE;
              end if;
          end case;
        end if;
      end if;
    end process;
  end generate;

  gen_generic_vendor : if not (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    signal ready_i     : std_logic;
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector((2 * DATA_WIDTH) - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
  begin
    ready_i <= '1' when out_valid_r = '0' or m_axis_tready = '1' else '0';
    s0_axis_tready <= ready_i and s1_axis_tvalid;
    s1_axis_tready <= ready_i and s0_axis_tvalid;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable ar_v    : signed(DATA_WIDTH - 1 downto 0);
      variable ai_v    : signed(DATA_WIDTH - 1 downto 0);
      variable br_v    : signed(DATA_WIDTH - 1 downto 0);
      variable bi_v    : signed(DATA_WIDTH - 1 downto 0);
      variable arbr_v  : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable aibi_v  : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable arbi_v  : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable aibr_v  : signed(C_PRODUCT_WIDTH - 1 downto 0);
      variable re_full : signed(C_PRODUCT_WIDTH downto 0);
      variable im_full : signed(C_PRODUCT_WIDTH downto 0);
      variable re_out  : signed(C_PRODUCT_WIDTH downto 0);
      variable im_out  : signed(C_PRODUCT_WIDTH downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        else
          if out_valid_r = '1' and m_axis_tready = '1' then
            out_valid_r <= '0';
          end if;

          if s0_axis_tvalid = '1' and s1_axis_tvalid = '1' and ready_i = '1' then
            ar_v := real_part(s0_axis_tdata);
            ai_v := imag_part(s0_axis_tdata);
            br_v := real_part(s1_axis_tdata);
            bi_v := imag_part(s1_axis_tdata);
            arbr_v := resize(ar_v * br_v, C_PRODUCT_WIDTH);
            aibi_v := resize(ai_v * bi_v, C_PRODUCT_WIDTH);
            arbi_v := resize(ar_v * bi_v, C_PRODUCT_WIDTH);
            aibr_v := resize(ai_v * br_v, C_PRODUCT_WIDTH);

            if correlate_i = '1' then
              re_full := resize(arbr_v, re_full'length) + resize(aibi_v, re_full'length);
              im_full := resize(aibr_v, im_full'length) - resize(arbi_v, im_full'length);
            else
              re_full := resize(arbr_v, re_full'length) - resize(aibi_v, re_full'length);
              im_full := resize(arbi_v, im_full'length) + resize(aibr_v, im_full'length);
            end if;

            re_out := shift_right(re_full, COEFF_FRAC_BITS);
            im_out := shift_right(im_full, COEFF_FRAC_BITS);
            out_data_r <= pack_complex(re_out, im_out);
            out_last_r <= s0_axis_tlast or s1_axis_tlast;
            out_valid_r <= '1';
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
