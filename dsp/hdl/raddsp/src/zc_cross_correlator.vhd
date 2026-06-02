library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.zc_reference_pkg.all;

entity zc_cross_correlator is
  generic (
    G_SAMPLE_WIDTH : integer := 16;
    G_ACC_WIDTH    : integer := 40;
    G_PRODUCT_SHIFT : integer := 15
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    block_start  : in  std_logic;
    sample_valid : in  std_logic;
    sample_i     : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    sample_q     : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    sample_ready : out std_logic;
    busy         : out std_logic;
    corr_valid   : out std_logic;
    corr_i       : out signed(G_ACC_WIDTH - 1 downto 0);
    corr_q       : out signed(G_ACC_WIDTH - 1 downto 0);
    corr_mag_sq  : out unsigned((2 * G_ACC_WIDTH) - 1 downto 0)
  );
end entity;

architecture rtl of zc_cross_correlator is
  type sample_array_t is array (0 to ZC_REF_LEN - 1) of signed(G_SAMPLE_WIDTH - 1 downto 0);
  type state_t is (S_COLLECT, S_MAC, S_DONE);

  signal state       : state_t := S_COLLECT;
  signal wr_idx      : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal mac_idx     : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal samples_i   : sample_array_t := (others => (others => '0'));
  signal samples_q   : sample_array_t := (others => (others => '0'));
  signal acc_i       : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal acc_q       : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal corr_i_reg  : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal corr_q_reg  : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal mag_reg     : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal valid_reg   : std_logic := '0';

  function sat_resize(value : integer; width : integer) return signed is
  begin
    return resize(to_signed(value, 32), width);
  end function;
begin
  sample_ready <= '1' when state = S_COLLECT else '0';
  busy <= '1' when state /= S_COLLECT else '0';
  corr_valid <= valid_reg;
  corr_i <= corr_i_reg;
  corr_q <= corr_q_reg;
  corr_mag_sq <= mag_reg;

  process(clk)
    variable xi       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable xq       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable ci       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable cq       : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable prod_i   : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable prod_q   : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable mag_i    : signed((2 * G_ACC_WIDTH) - 1 downto 0);
    variable mag_q    : signed((2 * G_ACC_WIDTH) - 1 downto 0);
    variable mag_sum  : unsigned((2 * G_ACC_WIDTH) - 1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S_COLLECT;
        wr_idx <= 0;
        mac_idx <= 0;
        acc_i <= (others => '0');
        acc_q <= (others => '0');
        corr_i_reg <= (others => '0');
        corr_q_reg <= (others => '0');
        mag_reg <= (others => '0');
        valid_reg <= '0';
      else
        valid_reg <= '0';

        case state is
          when S_COLLECT =>
            if block_start = '1' then
              wr_idx <= 0;
            end if;

            if sample_valid = '1' then
              samples_i(wr_idx) <= sample_i;
              samples_q(wr_idx) <= sample_q;
              if wr_idx = ZC_REF_LEN - 1 then
                wr_idx <= 0;
                mac_idx <= 0;
                acc_i <= (others => '0');
                acc_q <= (others => '0');
                state <= S_MAC;
              else
                wr_idx <= wr_idx + 1;
              end if;
            end if;

          when S_MAC =>
            xi := samples_i(mac_idx);
            xq := samples_q(mac_idx);
            ci := sat_resize(ZC_REF_I(mac_idx), G_SAMPLE_WIDTH);
            cq := sat_resize(ZC_REF_Q(mac_idx), G_SAMPLE_WIDTH);

            -- x * conj(c): real = xi*ci + xq*cq, imag = xq*ci - xi*cq
            prod_i := shift_right(resize(xi * ci, prod_i'length) + resize(xq * cq, prod_i'length), G_PRODUCT_SHIFT);
            prod_q := shift_right(resize(xq * ci, prod_q'length) - resize(xi * cq, prod_q'length), G_PRODUCT_SHIFT);
            acc_i <= acc_i + resize(prod_i, G_ACC_WIDTH);
            acc_q <= acc_q + resize(prod_q, G_ACC_WIDTH);

            if mac_idx = ZC_REF_LEN - 1 then
              corr_i_reg <= acc_i + resize(prod_i, G_ACC_WIDTH);
              corr_q_reg <= acc_q + resize(prod_q, G_ACC_WIDTH);
              state <= S_DONE;
            else
              mac_idx <= mac_idx + 1;
            end if;

          when S_DONE =>
            mag_i := corr_i_reg * corr_i_reg;
            mag_q := corr_q_reg * corr_q_reg;
            mag_sum := unsigned(mag_i) + unsigned(mag_q);
            mag_reg <= mag_sum;
            valid_reg <= '1';
            state <= S_COLLECT;
        end case;
      end if;
    end if;
  end process;
end architecture;
