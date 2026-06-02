library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library raddsp;

use work.iqcal_capture_pkg.all;

entity tb_zc_chirp_frame_detector_iqcal is
end entity;

architecture sim of tb_zc_chirp_frame_detector_iqcal is
  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal frame_start  : std_logic := '0';
  signal sample_valid : std_logic := '0';
  signal sample_i     : signed(15 downto 0) := (others => '0');
  signal sample_q     : signed(15 downto 0) := (others => '0');
  signal sample_ready : std_logic;
  signal processing   : std_logic;
  signal peak_valid   : std_logic;
  signal peak_index   : integer range 0 to IQCAL_FRAME_LEN - 1;
  signal peak_i       : signed(39 downto 0);
  signal peak_q       : signed(39 downto 0);
  signal chirp_valid  : std_logic;
  signal chirp_index  : integer range 0 to IQCAL_CHIRP_LEN - 1;
  signal chirp_i      : signed(15 downto 0);
  signal chirp_q      : signed(15 downto 0);
  signal chirp_done   : std_logic;
begin
  clk <= not clk after 5 ns;

  dut: entity raddsp.zc_chirp_frame_detector
    generic map (
      G_SAMPLE_WIDTH => 16,
      G_ACC_WIDTH => 40,
      G_FRAME_SAMPLES => IQCAL_FRAME_LEN,
      G_CHIRP_LEN => IQCAL_CHIRP_LEN,
      G_CHIRP_AFTER_PEAK => 160,
      G_PRODUCT_SHIFT => 15
    )
    port map (
      clk => clk, rst => rst, frame_start => frame_start,
      sample_valid => sample_valid, sample_i => sample_i, sample_q => sample_q,
      sample_ready => sample_ready, processing => processing,
      peak_valid => peak_valid, peak_index => peak_index, peak_i => peak_i, peak_q => peak_q,
      chirp_valid => chirp_valid, chirp_index => chirp_index, chirp_i => chirp_i, chirp_q => chirp_q,
      chirp_done => chirp_done
    );

  process
    variable seen_chirp : integer := 0;
  begin
    wait for 50 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    frame_start <= '1';
    for n in 0 to IQCAL_FRAME_LEN - 1 loop
      wait until rising_edge(clk);
      assert sample_ready = '1' report "input dropped during IQCAL frame capture" severity failure;
      frame_start <= '0';
      sample_valid <= '1';
      sample_i <= to_signed(IQCAL_FRAME_I(n), 16);
      sample_q <= to_signed(IQCAL_FRAME_Q(n), 16);
    end loop;
    wait until rising_edge(clk);
    sample_valid <= '0';

    wait until peak_valid = '1';
    assert peak_index = IQCAL_EXPECT_PEAK
      report "IQCAL ZC peak index mismatch" severity failure;

    while chirp_done = '0' loop
      wait until rising_edge(clk);
      if chirp_valid = '1' then
        assert to_integer(chirp_i) = IQCAL_CHIRP_I(chirp_index) and
               to_integer(chirp_q) = IQCAL_CHIRP_Q(chirp_index)
          report "IQCAL chirp replay mismatch at index " & integer'image(chirp_index) &
                 " got (" & integer'image(to_integer(chirp_i)) & "," &
                 integer'image(to_integer(chirp_q)) & ") expected (" &
                 integer'image(IQCAL_CHIRP_I(chirp_index)) & "," &
                 integer'image(IQCAL_CHIRP_Q(chirp_index)) & ")"
          severity failure;
        seen_chirp := seen_chirp + 1;
      end if;
    end loop;

    assert seen_chirp = IQCAL_CHIRP_LEN
      report "IQCAL chirp length mismatch" severity failure;
    report "PASS zc_chirp_frame_detector_iqcal";
    finish;
  end process;
end architecture;
