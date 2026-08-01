library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library gw5a;
use gw5a.components.all;

-- Gowin GW5A DPB-backed dual-clock capture RAM for RadILA.
entity radila_gowin_dpb_ram is
  generic (
    DATA_WIDTH : positive := 64;
    ADDR_WIDTH : positive := 8
  );
  port (
    wr_clk  : in  std_logic;
    wr_rst  : in  std_logic;
    wr_en   : in  std_logic;
    wr_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    wr_data : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rd_clk  : in  std_logic;
    rd_rst  : in  std_logic;
    rd_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    rd_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of radila_gowin_dpb_ram is
  constant C_LANES : positive := (DATA_WIDTH + 15) / 16;

  function expand_addr(addr : std_logic_vector) return std_logic_vector is
    variable r : std_logic_vector(13 downto 0) := (others => '0');
  begin
    r(13 downto 14 - ADDR_WIDTH) := addr;
    return r;
  end function;

  function lane_in(data : std_logic_vector; lane : natural) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0) := (others => '0');
    variable bit_index : natural;
  begin
    for i in 0 to 15 loop
      bit_index := (lane * 16) + i;
      if bit_index <= data'high then
        r(i) := data(bit_index);
      end if;
    end loop;
    return r;
  end function;

  type lane_array_t is array (0 to C_LANES - 1) of std_logic_vector(15 downto 0);
  signal lane_do_a : lane_array_t;
  signal lane_do_b : lane_array_t;
begin
  assert ADDR_WIDTH <= 14
    report "radila_gowin_dpb_ram ADDR_WIDTH must fit Gowin 14-bit BSRAM address"
    severity failure;

  gen_lanes : for lane in 0 to C_LANES - 1 generate
  begin
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
        DOA => lane_do_a(lane),
        DOB => lane_do_b(lane),
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
        DIA => lane_in(wr_data, lane),
        DIB => (others => '0')
      );

    gen_bits : for bit_idx in 0 to 15 generate
      constant out_idx : natural := (lane * 16) + bit_idx;
    begin
      gen_used : if out_idx < DATA_WIDTH generate
        rd_data(out_idx) <= lane_do_b(lane)(bit_idx);
      end generate;
    end generate;
  end generate;
end architecture;
