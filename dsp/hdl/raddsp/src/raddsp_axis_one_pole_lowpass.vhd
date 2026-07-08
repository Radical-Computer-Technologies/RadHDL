library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- AXI-stream one-pole low-pass filter.
-- Implements a lightweight recursive smoothing stage for control, envelope, and slowly varying DSP signals.
entity raddsp_axis_one_pole_lowpass is
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
    IMPLEMENTATION  : string  := "parallel"
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst           : in  std_logic;
    -- Input clear i signal for this module.
    clear_i       : in  std_logic;
    -- Input alpha i signal for this module.
    alpha_i       : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
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

architecture rtl of raddsp_axis_one_pole_lowpass is
  constant C_DELTA_WIDTH : positive := DATA_WIDTH + 1;
  constant C_ACC_WIDTH   : positive := 48;
begin
  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
  begin
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
  begin
  end generate;

  gen_parallel : if IMPLEMENTATION /= "sequential_mac" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal y_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable x_v      : signed(DATA_WIDTH - 1 downto 0);
      variable delta_v  : signed(DATA_WIDTH downto 0);
      variable prod_v   : signed(DATA_WIDTH + COEFF_WIDTH + 1 downto 0);
      variable step_v   : signed(DATA_WIDTH + COEFF_WIDTH + 1 downto 0);
      variable next_int : integer;
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          y_r <= (others => '0');
        else
          if clear_i = '1' then
            y_r <= (others => '0');
          end if;

          if ready_i = '1' then
            out_valid_r <= s_axis_tvalid;
            out_last_r <= s_axis_tlast;
            if s_axis_tvalid = '1' then
              x_v := signed(s_axis_tdata);
              delta_v := resize(x_v, DATA_WIDTH + 1) - resize(y_r, DATA_WIDTH + 1);
              prod_v := delta_v * signed('0' & alpha_i);
              step_v := shift_right(prod_v, COEFF_FRAC_BITS);
              next_int := to_integer(y_r) + to_integer(step_v);
              y_r <= raddsp_sat_signed(next_int, DATA_WIDTH);
              out_data_r <= std_logic_vector(raddsp_sat_signed(next_int, DATA_WIDTH));
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_sequential_mac_xilinx : if IMPLEMENTATION = "sequential_mac" and (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    type state_t is (ST_IDLE, ST_WAIT_PRODUCT);

    signal state_r      : state_t := ST_IDLE;
    signal out_valid_r  : std_logic := '0';
    signal out_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r   : std_logic := '0';
    signal y_r          : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal last_work_r  : std_logic := '0';
    signal ready_i      : std_logic;
    signal mul_valid    : std_logic := '0';
    signal mul_a        : signed(C_DELTA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_b        : signed(COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal mul_p        : signed(47 downto 0);
    signal mul_p_valid  : std_logic;
    signal unused_sub   : std_logic;
    signal unused_last  : std_logic;
  begin
    ready_i <= '1' when state_r = ST_IDLE and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    dsp_mul_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => C_DELTA_WIDTH,
        B_WIDTH => COEFF_WIDTH
      )
      port map (
        clk => clk,
        rst => rst,
        valid_i => mul_valid,
        subtract_i => '0',
        last_i => '0',
        a_i => mul_a,
        b_i => mul_b,
        valid_o => mul_p_valid,
        subtract_o => unused_sub,
        last_o => unused_last,
        p_o => mul_p
      );

    process(clk)
      variable x_v      : signed(DATA_WIDTH - 1 downto 0);
      variable delta_v  : signed(C_DELTA_WIDTH - 1 downto 0);
      variable step_v   : signed(C_ACC_WIDTH - 1 downto 0);
      variable next_v   : signed(C_ACC_WIDTH - 1 downto 0);
      variable y_next_v : signed(DATA_WIDTH - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          state_r <= ST_IDLE;
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          y_r <= (others => '0');
          last_work_r <= '0';
          mul_valid <= '0';
          mul_a <= (others => '0');
          mul_b <= (others => '0');
        else
          mul_valid <= '0';

          if clear_i = '1' then
            state_r <= ST_IDLE;
            out_valid_r <= '0';
            out_data_r <= (others => '0');
            out_last_r <= '0';
            y_r <= (others => '0');
            last_work_r <= '0';
          else
            if out_valid_r = '1' and m_axis_tready = '1' then
              out_valid_r <= '0';
            end if;

            case state_r is
              when ST_IDLE =>
                if s_axis_tvalid = '1' and ready_i = '1' then
                  x_v := signed(s_axis_tdata);
                  delta_v := resize(x_v, C_DELTA_WIDTH) - resize(y_r, C_DELTA_WIDTH);
                  mul_valid <= '1';
                  mul_a <= delta_v;
                  mul_b <= signed(alpha_i);
                  last_work_r <= s_axis_tlast;
                  state_r <= ST_WAIT_PRODUCT;
                end if;

              when ST_WAIT_PRODUCT =>
                if mul_p_valid = '1' then
                  step_v := shift_right(resize(mul_p, C_ACC_WIDTH), COEFF_FRAC_BITS);
                  next_v := resize(y_r, C_ACC_WIDTH) + step_v;
                  y_next_v := raddsp_sat_signed_vec(next_v, DATA_WIDTH);
                  y_r <= y_next_v;
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

  gen_sequential_mac_rtl : if IMPLEMENTATION = "sequential_mac" and not (VENDOR = "xilinx" or VENDOR = "XILINX") generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal y_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable x_v      : signed(DATA_WIDTH - 1 downto 0);
      variable delta_v  : signed(DATA_WIDTH downto 0);
      variable prod_v   : signed(DATA_WIDTH + COEFF_WIDTH + 1 downto 0);
      variable step_v   : signed(DATA_WIDTH + COEFF_WIDTH + 1 downto 0);
      variable next_int : integer;
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          y_r <= (others => '0');
        else
          if clear_i = '1' then
            y_r <= (others => '0');
          end if;

          if ready_i = '1' then
            out_valid_r <= s_axis_tvalid;
            out_last_r <= s_axis_tlast;
            if s_axis_tvalid = '1' then
              x_v := signed(s_axis_tdata);
              delta_v := resize(x_v, DATA_WIDTH + 1) - resize(y_r, DATA_WIDTH + 1);
              prod_v := delta_v * signed('0' & alpha_i);
              step_v := shift_right(prod_v, COEFF_FRAC_BITS);
              next_int := to_integer(y_r) + to_integer(step_v);
              y_r <= raddsp_sat_signed(next_int, DATA_WIDTH);
              out_data_r <= std_logic_vector(raddsp_sat_signed(next_int, DATA_WIDTH));
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
