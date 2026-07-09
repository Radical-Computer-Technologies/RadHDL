library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Fully pipelined unsigned integer square-root core.
--
-- raddsp_sqrt_u32 computes floor(sqrt(x_i)) with a restoring radix-2
-- algorithm. One bit of the result is resolved per pipeline stage, so the
-- latency is OUTPUT_WIDTH enabled clock cycles and the block can accept one
-- input sample per clock while the output side is ready. The implementation is
-- vendor-independent RTL: only registers, shifts, compares, subtractors, and
-- multiplexers are inferred.
entity raddsp_sqrt_u32 is
  generic (
    -- Width of the unsigned radicand.
    INPUT_WIDTH  : positive := 32;
    -- Width of the unsigned square-root result.
    OUTPUT_WIDTH : positive := 16
  );
  port (
    -- Pipeline clock.
    clk            : in  std_logic;
    -- Active-high synchronous reset.
    rst            : in  std_logic;
    -- Input sample valid.
    s_axis_tvalid  : in  std_logic;
    -- Input sample ready. Deasserts only when output backpressure stalls the pipeline.
    s_axis_tready  : out std_logic;
    -- Unsigned radicand.
    x_i            : in  std_logic_vector(INPUT_WIDTH - 1 downto 0);
    -- Output root valid.
    m_axis_tvalid  : out std_logic;
    -- Output root ready.
    m_axis_tready  : in  std_logic;
    -- Floor square-root result.
    root_o         : out std_logic_vector(OUTPUT_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of raddsp_sqrt_u32 is
  constant PAD_WIDTH : positive := OUTPUT_WIDTH * 2;
  constant REM_WIDTH : positive := PAD_WIDTH + 2;

  subtype padded_t is unsigned(PAD_WIDTH - 1 downto 0);
  subtype root_t is unsigned(OUTPUT_WIDTH - 1 downto 0);
  subtype rem_t is unsigned(REM_WIDTH - 1 downto 0);

  type padded_array_t is array (natural range <>) of padded_t;
  type root_array_t is array (natural range <>) of root_t;
  type rem_array_t is array (natural range <>) of rem_t;
  type valid_array_t is array (natural range <>) of std_logic;

  signal radicand_pipe : padded_array_t(0 to OUTPUT_WIDTH) := (others => (others => '0'));
  signal root_pipe     : root_array_t(0 to OUTPUT_WIDTH) := (others => (others => '0'));
  signal rem_pipe      : rem_array_t(0 to OUTPUT_WIDTH) := (others => (others => '0'));
  signal valid_pipe    : valid_array_t(0 to OUTPUT_WIDTH) := (others => '0');
  signal pipe_en       : std_logic;

  function padded_input(value : std_logic_vector) return padded_t is
    variable result : padded_t := (others => '0');
  begin
    result(value'length - 1 downto 0) := unsigned(value);
    return result;
  end function;
begin
  assert INPUT_WIDTH <= PAD_WIDTH
    report "raddsp_sqrt_u32 requires INPUT_WIDTH <= 2 * OUTPUT_WIDTH"
    severity failure;

  pipe_en <= m_axis_tready or not valid_pipe(OUTPUT_WIDTH);
  s_axis_tready <= pipe_en;
  m_axis_tvalid <= valid_pipe(OUTPUT_WIDTH);
  root_o <= std_logic_vector(root_pipe(OUTPUT_WIDTH));

  process(clk)
    variable pair_v      : unsigned(1 downto 0);
    variable rem_shift_v : rem_t;
    variable trial_v     : rem_t;
    variable root_next_v : root_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        radicand_pipe <= (others => (others => '0'));
        root_pipe <= (others => (others => '0'));
        rem_pipe <= (others => (others => '0'));
        valid_pipe <= (others => '0');
      elsif pipe_en = '1' then
        radicand_pipe(0) <= padded_input(x_i);
        root_pipe(0) <= (others => '0');
        rem_pipe(0) <= (others => '0');
        valid_pipe(0) <= s_axis_tvalid;

        for stage in 0 to OUTPUT_WIDTH - 1 loop
          pair_v := radicand_pipe(stage)(((OUTPUT_WIDTH - stage) * 2) - 1 downto (OUTPUT_WIDTH - 1 - stage) * 2);
          rem_shift_v := shift_left(rem_pipe(stage), 2);
          rem_shift_v(1 downto 0) := pair_v;
          trial_v := shift_left(resize(root_pipe(stage), REM_WIDTH), 2);
          trial_v(0) := '1';

          if rem_shift_v >= trial_v then
            rem_pipe(stage + 1) <= rem_shift_v - trial_v;
            root_next_v := shift_left(root_pipe(stage), 1);
            root_next_v(0) := '1';
            root_pipe(stage + 1) <= root_next_v;
          else
            rem_pipe(stage + 1) <= rem_shift_v;
            root_pipe(stage + 1) <= shift_left(root_pipe(stage), 1);
          end if;
          radicand_pipe(stage + 1) <= radicand_pipe(stage);
          valid_pipe(stage + 1) <= valid_pipe(stage);
        end loop;
      end if;
    end if;
  end process;
end architecture;
