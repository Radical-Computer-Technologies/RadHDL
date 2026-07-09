library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

library radif;

-- Exercises RADIF GPIO and interrupt-controller register behavior.
entity tb_radif_gpio_irq is
end entity;

architecture sim of tb_radif_gpio_irq is
  constant C_DATA_WIDTH : integer := 32;
  constant C_ADDR_WIDTH : integer := 16;
  constant C_GPIO_WIDTH : integer := 4;

  signal clk : std_logic := '0';
  signal rstn : std_logic := '0';

  signal gpio_i : std_logic_vector(C_GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_o : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
  signal gpio_oe : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
  signal gpio_irq : std_logic;

  signal gpio_wr_addr : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_rd_addr : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_wr_en : std_logic := '0';
  signal gpio_rd_en : std_logic := '0';
  signal gpio_data_in : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_data_out : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal gpio_wr_rdy : std_logic;
  signal gpio_rd_rdy : std_logic;
  signal gpio_wr_valid : std_logic;
  signal gpio_rd_valid : std_logic;
  signal gpio_error : std_logic;

  signal irq_inputs : std_logic_vector(C_GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal irq_o : std_logic;
  signal irq_pending : std_logic_vector(C_GPIO_WIDTH - 1 downto 0);
  signal irq_wr_addr : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal irq_rd_addr : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal irq_wr_en : std_logic := '0';
  signal irq_rd_en : std_logic := '0';
  signal irq_data_in : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal irq_data_out : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal irq_wr_rdy : std_logic;
  signal irq_rd_rdy : std_logic;
  signal irq_wr_valid : std_logic;
  signal irq_rd_valid : std_logic;
  signal irq_error : std_logic;
begin
  clk <= not clk after 5 ns;
  irq_inputs <= gpio_irq & "000";

  u_gpio : entity radif.radif_gpio_reg_block
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      REG_ADDR_WIDTH => C_ADDR_WIDTH,
      GPIO_WIDTH => C_GPIO_WIDTH
    )
    port map (
      clk => clk,
      rstn => rstn,
      gpio_i => gpio_i,
      gpio_o => gpio_o,
      gpio_oe_o => gpio_oe,
      irq_o => gpio_irq,
      reg_wr_addr => gpio_wr_addr,
      reg_rd_addr => gpio_rd_addr,
      reg_wr_en => gpio_wr_en,
      reg_rd_en => gpio_rd_en,
      reg_data_in => gpio_data_in,
      reg_data_out => gpio_data_out,
      reg_wr_rdy => gpio_wr_rdy,
      reg_rd_rdy => gpio_rd_rdy,
      reg_wr_valid => gpio_wr_valid,
      reg_rd_valid => gpio_rd_valid,
      reg_error => gpio_error
    );

  u_irq : entity radif.radif_irq_controller
    generic map (
      DATA_WIDTH => C_DATA_WIDTH,
      REG_ADDR_WIDTH => C_ADDR_WIDTH,
      IRQ_COUNT => C_GPIO_WIDTH
    )
    port map (
      clk => clk,
      rstn => rstn,
      irq_i => irq_inputs,
      irq_o => irq_o,
      irq_pending_o => irq_pending,
      reg_wr_addr => irq_wr_addr,
      reg_rd_addr => irq_rd_addr,
      reg_wr_en => irq_wr_en,
      reg_rd_en => irq_rd_en,
      reg_data_in => irq_data_in,
      reg_data_out => irq_data_out,
      reg_wr_rdy => irq_wr_rdy,
      reg_rd_rdy => irq_rd_rdy,
      reg_wr_valid => irq_wr_valid,
      reg_rd_valid => irq_rd_valid,
      reg_error => irq_error
    );

  stim : process
    variable rd : std_logic_vector(31 downto 0);

    procedure gpio_write(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      gpio_wr_addr <= std_logic_vector(to_unsigned(addr, C_ADDR_WIDTH));
      gpio_data_in <= data;
      gpio_wr_en <= '1';
      wait until rising_edge(clk);
      gpio_wr_en <= '0';
      wait until gpio_wr_valid = '1';
      assert gpio_error = '0' report "GPIO write error" severity failure;
    end procedure;

    procedure gpio_read(addr : natural; variable data : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      gpio_rd_addr <= std_logic_vector(to_unsigned(addr, C_ADDR_WIDTH));
      gpio_rd_en <= '1';
      wait until rising_edge(clk);
      gpio_rd_en <= '0';
      wait until gpio_rd_valid = '1';
      assert gpio_error = '0' report "GPIO read error" severity failure;
      data := gpio_data_out;
    end procedure;

    procedure irq_write(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      irq_wr_addr <= std_logic_vector(to_unsigned(addr, C_ADDR_WIDTH));
      irq_data_in <= data;
      irq_wr_en <= '1';
      wait until rising_edge(clk);
      irq_wr_en <= '0';
      wait until irq_wr_valid = '1';
      assert irq_error = '0' report "IRQ write error" severity failure;
    end procedure;

    procedure irq_read(addr : natural; variable data : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      irq_rd_addr <= std_logic_vector(to_unsigned(addr, C_ADDR_WIDTH));
      irq_rd_en <= '1';
      wait until rising_edge(clk);
      irq_rd_en <= '0';
      wait until irq_rd_valid = '1';
      assert irq_error = '0' report "IRQ read error" severity failure;
      data := irq_data_out;
    end procedure;
  begin
    wait for 100 ns;
    rstn <= '1';
    wait for 50 ns;

    gpio_write(16#00#, x"0000000A");
    gpio_write(16#04#, x"0000000F");
    assert gpio_o = "1010" report "GPIO output value mismatch" severity failure;
    assert gpio_oe = "1111" report "GPIO output enable mismatch" severity failure;

    gpio_i <= "0010";
    wait for 40 ns;
    gpio_read(16#08#, rd);
    assert rd(3 downto 0) = "0010" report "GPIO input readback mismatch" severity failure;

    gpio_write(16#10#, x"00000002");
    gpio_write(16#14#, x"00000002");
    gpio_i <= "0000";
    wait for 40 ns;
    gpio_i <= "0010";
    wait for 60 ns;
    assert gpio_irq = '1' report "GPIO IRQ did not assert" severity failure;
    gpio_read(16#0C#, rd);
    assert rd(1) = '1' report "GPIO pending bit did not latch" severity failure;

    irq_write(16#08#, x"00000008");
    irq_write(16#00#, x"00000001");
    wait for 80 ns;
    assert irq_o = '1' report "IRQ controller did not aggregate GPIO IRQ" severity failure;
    irq_read(16#0C#, rd);
    assert rd(3) = '1' report "IRQ controller pending bit missing" severity failure;
    gpio_write(16#0C#, x"00000002");
    wait for 30 ns;
    assert gpio_irq = '0' report "GPIO IRQ clear failed" severity failure;
    irq_write(16#10#, x"00000008");
    wait for 30 ns;
    assert irq_o = '0' report "IRQ controller clear failed" severity failure;

    report "tb_radif_gpio_irq passed" severity note;
    finish;
  end process;
end architecture;
