library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- RAD separate-clock FIFO built from explicit vendor RAM wrappers and Gray
-- pointer CDC. This is the ECP5 path and the generic fallback for families
-- without vendor FIFO IP.
entity radhdl_fifo_bram_async is
  generic (
    VENDOR        : string   := "generic";
    DEVICE_FAMILY : string   := "generic";
    DATA_WIDTH    : positive := 32;
    ADDR_WIDTH    : positive := 4;
    DEPTH         : positive := 16;
    CDC_STAGES    : positive := 2;
    SIMULATION    : boolean  := false
  );
  port (
    wr_clk        : in  std_logic;
    rd_clk        : in  std_logic;
    rst           : in  std_logic;
    wr_en         : in  std_logic;
    rd_en         : in  std_logic;
    din           : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    dout          : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    empty         : out std_logic;
    full          : out std_logic;
    data_valid    : out std_logic;
    wr_data_count : out unsigned(ADDR_WIDTH downto 0);
    rd_data_count : out unsigned(ADDR_WIDTH downto 0)
  );
end entity;

architecture rtl of radhdl_fifo_bram_async is
  subtype ptr_t is unsigned(ADDR_WIDTH downto 0);
  subtype addr_t is std_logic_vector(ADDR_WIDTH - 1 downto 0);

  function bin_to_gray(value : ptr_t) return std_logic_vector is
    variable result : std_logic_vector(value'range);
  begin
    result := std_logic_vector(value xor ('0' & value(value'high downto 1)));
    return result;
  end function;

  function gray_to_bin(value : std_logic_vector) return ptr_t is
    variable result : ptr_t := (others => '0');
  begin
    result(result'high) := value(value'high);
    for index in result'high - 1 downto 0 loop
      result(index) := result(index + 1) xor value(index);
    end loop;
    return result;
  end function;

  signal wr_bin_r          : ptr_t := (others => '0');
  signal wr_gray_r         : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_gray_next      : std_logic_vector(ADDR_WIDTH downto 0);
  signal rd_gray_in_wr     : std_logic_vector(ADDR_WIDTH downto 0);
  signal rd_bin_in_wr      : ptr_t;
  signal wr_full_r         : std_logic := '0';
  signal wr_fire           : std_logic;

  signal rd_bin_r          : ptr_t := (others => '0');
  signal rd_gray_r         : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_gray_in_rd     : std_logic_vector(ADDR_WIDTH downto 0);
  signal wr_bin_in_rd      : ptr_t;
  signal rd_empty_r        : std_logic := '1';
  signal rd_fire           : std_logic;
  signal rd_fire_r         : std_logic := '0';
  signal ram_dout          : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal unused_dout       : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal wr_rst_sync       : std_logic;
  signal rd_rst_sync       : std_logic;
begin
  assert DEPTH = 2 ** ADDR_WIDTH
    report "radhdl_fifo_bram_async DEPTH must equal 2**ADDR_WIDTH"
    severity failure;
  assert ADDR_WIDTH >= 2
    report "radhdl_fifo_bram_async ADDR_WIDTH must be at least 2"
    severity failure;

  rd_bin_in_wr <= gray_to_bin(rd_gray_in_wr);
  wr_bin_in_rd <= gray_to_bin(wr_gray_in_rd);
  wr_gray_next <= bin_to_gray(wr_bin_r + 1);
  wr_fire <= wr_en and not wr_full_r;
  rd_fire <= rd_en and not rd_empty_r;

  full <= wr_full_r;
  empty <= rd_empty_r;
  data_valid <= rd_fire_r;
  dout <= ram_dout;
  wr_data_count <= wr_bin_r - rd_bin_in_wr;
  rd_data_count <= wr_bin_in_rd - rd_bin_r;

  wr_rst_cdc : entity work.rad_cdc_async_rst
    generic map (
      VENDOR => VENDOR,
      STAGES => CDC_STAGES,
      ACTIVE_HIGH => true
    )
    port map (
      dest_clk => wr_clk,
      rst_i => rst,
      rst_o => wr_rst_sync
    );

  rd_rst_cdc : entity work.rad_cdc_async_rst
    generic map (
      VENDOR => VENDOR,
      STAGES => CDC_STAGES,
      ACTIVE_HIGH => true
    )
    port map (
      dest_clk => rd_clk,
      rst_i => rst,
      rst_o => rd_rst_sync
    );

  rd_ptr_cdc : entity work.rad_cdc_gray
    generic map (
      VENDOR => VENDOR,
      DATA_WIDTH => ADDR_WIDTH + 1,
      STAGES => CDC_STAGES
    )
    port map (
      dest_clk => wr_clk,
      src_gray_i => rd_gray_r,
      dest_gray_o => rd_gray_in_wr
    );

  wr_ptr_cdc : entity work.rad_cdc_gray
    generic map (
      VENDOR => VENDOR,
      DATA_WIDTH => ADDR_WIDTH + 1,
      STAGES => CDC_STAGES
    )
    port map (
      dest_clk => rd_clk,
      src_gray_i => wr_gray_r,
      dest_gray_o => wr_gray_in_rd
    );

  ram_i : entity work.radhdl_ram
    generic map (
      VENDOR => VENDOR,
      DEVICE_FAMILY => DEVICE_FAMILY,
      MODE => "tdp",
      MEMORY_KIND => "bram",
      DATA_WIDTH => DATA_WIDTH,
      ADDR_WIDTH => ADDR_WIDTH,
      DEPTH => DEPTH,
      CLOCKING_MODE => "independent_clock",
      SIMULATION => SIMULATION
    )
    port map (
      clka => wr_clk,
      rsta => wr_rst_sync,
      a_addr => std_logic_vector(wr_bin_r(ADDR_WIDTH - 1 downto 0)),
      a_din => din,
      a_dout => unused_dout,
      a_we => wr_fire,
      clkb => rd_clk,
      rstb => rd_rst_sync,
      b_addr => std_logic_vector(rd_bin_r(ADDR_WIDTH - 1 downto 0)),
      b_din => (others => '0'),
      b_dout => ram_dout,
      b_we => '0'
    );

  process(wr_clk)
    variable next_bin : ptr_t;
    variable next_gray : std_logic_vector(ADDR_WIDTH downto 0);
  begin
    if rising_edge(wr_clk) then
      if wr_rst_sync = '1' then
        wr_bin_r <= (others => '0');
        wr_gray_r <= (others => '0');
        wr_full_r <= '0';
      else
        next_bin := wr_bin_r;
        if wr_fire = '1' then
          next_bin := wr_bin_r + 1;
        end if;
        next_gray := bin_to_gray(next_bin);
        wr_bin_r <= next_bin;
        wr_gray_r <= next_gray;
        if next_gray(ADDR_WIDTH downto ADDR_WIDTH - 1) =
           not rd_gray_in_wr(ADDR_WIDTH downto ADDR_WIDTH - 1) and
           next_gray(ADDR_WIDTH - 2 downto 0) =
           rd_gray_in_wr(ADDR_WIDTH - 2 downto 0) then
          wr_full_r <= '1';
        else
          wr_full_r <= '0';
        end if;
      end if;
    end if;
  end process;

  process(rd_clk)
    variable next_bin : ptr_t;
    variable next_gray : std_logic_vector(ADDR_WIDTH downto 0);
  begin
    if rising_edge(rd_clk) then
      if rd_rst_sync = '1' then
        rd_bin_r <= (others => '0');
        rd_gray_r <= (others => '0');
        rd_empty_r <= '1';
        rd_fire_r <= '0';
      else
        next_bin := rd_bin_r;
        rd_fire_r <= rd_fire;
        if rd_fire = '1' then
          next_bin := rd_bin_r + 1;
        end if;
        next_gray := bin_to_gray(next_bin);
        rd_bin_r <= next_bin;
        rd_gray_r <= next_gray;
        if next_gray = wr_gray_in_rd then
          rd_empty_r <= '1';
        else
          rd_empty_r <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
