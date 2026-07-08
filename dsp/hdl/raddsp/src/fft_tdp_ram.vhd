library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

-- True dual-port RAM abstraction used by FFT pipeline memories.
-- Keeps storage portable while allowing vendor-specific implementations to infer or instantiate block RAM efficiently.
entity fft_tdp_ram is
  generic (
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
  function min_positive(left : positive; right : positive) return positive is
  begin
    if left < right then
      return left;
    end if;
    return right;
  end function;

  function write_mode_for_style(memory_style : string) return string is
  begin
    if memory_style = "ultra" then
      return "no_change";
    end if;
    return "read_first";
  end function;

  constant C_PHYS_WIDTH : positive := 72;
  constant C_BANKS      : positive := (DATA_WIDTH + C_PHYS_WIDTH - 1) / C_PHYS_WIDTH;
begin
  assert MEMORY_STYLE = "auto" or MEMORY_STYLE = "block" or MEMORY_STYLE = "distributed" or MEMORY_STYLE = "ultra"
    report "fft_tdp_ram MEMORY_STYLE must be auto, block, distributed, or ultra"
    severity failure;
  assert DATA_WIDTH > 0 report "fft_tdp_ram DATA_WIDTH must be positive" severity failure;
  assert ADDR_WIDTH > 0 report "fft_tdp_ram ADDR_WIDTH must be positive" severity failure;
  assert DEPTH > 0 report "fft_tdp_ram DEPTH must be positive" severity failure;

  gen_xpm_banks : for bank in 0 to C_BANKS - 1 generate
    constant C_LO          : natural := bank * C_PHYS_WIDTH;
    constant C_REMAINING   : positive := DATA_WIDTH - C_LO;
    constant C_THIS_WIDTH  : positive := min_positive(C_PHYS_WIDTH, C_REMAINING);
    signal a_we_v          : std_logic_vector(0 downto 0);
    signal b_we_v          : std_logic_vector(0 downto 0);
    signal a_din_slice     : std_logic_vector(C_THIS_WIDTH - 1 downto 0);
    signal b_din_slice     : std_logic_vector(C_THIS_WIDTH - 1 downto 0);
    signal a_dout_slice    : std_logic_vector(C_THIS_WIDTH - 1 downto 0);
    signal b_dout_slice    : std_logic_vector(C_THIS_WIDTH - 1 downto 0);
  begin
    a_we_v(0) <= a_we;
    b_we_v(0) <= b_we;
    a_din_slice <= a_din(C_LO + C_THIS_WIDTH - 1 downto C_LO);
    b_din_slice <= b_din(C_LO + C_THIS_WIDTH - 1 downto C_LO);
    a_dout(C_LO + C_THIS_WIDTH - 1 downto C_LO) <= a_dout_slice;
    b_dout(C_LO + C_THIS_WIDTH - 1 downto C_LO) <= b_dout_slice;

    xpm_tdp_i: xpm_memory_tdpram
      generic map (
        MEMORY_SIZE => C_THIS_WIDTH * DEPTH,
        MEMORY_PRIMITIVE => MEMORY_STYLE,
        CLOCKING_MODE => "common_clock",
        ECC_MODE => "no_ecc",
        ECC_TYPE => "none",
        MEMORY_INIT_FILE => "none",
        MEMORY_INIT_PARAM => "0",
        USE_MEM_INIT => 0,
        WAKEUP_TIME => "disable_sleep",
        MESSAGE_CONTROL => 0,
        MEMORY_OPTIMIZATION => "true",
        CASCADE_HEIGHT => 0,
        WRITE_DATA_WIDTH_A => C_THIS_WIDTH,
        READ_DATA_WIDTH_A => C_THIS_WIDTH,
        BYTE_WRITE_WIDTH_A => C_THIS_WIDTH,
        ADDR_WIDTH_A => ADDR_WIDTH,
        READ_RESET_VALUE_A => "0",
        READ_LATENCY_A => 1,
        WRITE_MODE_A => write_mode_for_style(MEMORY_STYLE),
        RST_MODE_A => "SYNC",
        WRITE_DATA_WIDTH_B => C_THIS_WIDTH,
        READ_DATA_WIDTH_B => C_THIS_WIDTH,
        BYTE_WRITE_WIDTH_B => C_THIS_WIDTH,
        ADDR_WIDTH_B => ADDR_WIDTH,
        READ_RESET_VALUE_B => "0",
        READ_LATENCY_B => 1,
        WRITE_MODE_B => write_mode_for_style(MEMORY_STYLE),
        RST_MODE_B => "SYNC"
      )
      port map (
        sleep => '0',
        clka => clk,
        rsta => '0',
        ena => '1',
        regcea => '1',
        wea => a_we_v,
        addra => a_addr,
        dina => a_din_slice,
        injectsbiterra => '0',
        injectdbiterra => '0',
        douta => a_dout_slice,
        sbiterra => open,
        dbiterra => open,
        clkb => clk,
        rstb => '0',
        enb => '1',
        regceb => '1',
        web => b_we_v,
        addrb => b_addr,
        dinb => b_din_slice,
        injectsbiterrb => '0',
        injectdbiterrb => '0',
        doutb => b_dout_slice,
        sbiterrb => open,
        dbiterrb => open
      );
  end generate;
end architecture;
