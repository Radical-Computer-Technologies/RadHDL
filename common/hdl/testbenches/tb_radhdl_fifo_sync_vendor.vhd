library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_radhdl_fifo_sync_vendor is
  generic (
    VENDOR        : string := "lattice";
    DEVICE_FAMILY : string := "ecp5";
    DONE_MARKER   : string := "RADHDL_FIFO_SYNC_VENDOR_SIM_OK"
  );
end entity;

architecture tb of tb_radhdl_fifo_sync_vendor is
  constant DATA_WIDTH : positive := 8;
  constant DEPTH      : positive := 16;
  constant COUNT_BITS : positive := 5;

  signal clk           : std_logic := '0';
  signal rst           : std_logic := '1';
  signal wr_en         : std_logic := '0';
  signal rd_en         : std_logic := '0';
  signal din           : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal dout          : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal empty         : std_logic;
  signal full          : std_logic;
  signal data_valid    : std_logic;
  signal rd_data_count : std_logic_vector(COUNT_BITS - 1 downto 0);
  signal wr_data_count : std_logic_vector(COUNT_BITS - 1 downto 0);

  procedure wait_clk(count : positive) is
  begin
    for index in 1 to count loop
      wait until rising_edge(clk);
    end loop;
  end procedure;
begin
  clk <= not clk after 5 ns;

  dut : entity work.radhdl_fifo_sync
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      FIFO_MEMORY_TYPE => "block",
      FIFO_READ_LATENCY => 1,
      FIFO_WRITE_DEPTH => DEPTH,
      READ_DATA_WIDTH => DATA_WIDTH,
      WRITE_DATA_WIDTH => DATA_WIDTH,
      READ_MODE => "std",
      SIM_ASSERT_CHK => 1,
      RD_DATA_COUNT_WIDTH => COUNT_BITS,
      WR_DATA_COUNT_WIDTH => COUNT_BITS
    )
    port map (
      almost_empty => open,
      almost_full => open,
      data_valid => data_valid,
      dbiterr => open,
      dout => dout,
      empty => empty,
      full => full,
      overflow => open,
      prog_empty => open,
      prog_full => open,
      rd_data_count => rd_data_count,
      rd_rst_busy => open,
      sbiterr => open,
      underflow => open,
      wr_ack => open,
      wr_data_count => wr_data_count,
      wr_rst_busy => open,
      din => din,
      injectdbiterr => '0',
      injectsbiterr => '0',
      rd_en => rd_en,
      rst => rst,
      sleep => '0',
      wr_clk => clk,
      wr_en => wr_en
    );

  process
    variable matched : boolean;
  begin
    wait_clk(4);
    rst <= '0';
    wait_clk(20);
    assert empty = '1' report "FIFO should be empty after reset" severity failure;

    for value in 1 to 6 loop
      wait until rising_edge(clk);
      din <= std_logic_vector(to_unsigned(value, DATA_WIDTH));
      wr_en <= '1';
    end loop;
    wait until rising_edge(clk);
    wr_en <= '0';

    wait_clk(20);
    for value in 1 to 6 loop
      wait until rising_edge(clk);
      rd_en <= '1';
      wait until rising_edge(clk);
      rd_en <= '0';
      wait for 1 ns;
      matched := false;
      for latency in 0 to 5 loop
        if data_valid = '1' then
          assert dout = std_logic_vector(to_unsigned(value, DATA_WIDTH))
            report "FIFO read data mismatch expected=" & integer'image(value) &
                   " got=" & integer'image(to_integer(unsigned(dout)))
            severity failure;
          matched := true;
          exit;
        end if;
        wait until rising_edge(clk);
        wait for 1 ns;
      end loop;
      assert matched report "FIFO data_valid did not assert within latency window" severity failure;
    end loop;

    wait_clk(3);
    assert empty = '1' report "FIFO should return empty" severity failure;
    report DONE_MARKER;
    wait;
  end process;
end architecture;
