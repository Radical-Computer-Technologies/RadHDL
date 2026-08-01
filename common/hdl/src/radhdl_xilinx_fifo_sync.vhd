library ieee;
use ieee.std_logic_1164.all;

library xpm;
use xpm.vcomponents.all;

-- Xilinx synchronous FIFO wrapper. XPM imports stay isolated here.
entity radhdl_xilinx_fifo_sync is
  generic (
    DATA_WIDTH        : positive := 32;
    FIFO_DEPTH        : positive := 1024;
    READ_MODE         : string   := "std";
    FIFO_READ_LATENCY : integer  := 1;
    COUNT_WIDTH       : positive := 10
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
    data_valid : out std_logic
  );
end entity;

architecture rtl of radhdl_xilinx_fifo_sync is
  signal empty_i      : std_logic;
  signal full_i       : std_logic;
  signal xpm_valid_i  : std_logic;
  signal read_fire_d1 : std_logic := '0';
begin
  empty <= empty_i;
  full <= full_i;
  data_valid <= xpm_valid_i or read_fire_d1;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        read_fire_d1 <= '0';
      else
        read_fire_d1 <= rd_en and not empty_i;
      end if;
    end if;
  end process;

  fifo_i : xpm_fifo_sync
    generic map (
      CASCADE_HEIGHT => 0,
      DOUT_RESET_VALUE => "0",
      ECC_MODE => "no_ecc",
      FIFO_MEMORY_TYPE => "block",
      FIFO_READ_LATENCY => FIFO_READ_LATENCY,
      FIFO_WRITE_DEPTH => FIFO_DEPTH,
      FULL_RESET_VALUE => 0,
      PROG_EMPTY_THRESH => 10,
      PROG_FULL_THRESH => 10,
      RD_DATA_COUNT_WIDTH => COUNT_WIDTH,
      READ_DATA_WIDTH => DATA_WIDTH,
      READ_MODE => READ_MODE,
      SIM_ASSERT_CHK => 0,
      USE_ADV_FEATURES => "0707",
      WAKEUP_TIME => 0,
      WRITE_DATA_WIDTH => DATA_WIDTH,
      WR_DATA_COUNT_WIDTH => COUNT_WIDTH
    )
    port map (
      almost_empty => open,
      almost_full => open,
      data_valid => xpm_valid_i,
      dbiterr => open,
      dout => dout,
      empty => empty_i,
      full => full_i,
      overflow => open,
      prog_empty => open,
      prog_full => open,
      rd_data_count => open,
      rd_rst_busy => open,
      sbiterr => open,
      underflow => open,
      wr_ack => open,
      wr_data_count => open,
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
end architecture;
