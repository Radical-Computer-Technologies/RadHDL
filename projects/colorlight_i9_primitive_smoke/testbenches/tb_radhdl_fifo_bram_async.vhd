library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_radhdl_fifo_bram_async is
end entity;

architecture tb of tb_radhdl_fifo_bram_async is
  signal wr_clk        : std_logic := '0';
  signal rd_clk        : std_logic := '0';
  signal rst           : std_logic := '1';
  signal wr_en         : std_logic := '0';
  signal rd_en         : std_logic := '0';
  signal din           : std_logic_vector(7 downto 0) := (others => '0');
  signal dout          : std_logic_vector(7 downto 0);
  signal empty         : std_logic;
  signal full          : std_logic;
  signal data_valid    : std_logic;
  signal wr_data_count : unsigned(3 downto 0);
  signal rd_data_count : unsigned(3 downto 0);

  procedure wait_wr_cycles(count : positive) is
  begin
    for index in 1 to count loop
      wait until rising_edge(wr_clk);
    end loop;
  end procedure;

  procedure wait_rd_cycles(count : positive) is
  begin
    for index in 1 to count loop
      wait until rising_edge(rd_clk);
    end loop;
  end procedure;
begin
  wr_clk <= not wr_clk after 5 ns;
  rd_clk <= not rd_clk after 7 ns;

  dut : entity work.radhdl_fifo_bram_async
    generic map (
      VENDOR => "lattice",
      DEVICE_FAMILY => "ecp5",
      DATA_WIDTH => 8,
      ADDR_WIDTH => 3,
      DEPTH => 8,
      CDC_STAGES => 2,
      SIMULATION => true
    )
    port map (
      wr_clk => wr_clk,
      rd_clk => rd_clk,
      rst => rst,
      wr_en => wr_en,
      rd_en => rd_en,
      din => din,
      dout => dout,
      empty => empty,
      full => full,
      data_valid => data_valid,
      wr_data_count => wr_data_count,
      rd_data_count => rd_data_count
    );

  process
    variable expected : natural := 0;
  begin
    wait for 40 ns;
    wait until rising_edge(wr_clk);
    rst <= '0';
    wait_wr_cycles(6);
    wait_rd_cycles(6);
    assert empty = '1' report "FIFO should settle empty after reset" severity failure;

    for value in 1 to 4 loop
      wait until rising_edge(wr_clk);
      din <= std_logic_vector(to_unsigned(value, din'length));
      wr_en <= '1';
    end loop;
    wait until rising_edge(wr_clk);
    wr_en <= '0';

    wait_rd_cycles(8);

    for value in 1 to 4 loop
      expected := value;
      wait until rising_edge(rd_clk);
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      rd_en <= '0';
      wait for 1 ns;
      assert data_valid = '1' report "Async FIFO read did not assert data_valid" severity failure;
      assert dout = std_logic_vector(to_unsigned(expected, dout'length))
        report "Async FIFO read data mismatch"
        severity failure;
    end loop;

    wait_rd_cycles(6);
    assert empty = '1' report "FIFO should return empty after all reads" severity failure;
    report "RADHDL_FIFO_BRAM_ASYNC_SIM_OK";
    wait;
  end process;
end architecture;
