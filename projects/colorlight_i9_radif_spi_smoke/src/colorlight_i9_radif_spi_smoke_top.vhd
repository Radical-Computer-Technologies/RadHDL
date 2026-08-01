library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity colorlight_i9_radif_spi_smoke_top is
  port (
    clk_25m_i   : in  std_logic;
    spi_sclk_i  : in  std_logic;
    spi_cs_n_i  : in  std_logic;
    spi_mosi_i  : in  std_logic;
    spi_miso_o  : out std_logic;
    led_o       : out std_logic
  );
end entity;

architecture rtl of colorlight_i9_radif_spi_smoke_top is
  signal rst_shift    : std_logic_vector(7 downto 0) := (others => '0');
  signal rstn         : std_logic;
  signal reg_wr_addr  : std_logic_vector(15 downto 0);
  signal reg_rd_addr  : std_logic_vector(15 downto 0);
  signal reg_wr_en    : std_logic;
  signal reg_rd_en    : std_logic;
  signal reg_data_in  : std_logic_vector(31 downto 0);
  signal reg_data_out : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_wr_valid : std_logic := '0';
  signal reg_rd_valid : std_logic := '0';
  signal control_reg  : std_logic_vector(31 downto 0) := (others => '0');
  signal scratch_reg  : std_logic_vector(31 downto 0) := x"52414449";
  signal status_reg   : std_logic_vector(31 downto 0) := x"00000001";
  signal spi_miso_oe  : std_logic;
begin
  rstn <= rst_shift(rst_shift'high);
  led_o <= control_reg(0);

  process(clk_25m_i)
  begin
    if rising_edge(clk_25m_i) then
      rst_shift <= rst_shift(rst_shift'high - 1 downto 0) & '1';
    end if;
  end process;

  u_spi : entity work.radif_spi_slave_to_reg
    generic map (
      DATA_WIDTH => 32,
      ADDR_WIDTH => 16,
      SPI_MODE => 0,
      ENABLE_CRC16 => false,
      VENDOR_TAG => "GENERIC",
      PRODUCT_SERIES_TAG => "ECP5"
    )
    port map (
      clk => clk_25m_i,
      rstn => rstn,
      spi_sclk_i => spi_sclk_i,
      spi_cs_n_i => spi_cs_n_i,
      spi_mosi_i => spi_mosi_i,
      spi_miso_o => spi_miso_o,
      spi_miso_oen => spi_miso_oe,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_data_in,
      reg_data_out => reg_data_out,
      reg_wr_rdy => '1',
      reg_rd_rdy => '1',
      reg_wr_valid => reg_wr_valid,
      reg_rd_valid => reg_rd_valid,
      reg_error => '0'
    );

  process(clk_25m_i)
  begin
    if rising_edge(clk_25m_i) then
      reg_wr_valid <= '0';
      reg_rd_valid <= '0';

      if rstn = '0' then
        control_reg <= (others => '0');
        scratch_reg <= x"52414449";
        status_reg <= x"00000001";
        reg_data_out <= (others => '0');
      else
        status_reg(15 downto 0) <= std_logic_vector(unsigned(status_reg(15 downto 0)) + 1);

        if reg_wr_en = '1' then
          case reg_wr_addr(7 downto 0) is
            when x"00" =>
              control_reg <= reg_data_in;
            when x"04" =>
              scratch_reg <= reg_data_in;
            when others =>
              null;
          end case;
          reg_wr_valid <= '1';
        end if;

        if reg_rd_en = '1' then
          case reg_rd_addr(7 downto 0) is
            when x"00" =>
              reg_data_out <= control_reg;
            when x"04" =>
              reg_data_out <= scratch_reg;
            when x"08" =>
              reg_data_out <= status_reg;
            when others =>
              reg_data_out <= x"52414430";
          end case;
          reg_rd_valid <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
