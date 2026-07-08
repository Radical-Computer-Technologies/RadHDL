library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vcomponents is
  component xpm_memory_tdpram is
    generic (
      MEMORY_SIZE : integer := 1024;
      MEMORY_PRIMITIVE : string := "auto";
      CLOCKING_MODE : string := "common_clock";
      ECC_MODE : string := "no_ecc";
      ECC_TYPE : string := "none";
      MEMORY_INIT_FILE : string := "none";
      MEMORY_INIT_PARAM : string := "0";
      USE_MEM_INIT : integer := 0;
      USE_MEM_INIT_MMI : integer := 0;
      WAKEUP_TIME : string := "disable_sleep";
      MESSAGE_CONTROL : integer := 0;
      MEMORY_OPTIMIZATION : string := "true";
      CASCADE_HEIGHT : integer := 0;
      AUTO_SLEEP_TIME : integer := 0;
      SIM_ASSERT_CHK : integer := 0;
      USE_EMBEDDED_CONSTRAINT : integer := 0;
      WRITE_DATA_WIDTH_A : integer := 32;
      READ_DATA_WIDTH_A : integer := 32;
      BYTE_WRITE_WIDTH_A : integer := 32;
      ADDR_WIDTH_A : integer := 8;
      READ_RESET_VALUE_A : string := "0";
      READ_LATENCY_A : integer := 1;
      WRITE_MODE_A : string := "read_first";
      RST_MODE_A : string := "SYNC";
      WRITE_DATA_WIDTH_B : integer := 32;
      READ_DATA_WIDTH_B : integer := 32;
      BYTE_WRITE_WIDTH_B : integer := 32;
      ADDR_WIDTH_B : integer := 8;
      READ_RESET_VALUE_B : string := "0";
      READ_LATENCY_B : integer := 1;
      WRITE_MODE_B : string := "read_first";
      RST_MODE_B : string := "SYNC"
    );
    port (
      sleep : in std_logic;
      clka : in std_logic;
      rsta : in std_logic;
      ena : in std_logic;
      regcea : in std_logic;
      wea : in std_logic_vector((WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A) - 1 downto 0);
      addra : in std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
      dina : in std_logic_vector(WRITE_DATA_WIDTH_A - 1 downto 0);
      injectsbiterra : in std_logic;
      injectdbiterra : in std_logic;
      douta : out std_logic_vector(READ_DATA_WIDTH_A - 1 downto 0);
      sbiterra : out std_logic;
      dbiterra : out std_logic;
      clkb : in std_logic;
      rstb : in std_logic;
      enb : in std_logic;
      regceb : in std_logic;
      web : in std_logic_vector((WRITE_DATA_WIDTH_B / BYTE_WRITE_WIDTH_B) - 1 downto 0);
      addrb : in std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
      dinb : in std_logic_vector(WRITE_DATA_WIDTH_B - 1 downto 0);
      injectsbiterrb : in std_logic;
      injectdbiterrb : in std_logic;
      doutb : out std_logic_vector(READ_DATA_WIDTH_B - 1 downto 0);
      sbiterrb : out std_logic;
      dbiterrb : out std_logic
    );
  end component;

  component xpm_memory_sdpram is
    generic (
      MEMORY_SIZE : integer := 1024;
      MEMORY_PRIMITIVE : string := "auto";
      CLOCKING_MODE : string := "common_clock";
      ECC_MODE : string := "no_ecc";
      MEMORY_INIT_FILE : string := "none";
      MEMORY_INIT_PARAM : string := "0";
      USE_MEM_INIT : integer := 0;
      WAKEUP_TIME : string := "disable_sleep";
      MESSAGE_CONTROL : integer := 0;
      MEMORY_OPTIMIZATION : string := "true";
      CASCADE_HEIGHT : integer := 0;
      WRITE_DATA_WIDTH_A : integer := 32;
      BYTE_WRITE_WIDTH_A : integer := 32;
      ADDR_WIDTH_A : integer := 8;
      READ_DATA_WIDTH_B : integer := 32;
      ADDR_WIDTH_B : integer := 8;
      READ_RESET_VALUE_B : string := "0";
      READ_LATENCY_B : integer := 1;
      WRITE_MODE_B : string := "read_first";
      RST_MODE_A : string := "SYNC";
      RST_MODE_B : string := "SYNC"
    );
    port (
      sleep : in std_logic;
      clka : in std_logic;
      ena : in std_logic;
      wea : in std_logic_vector((WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A) - 1 downto 0);
      addra : in std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
      dina : in std_logic_vector(WRITE_DATA_WIDTH_A - 1 downto 0);
      injectsbiterra : in std_logic;
      injectdbiterra : in std_logic;
      clkb : in std_logic;
      rstb : in std_logic;
      enb : in std_logic;
      regceb : in std_logic;
      addrb : in std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
      doutb : out std_logic_vector(READ_DATA_WIDTH_B - 1 downto 0);
      sbiterrb : out std_logic;
      dbiterrb : out std_logic
    );
  end component;

  component xpm_memory_sprom is
    generic (
      MEMORY_SIZE : integer := 1024;
      MEMORY_PRIMITIVE : string := "auto";
      ECC_MODE : string := "no_ecc";
      MEMORY_INIT_FILE : string := "none";
      MEMORY_INIT_PARAM : string := "";
      USE_MEM_INIT : integer := 0;
      USE_MEM_INIT_MMI : integer := 0;
      WAKEUP_TIME : string := "disable_sleep";
      MESSAGE_CONTROL : integer := 0;
      MEMORY_OPTIMIZATION : string := "true";
      READ_DATA_WIDTH_A : integer := 32;
      ADDR_WIDTH_A : integer := 8;
      READ_RESET_VALUE_A : string := "0";
      READ_LATENCY_A : integer := 1;
      RST_MODE_A : string := "SYNC"
    );
    port (
      sleep : in std_logic;
      clka : in std_logic;
      rsta : in std_logic;
      ena : in std_logic;
      regcea : in std_logic;
      addra : in std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
      injectsbiterra : in std_logic;
      injectdbiterra : in std_logic;
      douta : out std_logic_vector(READ_DATA_WIDTH_A - 1 downto 0);
      sbiterra : out std_logic;
      dbiterra : out std_logic
    );
  end component;

  component xpm_cdc_single is
    generic (DEST_SYNC_FF : integer := 3);
    port (
      src_clk : in std_logic;
      src_in : in std_logic;
      dest_clk : in std_logic;
      dest_out : out std_logic
    );
  end component;

  component xpm_cdc_array_single is
    generic (
      DEST_SYNC_FF : integer := 3;
      WIDTH : integer := 1
    );
    port (
      src_clk : in std_logic;
      src_in : in std_logic_vector(WIDTH - 1 downto 0);
      dest_clk : in std_logic;
      dest_out : out std_logic_vector(WIDTH - 1 downto 0)
    );
  end component;
end package;

package body vcomponents is
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xpm_memory_tdpram is
  generic (
    MEMORY_SIZE : integer := 1024;
    MEMORY_PRIMITIVE : string := "auto";
    CLOCKING_MODE : string := "common_clock";
    ECC_MODE : string := "no_ecc";
    ECC_TYPE : string := "none";
    MEMORY_INIT_FILE : string := "none";
    MEMORY_INIT_PARAM : string := "0";
    USE_MEM_INIT : integer := 0;
    USE_MEM_INIT_MMI : integer := 0;
    WAKEUP_TIME : string := "disable_sleep";
    MESSAGE_CONTROL : integer := 0;
    MEMORY_OPTIMIZATION : string := "true";
    CASCADE_HEIGHT : integer := 0;
    AUTO_SLEEP_TIME : integer := 0;
    SIM_ASSERT_CHK : integer := 0;
    USE_EMBEDDED_CONSTRAINT : integer := 0;
    WRITE_DATA_WIDTH_A : integer := 32;
    READ_DATA_WIDTH_A : integer := 32;
    BYTE_WRITE_WIDTH_A : integer := 32;
    ADDR_WIDTH_A : integer := 8;
    READ_RESET_VALUE_A : string := "0";
    READ_LATENCY_A : integer := 1;
    WRITE_MODE_A : string := "read_first";
    RST_MODE_A : string := "SYNC";
    WRITE_DATA_WIDTH_B : integer := 32;
    READ_DATA_WIDTH_B : integer := 32;
    BYTE_WRITE_WIDTH_B : integer := 32;
    ADDR_WIDTH_B : integer := 8;
    READ_RESET_VALUE_B : string := "0";
    READ_LATENCY_B : integer := 1;
    WRITE_MODE_B : string := "read_first";
    RST_MODE_B : string := "SYNC"
  );
  port (
    sleep : in std_logic;
    clka : in std_logic;
    rsta : in std_logic;
    ena : in std_logic;
    regcea : in std_logic;
    wea : in std_logic_vector((WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A) - 1 downto 0);
    addra : in std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
    dina : in std_logic_vector(WRITE_DATA_WIDTH_A - 1 downto 0);
    injectsbiterra : in std_logic;
    injectdbiterra : in std_logic;
    douta : out std_logic_vector(READ_DATA_WIDTH_A - 1 downto 0);
    sbiterra : out std_logic;
    dbiterra : out std_logic;
    clkb : in std_logic;
    rstb : in std_logic;
    enb : in std_logic;
    regceb : in std_logic;
    web : in std_logic_vector((WRITE_DATA_WIDTH_B / BYTE_WRITE_WIDTH_B) - 1 downto 0);
    addrb : in std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
    dinb : in std_logic_vector(WRITE_DATA_WIDTH_B - 1 downto 0);
    injectsbiterrb : in std_logic;
    injectdbiterrb : in std_logic;
    doutb : out std_logic_vector(READ_DATA_WIDTH_B - 1 downto 0);
    sbiterrb : out std_logic;
    dbiterrb : out std_logic
  );
end entity;

architecture sim of xpm_memory_tdpram is
  constant C_DEPTH : positive := 4096;
  subtype word_t is std_logic_vector(dina'range);
  type ram_t is array (natural range <>) of word_t;
  signal mem : ram_t(0 to C_DEPTH - 1) := (others => (others => '0'));

  function addr_index(addr : std_logic_vector) return natural is
  begin
    if addr'length = 0 then
      return 0;
    end if;
    return to_integer(unsigned(addr)) mod C_DEPTH;
  end function;
begin
  process(clka)
  begin
    if rising_edge(clka) then
      if rsta = '1' then
        douta <= (douta'range => '0');
      elsif ena = '1' then
        if wea'length > 0 and wea(wea'left) = '1' then
          mem(addr_index(addra)) <= dina;
        end if;
        douta <= mem(addr_index(addra))(douta'range);
      end if;
    end if;
  end process;

  process(clkb)
  begin
    if rising_edge(clkb) then
      if rstb = '1' then
        doutb <= (doutb'range => '0');
      elsif enb = '1' then
        if web'length > 0 and web(web'left) = '1' then
          mem(addr_index(addrb)) <= dinb(mem(0)'range);
        end if;
        doutb <= mem(addr_index(addrb))(doutb'range);
      end if;
    end if;
  end process;

  sbiterra <= '0';
  dbiterra <= '0';
  sbiterrb <= '0';
  dbiterrb <= '0';
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xpm_memory_sdpram is
  generic (
    MEMORY_SIZE : integer := 1024;
    MEMORY_PRIMITIVE : string := "auto";
    CLOCKING_MODE : string := "common_clock";
    ECC_MODE : string := "no_ecc";
    MEMORY_INIT_FILE : string := "none";
    MEMORY_INIT_PARAM : string := "0";
    USE_MEM_INIT : integer := 0;
    WAKEUP_TIME : string := "disable_sleep";
    MESSAGE_CONTROL : integer := 0;
    MEMORY_OPTIMIZATION : string := "true";
    CASCADE_HEIGHT : integer := 0;
    WRITE_DATA_WIDTH_A : integer := 32;
    BYTE_WRITE_WIDTH_A : integer := 32;
    ADDR_WIDTH_A : integer := 8;
    READ_DATA_WIDTH_B : integer := 32;
    ADDR_WIDTH_B : integer := 8;
    READ_RESET_VALUE_B : string := "0";
    READ_LATENCY_B : integer := 1;
    WRITE_MODE_B : string := "read_first";
    RST_MODE_A : string := "SYNC";
    RST_MODE_B : string := "SYNC"
  );
  port (
    sleep : in std_logic;
    clka : in std_logic;
    ena : in std_logic;
    wea : in std_logic_vector((WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A) - 1 downto 0);
    addra : in std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
    dina : in std_logic_vector(WRITE_DATA_WIDTH_A - 1 downto 0);
    injectsbiterra : in std_logic;
    injectdbiterra : in std_logic;
    clkb : in std_logic;
    rstb : in std_logic;
    enb : in std_logic;
    regceb : in std_logic;
    addrb : in std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
    doutb : out std_logic_vector(READ_DATA_WIDTH_B - 1 downto 0);
    sbiterrb : out std_logic;
    dbiterrb : out std_logic
  );
end entity;

architecture sim of xpm_memory_sdpram is
  constant C_DEPTH : positive := 4096;
  subtype word_t is std_logic_vector(dina'range);
  type ram_t is array (natural range <>) of word_t;
  signal mem : ram_t(0 to C_DEPTH - 1) := (others => (others => '0'));

  function addr_index(addr : std_logic_vector) return natural is
  begin
    if addr'length = 0 then
      return 0;
    end if;
    return to_integer(unsigned(addr)) mod C_DEPTH;
  end function;
begin
  process(clka)
  begin
    if rising_edge(clka) then
      if ena = '1' and wea'length > 0 and wea(wea'left) = '1' then
        mem(addr_index(addra)) <= dina;
      end if;
    end if;
  end process;

  process(clkb)
  begin
    if rising_edge(clkb) then
      if rstb = '1' then
        doutb <= (doutb'range => '0');
      elsif enb = '1' then
        doutb <= mem(addr_index(addrb))(doutb'range);
      end if;
    end if;
  end process;

  sbiterrb <= '0';
  dbiterrb <= '0';
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xpm_memory_sprom is
  generic (
    MEMORY_SIZE : integer := 1024;
    MEMORY_PRIMITIVE : string := "auto";
    ECC_MODE : string := "no_ecc";
    MEMORY_INIT_FILE : string := "none";
    MEMORY_INIT_PARAM : string := "";
    USE_MEM_INIT : integer := 0;
    USE_MEM_INIT_MMI : integer := 0;
    WAKEUP_TIME : string := "disable_sleep";
    MESSAGE_CONTROL : integer := 0;
    MEMORY_OPTIMIZATION : string := "true";
    READ_DATA_WIDTH_A : integer := 32;
    ADDR_WIDTH_A : integer := 8;
    READ_RESET_VALUE_A : string := "0";
    READ_LATENCY_A : integer := 1;
    RST_MODE_A : string := "SYNC"
  );
  port (
    sleep : in std_logic;
    clka : in std_logic;
    rsta : in std_logic;
    ena : in std_logic;
    regcea : in std_logic;
    addra : in std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
    injectsbiterra : in std_logic;
    injectdbiterra : in std_logic;
    douta : out std_logic_vector(READ_DATA_WIDTH_A - 1 downto 0);
    sbiterra : out std_logic;
    dbiterra : out std_logic
  );
end entity;

architecture sim of xpm_memory_sprom is
begin
  process(clka)
  begin
    if rising_edge(clka) then
      douta <= (douta'range => '0');
    end if;
  end process;
  sbiterra <= '0';
  dbiterra <= '0';
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity xpm_cdc_single is
  generic (DEST_SYNC_FF : integer := 3);
  port (
    src_clk : in std_logic;
    src_in : in std_logic;
    dest_clk : in std_logic;
    dest_out : out std_logic
  );
end entity;

architecture sim of xpm_cdc_single is
  signal sync : std_logic := '0';
begin
  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      sync <= src_in;
    end if;
  end process;
  dest_out <= sync;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity xpm_cdc_array_single is
  generic (
    DEST_SYNC_FF : integer := 3;
    WIDTH : integer := 1
  );
  port (
    src_clk : in std_logic;
    src_in : in std_logic_vector(WIDTH - 1 downto 0);
    dest_clk : in std_logic;
    dest_out : out std_logic_vector(WIDTH - 1 downto 0)
  );
end entity;

architecture sim of xpm_cdc_array_single is
  signal sync : std_logic_vector(src_in'range) := (others => '0');
begin
  process(dest_clk)
  begin
    if rising_edge(dest_clk) then
      sync <= src_in;
    end if;
  end process;
  dest_out <= sync(dest_out'range);
end architecture;
