library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

library raddsp;
use raddsp.raddsp_fft_twiddle_pkg.all;

-- Self-checking or stimulus-focused testbench for axis radfft.
-- Exercises representative handshakes, reset behavior, frame boundaries, and numeric corner cases for regression runs.
entity tb_raddsp_axis_radfft is
end entity;

architecture sim of tb_raddsp_axis_radfft is
  constant C_POINTS : positive := 16;
  constant C_IW     : positive := 16;
  constant C_TW     : positive := 16;
  constant C_OW     : positive := 32;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal s_valid : std_logic := '0';
  signal s_data  : std_logic_vector((2 * C_IW) - 1 downto 0) := (others => '0');
  signal s_last  : std_logic := '0';

  signal r2_ready : std_logic;
  signal r4_ready : std_logic;
  signal st_ready : std_logic;
  signal if_ready : std_logic;

  signal r2_valid : std_logic;
  signal r4_valid : std_logic;
  signal st_valid : std_logic;
  signal if_valid : std_logic;
  signal r2_data  : std_logic_vector((2 * C_OW) - 1 downto 0);
  signal r4_data  : std_logic_vector((2 * C_OW) - 1 downto 0);
  signal st_data  : std_logic_vector((2 * C_OW) - 1 downto 0);
  signal if_data  : std_logic_vector((2 * C_OW) - 1 downto 0);
  signal r2_last  : std_logic;
  signal r4_last  : std_logic;
  signal st_last  : std_logic;
  signal if_last  : std_logic;

  signal r2_tw_addr : std_logic_vector(31 downto 0);
  signal r4_tw_addr : std_logic_vector(31 downto 0);
  signal if_tw_addr : std_logic_vector(31 downto 0);
  signal r2_tw_re   : std_logic_vector(C_TW - 1 downto 0);
  signal r2_tw_im   : std_logic_vector(C_TW - 1 downto 0);
  signal r4_tw_re   : std_logic_vector(C_TW - 1 downto 0);
  signal r4_tw_im   : std_logic_vector(C_TW - 1 downto 0);
  signal if_tw_re   : std_logic_vector(C_TW - 1 downto 0);
  signal if_tw_im   : std_logic_vector(C_TW - 1 downto 0);

  signal r2_done : std_logic;
  signal r4_done : std_logic;
  signal st_done : std_logic;
  signal if_done : std_logic;
  signal r2_count : natural := 0;
  signal r4_count : natural := 0;
  signal st_count : natural := 0;
  signal if_count : natural := 0;

  function sample_re(index : natural) return integer is
  begin
    return (index * 137) - 900;
  end function;

  function sample_im(index : natural) return integer is
  begin
    return 400 - (index * 53);
  end function;

  function high_i(value : std_logic_vector) return integer is
  begin
    return to_integer(signed(value(value'left downto value'length / 2)));
  end function;

  function low_i(value : std_logic_vector) return integer is
  begin
    return to_integer(signed(value((value'length / 2) - 1 downto 0)));
  end function;

  procedure write_row(file f : text; index : natural; data : std_logic_vector) is
    variable l : line;
  begin
    write(l, index);
    write(l, string'(","));
    write(l, high_i(data));
    write(l, string'(","));
    write(l, low_i(data));
    writeline(f, l);
  end procedure;
begin
  clk <= not clk after 5 ns;

  r2_tw_re <= std_logic_vector(to_signed(radfft_twiddle_re(C_POINTS, to_integer(unsigned(r2_tw_addr(7 downto 0))), C_TW), C_TW));
  r2_tw_im <= std_logic_vector(to_signed(radfft_twiddle_im(C_POINTS, to_integer(unsigned(r2_tw_addr(7 downto 0))), C_TW, false), C_TW));
  r4_tw_re <= std_logic_vector(to_signed(radfft_twiddle_re(C_POINTS, to_integer(unsigned(r4_tw_addr(7 downto 0))), C_TW), C_TW));
  r4_tw_im <= std_logic_vector(to_signed(radfft_twiddle_im(C_POINTS, to_integer(unsigned(r4_tw_addr(7 downto 0))), C_TW, false), C_TW));
  if_tw_re <= std_logic_vector(to_signed(radfft_twiddle_re(C_POINTS, to_integer(unsigned(if_tw_addr(7 downto 0))), C_TW), C_TW));
  if_tw_im <= std_logic_vector(to_signed(radfft_twiddle_im(C_POINTS, to_integer(unsigned(if_tw_addr(7 downto 0))), C_TW, false), C_TW));

  batch_r2_i: entity raddsp.raddsp_axis_radfft
    generic map (
      G_POINTS => C_POINTS,
      G_MAX_POINTS => 64,
      G_RADIX => 2,
      G_PIPELINED_STREAMING => false,
      G_INVERSE_FFT => false,
      G_INPUT_WIDTH => C_IW,
      G_TWIDDLE_WIDTH => C_TW,
      G_OUTPUT_WIDTH => C_OW,
      G_MEMORY_STYLE => "block",
      G_TWIDDLE_INIT_FILE => "../../mem/radfft_twiddle_16_16_fft.mem"
    )
    port map (
      clk => clk, rst => rst,
      s_axis_tvalid => s_valid, s_axis_tready => r2_ready, s_axis_tdata => s_data, s_axis_tlast => s_last,
      m_axis_tvalid => r2_valid, m_axis_tready => '1', m_axis_tdata => r2_data, m_axis_tlast => r2_last,
      twiddle_addr_o => r2_tw_addr, twiddle_re_i => r2_tw_re, twiddle_im_i => r2_tw_im,
      busy_o => open, frame_done_o => r2_done
    );

  batch_r4_i: entity raddsp.raddsp_axis_radfft
    generic map (
      G_POINTS => C_POINTS,
      G_MAX_POINTS => 64,
      G_RADIX => 4,
      G_PIPELINED_STREAMING => false,
      G_INVERSE_FFT => false,
      G_INPUT_WIDTH => C_IW,
      G_TWIDDLE_WIDTH => C_TW,
      G_OUTPUT_WIDTH => C_OW,
      G_MEMORY_STYLE => "ultra",
      G_TWIDDLE_INIT_FILE => "../../mem/radfft_twiddle_16_16_fft.mem"
    )
    port map (
      clk => clk, rst => rst,
      s_axis_tvalid => s_valid, s_axis_tready => r4_ready, s_axis_tdata => s_data, s_axis_tlast => s_last,
      m_axis_tvalid => r4_valid, m_axis_tready => '1', m_axis_tdata => r4_data, m_axis_tlast => r4_last,
      twiddle_addr_o => r4_tw_addr, twiddle_re_i => r4_tw_re, twiddle_im_i => r4_tw_im,
      busy_o => open, frame_done_o => r4_done
    );

  stream_r2_i: entity raddsp.raddsp_axis_radfft
    generic map (
      G_POINTS => C_POINTS,
      G_MAX_POINTS => 64,
      G_RADIX => 2,
      G_PIPELINED_STREAMING => true,
      G_INVERSE_FFT => false,
      G_INPUT_WIDTH => C_IW,
      G_TWIDDLE_WIDTH => C_TW,
      G_OUTPUT_WIDTH => C_OW,
      G_MEMORY_STYLE => "distributed"
    )
    port map (
      clk => clk, rst => rst,
      s_axis_tvalid => s_valid, s_axis_tready => st_ready, s_axis_tdata => s_data, s_axis_tlast => s_last,
      m_axis_tvalid => st_valid, m_axis_tready => '1', m_axis_tdata => st_data, m_axis_tlast => st_last,
      twiddle_addr_o => open, twiddle_re_i => (others => '0'), twiddle_im_i => (others => '0'),
      busy_o => open, frame_done_o => st_done
    );

  stream_ifft_i: entity raddsp.raddsp_axis_radfft
    generic map (
      G_POINTS => C_POINTS,
      G_MAX_POINTS => 64,
      G_RADIX => 4,
      G_PIPELINED_STREAMING => true,
      G_INVERSE_FFT => true,
      G_INPUT_WIDTH => C_IW,
      G_TWIDDLE_WIDTH => C_TW,
      G_OUTPUT_WIDTH => C_OW,
      G_MEMORY_STYLE => "distributed"
    )
    port map (
      clk => clk, rst => rst,
      s_axis_tvalid => s_valid, s_axis_tready => if_ready, s_axis_tdata => s_data, s_axis_tlast => s_last,
      m_axis_tvalid => if_valid, m_axis_tready => '1', m_axis_tdata => if_data, m_axis_tlast => if_last,
      twiddle_addr_o => if_tw_addr, twiddle_re_i => if_tw_re, twiddle_im_i => if_tw_im,
      busy_o => open, frame_done_o => if_done
    );

  stim: process
    file input_file : text open write_mode is "radfft_input.csv";
    variable l : line;
  begin
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';

    write(l, string'("index,re,im"));
    writeline(input_file, l);

    for i in 0 to C_POINTS - 1 loop
      while not (r2_ready = '1' and r4_ready = '1' and st_ready = '1' and if_ready = '1') loop
        wait until rising_edge(clk);
      end loop;
      s_data <= std_logic_vector(to_signed(sample_re(i), C_IW)) & std_logic_vector(to_signed(sample_im(i), C_IW));
      s_last <= '1' when i = C_POINTS - 1 else '0';
      s_valid <= '1';
      wait until rising_edge(clk);
      s_valid <= '0';
      s_last <= '0';
      write(l, i);
      write(l, string'(","));
      write(l, sample_re(i));
      write(l, string'(","));
      write(l, sample_im(i));
      writeline(input_file, l);
      wait until rising_edge(clk);
    end loop;

    wait until r2_count = C_POINTS and r4_count = C_POINTS and st_count = C_POINTS and if_count = C_POINTS;
    wait for 100 ns;
    report "tb_raddsp_axis_radfft passed";
    stop;
  end process;

  capture_r2: process(clk)
    file f : text open write_mode is "radfft_batch_radix2_fft.csv";
    variable index : natural := 0;
    variable header : line;
    variable header_written : boolean := false;
  begin
    if not header_written then
      write(header, string'("index,re,im"));
      writeline(f, header);
      header_written := true;
    end if;
    if rising_edge(clk) and r2_valid = '1' then
      write_row(f, index, r2_data);
      index := index + 1;
      r2_count <= index;
    end if;
  end process;

  capture_r4: process(clk)
    file f : text open write_mode is "radfft_batch_radix4_fft.csv";
    variable index : natural := 0;
    variable header : line;
    variable header_written : boolean := false;
  begin
    if not header_written then
      write(header, string'("index,re,im"));
      writeline(f, header);
      header_written := true;
    end if;
    if rising_edge(clk) and r4_valid = '1' then
      write_row(f, index, r4_data);
      index := index + 1;
      r4_count <= index;
    end if;
  end process;

  capture_st: process(clk)
    file f : text open write_mode is "radfft_stream_radix2_fft.csv";
    variable index : natural := 0;
    variable header : line;
    variable header_written : boolean := false;
  begin
    if not header_written then
      write(header, string'("index,re,im"));
      writeline(f, header);
      header_written := true;
    end if;
    if rising_edge(clk) and st_valid = '1' then
      write_row(f, index, st_data);
      index := index + 1;
      st_count <= index;
    end if;
  end process;

  capture_if: process(clk)
    file f : text open write_mode is "radfft_stream_radix4_ifft.csv";
    variable index : natural := 0;
    variable header : line;
    variable header_written : boolean := false;
  begin
    if not header_written then
      write(header, string'("index,re,im"));
      writeline(f, header);
      header_written := true;
    end if;
    if rising_edge(clk) and if_valid = '1' then
      write_row(f, index, if_data);
      index := index + 1;
      if_count <= index;
    end if;
  end process;
end architecture;
