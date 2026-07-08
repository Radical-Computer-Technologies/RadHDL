library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI-stream wrapper around the radix-2 batch FFT core.
-- Adapts frame-oriented FFT processing to RadDSP streaming conventions and Vivado IP packaging.
entity raddsp_fft_radix2_batch_core is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR              : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY       : string  := "ultrascale+";
    -- Sets the transform, frame, or vector size used by the datapath.
    G_POINTS            : positive := 16;
    -- Sets the transform, frame, or vector size used by the datapath.
    G_MAX_POINTS        : positive := 2048;
    -- Sets the bit width for G INPUT WIDTH values carried by this module.
    G_INPUT_WIDTH       : positive := 16;
    -- Sets the bit width for G TWIDDLE WIDTH values carried by this module.
    G_TWIDDLE_WIDTH     : positive := 16;
    -- Sets the bit width for G OUTPUT WIDTH values carried by this module.
    G_OUTPUT_WIDTH      : positive := 32;
    -- Configures G SCALE EACH STAGE for this instance.
    G_SCALE_EACH_STAGE  : boolean := true
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
    sample_re    : in  std_logic_vector(31 downto 0);
    -- Sample im interface signal.
    sample_im    : in  std_logic_vector(31 downto 0);
    -- Sample ready interface signal.
    sample_ready : out std_logic;
    -- Twiddle addr interface signal.
    twiddle_addr : out std_logic_vector(31 downto 0);
    -- Twiddle re interface signal.
    twiddle_re   : in  std_logic_vector(31 downto 0);
    -- Twiddle im interface signal.
    twiddle_im   : in  std_logic_vector(31 downto 0);
    -- Busy interface signal.
    busy         : out std_logic;
    -- Done interface signal.
    done         : out std_logic;
    -- Output valid interface signal.
    output_valid : out std_logic;
    -- Output index interface signal.
    output_index : out std_logic_vector(31 downto 0);
    -- Output re interface signal.
    output_re    : out std_logic_vector(31 downto 0);
    -- Output im interface signal.
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
