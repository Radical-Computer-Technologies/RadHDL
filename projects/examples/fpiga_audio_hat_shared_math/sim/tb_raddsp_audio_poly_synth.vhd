library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.fpiga_audio_hat_tb_pkg.all;

entity tb_raddsp_audio_poly_synth is
end entity;

architecture sim of tb_raddsp_audio_poly_synth is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal sample_ce : std_logic := '0';
  signal cfg_wr_en : std_logic := '0';
  signal cfg_addr  : std_logic_vector(7 downto 0) := (others => '0');
  signal cfg_data  : std_logic_vector(31 downto 0) := (others => '0');
  signal cfg_rd_en : std_logic := '0';
  signal cfg_rd_addr : std_logic_vector(7 downto 0) := (others => '0');
  signal cfg_rd_data : std_logic_vector(31 downto 0);
  signal cfg_rd_valid : std_logic;
  signal cfg_error : std_logic;
  signal sample    : std_logic_vector(23 downto 0);
  signal valid     : std_logic;
  signal init_done : std_logic;
  signal busy      : std_logic;
begin
  clk <= not clk after 5 ns;

  dut : entity work.raddsp_audio_poly_synth
    generic map (
      VOICE_COUNT => 16,
      SAMPLE_WIDTH => 24,
      WAVE_WIDTH => 16,
      PHASE_WIDTH => 24,
      TABLE_ADDR_WIDTH => 8,
      COEFF_WIDTH => 18,
      COEFF_FRAC_BITS => 15,
      RESET_CONFIG_REGS => false
    )
    port map (
      clk => clk,
      rst => rst,
      sample_ce_i => sample_ce,
      cfg_wr_en_i => cfg_wr_en,
      cfg_addr_i => cfg_addr,
      cfg_data_i => cfg_data,
      cfg_rd_en_i => cfg_rd_en,
      cfg_rd_addr_i => cfg_rd_addr,
      cfg_data_o => cfg_rd_data,
      cfg_rd_valid_o => cfg_rd_valid,
      cfg_error_o => cfg_error,
      table_wr_en_i => '0',
      table_wr_addr_i => (others => '0'),
      table_wr_data_i => (others => '0'),
      sample_o => sample,
      valid_o => valid,
      table_init_done_o => init_done,
      busy_o => busy
    );

  process
    variable nonzero_seen : boolean := false;

    procedure cfg_write(addr : std_logic_vector(7 downto 0); data : std_logic_vector(31 downto 0)) is
    begin
      cfg_addr <= addr;
      cfg_data <= data;
      cfg_wr_en <= '1';
      wait until rising_edge(clk);
      cfg_wr_en <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure cfg_read(addr : std_logic_vector(7 downto 0); variable data : out std_logic_vector(31 downto 0)) is
    begin
      cfg_rd_addr <= addr;
      cfg_rd_en <= '1';
      wait until rising_edge(clk);
      cfg_rd_en <= '0';
      while cfg_rd_valid = '0' loop
        wait until rising_edge(clk);
      end loop;
      assert cfg_error = '0' report "poly config read returned error" severity failure;
      data := cfg_rd_data;
      wait until rising_edge(clk);
    end procedure;

    variable rb : std_logic_vector(31 downto 0);
  begin
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait until init_done = '1';
    wait until rising_edge(clk);

    cfg_write(x"00", x"00" & phase_inc(659.25));
    cfg_write(x"20", x"FFFFFFFF");
    cfg_write(x"30", x"01FFFFFF");
    cfg_write(x"10", x"00000003");

    cfg_read(x"00", rb);
    assert rb = (x"00" & phase_inc(659.25))
      report "standalone POLY_FREQ0 readback mismatch actual=0x" & to_hstring(rb)
      severity failure;
    cfg_read(x"20", rb);
    assert rb = x"FFFFFFFF"
      report "standalone POLY_VOLUME0 readback mismatch actual=0x" & to_hstring(rb)
      severity failure;
    cfg_read(x"30", rb);
    assert rb = x"01FFFFFF"
      report "standalone POLY_ADSR0 readback mismatch actual=0x" & to_hstring(rb)
      severity failure;
    cfg_read(x"10", rb);
    assert rb = x"00000003"
      report "standalone POLY_CTRL0 readback mismatch actual=0x" & to_hstring(rb)
      severity failure;

    for i in 0 to 63 loop
      sample_ce <= '1';
      wait until rising_edge(clk);
      sample_ce <= '0';
      while valid = '0' loop
        wait until rising_edge(clk);
      end loop;
      if sample /= x"000000" then
        nonzero_seen := true;
      end if;
      wait until rising_edge(clk);
    end loop;

    assert nonzero_seen
      report "Standalone poly synth stayed zero"
      severity failure;
    report "Standalone poly synth produced nonzero output";
    finish;
  end process;
end architecture;
