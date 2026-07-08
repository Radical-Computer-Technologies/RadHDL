library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Register-controlled I2C master.
-- Launches one-byte I2C read or write transactions from a RADIF register interface with programmable SCL timing.
entity radif_reg_to_i2c_master is
  generic (
    -- Width of the RADIF register data bus.
    DATA_WIDTH         : positive := 32;
    -- Width of the RADIF register address bus.
    REG_ADDR_WIDTH     : positive := 16;
    -- Default SCL half-period divider. The active half-period is divider + 1 FPGA clock cycles.
    DEFAULT_SCL_DIV    : natural  := 124;
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

    -- Open-drain SCL input as observed at the pin.
    i2c_scl_i    : in  std_logic;
    -- Open-drain SDA input as observed at the pin.
    i2c_sda_i    : in  std_logic;
    -- SCL output-enable. A value of 0 drives SCL low; a value of 1 releases SCL.
    i2c_scl_oen  : out std_logic;
    -- SDA output-enable. A value of 0 drives SDA low; a value of 1 releases SDA.
    i2c_sda_oen  : out std_logic
  );
end entity;

architecture rtl of radif_reg_to_i2c_master is
  constant C_REG_CONTROL    : natural := 16#00#;
  constant C_REG_STATUS     : natural := 16#04#;
  constant C_REG_CLK_DIV    : natural := 16#08#;
  constant C_REG_SLAVE_ADDR : natural := 16#0C#;
  constant C_REG_TX_DATA    : natural := 16#10#;
  constant C_REG_RX_DATA    : natural := 16#14#;

  type state_t is (
    IDLE,
    START_A,
    START_B,
    ADDR_LOW,
    ADDR_HIGH,
    ADDR_ACK_LOW,
    ADDR_ACK_HIGH,
    DATA_LOW,
    DATA_HIGH,
    DATA_ACK_LOW,
    DATA_ACK_HIGH,
    READ_LOW,
    READ_HIGH,
    MASTER_NACK_LOW,
    MASTER_NACK_HIGH,
    STOP_A,
    STOP_B
  );

  signal control_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal status_r     : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal clk_div_r    : unsigned(15 downto 0) := to_unsigned(DEFAULT_SCL_DIV, 16);
  signal slave_addr_r : std_logic_vector(6 downto 0) := (others => '0');
  signal tx_data_r    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_data_r    : std_logic_vector(7 downto 0) := (others => '0');
  signal shift_r      : std_logic_vector(7 downto 0) := (others => '0');
  signal state        : state_t := IDLE;
  signal div_count    : unsigned(15 downto 0) := (others => '0');
  signal bit_count    : natural range 0 to 8 := 0;
  signal read_mode_r  : std_logic := '0';
  signal scl_oen_r    : std_logic := '1';
  signal sda_oen_r    : std_logic := '1';
  signal wr_valid_r   : std_logic := '0';
  signal rd_valid_r   : std_logic := '0';
  signal error_r      : std_logic := '0';
  signal rd_data_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

begin
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;
  i2c_scl_oen <= scl_oen_r;
  i2c_sda_oen <= sda_oen_r;

  process(clk)
    variable idx : natural;
    variable do_step : boolean;
  begin
    if rising_edge(clk) then
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';
      do_step := false;

      if rstn = '0' then
        control_r <= (others => '0');
        status_r <= (others => '0');
        clk_div_r <= to_unsigned(DEFAULT_SCL_DIV, 16);
        slave_addr_r <= (others => '0');
        tx_data_r <= (others => '0');
        rx_data_r <= (others => '0');
        shift_r <= (others => '0');
        state <= IDLE;
        div_count <= (others => '0');
        bit_count <= 0;
        read_mode_r <= '0';
        scl_oen_r <= '1';
        sda_oen_r <= '1';
      else
        if div_count = 0 then
          div_count <= clk_div_r;
          do_step := true;
        else
          div_count <= div_count - 1;
        end if;

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
                read_mode_r <= reg_data_in(2);
                shift_r <= slave_addr_r & reg_data_in(2);
                bit_count <= 8;
                status_r(1) <= '0';
                status_r(2) <= '0';
                div_count <= clk_div_r;
                scl_oen_r <= '1';
                sda_oen_r <= '1';
                state <= START_A;
              elsif reg_data_in(0) = '1' and state /= IDLE then
                status_r(2) <= '1';
              end if;
            when C_REG_CLK_DIV =>
              clk_div_r <= unsigned(reg_data_in(15 downto 0));
            when C_REG_SLAVE_ADDR =>
              slave_addr_r <= reg_data_in(6 downto 0);
            when C_REG_TX_DATA =>
              tx_data_r <= reg_data_in(7 downto 0);
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
              if state /= IDLE then
                rd_data_r(0) <= '1';
              else
                rd_data_r(0) <= '0';
              end if;
            when C_REG_CLK_DIV =>
              rd_data_r <= (others => '0');
              rd_data_r(15 downto 0) <= std_logic_vector(clk_div_r);
            when C_REG_SLAVE_ADDR =>
              rd_data_r <= (others => '0');
              rd_data_r(6 downto 0) <= slave_addr_r;
            when C_REG_TX_DATA =>
              rd_data_r <= (others => '0');
              rd_data_r(7 downto 0) <= tx_data_r;
            when C_REG_RX_DATA =>
              rd_data_r <= (others => '0');
              rd_data_r(7 downto 0) <= rx_data_r;
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;

        if do_step then
          case state is
            when IDLE =>
              scl_oen_r <= '1';
              sda_oen_r <= '1';
              status_r(0) <= '0';

            when START_A =>
              scl_oen_r <= '1';
              sda_oen_r <= '0';
              status_r(0) <= '1';
              state <= START_B;

            when START_B =>
              scl_oen_r <= '0';
              state <= ADDR_LOW;

            when ADDR_LOW =>
              scl_oen_r <= '0';
              sda_oen_r <= not shift_r(7);
              state <= ADDR_HIGH;

            when ADDR_HIGH =>
              scl_oen_r <= '1';
              if i2c_scl_i = '1' then
                shift_r <= shift_r(6 downto 0) & '0';
                if bit_count <= 1 then
                  bit_count <= 0;
                  state <= ADDR_ACK_LOW;
                else
                  bit_count <= bit_count - 1;
                  state <= ADDR_LOW;
                end if;
              end if;

            when ADDR_ACK_LOW =>
              scl_oen_r <= '0';
              sda_oen_r <= '1';
              state <= ADDR_ACK_HIGH;

            when ADDR_ACK_HIGH =>
              scl_oen_r <= '1';
              if i2c_scl_i = '1' then
                if i2c_sda_i = '1' then
                  status_r(2) <= '1';
                  state <= STOP_A;
                elsif read_mode_r = '1' then
                  shift_r <= (others => '0');
                  bit_count <= 8;
                  state <= READ_LOW;
                else
                  shift_r <= tx_data_r;
                  bit_count <= 8;
                  state <= DATA_LOW;
                end if;
              end if;

            when DATA_LOW =>
              scl_oen_r <= '0';
              sda_oen_r <= not shift_r(7);
              state <= DATA_HIGH;

            when DATA_HIGH =>
              scl_oen_r <= '1';
              if i2c_scl_i = '1' then
                shift_r <= shift_r(6 downto 0) & '0';
                if bit_count <= 1 then
                  bit_count <= 0;
                  state <= DATA_ACK_LOW;
                else
                  bit_count <= bit_count - 1;
                  state <= DATA_LOW;
                end if;
              end if;

            when DATA_ACK_LOW =>
              scl_oen_r <= '0';
              sda_oen_r <= '1';
              state <= DATA_ACK_HIGH;

            when DATA_ACK_HIGH =>
              scl_oen_r <= '1';
              if i2c_scl_i = '1' then
                if i2c_sda_i = '1' then
                  status_r(2) <= '1';
                end if;
                state <= STOP_A;
              end if;

            when READ_LOW =>
              scl_oen_r <= '0';
              sda_oen_r <= '1';
              state <= READ_HIGH;

            when READ_HIGH =>
              scl_oen_r <= '1';
              if i2c_scl_i = '1' then
                shift_r <= shift_r(6 downto 0) & i2c_sda_i;
                if bit_count <= 1 then
                  rx_data_r <= shift_r(6 downto 0) & i2c_sda_i;
                  bit_count <= 0;
                  state <= MASTER_NACK_LOW;
                else
                  bit_count <= bit_count - 1;
                  state <= READ_LOW;
                end if;
              end if;

            when MASTER_NACK_LOW =>
              scl_oen_r <= '0';
              sda_oen_r <= '1';
              state <= MASTER_NACK_HIGH;

            when MASTER_NACK_HIGH =>
              scl_oen_r <= '1';
              state <= STOP_A;

            when STOP_A =>
              scl_oen_r <= '0';
              sda_oen_r <= '0';
              state <= STOP_B;

            when STOP_B =>
              scl_oen_r <= '1';
              sda_oen_r <= '1';
              status_r(1) <= '1';
              status_r(0) <= '0';
              state <= IDLE;
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
