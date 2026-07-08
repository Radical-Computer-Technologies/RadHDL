library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library radif;
use radif.radif_pkg.all;

-- Self-checking or stimulus-focused testbench for reg bank.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radif_reg_bank is
end entity;

architecture sim of tb_radif_reg_bank is
  signal clk      : std_logic := '0';
  signal rstn     : std_logic := '0';
  signal wr_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal rd_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal wr_en    : std_logic := '0';
  signal rd_en    : std_logic := '0';
  signal din      : std_logic_vector(31 downto 0) := (others => '0');
  signal dout     : std_logic_vector(31 downto 0);
  signal wr_rdy   : std_logic;
  signal rd_rdy   : std_logic;
  signal wr_valid : std_logic;
  signal rd_valid : std_logic;
  signal error    : std_logic;
  signal ro_regs  : radif_reg_array_t(0 to 1)(31 downto 0) := (
    0 => x"A5A50001",
    1 => x"A5A50002"
  );
  signal rw_regs  : radif_reg_array_t(0 to 3)(31 downto 0);
begin
  clk <= not clk after 5 ns;

  u_dut : entity radif.radif_reg_bank
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      READ_ONLY_REG_COUNT => 2,
      READ_WRITE_REG_COUNT => 4
    )
    port map (
      clk => clk,
      rstn => rstn,
      wr_addr => wr_addr,
      rd_addr => rd_addr,
      wr_en => wr_en,
      rd_en => rd_en,
      data_in => din,
      data_out => dout,
      read_only_regs_i => ro_regs,
      read_write_regs_o => rw_regs,
      wr_rdy => wr_rdy,
      rd_rdy => rd_rdy,
      wr_valid => wr_valid,
      rd_valid => rd_valid,
      error => error
    );

  process
  begin
    wait for 40 ns;
    rstn <= '1';
    wait until rising_edge(clk);

    wr_addr <= x"0008";
    din <= x"12345678";
    wr_en <= '1';
    wait until rising_edge(clk);
    wr_en <= '0';
    wait until rising_edge(clk);
    assert wr_valid = '1' and error = '0' report "register write failed" severity failure;
    assert rw_regs(2) = x"12345678" report "read/write output port did not update" severity failure;

    rd_addr <= x"0008";
    rd_en <= '1';
    wait until rising_edge(clk);
    rd_en <= '0';
    wait until rising_edge(clk);
    assert rd_valid = '1' and dout = x"12345678" and error = '0' report "register read failed" severity failure;

    rd_addr <= x"0010";
    rd_en <= '1';
    wait until rising_edge(clk);
    rd_en <= '0';
    wait until rising_edge(clk);
    assert rd_valid = '1' and dout = x"A5A50001" and error = '0' report "read-only register read failed" severity failure;

    wr_addr <= x"0010";
    din <= x"DEADBEEF";
    wr_en <= '1';
    wait until rising_edge(clk);
    wr_en <= '0';
    wait until rising_edge(clk);
    assert wr_valid = '1' and error = '1' and ro_regs(0) = x"A5A50001" report "read-only write was not rejected" severity failure;

    wr_addr <= x"0020";
    wr_en <= '1';
    wait until rising_edge(clk);
    wr_en <= '0';
    wait until rising_edge(clk);
    assert wr_valid = '1' and error = '1' report "out-of-range write did not flag error" severity failure;

    report "PASS tb_radif_reg_bank";
    std.env.finish;
    wait;
  end process;
end architecture;
