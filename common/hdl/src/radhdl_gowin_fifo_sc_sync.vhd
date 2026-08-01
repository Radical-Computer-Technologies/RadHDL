library ieee;
use ieee.std_logic_1164.all;

-- Gowin synchronous FIFO wrapper.
-- Expects a Gowin-generated FIFO_SC_Top module in the project. Generate it
-- with matching data width/depth and optional count/almost flags enabled.
entity radhdl_gowin_fifo_sc_sync is
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
end entity;

architecture ip of radhdl_gowin_fifo_sc_sync is
  component FIFO_SC_Top is
    port (
      Data         : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      Clk          : in  std_logic;
      WrEn         : in  std_logic;
      RdEn         : in  std_logic;
      Reset        : in  std_logic;
      Wnum         : out std_logic_vector(COUNT_WIDTH - 1 downto 0);
      Almost_Empty : out std_logic;
      Almost_Full  : out std_logic;
      Q            : out std_logic_vector(DATA_WIDTH - 1 downto 0);
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

  fifo_i : FIFO_SC_Top
    port map (
      Data => din,
      Clk => clk,
      WrEn => wr_en,
      RdEn => rd_en,
      Reset => rst,
      Wnum => data_count,
      Almost_Empty => almost_empty,
      Almost_Full => almost_full,
      Q => dout,
      Empty => empty_s,
      Full => full_s
    );

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        rd_fire_r <= '0';
      else
        rd_fire_r <= rd_en and not empty_s;
      end if;
    end if;
  end process;
end architecture;
