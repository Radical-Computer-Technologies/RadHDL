library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Register-controlled SPI master.
-- Provides a small software-visible register bank that launches single-word, 4-wire SPI transfers with programmable SCLK timing, chip-select polarity, clock polarity, and clock phase.
entity radif_reg_to_spi_master is
  generic (
    -- Width of the RADIF register data bus and the maximum SPI transfer word.
    DATA_WIDTH         : positive := 32;
    -- Width of the RADIF register address bus.
    REG_ADDR_WIDTH     : positive := 16;
    -- Default half-period divider for SCLK generation. The active half-period is divider + 1 FPGA clock cycles.
    DEFAULT_SCLK_DIV   : natural  := 124;
    -- Default number of bits shifted per transfer.
    DEFAULT_BIT_COUNT  : positive := 8;
    -- Selects the vendor-specific implementation path. This core is portable RTL for all values.
    VENDOR_TAG         : string   := "GENERIC";
    -- Identifies the target FPGA family for generated project metadata.
    PRODUCT_SERIES_TAG : string   := "GENERIC"
  );
  port (
    -- FPGA/register clock domain.
    clk          : in  std_logic;
    -- Active-low reset for the FPGA/register clock domain.
    rstn         : in  std_logic;

    -- Register write address.
    reg_wr_addr  : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- Register read address.
    reg_rd_addr  : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- One-cycle register write request.
    reg_wr_en    : in  std_logic;
    -- One-cycle register read request.
    reg_rd_en    : in  std_logic;
    -- Register write data.
    reg_data_in  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register read data.
    reg_data_out : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register write ready.
    reg_wr_rdy   : out std_logic;
    -- Register read ready.
    reg_rd_rdy   : out std_logic;
    -- Register write response valid.
    reg_wr_valid : out std_logic;
    -- Register read response valid.
    reg_rd_valid : out std_logic;
    -- Register address or transaction error.
    reg_error    : out std_logic;

    -- SPI serial clock.
    spi_sclk_o   : out std_logic;
    -- SPI chip select, active low by default.
    spi_cs_n_o   : out std_logic;
    -- SPI master-out/slave-in data.
    spi_mosi_o   : out std_logic;
    -- SPI master-in/slave-out data sampled into the RX_DATA register.
    spi_miso_i   : in  std_logic
  );
end entity;

architecture rtl of radif_reg_to_spi_master is
  constant C_REG_CONTROL  : natural := 16#00#;
  constant C_REG_STATUS   : natural := 16#04#;
  constant C_REG_CLK_DIV  : natural := 16#08#;
  constant C_REG_CONFIG   : natural := 16#0C#;
  constant C_REG_TX_DATA  : natural := 16#10#;
  constant C_REG_RX_DATA  : natural := 16#14#;

  type state_t is (IDLE, ASSERT_CS, SHIFT_LOW, SHIFT_HIGH, COMPLETE);

  signal control_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal status_r     : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal clk_div_r    : unsigned(15 downto 0) := to_unsigned(DEFAULT_SCLK_DIV, 16);
  signal config_r     : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal tx_data_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal rx_data_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal shift_tx_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal shift_rx_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal state        : state_t := IDLE;
  signal div_count    : unsigned(15 downto 0) := (others => '0');
  signal bit_count    : natural range 0 to DATA_WIDTH := 0;
  signal bits_total   : natural range 1 to DATA_WIDTH := 8;
  signal sclk_r       : std_logic := '0';
  signal cs_n_r       : std_logic := '1';
  signal mosi_r       : std_logic := '0';
  signal wr_valid_r   : std_logic := '0';
  signal rd_valid_r   : std_logic := '0';
  signal error_r      : std_logic := '0';
  signal rd_data_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

  function clamp_bits(value : std_logic_vector) return natural is
    variable requested : natural;
  begin
    requested := to_integer(unsigned(value));
    if requested < 1 then
      return 1;
    elsif requested > DATA_WIDTH then
      return DATA_WIDTH;
    end if;
    return requested;
  end function;

  function default_bits return natural is
  begin
    if DEFAULT_BIT_COUNT > DATA_WIDTH then
      return DATA_WIDTH;
    end if;
    return DEFAULT_BIT_COUNT;
  end function;

  function cpol(cfg : std_logic_vector) return std_logic is
  begin
    return cfg(0);
  end function;

  function cpha(cfg : std_logic_vector) return std_logic is
  begin
    return cfg(1);
  end function;
begin
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;
  spi_sclk_o <= sclk_r;
  spi_cs_n_o <= cs_n_r when config_r(2) = '0' else not cs_n_r;
  spi_mosi_o <= mosi_r;

  process(clk)
    variable idx : natural;
    variable next_status : std_logic_vector(DATA_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';
      next_status := status_r;
      if state /= IDLE then
        next_status(0) := '1';
      else
        next_status(0) := '0';
      end if;
      next_status(1) := status_r(1);
      next_status(2) := status_r(2);

      if rstn = '0' then
        control_r <= (others => '0');
        status_r <= (others => '0');
        clk_div_r <= to_unsigned(DEFAULT_SCLK_DIV, 16);
        config_r <= (others => '0');
        config_r(15 downto 8) <= std_logic_vector(to_unsigned(default_bits, 8));
        tx_data_r <= (others => '0');
        rx_data_r <= (others => '0');
        shift_tx_r <= (others => '0');
        shift_rx_r <= (others => '0');
        state <= IDLE;
        div_count <= (others => '0');
        bit_count <= 0;
        bits_total <= default_bits;
        sclk_r <= '0';
        cs_n_r <= '1';
        mosi_r <= '0';
      else
        if reg_wr_en = '1' then
          wr_valid_r <= '1';
          idx := reg_index(reg_wr_addr);
          case idx is
            when C_REG_CONTROL =>
              control_r <= reg_data_in;
              if reg_data_in(1) = '1' then
                status_r(1) <= '0';
                status_r(2) <= '0';
              end if;
              if reg_data_in(0) = '1' and state = IDLE then
                shift_tx_r <= tx_data_r;
                shift_rx_r <= (others => '0');
                bits_total <= clamp_bits(config_r(15 downto 8));
                bit_count <= clamp_bits(config_r(15 downto 8));
                div_count <= clk_div_r;
                sclk_r <= cpol(config_r);
                cs_n_r <= '0';
                mosi_r <= tx_data_r(DATA_WIDTH - 1);
                status_r(1) <= '0';
                status_r(2) <= '0';
                state <= ASSERT_CS;
              elsif reg_data_in(0) = '1' and state /= IDLE then
                status_r(2) <= '1';
              end if;
            when C_REG_CLK_DIV =>
              clk_div_r <= unsigned(reg_data_in(15 downto 0));
            when C_REG_CONFIG =>
              config_r <= reg_data_in;
            when C_REG_TX_DATA =>
              tx_data_r <= reg_data_in;
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
              rd_data_r <= next_status;
            when C_REG_CLK_DIV =>
              rd_data_r <= (others => '0');
              rd_data_r(15 downto 0) <= std_logic_vector(clk_div_r);
            when C_REG_CONFIG => rd_data_r <= config_r;
            when C_REG_TX_DATA => rd_data_r <= tx_data_r;
            when C_REG_RX_DATA => rd_data_r <= rx_data_r;
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;

        case state is
          when IDLE =>
            sclk_r <= cpol(config_r);
            cs_n_r <= '1';
            next_status(0) := '0';

          when ASSERT_CS =>
            cs_n_r <= '0';
            if div_count = 0 then
              div_count <= clk_div_r;
              if cpha(config_r) = '0' then
                state <= SHIFT_HIGH;
              else
                sclk_r <= not cpol(config_r);
                state <= SHIFT_LOW;
              end if;
            else
              div_count <= div_count - 1;
            end if;

          when SHIFT_LOW =>
            cs_n_r <= '0';
            if div_count = 0 then
              div_count <= clk_div_r;
              sclk_r <= not cpol(config_r);
              state <= SHIFT_HIGH;
            else
              div_count <= div_count - 1;
            end if;

          when SHIFT_HIGH =>
            cs_n_r <= '0';
            if div_count = 0 then
              div_count <= clk_div_r;
              shift_rx_r <= shift_rx_r(DATA_WIDTH - 2 downto 0) & spi_miso_i;
              sclk_r <= cpol(config_r);
              if bit_count <= 1 then
                state <= COMPLETE;
              else
                bit_count <= bit_count - 1;
                shift_tx_r <= shift_tx_r(DATA_WIDTH - 2 downto 0) & '0';
                mosi_r <= shift_tx_r(DATA_WIDTH - 2);
                state <= SHIFT_LOW;
              end if;
            else
              div_count <= div_count - 1;
            end if;

          when COMPLETE =>
            rx_data_r <= shift_rx_r;
            status_r(1) <= '1';
            cs_n_r <= '1';
            state <= IDLE;
        end case;

        if state /= IDLE then
          status_r(0) <= '1';
        else
          status_r(0) <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
