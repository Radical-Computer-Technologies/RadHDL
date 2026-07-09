library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

-- Self-checking or stimulus-focused testbench for radila core.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_radila_core is
end entity;

architecture sim of tb_radila_core is
  constant C_REG_ADDR_WIDTH : integer := 16;
  constant C_DATA_WIDTH     : integer := 32;

  signal sample_clk : std_logic := '0';
  signal reg_clk    : std_logic := '0';
  signal sample_rstn: std_logic := '0';
  signal reg_rstn   : std_logic := '0';
  signal sample     : std_logic_vector(31 downto 0) := (others => '0');
  signal event_v    : std_logic_vector(7 downto 0) := (others => '0');
  signal irq        : std_logic;

  signal reg_wr_addr  : std_logic_vector(C_REG_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal reg_rd_addr  : std_logic_vector(C_REG_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal reg_wr_en    : std_logic := '0';
  signal reg_rd_en    : std_logic := '0';
  signal reg_data_in  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal reg_data_out : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal reg_wr_rdy   : std_logic;
  signal reg_rd_rdy   : std_logic;
  signal reg_wr_valid : std_logic;
  signal reg_rd_valid : std_logic;
  signal reg_error    : std_logic;
begin
  sample_clk <= not sample_clk after 3.5 ns;
  reg_clk <= not reg_clk after 5 ns;

  dut : entity work.RadDebugHub
    generic map (
      DATA_WIDTH         => C_DATA_WIDTH,
      REG_ADDR_WIDTH     => C_REG_ADDR_WIDTH,
      SAMPLE_WIDTH       => 32,
      EVENT_WIDTH        => 8,
      DEPTH              => 64,
      ADDR_WIDTH         => 6,
      CMD_LANES          => 4,
      VENDOR_TAG         => "GENERIC"
    )
    port map (
      sample_clk    => sample_clk,
      sample_rstn   => sample_rstn,
      sample_i      => sample,
      event_i       => event_v,
      irq_o         => irq,
      reg_clk       => reg_clk,
      reg_rstn      => reg_rstn,
      reg_wr_addr   => reg_wr_addr,
      reg_rd_addr   => reg_rd_addr,
      reg_wr_en     => reg_wr_en,
      reg_rd_en     => reg_rd_en,
      reg_data_in   => reg_data_in,
      reg_data_out  => reg_data_out,
      reg_wr_rdy    => reg_wr_rdy,
      reg_rd_rdy    => reg_rd_rdy,
      reg_wr_valid  => reg_wr_valid,
      reg_rd_valid  => reg_rd_valid,
      reg_error     => reg_error
    );

  sample_stim : process
    variable n : unsigned(31 downto 0) := (others => '0');
  begin
    wait until sample_rstn = '1';
    loop
      wait until rising_edge(sample_clk);
      sample <= std_logic_vector(n);
      if n = to_unsigned(1000, n'length) then
        event_v <= x"01";
      else
        event_v <= x"00";
      end if;
      n := n + 1;
    end loop;
  end process;

  reg_stim : process
    variable rd : std_logic_vector(31 downto 0);

    procedure reg_write(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(reg_clk);
      reg_wr_addr <= std_logic_vector(to_unsigned(addr, reg_wr_addr'length));
      reg_data_in <= data;
      reg_wr_en <= '1';
      loop
        wait until rising_edge(reg_clk);
        exit when reg_wr_rdy = '1';
      end loop;
      reg_wr_en <= '0';
      loop
        wait until rising_edge(reg_clk);
        exit when reg_wr_valid = '1';
      end loop;
      assert reg_error = '0' report "register write response error" severity failure;
    end procedure;

    procedure reg_read(addr : natural; variable data : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(reg_clk);
      reg_rd_addr <= std_logic_vector(to_unsigned(addr, reg_rd_addr'length));
      reg_rd_en <= '1';
      loop
        wait until rising_edge(reg_clk);
        exit when reg_rd_rdy = '1';
      end loop;
      reg_rd_en <= '0';
      loop
        wait until rising_edge(reg_clk);
        exit when reg_rd_valid = '1';
      end loop;
      data := reg_data_out;
      assert reg_error = '0' report "register read response error" severity failure;
    end procedure;
  begin
    wait for 100 ns;
    sample_rstn <= '1';
    reg_rstn <= '1';
    wait for 100 ns;

    reg_read(16#00#, rd);
    assert rd = x"52414449" report "unexpected RadDebugHub ID" severity failure;

    reg_write(16#10#, x"00000001");
    wait for 250 ns;
    reg_write(16#14#, x"00000001");
    wait for 250 ns;
    reg_write(16#1c#, x"00000006");
    wait for 250 ns;
    reg_write(16#08#, x"00000001");

    for i in 0 to 500 loop
      wait for 50 ns;
      reg_read(16#0c#, rd);
      if rd(2) = '1' then
        exit;
      end if;
      if i = 250 then
        assert false report "capture did not complete" severity failure;
      end if;
    end loop;

    assert rd(2) = '1' report "done bit was not set" severity failure;
    assert unsigned(rd(31 downto 16)) >= to_unsigned(6, 16) report "captured count too small" severity failure;

    reg_write(16#20#, x"00000002");
    wait for 100 ns;
    reg_read(16#24#, rd);
    assert rd /= x"00000000" report "readback sample remained zero" severity failure;

    reg_write(16#08#, x"00000004");
    for i in 0 to 100 loop
      wait for 50 ns;
      reg_read(16#0c#, rd);
      if rd(2) = '0' then
        exit;
      end if;
      if i = 100 then
        assert false report "clear command did not reset done bit" severity failure;
      end if;
    end loop;
    assert rd(2) = '0' report "clear command did not reset done bit" severity failure;

    report "tb_radila_core passed" severity note;
    finish;
  end process;
end architecture;
