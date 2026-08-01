library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Public Lattice RAM wrapper. Internally delegates to the explicit DP16KD
-- implementation; consumer cores should instantiate this name.
entity radhdl_lattice_ram is
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
end entity;

architecture rtl of radhdl_lattice_ram is
  function min_positive(left : positive; right : positive) return positive is
  begin
    if left < right then
      return left;
    end if;
    return right;
  end function;

  constant C_PHYS_WIDTH : positive := 18;
  constant C_PHYS_DEPTH : positive := 1024;
  constant C_PHYS_ADDR_WIDTH : positive := 10;
  constant C_WIDTH_BANKS : positive := (DATA_WIDTH + C_PHYS_WIDTH - 1) / C_PHYS_WIDTH;
  constant C_DEPTH_BANKS : positive := (DEPTH + C_PHYS_DEPTH - 1) / C_PHYS_DEPTH;

  function low_addr(addr : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(C_PHYS_ADDR_WIDTH - 1 downto 0) := (others => '0');
  begin
    if addr'length < C_PHYS_ADDR_WIDTH then
      result(addr'length - 1 downto 0) := addr;
    else
      result := addr(C_PHYS_ADDR_WIDTH - 1 downto 0);
    end if;
    return result;
  end function;

  function depth_bank(addr : std_logic_vector) return natural is
  begin
    if C_DEPTH_BANKS = 1 or addr'length <= C_PHYS_ADDR_WIDTH then
      return 0;
    end if;
    return to_integer(unsigned(addr(addr'length - 1 downto C_PHYS_ADDR_WIDTH)));
  end function;

  signal a_depth_bank : natural range 0 to C_DEPTH_BANKS - 1;
  signal b_depth_bank : natural range 0 to C_DEPTH_BANKS - 1;
begin
  a_depth_bank <= depth_bank(a_addr);
  b_depth_bank <= depth_bank(b_addr);

  gen_width_banks : for width_bank in 0 to C_WIDTH_BANKS - 1 generate
    constant C_LO         : natural := width_bank * C_PHYS_WIDTH;
    constant C_REMAINING  : positive := DATA_WIDTH - C_LO;
    constant C_THIS_WIDTH : positive := min_positive(C_PHYS_WIDTH, C_REMAINING);
    signal a_din_slice    : std_logic_vector(C_THIS_WIDTH - 1 downto 0);
    signal b_din_slice    : std_logic_vector(C_THIS_WIDTH - 1 downto 0);
    type depth_slice_array_t is array (0 to C_DEPTH_BANKS - 1) of std_logic_vector(C_THIS_WIDTH - 1 downto 0);
    signal a_dout_slices  : depth_slice_array_t;
    signal b_dout_slices  : depth_slice_array_t;
  begin
    a_din_slice <= a_din(C_LO + C_THIS_WIDTH - 1 downto C_LO);
    b_din_slice <= b_din(C_LO + C_THIS_WIDTH - 1 downto C_LO);
    a_dout(C_LO + C_THIS_WIDTH - 1 downto C_LO) <= a_dout_slices(a_depth_bank);
    b_dout(C_LO + C_THIS_WIDTH - 1 downto C_LO) <= b_dout_slices(b_depth_bank);

    gen_depth_banks : for depth_bank_i in 0 to C_DEPTH_BANKS - 1 generate
      signal a_bank_we : std_logic;
      signal b_bank_we : std_logic;
    begin
      a_bank_we <= a_we when a_depth_bank = depth_bank_i else '0';
      b_bank_we <= b_we when b_depth_bank = depth_bank_i else '0';

      ram_i : entity work.radhdl_lattice_tdp_ram
        generic map (
          DATA_WIDTH => C_THIS_WIDTH,
          ADDR_WIDTH => C_PHYS_ADDR_WIDTH,
          DEPTH => C_PHYS_DEPTH,
          SIMULATION => SIMULATION
        )
        port map (
          clka => clka,
          a_addr => low_addr(a_addr),
          a_din => a_din_slice,
          a_dout => a_dout_slices(depth_bank_i),
          a_we => a_bank_we,
          clkb => clkb,
          b_addr => low_addr(b_addr),
          b_din => b_din_slice,
          b_dout => b_dout_slices(depth_bank_i),
          b_we => b_bank_we
        );
    end generate;
  end generate;
end architecture;
