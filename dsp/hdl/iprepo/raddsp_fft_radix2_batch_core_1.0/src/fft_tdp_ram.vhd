library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

-- Xilinx RAMB36 lane wrapper used by wide FFT memory banks.
-- Packages one physical memory lane behind a simple synchronous dual-port interface for generated FFT structures.
entity fft_ramb36_lane is
  generic (
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY : string := "ultrascale+"
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk    : in  std_logic;
    -- A addr interface signal.
    a_addr : in  std_logic_vector(9 downto 0);
    -- A din interface signal.
    a_din  : in  std_logic_vector(31 downto 0);
    -- A dout interface signal.
    a_dout : out std_logic_vector(31 downto 0);
    -- A en interface signal.
    a_en   : in  std_logic;
    -- A we interface signal.
    a_we   : in  std_logic;
    -- B addr interface signal.
    b_addr : in  std_logic_vector(9 downto 0);
    -- B din interface signal.
    b_din  : in  std_logic_vector(31 downto 0);
    -- B dout interface signal.
    b_dout : out std_logic_vector(31 downto 0);
    -- B en interface signal.
    b_en   : in  std_logic;
    -- B we interface signal.
    b_we   : in  std_logic
  );
end entity;

architecture rtl of fft_ramb36_lane is
  signal e2_addr_a : std_logic_vector(14 downto 0);
  signal e2_addr_b : std_logic_vector(14 downto 0);
  signal e1_addr_a : std_logic_vector(15 downto 0);
  signal e1_addr_b : std_logic_vector(15 downto 0);
  signal we_a4     : std_logic_vector(3 downto 0);
  signal we_b8     : std_logic_vector(7 downto 0);
begin
  e2_addr_a <= a_addr & "00000";
  e2_addr_b <= b_addr & "00000";
  e1_addr_a <= a_addr & "000000";
  e1_addr_b <= b_addr & "000000";
  we_a4 <= (others => a_we);
  we_b8 <= (others => b_we);

  gen_e2 : if DEVICE_FAMILY = "ultrascale+" or DEVICE_FAMILY = "ultrascale" generate
    ram : RAMB36E2
      generic map (
        CLOCK_DOMAINS => "COMMON",
        DOA_REG => 0,
        DOB_REG => 0,
        READ_WIDTH_A => 36,
        READ_WIDTH_B => 36,
        WRITE_WIDTH_A => 36,
        WRITE_WIDTH_B => 36,
        WRITE_MODE_A => "READ_FIRST",
        WRITE_MODE_B => "READ_FIRST"
      )
      port map (
        CASDOUTA => open, CASDOUTB => open, CASDOUTPA => open, CASDOUTPB => open,
        CASOUTDBITERR => open, CASOUTSBITERR => open, DBITERR => open,
        DOUTADOUT => a_dout, DOUTBDOUT => b_dout, DOUTPADOUTP => open, DOUTPBDOUTP => open,
        ECCPARITY => open, RDADDRECC => open, SBITERR => open,
        ADDRARDADDR => e2_addr_a, ADDRBWRADDR => e2_addr_b,
        ADDRENA => '1', ADDRENB => '1', CASDIMUXA => '0', CASDIMUXB => '0',
        CASDINA => (others => '0'), CASDINB => (others => '0'),
        CASDINPA => (others => '0'), CASDINPB => (others => '0'),
        CASDOMUXA => '0', CASDOMUXB => '0', CASDOMUXEN_A => '0', CASDOMUXEN_B => '0',
        CASINDBITERR => '0', CASINSBITERR => '0',
        CASOREGIMUXA => '0', CASOREGIMUXB => '0', CASOREGIMUXEN_A => '0', CASOREGIMUXEN_B => '0',
        CLKARDCLK => clk, CLKBWRCLK => clk,
        DINADIN => a_din, DINBDIN => b_din,
        DINPADINP => (others => '0'), DINPBDINP => (others => '0'),
        ECCPIPECE => '0', ENARDEN => a_en, ENBWREN => b_en,
        INJECTDBITERR => '0', INJECTSBITERR => '0',
        REGCEAREGCE => '1', REGCEB => '1',
        RSTRAMARSTRAM => '0', RSTRAMB => '0', RSTREGARSTREG => '0', RSTREGB => '0',
        SLEEP => '0', WEA => we_a4, WEBWE => we_b8
      );
  end generate;

  gen_e1 : if not (DEVICE_FAMILY = "ultrascale+" or DEVICE_FAMILY = "ultrascale") generate
    ram : RAMB36E1
      generic map (
        DOA_REG => 0,
        DOB_REG => 0,
        RAM_MODE => "TDP",
        READ_WIDTH_A => 36,
        READ_WIDTH_B => 36,
        WRITE_WIDTH_A => 36,
        WRITE_WIDTH_B => 36,
        WRITE_MODE_A => "READ_FIRST",
        WRITE_MODE_B => "READ_FIRST"
      )
      port map (
        CASCADEOUTA => open, CASCADEOUTB => open, DBITERR => open,
        DOADO => a_dout, DOBDO => b_dout, DOPADOP => open, DOPBDOP => open,
        ECCPARITY => open, RDADDRECC => open, SBITERR => open,
        ADDRARDADDR => e1_addr_a, ADDRBWRADDR => e1_addr_b,
        CASCADEINA => '0', CASCADEINB => '0',
        CLKARDCLK => clk, CLKBWRCLK => clk,
        DIADI => a_din, DIBDI => b_din,
        DIPADIP => (others => '0'), DIPBDIP => (others => '0'),
        ENARDEN => a_en, ENBWREN => b_en,
        INJECTDBITERR => '0', INJECTSBITERR => '0',
        REGCEAREGCE => '1', REGCEB => '1',
        RSTRAMARSTRAM => '0', RSTRAMB => '0', RSTREGARSTREG => '0', RSTREGB => '0',
        WEA => we_a4, WEBWE => we_b8
      );
  end generate;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- True dual-port RAM abstraction used by FFT pipeline memories.
-- Keeps storage portable while allowing vendor-specific implementations to infer or instantiate block RAM efficiently.
entity fft_tdp_ram is
  generic (
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY : string := "ultrascale+";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH    : integer := 64;
    -- Sets the bit width for ADDR WIDTH values carried by this module.
    ADDR_WIDTH    : integer := 5;
    -- Sets the storage depth, frame length, or number of buffered samples used internally.
    DEPTH         : integer := 32
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk    : in  std_logic;
    -- A addr interface signal.
    a_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- A din interface signal.
    a_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- A dout interface signal.
    a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- A we interface signal.
    a_we   : in  std_logic;
    -- B addr interface signal.
    b_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- B din interface signal.
    b_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- B dout interface signal.
    b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- B we interface signal.
    b_we   : in  std_logic
  );
end entity;

architecture rtl of fft_tdp_ram is
  signal a_low_addr : std_logic_vector(9 downto 0);
  signal b_low_addr : std_logic_vector(9 downto 0);
  signal a_bank     : std_logic;
  signal b_bank     : std_logic;
  signal a_bank_q   : std_logic := '0';
  signal b_bank_q   : std_logic := '0';
  signal a_en0      : std_logic;
  signal a_en1      : std_logic;
  signal b_en0      : std_logic;
  signal b_en1      : std_logic;
  signal a_we0      : std_logic;
  signal a_we1      : std_logic;
  signal b_we0      : std_logic;
  signal b_we1      : std_logic;
  signal a_lo0      : std_logic_vector(31 downto 0);
  signal a_hi0      : std_logic_vector(31 downto 0);
  signal b_lo0      : std_logic_vector(31 downto 0);
  signal b_hi0      : std_logic_vector(31 downto 0);
  signal a_lo1      : std_logic_vector(31 downto 0) := (others => '0');
  signal a_hi1      : std_logic_vector(31 downto 0) := (others => '0');
  signal b_lo1      : std_logic_vector(31 downto 0) := (others => '0');
  signal b_hi1      : std_logic_vector(31 downto 0) := (others => '0');

  function low_addr(addr : std_logic_vector) return std_logic_vector is
    variable ret : std_logic_vector(9 downto 0) := (others => '0');
  begin
    if addr'length >= 10 then
      ret := addr(9 downto 0);
    else
      ret(addr'length - 1 downto 0) := addr;
    end if;
    return ret;
  end function;

  function bank_addr(addr : std_logic_vector) return std_logic is
  begin
    if addr'length > 10 then
      return addr(10);
    end if;
    return '0';
  end function;
begin
  assert DATA_WIDTH = 64 report "fft_tdp_ram currently expects a 64-bit packed complex word" severity failure;
  assert DEPTH <= 2048 report "fft_tdp_ram supports up to 2048 packed complex words" severity failure;

  a_low_addr <= low_addr(a_addr);
  b_low_addr <= low_addr(b_addr);
  a_bank <= bank_addr(a_addr) when DEPTH > 1024 else '0';
  b_bank <= bank_addr(b_addr) when DEPTH > 1024 else '0';
  a_en0 <= '1' when a_bank = '0' else '0';
  a_en1 <= '1' when a_bank = '1' else '0';
  b_en0 <= '1' when b_bank = '0' else '0';
  b_en1 <= '1' when b_bank = '1' else '0';
  a_we0 <= a_we and a_en0;
  a_we1 <= a_we and a_en1;
  b_we0 <= b_we and b_en0;
  b_we1 <= b_we and b_en1;

  process(clk)
  begin
    if rising_edge(clk) then
      a_bank_q <= a_bank;
      b_bank_q <= b_bank;
    end if;
  end process;

  a_dout <= (a_hi1 & a_lo1) when a_bank_q = '1' else (a_hi0 & a_lo0);
  b_dout <= (b_hi1 & b_lo1) when b_bank_q = '1' else (b_hi0 & b_lo0);

  bank0_lo: entity work.fft_ramb36_lane
    generic map (DEVICE_FAMILY => DEVICE_FAMILY)
    port map (clk, a_low_addr, a_din(31 downto 0), a_lo0, a_en0, a_we0,
              b_low_addr, b_din(31 downto 0), b_lo0, b_en0, b_we0);
  bank0_hi: entity work.fft_ramb36_lane
    generic map (DEVICE_FAMILY => DEVICE_FAMILY)
    port map (clk, a_low_addr, a_din(63 downto 32), a_hi0, a_en0, a_we0,
              b_low_addr, b_din(63 downto 32), b_hi0, b_en0, b_we0);

  gen_bank1 : if DEPTH > 1024 generate
    bank1_lo: entity work.fft_ramb36_lane
      generic map (DEVICE_FAMILY => DEVICE_FAMILY)
      port map (clk, a_low_addr, a_din(31 downto 0), a_lo1, a_en1, a_we1,
                b_low_addr, b_din(31 downto 0), b_lo1, b_en1, b_we1);
    bank1_hi: entity work.fft_ramb36_lane
      generic map (DEVICE_FAMILY => DEVICE_FAMILY)
      port map (clk, a_low_addr, a_din(63 downto 32), a_hi1, a_en1, a_we1,
                b_low_addr, b_din(63 downto 32), b_hi1, b_en1, b_we1);
  end generate;
end architecture;
