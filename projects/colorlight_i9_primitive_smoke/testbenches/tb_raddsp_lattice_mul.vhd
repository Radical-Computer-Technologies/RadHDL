library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_raddsp_lattice_mul is
end entity;

architecture tb of tb_raddsp_lattice_mul is
  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal valid_i    : std_logic := '0';
  signal subtract_i : std_logic := '0';
  signal last_i     : std_logic := '0';
  signal a_i        : signed(17 downto 0) := (others => '0');
  signal b_i        : signed(17 downto 0) := (others => '0');
  signal valid_o    : std_logic;
  signal subtract_o : std_logic;
  signal last_o     : std_logic;
  signal p_o        : signed(47 downto 0);
  signal ram_a_addr : std_logic_vector(9 downto 0) := (others => '0');
  signal ram_b_addr : std_logic_vector(9 downto 0) := (others => '0');
  signal ram_a_din  : std_logic_vector(17 downto 0) := (others => '0');
  signal ram_b_din  : std_logic_vector(17 downto 0) := (others => '0');
  signal ram_a_dout : std_logic_vector(17 downto 0);
  signal ram_b_dout : std_logic_vector(17 downto 0);
  signal ram_a_we   : std_logic := '0';
  signal ram_b_we   : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.raddsp_lattice_mul
    generic map (
      DEVICE_FAMILY => "ecp5",
      A_WIDTH => 18,
      B_WIDTH => 18,
      SIMULATION => true
    )
    port map (
      clk => clk,
      rst => rst,
      valid_i => valid_i,
      subtract_i => subtract_i,
      last_i => last_i,
      a_i => a_i,
      b_i => b_i,
      valid_o => valid_o,
      subtract_o => subtract_o,
      last_o => last_o,
      p_o => p_o
    );

  ram : entity work.radhdl_lattice_tdp_ram
    generic map (
      DATA_WIDTH => 18,
      ADDR_WIDTH => 10,
      DEPTH => 1024,
      SIMULATION => true
    )
    port map (
      clka => clk,
      a_addr => ram_a_addr,
      a_din => ram_a_din,
      a_dout => ram_a_dout,
      a_we => ram_a_we,
      clkb => clk,
      b_addr => ram_b_addr,
      b_din => ram_b_din,
      b_dout => ram_b_dout,
      b_we => ram_b_we
    );

  process
  begin
    wait for 25 ns;
    wait until rising_edge(clk);
    rst <= '0';

    wait until rising_edge(clk);
    valid_i <= '1';
    subtract_i <= '1';
    last_i <= '1';
    a_i <= to_signed(-1234, 18);
    b_i <= to_signed(55, 18);

    wait until rising_edge(clk);
    valid_i <= '0';
    subtract_i <= '0';
    last_i <= '0';
    a_i <= (others => '0');
    b_i <= (others => '0');

    wait until rising_edge(clk);
    wait until rising_edge(clk);
    assert valid_o = '1' report "expected valid_o after two cycles" severity failure;
    assert subtract_o = '1' report "subtract sideband did not pipeline" severity failure;
    assert last_o = '1' report "last sideband did not pipeline" severity failure;
    assert p_o = to_signed(-1234 * 55, 48) report "signed multiply result mismatch" severity failure;

    ram_a_addr <= std_logic_vector(to_unsigned(7, 10));
    ram_a_din <= std_logic_vector(to_unsigned(16#12345#, 18));
    ram_a_we <= '1';
    wait until rising_edge(clk);
    ram_a_we <= '0';
    ram_b_addr <= std_logic_vector(to_unsigned(7, 10));
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    assert ram_b_dout = std_logic_vector(to_unsigned(16#12345#, 18)) report "dual-port RAM readback mismatch" severity failure;

    wait until rising_edge(clk);
    assert valid_o = '0' report "valid_o should drop after single transaction" severity failure;
    report "RADHDL_LATTICE_MUL_SIM_OK";
    wait;
  end process;
end architecture;
