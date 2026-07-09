library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.raddsp_axis_pkg.all;

-- Portable stereo fixed-point gain stage for audio sample streams.
-- Applies independent left/right coefficients to signed PCM samples and emits
-- saturated signed PCM output one cycle after each valid input sample.
entity raddsp_audio_stereo_gain is
  generic (
    SAMPLE_WIDTH    : positive := 24;
    COEFF_WIDTH     : positive := 18;
    COEFF_FRAC_BITS : natural  := 15
  );
  port (
    clk             : in  std_logic;
    rst             : in  std_logic;
    enable_i        : in  std_logic;
    left_i          : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_i         : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_i         : in  std_logic;
    left_gain_i     : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    right_gain_i    : in  std_logic_vector(COEFF_WIDTH - 1 downto 0);
    left_o          : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    right_o         : out std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    valid_o         : out std_logic
  );
end entity;

architecture rtl of raddsp_audio_stereo_gain is
  signal left_r  : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal right_r : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r : std_logic := '0';
begin
  left_o <= left_r;
  right_o <= right_r;
  valid_o <= valid_r;

  process(clk)
    variable left_product  : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
    variable right_product : signed(SAMPLE_WIDTH + COEFF_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        left_r <= (others => '0');
        right_r <= (others => '0');
        valid_r <= '0';
      else
        valid_r <= valid_i;
        if valid_i = '1' then
          if enable_i = '1' then
            left_product := signed(left_i) * signed(left_gain_i);
            right_product := signed(right_i) * signed(right_gain_i);
            left_r <= std_logic_vector(
              raddsp_sat_signed_vec(shift_right(left_product, COEFF_FRAC_BITS), SAMPLE_WIDTH)
            );
            right_r <= std_logic_vector(
              raddsp_sat_signed_vec(shift_right(right_product, COEFF_FRAC_BITS), SAMPLE_WIDTH)
            );
          else
            left_r <= left_i;
            right_r <= right_i;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
