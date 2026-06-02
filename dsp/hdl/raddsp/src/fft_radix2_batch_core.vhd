library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fft_radix2_batch_core is
  generic (
    VENDOR              : string  := "xilinx";
    DEVICE_FAMILY       : string  := "ultrascale+";
    G_POINTS            : positive := 16;
    G_MAX_POINTS        : positive := 2048;
    G_INPUT_WIDTH       : positive := 16;
    G_TWIDDLE_WIDTH     : positive := 16;
    G_OUTPUT_WIDTH      : positive := 32;
    G_SCALE_EACH_STAGE  : boolean := true
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    start_frame  : in  std_logic;
    sample_valid : in  std_logic;
    sample_re    : in  integer;
    sample_im    : in  integer;
    sample_ready : out std_logic;
    twiddle_addr : out integer range 0 to G_MAX_POINTS / 2 - 1;
    twiddle_re   : in  integer;
    twiddle_im   : in  integer;
    busy         : out std_logic;
    done         : out std_logic;
    output_valid : out std_logic;
    output_index : out integer range 0 to G_MAX_POINTS - 1;
    output_re    : out integer;
    output_im    : out integer
  );
end entity;

architecture rtl of fft_radix2_batch_core is
  type state_t is (
    S_IDLE,
    S_COLLECT,
    S_RUN_ADDR,
    S_RUN_WAIT,
    S_RUN_CAPTURE,
    S_RUN_MUL,
    S_RUN_COMB,
    S_RUN_WRITE,
    S_OUTPUT_ADDR,
    S_OUTPUT_WAIT,
    S_OUTPUT_EMIT
  );
  constant C_WORD_WIDTH : positive := G_OUTPUT_WIDTH * 2;

  function is_power_of_two(value : positive) return boolean is
    variable v : positive := value;
  begin
    while (v mod 2) = 0 loop
      v := v / 2;
    end loop;
    return v = 1;
  end function;

  function twiddle_scale return integer is
    variable value : integer := 1;
  begin
    for i in 1 to G_TWIDDLE_WIDTH - 2 loop
      value := value * 2;
    end loop;
    return value;
  end function;

  function clog2(value : positive) return positive is
    variable v : natural := value - 1;
    variable result : positive := 1;
  begin
    while v > 1 loop
      v := v / 2;
      result := result + 1;
    end loop;
    return result;
  end function;

  function scaled(value : integer) return integer is
  begin
    if G_SCALE_EACH_STAGE then
      return value / 2;
    end if;
    return value;
  end function;

  function bit_reverse(value : integer; points : positive) return integer is
    variable remaining : integer := value;
    variable result    : integer := 0;
    variable bit_count : integer := 1;
  begin
    while bit_count < points loop
      result := (result * 2) + (remaining mod 2);
      remaining := remaining / 2;
      bit_count := bit_count * 2;
    end loop;
    return result;
  end function;

  constant C_TWIDDLE_SCALE : integer := twiddle_scale;
  constant C_ADDR_WIDTH    : positive := clog2(G_MAX_POINTS);

  signal state : state_t := S_IDLE;
  signal ram_a_addr : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal ram_b_addr : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal ram_a_din  : std_logic_vector(C_WORD_WIDTH - 1 downto 0) := (others => '0');
  signal ram_b_din  : std_logic_vector(C_WORD_WIDTH - 1 downto 0) := (others => '0');
  signal ram_a_dout : std_logic_vector(C_WORD_WIDTH - 1 downto 0) := (others => '0');
  signal ram_b_dout : std_logic_vector(C_WORD_WIDTH - 1 downto 0) := (others => '0');
  signal ram_a_we   : std_logic := '0';
  signal ram_b_we   : std_logic := '0';
  signal ram_a_addr_slv : std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
  signal ram_b_addr_slv : std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
  signal load_index : integer range 0 to G_MAX_POINTS := 0;
  signal stage_size : integer range 2 to G_MAX_POINTS := 2;
  signal group_base : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal butterfly_j : integer range 0 to G_MAX_POINTS / 2 := 0;
  signal out_index_i : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal even_idx_reg : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal odd_idx_reg  : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal u_re_reg     : integer := 0;
  signal u_im_reg     : integer := 0;
  signal v_re_reg     : integer := 0;
  signal v_im_reg     : integer := 0;
  signal tw_re_reg    : integer := 0;
  signal tw_im_reg    : integer := 0;
  signal prod_rr_reg  : integer := 0;
  signal prod_ii_reg  : integer := 0;
  signal prod_ri_reg  : integer := 0;
  signal prod_ir_reg  : integer := 0;
  signal t_re_reg     : integer := 0;
  signal t_im_reg     : integer := 0;

  function pack_complex(re_value : integer; im_value : integer) return std_logic_vector is
    variable result : std_logic_vector(C_WORD_WIDTH - 1 downto 0);
  begin
    result(C_WORD_WIDTH - 1 downto G_OUTPUT_WIDTH) := std_logic_vector(to_signed(re_value, G_OUTPUT_WIDTH));
    result(G_OUTPUT_WIDTH - 1 downto 0) := std_logic_vector(to_signed(im_value, G_OUTPUT_WIDTH));
    return result;
  end function;

  function word_re(value : std_logic_vector) return integer is
  begin
    return to_integer(signed(value(C_WORD_WIDTH - 1 downto G_OUTPUT_WIDTH)));
  end function;

  function word_im(value : std_logic_vector) return integer is
  begin
    return to_integer(signed(value(G_OUTPUT_WIDTH - 1 downto 0)));
  end function;

  component fft_tdp_ram is
    generic (
      DEVICE_FAMILY : string := "ultrascale+";
      DATA_WIDTH : integer := 64;
      ADDR_WIDTH : integer := 5;
      DEPTH      : integer := 32
    );
    port (
      clk    : in  std_logic;
      a_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      a_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      a_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      a_we   : in  std_logic;
      b_addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
      b_din  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
      b_dout : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      b_we   : in  std_logic
    );
  end component;
begin
  assert G_POINTS <= G_MAX_POINTS report "G_POINTS must not exceed G_MAX_POINTS" severity failure;
  assert G_POINTS <= 2048 report "G_POINTS maximum supported value is 2048" severity failure;
  assert is_power_of_two(G_POINTS) report "G_POINTS must be a power of two" severity failure;
  assert G_INPUT_WIDTH <= 32 report "G_INPUT_WIDTH maximum supported value is 32" severity failure;

  twiddle_addr <= butterfly_j * (G_POINTS / stage_size);
  sample_ready <= '1' when state = S_IDLE or state = S_COLLECT else '0';
  busy <= '1' when state /= S_IDLE else '0';
  ram_a_addr_slv <= std_logic_vector(to_unsigned(ram_a_addr, C_ADDR_WIDTH));
  ram_b_addr_slv <= std_logic_vector(to_unsigned(ram_b_addr, C_ADDR_WIDTH));

  ram_i: fft_tdp_ram
    generic map (
      DEVICE_FAMILY => DEVICE_FAMILY,
      DATA_WIDTH => C_WORD_WIDTH,
      ADDR_WIDTH => C_ADDR_WIDTH,
      DEPTH => G_MAX_POINTS
    )
    port map (
      clk => clk,
      a_addr => ram_a_addr_slv,
      a_din => ram_a_din,
      a_dout => ram_a_dout,
      a_we => ram_a_we,
      b_addr => ram_b_addr_slv,
      b_din => ram_b_din,
      b_dout => ram_b_dout,
      b_we => ram_b_we
    );

  process(clk)
    variable even_idx : integer;
    variable odd_idx  : integer;
    variable t_re     : integer;
    variable t_im     : integer;
    variable u_re     : integer;
    variable u_im     : integer;
    variable sum_re   : integer;
    variable sum_im   : integer;
    variable diff_re  : integer;
    variable diff_im  : integer;
    variable load_addr : integer;
  begin
    if rising_edge(clk) then
      done <= '0';
      output_valid <= '0';
      ram_a_we <= '0';
      ram_b_we <= '0';

      if rst = '1' then
        state <= S_IDLE;
        load_index <= 0;
        stage_size <= 2;
        group_base <= 0;
        butterfly_j <= 0;
        out_index_i <= 0;
        output_re <= 0;
        output_im <= 0;
        output_index <= 0;
        ram_a_addr <= 0;
        ram_b_addr <= 0;
        ram_a_din <= (others => '0');
        ram_b_din <= (others => '0');
        even_idx_reg <= 0;
        odd_idx_reg <= 0;
        u_re_reg <= 0;
        u_im_reg <= 0;
        v_re_reg <= 0;
        v_im_reg <= 0;
        tw_re_reg <= 0;
        tw_im_reg <= 0;
        prod_rr_reg <= 0;
        prod_ii_reg <= 0;
        prod_ri_reg <= 0;
        prod_ir_reg <= 0;
        t_re_reg <= 0;
        t_im_reg <= 0;
      else
        case state is
          when S_IDLE =>
            if start_frame = '1' then
              load_index <= 0;
              state <= S_COLLECT;
            end if;

          when S_COLLECT =>
            if start_frame = '1' then
              load_index <= 0;
            elsif sample_valid = '1' then
              load_addr := bit_reverse(load_index, G_POINTS);
              ram_a_addr <= load_addr;
              ram_a_din <= pack_complex(sample_re, sample_im);
              ram_a_we <= '1';
              if load_index = G_POINTS - 1 then
                stage_size <= 2;
                group_base <= 0;
                butterfly_j <= 0;
                state <= S_RUN_ADDR;
              else
                load_index <= load_index + 1;
              end if;
            end if;

          when S_RUN_ADDR =>
            even_idx := group_base + butterfly_j;
            odd_idx := even_idx + stage_size / 2;
            even_idx_reg <= even_idx;
            odd_idx_reg <= odd_idx;
            ram_a_addr <= even_idx;
            ram_b_addr <= odd_idx;
            state <= S_RUN_WAIT;

          when S_RUN_WAIT =>
            state <= S_RUN_CAPTURE;

          when S_RUN_CAPTURE =>
            u_re_reg <= word_re(ram_a_dout);
            u_im_reg <= word_im(ram_a_dout);
            v_re_reg <= word_re(ram_b_dout);
            v_im_reg <= word_im(ram_b_dout);
            tw_re_reg <= twiddle_re;
            tw_im_reg <= twiddle_im;
            state <= S_RUN_MUL;

          when S_RUN_MUL =>
            prod_rr_reg <= v_re_reg * tw_re_reg;
            prod_ii_reg <= v_im_reg * tw_im_reg;
            prod_ri_reg <= v_re_reg * tw_im_reg;
            prod_ir_reg <= v_im_reg * tw_re_reg;
            state <= S_RUN_COMB;

          when S_RUN_COMB =>
            t_re := (prod_rr_reg - prod_ii_reg) / C_TWIDDLE_SCALE;
            t_im := (prod_ri_reg + prod_ir_reg) / C_TWIDDLE_SCALE;
            t_re_reg <= t_re;
            t_im_reg <= t_im;
            sum_re := u_re_reg + t_re;
            sum_im := u_im_reg + t_im;
            diff_re := u_re_reg - t_re;
            diff_im := u_im_reg - t_im;
            ram_a_addr <= even_idx_reg;
            ram_b_addr <= odd_idx_reg;
            ram_a_din <= pack_complex(scaled(sum_re), scaled(sum_im));
            ram_b_din <= pack_complex(scaled(diff_re), scaled(diff_im));
            ram_a_we <= '1';
            ram_b_we <= '1';
            state <= S_RUN_WRITE;

          when S_RUN_WRITE =>
            if butterfly_j = (stage_size / 2) - 1 then
              butterfly_j <= 0;
              if group_base + stage_size >= G_POINTS then
                group_base <= 0;
                if stage_size = G_POINTS then
                  out_index_i <= 0;
                  state <= S_OUTPUT_ADDR;
                else
                  stage_size <= stage_size * 2;
                  state <= S_RUN_ADDR;
                end if;
              else
                group_base <= group_base + stage_size;
                state <= S_RUN_ADDR;
              end if;
            else
              butterfly_j <= butterfly_j + 1;
              state <= S_RUN_ADDR;
            end if;

          when S_OUTPUT_ADDR =>
            ram_a_addr <= out_index_i;
            state <= S_OUTPUT_WAIT;

          when S_OUTPUT_WAIT =>
            if G_POINTS > 1 then
              ram_a_addr <= 1;
            end if;
            state <= S_OUTPUT_EMIT;

          when S_OUTPUT_EMIT =>
            output_valid <= '1';
            output_index <= out_index_i;
            output_re <= word_re(ram_a_dout);
            output_im <= word_im(ram_a_dout);
            if out_index_i = G_POINTS - 1 then
              done <= '1';
              state <= S_IDLE;
            else
              if out_index_i + 2 < G_POINTS then
                ram_a_addr <= out_index_i + 2;
              end if;
              out_index_i <= out_index_i + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
