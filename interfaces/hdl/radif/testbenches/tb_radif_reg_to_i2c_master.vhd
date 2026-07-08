library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library radif;

-- Exercises the register-controlled I2C master with always-acknowledging open-drain bus behavior.
-- The waveform shows register launch, START, address byte, write data byte, ACK sampling, STOP, and completion status.
entity tb_radif_reg_to_i2c_master is
end entity;

architecture sim of tb_radif_reg_to_i2c_master is
  signal clk          : std_logic := '0';
  signal rstn         : std_logic := '0';
  signal reg_wr_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_rd_addr  : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_wr_en    : std_logic := '0';
  signal reg_rd_en    : std_logic := '0';
  signal reg_data_in  : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_data_out : std_logic_vector(31 downto 0);
  signal reg_wr_rdy   : std_logic;
  signal reg_rd_rdy   : std_logic;
  signal reg_wr_valid : std_logic;
  signal reg_rd_valid : std_logic;
  signal reg_error    : std_logic;
  signal scl_i        : std_logic;
  signal sda_i        : std_logic := '0';
  signal scl_oen      : std_logic;
  signal sda_oen      : std_logic;
begin
  clk <= not clk after 5 ns;
  scl_i <= '1' when scl_oen = '1' else '0';

  dut : entity radif.radif_reg_to_i2c_master
    generic map (
      DEFAULT_SCL_DIV => 1
    )
    port map (
      clk => clk,
      rstn => rstn,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_data_in,
      reg_data_out => reg_data_out,
      reg_wr_rdy => reg_wr_rdy,
      reg_rd_rdy => reg_rd_rdy,
      reg_wr_valid => reg_wr_valid,
      reg_rd_valid => reg_rd_valid,
      reg_error => reg_error,
      i2c_scl_i => scl_i,
      i2c_sda_i => sda_i,
      i2c_scl_oen => scl_oen,
      i2c_sda_oen => sda_oen
    );

  process
    procedure reg_write(addr : std_logic_vector(15 downto 0); data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_wr_addr <= addr;
      reg_data_in <= data;
      reg_wr_en <= '1';
      wait until rising_edge(clk);
      reg_wr_en <= '0';
    end procedure;

    procedure reg_read(addr : std_logic_vector(15 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_rd_addr <= addr;
      reg_rd_en <= '1';
      wait until rising_edge(clk);
      reg_rd_en <= '0';
      wait until rising_edge(clk);
    end procedure;
  begin
    wait for 40 ns;
    rstn <= '1';

    reg_write(x"0008", x"00000001");
    reg_write(x"000C", x"0000002A");
    reg_write(x"0010", x"0000005A");
    reg_write(x"0000", x"00000001");

    for i in 0 to 200 loop
      wait until rising_edge(clk);
      reg_read(x"0004");
      exit when reg_data_out(1) = '1';
    end loop;

    assert reg_data_out(1) = '1' report "I2C transaction did not complete" severity failure;
    assert reg_data_out(2) = '0' report "I2C transaction reported ACK error" severity failure;
    report "PASS tb_radif_reg_to_i2c_master";
    finish;
  end process;
end architecture;
