library ieee;
use ieee.std_logic_1164.all;

-- Single-bit clock-domain synchronizer.
entity rad_cdc_single is
  generic (
    VENDOR : string := "generic";
    STAGES : positive := 2;
    INIT   : std_logic := '0'
  );
  port (
    dest_clk : in  std_logic;
    src_i    : in  std_logic;
    dest_o   : out std_logic
  );
end entity;

architecture rtl of rad_cdc_single is
  signal sync_r : std_logic_vector(STAGES - 1 downto 0) := (others => INIT);
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_single STAGES must be at least 2"
    severity failure;

  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      sync_r(0) <= src_i;
      for index in 1 to STAGES - 1 loop
        sync_r(index) <= sync_r(index - 1);
      end loop;
    end if;
  end process;

  dest_o <= sync_r(STAGES - 1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Multi-bit synchronizer for independently changing static/status bits.
entity rad_cdc_array_single is
  generic (
    VENDOR     : string := "generic";
    DATA_WIDTH : positive := 1;
    STAGES     : positive := 2;
    INIT       : std_logic := '0'
  );
  port (
    dest_clk : in  std_logic;
    src_i    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    dest_o   : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of rad_cdc_array_single is
  type sync_array_t is array (natural range <>) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal sync_r : sync_array_t(0 to STAGES - 1) := (others => (others => INIT));
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_array_single STAGES must be at least 2"
    severity failure;

  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      sync_r(0) <= src_i;
      for index in 1 to STAGES - 1 loop
        sync_r(index) <= sync_r(index - 1);
      end loop;
    end if;
  end process;

  dest_o <= sync_r(STAGES - 1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Synchronous reset synchronizer. Assertion and deassertion are sampled by
-- dest_clk.
entity rad_cdc_sync_rst is
  generic (
    VENDOR      : string := "generic";
    STAGES      : positive := 2;
    ACTIVE_HIGH : boolean := true
  );
  port (
    dest_clk : in  std_logic;
    rst_i    : in  std_logic;
    rst_o    : out std_logic
  );
end entity;

architecture rtl of rad_cdc_sync_rst is
  constant C_ASSERTED   : std_logic := '1';
  constant C_DEASSERTED : std_logic := '0';
  signal sync_r         : std_logic_vector(STAGES - 1 downto 0) := (others => C_ASSERTED);
  signal rst_active     : std_logic;
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_sync_rst STAGES must be at least 2"
    severity failure;

  rst_active <= rst_i when ACTIVE_HIGH else not rst_i;

  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      sync_r(0) <= rst_active;
      for index in 1 to STAGES - 1 loop
        sync_r(index) <= sync_r(index - 1);
      end loop;
    end if;
  end process;

  rst_o <= sync_r(STAGES - 1) when ACTIVE_HIGH else not sync_r(STAGES - 1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Async-assert, sync-deassert reset synchronizer.
entity rad_cdc_async_rst is
  generic (
    VENDOR      : string := "generic";
    STAGES      : positive := 2;
    ACTIVE_HIGH : boolean := true
  );
  port (
    dest_clk : in  std_logic;
    rst_i    : in  std_logic;
    rst_o    : out std_logic
  );
end entity;

architecture rtl of rad_cdc_async_rst is
  signal sync_r     : std_logic_vector(STAGES - 1 downto 0) := (others => '1');
  signal rst_active : std_logic;
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_async_rst STAGES must be at least 2"
    severity failure;

  rst_active <= rst_i when ACTIVE_HIGH else not rst_i;

  process(dest_clk, rst_active)
  begin
    if rst_active = '1' then
      sync_r <= (others => '1');
    elsif rising_edge(dest_clk) then
      sync_r(0) <= '0';
      for index in 1 to STAGES - 1 loop
        sync_r(index) <= sync_r(index - 1);
      end loop;
    end if;
  end process;

  rst_o <= sync_r(STAGES - 1) when ACTIVE_HIGH else not sync_r(STAGES - 1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Pulse transfer using a source-domain toggle and destination-domain edge
-- detection.
entity rad_cdc_pulse is
  generic (
    VENDOR : string := "generic";
    STAGES : positive := 2
  );
  port (
    src_clk      : in  std_logic;
    src_rst      : in  std_logic;
    src_pulse_i  : in  std_logic;
    dest_clk     : in  std_logic;
    dest_rst     : in  std_logic;
    dest_pulse_o : out std_logic
  );
end entity;

architecture rtl of rad_cdc_pulse is
  signal src_toggle_r : std_logic := '0';
  signal dest_sync_r  : std_logic_vector(STAGES downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of dest_sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_pulse STAGES must be at least 2"
    severity failure;

  process(src_clk)
  begin
    if rising_edge(src_clk) then
      if src_rst = '1' then
        src_toggle_r <= '0';
      elsif src_pulse_i = '1' then
        src_toggle_r <= not src_toggle_r;
      end if;
    end if;
  end process;

  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      if dest_rst = '1' then
        dest_sync_r <= (others => '0');
      else
        dest_sync_r(0) <= src_toggle_r;
        for index in 1 to STAGES loop
          dest_sync_r(index) <= dest_sync_r(index - 1);
        end loop;
      end if;
    end if;
  end process;

  dest_pulse_o <= dest_sync_r(STAGES) xor dest_sync_r(STAGES - 1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Gray-coded multi-bit CDC. The source input must change by one bit per
-- transfer; this wrapper synchronizes each bit into dest_clk.
entity rad_cdc_gray is
  generic (
    VENDOR     : string := "generic";
    DATA_WIDTH : positive := 4;
    STAGES     : positive := 2
  );
  port (
    dest_clk    : in  std_logic;
    src_gray_i  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    dest_gray_o : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of rad_cdc_gray is
  type sync_array_t is array (natural range <>) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal sync_r : sync_array_t(0 to STAGES - 1) := (others => (others => '0'));
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_gray STAGES must be at least 2"
    severity failure;

  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      sync_r(0) <= src_gray_i;
      for index in 1 to STAGES - 1 loop
        sync_r(index) <= sync_r(index - 1);
      end loop;
    end if;
  end process;

  dest_gray_o <= sync_r(STAGES - 1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Two-phase valid/ready handshake CDC for a source-held payload.
entity rad_cdc_handshake is
  generic (
    VENDOR     : string := "generic";
    DATA_WIDTH : positive := 1;
    STAGES     : positive := 2
  );
  port (
    src_clk     : in  std_logic;
    src_rst     : in  std_logic;
    src_valid_i : in  std_logic;
    src_data_i  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    src_ready_o : out std_logic;
    dest_clk    : in  std_logic;
    dest_rst    : in  std_logic;
    dest_valid_o: out std_logic;
    dest_data_o : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    dest_ready_i: in  std_logic
  );
end entity;

architecture rtl of rad_cdc_handshake is
  signal src_req_toggle_r  : std_logic := '0';
  signal src_busy_r        : std_logic := '0';
  signal src_data_hold_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal src_ack_sync_r    : std_logic_vector(STAGES - 1 downto 0) := (others => '0');
  signal dest_req_sync_r   : std_logic_vector(STAGES - 1 downto 0) := (others => '0');
  signal dest_req_seen_r   : std_logic := '0';
  signal dest_ack_toggle_r : std_logic := '0';
  signal dest_valid_r      : std_logic := '0';
  signal dest_data_r       : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of src_ack_sync_r : signal is "TRUE";
  attribute ASYNC_REG of dest_req_sync_r : signal is "TRUE";
begin
  assert STAGES >= 2
    report "rad_cdc_handshake STAGES must be at least 2"
    severity failure;

  src_ready_o <= not src_busy_r;
  dest_valid_o <= dest_valid_r;
  dest_data_o <= dest_data_r;

  process(src_clk)
  begin
    if rising_edge(src_clk) then
      if src_rst = '1' then
        src_req_toggle_r <= '0';
        src_busy_r <= '0';
        src_data_hold_r <= (others => '0');
        src_ack_sync_r <= (others => '0');
      else
        src_ack_sync_r(0) <= dest_ack_toggle_r;
        for index in 1 to STAGES - 1 loop
          src_ack_sync_r(index) <= src_ack_sync_r(index - 1);
        end loop;

        if src_busy_r = '1' then
          if src_ack_sync_r(STAGES - 1) = src_req_toggle_r then
            src_busy_r <= '0';
          end if;
        elsif src_valid_i = '1' then
          src_data_hold_r <= src_data_i;
          src_req_toggle_r <= not src_req_toggle_r;
          src_busy_r <= '1';
        end if;
      end if;
    end if;
  end process;

  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      if dest_rst = '1' then
        dest_req_sync_r <= (others => '0');
        dest_req_seen_r <= '0';
        dest_ack_toggle_r <= '0';
        dest_valid_r <= '0';
        dest_data_r <= (others => '0');
      else
        dest_req_sync_r(0) <= src_req_toggle_r;
        for index in 1 to STAGES - 1 loop
          dest_req_sync_r(index) <= dest_req_sync_r(index - 1);
        end loop;

        if dest_valid_r = '1' then
          if dest_ready_i = '1' then
            dest_valid_r <= '0';
            dest_ack_toggle_r <= dest_req_seen_r;
          end if;
        elsif dest_req_sync_r(STAGES - 1) /= dest_req_seen_r then
          dest_req_seen_r <= dest_req_sync_r(STAGES - 1);
          dest_data_r <= src_data_hold_r;
          dest_valid_r <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
