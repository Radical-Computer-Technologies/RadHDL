library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library radif;
use radif.radif_pkg.all;

-- Self-checking or stimulus-focused testbench for smi16 to reg.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radif_smi16_to_reg is
end entity;

architecture sim of tb_radif_smi16_to_reg is
  signal clk       : std_logic := '0';
  signal rstn      : std_logic := '0';
  signal cs_n      : std_logic := '1';
  signal rd_n      : std_logic := '1';
  signal wr_n      : std_logic := '1';
  signal smi_addr  : std_logic_vector(7 downto 0) := (others => '0');
  signal smi_din   : std_logic_vector(15 downto 0) := (others => '0');
  signal smi_dout  : std_logic_vector(15 downto 0);
  signal smi_oen   : std_logic;
  signal smi_ack   : std_logic;
  signal wr_addr   : std_logic_vector(15 downto 0);
  signal rd_addr   : std_logic_vector(15 downto 0);
  signal wr_en     : std_logic;
  signal rd_en     : std_logic;
  signal reg_din   : std_logic_vector(63 downto 0);
  signal reg_dout  : std_logic_vector(63 downto 0);
  signal wr_rdy    : std_logic;
  signal rd_rdy    : std_logic;
  signal wr_valid  : std_logic;
  signal rd_valid  : std_logic;
  signal reg_error : std_logic;
  signal ro_regs   : radif_reg_array_t(0 to 0)(63 downto 0) := (0 => x"CAFE0000FACE0000");
  signal rw_regs   : radif_reg_array_t(0 to 7)(63 downto 0);
begin
  clk <= not clk after 5 ns;

  u_smi : entity radif.radif_smi16_to_reg
    generic map (
      DATA_WIDTH => 64,
      REG_ADDR_WIDTH => 16,
      SMI_ADDR_WIDTH => 8
    )
    port map (
      clk => clk,
      rstn => rstn,
      smi_cs_n_i => cs_n,
      smi_rd_n_i => rd_n,
      smi_wr_n_i => wr_n,
      smi_addr_i => smi_addr,
      smi_data_i => smi_din,
      smi_data_o => smi_dout,
      smi_data_oen => smi_oen,
      smi_ack_o => smi_ack,
      reg_wr_addr => wr_addr,
      reg_rd_addr => rd_addr,
      reg_wr_en => wr_en,
      reg_rd_en => rd_en,
      reg_data_in => reg_din,
      reg_data_out => reg_dout,
      reg_wr_rdy => wr_rdy,
      reg_rd_rdy => rd_rdy,
      reg_wr_valid => wr_valid,
      reg_rd_valid => rd_valid,
      reg_error => reg_error
    );

  u_regs : entity radif.radif_reg_bank
    generic map (
      DATA_WIDTH => 64,
      ADDR_WIDTH => 16,
      READ_ONLY_REG_COUNT => 1,
      READ_WRITE_REG_COUNT => 8
    )
    port map (
      clk => clk,
      rstn => rstn,
      wr_addr => wr_addr,
      rd_addr => rd_addr,
      wr_en => wr_en,
      rd_en => rd_en,
      data_in => reg_din,
      data_out => reg_dout,
      read_only_regs_i => ro_regs,
      read_write_regs_o => rw_regs,
      wr_rdy => wr_rdy,
      rd_rdy => rd_rdy,
      wr_valid => wr_valid,
      rd_valid => rd_valid,
      error => reg_error
    );

  process
    procedure smi_write(
      constant a : in std_logic_vector(7 downto 0);
      constant d : in std_logic_vector(15 downto 0)
    ) is
    begin
      smi_addr <= a;
      smi_din <= d;
      cs_n <= '0';
      wr_n <= '0';
      wait for 50 ns;
      wr_n <= '1';
      cs_n <= '1';
      wait for 50 ns;
    end procedure;

    procedure smi_read(
      constant a : in std_logic_vector(7 downto 0)
    ) is
    begin
      smi_addr <= a;
      cs_n <= '0';
      rd_n <= '0';
      wait for 80 ns;
      rd_n <= '1';
      cs_n <= '1';
      wait for 40 ns;
    end procedure;
  begin
    wait for 50 ns;
    rstn <= '1';
    wait for 50 ns;

    smi_write(x"00", x"1122");
    smi_write(x"01", x"3344");
    smi_write(x"02", x"5566");
    smi_write(x"03", x"7788");
    wait for 100 ns;

    assert wr_en = '0' report "write enable stuck high" severity failure;
    assert rw_regs(0) = x"7788556633441122" report "SMI packed read/write register output failed" severity failure;

    smi_read(x"00");
    assert smi_dout = x"1122" report "SMI lane 0 readback failed" severity failure;
    smi_read(x"01");
    assert smi_dout = x"3344" report "SMI lane 1 readback failed" severity failure;
    smi_read(x"02");
    assert smi_dout = x"5566" report "SMI lane 2 readback failed" severity failure;
    smi_read(x"03");
    assert smi_dout = x"7788" report "SMI lane 3 readback failed" severity failure;

    report "PASS tb_radif_smi16_to_reg";
    std.env.finish;
    wait;
  end process;
end architecture;
