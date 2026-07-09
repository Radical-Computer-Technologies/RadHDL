library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- RADIF-controlled GPIO register block for simple board control and status.
-- Exposes output value, output enable, input value, edge-detect pending bits,
-- interrupt masks, and edge polarity selection through the shared RADIF bus.
entity radif_gpio_reg_block is
  generic (
    -- Width of the RADIF register data path.
    DATA_WIDTH         : integer := 32;
    -- Width of the RADIF byte address path.
    REG_ADDR_WIDTH     : integer := 16;
    -- Number of GPIO pins controlled or observed by this block.
    GPIO_WIDTH         : positive := 8;
    -- Reset value for GPIO outputs.
    RESET_OUT_VALUE    : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
    -- Reset value for GPIO output enables.
    RESET_OUT_ENABLE   : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
    -- Vendor selector retained for generated package consistency.
    VENDOR_TAG         : string  := "GENERIC";
    -- Device-family selector retained for generated package consistency.
    PRODUCT_SERIES_TAG : string  := "GENERIC"
  );
  port (
    -- Register clock.
    clk           : in  std_logic;
    -- Active-low register reset.
    rstn          : in  std_logic;
    -- External GPIO input pins synchronized into clk.
    gpio_i        : in  std_logic_vector(GPIO_WIDTH - 1 downto 0);
    -- GPIO output drive values.
    gpio_o        : out std_logic_vector(GPIO_WIDTH - 1 downto 0);
    -- GPIO output enable bits.
    gpio_oe_o     : out std_logic_vector(GPIO_WIDTH - 1 downto 0);
    -- Interrupt asserted when an enabled edge-detect pending bit is set.
    irq_o         : out std_logic;
    -- Register write address.
    reg_wr_addr   : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- Register read address.
    reg_rd_addr   : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- One-cycle register write request.
    reg_wr_en     : in  std_logic;
    -- One-cycle register read request.
    reg_rd_en     : in  std_logic;
    -- Register write data.
    reg_data_in   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register read data.
    reg_data_out  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register write ready.
    reg_wr_rdy    : out std_logic;
    -- Register read ready.
    reg_rd_rdy    : out std_logic;
    -- Register write response valid.
    reg_wr_valid  : out std_logic;
    -- Register read response valid.
    reg_rd_valid  : out std_logic;
    -- Register transaction error.
    reg_error     : out std_logic
  );
end entity;

architecture rtl of radif_gpio_reg_block is
  constant C_REG_OUT_VALUE : natural := 16#00#;
  constant C_REG_OUT_EN    : natural := 16#04#;
  constant C_REG_IN_VALUE  : natural := 16#08#;
  constant C_REG_IRQ_STAT  : natural := 16#0C#;
  constant C_REG_IRQ_MASK  : natural := 16#10#;
  constant C_REG_RISE_EN   : natural := 16#14#;
  constant C_REG_FALL_EN   : natural := 16#18#;

  signal out_value_r : std_logic_vector(GPIO_WIDTH - 1 downto 0) := RESET_OUT_VALUE;
  signal out_en_r    : std_logic_vector(GPIO_WIDTH - 1 downto 0) := RESET_OUT_ENABLE;
  signal irq_stat_r  : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal irq_mask_r  : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal rise_en_r   : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal fall_en_r   : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_meta_r : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_sync_r : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal gpio_prev_r : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  signal rd_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_valid_r  : std_logic := '0';
  signal rd_valid_r  : std_logic := '0';
  signal error_r     : std_logic := '0';

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

  function pad_gpio(value : std_logic_vector(GPIO_WIDTH - 1 downto 0)) return std_logic_vector is
    variable outv : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  begin
    outv(GPIO_WIDTH - 1 downto 0) := value;
    return outv;
  end function;

  function data_to_gpio(value : std_logic_vector) return std_logic_vector is
    variable outv : std_logic_vector(GPIO_WIDTH - 1 downto 0) := (others => '0');
  begin
    outv := value(GPIO_WIDTH - 1 downto 0);
    return outv;
  end function;
begin
  assert DATA_WIDTH >= GPIO_WIDTH
    report "radif_gpio_reg_block DATA_WIDTH must be >= GPIO_WIDTH"
    severity failure;

  gpio_o <= out_value_r;
  gpio_oe_o <= out_en_r;
  irq_o <= '1' when (irq_stat_r and irq_mask_r) /= (irq_stat_r'range => '0') else '0';
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;

  process(clk)
    variable idx : natural;
    variable rise_hits : std_logic_vector(GPIO_WIDTH - 1 downto 0);
    variable fall_hits : std_logic_vector(GPIO_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';
      gpio_meta_r <= gpio_i;
      gpio_sync_r <= gpio_meta_r;
      gpio_prev_r <= gpio_sync_r;
      rise_hits := (gpio_sync_r and not gpio_prev_r) and rise_en_r;
      fall_hits := ((not gpio_sync_r) and gpio_prev_r) and fall_en_r;

      if rstn = '0' then
        out_value_r <= RESET_OUT_VALUE;
        out_en_r <= RESET_OUT_ENABLE;
        irq_stat_r <= (others => '0');
        irq_mask_r <= (others => '0');
        rise_en_r <= (others => '0');
        fall_en_r <= (others => '0');
        gpio_meta_r <= (others => '0');
        gpio_sync_r <= (others => '0');
        gpio_prev_r <= (others => '0');
        rd_data_r <= (others => '0');
      else
        irq_stat_r <= irq_stat_r or rise_hits or fall_hits;

        if reg_wr_en = '1' then
          wr_valid_r <= '1';
          idx := reg_index(reg_wr_addr);
          case idx is
            when C_REG_OUT_VALUE => out_value_r <= data_to_gpio(reg_data_in);
            when C_REG_OUT_EN => out_en_r <= data_to_gpio(reg_data_in);
            when C_REG_IRQ_STAT => irq_stat_r <= irq_stat_r and not data_to_gpio(reg_data_in);
            when C_REG_IRQ_MASK => irq_mask_r <= data_to_gpio(reg_data_in);
            when C_REG_RISE_EN => rise_en_r <= data_to_gpio(reg_data_in);
            when C_REG_FALL_EN => fall_en_r <= data_to_gpio(reg_data_in);
            when others => error_r <= '1';
          end case;
        end if;

        if reg_rd_en = '1' then
          rd_valid_r <= '1';
          idx := reg_index(reg_rd_addr);
          case idx is
            when C_REG_OUT_VALUE => rd_data_r <= pad_gpio(out_value_r);
            when C_REG_OUT_EN => rd_data_r <= pad_gpio(out_en_r);
            when C_REG_IN_VALUE => rd_data_r <= pad_gpio(gpio_sync_r);
            when C_REG_IRQ_STAT => rd_data_r <= pad_gpio(irq_stat_r);
            when C_REG_IRQ_MASK => rd_data_r <= pad_gpio(irq_mask_r);
            when C_REG_RISE_EN => rd_data_r <= pad_gpio(rise_en_r);
            when C_REG_FALL_EN => rd_data_r <= pad_gpio(fall_en_r);
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
