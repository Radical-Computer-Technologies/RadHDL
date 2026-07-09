library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- RADIF-controlled interrupt aggregator.
-- Latches interrupt sources into a pending register, applies a programmable
-- mask, supports software force/clear bits, and emits one shared IRQ output.
entity radif_irq_controller is
  generic (
    -- Width of the RADIF register data path.
    DATA_WIDTH         : integer := 32;
    -- Width of the RADIF byte address path.
    REG_ADDR_WIDTH     : integer := 16;
    -- Number of interrupt source inputs.
    IRQ_COUNT          : positive := 8;
    -- Vendor selector retained for generated package consistency.
    VENDOR_TAG         : string := "GENERIC";
    -- Device-family selector retained for generated package consistency.
    PRODUCT_SERIES_TAG : string := "GENERIC"
  );
  port (
    -- Register clock.
    clk           : in  std_logic;
    -- Active-low register reset.
    rstn          : in  std_logic;
    -- Raw interrupt source inputs.
    irq_i         : in  std_logic_vector(IRQ_COUNT - 1 downto 0);
    -- Shared masked interrupt output.
    irq_o         : out std_logic;
    -- Masked pending interrupt bits.
    irq_pending_o : out std_logic_vector(IRQ_COUNT - 1 downto 0);
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

architecture rtl of radif_irq_controller is
  constant C_REG_CONTROL : natural := 16#00#;
  constant C_REG_STATUS  : natural := 16#04#;
  constant C_REG_MASK    : natural := 16#08#;
  constant C_REG_PENDING : natural := 16#0C#;
  constant C_REG_CLEAR   : natural := 16#10#;
  constant C_REG_FORCE   : natural := 16#14#;

  signal control_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal mask_r      : std_logic_vector(IRQ_COUNT - 1 downto 0) := (others => '0');
  signal pending_r   : std_logic_vector(IRQ_COUNT - 1 downto 0) := (others => '0');
  signal irq_meta_r  : std_logic_vector(IRQ_COUNT - 1 downto 0) := (others => '0');
  signal irq_sync_r  : std_logic_vector(IRQ_COUNT - 1 downto 0) := (others => '0');
  signal rd_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_valid_r  : std_logic := '0';
  signal rd_valid_r  : std_logic := '0';
  signal error_r     : std_logic := '0';

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

  function pad_irq(value : std_logic_vector(IRQ_COUNT - 1 downto 0)) return std_logic_vector is
    variable outv : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  begin
    outv(IRQ_COUNT - 1 downto 0) := value;
    return outv;
  end function;

  function data_to_irq(value : std_logic_vector) return std_logic_vector is
    variable outv : std_logic_vector(IRQ_COUNT - 1 downto 0) := (others => '0');
  begin
    outv := value(IRQ_COUNT - 1 downto 0);
    return outv;
  end function;
begin
  assert DATA_WIDTH >= IRQ_COUNT
    report "radif_irq_controller DATA_WIDTH must be >= IRQ_COUNT"
    severity failure;

  irq_o <= '1' when control_r(0) = '1' and (pending_r and mask_r) /= (pending_r'range => '0') else '0';
  irq_pending_o <= pending_r and mask_r;
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;

  process(clk)
    variable idx : natural;
    variable next_pending : std_logic_vector(IRQ_COUNT - 1 downto 0);
  begin
    if rising_edge(clk) then
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';
      irq_meta_r <= irq_i;
      irq_sync_r <= irq_meta_r;

      if rstn = '0' then
        control_r <= (others => '0');
        mask_r <= (others => '0');
        pending_r <= (others => '0');
        irq_meta_r <= (others => '0');
        irq_sync_r <= (others => '0');
        rd_data_r <= (others => '0');
      else
        next_pending := pending_r or irq_sync_r;

        if reg_wr_en = '1' then
          wr_valid_r <= '1';
          idx := reg_index(reg_wr_addr);
          case idx is
            when C_REG_CONTROL => control_r <= reg_data_in;
            when C_REG_MASK => mask_r <= data_to_irq(reg_data_in);
            when C_REG_PENDING => next_pending := data_to_irq(reg_data_in);
            when C_REG_CLEAR => next_pending := next_pending and not data_to_irq(reg_data_in);
            when C_REG_FORCE => next_pending := next_pending or data_to_irq(reg_data_in);
            when others => error_r <= '1';
          end case;
        end if;

        pending_r <= next_pending;

        if reg_rd_en = '1' then
          rd_valid_r <= '1';
          idx := reg_index(reg_rd_addr);
          case idx is
            when C_REG_CONTROL => rd_data_r <= control_r;
            when C_REG_STATUS =>
              rd_data_r <= (others => '0');
              rd_data_r(0) <= control_r(0);
              if (pending_r and mask_r) /= (pending_r'range => '0') then
                rd_data_r(1) <= '1';
              end if;
            when C_REG_MASK => rd_data_r <= pad_irq(mask_r);
            when C_REG_PENDING => rd_data_r <= pad_irq(pending_r);
            when C_REG_CLEAR => rd_data_r <= (others => '0');
            when C_REG_FORCE => rd_data_r <= (others => '0');
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
