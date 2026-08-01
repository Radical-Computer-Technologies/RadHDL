library ieee;
use ieee.std_logic_1164.all;

-- Public vendor-neutral FIFO primitive.
-- Synchronous and asynchronous modes route to explicit vendor FIFO IP or hard
-- FIFO macros. This wrapper deliberately avoids inferred FIFO storage.
entity radhdl_fifo is
  generic (
    VENDOR              : string  := "xilinx";
    DEVICE_FAMILY       : string  := "7series";
    FIFO_MODE           : string  := "sync";
    ASYNC               : boolean := false;
    CASCADE_HEIGHT      : integer := 0;
    DOUT_RESET_VALUE    : string  := "0";
    ECC_MODE            : string  := "no_ecc";
    FIFO_MEMORY_TYPE    : string  := "auto";
    FIFO_READ_LATENCY   : integer := 1;
    FIFO_WRITE_DEPTH    : integer := 1024;
    FULL_RESET_VALUE    : integer := 0;
    PROG_EMPTY_THRESH   : integer := 10;
    PROG_FULL_THRESH    : integer := 10;
    RD_DATA_COUNT_WIDTH : integer := 1;
    READ_DATA_WIDTH     : integer := 32;
    READ_MODE           : string  := "std";
    SIM_ASSERT_CHK      : integer := 0;
    USE_ADV_FEATURES    : string  := "0707";
    WAKEUP_TIME         : integer := 0;
    WRITE_DATA_WIDTH    : integer := 32;
    WR_DATA_COUNT_WIDTH : integer := 1
  );
  port (
    almost_empty  : out std_logic;
    almost_full   : out std_logic;
    data_valid    : out std_logic;
    dbiterr       : out std_logic;
    dout          : out std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
    empty         : out std_logic;
    full          : out std_logic;
    overflow      : out std_logic;
    prog_empty    : out std_logic;
    prog_full     : out std_logic;
    rd_data_count : out std_logic_vector(RD_DATA_COUNT_WIDTH - 1 downto 0);
    rd_rst_busy   : out std_logic;
    sbiterr       : out std_logic;
    underflow     : out std_logic;
    wr_ack        : out std_logic;
    wr_data_count : out std_logic_vector(WR_DATA_COUNT_WIDTH - 1 downto 0);
    wr_rst_busy   : out std_logic;
    din           : in  std_logic_vector(WRITE_DATA_WIDTH - 1 downto 0);
    injectdbiterr : in  std_logic;
    injectsbiterr : in  std_logic;
    rd_en         : in  std_logic;
    rst           : in  std_logic;
    sleep         : in  std_logic;
    rd_clk        : in  std_logic := '0';
    wr_clk        : in  std_logic;
    wr_en         : in  std_logic
  );
end entity;

architecture rtl of radhdl_fifo is
  component radhdl_fifo_sync is
    generic (
      VENDOR              : string  := "xilinx";
      DEVICE_FAMILY       : string  := "7series";
      CASCADE_HEIGHT      : integer := 0;
      DOUT_RESET_VALUE    : string  := "0";
      ECC_MODE            : string  := "no_ecc";
      FIFO_MEMORY_TYPE    : string  := "auto";
      FIFO_READ_LATENCY   : integer := 1;
      FIFO_WRITE_DEPTH    : integer := 1024;
      FULL_RESET_VALUE    : integer := 0;
      PROG_EMPTY_THRESH   : integer := 10;
      PROG_FULL_THRESH    : integer := 10;
      RD_DATA_COUNT_WIDTH : integer := 1;
      READ_DATA_WIDTH     : integer := 32;
      READ_MODE           : string  := "std";
      SIM_ASSERT_CHK      : integer := 0;
      USE_ADV_FEATURES    : string  := "0707";
      WAKEUP_TIME         : integer := 0;
      WRITE_DATA_WIDTH    : integer := 32;
      WR_DATA_COUNT_WIDTH : integer := 1
    );
    port (
      almost_empty  : out std_logic;
      almost_full   : out std_logic;
      data_valid    : out std_logic;
      dbiterr       : out std_logic;
      dout          : out std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
      empty         : out std_logic;
      full          : out std_logic;
      overflow      : out std_logic;
      prog_empty    : out std_logic;
      prog_full     : out std_logic;
      rd_data_count : out std_logic_vector(RD_DATA_COUNT_WIDTH - 1 downto 0);
      rd_rst_busy   : out std_logic;
      sbiterr       : out std_logic;
      underflow     : out std_logic;
      wr_ack        : out std_logic;
      wr_data_count : out std_logic_vector(WR_DATA_COUNT_WIDTH - 1 downto 0);
      wr_rst_busy   : out std_logic;
      din           : in  std_logic_vector(WRITE_DATA_WIDTH - 1 downto 0);
      injectdbiterr : in  std_logic;
      injectsbiterr : in  std_logic;
      rd_en         : in  std_logic;
      rst           : in  std_logic;
      sleep         : in  std_logic;
      wr_clk        : in  std_logic;
      wr_en         : in  std_logic
    );
  end component;

  component radhdl_fifo_async is
    generic (
      VENDOR              : string  := "xilinx";
      DEVICE_FAMILY       : string  := "7series";
      FIFO_READ_LATENCY   : integer := 1;
      FIFO_WRITE_DEPTH    : integer := 1024;
      RD_DATA_COUNT_WIDTH : integer := 1;
      READ_DATA_WIDTH     : integer := 32;
      READ_MODE           : string  := "std";
      WRITE_DATA_WIDTH    : integer := 32;
      WR_DATA_COUNT_WIDTH : integer := 1
    );
    port (
      almost_empty  : out std_logic;
      almost_full   : out std_logic;
      data_valid    : out std_logic;
      dout          : out std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
      empty         : out std_logic;
      full          : out std_logic;
      rd_data_count : out std_logic_vector(RD_DATA_COUNT_WIDTH - 1 downto 0);
      wr_data_count : out std_logic_vector(WR_DATA_COUNT_WIDTH - 1 downto 0);
      din           : in  std_logic_vector(WRITE_DATA_WIDTH - 1 downto 0);
      rd_clk        : in  std_logic;
      rd_en         : in  std_logic;
      rst           : in  std_logic;
      wr_clk        : in  std_logic;
      wr_en         : in  std_logic
    );
  end component;
begin
  assert FIFO_MODE = "sync" or FIFO_MODE = "SYNC" or FIFO_MODE = "async" or FIFO_MODE = "ASYNC"
    report "radhdl_fifo FIFO_MODE must be sync or async"
    severity failure;

  gen_sync : if (not ASYNC) and (FIFO_MODE = "sync" or FIFO_MODE = "SYNC") generate
  begin
    fifo_i : radhdl_fifo_sync
      generic map (
        VENDOR => VENDOR,
        DEVICE_FAMILY => DEVICE_FAMILY,
        CASCADE_HEIGHT => CASCADE_HEIGHT,
        DOUT_RESET_VALUE => DOUT_RESET_VALUE,
        ECC_MODE => ECC_MODE,
        FIFO_MEMORY_TYPE => FIFO_MEMORY_TYPE,
        FIFO_READ_LATENCY => FIFO_READ_LATENCY,
        FIFO_WRITE_DEPTH => FIFO_WRITE_DEPTH,
        FULL_RESET_VALUE => FULL_RESET_VALUE,
        PROG_EMPTY_THRESH => PROG_EMPTY_THRESH,
        PROG_FULL_THRESH => PROG_FULL_THRESH,
        RD_DATA_COUNT_WIDTH => RD_DATA_COUNT_WIDTH,
        READ_DATA_WIDTH => READ_DATA_WIDTH,
        READ_MODE => READ_MODE,
        SIM_ASSERT_CHK => SIM_ASSERT_CHK,
        USE_ADV_FEATURES => USE_ADV_FEATURES,
        WAKEUP_TIME => WAKEUP_TIME,
        WRITE_DATA_WIDTH => WRITE_DATA_WIDTH,
        WR_DATA_COUNT_WIDTH => WR_DATA_COUNT_WIDTH
      )
      port map (
        almost_empty => almost_empty,
        almost_full => almost_full,
        data_valid => data_valid,
        dbiterr => dbiterr,
        dout => dout,
        empty => empty,
        full => full,
        overflow => overflow,
        prog_empty => prog_empty,
        prog_full => prog_full,
        rd_data_count => rd_data_count,
        rd_rst_busy => rd_rst_busy,
        sbiterr => sbiterr,
        underflow => underflow,
        wr_ack => wr_ack,
        wr_data_count => wr_data_count,
        wr_rst_busy => wr_rst_busy,
        din => din,
        injectdbiterr => injectdbiterr,
        injectsbiterr => injectsbiterr,
        rd_en => rd_en,
        rst => rst,
        sleep => sleep,
        wr_clk => wr_clk,
        wr_en => wr_en
      );
  end generate;

  gen_async : if ASYNC or FIFO_MODE = "async" or FIFO_MODE = "ASYNC" generate
  begin
    dbiterr <= '0';
    overflow <= '0';
    prog_empty <= almost_empty;
    prog_full <= almost_full;
    rd_rst_busy <= '0';
    sbiterr <= '0';
    underflow <= '0';
    wr_ack <= wr_en and not full;
    wr_rst_busy <= '0';

    fifo_i : radhdl_fifo_async
      generic map (
        VENDOR => VENDOR,
        DEVICE_FAMILY => DEVICE_FAMILY,
        FIFO_READ_LATENCY => FIFO_READ_LATENCY,
        FIFO_WRITE_DEPTH => FIFO_WRITE_DEPTH,
        RD_DATA_COUNT_WIDTH => RD_DATA_COUNT_WIDTH,
        READ_DATA_WIDTH => READ_DATA_WIDTH,
        READ_MODE => READ_MODE,
        WRITE_DATA_WIDTH => WRITE_DATA_WIDTH,
        WR_DATA_COUNT_WIDTH => WR_DATA_COUNT_WIDTH
      )
      port map (
        almost_empty => almost_empty,
        almost_full => almost_full,
        data_valid => data_valid,
        dout => dout,
        empty => empty,
        full => full,
        rd_data_count => rd_data_count,
        wr_data_count => wr_data_count,
        din => din,
        rd_clk => rd_clk,
        rd_en => rd_en,
        rst => rst,
        wr_clk => wr_clk,
        wr_en => wr_en
      );
  end generate;
end architecture;
