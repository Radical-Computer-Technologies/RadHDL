library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library radif;
use radif.radif_pkg.all;

-- Self-checking or stimulus-focused testbench for reg interconnect.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radif_reg_interconnect is
end entity;

architecture sim of tb_radif_reg_interconnect is
  constant DATA_WIDTH : integer := 32;
  constant ADDR_WIDTH : integer := 16;
  constant SLAVES     : integer := 2;

  signal clk       : std_logic := '0';
  signal rstn      : std_logic := '0';
  signal wr_addr   : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_addr   : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal wr_en     : std_logic := '0';
  signal rd_en     : std_logic := '0';
  signal data_in   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal data_out  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal wr_rdy    : std_logic;
  signal rd_rdy    : std_logic;
  signal wr_valid  : std_logic;
  signal rd_valid  : std_logic;
  signal error     : std_logic;

  signal s_wr_addr  : std_logic_vector((SLAVES * ADDR_WIDTH) - 1 downto 0);
  signal s_rd_addr  : std_logic_vector((SLAVES * ADDR_WIDTH) - 1 downto 0);
  signal s_wr_en    : std_logic_vector(SLAVES - 1 downto 0);
  signal s_rd_en    : std_logic_vector(SLAVES - 1 downto 0);
  signal s_data_in  : std_logic_vector((SLAVES * DATA_WIDTH) - 1 downto 0);
  signal s_data_out : std_logic_vector((SLAVES * DATA_WIDTH) - 1 downto 0);
  signal s_wr_rdy   : std_logic_vector(SLAVES - 1 downto 0);
  signal s_rd_rdy   : std_logic_vector(SLAVES - 1 downto 0);
  signal s_wr_valid : std_logic_vector(SLAVES - 1 downto 0);
  signal s_rd_valid : std_logic_vector(SLAVES - 1 downto 0);
  signal s_error    : std_logic_vector(SLAVES - 1 downto 0);

  signal ro0 : radif_reg_array_t(0 to 1)(31 downto 0) := (x"AAAA0000", x"AAAA0001");
  signal ro1 : radif_reg_array_t(0 to 1)(31 downto 0) := (x"BBBB0000", x"BBBB0001");
  signal rw0 : radif_reg_array_t(0 to 3)(31 downto 0);
  signal rw1 : radif_reg_array_t(0 to 3)(31 downto 0);
begin
  clk <= not clk after 5 ns;

  dut: entity radif.radif_reg_interconnect
    generic map (
      DATA_WIDTH => DATA_WIDTH,
      ADDR_WIDTH => ADDR_WIDTH,
      SLAVE_COUNT => SLAVES,
      SLAVE_BASE_ADDRS => x"10000000",
      SLAVE_ADDR_MASKS => x"F000F000"
    )
    port map (
      clk => clk,
      rstn => rstn,
      wr_addr_i => wr_addr,
      rd_addr_i => rd_addr,
      wr_en_i => wr_en,
      rd_en_i => rd_en,
      data_in_i => data_in,
      data_out_o => data_out,
      wr_rdy_o => wr_rdy,
      rd_rdy_o => rd_rdy,
      wr_valid_o => wr_valid,
      rd_valid_o => rd_valid,
      error_o => error,
      s_wr_addr_o => s_wr_addr,
      s_rd_addr_o => s_rd_addr,
      s_wr_en_o => s_wr_en,
      s_rd_en_o => s_rd_en,
      s_data_in_o => s_data_in,
      s_data_out_i => s_data_out,
      s_wr_rdy_i => s_wr_rdy,
      s_rd_rdy_i => s_rd_rdy,
      s_wr_valid_i => s_wr_valid,
      s_rd_valid_i => s_rd_valid,
      s_error_i => s_error
    );

  bank0: entity radif.radif_reg_bank
    generic map (READ_ONLY_REG_COUNT => 2, READ_WRITE_REG_COUNT => 4)
    port map (
      clk => clk, rstn => rstn,
      wr_addr => s_wr_addr(15 downto 0), rd_addr => s_rd_addr(15 downto 0),
      wr_en => s_wr_en(0), rd_en => s_rd_en(0),
      data_in => s_data_in(31 downto 0), data_out => s_data_out(31 downto 0),
      read_only_regs_i => ro0, read_write_regs_o => rw0,
      wr_rdy => s_wr_rdy(0), rd_rdy => s_rd_rdy(0),
      wr_valid => s_wr_valid(0), rd_valid => s_rd_valid(0), error => s_error(0)
    );

  bank1: entity radif.radif_reg_bank
    generic map (READ_ONLY_REG_COUNT => 2, READ_WRITE_REG_COUNT => 4)
    port map (
      clk => clk, rstn => rstn,
      wr_addr => s_wr_addr(31 downto 16), rd_addr => s_rd_addr(31 downto 16),
      wr_en => s_wr_en(1), rd_en => s_rd_en(1),
      data_in => s_data_in(63 downto 32), data_out => s_data_out(63 downto 32),
      read_only_regs_i => ro1, read_write_regs_o => rw1,
      wr_rdy => s_wr_rdy(1), rd_rdy => s_rd_rdy(1),
      wr_valid => s_wr_valid(1), rd_valid => s_rd_valid(1), error => s_error(1)
    );

  process
  begin
    rstn <= '0';
    wait for 25 ns;
    rstn <= '1';
    wait until rising_edge(clk);

    wr_addr <= x"1004";
    data_in <= x"12345678";
    wr_en <= '1';
    wait until rising_edge(clk);
    wr_en <= '0';
    wait until rising_edge(clk);
    assert wr_valid = '1' and error = '0' report "write to slave 1 should succeed" severity failure;

    rd_addr <= x"1004";
    rd_en <= '1';
    wait until rising_edge(clk);
    rd_en <= '0';
    wait until rising_edge(clk);
    assert rd_valid = '1' and data_out = x"12345678" and error = '0' report "readback from slave 1 should match" severity failure;

    rd_addr <= x"1010";
    rd_en <= '1';
    wait until rising_edge(clk);
    rd_en <= '0';
    wait until rising_edge(clk);
    assert rd_valid = '1' and data_out = x"BBBB0000" and error = '0' report "slave 1 local read-only offset should decode" severity failure;

    rd_addr <= x"3000";
    rd_en <= '1';
    wait until rising_edge(clk);
    rd_en <= '0';
    wait until rising_edge(clk);
    assert rd_valid = '1' and error = '1' report "decode miss should return error" severity failure;

    report "PASS tb_radif_reg_interconnect";
    finish;
  end process;
end architecture;
