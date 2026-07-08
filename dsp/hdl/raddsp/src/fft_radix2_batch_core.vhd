library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Radix-2 batch FFT compute core for fixed-size frame transforms.
-- Processes buffered sample batches through staged butterfly operations using local twiddle and scratch memories.
entity fft_radix2_batch_core is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR              : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY       : string  := "ultrascale+";
    -- Sets the transform, frame, or vector size used by the datapath.
    G_POINTS            : positive := 16;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_MAX_POINTS        : positive := 2048;
    -- Configures G RADIX for this instance.
    G_RADIX             : positive := 2;
    -- Sets the bit width for G INPUT WIDTH values carried by this module.
    G_INPUT_WIDTH       : positive := 16;
    -- Sets the bit width for G TWIDDLE WIDTH values carried by this module.
    G_TWIDDLE_WIDTH     : positive := 16;
    -- Sets the bit width for G OUTPUT WIDTH values carried by this module.
    G_OUTPUT_WIDTH      : positive := 32;
    -- Configures G SCALE EACH STAGE for this instance.
    G_SCALE_EACH_STAGE  : boolean := true;
    -- Configures G MEMORY STYLE for this instance.
    G_MEMORY_STYLE      : string := "block"
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk          : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst          : in  std_logic;
    -- Start frame interface signal.
    start_frame  : in  std_logic;
    -- Sample valid interface signal.
    sample_valid : in  std_logic;
    -- Sample re interface signal.
    sample_re    : in  integer;
    -- Sample im interface signal.
    sample_im    : in  integer;
    -- Sample ready interface signal.
    sample_ready : out std_logic;
    -- Twiddle addr interface signal.
    twiddle_addr : out integer range 0 to G_MAX_POINTS / 2 - 1;
    -- Twiddle re interface signal.
    twiddle_re   : in  integer;
    -- Twiddle im interface signal.
    twiddle_im   : in  integer;
    -- Busy interface signal.
    busy         : out std_logic;
    -- Done interface signal.
    done         : out std_logic;
    -- Output ready interface signal.
    output_ready : in  std_logic;
    -- Output valid interface signal.
    output_valid : out std_logic;
    -- Output index interface signal.
    output_index : out integer range 0 to G_MAX_POINTS - 1;
    -- Output re interface signal.
    output_re    : out integer;
    -- Output im interface signal.
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
    S_RUN_SUMDIFF,
    S_RUN_WRITE,
    S_RUN_ADVANCE,
    S_RUN4_ADDR0,
    S_RUN4_WAIT0,
    S_RUN4_CAPTURE0,
    S_RUN4_ADDR1,
    S_RUN4_WAIT1,
    S_RUN4_CAPTURE1,
    S_RUN4_TW1,
    S_RUN4_MUL1,
    S_RUN4_COMB1,
    S_RUN4_TW2,
    S_RUN4_MUL2,
    S_RUN4_COMB2,
    S_RUN4_TW3,
    S_RUN4_MUL3,
    S_RUN4_COMB3,
    S_RUN4_BUTTERFLY,
    S_RUN4_WRITE0,
    S_RUN4_WRITE1,
    S_RUN4_ADVANCE,
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

  function scaled_radix4(value : integer) return integer is
  begin
    if G_SCALE_EACH_STAGE then
      return value / 4;
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

  function base4_reverse(value : integer; points : positive) return integer is
    variable remaining   : integer := value;
    variable result      : integer := 0;
    variable digit_count : integer := 1;
  begin
    while digit_count < points loop
      result := (result * 4) + (remaining mod 4);
      remaining := remaining / 4;
      digit_count := digit_count * 4;
    end loop;
    return result;
  end function;

  function is_power_of_four(value : positive) return boolean is
    variable v : positive := value;
  begin
    while (v mod 4) = 0 loop
      v := v / 4;
    end loop;
    return v = 1;
  end function;

  function half_twiddle_addr(index : integer; points : positive) return integer is
    variable half : integer := points / 2;
  begin
    if index >= half then
      return index - half;
    end if;
    return index;
  end function;

  function half_twiddle_neg(index : integer; points : positive) return std_logic is
    variable half : integer := points / 2;
  begin
    if index >= half then
      return '1';
    end if;
    return '0';
  end function;

  function twiddle_with_sign(value : integer; negate : std_logic) return integer is
  begin
    if negate = '1' then
      return -value;
    end if;
    return value;
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
  signal sum_re_reg   : integer := 0;
  signal sum_im_reg   : integer := 0;
  signal diff_re_reg  : integer := 0;
  signal diff_im_reg  : integer := 0;
  signal twiddle_addr_i : integer range 0 to G_MAX_POINTS / 2 - 1 := 0;
  signal twiddle_neg_i  : std_logic := '0';
  signal twiddle_step    : integer range 1 to G_MAX_POINTS := 1;
  signal twiddle_base    : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal r4_idx0_reg : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal r4_idx1_reg : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal r4_idx2_reg : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal r4_idx3_reg : integer range 0 to G_MAX_POINTS - 1 := 0;
  signal r4_tw1_addr_reg : integer range 0 to G_MAX_POINTS / 2 - 1 := 0;
  signal r4_tw2_addr_reg : integer range 0 to G_MAX_POINTS / 2 - 1 := 0;
  signal r4_tw3_addr_reg : integer range 0 to G_MAX_POINTS / 2 - 1 := 0;
  signal r4_tw1_neg_reg  : std_logic := '0';
  signal r4_tw2_neg_reg  : std_logic := '0';
  signal r4_tw3_neg_reg  : std_logic := '0';
  signal r4_x0_re_reg : integer := 0;
  signal r4_x0_im_reg : integer := 0;
  signal r4_x1_re_reg : integer := 0;
  signal r4_x1_im_reg : integer := 0;
  signal r4_x2_re_reg : integer := 0;
  signal r4_x2_im_reg : integer := 0;
  signal r4_x3_re_reg : integer := 0;
  signal r4_x3_im_reg : integer := 0;
  signal r4_t1_re_reg : integer := 0;
  signal r4_t1_im_reg : integer := 0;
  signal r4_t2_re_reg : integer := 0;
  signal r4_t2_im_reg : integer := 0;
  signal r4_t3_re_reg : integer := 0;
  signal r4_t3_im_reg : integer := 0;
  signal r4_y0_re_reg : integer := 0;
  signal r4_y0_im_reg : integer := 0;
  signal r4_y1_re_reg : integer := 0;
  signal r4_y1_im_reg : integer := 0;
  signal r4_y2_re_reg : integer := 0;
  signal r4_y2_im_reg : integer := 0;
  signal r4_y3_re_reg : integer := 0;
  signal r4_y3_im_reg : integer := 0;

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
      -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
      DEVICE_FAMILY : string := "ultrascale+";
      -- Configures MEMORY STYLE for this instance.
      MEMORY_STYLE  : string := "block";
      -- Sets the bit width for DATA WIDTH values carried by this module.
      DATA_WIDTH : integer := 64;
      -- Sets the bit width for ADDR WIDTH values carried by this module.
      ADDR_WIDTH : integer := 5;
      -- Sets the storage depth, frame length, or number of buffered samples used internally.
      DEPTH      : integer := 32
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
  end component;
begin
  assert G_POINTS <= G_MAX_POINTS report "G_POINTS must not exceed G_MAX_POINTS" severity failure;
  assert G_POINTS <= 2048 report "G_POINTS maximum supported value is 2048" severity failure;
  assert is_power_of_two(G_POINTS) report "G_POINTS must be a power of two" severity failure;
  assert G_RADIX = 2 or G_RADIX = 4 report "G_RADIX must be 2 or 4" severity failure;
  assert G_RADIX = 2 or is_power_of_four(G_POINTS) report "G_RADIX=4 requires G_POINTS to be a power of four" severity failure;
  assert G_INPUT_WIDTH <= 32 report "G_INPUT_WIDTH maximum supported value is 32" severity failure;
  assert G_OUTPUT_WIDTH <= 32 report "G_OUTPUT_WIDTH maximum supported value is 32 while RADFFT uses integer internal arithmetic" severity failure;
  assert G_TWIDDLE_WIDTH <= 30 report "G_TWIDDLE_WIDTH maximum supported value is 30 while RADFFT uses integer internal arithmetic" severity failure;
  assert G_MEMORY_STYLE = "auto" or G_MEMORY_STYLE = "block" or G_MEMORY_STYLE = "distributed" or G_MEMORY_STYLE = "ultra"
    report "G_MEMORY_STYLE must be auto, block, distributed, or ultra"
    severity failure;

  twiddle_addr <= twiddle_addr_i;
  sample_ready <= '1' when state = S_IDLE or state = S_COLLECT else '0';
  busy <= '1' when state /= S_IDLE else '0';
  ram_a_addr_slv <= std_logic_vector(to_unsigned(ram_a_addr, C_ADDR_WIDTH));
  ram_b_addr_slv <= std_logic_vector(to_unsigned(ram_b_addr, C_ADDR_WIDTH));

  ram_i: fft_tdp_ram
    generic map (
      DEVICE_FAMILY => DEVICE_FAMILY,
      MEMORY_STYLE => G_MEMORY_STYLE,
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

  gen_radix2 : if G_RADIX = 2 generate
  begin
    process(clk)
      variable even_idx : integer;
      variable odd_idx  : integer;
      variable t_re     : integer;
      variable t_im     : integer;
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
          sum_re_reg <= 0;
          sum_im_reg <= 0;
          diff_re_reg <= 0;
          diff_im_reg <= 0;
          twiddle_addr_i <= 0;
          twiddle_neg_i <= '0';
          twiddle_step <= G_POINTS / 2;
          twiddle_base <= 0;
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
                  twiddle_step <= G_POINTS / 2;
                  twiddle_base <= 0;
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
              twiddle_addr_i <= half_twiddle_addr(twiddle_base, G_POINTS);
              twiddle_neg_i <= '0';
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
              state <= S_RUN_SUMDIFF;

            when S_RUN_SUMDIFF =>
              sum_re := u_re_reg + t_re_reg;
              sum_im := u_im_reg + t_im_reg;
              diff_re := u_re_reg - t_re_reg;
              diff_im := u_im_reg - t_im_reg;
              sum_re_reg <= sum_re;
              sum_im_reg <= sum_im;
              diff_re_reg <= diff_re;
              diff_im_reg <= diff_im;
              state <= S_RUN_WRITE;

            when S_RUN_WRITE =>
              ram_a_addr <= even_idx_reg;
              ram_b_addr <= odd_idx_reg;
              ram_a_din <= pack_complex(scaled(sum_re_reg), scaled(sum_im_reg));
              ram_b_din <= pack_complex(scaled(diff_re_reg), scaled(diff_im_reg));
              ram_a_we <= '1';
              ram_b_we <= '1';
              state <= S_RUN_ADVANCE;

            when S_RUN_ADVANCE =>
              if butterfly_j = (stage_size / 2) - 1 then
                butterfly_j <= 0;
                twiddle_base <= 0;
                if group_base + stage_size >= G_POINTS then
                  group_base <= 0;
                  if stage_size = G_POINTS then
                    out_index_i <= 0;
                    state <= S_OUTPUT_ADDR;
                  else
                    stage_size <= stage_size * 2;
                    twiddle_step <= twiddle_step / 2;
                    state <= S_RUN_ADDR;
                  end if;
                else
                  group_base <= group_base + stage_size;
                  state <= S_RUN_ADDR;
                end if;
              else
                butterfly_j <= butterfly_j + 1;
                twiddle_base <= twiddle_base + twiddle_step;
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
              if output_ready = '1' then
                if out_index_i = G_POINTS - 1 then
                  done <= '1';
                  state <= S_IDLE;
                else
                  if out_index_i + 2 < G_POINTS then
                    ram_a_addr <= out_index_i + 2;
                  end if;
                  out_index_i <= out_index_i + 1;
                end if;
              end if;

            when others =>
              state <= S_IDLE;
          end case;
        end if;
      end if;
    end process;
  end generate gen_radix2;

  gen_radix4 : if G_RADIX = 4 generate
  begin
    process(clk)
      variable load_addr : integer;
      variable quarter  : integer;
      variable tw_idx   : integer;
      variable r4_y0_re : integer;
      variable r4_y0_im : integer;
      variable r4_y1_re : integer;
      variable r4_y1_im : integer;
      variable r4_y2_re : integer;
      variable r4_y2_im : integer;
      variable r4_y3_re : integer;
      variable r4_y3_im : integer;
    begin
      if rising_edge(clk) then
        done <= '0';
        output_valid <= '0';
        ram_a_we <= '0';
        ram_b_we <= '0';

        if rst = '1' then
          state <= S_IDLE;
          load_index <= 0;
          stage_size <= 4;
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
          tw_re_reg <= 0;
          tw_im_reg <= 0;
          prod_rr_reg <= 0;
          prod_ii_reg <= 0;
          prod_ri_reg <= 0;
          prod_ir_reg <= 0;
          twiddle_addr_i <= 0;
          twiddle_neg_i <= '0';
          twiddle_step <= G_POINTS / 4;
          twiddle_base <= 0;
          r4_idx0_reg <= 0;
          r4_idx1_reg <= 0;
          r4_idx2_reg <= 0;
          r4_idx3_reg <= 0;
          r4_tw1_addr_reg <= 0;
          r4_tw2_addr_reg <= 0;
          r4_tw3_addr_reg <= 0;
          r4_tw1_neg_reg <= '0';
          r4_tw2_neg_reg <= '0';
          r4_tw3_neg_reg <= '0';
          r4_x0_re_reg <= 0;
          r4_x0_im_reg <= 0;
          r4_x1_re_reg <= 0;
          r4_x1_im_reg <= 0;
          r4_x2_re_reg <= 0;
          r4_x2_im_reg <= 0;
          r4_x3_re_reg <= 0;
          r4_x3_im_reg <= 0;
          r4_t1_re_reg <= 0;
          r4_t1_im_reg <= 0;
          r4_t2_re_reg <= 0;
          r4_t2_im_reg <= 0;
          r4_t3_re_reg <= 0;
          r4_t3_im_reg <= 0;
          r4_y0_re_reg <= 0;
          r4_y0_im_reg <= 0;
          r4_y1_re_reg <= 0;
          r4_y1_im_reg <= 0;
          r4_y2_re_reg <= 0;
          r4_y2_im_reg <= 0;
          r4_y3_re_reg <= 0;
          r4_y3_im_reg <= 0;
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
                load_addr := base4_reverse(load_index, G_POINTS);
                ram_a_addr <= load_addr;
                ram_a_din <= pack_complex(sample_re, sample_im);
                ram_a_we <= '1';
                if load_index = G_POINTS - 1 then
                  stage_size <= 4;
                  group_base <= 0;
                  butterfly_j <= 0;
                  twiddle_step <= G_POINTS / 4;
                  twiddle_base <= 0;
                  state <= S_RUN4_ADDR0;
                else
                  load_index <= load_index + 1;
                end if;
              end if;

            when S_RUN4_ADDR0 =>
              quarter := stage_size / 4;
              r4_idx0_reg <= group_base + butterfly_j;
              r4_idx1_reg <= group_base + butterfly_j + quarter;
              r4_idx2_reg <= group_base + butterfly_j + (2 * quarter);
              r4_idx3_reg <= group_base + butterfly_j + (3 * quarter);
              r4_tw1_addr_reg <= half_twiddle_addr(twiddle_base, G_POINTS);
              r4_tw1_neg_reg <= half_twiddle_neg(twiddle_base, G_POINTS);
              r4_tw2_addr_reg <= half_twiddle_addr(twiddle_base + twiddle_base, G_POINTS);
              r4_tw2_neg_reg <= half_twiddle_neg(twiddle_base + twiddle_base, G_POINTS);
              r4_tw3_addr_reg <= half_twiddle_addr(twiddle_base + twiddle_base + twiddle_base, G_POINTS);
              r4_tw3_neg_reg <= half_twiddle_neg(twiddle_base + twiddle_base + twiddle_base, G_POINTS);
              ram_a_addr <= group_base + butterfly_j;
              ram_b_addr <= group_base + butterfly_j + quarter;
              state <= S_RUN4_WAIT0;

            when S_RUN4_WAIT0 =>
              state <= S_RUN4_CAPTURE0;

            when S_RUN4_CAPTURE0 =>
              r4_x0_re_reg <= word_re(ram_a_dout);
              r4_x0_im_reg <= word_im(ram_a_dout);
              r4_x1_re_reg <= word_re(ram_b_dout);
              r4_x1_im_reg <= word_im(ram_b_dout);
              ram_a_addr <= r4_idx2_reg;
              ram_b_addr <= r4_idx3_reg;
              state <= S_RUN4_WAIT1;

            when S_RUN4_WAIT1 =>
              state <= S_RUN4_CAPTURE1;

            when S_RUN4_CAPTURE1 =>
              r4_x2_re_reg <= word_re(ram_a_dout);
              r4_x2_im_reg <= word_im(ram_a_dout);
              r4_x3_re_reg <= word_re(ram_b_dout);
              r4_x3_im_reg <= word_im(ram_b_dout);
              twiddle_addr_i <= r4_tw1_addr_reg;
              twiddle_neg_i <= r4_tw1_neg_reg;
              state <= S_RUN4_TW1;

            when S_RUN4_TW1 =>
              tw_re_reg <= twiddle_with_sign(twiddle_re, twiddle_neg_i);
              tw_im_reg <= twiddle_with_sign(twiddle_im, twiddle_neg_i);
              state <= S_RUN4_MUL1;

            when S_RUN4_MUL1 =>
              prod_rr_reg <= r4_x1_re_reg * tw_re_reg;
              prod_ii_reg <= r4_x1_im_reg * tw_im_reg;
              prod_ri_reg <= r4_x1_re_reg * tw_im_reg;
              prod_ir_reg <= r4_x1_im_reg * tw_re_reg;
              state <= S_RUN4_COMB1;

            when S_RUN4_COMB1 =>
              r4_t1_re_reg <= (prod_rr_reg - prod_ii_reg) / C_TWIDDLE_SCALE;
              r4_t1_im_reg <= (prod_ri_reg + prod_ir_reg) / C_TWIDDLE_SCALE;
              twiddle_addr_i <= r4_tw2_addr_reg;
              twiddle_neg_i <= r4_tw2_neg_reg;
              state <= S_RUN4_TW2;

            when S_RUN4_TW2 =>
              tw_re_reg <= twiddle_with_sign(twiddle_re, twiddle_neg_i);
              tw_im_reg <= twiddle_with_sign(twiddle_im, twiddle_neg_i);
              state <= S_RUN4_MUL2;

            when S_RUN4_MUL2 =>
              prod_rr_reg <= r4_x2_re_reg * tw_re_reg;
              prod_ii_reg <= r4_x2_im_reg * tw_im_reg;
              prod_ri_reg <= r4_x2_re_reg * tw_im_reg;
              prod_ir_reg <= r4_x2_im_reg * tw_re_reg;
              state <= S_RUN4_COMB2;

            when S_RUN4_COMB2 =>
              r4_t2_re_reg <= (prod_rr_reg - prod_ii_reg) / C_TWIDDLE_SCALE;
              r4_t2_im_reg <= (prod_ri_reg + prod_ir_reg) / C_TWIDDLE_SCALE;
              twiddle_addr_i <= r4_tw3_addr_reg;
              twiddle_neg_i <= r4_tw3_neg_reg;
              state <= S_RUN4_TW3;

            when S_RUN4_TW3 =>
              tw_re_reg <= twiddle_with_sign(twiddle_re, twiddle_neg_i);
              tw_im_reg <= twiddle_with_sign(twiddle_im, twiddle_neg_i);
              state <= S_RUN4_MUL3;

            when S_RUN4_MUL3 =>
              prod_rr_reg <= r4_x3_re_reg * tw_re_reg;
              prod_ii_reg <= r4_x3_im_reg * tw_im_reg;
              prod_ri_reg <= r4_x3_re_reg * tw_im_reg;
              prod_ir_reg <= r4_x3_im_reg * tw_re_reg;
              state <= S_RUN4_COMB3;

            when S_RUN4_COMB3 =>
              r4_t3_re_reg <= (prod_rr_reg - prod_ii_reg) / C_TWIDDLE_SCALE;
              r4_t3_im_reg <= (prod_ri_reg + prod_ir_reg) / C_TWIDDLE_SCALE;
              state <= S_RUN4_BUTTERFLY;

            when S_RUN4_BUTTERFLY =>
              r4_y0_re := r4_x0_re_reg + r4_t1_re_reg + r4_t2_re_reg + r4_t3_re_reg;
              r4_y0_im := r4_x0_im_reg + r4_t1_im_reg + r4_t2_im_reg + r4_t3_im_reg;
              r4_y1_re := r4_x0_re_reg + r4_t1_im_reg - r4_t2_re_reg - r4_t3_im_reg;
              r4_y1_im := r4_x0_im_reg - r4_t1_re_reg - r4_t2_im_reg + r4_t3_re_reg;
              r4_y2_re := r4_x0_re_reg - r4_t1_re_reg + r4_t2_re_reg - r4_t3_re_reg;
              r4_y2_im := r4_x0_im_reg - r4_t1_im_reg + r4_t2_im_reg - r4_t3_im_reg;
              r4_y3_re := r4_x0_re_reg - r4_t1_im_reg - r4_t2_re_reg + r4_t3_im_reg;
              r4_y3_im := r4_x0_im_reg + r4_t1_re_reg - r4_t2_im_reg - r4_t3_re_reg;
              r4_y0_re_reg <= r4_y0_re;
              r4_y0_im_reg <= r4_y0_im;
              r4_y1_re_reg <= r4_y1_re;
              r4_y1_im_reg <= r4_y1_im;
              r4_y2_re_reg <= r4_y2_re;
              r4_y2_im_reg <= r4_y2_im;
              r4_y3_re_reg <= r4_y3_re;
              r4_y3_im_reg <= r4_y3_im;
              state <= S_RUN4_WRITE0;

            when S_RUN4_WRITE0 =>
              ram_a_addr <= r4_idx0_reg;
              ram_b_addr <= r4_idx1_reg;
              ram_a_din <= pack_complex(scaled_radix4(r4_y0_re_reg), scaled_radix4(r4_y0_im_reg));
              ram_b_din <= pack_complex(scaled_radix4(r4_y1_re_reg), scaled_radix4(r4_y1_im_reg));
              ram_a_we <= '1';
              ram_b_we <= '1';
              state <= S_RUN4_WRITE1;

            when S_RUN4_WRITE1 =>
              ram_a_addr <= r4_idx2_reg;
              ram_b_addr <= r4_idx3_reg;
              ram_a_din <= pack_complex(scaled_radix4(r4_y2_re_reg), scaled_radix4(r4_y2_im_reg));
              ram_b_din <= pack_complex(scaled_radix4(r4_y3_re_reg), scaled_radix4(r4_y3_im_reg));
              ram_a_we <= '1';
              ram_b_we <= '1';
              state <= S_RUN4_ADVANCE;

            when S_RUN4_ADVANCE =>
              if butterfly_j = (stage_size / 4) - 1 then
                butterfly_j <= 0;
                twiddle_base <= 0;
                if group_base + stage_size >= G_POINTS then
                  group_base <= 0;
                  if stage_size = G_POINTS then
                    out_index_i <= 0;
                    state <= S_OUTPUT_ADDR;
                  else
                    stage_size <= stage_size * 4;
                    twiddle_step <= twiddle_step / 4;
                    state <= S_RUN4_ADDR0;
                  end if;
                else
                  group_base <= group_base + stage_size;
                  state <= S_RUN4_ADDR0;
                end if;
              else
                butterfly_j <= butterfly_j + 1;
                twiddle_base <= twiddle_base + twiddle_step;
                state <= S_RUN4_ADDR0;
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
              if output_ready = '1' then
                if out_index_i = G_POINTS - 1 then
                  done <= '1';
                  state <= S_IDLE;
                else
                  if out_index_i + 2 < G_POINTS then
                    ram_a_addr <= out_index_i + 2;
                  end if;
                  out_index_i <= out_index_i + 1;
                end if;
              end if;

            when others =>
              state <= S_IDLE;
          end case;
        end if;
      end if;
    end process;
  end generate gen_radix4;
end architecture;
