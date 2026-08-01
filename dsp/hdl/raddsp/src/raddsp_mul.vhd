library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Vendor selector for RadDSP signed multipliers.
-- Portable cores should instantiate this entity instead of a vendor-specific
-- primitive wrapper directly.
entity raddsp_mul is
  generic (
    VENDOR        : string  := "xilinx";
    DEVICE_FAMILY : string  := "7series";
    A_WIDTH       : positive := 16;
    B_WIDTH       : positive := 18;
    SIMULATION    : boolean  := false
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    valid_i    : in  std_logic;
    subtract_i : in  std_logic;
    last_i     : in  std_logic;
    a_i        : in  signed(A_WIDTH - 1 downto 0);
    b_i        : in  signed(B_WIDTH - 1 downto 0);
    valid_o    : out std_logic;
    subtract_o : out std_logic;
    last_o     : out std_logic;
    p_o        : out signed(47 downto 0)
  );
end entity;

architecture rtl of raddsp_mul is
  constant C_IS_XILINX : boolean := VENDOR = "xilinx" or VENDOR = "XILINX";
  constant C_IS_LATTICE : boolean :=
    VENDOR = "lattice" or VENDOR = "LATTICE" or
    VENDOR = "ecp5" or VENDOR = "ECP5";

  component raddsp_xilinx_dsp48_mul is
    generic (
      DEVICE_FAMILY : string := "7series";
      A_WIDTH       : positive := 16;
      B_WIDTH       : positive := 18
    );
    port (
      clk        : in  std_logic;
      rst        : in  std_logic;
      valid_i    : in  std_logic;
      subtract_i : in  std_logic;
      last_i     : in  std_logic;
      a_i        : in  signed(A_WIDTH - 1 downto 0);
      b_i        : in  signed(B_WIDTH - 1 downto 0);
      valid_o    : out std_logic;
      subtract_o : out std_logic;
      last_o     : out std_logic;
      p_o        : out signed(47 downto 0)
    );
  end component;
begin
  gen_xilinx : if C_IS_XILINX generate
  begin
    mul_i : raddsp_xilinx_dsp48_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => A_WIDTH,
        B_WIDTH => B_WIDTH
      )
      port map (
        clk => clk,
        rst => rst,
        valid_i => valid_i,
        subtract_i => subtract_i,
        last_i => last_i,
        a_i => a_i,
        b_i => b_i,
        valid_o => valid_o,
        subtract_o => subtract_o,
        last_o => last_o,
        p_o => p_o
      );
  end generate;

  gen_lattice : if C_IS_LATTICE generate
  begin
    mul_i : entity work.raddsp_lattice_mul
      generic map (
        DEVICE_FAMILY => DEVICE_FAMILY,
        A_WIDTH => A_WIDTH,
        B_WIDTH => B_WIDTH,
        SIMULATION => SIMULATION
      )
      port map (
        clk => clk,
        rst => rst,
        valid_i => valid_i,
        subtract_i => subtract_i,
        last_i => last_i,
        a_i => a_i,
        b_i => b_i,
        valid_o => valid_o,
        subtract_o => subtract_o,
        last_o => last_o,
        p_o => p_o
      );
  end generate;

  gen_unsupported : if not C_IS_XILINX and not C_IS_LATTICE generate
  begin
    assert false
      report "raddsp_mul unsupported VENDOR; expected xilinx or lattice/ecp5"
      severity failure;
  end generate;
end architecture;
