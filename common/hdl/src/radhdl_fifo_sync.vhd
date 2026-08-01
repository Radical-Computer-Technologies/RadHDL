library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Vendor-selected synchronous FIFO with XPM-compatible ports. Portable cores
-- instantiate this wrapper, not XPM or raw ECP5 storage directly.
entity radhdl_fifo_sync is
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
end entity;

architecture rtl of radhdl_fifo_sync is
  constant C_IS_XILINX : boolean := VENDOR = "xilinx" or VENDOR = "XILINX";
  constant C_IS_GOWIN : boolean := VENDOR = "gowin" or VENDOR = "GOWIN";
  constant C_IS_LATTICE_XO : boolean :=
    VENDOR = "machxo2" or VENDOR = "MACHXO2" or VENDOR = "machxo3" or VENDOR = "MACHXO3" or
    DEVICE_FAMILY = "xo2" or DEVICE_FAMILY = "XO2" or DEVICE_FAMILY = "xo3" or DEVICE_FAMILY = "XO3" or
    DEVICE_FAMILY = "machxo2" or DEVICE_FAMILY = "MACHXO2" or DEVICE_FAMILY = "machxo3" or DEVICE_FAMILY = "MACHXO3";
  constant C_IS_ECP5 : boolean :=
    VENDOR = "ecp5" or VENDOR = "ECP5" or DEVICE_FAMILY = "ecp5" or DEVICE_FAMILY = "ECP5";

  component radhdl_xilinx_fifo_sync is
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
  end component;

  component radhdl_gowin_fifo_sc_sync is
    generic (
      DATA_WIDTH  : positive := 32;
      COUNT_WIDTH : positive := 10
    );
    port (
      clk          : in  std_logic;
      rst          : in  std_logic;
      wr_en        : in  std_logic;
      rd_en        : in  std_logic;
      din          : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      dout         : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      empty        : out std_logic;
      full         : out std_logic;
      almost_empty : out std_logic;
      almost_full  : out std_logic;
      data_valid   : out std_logic;
      data_count   : out std_logic_vector(COUNT_WIDTH - 1 downto 0)
    );
  end component;

  component radhdl_lattice_fifo8kb is
    generic (
      DATA_WIDTH : positive := 18
    );
    port (
      wr_clk       : in  std_logic;
      rd_clk       : in  std_logic;
      rst          : in  std_logic;
      wr_en        : in  std_logic;
      rd_en        : in  std_logic;
      din          : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      dout         : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      empty        : out std_logic;
      full         : out std_logic;
      almost_empty : out std_logic;
      almost_full  : out std_logic;
      data_valid   : out std_logic
    );
  end component;

  component radhdl_fifo_bram_sync is
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
  end component;

  function max_positive(left : integer; right : integer) return positive is
  begin
    if left > right then
      return left;
    end if;
    return right;
  end function;

  function clog2(value : positive) return positive is
    variable result : positive := 1;
    variable power  : positive := 2;
  begin
    while power < value loop
      power := power * 2;
      result := result + 1;
    end loop;
    return result;
  end function;

  constant C_ADDR_WIDTH  : positive := clog2(FIFO_WRITE_DEPTH);
  constant C_COUNT_WIDTH : positive := max_positive(max_positive(WR_DATA_COUNT_WIDTH, RD_DATA_COUNT_WIDTH), C_ADDR_WIDTH + 1);
  signal count_vector    : std_logic_vector(C_COUNT_WIDTH - 1 downto 0);
  signal bram_count      : unsigned(C_ADDR_WIDTH downto 0);
  signal empty_i         : std_logic;
  signal full_i          : std_logic;
  signal almost_empty_i  : std_logic;
  signal almost_full_i   : std_logic;
begin
  assert C_IS_XILINX or C_IS_GOWIN or C_IS_LATTICE_XO or C_IS_ECP5
    report "radhdl_fifo_sync unsupported VENDOR/DEVICE_FAMILY"
    severity failure;
  assert READ_DATA_WIDTH = WRITE_DATA_WIDTH
    report "radhdl_fifo_sync currently requires equal read/write widths"
    severity failure;
  assert READ_MODE = "std" or READ_MODE = "fwft"
    report "radhdl_fifo_sync READ_MODE must be std or fwft"
    severity failure;
  assert (not C_IS_LATTICE_XO) or (READ_DATA_WIDTH <= 18 and WRITE_DATA_WIDTH <= 18)
    report "radhdl_fifo_sync Lattice FIFO8KB backend supports widths up to 18 bits"
    severity failure;

  dbiterr <= '0';
  overflow <= '0';
  rd_rst_busy <= '0';
  sbiterr <= '0';
  underflow <= '0';
  empty <= empty_i;
  full <= full_i;
  almost_empty <= almost_empty_i;
  almost_full <= almost_full_i;
  wr_ack <= wr_en and not full_i;
  wr_rst_busy <= '0';
  rd_data_count <= std_logic_vector(resize(unsigned(count_vector), RD_DATA_COUNT_WIDTH));
  wr_data_count <= std_logic_vector(resize(unsigned(count_vector), WR_DATA_COUNT_WIDTH));

  gen_xilinx : if C_IS_XILINX generate
  begin
    almost_empty_i <= empty_i;
    almost_full_i <= full_i;
    prog_empty <= empty_i;
    prog_full <= full_i;
    count_vector <= (others => '0');
    fifo_i : radhdl_xilinx_fifo_sync
      generic map (
        DATA_WIDTH => WRITE_DATA_WIDTH,
        FIFO_DEPTH => FIFO_WRITE_DEPTH,
        READ_MODE => READ_MODE,
        FIFO_READ_LATENCY => FIFO_READ_LATENCY,
        COUNT_WIDTH => C_COUNT_WIDTH
      )
      port map (
        clk => wr_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty_i,
        full => full_i,
        data_valid => data_valid
      );
  end generate;

  gen_gowin : if C_IS_GOWIN generate
  begin
    prog_empty <= almost_empty_i;
    prog_full <= almost_full_i;
    fifo_i : radhdl_gowin_fifo_sc_sync
      generic map (
        DATA_WIDTH => WRITE_DATA_WIDTH,
        COUNT_WIDTH => C_COUNT_WIDTH
      )
      port map (
        clk => wr_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty_i,
        full => full_i,
        almost_empty => almost_empty_i,
        almost_full => almost_full_i,
        data_valid => data_valid,
        data_count => count_vector
      );
  end generate;

  gen_lattice_xo : if C_IS_LATTICE_XO generate
  begin
    prog_empty <= almost_empty_i;
    prog_full <= almost_full_i;
    count_vector <= (others => '0');
    fifo_i : radhdl_lattice_fifo8kb
      generic map (
        DATA_WIDTH => WRITE_DATA_WIDTH
      )
      port map (
        wr_clk => wr_clk,
        rd_clk => wr_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty_i,
        full => full_i,
        almost_empty => almost_empty_i,
        almost_full => almost_full_i,
        data_valid => data_valid
      );
  end generate;

  gen_ecp5_unsupported : if C_IS_ECP5 generate
  begin
    almost_empty_i <= empty_i;
    almost_full_i <= full_i;
    prog_empty <= empty_i;
    prog_full <= full_i;
    count_vector <= std_logic_vector(resize(bram_count, C_COUNT_WIDTH));
    fifo_i : radhdl_fifo_bram_sync
      generic map (
        VENDOR => "lattice",
        DEVICE_FAMILY => "ecp5",
        DATA_WIDTH => WRITE_DATA_WIDTH,
        ADDR_WIDTH => C_ADDR_WIDTH,
        DEPTH => FIFO_WRITE_DEPTH,
        SIMULATION => SIM_ASSERT_CHK /= 0
      )
      port map (
        clk => wr_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty_i,
        full => full_i,
        data_valid => data_valid,
        count_o => bram_count
      );
  end generate;
end architecture;
