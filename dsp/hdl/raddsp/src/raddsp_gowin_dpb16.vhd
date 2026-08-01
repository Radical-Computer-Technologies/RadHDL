library ieee;
use ieee.std_logic_1164.all;

library gw5a;
use gw5a.components.all;

-- Gowin GW5A 16-bit simple dual-port BSRAM wrapper.
entity raddsp_gowin_dpb16 is
  generic (
    ADDR_WIDTH : positive := 10
  );
  port (
    wr_clk  : in  std_logic;
    wr_rst  : in  std_logic;
    wr_en   : in  std_logic;
    wr_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    wr_data : in  std_logic_vector(15 downto 0);
    rd_clk  : in  std_logic;
    rd_rst  : in  std_logic;
    rd_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    rd_data : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of raddsp_gowin_dpb16 is
  signal do_a : std_logic_vector(15 downto 0);
  signal do_b : std_logic_vector(15 downto 0);

  function expand_addr(addr : std_logic_vector) return std_logic_vector is
    variable r : std_logic_vector(13 downto 0) := (others => '0');
  begin
    r(13 downto 14 - ADDR_WIDTH) := addr;
    return r;
  end function;
begin
  assert ADDR_WIDTH <= 10
    report "raddsp_gowin_dpb16 ADDR_WIDTH must fit a 16-bit Gowin BSRAM configuration"
    severity failure;

  rd_data <= do_b;

  u_ram : DPB
    generic map (
      BIT_WIDTH_0 => 16,
      BIT_WIDTH_1 => 16,
      READ_MODE0 => '0',
      READ_MODE1 => '0',
      WRITE_MODE0 => "00",
      WRITE_MODE1 => "00",
      BLK_SEL_0 => "000",
      BLK_SEL_1 => "000",
      RESET_MODE => "SYNC"
    )
    port map (
      DOA => do_a,
      DOB => do_b,
      CLKA => wr_clk,
      CLKB => rd_clk,
      CEA => '1',
      CEB => '1',
      OCEA => '1',
      OCEB => '1',
      RESETA => wr_rst,
      RESETB => rd_rst,
      WREA => wr_en,
      WREB => '0',
      ADA => expand_addr(wr_addr),
      ADB => expand_addr(rd_addr),
      BLKSELA => "000",
      BLKSELB => "000",
      DIA => wr_data,
      DIB => (others => '0')
    );
end architecture;
