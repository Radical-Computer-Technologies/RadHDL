library ieee;
use ieee.std_logic_1164.all;

-- Lattice MachXO2/MachXO3 FIFO8KB primitive wrapper.
-- This is intentionally a primitive wrapper, not a RAM-inferred FIFO.
entity radhdl_lattice_fifo8kb is
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
end entity;

architecture primitive of radhdl_lattice_fifo8kb is
  component FIFO8KB is
    generic (
      DATA_WIDTH_W       : integer := 18;
      DATA_WIDTH_R       : integer := 18;
      REGMODE            : string  := "NOREG";
      RESETMODE          : string  := "ASYNC";
      ASYNC_RESET_RELEASE: string  := "SYNC";
      CSDECODE_W         : string  := "0b00";
      CSDECODE_R         : string  := "0b00";
      AEPOINTER          : string  := "0b00000000000000";
      AEPOINTER1         : string  := "0b00000000000000";
      AFPOINTER          : string  := "0b00000000000000";
      AFPOINTER1         : string  := "0b00000000000000";
      FULLPOINTER        : string  := "0b00000000000000";
      FULLPOINTER1       : string  := "0b00000000000000";
      GSR                : string  := "DISABLED"
    );
    port (
      DI0    : in  std_logic;
      DI1    : in  std_logic;
      DI2    : in  std_logic;
      DI3    : in  std_logic;
      DI4    : in  std_logic;
      DI5    : in  std_logic;
      DI6    : in  std_logic;
      DI7    : in  std_logic;
      DI8    : in  std_logic;
      DI9    : in  std_logic;
      DI10   : in  std_logic;
      DI11   : in  std_logic;
      DI12   : in  std_logic;
      DI13   : in  std_logic;
      DI14   : in  std_logic;
      DI15   : in  std_logic;
      DI16   : in  std_logic;
      DI17   : in  std_logic;
      CSW0   : in  std_logic;
      CSW1   : in  std_logic;
      CSR0   : in  std_logic;
      CSR1   : in  std_logic;
      WE     : in  std_logic;
      RE     : in  std_logic;
      ORE    : in  std_logic;
      CLKW   : in  std_logic;
      CLKR   : in  std_logic;
      RST    : in  std_logic;
      RPRST  : in  std_logic;
      FULLI  : in  std_logic;
      EMPTYI : in  std_logic;
      DO0    : out std_logic;
      DO1    : out std_logic;
      DO2    : out std_logic;
      DO3    : out std_logic;
      DO4    : out std_logic;
      DO5    : out std_logic;
      DO6    : out std_logic;
      DO7    : out std_logic;
      DO8    : out std_logic;
      DO9    : out std_logic;
      DO10   : out std_logic;
      DO11   : out std_logic;
      DO12   : out std_logic;
      DO13   : out std_logic;
      DO14   : out std_logic;
      DO15   : out std_logic;
      DO16   : out std_logic;
      DO17   : out std_logic;
      EF     : out std_logic;
      AEF    : out std_logic;
      AFF    : out std_logic;
      FF     : out std_logic
    );
  end component;

  signal di18      : std_logic_vector(17 downto 0) := (others => '0');
  signal do18      : std_logic_vector(17 downto 0);
  signal rd_fire_r : std_logic := '0';
  signal empty_s   : std_logic;
  signal full_s    : std_logic;
begin
  assert DATA_WIDTH = 1 or DATA_WIDTH = 2 or DATA_WIDTH = 4 or DATA_WIDTH = 9 or DATA_WIDTH = 18
    report "radhdl_lattice_fifo8kb DATA_WIDTH must be one of 1, 2, 4, 9, or 18"
    severity failure;

  di18(DATA_WIDTH - 1 downto 0) <= din;
  dout <= do18(DATA_WIDTH - 1 downto 0);
  empty <= empty_s;
  full <= full_s;
  data_valid <= rd_fire_r;

  fifo_i : FIFO8KB
    generic map (
      DATA_WIDTH_W => DATA_WIDTH,
      DATA_WIDTH_R => DATA_WIDTH,
      REGMODE => "NOREG",
      RESETMODE => "ASYNC",
      ASYNC_RESET_RELEASE => "SYNC",
      CSDECODE_W => "0b00",
      CSDECODE_R => "0b00",
      GSR => "DISABLED"
    )
    port map (
      DI0 => di18(0), DI1 => di18(1), DI2 => di18(2), DI3 => di18(3),
      DI4 => di18(4), DI5 => di18(5), DI6 => di18(6), DI7 => di18(7),
      DI8 => di18(8), DI9 => di18(9), DI10 => di18(10), DI11 => di18(11),
      DI12 => di18(12), DI13 => di18(13), DI14 => di18(14), DI15 => di18(15),
      DI16 => di18(16), DI17 => di18(17),
      CSW0 => '0', CSW1 => '0', CSR0 => '0', CSR1 => '0',
      WE => wr_en,
      RE => rd_en,
      ORE => '1',
      CLKW => wr_clk,
      CLKR => rd_clk,
      RST => rst,
      RPRST => rst,
      FULLI => '0',
      EMPTYI => '0',
      DO0 => do18(0), DO1 => do18(1), DO2 => do18(2), DO3 => do18(3),
      DO4 => do18(4), DO5 => do18(5), DO6 => do18(6), DO7 => do18(7),
      DO8 => do18(8), DO9 => do18(9), DO10 => do18(10), DO11 => do18(11),
      DO12 => do18(12), DO13 => do18(13), DO14 => do18(14), DO15 => do18(15),
      DO16 => do18(16), DO17 => do18(17),
      EF => empty_s,
      AEF => almost_empty,
      AFF => almost_full,
      FF => full_s
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
