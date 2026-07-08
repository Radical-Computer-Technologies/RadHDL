library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Bidirectional I2S to AXI-Stream bridge.
-- Converts stereo I2S samples to AXI-Stream frames and AXI-Stream frames back to I2S while exposing clocking and enable controls through a RADIF register interface.
entity radif_i2s_axis is
  generic (
    -- Sample width per left/right channel.
    SAMPLE_WIDTH       : positive := 24;
    -- AXI-Stream payload width. The low half carries right-channel data and the high half carries left-channel data.
    AXIS_DATA_WIDTH    : positive := 64;
    -- Width of the RADIF register data bus.
    REG_DATA_WIDTH     : positive := 32;
    -- Width of the RADIF register address bus.
    REG_ADDR_WIDTH     : positive := 16;
    -- Default MCLK half-period divider. Ignored when GENERATE_MCLK is false.
    DEFAULT_MCLK_DIV   : natural  := 1;
    -- Default BCLK half-period divider used when USE_EXTERNAL_BCLK is false.
    DEFAULT_BCLK_DIV   : natural  := 7;
    -- Default number of BCLK rising edges per LRCK half-frame.
    DEFAULT_LRCK_BITS  : positive := 32;
    -- Use the external MCLK pin as a timing reference indicator instead of generating MCLK.
    USE_EXTERNAL_MCLK  : boolean  := false;
    -- Disable MCLK generation and leave MCLK output released.
    NO_MCLK            : boolean  := false;
    -- Use the external BCLK/LRCK pins for I2S timing instead of generating them.
    USE_EXTERNAL_BCLK  : boolean  := false;
    -- Emit I2S-to-AXIS receive datapath logic.
    ENABLE_I2S_TO_AXIS : boolean  := true;
    -- Emit AXIS-to-I2S transmit datapath logic.
    ENABLE_AXIS_TO_I2S : boolean  := true;
    -- Selects the vendor-specific implementation path. This core is portable RTL for all values.
    VENDOR_TAG         : string   := "GENERIC";
    -- Identifies the target FPGA family for generated project metadata.
    PRODUCT_SERIES_TAG : string   := "GENERIC"
  );
  port (
    -- FPGA/register clock domain.
    clk           : in  std_logic;
    -- Active-low reset for the FPGA/register clock domain.
    rstn          : in  std_logic;

    -- Register write address.
    reg_wr_addr   : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- Register read address.
    reg_rd_addr   : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- One-cycle register write request.
    reg_wr_en     : in  std_logic;
    -- One-cycle register read request.
    reg_rd_en     : in  std_logic;
    -- Register write data.
    reg_data_in   : in  std_logic_vector(REG_DATA_WIDTH - 1 downto 0);
    -- Register read data.
    reg_data_out  : out std_logic_vector(REG_DATA_WIDTH - 1 downto 0);
    -- Register write ready.
    reg_wr_rdy    : out std_logic;
    -- Register read ready.
    reg_rd_rdy    : out std_logic;
    -- Register write response valid.
    reg_wr_valid  : out std_logic;
    -- Register read response valid.
    reg_rd_valid  : out std_logic;
    -- Register address or runtime error.
    reg_error     : out std_logic;

    -- External MCLK input when USE_EXTERNAL_MCLK is true.
    i2s_mclk_i    : in  std_logic;
    -- Generated MCLK output when enabled.
    i2s_mclk_o    : out std_logic;
    -- MCLK output-enable. A value of 1 enables the generated MCLK output.
    i2s_mclk_oe   : out std_logic;
    -- External BCLK input when USE_EXTERNAL_BCLK is true.
    i2s_bclk_i    : in  std_logic;
    -- Generated BCLK output when USE_EXTERNAL_BCLK is false.
    i2s_bclk_o    : out std_logic;
    -- BCLK output-enable. A value of 1 enables the generated BCLK output.
    i2s_bclk_oe   : out std_logic;
    -- External LRCK input when USE_EXTERNAL_BCLK is true.
    i2s_lrck_i    : in  std_logic;
    -- Generated LRCK output when USE_EXTERNAL_BCLK is false.
    i2s_lrck_o    : out std_logic;
    -- LRCK output-enable. A value of 1 enables the generated LRCK output.
    i2s_lrck_oe   : out std_logic;
    -- I2S serial data input.
    i2s_sdata_i   : in  std_logic;
    -- I2S serial data output.
    i2s_sdata_o   : out std_logic;
    -- Serial data output-enable. A value of 1 enables the generated serial data output.
    i2s_sdata_oe  : out std_logic;

    -- AXI-Stream output generated from received I2S stereo frames.
    m_axis_tdata  : out std_logic_vector(AXIS_DATA_WIDTH - 1 downto 0);
    -- AXI-Stream output valid.
    m_axis_tvalid : out std_logic;
    -- AXI-Stream output ready.
    m_axis_tready : in  std_logic;
    -- AXI-Stream output frame marker.
    m_axis_tlast  : out std_logic;

    -- AXI-Stream input consumed for I2S transmit stereo frames.
    s_axis_tdata  : in  std_logic_vector(AXIS_DATA_WIDTH - 1 downto 0);
    -- AXI-Stream input valid.
    s_axis_tvalid : in  std_logic;
    -- AXI-Stream input ready.
    s_axis_tready : out std_logic;
    -- AXI-Stream input frame marker.
    s_axis_tlast  : in  std_logic
  );
end entity;

architecture rtl of radif_i2s_axis is
  constant C_REG_CONTROL      : natural := 16#00#;
  constant C_REG_STATUS       : natural := 16#04#;
  constant C_REG_MCLK_DIV     : natural := 16#08#;
  constant C_REG_BCLK_DIV     : natural := 16#0C#;
  constant C_REG_LRCK_BITS    : natural := 16#10#;
  constant C_REG_RX_COUNT     : natural := 16#14#;
  constant C_REG_TX_COUNT     : natural := 16#18#;

  signal control_r      : std_logic_vector(REG_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal status_r       : std_logic_vector(REG_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal mclk_div_r     : unsigned(15 downto 0) := to_unsigned(DEFAULT_MCLK_DIV, 16);
  signal bclk_div_r     : unsigned(15 downto 0) := to_unsigned(DEFAULT_BCLK_DIV, 16);
  signal lrck_bits_r    : unsigned(15 downto 0) := to_unsigned(DEFAULT_LRCK_BITS, 16);
  signal rx_count_r     : unsigned(31 downto 0) := (others => '0');
  signal tx_count_r     : unsigned(31 downto 0) := (others => '0');
  signal rd_data_r      : std_logic_vector(REG_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_valid_r     : std_logic := '0';
  signal rd_valid_r     : std_logic := '0';
  signal error_r        : std_logic := '0';

  signal mclk_count     : unsigned(15 downto 0) := (others => '0');
  signal bclk_count     : unsigned(15 downto 0) := (others => '0');
  signal lrck_count     : unsigned(15 downto 0) := (others => '0');
  signal mclk_r         : std_logic := '0';
  signal bclk_r         : std_logic := '0';
  signal lrck_r         : std_logic := '0';
  signal bclk_meta      : std_logic := '0';
  signal bclk_sync      : std_logic := '0';
  signal bclk_prev      : std_logic := '0';
  signal lrck_meta      : std_logic := '0';
  signal lrck_sync      : std_logic := '0';
  signal lrck_prev      : std_logic := '0';
  signal bclk_rise      : std_logic := '0';
  signal lrck_change    : std_logic := '0';

  signal rx_left        : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal rx_right       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal rx_shift       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal rx_bit_count   : natural range 0 to SAMPLE_WIDTH := 0;
  signal rx_axis_data   : std_logic_vector(AXIS_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal rx_axis_valid  : std_logic := '0';

  signal tx_axis_ready  : std_logic := '0';
  signal tx_loaded      : std_logic := '0';
  signal tx_left        : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal tx_right       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal tx_shift       : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal tx_bit_count   : natural range 0 to SAMPLE_WIDTH := 0;
  signal sdata_o_r      : std_logic := '0';

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

  function pack_stereo(left_sample : std_logic_vector; right_sample : std_logic_vector) return std_logic_vector is
    variable packed : std_logic_vector(AXIS_DATA_WIDTH - 1 downto 0) := (others => '0');
    constant HALF_WIDTH : natural := AXIS_DATA_WIDTH / 2;
  begin
    if HALF_WIDTH >= SAMPLE_WIDTH then
      packed(HALF_WIDTH + SAMPLE_WIDTH - 1 downto HALF_WIDTH) := left_sample;
      packed(SAMPLE_WIDTH - 1 downto 0) := right_sample;
    else
      packed(AXIS_DATA_WIDTH - 1 downto HALF_WIDTH) := left_sample(SAMPLE_WIDTH - 1 downto SAMPLE_WIDTH - HALF_WIDTH);
      packed(HALF_WIDTH - 1 downto 0) := right_sample(SAMPLE_WIDTH - 1 downto SAMPLE_WIDTH - HALF_WIDTH);
    end if;
    return packed;
  end function;

  function unpack_left(data : std_logic_vector) return std_logic_vector is
    variable sample : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
    constant HALF_WIDTH : natural := AXIS_DATA_WIDTH / 2;
  begin
    if HALF_WIDTH >= SAMPLE_WIDTH then
      sample := data(HALF_WIDTH + SAMPLE_WIDTH - 1 downto HALF_WIDTH);
    else
      sample(SAMPLE_WIDTH - 1 downto SAMPLE_WIDTH - HALF_WIDTH) := data(AXIS_DATA_WIDTH - 1 downto HALF_WIDTH);
    end if;
    return sample;
  end function;

  function unpack_right(data : std_logic_vector) return std_logic_vector is
    variable sample : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
    constant HALF_WIDTH : natural := AXIS_DATA_WIDTH / 2;
  begin
    if HALF_WIDTH >= SAMPLE_WIDTH then
      sample := data(SAMPLE_WIDTH - 1 downto 0);
    else
      sample(SAMPLE_WIDTH - 1 downto SAMPLE_WIDTH - HALF_WIDTH) := data(HALF_WIDTH - 1 downto 0);
    end if;
    return sample;
  end function;
begin
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;

  i2s_mclk_o <= mclk_r;
  i2s_mclk_oe <= '1' when (not USE_EXTERNAL_MCLK) and (not NO_MCLK) else '0';
  i2s_bclk_o <= bclk_r;
  i2s_bclk_oe <= '0' when USE_EXTERNAL_BCLK else '1';
  i2s_lrck_o <= lrck_r;
  i2s_lrck_oe <= '0' when USE_EXTERNAL_BCLK else '1';
  i2s_sdata_o <= sdata_o_r;
  i2s_sdata_oe <= control_r(1) when ENABLE_AXIS_TO_I2S else '0';

  m_axis_tdata <= rx_axis_data;
  m_axis_tvalid <= rx_axis_valid;
  m_axis_tlast <= rx_axis_valid;
  s_axis_tready <= tx_axis_ready;

  process(clk)
    variable idx : natural;
    variable bclk_rise_now : boolean;
    variable lrck_change_now : boolean;
  begin
    if rising_edge(clk) then
      bclk_rise_now := false;
      lrck_change_now := false;
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';
      bclk_rise <= '0';
      lrck_change <= '0';

      bclk_meta <= i2s_bclk_i;
      bclk_sync <= bclk_meta;
      bclk_prev <= bclk_sync;
      lrck_meta <= i2s_lrck_i;
      lrck_sync <= lrck_meta;
      lrck_prev <= lrck_sync;

      if rstn = '0' then
        control_r <= (others => '0');
        status_r <= (others => '0');
        mclk_div_r <= to_unsigned(DEFAULT_MCLK_DIV, 16);
        bclk_div_r <= to_unsigned(DEFAULT_BCLK_DIV, 16);
        lrck_bits_r <= to_unsigned(DEFAULT_LRCK_BITS, 16);
        rx_count_r <= (others => '0');
        tx_count_r <= (others => '0');
        mclk_count <= (others => '0');
        bclk_count <= (others => '0');
        lrck_count <= (others => '0');
        mclk_r <= '0';
        bclk_r <= '0';
        lrck_r <= '0';
        rx_axis_valid <= '0';
        tx_axis_ready <= '0';
        tx_loaded <= '0';
        sdata_o_r <= '0';
      else
        if reg_wr_en = '1' then
          wr_valid_r <= '1';
          idx := reg_index(reg_wr_addr);
          case idx is
            when C_REG_CONTROL =>
              control_r <= reg_data_in;
              if reg_data_in(2) = '1' then
                status_r(1) <= '0';
                status_r(2) <= '0';
                rx_count_r <= (others => '0');
                tx_count_r <= (others => '0');
              end if;
            when C_REG_MCLK_DIV =>
              mclk_div_r <= unsigned(reg_data_in(15 downto 0));
            when C_REG_BCLK_DIV =>
              bclk_div_r <= unsigned(reg_data_in(15 downto 0));
            when C_REG_LRCK_BITS =>
              lrck_bits_r <= unsigned(reg_data_in(15 downto 0));
            when others =>
              error_r <= '1';
          end case;
        end if;

        if reg_rd_en = '1' then
          rd_valid_r <= '1';
          idx := reg_index(reg_rd_addr);
          case idx is
            when C_REG_CONTROL => rd_data_r <= control_r;
            when C_REG_STATUS =>
              rd_data_r <= status_r;
              rd_data_r(0) <= tx_loaded or rx_axis_valid;
              if USE_EXTERNAL_MCLK then
                rd_data_r(8) <= '1';
              else
                rd_data_r(8) <= '0';
              end if;
              if USE_EXTERNAL_BCLK then
                rd_data_r(9) <= '1';
              else
                rd_data_r(9) <= '0';
              end if;
              if NO_MCLK then
                rd_data_r(10) <= '1';
              else
                rd_data_r(10) <= '0';
              end if;
            when C_REG_MCLK_DIV =>
              rd_data_r <= (others => '0');
              rd_data_r(15 downto 0) <= std_logic_vector(mclk_div_r);
            when C_REG_BCLK_DIV =>
              rd_data_r <= (others => '0');
              rd_data_r(15 downto 0) <= std_logic_vector(bclk_div_r);
            when C_REG_LRCK_BITS =>
              rd_data_r <= (others => '0');
              rd_data_r(15 downto 0) <= std_logic_vector(lrck_bits_r);
            when C_REG_RX_COUNT =>
              rd_data_r <= std_logic_vector(rx_count_r(REG_DATA_WIDTH - 1 downto 0));
            when C_REG_TX_COUNT =>
              rd_data_r <= std_logic_vector(tx_count_r(REG_DATA_WIDTH - 1 downto 0));
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;

        if not USE_EXTERNAL_MCLK and not NO_MCLK then
          if mclk_count = 0 then
            mclk_count <= mclk_div_r;
            mclk_r <= not mclk_r;
          else
            mclk_count <= mclk_count - 1;
          end if;
        end if;

        if USE_EXTERNAL_BCLK then
          if bclk_sync = '1' and bclk_prev = '0' then
            bclk_rise <= '1';
            bclk_rise_now := true;
          end if;
          if lrck_sync /= lrck_prev then
            lrck_change <= '1';
            lrck_change_now := true;
          end if;
        else
          if bclk_count = 0 then
            bclk_count <= bclk_div_r;
            bclk_r <= not bclk_r;
            if bclk_r = '0' then
              bclk_rise <= '1';
              bclk_rise_now := true;
              if lrck_count = lrck_bits_r - 1 then
                lrck_count <= (others => '0');
                lrck_r <= not lrck_r;
                lrck_change <= '1';
                lrck_change_now := true;
              else
                lrck_count <= lrck_count + 1;
              end if;
            end if;
          else
            bclk_count <= bclk_count - 1;
          end if;
        end if;

        if rx_axis_valid = '1' and m_axis_tready = '1' then
          rx_axis_valid <= '0';
        end if;

        tx_axis_ready <= '0';
        if ENABLE_AXIS_TO_I2S and control_r(1) = '1' and tx_loaded = '0' then
          tx_axis_ready <= '1';
          if s_axis_tvalid = '1' then
            tx_left <= unpack_left(s_axis_tdata);
            tx_right <= unpack_right(s_axis_tdata);
            tx_loaded <= '1';
            tx_bit_count <= 0;
            tx_axis_ready <= '0';
          end if;
        end if;

        if bclk_rise_now then
          if ENABLE_I2S_TO_AXIS and control_r(0) = '1' then
            if lrck_change_now then
              rx_bit_count <= 0;
              rx_shift <= (others => '0');
            elsif rx_bit_count < SAMPLE_WIDTH then
              rx_shift <= rx_shift(SAMPLE_WIDTH - 2 downto 0) & i2s_sdata_i;
              rx_bit_count <= rx_bit_count + 1;
              if rx_bit_count = SAMPLE_WIDTH - 1 then
                if (USE_EXTERNAL_BCLK and lrck_sync = '0') or ((not USE_EXTERNAL_BCLK) and lrck_r = '0') then
                  rx_left <= rx_shift(SAMPLE_WIDTH - 2 downto 0) & i2s_sdata_i;
                else
                  rx_right <= rx_shift(SAMPLE_WIDTH - 2 downto 0) & i2s_sdata_i;
                  rx_axis_data <= pack_stereo(rx_left, rx_shift(SAMPLE_WIDTH - 2 downto 0) & i2s_sdata_i);
                  rx_axis_valid <= '1';
                  rx_count_r <= rx_count_r + 1;
                end if;
              end if;
            end if;
          end if;

          if ENABLE_AXIS_TO_I2S and control_r(1) = '1' and tx_loaded = '1' then
            if lrck_change_now then
              tx_bit_count <= 0;
              if (USE_EXTERNAL_BCLK and lrck_sync = '0') or ((not USE_EXTERNAL_BCLK) and lrck_r = '0') then
                tx_shift <= tx_left;
              else
                tx_shift <= tx_right;
              end if;
            elsif tx_bit_count < SAMPLE_WIDTH then
              sdata_o_r <= tx_shift(SAMPLE_WIDTH - 1);
              tx_shift <= tx_shift(SAMPLE_WIDTH - 2 downto 0) & '0';
              tx_bit_count <= tx_bit_count + 1;
              if tx_bit_count = SAMPLE_WIDTH - 1 and ((USE_EXTERNAL_BCLK and lrck_sync = '1') or ((not USE_EXTERNAL_BCLK) and lrck_r = '1')) then
                tx_loaded <= '0';
                tx_count_r <= tx_count_r + 1;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
