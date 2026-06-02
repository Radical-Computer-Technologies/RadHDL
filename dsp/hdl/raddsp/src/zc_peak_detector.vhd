library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.zc_reference_pkg.all;

entity zc_peak_detector is
  generic (
    G_SAMPLE_WIDTH  : integer := 16;
    G_ACC_WIDTH     : integer := 40;
    G_FRAME_SAMPLES : integer := 1024;
    G_PRODUCT_SHIFT : integer := 15
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    frame_start  : in  std_logic;
    sample_valid : in  std_logic;
    sample_i     : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    sample_q     : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    sample_ready : out std_logic;
    busy         : out std_logic;
    peak_valid   : out std_logic;
    peak_index   : out integer range 0 to G_FRAME_SAMPLES - 1;
    peak_i       : out signed(G_ACC_WIDTH - 1 downto 0);
    peak_q       : out signed(G_ACC_WIDTH - 1 downto 0);
    peak_mag_sq  : out unsigned((2 * G_ACC_WIDTH) - 1 downto 0)
  );
end entity;

architecture rtl of zc_peak_detector is
  constant C_LAST_OFFSET : integer := G_FRAME_SAMPLES - ZC_REF_LEN;

  type sample_array_t is array (0 to G_FRAME_SAMPLES - 1) of signed(G_SAMPLE_WIDTH - 1 downto 0);
  type state_t is (S_CAPTURE, S_SCAN, S_SCORE, S_DONE);

  signal state      : state_t := S_CAPTURE;
  signal wr_idx     : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal offset_idx : integer range 0 to C_LAST_OFFSET := 0;
  signal zc_idx     : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal frame_i    : sample_array_t := (others => (others => '0'));
  signal frame_q    : sample_array_t := (others => (others => '0'));
  signal acc_i      : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal acc_q      : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_i     : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_q     : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_mag   : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal best_idx   : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal valid_reg  : std_logic := '0';

  function coeff(value : integer; width : integer) return signed is
  begin
    return resize(to_signed(value, 32), width);
  end function;
begin
  sample_ready <= '1' when state = S_CAPTURE else '0';
  busy <= '1' when state /= S_CAPTURE else '0';
  peak_valid <= valid_reg;
  peak_index <= best_idx;
  peak_i <= best_i;
  peak_q <= best_q;
  peak_mag_sq <= best_mag;

  process(clk)
    variable xi       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable xq       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable ci       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable cq       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable prod_i   : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable prod_q   : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable next_i   : signed(G_ACC_WIDTH - 1 downto 0);
    variable next_q   : signed(G_ACC_WIDTH - 1 downto 0);
    variable mag_i    : signed((2 * G_ACC_WIDTH) - 1 downto 0);
    variable mag_q    : signed((2 * G_ACC_WIDTH) - 1 downto 0);
    variable mag      : unsigned((2 * G_ACC_WIDTH) - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S_CAPTURE;
        wr_idx <= 0;
        offset_idx <= 0;
        zc_idx <= 0;
        acc_i <= (others => '0');
        acc_q <= (others => '0');
        best_i <= (others => '0');
        best_q <= (others => '0');
        best_mag <= (others => '0');
        best_idx <= 0;
        valid_reg <= '0';
      else
        valid_reg <= '0';

        case state is
          when S_CAPTURE =>
            if frame_start = '1' then
              wr_idx <= 0;
            end if;

            if sample_valid = '1' then
              frame_i(wr_idx) <= sample_i;
              frame_q(wr_idx) <= sample_q;
              if wr_idx = G_FRAME_SAMPLES - 1 then
                wr_idx <= 0;
                offset_idx <= 0;
                zc_idx <= 0;
                acc_i <= (others => '0');
                acc_q <= (others => '0');
                best_i <= (others => '0');
                best_q <= (others => '0');
                best_mag <= (others => '0');
                best_idx <= 0;
                state <= S_SCAN;
              else
                wr_idx <= wr_idx + 1;
              end if;
            end if;

          when S_SCAN =>
            xi := frame_i(offset_idx + zc_idx);
            xq := frame_q(offset_idx + zc_idx);
            ci := coeff(ZC_REF_I(zc_idx), G_SAMPLE_WIDTH);
            cq := coeff(ZC_REF_Q(zc_idx), G_SAMPLE_WIDTH);
            prod_i := shift_right(resize(xi * ci, prod_i'length) + resize(xq * cq, prod_i'length), G_PRODUCT_SHIFT);
            prod_q := shift_right(resize(xq * ci, prod_q'length) - resize(xi * cq, prod_q'length), G_PRODUCT_SHIFT);
            next_i := acc_i + resize(prod_i, G_ACC_WIDTH);
            next_q := acc_q + resize(prod_q, G_ACC_WIDTH);
            acc_i <= next_i;
            acc_q <= next_q;

            if zc_idx = ZC_REF_LEN - 1 then
              mag_i := next_i * next_i;
              mag_q := next_q * next_q;
              mag := unsigned(mag_i) + unsigned(mag_q);
              if mag > best_mag then
                best_mag <= mag;
                best_i <= next_i;
                best_q <= next_q;
                best_idx <= offset_idx + (ZC_REF_LEN / 2);
              end if;
              state <= S_SCORE;
            else
              zc_idx <= zc_idx + 1;
            end if;

          when S_SCORE =>
            acc_i <= (others => '0');
            acc_q <= (others => '0');
            zc_idx <= 0;
            if offset_idx = C_LAST_OFFSET then
              state <= S_DONE;
            else
              offset_idx <= offset_idx + 1;
              state <= S_SCAN;
            end if;

          when S_DONE =>
            valid_reg <= '1';
            state <= S_CAPTURE;
        end case;
      end if;
    end if;
  end process;
end architecture;
