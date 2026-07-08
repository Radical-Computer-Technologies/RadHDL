library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.zc_reference_pkg.all;

-- Peak selection stage for Zadoff-Chu correlation results.
-- Tracks candidate correlation maxima and emits timing/score metadata for frame detector logic.
entity zc_peak_detector is
  generic (
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string := "7series";
    -- Sets the bit width for G SAMPLE WIDTH values carried by this module.
    G_SAMPLE_WIDTH  : integer := 16;
    -- Sets the bit width for G ACC WIDTH values carried by this module.
    G_ACC_WIDTH     : integer := 40;
    -- Sets the width or count of samples handled by the datapath.
    G_FRAME_SAMPLES : integer := 1024;
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    G_PRODUCT_SHIFT : integer := 15
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk          : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst          : in  std_logic;
    -- Frame start interface signal.
    frame_start  : in  std_logic;
    -- Sample valid interface signal.
    sample_valid : in  std_logic;
    -- Input sample vector captured or processed by the datapath.
    sample_i     : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    -- Sample q interface signal.
    sample_q     : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    -- Sample ready interface signal.
    sample_ready : out std_logic;
    -- Busy interface signal.
    busy         : out std_logic;
    -- Peak valid interface signal.
    peak_valid   : out std_logic;
    -- Peak index interface signal.
    peak_index   : out integer range 0 to G_FRAME_SAMPLES - 1;
    -- Input peak i signal for this module.
    peak_i       : out signed(G_ACC_WIDTH - 1 downto 0);
    -- Peak q interface signal.
    peak_q       : out signed(G_ACC_WIDTH - 1 downto 0);
    -- Peak mag sq interface signal.
    peak_mag_sq  : out unsigned((2 * G_ACC_WIDTH) - 1 downto 0)
  );
end entity;

architecture rtl of zc_peak_detector is
  constant C_LAST_OFFSET : integer := G_FRAME_SAMPLES - ZC_REF_LEN;

  type sample_array_t is array (0 to G_FRAME_SAMPLES - 1) of signed(G_SAMPLE_WIDTH - 1 downto 0);
  type state_t is (
    S_CAPTURE,
    S_SCAN_ADDR,
    S_SCAN_READ,
    S_SCAN_MUL,
    S_SCAN_ACC,
    S_MAG_SQUARE,
    S_MAG_MUL_I,
    S_MAG_MUL_Q,
    S_MAG_SUM,
    S_SCORE,
    S_DONE
  );

  signal state      : state_t := S_CAPTURE;
  signal wr_idx     : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal offset_idx : integer range 0 to C_LAST_OFFSET := 0;
  signal zc_idx     : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal frame_i    : sample_array_t := (others => (others => '0'));
  signal frame_q    : sample_array_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of frame_i : signal is "block";
  attribute ram_style of frame_q : signal is "block";
  signal frame_rd_addr : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal frame_rd_i    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal frame_rd_q    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal acc_i      : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal acc_q      : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal mul_valid  : std_logic := '0';
  signal mul_xi     : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal mul_xq     : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal mul_ci     : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal mul_cq     : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal rr_p       : signed(47 downto 0);
  signal qq_p       : signed(47 downto 0);
  signal qi_p       : signed(47 downto 0);
  signal iq_p       : signed(47 downto 0);
  signal rr_valid   : std_logic;
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
  signal candidate_i : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal candidate_q : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal candidate_idx : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal mag_i_reg  : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal mag_q_reg  : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal mag_start  : std_logic := '0';
  signal mag_value  : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal mag_square : unsigned((2 * G_ACC_WIDTH) - 1 downto 0);
  signal mag_valid  : std_logic;
  signal mag_busy   : std_logic;
  signal candidate_mag : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal best_i     : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_q     : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_mag   : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal best_idx   : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal valid_reg  : std_logic := '0';

  function coeff(value : integer; width : integer) return signed is
  begin
    return resize(to_signed(value, 32), width);
  end function;
begin
  assert G_SAMPLE_WIDTH <= 18
    report "ZC peak detector direct DSP48 complex multiply supports G_SAMPLE_WIDTH <= 18"
    severity failure;

  sample_ready <= '1' when state = S_CAPTURE else '0';
  busy <= '1' when state /= S_CAPTURE else '0';
  peak_valid <= valid_reg;
  peak_index <= best_idx;
  peak_i <= best_i;
  peak_q <= best_q;
  peak_mag_sq <= best_mag;

  rr_mul_i: entity work.raddsp_xilinx_dsp48_mul
    generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xi, b_i => mul_ci,
      valid_o => rr_valid, subtract_o => unused_sub0, last_o => unused_last0, p_o => rr_p
    );

  qq_mul_i: entity work.raddsp_xilinx_dsp48_mul
    generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xq, b_i => mul_cq,
      valid_o => unused_valid0, subtract_o => unused_sub1, last_o => unused_last1, p_o => qq_p
    );

  qi_mul_i: entity work.raddsp_xilinx_dsp48_mul
    generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xq, b_i => mul_ci,
      valid_o => unused_valid1, subtract_o => unused_sub2, last_o => unused_last2, p_o => qi_p
    );

  iq_mul_i: entity work.raddsp_xilinx_dsp48_mul
    generic map (DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xi, b_i => mul_cq,
      valid_o => unused_valid2, subtract_o => unused_sub3, last_o => unused_last3, p_o => iq_p
    );

  mag_square_i: entity work.raddsp_xilinx_dsp48_square_seq
    generic map (
      DEVICE_FAMILY => DEVICE_FAMILY,
      WIDTH         => G_ACC_WIDTH
    )
    port map (
      clk     => clk,
      rst     => rst,
      start_i => mag_start,
      x_i     => mag_value,
      busy_o  => mag_busy,
      valid_o => mag_valid,
      y_o     => mag_square
    );

  process(clk)
    variable ci       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable cq       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable prod_i   : signed(48 downto 0);
    variable prod_q   : signed(48 downto 0);
    variable next_i   : signed(G_ACC_WIDTH - 1 downto 0);
    variable next_q   : signed(G_ACC_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S_CAPTURE;
        wr_idx <= 0;
        offset_idx <= 0;
        zc_idx <= 0;
        frame_rd_addr <= 0;
        frame_rd_i <= (others => '0');
        frame_rd_q <= (others => '0');
        acc_i <= (others => '0');
        acc_q <= (others => '0');
        mul_valid <= '0';
        mul_xi <= (others => '0');
        mul_xq <= (others => '0');
        mul_ci <= (others => '0');
        mul_cq <= (others => '0');
        candidate_i <= (others => '0');
        candidate_q <= (others => '0');
        candidate_idx <= 0;
        mag_i_reg <= (others => '0');
        mag_q_reg <= (others => '0');
        mag_start <= '0';
        mag_value <= (others => '0');
        candidate_mag <= (others => '0');
        best_i <= (others => '0');
        best_q <= (others => '0');
        best_mag <= (others => '0');
        best_idx <= 0;
        valid_reg <= '0';
      else
        frame_rd_i <= frame_i(frame_rd_addr);
        frame_rd_q <= frame_q(frame_rd_addr);
        mul_valid <= '0';
        mag_start <= '0';
        valid_reg <= '0';

        case state is
          when S_CAPTURE =>
            if frame_start = '1' then
              wr_idx <= 0;
            end if;

            if sample_valid = '1' then
              frame_i(wr_idx) <= sample_i;
              frame_q(wr_idx) <= sample_q;
              if wr_idx = G_FRAME_SAMPLES - 1 then
                wr_idx <= 0;
                offset_idx <= 0;
                zc_idx <= 0;
                frame_rd_addr <= 0;
                acc_i <= (others => '0');
                acc_q <= (others => '0');
                mul_valid <= '0';
                mul_xi <= (others => '0');
                mul_xq <= (others => '0');
                mul_ci <= (others => '0');
                mul_cq <= (others => '0');
                candidate_i <= (others => '0');
                candidate_q <= (others => '0');
                candidate_idx <= 0;
                mag_i_reg <= (others => '0');
                mag_q_reg <= (others => '0');
                mag_start <= '0';
                mag_value <= (others => '0');
                candidate_mag <= (others => '0');
                best_i <= (others => '0');
                best_q <= (others => '0');
                best_mag <= (others => '0');
                best_idx <= 0;
                state <= S_SCAN_ADDR;
              else
                wr_idx <= wr_idx + 1;
              end if;
            end if;

          when S_SCAN_ADDR =>
            frame_rd_addr <= offset_idx + zc_idx;
            state <= S_SCAN_READ;

          when S_SCAN_READ =>
            state <= S_SCAN_MUL;

          when S_SCAN_MUL =>
            ci := coeff(ZC_REF_I(zc_idx), G_SAMPLE_WIDTH);
            cq := coeff(ZC_REF_Q(zc_idx), G_SAMPLE_WIDTH);
            mul_xi <= frame_rd_i;
            mul_xq <= frame_rd_q;
            mul_ci <= ci;
            mul_cq <= cq;
            mul_valid <= '1';
            state <= S_SCAN_ACC;

          when S_SCAN_ACC =>
            if rr_valid = '1' then
              prod_i := resize(rr_p, prod_i'length) + resize(qq_p, prod_i'length);
              prod_q := resize(qi_p, prod_q'length) - resize(iq_p, prod_q'length);
              next_i := acc_i + resize(shift_right(prod_i, G_PRODUCT_SHIFT), G_ACC_WIDTH);
              next_q := acc_q + resize(shift_right(prod_q, G_PRODUCT_SHIFT), G_ACC_WIDTH);
              acc_i <= next_i;
              acc_q <= next_q;
              if zc_idx = ZC_REF_LEN - 1 then
                candidate_i <= next_i;
                candidate_q <= next_q;
                candidate_idx <= offset_idx + (ZC_REF_LEN / 2);
                state <= S_MAG_SQUARE;
              else
                zc_idx <= zc_idx + 1;
                state <= S_SCAN_ADDR;
              end if;
            end if;

          when S_MAG_SQUARE =>
            mag_value <= candidate_i;
            mag_start <= '1';
            state <= S_MAG_MUL_I;

          when S_MAG_MUL_I =>
            if mag_valid = '1' then
              mag_i_reg <= mag_square;
              mag_value <= candidate_q;
              mag_start <= '1';
              state <= S_MAG_MUL_Q;
            end if;

          when S_MAG_MUL_Q =>
            if mag_valid = '1' then
              mag_q_reg <= mag_square;
              state <= S_MAG_SUM;
            end if;

          when S_MAG_SUM =>
            candidate_mag <= mag_i_reg + mag_q_reg;
            state <= S_SCORE;

          when S_SCORE =>
            if candidate_mag > best_mag then
              best_mag <= candidate_mag;
              best_i <= candidate_i;
              best_q <= candidate_q;
              best_idx <= candidate_idx;
            end if;
            acc_i <= (others => '0');
            acc_q <= (others => '0');
            zc_idx <= 0;
            if offset_idx = C_LAST_OFFSET then
              state <= S_DONE;
            else
              offset_idx <= offset_idx + 1;
              state <= S_SCAN_ADDR;
            end if;

          when S_DONE =>
            valid_reg <= '1';
            state <= S_CAPTURE;
        end case;
      end if;
    end if;
  end process;
end architecture;
