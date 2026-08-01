library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Vendor-selected wide signed multiplier built from the RAD hard multiplier wrapper.
entity raddsp_wide_mul is
  generic (
    VENDOR        : string := "xilinx";
    DEVICE_FAMILY : string := "7series";
    A_WIDTH       : positive := 16;
    B_WIDTH       : positive := 16;
    PRODUCT_WIDTH : positive := 64;
    CHUNK_WIDTH   : positive := 16
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    valid_i  : in  std_logic;
    a_i      : in  signed(A_WIDTH - 1 downto 0);
    b_i      : in  signed(B_WIDTH - 1 downto 0);
    valid_o  : out std_logic;
    p_o      : out signed(PRODUCT_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of raddsp_wide_mul is
  function chunks_for(width : positive) return positive is
  begin
    return (width + CHUNK_WIDTH - 1) / CHUNK_WIDTH;
  end function;

  constant C_A_CHUNKS : positive := chunks_for(A_WIDTH);
  constant C_B_CHUNKS : positive := chunks_for(B_WIDTH);
  constant C_PARTS    : positive := C_A_CHUNKS * C_B_CHUNKS;
  constant C_DSP_IN_WIDTH : positive := CHUNK_WIDTH + 1;

  subtype dsp_product_t is signed(47 downto 0);
  type dsp_product_array_t is array (0 to C_PARTS - 1) of dsp_product_t;

  signal a_ext : signed(A_WIDTH downto 0);
  signal b_ext : signed(B_WIDTH downto 0);
  signal a_abs : unsigned(A_WIDTH downto 0);
  signal b_abs : unsigned(B_WIDTH downto 0);
  signal neg_pipe : std_logic_vector(2 downto 0) := (others => '0');
  signal valid_sum_r : std_logic := '0';
  signal valid_parts : std_logic_vector(0 to C_PARTS - 1);
  signal part_p : dsp_product_array_t := (others => (others => '0'));
  signal unused_sub : std_logic_vector(0 to C_PARTS - 1);
  signal unused_last : std_logic_vector(0 to C_PARTS - 1);

  function part_index(ai : natural; bi : natural) return natural is
  begin
    return (ai * C_B_CHUNKS) + bi;
  end function;

  function get_chunk(value : unsigned; chunk : natural) return signed is
    variable ret : signed(C_DSP_IN_WIDTH - 1 downto 0) := (others => '0');
    variable bit_index : natural;
  begin
    for i in 0 to CHUNK_WIDTH - 1 loop
      bit_index := (chunk * CHUNK_WIDTH) + i;
      if bit_index <= value'left then
        ret(i) := value(bit_index);
      end if;
    end loop;
    return ret;
  end function;
begin
  assert CHUNK_WIDTH <= 16 report "raddsp_wide_mul CHUNK_WIDTH must be <= 16" severity failure;
  assert C_DSP_IN_WIDTH <= 18 report "raddsp_wide_mul DSP chunk width must fit hard multiplier input" severity failure;
  assert PRODUCT_WIDTH >= A_WIDTH + B_WIDTH report "PRODUCT_WIDTH must fit A_WIDTH+B_WIDTH" severity failure;

  a_ext <= resize(a_i, A_WIDTH + 1);
  b_ext <= resize(b_i, B_WIDTH + 1);
  a_abs <= unsigned(-a_ext) when a_i(A_WIDTH - 1) = '1' else unsigned(a_ext);
  b_abs <= unsigned(-b_ext) when b_i(B_WIDTH - 1) = '1' else unsigned(b_ext);

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        neg_pipe <= (others => '0');
      else
        if valid_i = '1' then
          neg_pipe <= neg_pipe(1 downto 0) & (a_i(A_WIDTH - 1) xor b_i(B_WIDTH - 1));
        else
          neg_pipe <= neg_pipe(1 downto 0) & '0';
        end if;
      end if;
    end if;
  end process;

  gen_a : for ai in 0 to C_A_CHUNKS - 1 generate
    gen_b : for bi in 0 to C_B_CHUNKS - 1 generate
      constant C_INDEX : natural := part_index(ai, bi);
    begin
      mul_i : entity work.raddsp_mul
        generic map (
          VENDOR => VENDOR,
          DEVICE_FAMILY => DEVICE_FAMILY,
          A_WIDTH => C_DSP_IN_WIDTH,
          B_WIDTH => C_DSP_IN_WIDTH
        )
        port map (
          clk => clk,
          rst => rst,
          valid_i => valid_i,
          subtract_i => '0',
          last_i => '0',
          a_i => get_chunk(a_abs, ai),
          b_i => get_chunk(b_abs, bi),
          valid_o => valid_parts(C_INDEX),
          subtract_o => unused_sub(C_INDEX),
          last_o => unused_last(C_INDEX),
          p_o => part_p(C_INDEX)
        );
    end generate;
  end generate;

  process(clk)
    variable sum_v : signed(PRODUCT_WIDTH - 1 downto 0);
    variable shifted_v : signed(PRODUCT_WIDTH - 1 downto 0);
    variable idx : natural;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        valid_o <= '0';
        valid_sum_r <= '0';
        p_o <= (others => '0');
      else
        sum_v := (others => '0');
        for ai in 0 to C_A_CHUNKS - 1 loop
          for bi in 0 to C_B_CHUNKS - 1 loop
            idx := part_index(ai, bi);
            shifted_v := shift_left(resize(part_p(idx), PRODUCT_WIDTH), (ai + bi) * CHUNK_WIDTH);
            sum_v := sum_v + shifted_v;
          end loop;
        end loop;

        if neg_pipe(2) = '1' then
          p_o <= -sum_v;
        else
          p_o <= sum_v;
        end if;
        valid_sum_r <= valid_parts(0);
        valid_o <= valid_sum_r;
      end if;
    end if;
  end process;
end architecture;
