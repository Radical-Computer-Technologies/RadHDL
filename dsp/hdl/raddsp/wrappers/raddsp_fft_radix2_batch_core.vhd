library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity raddsp_fft_radix2_batch_core is
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
    sample_re    : in  std_logic_vector(31 downto 0);
    sample_im    : in  std_logic_vector(31 downto 0);
    sample_ready : out std_logic;
    twiddle_addr : out std_logic_vector(31 downto 0);
    twiddle_re   : in  std_logic_vector(31 downto 0);
    twiddle_im   : in  std_logic_vector(31 downto 0);
    busy         : out std_logic;
    done         : out std_logic;
    output_valid : out std_logic;
    output_index : out std_logic_vector(31 downto 0);
    output_re    : out std_logic_vector(31 downto 0);
    output_im    : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of raddsp_fft_radix2_batch_core is
  signal twiddle_addr_i : integer range 0 to G_MAX_POINTS / 2 - 1;
  signal output_index_i : integer range 0 to G_MAX_POINTS - 1;
  signal output_re_i    : integer;
  signal output_im_i    : integer;
begin
  twiddle_addr <= std_logic_vector(to_unsigned(twiddle_addr_i, 32));
  output_index <= std_logic_vector(to_unsigned(output_index_i, 32));
  output_re <= std_logic_vector(to_signed(output_re_i, 32));
  output_im <= std_logic_vector(to_signed(output_im_i, 32));

  core: entity work.fft_radix2_batch_core
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      G_POINTS => G_POINTS,
      G_MAX_POINTS => G_MAX_POINTS,
      G_INPUT_WIDTH => G_INPUT_WIDTH,
      G_TWIDDLE_WIDTH => G_TWIDDLE_WIDTH,
      G_OUTPUT_WIDTH => G_OUTPUT_WIDTH,
      G_SCALE_EACH_STAGE => G_SCALE_EACH_STAGE
    )
    port map (
      clk => clk,
      rst => rst,
      start_frame => start_frame,
      sample_valid => sample_valid,
      sample_re => to_integer(signed(sample_re)),
      sample_im => to_integer(signed(sample_im)),
      sample_ready => sample_ready,
      twiddle_addr => twiddle_addr_i,
      twiddle_re => to_integer(signed(twiddle_re)),
      twiddle_im => to_integer(signed(twiddle_im)),
      busy => busy,
      done => done,
      output_valid => output_valid,
      output_index => output_index_i,
      output_re => output_re_i,
      output_im => output_im_i
    );
end architecture;
