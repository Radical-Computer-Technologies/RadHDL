library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- True dual-port RAM abstraction used by FFT pipeline memories.
-- Keeps storage portable while routing synthesis through explicit vendor RAM wrappers.
entity fft_tdp_ram is
  generic (
    -- Selects the vendor RAM wrapper.
    VENDOR        : string := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY : string := "ultrascale+";
    -- Configures MEMORY STYLE for this instance.
    MEMORY_STYLE  : string := "block";
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
  component radhdl_ram is
    generic (
      VENDOR           : string   := "xilinx";
      DEVICE_FAMILY    : string   := "7series";
      MODE             : string   := "tdp";
      MEMORY_KIND      : string   := "bram";
      DATA_WIDTH       : positive := 18;
      ADDR_WIDTH       : positive := 10;
      DEPTH            : positive := 1024;
      CLOCKING_MODE    : string   := "common_clock";
      MEMORY_INIT_FILE : string   := "none";
      USE_MEM_INIT     : integer  := 0;
      SIMULATION       : boolean  := false
    );
    port (
      clka : in std_logic; rsta : in std_logic; a_addr : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
      a_din : in std_logic_vector(DATA_WIDTH - 1 downto 0); a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0); a_we : in std_logic;
      clkb : in std_logic; rstb : in std_logic; b_addr : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
      b_din : in std_logic_vector(DATA_WIDTH - 1 downto 0); b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0); b_we : in std_logic
    );
  end component;
begin
  assert MEMORY_STYLE = "auto" or MEMORY_STYLE = "block" or MEMORY_STYLE = "distributed" or MEMORY_STYLE = "ultra"
    report "fft_tdp_ram MEMORY_STYLE must be auto, block, distributed, or ultra"
    severity failure;
  assert DATA_WIDTH > 0 report "fft_tdp_ram DATA_WIDTH must be positive" severity failure;
  assert ADDR_WIDTH > 0 report "fft_tdp_ram ADDR_WIDTH must be positive" severity failure;
  assert DEPTH > 0 report "fft_tdp_ram DEPTH must be positive" severity failure;

  ram_i : radhdl_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      MODE => "tdp",
      MEMORY_KIND => MEMORY_STYLE,
      DATA_WIDTH => DATA_WIDTH,
      ADDR_WIDTH => ADDR_WIDTH,
      DEPTH => DEPTH,
      CLOCKING_MODE => "common_clock"
    )
    port map (
      clka => clk, rsta => '0', a_addr => a_addr, a_din => a_din, a_dout => a_dout, a_we => a_we,
      clkb => clk, rstb => '0', b_addr => b_addr, b_din => b_din, b_dout => b_dout, b_we => b_we
    );
end architecture;
