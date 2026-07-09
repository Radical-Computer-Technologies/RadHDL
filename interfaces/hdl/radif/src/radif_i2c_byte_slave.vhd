library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- I2C byte-register slave for simple board-control buses.
-- Implements the common Linux SMBus-style transaction used by the FPiGA
-- userspace library: one address byte selects an 8-bit register, writes append
-- byte data with auto-increment, and reads return bytes with auto-increment.
entity radif_i2c_byte_slave is
  generic (
    I2C_ADDR : std_logic_vector(6 downto 0) := "0010010"
  );
  port (
    clk        : in  std_logic;
    rstn       : in  std_logic;
    scl_i      : in  std_logic;
    sda_i      : in  std_logic;
    sda_oen    : out std_logic;
    wr_addr    : out std_logic_vector(7 downto 0);
    wr_data    : out std_logic_vector(7 downto 0);
    wr_en      : out std_logic;
    rd_addr    : out std_logic_vector(7 downto 0);
    rd_data    : in  std_logic_vector(7 downto 0);
    rd_en      : out std_logic;
    read_done  : out std_logic
  );
end entity;

architecture rtl of radif_i2c_byte_slave is
  type state_t is (
    IDLE,
    ADDR,
    ACK_ADDR,
    REG_ADDR,
    ACK_REG,
    WRITE_DATA,
    ACK_WRITE,
    READ_DATA,
    READ_ACK,
    READ_LOAD
  );

  signal state       : state_t := IDLE;
  signal scl_meta    : std_logic := '1';
  signal scl_sync    : std_logic := '1';
  signal scl_prev    : std_logic := '1';
  signal sda_meta    : std_logic := '1';
  signal sda_sync    : std_logic := '1';
  signal sda_prev    : std_logic := '1';
  signal bit_count   : unsigned(2 downto 0) := (others => '0');
  signal shift_in    : std_logic_vector(7 downto 0) := (others => '0');
  signal shift_out   : std_logic_vector(7 downto 0) := (others => '1');
  signal reg_addr_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal sda_oen_r   : std_logic := '1';
  signal selected_r  : std_logic := '0';
  signal rw_r        : std_logic := '0';
  signal wr_en_r     : std_logic := '0';
  signal rd_en_r     : std_logic := '0';
  signal read_done_r : std_logic := '0';

  function inc8(value : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    return std_logic_vector(unsigned(value) + 1);
  end function;
begin
  sda_oen <= sda_oen_r;
  wr_addr <= reg_addr_r;
  wr_en <= wr_en_r;
  rd_addr <= reg_addr_r;
  rd_en <= rd_en_r;
  read_done <= read_done_r;

  process(clk)
    variable rx_byte    : std_logic_vector(7 downto 0);
    variable start_seen : boolean;
    variable stop_seen  : boolean;
    variable scl_rise   : boolean;
    variable scl_fall   : boolean;
  begin
    if rising_edge(clk) then
      scl_meta <= scl_i;
      scl_sync <= scl_meta;
      scl_prev <= scl_sync;
      sda_meta <= sda_i;
      sda_sync <= sda_meta;
      sda_prev <= sda_sync;

      wr_en_r <= '0';
      rd_en_r <= '0';
      read_done_r <= '0';

      start_seen := sda_prev = '1' and sda_sync = '0' and scl_sync = '1';
      stop_seen := sda_prev = '0' and sda_sync = '1' and scl_sync = '1';
      scl_rise := scl_prev = '0' and scl_sync = '1';
      scl_fall := scl_prev = '1' and scl_sync = '0';
      rx_byte := shift_in(6 downto 0) & sda_sync;

      if rstn = '0' then
        state <= IDLE;
        sda_oen_r <= '1';
        selected_r <= '0';
        bit_count <= (others => '0');
        reg_addr_r <= (others => '0');
        shift_in <= (others => '0');
        shift_out <= (others => '1');
      elsif start_seen then
        state <= ADDR;
        sda_oen_r <= '1';
        selected_r <= '0';
        bit_count <= to_unsigned(7, bit_count'length);
        shift_in <= (others => '0');
      elsif stop_seen then
        state <= IDLE;
        sda_oen_r <= '1';
        selected_r <= '0';
        bit_count <= (others => '0');
      else
        case state is
          when IDLE =>
            sda_oen_r <= '1';

          when ADDR =>
            if scl_rise then
              shift_in <= shift_in(6 downto 0) & sda_sync;
              if bit_count = to_unsigned(0, bit_count'length) then
                if rx_byte(7 downto 1) = I2C_ADDR then
                  selected_r <= '1';
                  rw_r <= rx_byte(0);
                  state <= ACK_ADDR;
                else
                  selected_r <= '0';
                  state <= IDLE;
                end if;
              else
                bit_count <= bit_count - 1;
              end if;
            end if;

          when ACK_ADDR =>
            if scl_fall then
              sda_oen_r <= '0';
            elsif scl_rise then
              sda_oen_r <= '1';
              if selected_r = '1' and rw_r = '1' then
                shift_out <= rd_data;
                rd_en_r <= '1';
                read_done_r <= '1';
                bit_count <= to_unsigned(7, bit_count'length);
                state <= READ_DATA;
              else
                bit_count <= to_unsigned(7, bit_count'length);
                state <= REG_ADDR;
              end if;
            end if;

          when REG_ADDR =>
            if scl_rise then
              shift_in <= shift_in(6 downto 0) & sda_sync;
              if bit_count = to_unsigned(0, bit_count'length) then
                reg_addr_r <= rx_byte;
                state <= ACK_REG;
              else
                bit_count <= bit_count - 1;
              end if;
            end if;

          when ACK_REG =>
            if scl_fall then
              sda_oen_r <= '0';
            elsif scl_rise then
              sda_oen_r <= '1';
              bit_count <= to_unsigned(7, bit_count'length);
              state <= WRITE_DATA;
            end if;

          when WRITE_DATA =>
            if scl_rise then
              shift_in <= shift_in(6 downto 0) & sda_sync;
              if bit_count = to_unsigned(0, bit_count'length) then
                wr_data <= rx_byte;
                wr_en_r <= '1';
                state <= ACK_WRITE;
              else
                bit_count <= bit_count - 1;
              end if;
            end if;

          when ACK_WRITE =>
            if scl_fall then
              sda_oen_r <= '0';
            elsif scl_rise then
              sda_oen_r <= '1';
              reg_addr_r <= inc8(reg_addr_r);
              bit_count <= to_unsigned(7, bit_count'length);
              state <= WRITE_DATA;
            end if;

          when READ_DATA =>
            if scl_fall then
              sda_oen_r <= shift_out(7);
              shift_out <= shift_out(6 downto 0) & '1';
              if bit_count = to_unsigned(0, bit_count'length) then
                state <= READ_ACK;
              else
                bit_count <= bit_count - 1;
              end if;
            end if;

          when READ_ACK =>
            if scl_fall then
              sda_oen_r <= '1';
            elsif scl_rise then
              if sda_sync = '0' then
                reg_addr_r <= inc8(reg_addr_r);
                rd_en_r <= '1';
                read_done_r <= '1';
                bit_count <= to_unsigned(7, bit_count'length);
                state <= READ_LOAD;
              else
                state <= IDLE;
              end if;
            end if;

          when READ_LOAD =>
            shift_out <= rd_data;
            state <= READ_DATA;
        end case;
      end if;
    end if;
  end process;
end architecture;
