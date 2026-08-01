library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Public vendor-neutral RAM primitive.
-- This is the stable RadHDL RAM boundary; vendor-specific primitive wrappers stay below it.
entity radhdl_ram is
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
    clka   : in  std_logic;
    rsta   : in  std_logic;
    a_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    a_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    a_we   : in  std_logic;
    clkb   : in  std_logic;
    rstb   : in  std_logic;
    b_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    b_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    b_we   : in  std_logic
  );
end entity;

architecture rtl of radhdl_ram is
  constant C_IS_XILINX : boolean :=
    VENDOR = "xilinx" or VENDOR = "XILINX";
  constant C_IS_LATTICE : boolean :=
    VENDOR = "lattice" or VENDOR = "LATTICE" or VENDOR = "ecp5" or VENDOR = "ECP5" or
    DEVICE_FAMILY = "ecp5" or DEVICE_FAMILY = "ECP5";

  function xilinx_memory_style(kind : string) return string is
  begin
    if kind = "auto" or kind = "AUTO" then
      return "auto";
    elsif kind = "bram" or kind = "BRAM" or kind = "block" or kind = "BLOCK" then
      return "block";
    elsif kind = "uram" or kind = "URAM" or kind = "ultra" or kind = "ULTRA" then
      return "ultra";
    elsif kind = "distributed" or kind = "DISTRIBUTED" then
      return "distributed";
    end if;
    return kind;
  end function;

  signal a_we_i : std_logic;
  signal b_we_i : std_logic;

  component radhdl_xilinx_ram is
    generic (
      DATA_WIDTH       : positive := 18;
      ADDR_WIDTH       : positive := 10;
      DEPTH            : positive := 1024;
      MEMORY_STYLE     : string   := "block";
      CLOCKING_MODE    : string   := "common_clock";
      MEMORY_INIT_FILE : string   := "none";
      USE_MEM_INIT     : integer  := 0
    );
    port (
      clka   : in  std_logic;
      rsta   : in  std_logic;
      a_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      a_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      a_we   : in  std_logic;
      clkb   : in  std_logic;
      rstb   : in  std_logic;
      b_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      b_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      b_we   : in  std_logic
    );
  end component;

  component radhdl_lattice_ram is
    generic (
      DATA_WIDTH : positive := 18;
      ADDR_WIDTH : positive := 10;
      DEPTH      : positive := 1024;
      SIMULATION : boolean  := false
    );
    port (
      clka   : in  std_logic;
      rsta   : in  std_logic;
      a_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      a_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      a_we   : in  std_logic;
      clkb   : in  std_logic;
      rstb   : in  std_logic;
      b_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      b_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      b_we   : in  std_logic
    );
  end component;
begin
  assert C_IS_XILINX or C_IS_LATTICE
    report "radhdl_ram unsupported VENDOR; expected xilinx or lattice/ecp5"
    severity failure;
  assert MODE = "tdp" or MODE = "TDP" or MODE = "sdp" or MODE = "SDP" or MODE = "sp" or MODE = "SP" or MODE = "rom" or MODE = "ROM"
    report "radhdl_ram MODE must be tdp, sdp, sp, or rom"
    severity failure;
  assert MEMORY_KIND = "auto" or MEMORY_KIND = "AUTO" or
         MEMORY_KIND = "bram" or MEMORY_KIND = "BRAM" or MEMORY_KIND = "block" or MEMORY_KIND = "BLOCK" or
         MEMORY_KIND = "uram" or MEMORY_KIND = "URAM" or MEMORY_KIND = "ultra" or MEMORY_KIND = "ULTRA" or
         MEMORY_KIND = "distributed" or MEMORY_KIND = "DISTRIBUTED"
    report "radhdl_ram MEMORY_KIND must be auto, bram/block, uram/ultra, or distributed"
    severity failure;
  assert (not C_IS_LATTICE) or
         MEMORY_KIND = "auto" or MEMORY_KIND = "AUTO" or MEMORY_KIND = "bram" or MEMORY_KIND = "BRAM" or
         MEMORY_KIND = "block" or MEMORY_KIND = "BLOCK"
    report "radhdl_ram Lattice/ECP5 path currently supports only explicit BRAM/DP16KD storage"
    severity failure;
  assert (not C_IS_LATTICE) or USE_MEM_INIT = 0
    report "radhdl_ram Lattice/ECP5 memory initialization is not wired into DP16KD INITVAL yet"
    severity failure;
  a_we_i <= '0' when MODE = "rom" or MODE = "ROM" else a_we;
  b_we_i <= '0' when MODE = "sp" or MODE = "SP" or MODE = "sdp" or MODE = "SDP" or MODE = "rom" or MODE = "ROM" else b_we;

  gen_xilinx : if C_IS_XILINX generate
  begin
    ram_i : radhdl_xilinx_ram
      generic map (
        DATA_WIDTH => DATA_WIDTH,
        ADDR_WIDTH => ADDR_WIDTH,
        DEPTH => DEPTH,
        MEMORY_STYLE => xilinx_memory_style(MEMORY_KIND),
        CLOCKING_MODE => CLOCKING_MODE,
        MEMORY_INIT_FILE => MEMORY_INIT_FILE,
        USE_MEM_INIT => USE_MEM_INIT
      )
      port map (
        clka => clka,
        rsta => rsta,
        a_addr => a_addr,
        a_din => a_din,
        a_dout => a_dout,
        a_we => a_we_i,
        clkb => clkb,
        rstb => rstb,
        b_addr => b_addr,
        b_din => b_din,
        b_dout => b_dout,
        b_we => b_we_i
      );
  end generate;

  gen_lattice : if C_IS_LATTICE generate
  begin
    ram_i : radhdl_lattice_ram
      generic map (
        DATA_WIDTH => DATA_WIDTH,
        ADDR_WIDTH => ADDR_WIDTH,
        DEPTH => DEPTH,
        SIMULATION => SIMULATION
      )
      port map (
        clka => clka,
        rsta => rsta,
        a_addr => a_addr,
        a_din => a_din,
        a_dout => a_dout,
        a_we => a_we_i,
        clkb => clkb,
        rstb => rstb,
        b_addr => b_addr,
        b_din => b_din,
        b_dout => b_dout,
        b_we => b_we_i
      );
  end generate;
end architecture;
