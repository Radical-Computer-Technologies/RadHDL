library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_radhdl_ram_vendor is
  generic (
    VENDOR        : string := "lattice";
    DEVICE_FAMILY : string := "ecp5";
    DONE_MARKER   : string := "RADHDL_RAM_VENDOR_SIM_OK"
  );
end entity;

architecture tb of tb_radhdl_ram_vendor is
  constant DATA_WIDTH : positive := 16;
  constant ADDR_WIDTH : positive := 4;
  constant DEPTH      : positive := 16;

  signal clka   : std_logic := '0';
  signal clkb   : std_logic := '0';
  signal rst    : std_logic := '1';
  signal a_addr : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal a_din  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal a_dout : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal a_we   : std_logic := '0';
  signal b_addr : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal b_din  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal b_dout : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal b_we   : std_logic := '0';

  procedure wait_a(count : positive) is
  begin
    for index in 1 to count loop
      wait until rising_edge(clka);
    end loop;
  end procedure;

  procedure wait_b(count : positive) is
  begin
    for index in 1 to count loop
      wait until rising_edge(clkb);
    end loop;
  end procedure;
begin
  clka <= not clka after 5 ns;
  clkb <= not clkb after 7 ns;

  dut : entity work.radhdl_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      MODE => "tdp",
      MEMORY_KIND => "bram",
      DATA_WIDTH => DATA_WIDTH,
      ADDR_WIDTH => ADDR_WIDTH,
      DEPTH => DEPTH,
      CLOCKING_MODE => "independent_clock",
      SIMULATION => true
    )
    port map (
      clka => clka,
      rsta => rst,
      a_addr => a_addr,
      a_din => a_din,
      a_dout => a_dout,
      a_we => a_we,
      clkb => clkb,
      rstb => rst,
      b_addr => b_addr,
      b_din => b_din,
      b_dout => b_dout,
      b_we => b_we
    );

  process
  begin
    wait_a(4);
    rst <= '0';
    wait_a(2);

    for index in 0 to 7 loop
      wait until rising_edge(clka);
      a_addr <= std_logic_vector(to_unsigned(index, ADDR_WIDTH));
      a_din <= std_logic_vector(to_unsigned(16#1000# + index, DATA_WIDTH));
      a_we <= '1';
    end loop;
    wait until rising_edge(clka);
    a_we <= '0';

    wait_b(4);
    for index in 0 to 7 loop
      wait until rising_edge(clkb);
      b_addr <= std_logic_vector(to_unsigned(index, ADDR_WIDTH));
      wait until rising_edge(clkb);
      wait for 1 ns;
      assert b_dout = std_logic_vector(to_unsigned(16#1000# + index, DATA_WIDTH))
        report "RAM readback mismatch"
        severity failure;
    end loop;

    report DONE_MARKER;
    wait;
  end process;
end architecture;
