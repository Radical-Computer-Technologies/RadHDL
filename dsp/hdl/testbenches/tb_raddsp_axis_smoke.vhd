library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library raddsp;

-- Self-checking or stimulus-focused testbench for axis smoke.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_smoke is
end entity;

architecture sim of tb_raddsp_axis_smoke is
  constant C_DATA_WIDTH  : positive := 16;
  constant C_COEFF_WIDTH : positive := 16;
  constant C_FRAC_BITS   : natural := 8;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal gain_coeff : std_logic_vector(C_COEFF_WIDTH - 1 downto 0) := std_logic_vector(to_signed(512, C_COEFF_WIDTH));
  signal gain_s_valid : std_logic := '0';
  signal gain_s_ready : std_logic;
  signal gain_s_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal gain_s_last  : std_logic := '0';
  signal gain_m_valid : std_logic;
  signal gain_m_ready : std_logic := '1';
  signal gain_m_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal gain_m_last  : std_logic;

  signal gain2_coeff : std_logic_vector((2 * C_COEFF_WIDTH) - 1 downto 0) :=
    std_logic_vector(to_signed(-256, C_COEFF_WIDTH)) &
    std_logic_vector(to_signed(512, C_COEFF_WIDTH));
  signal gain2_s_valid : std_logic := '0';
  signal gain2_s_ready : std_logic;
  signal gain2_s_data  : std_logic_vector((2 * C_DATA_WIDTH) - 1 downto 0) := (others => '0');
  signal gain2_s_last  : std_logic := '0';
  signal gain2_m_valid : std_logic;
  signal gain2_m_ready : std_logic := '1';
  signal gain2_m_data  : std_logic_vector((2 * C_DATA_WIDTH) - 1 downto 0);
  signal gain2_m_last  : std_logic;

  signal bq_b0 : std_logic_vector(C_COEFF_WIDTH - 1 downto 0) := std_logic_vector(to_signed(256, C_COEFF_WIDTH));
  signal bq_z  : std_logic_vector(C_COEFF_WIDTH - 1 downto 0) := (others => '0');
  signal bq_s_valid : std_logic := '0';
  signal bq_s_ready : std_logic;
  signal bq_s_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal bq_s_last  : std_logic := '0';
  signal bq_m_valid : std_logic;
  signal bq_m_ready : std_logic := '1';
  signal bq_m_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal bq_m_last  : std_logic;

  signal bq_seq_s_valid : std_logic := '0';
  signal bq_seq_s_ready : std_logic;
  signal bq_seq_s_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal bq_seq_s_last  : std_logic := '0';
  signal bq_seq_m_valid : std_logic;
  signal bq_seq_m_ready : std_logic := '1';
  signal bq_seq_m_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal bq_seq_m_last  : std_logic;

  signal lp_seq_s_valid : std_logic := '0';
  signal lp_seq_s_ready : std_logic;
  signal lp_seq_s_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal lp_seq_s_last  : std_logic := '0';
  signal lp_seq_m_valid : std_logic;
  signal lp_seq_m_ready : std_logic := '1';
  signal lp_seq_m_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal lp_seq_m_last  : std_logic;

  signal fir_taps : std_logic_vector((2 * C_COEFF_WIDTH) - 1 downto 0) :=
    std_logic_vector(to_signed(256, C_COEFF_WIDTH)) &
    std_logic_vector(to_signed(256, C_COEFF_WIDTH));
  signal fir_s_valid : std_logic := '0';
  signal fir_s_ready : std_logic;
  signal fir_s_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal fir_s_last  : std_logic := '0';
  signal fir_m_valid : std_logic;
  signal fir_m_ready : std_logic := '1';
  signal fir_m_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal fir_m_last  : std_logic;

  signal fir_seq_s_valid : std_logic := '0';
  signal fir_seq_s_ready : std_logic;
  signal fir_seq_s_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal fir_seq_s_last  : std_logic := '0';
  signal fir_seq_m_valid : std_logic;
  signal fir_seq_m_ready : std_logic := '1';
  signal fir_seq_m_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal fir_seq_m_last  : std_logic;

  signal mat_op : std_logic_vector(1 downto 0) := "00";
  signal mat_s0_valid : std_logic := '0';
  signal mat_s0_ready : std_logic;
  signal mat_s0_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal mat_s0_last  : std_logic := '0';
  signal mat_s1_valid : std_logic := '0';
  signal mat_s1_ready : std_logic;
  signal mat_s1_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal mat_s1_last  : std_logic := '0';
  signal mat_m_valid  : std_logic;
  signal mat_m_ready  : std_logic := '1';
  signal mat_m_data   : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal mat_m_last   : std_logic;

  signal dot_s0_valid : std_logic := '0';
  signal dot_s0_ready : std_logic;
  signal dot_s0_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal dot_s0_last  : std_logic := '0';
  signal dot_s1_valid : std_logic := '0';
  signal dot_s1_ready : std_logic;
  signal dot_s1_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal dot_s1_last  : std_logic := '0';
  signal dot_m_valid  : std_logic;
  signal dot_m_ready  : std_logic := '1';
  signal dot_m_data   : std_logic_vector(31 downto 0);
  signal dot_m_last   : std_logic;
  signal dot_count    : std_logic_vector(31 downto 0);

  procedure send_sample(
    signal valid : out std_logic;
    signal ready : in std_logic;
    signal data  : out std_logic_vector;
    signal last  : out std_logic;
    value        : integer;
    is_last      : std_logic
  ) is
  begin
    wait until rising_edge(clk);
    data <= std_logic_vector(to_signed(value, data'length));
    last <= is_last;
    valid <= '1';
    wait until rising_edge(clk) and ready = '1';
    valid <= '0';
    last <= '0';
  end procedure;

  procedure send_pair(
    signal v0 : out std_logic;
    signal r0 : in std_logic;
    signal d0 : out std_logic_vector;
    signal l0 : out std_logic;
    signal v1 : out std_logic;
    signal r1 : in std_logic;
    signal d1 : out std_logic_vector;
    signal l1 : out std_logic;
    value0    : integer;
    value1    : integer;
    is_last   : std_logic
  ) is
  begin
    wait until rising_edge(clk);
    d0 <= std_logic_vector(to_signed(value0, d0'length));
    d1 <= std_logic_vector(to_signed(value1, d1'length));
    l0 <= is_last;
    l1 <= is_last;
    v0 <= '1';
    v1 <= '1';
    wait until rising_edge(clk) and r0 = '1' and r1 = '1';
    v0 <= '0';
    v1 <= '0';
    l0 <= '0';
    l1 <= '0';
  end procedure;
begin
  clk <= not clk after 5 ns;

  gain_i: entity raddsp.raddsp_axis_gain
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      COEFF_WIDTH => C_COEFF_WIDTH,
      COEFF_FRAC_BITS => C_FRAC_BITS
    )
    port map (
      clk => clk,
      rst => rst,
      gain_i => gain_coeff,
      s_axis_tvalid => gain_s_valid,
      s_axis_tready => gain_s_ready,
      s_axis_tdata => gain_s_data,
      s_axis_tlast => gain_s_last,
      m_axis_tvalid => gain_m_valid,
      m_axis_tready => gain_m_ready,
      m_axis_tdata => gain_m_data,
      m_axis_tlast => gain_m_last
    );

  gain2_i: entity raddsp.raddsp_axis_gain
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      COEFF_WIDTH => C_COEFF_WIDTH,
      COEFF_FRAC_BITS => C_FRAC_BITS,
      CHANNEL_COUNT => 2
    )
    port map (
      clk => clk,
      rst => rst,
      gain_i => gain2_coeff,
      s_axis_tvalid => gain2_s_valid,
      s_axis_tready => gain2_s_ready,
      s_axis_tdata => gain2_s_data,
      s_axis_tlast => gain2_s_last,
      m_axis_tvalid => gain2_m_valid,
      m_axis_tready => gain2_m_ready,
      m_axis_tdata => gain2_m_data,
      m_axis_tlast => gain2_m_last
    );

  biquad_i: entity raddsp.raddsp_axis_biquad
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      COEFF_WIDTH => C_COEFF_WIDTH,
      COEFF_FRAC_BITS => C_FRAC_BITS
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => '0',
      b0_i => bq_b0,
      b1_i => bq_z,
      b2_i => bq_z,
      a1_i => bq_z,
      a2_i => bq_z,
      s_axis_tvalid => bq_s_valid,
      s_axis_tready => bq_s_ready,
      s_axis_tdata => bq_s_data,
      s_axis_tlast => bq_s_last,
      m_axis_tvalid => bq_m_valid,
      m_axis_tready => bq_m_ready,
      m_axis_tdata => bq_m_data,
      m_axis_tlast => bq_m_last
    );

  biquad_seq_i: entity raddsp.raddsp_axis_biquad
    generic map (
      DEVICE_FAMILY => "ultrascaleplus",
      DATA_WIDTH => C_DATA_WIDTH,
      COEFF_WIDTH => C_COEFF_WIDTH,
      COEFF_FRAC_BITS => C_FRAC_BITS,
      IMPLEMENTATION => "sequential_mac",
      DSP_LANES => 5
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => '0',
      b0_i => bq_b0,
      b1_i => bq_z,
      b2_i => bq_z,
      a1_i => bq_z,
      a2_i => bq_z,
      s_axis_tvalid => bq_seq_s_valid,
      s_axis_tready => bq_seq_s_ready,
      s_axis_tdata => bq_seq_s_data,
      s_axis_tlast => bq_seq_s_last,
      m_axis_tvalid => bq_seq_m_valid,
      m_axis_tready => bq_seq_m_ready,
      m_axis_tdata => bq_seq_m_data,
      m_axis_tlast => bq_seq_m_last
    );

  lowpass_seq_i: entity raddsp.raddsp_axis_one_pole_lowpass
    generic map (
      DEVICE_FAMILY => "ultrascaleplus",
      DATA_WIDTH => C_DATA_WIDTH,
      COEFF_WIDTH => C_COEFF_WIDTH,
      COEFF_FRAC_BITS => C_FRAC_BITS,
      IMPLEMENTATION => "sequential_mac"
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => '0',
      alpha_i => bq_b0,
      s_axis_tvalid => lp_seq_s_valid,
      s_axis_tready => lp_seq_s_ready,
      s_axis_tdata => lp_seq_s_data,
      s_axis_tlast => lp_seq_s_last,
      m_axis_tvalid => lp_seq_m_valid,
      m_axis_tready => lp_seq_m_ready,
      m_axis_tdata => lp_seq_m_data,
      m_axis_tlast => lp_seq_m_last
    );

  fir_i: entity raddsp.raddsp_axis_fir
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      TAP_WIDTH => C_COEFF_WIDTH,
      TAP_COUNT => 2,
      COEFF_FRAC_BITS => C_FRAC_BITS
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => '0',
      taps_i => fir_taps,
      s_axis_tvalid => fir_s_valid,
      s_axis_tready => fir_s_ready,
      s_axis_tdata => fir_s_data,
      s_axis_tlast => fir_s_last,
      m_axis_tvalid => fir_m_valid,
      m_axis_tready => fir_m_ready,
      m_axis_tdata => fir_m_data,
      m_axis_tlast => fir_m_last
    );

  fir_seq_i: entity raddsp.raddsp_axis_fir
    generic map (
      DEVICE_FAMILY => "ultrascaleplus",
      DATA_WIDTH => C_DATA_WIDTH,
      TAP_WIDTH => C_COEFF_WIDTH,
      TAP_COUNT => 2,
      COEFF_FRAC_BITS => C_FRAC_BITS,
      IMPLEMENTATION => "sequential_mac",
      DSP_LANES => 2
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => '0',
      taps_i => fir_taps,
      s_axis_tvalid => fir_seq_s_valid,
      s_axis_tready => fir_seq_s_ready,
      s_axis_tdata => fir_seq_s_data,
      s_axis_tlast => fir_seq_s_last,
      m_axis_tvalid => fir_seq_m_valid,
      m_axis_tready => fir_seq_m_ready,
      m_axis_tdata => fir_seq_m_data,
      m_axis_tlast => fir_seq_m_last
    );

  matrix_elementwise_i: entity raddsp.raddsp_axis_matrix_elementwise
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      COEFF_FRAC_BITS => C_FRAC_BITS
    )
    port map (
      clk => clk,
      rst => rst,
      op_i => mat_op,
      s0_axis_tvalid => mat_s0_valid,
      s0_axis_tready => mat_s0_ready,
      s0_axis_tdata => mat_s0_data,
      s0_axis_tlast => mat_s0_last,
      s1_axis_tvalid => mat_s1_valid,
      s1_axis_tready => mat_s1_ready,
      s1_axis_tdata => mat_s1_data,
      s1_axis_tlast => mat_s1_last,
      m_axis_tvalid => mat_m_valid,
      m_axis_tready => mat_m_ready,
      m_axis_tdata => mat_m_data,
      m_axis_tlast => mat_m_last
    );

  matrix_dot_i: entity raddsp.raddsp_axis_matrix_dot
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      ACC_WIDTH => 32,
      COEFF_FRAC_BITS => 0
    )
    port map (
      clk => clk,
      rst => rst,
      clear_i => '0',
      s0_axis_tvalid => dot_s0_valid,
      s0_axis_tready => dot_s0_ready,
      s0_axis_tdata => dot_s0_data,
      s0_axis_tlast => dot_s0_last,
      s1_axis_tvalid => dot_s1_valid,
      s1_axis_tready => dot_s1_ready,
      s1_axis_tdata => dot_s1_data,
      s1_axis_tlast => dot_s1_last,
      m_axis_tvalid => dot_m_valid,
      m_axis_tready => dot_m_ready,
      m_axis_tdata => dot_m_data,
      m_axis_tlast => dot_m_last,
      sample_count_o => dot_count
    );

  process
  begin
    wait for 50 ns;
    wait until rising_edge(clk);
    rst <= '0';

    send_sample(gain_s_valid, gain_s_ready, gain_s_data, gain_s_last, 100, '1');
    wait until rising_edge(clk) and gain_m_valid = '1';
    assert to_integer(signed(gain_m_data)) = 200 report "gain output mismatch" severity failure;
    assert gain_m_last = '1' report "gain tlast mismatch" severity failure;

    wait until rising_edge(clk);
    gain2_s_data <= std_logic_vector(to_signed(-30, C_DATA_WIDTH)) &
                    std_logic_vector(to_signed(50, C_DATA_WIDTH));
    gain2_s_last <= '1';
    gain2_s_valid <= '1';
    wait until rising_edge(clk) and gain2_s_ready = '1';
    gain2_s_valid <= '0';
    gain2_s_last <= '0';
    wait until rising_edge(clk) and gain2_m_valid = '1';
    assert to_integer(signed(gain2_m_data(C_DATA_WIDTH - 1 downto 0))) = 100
      report "gain channel 0 output mismatch" severity failure;
    assert to_integer(signed(gain2_m_data((2 * C_DATA_WIDTH) - 1 downto C_DATA_WIDTH))) = 30
      report "gain channel 1 output mismatch" severity failure;
    assert gain2_m_last = '1' report "gain channelized tlast mismatch" severity failure;

    send_sample(bq_s_valid, bq_s_ready, bq_s_data, bq_s_last, -123, '1');
    wait until rising_edge(clk) and bq_m_valid = '1';
    assert to_integer(signed(bq_m_data)) = -123 report "biquad identity output mismatch" severity failure;
    assert bq_m_last = '1' report "biquad tlast mismatch" severity failure;

    send_sample(bq_seq_s_valid, bq_seq_s_ready, bq_seq_s_data, bq_seq_s_last, 77, '1');
    wait until rising_edge(clk) and bq_seq_m_valid = '1';
    assert to_integer(signed(bq_seq_m_data)) = 77 report "sequential dsp48 biquad identity output mismatch" severity failure;
    assert bq_seq_m_last = '1' report "sequential dsp48 biquad tlast mismatch" severity failure;

    send_sample(lp_seq_s_valid, lp_seq_s_ready, lp_seq_s_data, lp_seq_s_last, 55, '1');
    wait until rising_edge(clk) and lp_seq_m_valid = '1';
    assert to_integer(signed(lp_seq_m_data)) = 55 report "sequential dsp48 lowpass output mismatch" severity failure;
    assert lp_seq_m_last = '1' report "sequential dsp48 lowpass tlast mismatch" severity failure;

    send_sample(fir_s_valid, fir_s_ready, fir_s_data, fir_s_last, 10, '0');
    wait until rising_edge(clk) and fir_m_valid = '1';
    assert to_integer(signed(fir_m_data)) = 10 report "fir first output mismatch" severity failure;

    send_sample(fir_s_valid, fir_s_ready, fir_s_data, fir_s_last, 20, '1');
    wait until rising_edge(clk) and fir_m_valid = '1';
    assert to_integer(signed(fir_m_data)) = 30 report "fir second output mismatch" severity failure;
    assert fir_m_last = '1' report "fir tlast mismatch" severity failure;

    send_sample(fir_seq_s_valid, fir_seq_s_ready, fir_seq_s_data, fir_seq_s_last, 10, '0');
    wait until rising_edge(clk) and fir_seq_m_valid = '1';
    assert to_integer(signed(fir_seq_m_data)) = 10 report "sequential dsp48 fir first output mismatch" severity failure;

    send_sample(fir_seq_s_valid, fir_seq_s_ready, fir_seq_s_data, fir_seq_s_last, 20, '1');
    wait until rising_edge(clk) and fir_seq_m_valid = '1';
    assert to_integer(signed(fir_seq_m_data)) = 30 report "sequential dsp48 fir second output mismatch" severity failure;
    assert fir_seq_m_last = '1' report "sequential dsp48 fir tlast mismatch" severity failure;

    mat_op <= "00";
    send_pair(mat_s0_valid, mat_s0_ready, mat_s0_data, mat_s0_last,
              mat_s1_valid, mat_s1_ready, mat_s1_data, mat_s1_last,
              100, 23, '1');
    wait until rising_edge(clk) and mat_m_valid = '1';
    assert to_integer(signed(mat_m_data)) = 123 report "matrix add output mismatch" severity failure;
    assert mat_m_last = '1' report "matrix add tlast mismatch" severity failure;

    mat_op <= "10";
    send_pair(mat_s0_valid, mat_s0_ready, mat_s0_data, mat_s0_last,
              mat_s1_valid, mat_s1_ready, mat_s1_data, mat_s1_last,
              512, 512, '1');
    wait until rising_edge(clk) and mat_m_valid = '1';
    assert to_integer(signed(mat_m_data)) = 1024 report "matrix hadamard output mismatch" severity failure;

    send_pair(dot_s0_valid, dot_s0_ready, dot_s0_data, dot_s0_last,
              dot_s1_valid, dot_s1_ready, dot_s1_data, dot_s1_last,
              2, 5, '0');
    send_pair(dot_s0_valid, dot_s0_ready, dot_s0_data, dot_s0_last,
              dot_s1_valid, dot_s1_ready, dot_s1_data, dot_s1_last,
              3, 7, '1');
    wait until rising_edge(clk) and dot_m_valid = '1';
    assert to_integer(signed(dot_m_data)) = 31 report "matrix dot output mismatch" severity failure;
    assert dot_m_last = '1' report "matrix dot tlast mismatch" severity failure;

    report "PASS raddsp_axis_smoke";
    finish;
  end process;
end architecture;
