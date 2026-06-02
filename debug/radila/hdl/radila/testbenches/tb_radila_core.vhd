library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

entity tb_radila_core is
end entity;

architecture sim of tb_radila_core is
  constant C_AXI_ADDR_WIDTH : integer := 6;
  constant C_AXI_DATA_WIDTH : integer := 32;

  signal sample_clk : std_logic := '0';
  signal axi_clk    : std_logic := '0';
  signal sample_rstn: std_logic := '0';
  signal axi_rstn   : std_logic := '0';
  signal sample     : std_logic_vector(31 downto 0) := (others => '0');
  signal event_v    : std_logic_vector(7 downto 0) := (others => '0');
  signal irq        : std_logic;

  signal awaddr     : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal awprot     : std_logic_vector(2 downto 0) := (others => '0');
  signal awvalid    : std_logic := '0';
  signal awready    : std_logic;
  signal wdata      : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb      : std_logic_vector(3 downto 0) := (others => '1');
  signal wvalid     : std_logic := '0';
  signal wready     : std_logic;
  signal bresp      : std_logic_vector(1 downto 0);
  signal bvalid     : std_logic;
  signal bready     : std_logic := '0';
  signal araddr     : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal arprot     : std_logic_vector(2 downto 0) := (others => '0');
  signal arvalid    : std_logic := '0';
  signal arready    : std_logic;
  signal rdata      : std_logic_vector(31 downto 0);
  signal rresp      : std_logic_vector(1 downto 0);
  signal rvalid     : std_logic;
  signal rready     : std_logic := '0';
begin
  sample_clk <= not sample_clk after 3.5 ns;
  axi_clk <= not axi_clk after 5 ns;

  dut : entity work.RadDebugHub
    generic map (
      C_S_AXI_DATA_WIDTH => C_AXI_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH => C_AXI_ADDR_WIDTH,
      SAMPLE_WIDTH       => 32,
      EVENT_WIDTH        => 8,
      DEPTH              => 64,
      ADDR_WIDTH         => 6,
      CMD_LANES          => 4,
      G_DEBUG_BUS        => "AXI_LITE"
    )
    port map (
      sample_clk    => sample_clk,
      sample_rstn   => sample_rstn,
      sample_i      => sample,
      event_i       => event_v,
      irq_o         => irq,
      S_AXI_ACLK    => axi_clk,
      S_AXI_ARESETN => axi_rstn,
      S_AXI_AWADDR  => awaddr,
      S_AXI_AWPROT  => awprot,
      S_AXI_AWVALID => awvalid,
      S_AXI_AWREADY => awready,
      S_AXI_WDATA   => wdata,
      S_AXI_WSTRB   => wstrb,
      S_AXI_WVALID  => wvalid,
      S_AXI_WREADY  => wready,
      S_AXI_BRESP   => bresp,
      S_AXI_BVALID  => bvalid,
      S_AXI_BREADY  => bready,
      S_AXI_ARADDR  => araddr,
      S_AXI_ARPROT  => arprot,
      S_AXI_ARVALID => arvalid,
      S_AXI_ARREADY => arready,
      S_AXI_RDATA   => rdata,
      S_AXI_RRESP   => rresp,
      S_AXI_RVALID  => rvalid,
      S_AXI_RREADY  => rready
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

  axi_stim : process
    variable rd : std_logic_vector(31 downto 0);

    procedure axi_write(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(axi_clk);
      awaddr <= std_logic_vector(to_unsigned(addr, awaddr'length));
      wdata <= data;
      awvalid <= '1';
      wvalid <= '1';
      bready <= '1';
      loop
        wait until rising_edge(axi_clk);
        exit when awready = '1' and wready = '1';
      end loop;
      awvalid <= '0';
      wvalid <= '0';
      loop
        wait until rising_edge(axi_clk);
        exit when bvalid = '1';
      end loop;
      bready <= '0';
      assert bresp = "00" report "AXI write response error" severity failure;
    end procedure;

    procedure axi_read(addr : natural; variable data : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(axi_clk);
      araddr <= std_logic_vector(to_unsigned(addr, araddr'length));
      arvalid <= '1';
      rready <= '1';
      loop
        wait until rising_edge(axi_clk);
        exit when arready = '1';
      end loop;
      arvalid <= '0';
      loop
        wait until rising_edge(axi_clk);
        exit when rvalid = '1';
      end loop;
      data := rdata;
      rready <= '0';
      assert rresp = "00" report "AXI read response error" severity failure;
    end procedure;
  begin
    wait for 100 ns;
    sample_rstn <= '1';
    axi_rstn <= '1';
    wait for 100 ns;

    axi_read(16#00#, rd);
    assert rd = x"52414449" report "unexpected RadDebugHub ID" severity failure;

    axi_write(16#10#, x"00000001");
    wait for 250 ns;
    axi_write(16#14#, x"00000001");
    wait for 250 ns;
    axi_write(16#1c#, x"00000006");
    wait for 250 ns;
    axi_write(16#08#, x"00000001");

    for i in 0 to 500 loop
      wait for 50 ns;
      axi_read(16#0c#, rd);
      if rd(2) = '1' then
        exit;
      end if;
      if i = 250 then
        assert false report "capture did not complete" severity failure;
      end if;
    end loop;

    assert rd(2) = '1' report "done bit was not set" severity failure;
    assert unsigned(rd(31 downto 16)) >= to_unsigned(6, 16) report "captured count too small" severity failure;

    axi_write(16#20#, x"00000002");
    wait for 100 ns;
    axi_read(16#24#, rd);
    assert rd /= x"00000000" report "readback sample remained zero" severity failure;

    axi_write(16#08#, x"00000004");
    for i in 0 to 100 loop
      wait for 50 ns;
      axi_read(16#0c#, rd);
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
