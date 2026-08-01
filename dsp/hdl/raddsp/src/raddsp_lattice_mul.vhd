library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ECP5 signed multiplier wrapper with the same handshake shape as the
-- DSP48 wrapper. Synthesis uses explicit MULT18X18D hard cells through the
-- radhdl_ecp5_mult18x18d VHDL wrapper.
entity raddsp_lattice_mul is
  generic (
    DEVICE_FAMILY : string  := "ecp5";
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

architecture rtl of raddsp_lattice_mul is
  function chunks_for(width : positive) return positive is
  begin
    return (width + 16) / 17;
  end function;

  constant C_CHUNK_BITS : positive := 17;
  constant C_A_CHUNKS   : positive := chunks_for(A_WIDTH + 1);
  constant C_B_CHUNKS   : positive := chunks_for(B_WIDTH + 1);
  constant C_PARTS      : positive := C_A_CHUNKS * C_B_CHUNKS;

  subtype mult_in_t is std_logic_vector(17 downto 0);
  subtype mult_out_t is std_logic_vector(35 downto 0);
  type mult_in_array_t is array (0 to C_PARTS - 1) of mult_in_t;
  type mult_out_array_t is array (0 to C_PARTS - 1) of mult_out_t;

  component radhdl_ecp5_mult18x18d is
    port (
      clk : in  std_logic;
      rst : in  std_logic;
      ce  : in  std_logic;
      a : in  std_logic_vector(17 downto 0);
      b : in  std_logic_vector(17 downto 0);
      p : out std_logic_vector(35 downto 0)
    );
  end component;

  signal valid_pipe : std_logic_vector(1 downto 0) := (others => '0');
  signal sub_pipe   : std_logic_vector(1 downto 0) := (others => '0');
  signal last_pipe  : std_logic_vector(1 downto 0) := (others => '0');
  signal neg_pipe   : std_logic_vector(1 downto 0) := (others => '0');
  signal p_r        : signed(47 downto 0) := (others => '0');

  function part_index(ai : natural; bi : natural) return natural is
  begin
    return (ai * C_B_CHUNKS) + bi;
  end function;

  function abs_signed(value : signed) return unsigned is
    variable extended : signed(value'length downto 0);
  begin
    extended := resize(value, value'length + 1);
    if value(value'high) = '1' then
      return unsigned(-extended);
    end if;
    return unsigned(extended);
  end function;

  function chunk(value : unsigned; index : natural) return mult_in_t is
    variable result : mult_in_t := (others => '0');
    variable bit_index : natural;
  begin
    for n in 0 to C_CHUNK_BITS - 1 loop
      bit_index := (index * C_CHUNK_BITS) + n;
      if bit_index <= value'left then
        result(n) := value(bit_index);
      end if;
    end loop;
    return result;
  end function;
begin
  assert DEVICE_FAMILY = "ecp5" or DEVICE_FAMILY = "ECP5" or DEVICE_FAMILY = "lattice" or DEVICE_FAMILY = "LATTICE"
    report "raddsp_lattice_mul currently targets Lattice ECP5"
    severity failure;
  assert A_WIDTH + B_WIDTH <= 48
    report "raddsp_lattice_mul product must fit in 48 bits"
    severity failure;

  valid_o <= valid_pipe(1);
  subtract_o <= sub_pipe(1);
  last_o <= last_pipe(1);
  p_o <= p_r;

  gen_simulation : if SIMULATION generate
    signal mult_r : signed(47 downto 0) := (others => '0');
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if rst = '1' then
          valid_pipe <= (others => '0');
          sub_pipe <= (others => '0');
          last_pipe <= (others => '0');
          neg_pipe <= (others => '0');
          mult_r <= (others => '0');
          p_r <= (others => '0');
        else
          valid_pipe <= valid_pipe(0) & valid_i;
          sub_pipe <= sub_pipe(0) & subtract_i;
          last_pipe <= last_pipe(0) & last_i;
          neg_pipe <= neg_pipe(0) & (a_i(A_WIDTH - 1) xor b_i(B_WIDTH - 1));
          if valid_i = '1' then
            mult_r <= resize(a_i * b_i, mult_r'length);
          end if;
          if valid_pipe(0) = '1' then
            p_r <= mult_r;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_hardware : if not SIMULATION generate
    signal a_abs      : unsigned(A_WIDTH downto 0);
    signal b_abs      : unsigned(B_WIDTH downto 0);
    signal part_a     : mult_in_array_t := (others => (others => '0'));
    signal part_b     : mult_in_array_t := (others => (others => '0'));
    signal part_p     : mult_out_array_t := (others => (others => '0'));
    signal part_p_r   : mult_out_array_t := (others => (others => '0'));
  begin
    a_abs <= abs_signed(a_i);
    b_abs <= abs_signed(b_i);

    gen_a : for ai in 0 to C_A_CHUNKS - 1 generate
      gen_b : for bi in 0 to C_B_CHUNKS - 1 generate
        constant C_INDEX : natural := part_index(ai, bi);
      begin
        part_a(C_INDEX) <= chunk(a_abs, ai);
        part_b(C_INDEX) <= chunk(b_abs, bi);

        mult_i : radhdl_ecp5_mult18x18d
          port map (
            clk => clk,
            rst => rst,
            ce => valid_i,
            a => part_a(C_INDEX),
            b => part_b(C_INDEX),
            p => part_p(C_INDEX)
          );
      end generate;
    end generate;

    process(clk)
      variable sum_v : unsigned(47 downto 0);
      variable idx_v : natural;
    begin
      if rising_edge(clk) then
        if rst = '1' then
          valid_pipe <= (others => '0');
          sub_pipe <= (others => '0');
          last_pipe <= (others => '0');
          neg_pipe <= (others => '0');
          part_p_r <= (others => (others => '0'));
          p_r <= (others => '0');
        else
          valid_pipe <= valid_pipe(0) & valid_i;
          sub_pipe <= sub_pipe(0) & subtract_i;
          last_pipe <= last_pipe(0) & last_i;
          neg_pipe <= neg_pipe(0) & (a_i(A_WIDTH - 1) xor b_i(B_WIDTH - 1));

          if valid_i = '1' then
            part_p_r <= part_p;
          end if;

          if valid_pipe(0) = '1' then
            sum_v := (others => '0');
            for ai in 0 to C_A_CHUNKS - 1 loop
              for bi in 0 to C_B_CHUNKS - 1 loop
                idx_v := part_index(ai, bi);
                sum_v := sum_v + shift_left(resize(unsigned(part_p_r(idx_v)), 48), (ai + bi) * C_CHUNK_BITS);
              end loop;
            end loop;
            if neg_pipe(0) = '1' then
              p_r <= -signed(sum_v);
            else
              p_r <= signed(sum_v);
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
