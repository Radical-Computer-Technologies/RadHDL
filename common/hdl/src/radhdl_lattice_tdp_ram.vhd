library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ECP5 true dual-port RAM wrapper backed by explicit DP16KD blocks.
-- This first implementation covers one 18x1024 DP16KD shape; wider/deeper
-- banking should be added here rather than inferred in consumer cores.
entity radhdl_lattice_tdp_ram is
  generic (
    DATA_WIDTH : positive := 18;
    ADDR_WIDTH : positive := 10;
    DEPTH      : positive := 1024;
    SIMULATION : boolean  := false
  );
  port (
    clka   : in  std_logic;
    a_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    a_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    a_we   : in  std_logic;
    clkb   : in  std_logic;
    b_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    b_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    b_we   : in  std_logic
  );
end entity;

architecture rtl of radhdl_lattice_tdp_ram is
  component radhdl_ecp5_dp16kd_18x1024 is
    port (
      clka  : in  std_logic;
      wea   : in  std_logic;
      addra : in  std_logic_vector(9 downto 0);
      dia   : in  std_logic_vector(17 downto 0);
      doa   : out std_logic_vector(17 downto 0);
      clkb  : in  std_logic;
      web   : in  std_logic;
      addrb : in  std_logic_vector(9 downto 0);
      dib   : in  std_logic_vector(17 downto 0);
      dob   : out std_logic_vector(17 downto 0)
    );
  end component;

  type ram_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  function addr10(addr : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(9 downto 0) := (others => '0');
  begin
    result(addr'length - 1 downto 0) := addr;
    return result;
  end function;

  function data18(data : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(17 downto 0) := (others => '0');
  begin
    result(data'length - 1 downto 0) := data;
    return result;
  end function;
begin
  assert DATA_WIDTH <= 18 report "radhdl_lattice_tdp_ram v1 supports DATA_WIDTH <= 18" severity failure;
  assert ADDR_WIDTH <= 10 report "radhdl_lattice_tdp_ram v1 supports ADDR_WIDTH <= 10" severity failure;
  assert DEPTH <= 1024 report "radhdl_lattice_tdp_ram v1 supports DEPTH <= 1024" severity failure;

  gen_simulation : if SIMULATION generate
    signal ram_r : ram_t := (others => (others => '0'));
    signal a_dout_r : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal b_dout_r : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  begin
    a_dout <= a_dout_r;
    b_dout <= b_dout_r;

    process(clka)
    begin
      if rising_edge(clka) then
        a_dout_r <= ram_r(to_integer(unsigned(a_addr)));
        b_dout_r <= ram_r(to_integer(unsigned(b_addr)));
        if a_we = '1' then
          ram_r(to_integer(unsigned(a_addr))) <= a_din;
        end if;
        if b_we = '1' then
          ram_r(to_integer(unsigned(b_addr))) <= b_din;
        end if;
      end if;
    end process;
  end generate;

  gen_hardware : if not SIMULATION generate
    signal doa : std_logic_vector(17 downto 0);
    signal dob : std_logic_vector(17 downto 0);
  begin
    a_dout <= doa(DATA_WIDTH - 1 downto 0);
    b_dout <= dob(DATA_WIDTH - 1 downto 0);

    ram_i : radhdl_ecp5_dp16kd_18x1024
      port map (
        clka => clka,
        wea => a_we,
        addra => addr10(a_addr),
        dia => data18(a_din),
        doa => doa,
        clkb => clkb,
        web => b_we,
        addrb => addr10(b_addr),
        dib => data18(b_din),
        dob => dob
      );
  end generate;
end architecture;
