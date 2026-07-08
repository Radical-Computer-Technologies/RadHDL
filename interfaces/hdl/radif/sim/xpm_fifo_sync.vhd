library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Portable simulation model for the subset of xpm_fifo_sync used by RadHDL.
-- This model is intentionally small and vendor-neutral; synthesis should use
-- the vendor primitive or a proper implementation selected by the build flow.
entity xpm_fifo_sync is
  generic (
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
end entity;

architecture sim of xpm_fifo_sync is
  constant DEPTH : positive := FIFO_WRITE_DEPTH;
  constant DATA_WIDTH : positive := WRITE_DATA_WIDTH;
  type mem_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal mem : mem_t := (others => (others => '0'));
  signal wr_ptr : natural range 0 to DEPTH - 1 := 0;
  signal rd_ptr : natural range 0 to DEPTH - 1 := 0;
  signal count : natural range 0 to DEPTH := 0;
  signal data_valid_r : std_logic := '0';
  signal overflow_r : std_logic := '0';
  signal underflow_r : std_logic := '0';

  function inc_ptr(value : natural) return natural is
  begin
    if value = DEPTH - 1 then
      return 0;
    end if;
    return value + 1;
  end function;

  function count_vector(value : natural; width : natural) return std_logic_vector is
  begin
    if width = 0 then
      return "";
    end if;
    return std_logic_vector(to_unsigned(value, width));
  end function;
begin
  assert WRITE_DATA_WIDTH = READ_DATA_WIDTH
    report "portable xpm_fifo_sync model requires equal read/write widths"
    severity failure;

  empty <= '1' when count = 0 else '0';
  full <= '1' when count = DEPTH else '0';
  almost_empty <= '1' when count <= 1 else '0';
  almost_full <= '1' when count >= DEPTH - 1 else '0';
  prog_empty <= '1' when count <= PROG_EMPTY_THRESH else '0';
  prog_full <= '1' when count >= PROG_FULL_THRESH else '0';
  data_valid <= data_valid_r when READ_MODE /= "fwft" else '1' when count > 0 else '0';
  dout <= mem(rd_ptr)(READ_DATA_WIDTH - 1 downto 0) when count > 0 else (others => '0');
  dbiterr <= '0';
  sbiterr <= '0';
  rd_rst_busy <= rst;
  wr_rst_busy <= rst;
  overflow <= overflow_r;
  underflow <= underflow_r;
  wr_ack <= wr_en when count < DEPTH and rst = '0' else '0';
  rd_data_count <= count_vector(count, RD_DATA_COUNT_WIDTH);
  wr_data_count <= count_vector(count, WR_DATA_COUNT_WIDTH);

  process(wr_clk)
    variable next_count : natural range 0 to DEPTH;
    variable did_read : boolean;
    variable did_write : boolean;
  begin
    if rising_edge(wr_clk) then
      data_valid_r <= '0';
      overflow_r <= '0';
      underflow_r <= '0';

      if rst = '1' then
        wr_ptr <= 0;
        rd_ptr <= 0;
        count <= 0;
      elsif sleep = '0' then
        next_count := count;
        did_read := false;
        did_write := false;

        if rd_en = '1' then
          if count > 0 then
            rd_ptr <= inc_ptr(rd_ptr);
            next_count := next_count - 1;
            did_read := true;
          else
            underflow_r <= '1';
          end if;
        end if;

        if wr_en = '1' then
          if count < DEPTH then
            mem(wr_ptr) <= din;
            wr_ptr <= inc_ptr(wr_ptr);
            next_count := next_count + 1;
            did_write := true;
          else
            overflow_r <= '1';
          end if;
        end if;

        if did_read and not did_write and count > 0 then
          data_valid_r <= '1';
        end if;

        count <= next_count;
      end if;
    end if;
  end process;
end architecture;
