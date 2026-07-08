library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- AXI-stream elementwise matrix arithmetic block.
-- Applies lane-wise arithmetic across matrix-shaped streams for preprocessing and transform pipelines.
entity raddsp_axis_matrix_elementwise is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk             : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst             : in  std_logic;
    -- Input op i signal for this module.
    op_i            : in  std_logic_vector(1 downto 0);
    -- S0 axis tvalid interface signal.
    s0_axis_tvalid  : in  std_logic;
    -- S0 axis tready interface signal.
    s0_axis_tready  : out std_logic;
    -- S0 axis tdata interface signal.
    s0_axis_tdata   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- S0 axis tlast interface signal.
    s0_axis_tlast   : in  std_logic;
    -- S1 axis tvalid interface signal.
    s1_axis_tvalid  : in  std_logic;
    -- S1 axis tready interface signal.
    s1_axis_tready  : out std_logic;
    -- S1 axis tdata interface signal.
    s1_axis_tdata   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- S1 axis tlast interface signal.
    s1_axis_tlast   : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid   : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready   : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata    : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast    : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_matrix_elementwise is
  constant OP_ADD      : std_logic_vector(1 downto 0) := "00";
  constant OP_SUBTRACT : std_logic_vector(1 downto 0) := "01";
  constant OP_HADAMARD : std_logic_vector(1 downto 0) := "10";
begin
  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal busy_r      : std_logic := '0';
    signal ready_i     : std_logic;
    signal mul_valid   : std_logic := '0';
    signal mul_last    : std_logic := '0';
    signal mul_a       : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_b       : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_p       : signed(47 downto 0);
    signal mul_p_valid : std_logic;
    signal mul_p_last  : std_logic;
    signal unused_sub  : std_logic;
  begin
    assert DATA_WIDTH <= 18
      report "DSP48 matrix elementwise supports DATA_WIDTH <= 18"
      severity failure;

    ready_i <= '1' when busy_r = '0' and (out_valid_r = '0' or m_axis_tready = '1') else '0';
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
        last_i => mul_last,
        a_i => mul_a,
        b_i => mul_b,
        valid_o => mul_p_valid,
        subtract_o => unused_sub,
        last_o => mul_p_last,
        p_o => mul_p
      );

    process(clk)
      variable a_v      : signed(DATA_WIDTH - 1 downto 0);
      variable b_v      : signed(DATA_WIDTH - 1 downto 0);
      variable sum_v    : signed(DATA_WIDTH downto 0);
      variable scaled_v : signed(47 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          busy_r <= '0';
          mul_valid <= '0';
          mul_last <= '0';
          mul_a <= (others => '0');
          mul_b <= (others => '0');
        else
          mul_valid <= '0';
          mul_last <= '0';

          if out_valid_r = '1' and m_axis_tready = '1' then
            out_valid_r <= '0';
          end if;

          if mul_p_valid = '1' then
            scaled_v := shift_right(mul_p, COEFF_FRAC_BITS);
            out_data_r <= std_logic_vector(raddsp_sat_signed_vec(scaled_v, DATA_WIDTH));
            out_last_r <= mul_p_last;
            out_valid_r <= '1';
            busy_r <= '0';
          end if;

          if s0_axis_tvalid = '1' and s1_axis_tvalid = '1' and ready_i = '1' then
            a_v := signed(s0_axis_tdata);
            b_v := signed(s1_axis_tdata);
            case op_i is
              when OP_ADD =>
                sum_v := resize(a_v, DATA_WIDTH + 1) + resize(b_v, DATA_WIDTH + 1);
                out_data_r <= std_logic_vector(raddsp_sat_signed_vec(sum_v, DATA_WIDTH));
                out_last_r <= s0_axis_tlast or s1_axis_tlast;
                out_valid_r <= '1';
              when OP_SUBTRACT =>
                sum_v := resize(a_v, DATA_WIDTH + 1) - resize(b_v, DATA_WIDTH + 1);
                out_data_r <= std_logic_vector(raddsp_sat_signed_vec(sum_v, DATA_WIDTH));
                out_last_r <= s0_axis_tlast or s1_axis_tlast;
                out_valid_r <= '1';
              when OP_HADAMARD =>
                mul_a <= a_v;
                mul_b <= b_v;
                mul_valid <= '1';
                mul_last <= s0_axis_tlast or s1_axis_tlast;
                busy_r <= '1';
              when others =>
                out_data_r <= s0_axis_tdata;
                out_last_r <= s0_axis_tlast or s1_axis_tlast;
                out_valid_r <= '1';
            end case;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s0_axis_tready <= ready_i and s1_axis_tvalid;
    s1_axis_tready <= ready_i and s0_axis_tvalid;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable a_v       : signed(DATA_WIDTH - 1 downto 0);
      variable b_v       : signed(DATA_WIDTH - 1 downto 0);
      variable sum_v     : signed(DATA_WIDTH downto 0);
      variable product_v : signed((2 * DATA_WIDTH) - 1 downto 0);
      variable scaled_v  : signed((2 * DATA_WIDTH) - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        elsif ready_i = '1' then
          out_valid_r <= s0_axis_tvalid and s1_axis_tvalid;
          out_last_r <= s0_axis_tlast or s1_axis_tlast;
          if s0_axis_tvalid = '1' and s1_axis_tvalid = '1' then
            a_v := signed(s0_axis_tdata);
            b_v := signed(s1_axis_tdata);
            case op_i is
              when OP_ADD =>
                sum_v := resize(a_v, DATA_WIDTH + 1) + resize(b_v, DATA_WIDTH + 1);
                out_data_r <= std_logic_vector(raddsp_sat_signed_vec(sum_v, DATA_WIDTH));
              when OP_SUBTRACT =>
                sum_v := resize(a_v, DATA_WIDTH + 1) - resize(b_v, DATA_WIDTH + 1);
                out_data_r <= std_logic_vector(raddsp_sat_signed_vec(sum_v, DATA_WIDTH));
              when OP_HADAMARD =>
                product_v := a_v * b_v;
                scaled_v := shift_right(product_v, COEFF_FRAC_BITS);
                out_data_r <= std_logic_vector(raddsp_sat_signed_vec(scaled_v, DATA_WIDTH));
              when others =>
                out_data_r <= s0_axis_tdata;
            end case;
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
