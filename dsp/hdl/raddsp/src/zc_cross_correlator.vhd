library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.zc_reference_pkg.all;

-- Streaming Zadoff-Chu cross-correlator primitive.
-- Computes correlation energy between an incoming complex stream and a stored reference sequence.
entity zc_cross_correlator is
  generic (
    -- Selects the vendor-specific implementation path.
    VENDOR          : string := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY : string := "7series";
    -- Sets the bit width for G SAMPLE WIDTH values carried by this module.
    G_SAMPLE_WIDTH : integer := 16;
    -- Sets the bit width for G ACC WIDTH values carried by this module.
    G_ACC_WIDTH    : integer := 40;
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    G_PRODUCT_SHIFT : integer := 15
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk          : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst          : in  std_logic;
    -- Block start interface signal.
    block_start  : in  std_logic;
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
    -- Corr valid interface signal.
    corr_valid   : out std_logic;
    -- Input corr i signal for this module.
    corr_i       : out signed(G_ACC_WIDTH - 1 downto 0);
    -- Corr q interface signal.
    corr_q       : out signed(G_ACC_WIDTH - 1 downto 0);
    -- Corr mag sq interface signal.
    corr_mag_sq  : out unsigned((2 * G_ACC_WIDTH) - 1 downto 0)
  );
end entity;

architecture rtl of zc_cross_correlator is
  function addr_width(depth : positive) return positive is
    variable v : natural := depth - 1;
    variable w : positive := 1;
  begin
    while v > 1 loop
      v := v / 2;
      w := w + 1;
    end loop;
    return w;
  end function;

  constant C_SAMPLE_ADDR_WIDTH : positive := addr_width(ZC_REF_LEN);
  type state_t is (
    S_COLLECT,
    S_MAC_ADDR,
    S_MAC_READ,
    S_MAC_MUL,
    S_MAC_ACC,
    S_MAG_SQUARE,
    S_MAG_MUL_I,
    S_MAG_MUL_Q,
    S_MAG_SUM,
    S_DONE
  );

  signal state       : state_t := S_COLLECT;
  signal wr_idx      : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal mac_idx     : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal sample_wr_en : std_logic := '0';
  signal sample_wr_addr : unsigned(C_SAMPLE_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal sample_wr_i : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_wr_q : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_rd_addr : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal sample_rd_i    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_rd_q    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal acc_i       : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal acc_q       : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal corr_i_reg  : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal corr_q_reg  : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal mul_valid   : std_logic := '0';
  signal mul_xi      : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal mul_xq      : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal mul_ci      : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal mul_cq      : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal rr_p        : signed(47 downto 0);
  signal qq_p        : signed(47 downto 0);
  signal qi_p        : signed(47 downto 0);
  signal iq_p        : signed(47 downto 0);
  signal rr_valid    : std_logic;
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
  signal mag_i_reg   : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal mag_q_reg   : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal mag_start   : std_logic := '0';
  signal mag_value   : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal mag_square  : unsigned((2 * G_ACC_WIDTH) - 1 downto 0);
  signal mag_valid   : std_logic;
  signal mag_busy    : std_logic;
  signal mag_reg     : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal valid_reg   : std_logic := '0';

  function sat_resize(value : integer; width : integer) return signed is
  begin
    return resize(to_signed(value, 32), width);
  end function;
begin
  assert G_SAMPLE_WIDTH <= 18
    report "ZC cross correlator direct DSP48 complex multiply supports G_SAMPLE_WIDTH <= 18"
    severity failure;

  sample_ready <= '1' when state = S_COLLECT else '0';
  busy <= '1' when state /= S_COLLECT else '0';
  corr_valid <= valid_reg;
  corr_i <= corr_i_reg;
  corr_q <= corr_q_reg;
  corr_mag_sq <= mag_reg;

  sample_i_ram : entity work.radhdl_sample_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      DATA_WIDTH => G_SAMPLE_WIDTH,
      ADDR_WIDTH => C_SAMPLE_ADDR_WIDTH,
      DEPTH => ZC_REF_LEN
    )
    port map (
      clk => clk,
      wr_en => sample_wr_en,
      wr_addr => sample_wr_addr,
      wr_data => sample_wr_i,
      rd_addr => to_unsigned(sample_rd_addr, C_SAMPLE_ADDR_WIDTH),
      rd_data => sample_rd_i
    );

  sample_q_ram : entity work.radhdl_sample_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      DATA_WIDTH => G_SAMPLE_WIDTH,
      ADDR_WIDTH => C_SAMPLE_ADDR_WIDTH,
      DEPTH => ZC_REF_LEN
    )
    port map (
      clk => clk,
      wr_en => sample_wr_en,
      wr_addr => sample_wr_addr,
      wr_data => sample_wr_q,
      rd_addr => to_unsigned(sample_rd_addr, C_SAMPLE_ADDR_WIDTH),
      rd_data => sample_rd_q
    );

  rr_mul_i: entity work.raddsp_mul
    generic map (VENDOR => VENDOR, DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xi, b_i => mul_ci,
      valid_o => rr_valid, subtract_o => unused_sub0, last_o => unused_last0, p_o => rr_p
    );

  qq_mul_i: entity work.raddsp_mul
    generic map (VENDOR => VENDOR, DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xq, b_i => mul_cq,
      valid_o => unused_valid0, subtract_o => unused_sub1, last_o => unused_last1, p_o => qq_p
    );

  qi_mul_i: entity work.raddsp_mul
    generic map (VENDOR => VENDOR, DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xq, b_i => mul_ci,
      valid_o => unused_valid1, subtract_o => unused_sub2, last_o => unused_last2, p_o => qi_p
    );

  iq_mul_i: entity work.raddsp_mul
    generic map (VENDOR => VENDOR, DEVICE_FAMILY => DEVICE_FAMILY, A_WIDTH => G_SAMPLE_WIDTH, B_WIDTH => G_SAMPLE_WIDTH)
    port map (
      clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => '0',
      a_i => mul_xi, b_i => mul_cq,
      valid_o => unused_valid2, subtract_o => unused_sub3, last_o => unused_last3, p_o => iq_p
    );

  mag_square_i: entity work.raddsp_square_seq
    generic map (
      VENDOR => VENDOR,
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
        state <= S_COLLECT;
        wr_idx <= 0;
        mac_idx <= 0;
        sample_wr_en <= '0';
        sample_wr_addr <= (others => '0');
        sample_wr_i <= (others => '0');
        sample_wr_q <= (others => '0');
        sample_rd_addr <= 0;
        sample_rd_i <= (others => '0');
        sample_rd_q <= (others => '0');
        acc_i <= (others => '0');
        acc_q <= (others => '0');
        corr_i_reg <= (others => '0');
        corr_q_reg <= (others => '0');
        mul_valid <= '0';
        mul_xi <= (others => '0');
        mul_xq <= (others => '0');
        mul_ci <= (others => '0');
        mul_cq <= (others => '0');
        mag_i_reg <= (others => '0');
        mag_q_reg <= (others => '0');
        mag_start <= '0';
        mag_value <= (others => '0');
        mag_reg <= (others => '0');
        valid_reg <= '0';
      else
        sample_wr_en <= '0';
        mul_valid <= '0';
        mag_start <= '0';
        valid_reg <= '0';

        case state is
          when S_COLLECT =>
            if block_start = '1' then
              wr_idx <= 0;
            end if;

            if sample_valid = '1' then
              sample_wr_en <= '1';
              sample_wr_addr <= to_unsigned(wr_idx, C_SAMPLE_ADDR_WIDTH);
              sample_wr_i <= sample_i;
              sample_wr_q <= sample_q;
              if wr_idx = ZC_REF_LEN - 1 then
                wr_idx <= 0;
                mac_idx <= 0;
                acc_i <= (others => '0');
                acc_q <= (others => '0');
                sample_rd_addr <= 0;
                state <= S_MAC_ADDR;
              else
                wr_idx <= wr_idx + 1;
              end if;
            end if;

          when S_MAC_ADDR =>
            sample_rd_addr <= mac_idx;
            state <= S_MAC_READ;

          when S_MAC_READ =>
            state <= S_MAC_MUL;

          when S_MAC_MUL =>
            ci := sat_resize(ZC_REF_I(mac_idx), G_SAMPLE_WIDTH);
            cq := sat_resize(ZC_REF_Q(mac_idx), G_SAMPLE_WIDTH);
            mul_xi <= sample_rd_i;
            mul_xq <= sample_rd_q;
            mul_ci <= ci;
            mul_cq <= cq;
            mul_valid <= '1';
            state <= S_MAC_ACC;

          when S_MAC_ACC =>
            if rr_valid = '1' then
              prod_i := resize(rr_p, prod_i'length) + resize(qq_p, prod_i'length);
              prod_q := resize(qi_p, prod_q'length) - resize(iq_p, prod_q'length);
              next_i := acc_i + resize(shift_right(prod_i, G_PRODUCT_SHIFT), G_ACC_WIDTH);
              next_q := acc_q + resize(shift_right(prod_q, G_PRODUCT_SHIFT), G_ACC_WIDTH);
              acc_i <= next_i;
              acc_q <= next_q;

              if mac_idx = ZC_REF_LEN - 1 then
                corr_i_reg <= next_i;
                corr_q_reg <= next_q;
                state <= S_MAG_SQUARE;
              else
                mac_idx <= mac_idx + 1;
                state <= S_MAC_ADDR;
              end if;
            end if;

          when S_MAG_SQUARE =>
            mag_value <= corr_i_reg;
            mag_start <= '1';
            state <= S_MAG_MUL_I;

          when S_MAG_MUL_I =>
            if mag_valid = '1' then
              mag_i_reg <= mag_square;
              mag_value <= corr_q_reg;
              mag_start <= '1';
              state <= S_MAG_MUL_Q;
            end if;

          when S_MAG_MUL_Q =>
            if mag_valid = '1' then
              mag_q_reg <= mag_square;
              state <= S_MAG_SUM;
            end if;

          when S_MAG_SUM =>
            mag_reg <= mag_i_reg + mag_q_reg;
            state <= S_DONE;

          when S_DONE =>
            valid_reg <= '1';
            state <= S_COLLECT;
        end case;
      end if;
    end if;
  end process;
end architecture;
