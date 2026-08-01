library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- RAD synchronous FIFO built from explicit vendor RAM wrappers plus local
-- pointer/count logic. This is used for FPGA families such as ECP5 that expose
-- BRAM primitives but no separate FIFO hard macro in the open-source flow.
entity radhdl_fifo_bram_sync is
  generic (
    VENDOR        : string   := "generic";
    DEVICE_FAMILY : string   := "generic";
    DATA_WIDTH    : positive := 32;
    ADDR_WIDTH    : positive := 4;
    DEPTH         : positive := 16;
    SIMULATION    : boolean  := false
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    wr_en      : in  std_logic;
    rd_en      : in  std_logic;
    din        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    dout       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    empty      : out std_logic;
    full       : out std_logic;
    data_valid : out std_logic;
    count_o    : out unsigned(ADDR_WIDTH downto 0)
  );
end entity;

architecture rtl of radhdl_fifo_bram_sync is
  signal wr_ptr       : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_ptr       : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal count_r      : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_fire      : std_logic;
  signal rd_fire      : std_logic;
  signal rd_fire_r    : std_logic := '0';
  signal ram_dout     : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal unused_dout  : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  assert DEPTH = 2 ** ADDR_WIDTH
    report "radhdl_fifo_bram_sync DEPTH must equal 2**ADDR_WIDTH"
    severity failure;

  empty <= '1' when count_r = 0 else '0';
  full <= '1' when count_r = DEPTH else '0';
  wr_fire <= '1' when wr_en = '1' and count_r < DEPTH else '0';
  rd_fire <= '1' when rd_en = '1' and count_r > 0 else '0';
  count_o <= count_r;
  data_valid <= rd_fire_r;
  dout <= ram_dout;

  ram_i : entity work.radhdl_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      MODE => "tdp",
      MEMORY_KIND => "bram",
      DATA_WIDTH => DATA_WIDTH,
      ADDR_WIDTH => ADDR_WIDTH,
      DEPTH => DEPTH,
      CLOCKING_MODE => "common_clock",
      SIMULATION => SIMULATION
    )
    port map (
      clka => clk,
      rsta => rst,
      a_addr => std_logic_vector(wr_ptr),
      a_din => din,
      a_dout => unused_dout,
      a_we => wr_fire,
      clkb => clk,
      rstb => rst,
      b_addr => std_logic_vector(rd_ptr),
      b_din => (others => '0'),
      b_dout => ram_dout,
      b_we => '0'
    );

  process(clk)
    variable next_count : unsigned(ADDR_WIDTH downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
        count_r <= (others => '0');
        rd_fire_r <= '0';
      else
        next_count := count_r;
        rd_fire_r <= rd_fire;

        if wr_fire = '1' then
          wr_ptr <= wr_ptr + 1;
          next_count := next_count + 1;
        end if;

        if rd_fire = '1' then
          rd_ptr <= rd_ptr + 1;
          next_count := next_count - 1;
        end if;

        count_r <= next_count;
      end if;
    end if;
  end process;
end architecture;
