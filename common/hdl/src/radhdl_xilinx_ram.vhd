library ieee;
use ieee.std_logic_1164.all;

library xpm;
use xpm.vcomponents.all;

-- Xilinx RAM wrapper. XPM imports stay isolated here so portable cores can
-- select this wrapper without directly depending on the XPM library.
entity radhdl_xilinx_ram is
  generic (
    DATA_WIDTH      : positive := 18;
    ADDR_WIDTH      : positive := 10;
    DEPTH           : positive := 1024;
    MEMORY_STYLE    : string   := "block";
    CLOCKING_MODE   : string   := "common_clock";
    MEMORY_INIT_FILE : string  := "none";
    USE_MEM_INIT    : integer  := 0
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

architecture rtl of radhdl_xilinx_ram is
  function write_mode_for_style(memory_style : string) return string is
  begin
    if memory_style = "ultra" then
      return "no_change";
    end if;
    return "read_first";
  end function;

  signal a_we_v : std_logic_vector(0 downto 0);
  signal b_we_v : std_logic_vector(0 downto 0);
begin
  a_we_v(0) <= a_we;
  b_we_v(0) <= b_we;

  ram_i : xpm_memory_tdpram
    generic map (
      MEMORY_SIZE => DATA_WIDTH * DEPTH,
      MEMORY_PRIMITIVE => MEMORY_STYLE,
      CLOCKING_MODE => CLOCKING_MODE,
      ECC_MODE => "no_ecc",
      ECC_TYPE => "none",
      MEMORY_INIT_FILE => MEMORY_INIT_FILE,
      MEMORY_INIT_PARAM => "0",
      USE_MEM_INIT => USE_MEM_INIT,
      WAKEUP_TIME => "disable_sleep",
      MESSAGE_CONTROL => 0,
      MEMORY_OPTIMIZATION => "true",
      CASCADE_HEIGHT => 0,
      WRITE_DATA_WIDTH_A => DATA_WIDTH,
      READ_DATA_WIDTH_A => DATA_WIDTH,
      BYTE_WRITE_WIDTH_A => DATA_WIDTH,
      ADDR_WIDTH_A => ADDR_WIDTH,
      READ_RESET_VALUE_A => "0",
      READ_LATENCY_A => 1,
      WRITE_MODE_A => write_mode_for_style(MEMORY_STYLE),
      RST_MODE_A => "SYNC",
      WRITE_DATA_WIDTH_B => DATA_WIDTH,
      READ_DATA_WIDTH_B => DATA_WIDTH,
      BYTE_WRITE_WIDTH_B => DATA_WIDTH,
      ADDR_WIDTH_B => ADDR_WIDTH,
      READ_RESET_VALUE_B => "0",
      READ_LATENCY_B => 1,
      WRITE_MODE_B => write_mode_for_style(MEMORY_STYLE),
      RST_MODE_B => "SYNC"
    )
    port map (
      sleep => '0',
      clka => clka,
      rsta => rsta,
      ena => '1',
      regcea => '1',
      wea => a_we_v,
      addra => a_addr,
      dina => a_din,
      injectsbiterra => '0',
      injectdbiterra => '0',
      douta => a_dout,
      sbiterra => open,
      dbiterra => open,
      clkb => clkb,
      rstb => rstb,
      enb => '1',
      regceb => '1',
      web => b_we_v,
      addrb => b_addr,
      dinb => b_din,
      injectsbiterrb => '0',
      injectdbiterrb => '0',
      doutb => b_dout,
      sbiterrb => open,
      dbiterrb => open
    );
end architecture;
