library ieee;
use ieee.std_logic_1164.all;

library xpm;
use xpm.vcomponents.all;

-- Xilinx asynchronous FIFO wrapper. XPM imports stay isolated here.
entity radhdl_xilinx_fifo_async is
  generic (
    DATA_WIDTH        : positive := 32;
    FIFO_DEPTH        : positive := 1024;
    READ_MODE         : string   := "std";
    FIFO_READ_LATENCY : integer  := 1;
    COUNT_WIDTH       : positive := 10
  );
  port (
    wr_clk     : in  std_logic;
    rd_clk     : in  std_logic;
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

architecture rtl of radhdl_xilinx_fifo_async is
begin
  fifo_i : xpm_fifo_async
    generic map (
      CASCADE_HEIGHT => 0,
      CDC_SYNC_STAGES => 2,
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
      RELATED_CLOCKS => 0,
      SIM_ASSERT_CHK => 0,
      USE_ADV_FEATURES => "0707",
      WAKEUP_TIME => 0,
      WRITE_DATA_WIDTH => DATA_WIDTH,
      WR_DATA_COUNT_WIDTH => COUNT_WIDTH
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
      rd_clk => rd_clk,
      rd_en => rd_en,
      rst => rst,
      sleep => '0',
      wr_clk => wr_clk,
      wr_en => wr_en
    );
end architecture;
