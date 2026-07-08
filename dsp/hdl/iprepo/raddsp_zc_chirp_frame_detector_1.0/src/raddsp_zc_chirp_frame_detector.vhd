library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI-stream wrapper around the Zadoff-Chu chirp frame detector.
-- Connects streaming sample input to frame-detection outputs for packet synchronization pipelines.
entity raddsp_zc_chirp_frame_detector is
  generic (
    -- Sets the bit width for G SAMPLE WIDTH values carried by this module.
    G_SAMPLE_WIDTH      : integer := 16;
    -- Sets the bit width for G ACC WIDTH values carried by this module.
    G_ACC_WIDTH         : integer := 40;
    -- Sets the width or count of samples handled by the datapath.
    G_FRAME_SAMPLES     : integer := 1024;
    -- Configures G CHIRP LEN for this instance.
    G_CHIRP_LEN         : integer := 512;
    -- Configures G CHIRP AFTER PEAK for this instance.
    G_CHIRP_AFTER_PEAK  : integer := 160;
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    G_PRODUCT_SHIFT     : integer := 15
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk              : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst              : in  std_logic;
    -- Frame start interface signal.
    frame_start      : in  std_logic;
    -- Sample valid interface signal.
    sample_valid     : in  std_logic;
    -- Input sample vector captured or processed by the datapath.
    sample_i         : in  std_logic_vector(G_SAMPLE_WIDTH - 1 downto 0);
    -- Sample q interface signal.
    sample_q         : in  std_logic_vector(G_SAMPLE_WIDTH - 1 downto 0);
    -- Sample ready interface signal.
    sample_ready     : out std_logic;
    -- Processing interface signal.
    processing       : out std_logic;
    -- Peak valid interface signal.
    peak_valid       : out std_logic;
    -- Peak index interface signal.
    peak_index       : out std_logic_vector(31 downto 0);
    -- Input peak i signal for this module.
    peak_i           : out std_logic_vector(G_ACC_WIDTH - 1 downto 0);
    -- Peak q interface signal.
    peak_q           : out std_logic_vector(G_ACC_WIDTH - 1 downto 0);
    -- Chirp valid interface signal.
    chirp_valid      : out std_logic;
    -- Chirp index interface signal.
    chirp_index      : out std_logic_vector(31 downto 0);
    -- Input chirp i signal for this module.
    chirp_i          : out std_logic_vector(G_SAMPLE_WIDTH - 1 downto 0);
    -- Chirp q interface signal.
    chirp_q          : out std_logic_vector(G_SAMPLE_WIDTH - 1 downto 0);
    -- Chirp done interface signal.
    chirp_done       : out std_logic
  );
end entity;

architecture rtl of raddsp_zc_chirp_frame_detector is
  signal peak_index_i  : integer range 0 to G_FRAME_SAMPLES - 1;
  signal chirp_index_i : integer range 0 to G_CHIRP_LEN - 1;
  signal peak_i_s      : signed(G_ACC_WIDTH - 1 downto 0);
  signal peak_q_s      : signed(G_ACC_WIDTH - 1 downto 0);
  signal chirp_i_s     : signed(G_SAMPLE_WIDTH - 1 downto 0);
  signal chirp_q_s     : signed(G_SAMPLE_WIDTH - 1 downto 0);
begin
  peak_index <= std_logic_vector(to_unsigned(peak_index_i, 32));
  chirp_index <= std_logic_vector(to_unsigned(chirp_index_i, 32));
  peak_i <= std_logic_vector(peak_i_s);
  peak_q <= std_logic_vector(peak_q_s);
  chirp_i <= std_logic_vector(chirp_i_s);
  chirp_q <= std_logic_vector(chirp_q_s);

  core: entity work.zc_chirp_frame_detector
    generic map (
      G_SAMPLE_WIDTH => G_SAMPLE_WIDTH,
      G_ACC_WIDTH => G_ACC_WIDTH,
      G_FRAME_SAMPLES => G_FRAME_SAMPLES,
      G_CHIRP_LEN => G_CHIRP_LEN,
      G_CHIRP_AFTER_PEAK => G_CHIRP_AFTER_PEAK,
      G_PRODUCT_SHIFT => G_PRODUCT_SHIFT
    )
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,
      sample_valid => sample_valid,
      sample_i => signed(sample_i),
      sample_q => signed(sample_q),
      sample_ready => sample_ready,
      processing => processing,
      peak_valid => peak_valid,
      peak_index => peak_index_i,
      peak_i => peak_i_s,
      peak_q => peak_q_s,
      chirp_valid => chirp_valid,
      chirp_index => chirp_index_i,
      chirp_i => chirp_i_s,
      chirp_q => chirp_q_s,
      chirp_done => chirp_done
    );
end architecture;
