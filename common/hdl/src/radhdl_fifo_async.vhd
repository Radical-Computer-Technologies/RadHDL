library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Vendor-selected separate-clock FIFO with XPM-compatible ports.
entity radhdl_fifo_async is
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
end entity;

architecture rtl of radhdl_fifo_async is
  constant C_IS_XILINX : boolean := VENDOR = "xilinx" or VENDOR = "XILINX";
  constant C_IS_GOWIN : boolean := VENDOR = "gowin" or VENDOR = "GOWIN";
  constant C_IS_LATTICE_XO : boolean :=
    VENDOR = "machxo2" or VENDOR = "MACHXO2" or VENDOR = "machxo3" or VENDOR = "MACHXO3" or
    DEVICE_FAMILY = "xo2" or DEVICE_FAMILY = "XO2" or DEVICE_FAMILY = "xo3" or DEVICE_FAMILY = "XO3" or
    DEVICE_FAMILY = "machxo2" or DEVICE_FAMILY = "MACHXO2" or DEVICE_FAMILY = "machxo3" or DEVICE_FAMILY = "MACHXO3";
  constant C_IS_ECP5 : boolean :=
    VENDOR = "ecp5" or VENDOR = "ECP5" or DEVICE_FAMILY = "ecp5" or DEVICE_FAMILY = "ECP5";

  component radhdl_xilinx_fifo_async is
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
  end component;

  component radhdl_gowin_fifo_hs_async is
    generic (
      WRITE_DATA_WIDTH : positive := 32;
      READ_DATA_WIDTH  : positive := 32;
      WR_COUNT_WIDTH   : positive := 10;
      RD_COUNT_WIDTH   : positive := 10
    );
    port (
      wr_clk        : in  std_logic;
      rd_clk        : in  std_logic;
      rst           : in  std_logic;
      wr_en         : in  std_logic;
      rd_en         : in  std_logic;
      din           : in  std_logic_vector(WRITE_DATA_WIDTH - 1 downto 0);
      dout          : out std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
      empty         : out std_logic;
      full          : out std_logic;
      almost_empty  : out std_logic;
      almost_full   : out std_logic;
      data_valid    : out std_logic;
      wr_data_count : out std_logic_vector(WR_COUNT_WIDTH - 1 downto 0);
      rd_data_count : out std_logic_vector(RD_COUNT_WIDTH - 1 downto 0)
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

  component radhdl_fifo_bram_async is
    generic (
      VENDOR        : string   := "generic";
      DEVICE_FAMILY : string   := "generic";
      DATA_WIDTH    : positive := 32;
      ADDR_WIDTH    : positive := 4;
      DEPTH         : positive := 16;
      CDC_STAGES    : positive := 2;
      SIMULATION    : boolean  := false
    );
    port (
      wr_clk        : in  std_logic;
      rd_clk        : in  std_logic;
      rst           : in  std_logic;
      wr_en         : in  std_logic;
      rd_en         : in  std_logic;
      din           : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      dout          : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      empty         : out std_logic;
      full          : out std_logic;
      data_valid    : out std_logic;
      wr_data_count : out unsigned(ADDR_WIDTH downto 0);
      rd_data_count : out unsigned(ADDR_WIDTH downto 0)
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
  signal bram_wr_count   : unsigned(C_ADDR_WIDTH downto 0);
  signal bram_rd_count   : unsigned(C_ADDR_WIDTH downto 0);
begin
  assert C_IS_XILINX or C_IS_GOWIN or C_IS_LATTICE_XO or C_IS_ECP5
    report "radhdl_fifo_async unsupported VENDOR/DEVICE_FAMILY"
    severity failure;
  assert (C_IS_GOWIN) or (READ_DATA_WIDTH = WRITE_DATA_WIDTH)
    report "radhdl_fifo_async non-Gowin backends currently require equal read/write widths"
    severity failure;
  assert (not C_IS_LATTICE_XO) or (READ_DATA_WIDTH <= 18 and WRITE_DATA_WIDTH <= 18)
    report "radhdl_fifo_async Lattice FIFO8KB backend supports widths up to 18 bits"
    severity failure;

  gen_xilinx : if C_IS_XILINX generate
  begin
    almost_empty <= empty;
    almost_full <= full;
    rd_data_count <= (others => '0');
    wr_data_count <= (others => '0');
    fifo_i : radhdl_xilinx_fifo_async
      generic map (
        DATA_WIDTH => WRITE_DATA_WIDTH,
        FIFO_DEPTH => FIFO_WRITE_DEPTH,
        READ_MODE => READ_MODE,
        FIFO_READ_LATENCY => FIFO_READ_LATENCY,
        COUNT_WIDTH => WR_DATA_COUNT_WIDTH
      )
      port map (
        wr_clk => wr_clk,
        rd_clk => rd_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty,
        full => full,
        data_valid => data_valid
      );
  end generate;

  gen_gowin : if C_IS_GOWIN generate
  begin
    fifo_i : radhdl_gowin_fifo_hs_async
      generic map (
        WRITE_DATA_WIDTH => WRITE_DATA_WIDTH,
        READ_DATA_WIDTH => READ_DATA_WIDTH,
        WR_COUNT_WIDTH => WR_DATA_COUNT_WIDTH,
        RD_COUNT_WIDTH => RD_DATA_COUNT_WIDTH
      )
      port map (
        wr_clk => wr_clk,
        rd_clk => rd_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty,
        full => full,
        almost_empty => almost_empty,
        almost_full => almost_full,
        data_valid => data_valid,
        wr_data_count => wr_data_count,
        rd_data_count => rd_data_count
      );
  end generate;

  gen_lattice_xo : if C_IS_LATTICE_XO generate
  begin
    rd_data_count <= (others => '0');
    wr_data_count <= (others => '0');
    fifo_i : radhdl_lattice_fifo8kb
      generic map (
        DATA_WIDTH => WRITE_DATA_WIDTH
      )
      port map (
        wr_clk => wr_clk,
        rd_clk => rd_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty,
        full => full,
        almost_empty => almost_empty,
        almost_full => almost_full,
        data_valid => data_valid
      );
  end generate;

  gen_ecp5_unsupported : if C_IS_ECP5 generate
  begin
    almost_empty <= empty;
    almost_full <= full;
    rd_data_count <= std_logic_vector(resize(bram_rd_count, RD_DATA_COUNT_WIDTH));
    wr_data_count <= std_logic_vector(resize(bram_wr_count, WR_DATA_COUNT_WIDTH));
    fifo_i : radhdl_fifo_bram_async
      generic map (
        VENDOR => "lattice",
        DEVICE_FAMILY => "ecp5",
        DATA_WIDTH => WRITE_DATA_WIDTH,
        ADDR_WIDTH => C_ADDR_WIDTH,
        DEPTH => FIFO_WRITE_DEPTH,
        CDC_STAGES => 2,
        SIMULATION => false
      )
      port map (
        wr_clk => wr_clk,
        rd_clk => rd_clk,
        rst => rst,
        wr_en => wr_en,
        rd_en => rd_en,
        din => din,
        dout => dout,
        empty => empty,
        full => full,
        data_valid => data_valid,
        wr_data_count => bram_wr_count,
        rd_data_count => bram_rd_count
      );
  end generate;
end architecture;
