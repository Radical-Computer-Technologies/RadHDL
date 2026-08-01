library ieee;
use ieee.std_logic_1164.all;

-- Gowin separate-clock FIFO wrapper.
-- Expects a Gowin-generated FIFO_HS_Top module in the project. Generate it
-- with matching widths/depths, independent write/read reset ports, and
-- optional count/almost flags enabled.
entity radhdl_gowin_fifo_hs_async is
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
end entity;

architecture ip of radhdl_gowin_fifo_hs_async is
  component FIFO_HS_Top is
    port (
      Data         : in  std_logic_vector(WRITE_DATA_WIDTH - 1 downto 0);
      WrReset      : in  std_logic;
      RdReset      : in  std_logic;
      WrClk        : in  std_logic;
      RdClk        : in  std_logic;
      WrEn         : in  std_logic;
      RdEn         : in  std_logic;
      Wnum         : out std_logic_vector(WR_COUNT_WIDTH - 1 downto 0);
      Rnum         : out std_logic_vector(RD_COUNT_WIDTH - 1 downto 0);
      Almost_Empty : out std_logic;
      Almost_Full  : out std_logic;
      Q            : out std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
      Empty        : out std_logic;
      Full         : out std_logic
    );
  end component;

  signal empty_s   : std_logic;
  signal full_s    : std_logic;
  signal rd_fire_r : std_logic := '0';
begin
  empty <= empty_s;
  full <= full_s;
  data_valid <= rd_fire_r;

  fifo_i : FIFO_HS_Top
    port map (
      Data => din,
      WrReset => rst,
      RdReset => rst,
      WrClk => wr_clk,
      RdClk => rd_clk,
      WrEn => wr_en,
      RdEn => rd_en,
      Wnum => wr_data_count,
      Rnum => rd_data_count,
      Almost_Empty => almost_empty,
      Almost_Full => almost_full,
      Q => dout,
      Empty => empty_s,
      Full => full_s
    );

  process(rd_clk)
  begin
    if rising_edge(rd_clk) then
      if rst = '1' then
        rd_fire_r <= '0';
      else
        rd_fire_r <= rd_en and not empty_s;
      end if;
    end if;
  end process;
end architecture;
