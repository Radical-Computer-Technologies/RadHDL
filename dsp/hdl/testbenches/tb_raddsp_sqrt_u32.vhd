library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

library raddsp;

-- Verifies the pipelined raddsp_sqrt_u32 restoring square-root core. The
-- sequence covers small exact squares, neighboring non-squares, wide 32-bit
-- values, continuous input acceptance, and output backpressure stalls.
entity tb_raddsp_sqrt_u32 is
end entity;

architecture sim of tb_raddsp_sqrt_u32 is
  constant C_INPUT_WIDTH  : positive := 32;
  constant C_OUTPUT_WIDTH : positive := 16;
  constant C_COUNT        : natural := 96;

  subtype root_t is unsigned(C_OUTPUT_WIDTH - 1 downto 0);
  type root_array_t is array (natural range <>) of root_t;

  signal clk           : std_logic := '0';
  signal rst           : std_logic := '1';
  signal s_axis_tvalid : std_logic := '0';
  signal s_axis_tready : std_logic;
  signal x_i           : std_logic_vector(C_INPUT_WIDTH - 1 downto 0) := (others => '0');
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal root_o        : std_logic_vector(C_OUTPUT_WIDTH - 1 downto 0);
  signal sent_count    : natural range 0 to C_COUNT := 0;
  signal recv_count    : natural range 0 to C_COUNT := 0;
  signal expected_fifo : root_array_t(0 to C_COUNT - 1) := (others => (others => '0'));
  signal wr_index      : natural range 0 to C_COUNT := 0;
  signal rd_index      : natural range 0 to C_COUNT := 0;
  signal cycle_count   : natural := 0;

  function stimulus_value(index : natural) return unsigned is
    variable value_v : unsigned(C_INPUT_WIDTH - 1 downto 0) := (others => '0');
  begin
    if index < 32 then
      value_v := to_unsigned(index * index, C_INPUT_WIDTH);
    elsif index < 64 then
      value_v := to_unsigned(((index - 32) * (index - 32)) + (index mod 5), C_INPUT_WIDTH);
    elsif index = 64 then
      value_v := to_unsigned(65535, C_INPUT_WIDTH);
    elsif index = 65 then
      value_v := to_unsigned(65536, C_INPUT_WIDTH);
    elsif index = 66 then
      value_v := to_unsigned(1048575, C_INPUT_WIDTH);
    elsif index = 67 then
      value_v := to_unsigned(1048576, C_INPUT_WIDTH);
    elsif index = 68 then
      value_v := to_unsigned(2147395600, C_INPUT_WIDTH);
    elsif index = 69 then
      value_v := to_unsigned(2147483647, C_INPUT_WIDTH);
    else
      value_v := to_unsigned(((index * 7919) + 12345) mod 2147483647, C_INPUT_WIDTH);
    end if;
    return value_v;
  end function;

  function isqrt_unsigned(value : unsigned) return root_t is
    constant PAD_WIDTH : positive := C_OUTPUT_WIDTH * 2;
    constant REM_WIDTH : positive := PAD_WIDTH + 2;
    variable padded_v  : unsigned(PAD_WIDTH - 1 downto 0) := (others => '0');
    variable rem_v     : unsigned(REM_WIDTH - 1 downto 0) := (others => '0');
    variable trial_v   : unsigned(REM_WIDTH - 1 downto 0) := (others => '0');
    variable root_v    : root_t := (others => '0');
    variable pair_v    : unsigned(1 downto 0);
  begin
    padded_v(value'length - 1 downto 0) := value;
    for stage in 0 to C_OUTPUT_WIDTH - 1 loop
      pair_v := padded_v(((C_OUTPUT_WIDTH - stage) * 2) - 1 downto (C_OUTPUT_WIDTH - 1 - stage) * 2);
      rem_v := shift_left(rem_v, 2);
      rem_v(1 downto 0) := pair_v;
      trial_v := shift_left(resize(root_v, REM_WIDTH), 2);
      trial_v(0) := '1';
      if rem_v >= trial_v then
        rem_v := rem_v - trial_v;
        root_v := shift_left(root_v, 1);
        root_v(0) := '1';
      else
        root_v := shift_left(root_v, 1);
      end if;
    end loop;
    return root_v;
  end function;
begin
  clk <= not clk after 5 ns;
  s_axis_tvalid <= '1' when rst = '0' and sent_count < C_COUNT else '0';
  x_i <= std_logic_vector(stimulus_value(sent_count)) when sent_count < C_COUNT else (others => '0');

  u_dut : entity raddsp.raddsp_sqrt_u32
    generic map (
      INPUT_WIDTH => C_INPUT_WIDTH,
      OUTPUT_WIDTH => C_OUTPUT_WIDTH
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      x_i => x_i,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      root_o => root_o
    );

  stim : process(clk)
    variable input_v    : unsigned(C_INPUT_WIDTH - 1 downto 0);
    variable expected_v : root_t;
    variable observed_v : root_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sent_count <= 0;
        recv_count <= 0;
        wr_index <= 0;
        rd_index <= 0;
        cycle_count <= 0;
        expected_fifo <= (others => (others => '0'));
        m_axis_tready <= '1';
      else
        cycle_count <= cycle_count + 1;
        if cycle_count mod 11 = 7 or cycle_count mod 17 = 9 then
          m_axis_tready <= '0';
        else
          m_axis_tready <= '1';
        end if;

        if s_axis_tvalid = '1' and s_axis_tready = '1' then
          input_v := unsigned(x_i);
          expected_v := isqrt_unsigned(input_v);
          expected_fifo(wr_index) <= expected_v;
          wr_index <= wr_index + 1;
          sent_count <= sent_count + 1;
        end if;

        if m_axis_tvalid = '1' and m_axis_tready = '1' then
          observed_v := unsigned(root_o);
          assert observed_v = expected_fifo(rd_index)
            report "sqrt mismatch at output " & integer'image(rd_index)
              & ": observed " & integer'image(to_integer(observed_v))
              & ", expected " & integer'image(to_integer(expected_fifo(rd_index)))
            severity failure;
          rd_index <= rd_index + 1;
          recv_count <= recv_count + 1;
        end if;

        if recv_count = C_COUNT then
          report "tb_raddsp_sqrt_u32 passed" severity note;
          finish;
        end if;
      end if;
    end if;
  end process;

  reset_proc : process
  begin
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait;
  end process;
end architecture;
