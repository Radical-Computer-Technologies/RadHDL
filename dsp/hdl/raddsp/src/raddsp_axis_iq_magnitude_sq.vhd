library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


-- AXI-stream complex magnitude-squared stage for IQ samples.
-- Computes I*I plus Q*Q energy values for detection, normalization, and spectral analysis pipelines.
entity raddsp_axis_iq_magnitude_sq is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR        : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH    : positive := 16;
    -- Sets the bit width for MAG WIDTH values carried by this module.
    MAG_WIDTH     : positive := 32
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst           : in  std_logic;
    -- Input AXI-stream valid qualifier for the current sample beat.
    s_axis_tvalid : in  std_logic;
    -- Input AXI-stream ready response indicating this block can accept a beat.
    s_axis_tready : out std_logic;
    -- Input AXI-stream payload containing packed sample or feature lanes.
    s_axis_tdata  : in  std_logic_vector((2 * DATA_WIDTH) - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector(MAG_WIDTH - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_iq_magnitude_sq is
begin
  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(MAG_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal busy_r      : std_logic := '0';
    signal ready_i     : std_logic;
    signal i_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal q_r         : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal mul_valid   : std_logic := '0';
    signal mul_last    : std_logic := '0';
    signal ii_p        : signed(47 downto 0);
    signal qq_p        : signed(47 downto 0);
    signal ii_valid    : std_logic;
    signal qq_valid    : std_logic;
    signal ii_last     : std_logic;
    signal qq_last     : std_logic;
    signal unused_sub0 : std_logic;
    signal unused_sub1 : std_logic;
  begin
    assert DATA_WIDTH <= 18
      report "DSP48 IQ magnitude square supports DATA_WIDTH <= 18"
      severity failure;

    ready_i <= '1' when busy_r = '0' and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    i_square_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => DATA_WIDTH,
        B_WIDTH => DATA_WIDTH
      )
      port map (
        clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => mul_last,
        a_i => i_r, b_i => i_r,
        valid_o => ii_valid, subtract_o => unused_sub0, last_o => ii_last, p_o => ii_p
      );

    q_square_i: entity work.raddsp_xilinx_dsp48_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => DATA_WIDTH,
        B_WIDTH => DATA_WIDTH
      )
      port map (
        clk => clk, rst => rst, valid_i => mul_valid, subtract_i => '0', last_i => mul_last,
        a_i => q_r, b_i => q_r,
        valid_o => qq_valid, subtract_o => unused_sub1, last_o => qq_last, p_o => qq_p
      );

    process(clk)
      variable sum_v : unsigned(48 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          busy_r <= '0';
          i_r <= (others => '0');
          q_r <= (others => '0');
          mul_valid <= '0';
          mul_last <= '0';
        else
          mul_valid <= '0';
          mul_last <= '0';

          if out_valid_r = '1' and m_axis_tready = '1' then
            out_valid_r <= '0';
          end if;

          if ii_valid = '1' and qq_valid = '1' then
            sum_v := resize(unsigned(ii_p), sum_v'length) + resize(unsigned(qq_p), sum_v'length);
            out_data_r <= std_logic_vector(resize(sum_v, MAG_WIDTH));
            out_last_r <= ii_last or qq_last;
            out_valid_r <= '1';
            busy_r <= '0';
          end if;

          if s_axis_tvalid = '1' and ready_i = '1' then
            i_r <= signed(s_axis_tdata((2 * DATA_WIDTH) - 1 downto DATA_WIDTH));
            q_r <= signed(s_axis_tdata(DATA_WIDTH - 1 downto 0));
            mul_valid <= '1';
            mul_last <= s_axis_tlast;
            busy_r <= '1';
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector(MAG_WIDTH - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable i_v   : signed(DATA_WIDTH - 1 downto 0);
      variable q_v   : signed(DATA_WIDTH - 1 downto 0);
      variable ii_v  : signed((2 * DATA_WIDTH) - 1 downto 0);
      variable qq_v  : signed((2 * DATA_WIDTH) - 1 downto 0);
      variable sum_v : unsigned((2 * DATA_WIDTH) downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        elsif ready_i = '1' then
          out_valid_r <= s_axis_tvalid;
          out_last_r <= s_axis_tlast;
          if s_axis_tvalid = '1' then
            i_v := signed(s_axis_tdata((2 * DATA_WIDTH) - 1 downto DATA_WIDTH));
            q_v := signed(s_axis_tdata(DATA_WIDTH - 1 downto 0));
            ii_v := i_v * i_v;
            qq_v := q_v * q_v;
            sum_v := resize(unsigned(ii_v), sum_v'length) + resize(unsigned(qq_v), sum_v'length);
            out_data_r <= std_logic_vector(resize(sum_v, MAG_WIDTH));
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
