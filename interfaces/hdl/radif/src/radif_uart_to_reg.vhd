library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- UART bridge to the RADIF register interface for low-cost board bring-up.
-- Protocol bytes are binary and intentionally small:
--   Write request: 0x57 addr_hi addr_lo data[31:24] data[23:16] data[15:8] data[7:0]
--   Write response: 0x77 status
--   Read request:  0x52 addr_hi addr_lo
--   Read response: 0x72 status data[31:24] data[23:16] data[15:8] data[7:0]
-- Status is 0 for OK and 1 for register target error.
entity radif_uart_to_reg is
  generic (
    -- Width of the RADIF register data path. This bridge currently transports 32-bit words.
    DATA_WIDTH         : integer := 32;
    -- Width of the RADIF byte address path.
    ADDR_WIDTH         : integer := 16;
    -- Number of clk cycles per UART bit.
    BAUD_DIVISOR       : positive := 868;
    -- Vendor selector retained for generated package consistency.
    VENDOR_TAG         : string := "GENERIC";
    -- Device-family selector retained for generated package consistency.
    PRODUCT_SERIES_TAG : string := "GENERIC"
  );
  port (
    -- Register/UART clock.
    clk          : in  std_logic;
    -- Active-low reset.
    rstn         : in  std_logic;
    -- UART receive pin.
    uart_rx_i    : in  std_logic;
    -- UART transmit pin.
    uart_tx_o    : out std_logic;
    -- Register write address.
    reg_wr_addr  : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- Register read address.
    reg_rd_addr  : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- One-cycle register write request.
    reg_wr_en    : out std_logic;
    -- One-cycle register read request.
    reg_rd_en    : out std_logic;
    -- Register write data.
    reg_data_in  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register read data.
    reg_data_out : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register target write ready.
    reg_wr_rdy   : in  std_logic;
    -- Register target read ready.
    reg_rd_rdy   : in  std_logic;
    -- Register target write response valid.
    reg_wr_valid : in  std_logic;
    -- Register target read response valid.
    reg_rd_valid : in  std_logic;
    -- Register target error for current response.
    reg_error    : in  std_logic
  );
end entity;

architecture rtl of radif_uart_to_reg is
  constant C_CMD_WRITE : std_logic_vector(7 downto 0) := x"57";
  constant C_CMD_READ  : std_logic_vector(7 downto 0) := x"52";
  constant C_RSP_WRITE : std_logic_vector(7 downto 0) := x"77";
  constant C_RSP_READ  : std_logic_vector(7 downto 0) := x"72";

  type rx_state_t is (RX_IDLE, RX_START, RX_BITS, RX_STOP);
  type tx_state_t is (TX_IDLE, TX_START, TX_BITS, TX_STOP);
  type cmd_state_t is (
    CMD_WAIT, CMD_ADDR_HI, CMD_ADDR_LO,
    CMD_WD3, CMD_WD2, CMD_WD1, CMD_WD0,
    CMD_ISSUE_WR, CMD_WAIT_WR, CMD_ISSUE_RD, CMD_WAIT_RD,
    CMD_SEND_W_ACK, CMD_SEND_R_HDR, CMD_SEND_R_STAT, CMD_SEND_R_D3, CMD_SEND_R_D2, CMD_SEND_R_D1, CMD_SEND_R_D0
  );

  signal rx_meta_r  : std_logic := '1';
  signal rx_sync_r  : std_logic := '1';
  signal rx_state   : rx_state_t := RX_IDLE;
  signal rx_div     : natural range 0 to BAUD_DIVISOR - 1 := 0;
  signal rx_bit     : natural range 0 to 7 := 0;
  signal rx_shift   : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_data_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_valid_r : std_logic := '0';

  signal tx_state   : tx_state_t := TX_IDLE;
  signal tx_div     : natural range 0 to BAUD_DIVISOR - 1 := 0;
  signal tx_bit     : natural range 0 to 7 := 0;
  signal tx_shift   : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_line_r  : std_logic := '1';
  signal tx_start_r : std_logic := '0';
  signal tx_data_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_busy    : std_logic;

  signal cmd_state  : cmd_state_t := CMD_WAIT;
  signal command_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal addr_r     : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal wdata_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal rdata_r    : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal status_r   : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_en_r    : std_logic := '0';
  signal rd_en_r    : std_logic := '0';

  procedure start_tx(
    signal start_s : out std_logic;
    signal data_s  : out std_logic_vector(7 downto 0);
    constant value : in  std_logic_vector(7 downto 0)
  ) is
  begin
    data_s <= value;
    start_s <= '1';
  end procedure;
begin
  assert DATA_WIDTH = 32
    report "radif_uart_to_reg currently transports DATA_WIDTH=32 words"
    severity failure;
  assert ADDR_WIDTH >= 16
    report "radif_uart_to_reg requires ADDR_WIDTH >= 16"
    severity failure;

  uart_tx_o <= tx_line_r;
  tx_busy <= '1' when tx_state /= TX_IDLE else '0';
  reg_wr_addr <= addr_r;
  reg_rd_addr <= addr_r;
  reg_data_in <= wdata_r;
  reg_wr_en <= wr_en_r;
  reg_rd_en <= rd_en_r;

  process(clk)
  begin
    if rising_edge(clk) then
      rx_valid_r <= '0';
      rx_meta_r <= uart_rx_i;
      rx_sync_r <= rx_meta_r;

      if rstn = '0' then
        rx_state <= RX_IDLE;
        rx_div <= 0;
        rx_bit <= 0;
        rx_shift <= (others => '0');
        rx_data_r <= (others => '0');
      else
        case rx_state is
          when RX_IDLE =>
            if rx_sync_r = '0' then
              rx_div <= BAUD_DIVISOR / 2;
              rx_state <= RX_START;
            end if;

          when RX_START =>
            if rx_div = 0 then
              if rx_sync_r = '0' then
                rx_div <= BAUD_DIVISOR - 1;
                rx_bit <= 0;
                rx_state <= RX_BITS;
              else
                rx_state <= RX_IDLE;
              end if;
            else
              rx_div <= rx_div - 1;
            end if;

          when RX_BITS =>
            if rx_div = 0 then
              rx_shift(rx_bit) <= rx_sync_r;
              rx_div <= BAUD_DIVISOR - 1;
              if rx_bit = 7 then
                rx_state <= RX_STOP;
              else
                rx_bit <= rx_bit + 1;
              end if;
            else
              rx_div <= rx_div - 1;
            end if;

          when RX_STOP =>
            if rx_div = 0 then
              if rx_sync_r = '1' then
                rx_data_r <= rx_shift;
                rx_valid_r <= '1';
              end if;
              rx_state <= RX_IDLE;
            else
              rx_div <= rx_div - 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rstn = '0' then
        tx_state <= TX_IDLE;
        tx_div <= 0;
        tx_bit <= 0;
        tx_shift <= (others => '0');
        tx_line_r <= '1';
      else
        case tx_state is
          when TX_IDLE =>
            tx_line_r <= '1';
            if tx_start_r = '1' then
              tx_shift <= tx_data_r;
              tx_line_r <= '0';
              tx_div <= BAUD_DIVISOR - 1;
              tx_bit <= 0;
              tx_state <= TX_START;
            end if;

          when TX_START =>
            if tx_div = 0 then
              tx_line_r <= tx_shift(0);
              tx_div <= BAUD_DIVISOR - 1;
              tx_state <= TX_BITS;
            else
              tx_div <= tx_div - 1;
            end if;

          when TX_BITS =>
            if tx_div = 0 then
              if tx_bit = 7 then
                tx_line_r <= '1';
                tx_div <= BAUD_DIVISOR - 1;
                tx_state <= TX_STOP;
              else
                tx_bit <= tx_bit + 1;
                tx_line_r <= tx_shift(tx_bit + 1);
                tx_div <= BAUD_DIVISOR - 1;
              end if;
            else
              tx_div <= tx_div - 1;
            end if;

          when TX_STOP =>
            if tx_div = 0 then
              tx_state <= TX_IDLE;
            else
              tx_div <= tx_div - 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      tx_start_r <= '0';
      wr_en_r <= '0';
      rd_en_r <= '0';

      if rstn = '0' then
        cmd_state <= CMD_WAIT;
        command_r <= (others => '0');
        addr_r <= (others => '0');
        wdata_r <= (others => '0');
        rdata_r <= (others => '0');
        status_r <= (others => '0');
      else
        case cmd_state is
          when CMD_WAIT =>
            if rx_valid_r = '1' then
              if rx_data_r = C_CMD_WRITE then
                command_r <= rx_data_r;
                cmd_state <= CMD_ADDR_HI;
              elsif rx_data_r = C_CMD_READ then
                command_r <= rx_data_r;
                cmd_state <= CMD_ADDR_HI;
              end if;
            end if;

          when CMD_ADDR_HI =>
            if rx_valid_r = '1' then
              addr_r(15 downto 8) <= rx_data_r;
              cmd_state <= CMD_ADDR_LO;
            end if;

          when CMD_ADDR_LO =>
            if rx_valid_r = '1' then
              addr_r(7 downto 0) <= rx_data_r;
              if command_r = C_CMD_WRITE then
                cmd_state <= CMD_WD3;
              else
                cmd_state <= CMD_ISSUE_RD;
              end if;
            end if;

          when CMD_WD3 =>
            if rx_valid_r = '1' then
              wdata_r(31 downto 24) <= rx_data_r;
              cmd_state <= CMD_WD2;
            end if;
          when CMD_WD2 =>
            if rx_valid_r = '1' then
              wdata_r(23 downto 16) <= rx_data_r;
              cmd_state <= CMD_WD1;
            end if;
          when CMD_WD1 =>
            if rx_valid_r = '1' then
              wdata_r(15 downto 8) <= rx_data_r;
              cmd_state <= CMD_WD0;
            end if;
          when CMD_WD0 =>
            if rx_valid_r = '1' then
              wdata_r(7 downto 0) <= rx_data_r;
              cmd_state <= CMD_ISSUE_WR;
            end if;

          when CMD_ISSUE_WR =>
            if reg_wr_rdy = '1' then
              wr_en_r <= '1';
              cmd_state <= CMD_WAIT_WR;
            end if;

          when CMD_WAIT_WR =>
            if reg_wr_valid = '1' then
              if reg_error = '1' then
                status_r <= x"01";
              else
                status_r <= x"00";
              end if;
              cmd_state <= CMD_SEND_W_ACK;
            end if;

          when CMD_ISSUE_RD =>
            if reg_rd_rdy = '1' then
              rd_en_r <= '1';
              cmd_state <= CMD_WAIT_RD;
            end if;

          when CMD_WAIT_RD =>
            if reg_rd_valid = '1' then
              rdata_r <= reg_data_out;
              if reg_error = '1' then
                status_r <= x"01";
              else
                status_r <= x"00";
              end if;
              cmd_state <= CMD_SEND_R_HDR;
            end if;

          when CMD_SEND_W_ACK =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, C_RSP_WRITE);
              cmd_state <= CMD_SEND_R_STAT;
            end if;

          when CMD_SEND_R_HDR =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, C_RSP_READ);
              cmd_state <= CMD_SEND_R_STAT;
            end if;

          when CMD_SEND_R_STAT =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, status_r);
              if command_r = C_CMD_WRITE then
                cmd_state <= CMD_WAIT;
              else
                cmd_state <= CMD_SEND_R_D3;
              end if;
            end if;

          when CMD_SEND_R_D3 =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, rdata_r(31 downto 24));
              cmd_state <= CMD_SEND_R_D2;
            end if;
          when CMD_SEND_R_D2 =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, rdata_r(23 downto 16));
              cmd_state <= CMD_SEND_R_D1;
            end if;
          when CMD_SEND_R_D1 =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, rdata_r(15 downto 8));
              cmd_state <= CMD_SEND_R_D0;
            end if;
          when CMD_SEND_R_D0 =>
            if tx_busy = '0' then
              start_tx(tx_start_r, tx_data_r, rdata_r(7 downto 0));
              cmd_state <= CMD_WAIT;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
