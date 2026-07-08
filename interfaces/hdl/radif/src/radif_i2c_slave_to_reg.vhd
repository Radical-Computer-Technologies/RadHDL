library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.radif_pkg.all;

-- I2C slave bridge to the RadIF register transaction interface.
-- Decodes host I2C register accesses and presents them as synchronous register read/write requests.
entity radif_i2c_slave_to_reg is
  generic (
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH         : integer := 32;
    -- Sets the bit width for ADDR WIDTH values carried by this module.
    ADDR_WIDTH         : integer := 16;
    -- Configures I2C ADDR for this instance.
    I2C_ADDR           : std_logic_vector(6 downto 0) := "0101010";
    -- Configures ENABLE CRC16 for this instance.
    ENABLE_CRC16       : boolean := false;
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR_TAG         : string  := "XILINX";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    PRODUCT_SERIES_TAG : string  := "GENERIC"
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-low reset for this clock domain.
    rstn          : in  std_logic;
    -- Input i2c scl i signal for this module.
    i2c_scl_i     : in  std_logic;
    -- Input i2c sda i signal for this module.
    i2c_sda_i     : in  std_logic;
    -- I2c sda oen interface signal.
    i2c_sda_oen   : out std_logic;
    -- Register write address issued to the internal RadIF register target.
    reg_wr_addr   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- Register read address issued to the internal RadIF register target.
    reg_rd_addr   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- One-cycle write request pulse for the internal register target.
    reg_wr_en     : out std_logic;
    -- One-cycle read request pulse for the internal register target.
    reg_rd_en     : out std_logic;
    -- Write data presented to the internal register target.
    reg_data_in   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Read data returned by the internal register target.
    reg_data_out  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Write-side ready indication from the internal register target.
    reg_wr_rdy    : in  std_logic;
    -- Read-side ready indication from the internal register target.
    reg_rd_rdy    : in  std_logic;
    -- Write response valid indication from the internal register target.
    reg_wr_valid  : in  std_logic;
    -- Read response valid indication from the internal register target.
    reg_rd_valid  : in  std_logic;
    -- Register target error flag converted into the external bus error response.
    reg_error     : in  std_logic
  );
end entity;

architecture rtl of radif_i2c_slave_to_reg is
  type state_t is (IDLE, ADDR_BYTE, RX_OP, RX_ADDR_H, RX_ADDR_L, RX_DATA, WAIT_WRITE, WAIT_READ, TX_DATA);
  constant WORD_BYTES : natural := (DATA_WIDTH + 7) / 8;

  signal scl_meta  : std_logic := '1';
  signal scl_sync  : std_logic := '1';
  signal scl_prev  : std_logic := '1';
  signal sda_meta  : std_logic := '1';
  signal sda_sync  : std_logic := '1';
  signal sda_prev  : std_logic := '1';
  signal sda_oen_r : std_logic := '1';
  signal bit_count : unsigned(2 downto 0) := (others => '0');
  signal rx_shift  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_shift  : std_logic_vector(7 downto 0) := (others => '1');
  signal state     : state_t := IDLE;
  signal op_r      : std_logic_vector(7 downto 0) := (others => '0');
  signal addr_r    : std_logic_vector(15 downto 0) := (others => '0');
  signal wr_data_r : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_addr_r : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_addr_r : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal wr_en_r   : std_logic := '0';
  signal rd_en_r   : std_logic := '0';
  signal byte_index: natural range 0 to WORD_BYTES := 0;
  signal tx_index  : natural range 0 to WORD_BYTES := 0;
  signal tx_word   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal selected  : std_logic := '0';

  function resize_addr(a : std_logic_vector(15 downto 0)) return std_logic_vector is
    variable outv : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  begin
    if ADDR_WIDTH <= 16 then
      outv := a(ADDR_WIDTH - 1 downto 0);
    else
      outv(15 downto 0) := a;
    end if;
    return outv;
  end function;

  function byte_from_word(w : std_logic_vector; idx : natural) return std_logic_vector is
    variable b : std_logic_vector(7 downto 0) := (others => '0');
    variable hi : integer;
  begin
    hi := w'length - 1 - integer(idx * 8);
    if hi >= 7 then
      b := w(hi downto hi - 7);
    end if;
    return b;
  end function;
begin
  i2c_sda_oen <= sda_oen_r;
  reg_wr_addr <= wr_addr_r;
  reg_rd_addr <= rd_addr_r;
  reg_data_in <= wr_data_r;
  reg_wr_en <= wr_en_r;
  reg_rd_en <= rd_en_r;

  gen_xilinx_vendor : if VENDOR_TAG = "XILINX" generate
  begin
  end generate;

  gen_generic_vendor : if VENDOR_TAG /= "XILINX" generate
  begin
  end generate;

  process(clk)
    variable rx_byte : std_logic_vector(7 downto 0);
    variable byte_valid : boolean;
    variable start_seen : boolean;
    variable stop_seen : boolean;
    variable next_addr : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      scl_meta <= i2c_scl_i;
      scl_sync <= scl_meta;
      scl_prev <= scl_sync;
      sda_meta <= i2c_sda_i;
      sda_sync <= sda_meta;
      sda_prev <= sda_sync;

      wr_en_r <= '0';
      rd_en_r <= '0';
      sda_oen_r <= '1';
      byte_valid := false;
      start_seen := sda_prev = '1' and sda_sync = '0' and scl_sync = '1';
      stop_seen := sda_prev = '0' and sda_sync = '1' and scl_sync = '1';
      rx_byte := rx_shift(6 downto 0) & sda_sync;

      if rstn = '0' then
        state <= IDLE;
        selected <= '0';
        bit_count <= (others => '0');
        wr_data_r <= (others => '0');
      elsif start_seen then
        state <= ADDR_BYTE;
        selected <= '0';
        bit_count <= (others => '0');
      elsif stop_seen then
        state <= IDLE;
        selected <= '0';
        bit_count <= (others => '0');
      else
        if scl_sync = '1' and scl_prev = '0' then
          rx_shift <= rx_shift(6 downto 0) & sda_sync;
          if bit_count = "111" then
            bit_count <= (others => '0');
            byte_valid := true;
          else
            bit_count <= bit_count + 1;
          end if;
        end if;

        if scl_sync = '0' and scl_prev = '1' and state = TX_DATA then
          sda_oen_r <= tx_shift(7);
          tx_shift <= tx_shift(6 downto 0) & '1';
        end if;

        if byte_valid then
          case state is
            when IDLE =>
              null;

            when ADDR_BYTE =>
              if rx_byte(7 downto 1) = I2C_ADDR then
                selected <= '1';
                sda_oen_r <= '0';
                if rx_byte(0) = '1' then
                  tx_shift <= byte_from_word(tx_word, 0);
                  tx_index <= 1;
                  state <= TX_DATA;
                else
                  state <= RX_OP;
                end if;
              else
                selected <= '0';
                state <= IDLE;
              end if;

            when RX_OP =>
              if selected = '1' then
                op_r <= rx_byte;
                sda_oen_r <= '0';
                state <= RX_ADDR_H;
              end if;

            when RX_ADDR_H =>
              addr_r(15 downto 8) <= rx_byte;
              sda_oen_r <= '0';
              state <= RX_ADDR_L;

            when RX_ADDR_L =>
              next_addr := addr_r(15 downto 8) & rx_byte;
              addr_r(7 downto 0) <= rx_byte;
              sda_oen_r <= '0';
              if op_r = RADIF_OP_REG_WRITE then
                wr_data_r <= (others => '0');
                byte_index <= 0;
                state <= RX_DATA;
              elsif op_r = RADIF_OP_REG_READ and reg_rd_rdy = '1' then
                rd_addr_r <= resize_addr(next_addr);
                rd_en_r <= '1';
                state <= WAIT_READ;
              else
                state <= IDLE;
              end if;

            when RX_DATA =>
              wr_data_r(DATA_WIDTH - 1 - (byte_index * 8) downto DATA_WIDTH - 8 - (byte_index * 8)) <= rx_byte;
              sda_oen_r <= '0';
              if byte_index = WORD_BYTES - 1 then
                if reg_wr_rdy = '1' then
                  wr_addr_r <= resize_addr(addr_r);
                  wr_en_r <= '1';
                  state <= WAIT_WRITE;
                end if;
              else
                byte_index <= byte_index + 1;
              end if;

            when WAIT_WRITE =>
              if reg_wr_valid = '1' then
                state <= IDLE;
              end if;

            when WAIT_READ =>
              if reg_rd_valid = '1' then
                if reg_error = '1' then
                  tx_word <= (others => '0');
                else
                  tx_word <= reg_data_out;
                end if;
                state <= IDLE;
              end if;

            when TX_DATA =>
              if tx_index < WORD_BYTES then
                tx_shift <= byte_from_word(tx_word, tx_index);
                tx_index <= tx_index + 1;
              else
                tx_shift <= x"00";
              end if;
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
