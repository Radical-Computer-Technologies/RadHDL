library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Signed sample RAM wrapper for one write port and one read port.
entity radhdl_sample_ram is
  generic (
    VENDOR        : string   := "xilinx";
    DEVICE_FAMILY : string   := "7series";
    DATA_WIDTH    : positive := 16;
    ADDR_WIDTH    : positive := 10;
    DEPTH         : positive := 1024
  );
  port (
    clk     : in  std_logic;
    wr_en   : in  std_logic;
    wr_addr : in  unsigned(ADDR_WIDTH - 1 downto 0);
    wr_data : in  signed(DATA_WIDTH - 1 downto 0);
    rd_addr : in  unsigned(ADDR_WIDTH - 1 downto 0);
    rd_data : out signed(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of radhdl_sample_ram is
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

  signal unused_a_dout : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rd_bits       : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  rd_data <= signed(rd_bits);

  ram_i : radhdl_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      MODE => "sdp",
      MEMORY_KIND => "bram",
      DATA_WIDTH => DATA_WIDTH,
      ADDR_WIDTH => ADDR_WIDTH,
      DEPTH => DEPTH,
      CLOCKING_MODE => "common_clock"
    )
    port map (
      clka => clk, rsta => '0', a_addr => std_logic_vector(wr_addr), a_din => std_logic_vector(wr_data), a_dout => unused_a_dout, a_we => wr_en,
      clkb => clk, rstb => '0', b_addr => std_logic_vector(rd_addr), b_din => (others => '0'), b_dout => rd_bits, b_we => '0'
    );
end architecture;
