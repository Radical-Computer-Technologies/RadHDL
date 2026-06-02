library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.zc_reference_pkg.all;

entity zc_chirp_frame_detector is
  generic (
    G_SAMPLE_WIDTH      : integer := 16;
    G_ACC_WIDTH         : integer := 40;
    G_FRAME_SAMPLES     : integer := 1024;
    G_CHIRP_LEN         : integer := 512;
    G_CHIRP_AFTER_PEAK  : integer := 160;
    G_PRODUCT_SHIFT     : integer := 15
  );
  port (
    clk              : in  std_logic;
    rst              : in  std_logic;
    frame_start      : in  std_logic;
    sample_valid     : in  std_logic;
    sample_i         : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    sample_q         : in  signed(G_SAMPLE_WIDTH - 1 downto 0);
    sample_ready     : out std_logic;
    processing       : out std_logic;
    peak_valid       : out std_logic;
    peak_index       : out integer range 0 to G_FRAME_SAMPLES - 1;
    peak_i           : out signed(G_ACC_WIDTH - 1 downto 0);
    peak_q           : out signed(G_ACC_WIDTH - 1 downto 0);
    chirp_valid      : out std_logic;
    chirp_index      : out integer range 0 to G_CHIRP_LEN - 1;
    chirp_i          : out signed(G_SAMPLE_WIDTH - 1 downto 0);
    chirp_q          : out signed(G_SAMPLE_WIDTH - 1 downto 0);
    chirp_done       : out std_logic
  );
end entity;

architecture rtl of zc_chirp_frame_detector is
  constant C_LAST_OFFSET : integer := G_FRAME_SAMPLES - ZC_REF_LEN;

  type sample_array_t is array (0 to G_FRAME_SAMPLES - 1) of signed(G_SAMPLE_WIDTH - 1 downto 0);
  type state_t is (
    S_CAPTURE,
    S_SCAN_ADDR,
    S_SCAN,
    S_MAG_SQUARE,
    S_MAG_SUM,
    S_SCORE,
    S_REPLAY_ADDR,
    S_REPLAY_WAIT,
    S_REPLAY_EMIT,
    S_DONE
  );

  signal state      : state_t := S_CAPTURE;
  signal wr_idx     : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal offset_idx : integer range 0 to C_LAST_OFFSET := 0;
  signal zc_idx     : integer range 0 to ZC_REF_LEN - 1 := 0;
  signal replay_idx : integer range 0 to G_CHIRP_LEN - 1 := 0;
  signal chirp_base : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  -- Duplicate sample storage gives the correlator two independent BRAM read
  -- ports during scan without asking inference for a three-port memory.
  signal frame_i0   : sample_array_t := (others => (others => '0'));
  signal frame_q0   : sample_array_t := (others => (others => '0'));
  signal frame_i1   : sample_array_t := (others => (others => '0'));
  signal frame_q1   : sample_array_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of frame_i0 : signal is "block";
  attribute ram_style of frame_q0 : signal is "block";
  attribute ram_style of frame_i1 : signal is "block";
  attribute ram_style of frame_q1 : signal is "block";
  signal frame_rd_addr0 : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal frame_rd_addr1 : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal frame_rd_i0    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal frame_rd_q0    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal frame_rd_i1    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal frame_rd_q1    : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal acc_i      : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal acc_q      : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_i     : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_q     : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal best_mag   : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal best_idx   : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal candidate_i   : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal candidate_q   : signed(G_ACC_WIDTH - 1 downto 0) := (others => '0');
  signal candidate_idx : integer range 0 to G_FRAME_SAMPLES - 1 := 0;
  signal mag_i_reg     : signed((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal mag_q_reg     : signed((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal candidate_mag : unsigned((2 * G_ACC_WIDTH) - 1 downto 0) := (others => '0');
  signal peak_v     : std_logic := '0';
  signal chirp_v    : std_logic := '0';
  signal chirp_index_r : integer range 0 to G_CHIRP_LEN - 1 := 0;
  signal chirp_i_r   : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal chirp_q_r   : signed(G_SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal chirp_done_r : std_logic := '0';

  function coeff(value : integer; width : integer) return signed is
  begin
    return resize(to_signed(value, 32), width);
  end function;
begin
  -- The input side only deasserts ready after the configured frame is captured.
  -- In a live design, put this behind a FIFO or ping-pong this module if frames
  -- arrive back-to-back with no inter-frame gap.
  sample_ready <= '1' when state = S_CAPTURE else '0';
  processing <= '1' when state /= S_CAPTURE else '0';
  peak_valid <= peak_v;
  peak_index <= best_idx;
  peak_i <= best_i;
  peak_q <= best_q;
  chirp_valid <= chirp_v;
  chirp_index <= chirp_index_r;
  chirp_i <= chirp_i_r;
  chirp_q <= chirp_q_r;
  chirp_done <= chirp_done_r;

  process(clk)
    variable xi0      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable xq0      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable xi1      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable xq1      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable ci0      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable cq0      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable ci1      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable cq1      : signed(G_SAMPLE_WIDTH - 1 downto 0);
    variable prod_i0  : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable prod_q0  : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable prod_i1  : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable prod_q1  : signed((2 * G_SAMPLE_WIDTH) downto 0);
    variable next_i   : signed(G_ACC_WIDTH - 1 downto 0);
    variable next_q   : signed(G_ACC_WIDTH - 1 downto 0);
    variable score_idx : integer range 0 to G_FRAME_SAMPLES - 1;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S_CAPTURE;
        wr_idx <= 0;
        offset_idx <= 0;
        zc_idx <= 0;
        replay_idx <= 0;
        chirp_base <= 0;
        acc_i <= (others => '0');
        acc_q <= (others => '0');
        best_i <= (others => '0');
        best_q <= (others => '0');
        best_mag <= (others => '0');
        best_idx <= 0;
        candidate_i <= (others => '0');
        candidate_q <= (others => '0');
        candidate_idx <= 0;
        mag_i_reg <= (others => '0');
        mag_q_reg <= (others => '0');
        candidate_mag <= (others => '0');
        peak_v <= '0';
        chirp_v <= '0';
        chirp_index_r <= 0;
        chirp_i_r <= (others => '0');
        chirp_q_r <= (others => '0');
        chirp_done_r <= '0';
      else
        frame_rd_i0 <= frame_i0(frame_rd_addr0);
        frame_rd_q0 <= frame_q0(frame_rd_addr0);
        frame_rd_i1 <= frame_i1(frame_rd_addr1);
        frame_rd_q1 <= frame_q1(frame_rd_addr1);
        peak_v <= '0';
        chirp_v <= '0';
        chirp_done_r <= '0';

        case state is
          when S_CAPTURE =>
            if frame_start = '1' then
              wr_idx <= 0;
            end if;
            if sample_valid = '1' then
              frame_i0(wr_idx) <= sample_i;
              frame_q0(wr_idx) <= sample_q;
              frame_i1(wr_idx) <= sample_i;
              frame_q1(wr_idx) <= sample_q;
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
                candidate_i <= (others => '0');
                candidate_q <= (others => '0');
                candidate_idx <= 0;
                mag_i_reg <= (others => '0');
                mag_q_reg <= (others => '0');
                candidate_mag <= (others => '0');
                frame_rd_addr0 <= 0;
                frame_rd_addr1 <= 1;
                state <= S_SCAN_ADDR;
              else
                wr_idx <= wr_idx + 1;
              end if;
            end if;

          when S_SCAN_ADDR =>
            state <= S_SCAN;

          when S_SCAN =>
            xi0 := frame_rd_i0;
            xq0 := frame_rd_q0;
            ci0 := coeff(ZC_REF_I(zc_idx), G_SAMPLE_WIDTH);
            cq0 := coeff(ZC_REF_Q(zc_idx), G_SAMPLE_WIDTH);
            prod_i0 := shift_right(resize(xi0 * ci0, prod_i0'length) + resize(xq0 * cq0, prod_i0'length), G_PRODUCT_SHIFT);
            prod_q0 := shift_right(resize(xq0 * ci0, prod_q0'length) - resize(xi0 * cq0, prod_q0'length), G_PRODUCT_SHIFT);
            next_i := acc_i + resize(prod_i0, G_ACC_WIDTH);
            next_q := acc_q + resize(prod_q0, G_ACC_WIDTH);
            if zc_idx < ZC_REF_LEN - 1 then
              xi1 := frame_rd_i1;
              xq1 := frame_rd_q1;
              ci1 := coeff(ZC_REF_I(zc_idx + 1), G_SAMPLE_WIDTH);
              cq1 := coeff(ZC_REF_Q(zc_idx + 1), G_SAMPLE_WIDTH);
              prod_i1 := shift_right(resize(xi1 * ci1, prod_i1'length) + resize(xq1 * cq1, prod_i1'length), G_PRODUCT_SHIFT);
              prod_q1 := shift_right(resize(xq1 * ci1, prod_q1'length) - resize(xi1 * cq1, prod_q1'length), G_PRODUCT_SHIFT);
              next_i := next_i + resize(prod_i1, G_ACC_WIDTH);
              next_q := next_q + resize(prod_q1, G_ACC_WIDTH);
            end if;
            acc_i <= next_i;
            acc_q <= next_q;
            if zc_idx >= ZC_REF_LEN - 2 then
              candidate_i <= next_i;
              candidate_q <= next_q;
              candidate_idx <= offset_idx + (ZC_REF_LEN / 2);
              state <= S_MAG_SQUARE;
            else
              zc_idx <= zc_idx + 2;
              frame_rd_addr0 <= offset_idx + zc_idx + 2;
              frame_rd_addr1 <= offset_idx + zc_idx + 3;
              state <= S_SCAN_ADDR;
            end if;

          when S_MAG_SQUARE =>
            mag_i_reg <= candidate_i * candidate_i;
            mag_q_reg <= candidate_q * candidate_q;
            state <= S_MAG_SUM;

          when S_MAG_SUM =>
            candidate_mag <= unsigned(mag_i_reg) + unsigned(mag_q_reg);
            state <= S_SCORE;

          when S_SCORE =>
            score_idx := best_idx;
            if candidate_mag > best_mag then
              best_mag <= candidate_mag;
              best_i <= candidate_i;
              best_q <= candidate_q;
              best_idx <= candidate_idx;
              score_idx := candidate_idx;
            end if;
            acc_i <= (others => '0');
            acc_q <= (others => '0');
            zc_idx <= 0;
            if offset_idx = C_LAST_OFFSET then
              peak_v <= '1';
              if score_idx + G_CHIRP_AFTER_PEAK < G_FRAME_SAMPLES then
                chirp_base <= score_idx + G_CHIRP_AFTER_PEAK;
              else
                chirp_base <= G_FRAME_SAMPLES - 1;
              end if;
              replay_idx <= 0;
              state <= S_REPLAY_ADDR;
            else
              offset_idx <= offset_idx + 1;
              frame_rd_addr0 <= offset_idx + 1;
              frame_rd_addr1 <= offset_idx + 2;
              state <= S_SCAN_ADDR;
            end if;

          when S_REPLAY_ADDR =>
            if chirp_base + replay_idx < G_FRAME_SAMPLES then
              frame_rd_addr0 <= chirp_base + replay_idx;
            else
              frame_rd_addr0 <= G_FRAME_SAMPLES - 1;
            end if;
            state <= S_REPLAY_WAIT;

          when S_REPLAY_WAIT =>
            state <= S_REPLAY_EMIT;

          when S_REPLAY_EMIT =>
            chirp_v <= '1';
            chirp_index_r <= replay_idx;
            chirp_i_r <= frame_rd_i0;
            chirp_q_r <= frame_rd_q0;
            if replay_idx = G_CHIRP_LEN - 1 or chirp_base + replay_idx >= G_FRAME_SAMPLES - 1 then
              chirp_done_r <= '1';
              state <= S_DONE;
            else
              replay_idx <= replay_idx + 1;
              state <= S_REPLAY_ADDR;
            end if;

          when S_DONE =>
            state <= S_CAPTURE;
        end case;
      end if;
    end if;
  end process;
end architecture;
