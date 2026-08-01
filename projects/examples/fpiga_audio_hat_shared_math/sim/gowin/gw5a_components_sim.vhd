library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package components is
  component ODDR is
    generic (
      INIT      : std_logic := '0';
      TXCLK_POL : std_logic := '0'
    );
    port (
      Q0  : out std_logic;
      Q1  : out std_logic;
      D0  : in  std_logic;
      D1  : in  std_logic;
      TX  : in  std_logic;
      CLK : in  std_logic
    );
  end component;

  component PLLA is
    generic (
      FCLKIN         : string := "50";
      IDIV_SEL       : integer := 1;
      FBDIV_SEL      : integer := 1;
      ODIV0_SEL      : integer := 8;
      ODIV0_FRAC_SEL : integer := 0;
      ODIV1_SEL      : integer := 8;
      ODIV2_SEL      : integer := 8;
      ODIV3_SEL      : integer := 8;
      ODIV4_SEL      : integer := 8;
      ODIV5_SEL      : integer := 8;
      ODIV6_SEL      : integer := 8;
      MDIV_SEL       : integer := 8;
      CLKOUT0_EN     : string := "TRUE";
      CLKOUT1_EN     : string := "FALSE";
      CLKOUT2_EN     : string := "TRUE";
      CLKOUT3_EN     : string := "FALSE";
      CLKOUT4_EN     : string := "FALSE";
      CLKOUT5_EN     : string := "FALSE";
      CLKOUT6_EN     : string := "FALSE";
      CLKFB_SEL      : string := "INTERNAL"
    );
    port (
      CLKIN          : in  std_logic;
      CLKFB          : in  std_logic;
      RESET          : in  std_logic;
      PLLPWD         : in  std_logic;
      RESET_I        : in  std_logic;
      RESET_O        : in  std_logic;
      PSSEL          : in  std_logic_vector(2 downto 0);
      PSDIR          : in  std_logic;
      PSPULSE        : in  std_logic;
      SSCPOL         : in  std_logic;
      SSCON          : in  std_logic;
      SSCMDSEL       : in  std_logic_vector(6 downto 0);
      SSCMDSEL_FRAC  : in  std_logic_vector(2 downto 0);
      MDCLK          : in  std_logic;
      MDOPC          : in  std_logic_vector(1 downto 0);
      MDAINC         : in  std_logic;
      MDWDI          : in  std_logic_vector(7 downto 0);
      MDRDO          : out std_logic_vector(7 downto 0);
      LOCK           : out std_logic;
      CLKOUT0        : out std_logic;
      CLKOUT1        : out std_logic;
      CLKOUT2        : out std_logic;
      CLKOUT3        : out std_logic;
      CLKOUT4        : out std_logic;
      CLKOUT5        : out std_logic;
      CLKOUT6        : out std_logic;
      CLKFBOUT       : out std_logic
    );
  end component;

  component MULTALU27X18 is
    generic (
      AREG_CLK        : string := "CLK0";
      AREG_CE         : string := "CE0";
      AREG_RESET      : string := "RESET0";
      BREG_CLK        : string := "CLK0";
      BREG_CE         : string := "CE0";
      BREG_RESET      : string := "RESET0";
      OREG_CLK        : string := "CLK0";
      OREG_CE         : string := "CE0";
      OREG_RESET      : string := "RESET0";
      MULT_RESET_MODE : string := "SYNC";
      C_SEL           : std_logic := '1';
      CASI_SEL        : std_logic := '0';
      ADD_SUB_0       : std_logic := '0';
      ADD_SUB_1       : std_logic := '0';
      MULT12X12_EN    : string := "FALSE"
    );
    port (
      A       : in  std_logic_vector(26 downto 0);
      SIA     : in  std_logic_vector(26 downto 0);
      B       : in  std_logic_vector(17 downto 0);
      D       : in  std_logic_vector(26 downto 0);
      C       : in  std_logic_vector(53 downto 0);
      CASI    : in  std_logic_vector(54 downto 0);
      ACCSEL  : in  std_logic;
      PSEL    : in  std_logic;
      ASEL    : in  std_logic;
      PADDSUB : in  std_logic;
      CSEL    : in  std_logic;
      CASISEL : in  std_logic;
      ADDSUB  : in  std_logic_vector(1 downto 0);
      CE      : in  std_logic_vector(1 downto 0);
      CLK     : in  std_logic_vector(1 downto 0);
      RESET   : in  std_logic_vector(1 downto 0);
      DOUT    : out std_logic_vector(47 downto 0);
      SOA     : out std_logic_vector(26 downto 0);
      CASO    : out std_logic_vector(54 downto 0)
    );
  end component;

  component DPB is
    generic (
      BIT_WIDTH_0 : integer := 16;
      BIT_WIDTH_1 : integer := 16;
      READ_MODE0  : std_logic := '0';
      READ_MODE1  : std_logic := '0';
      WRITE_MODE0 : string := "00";
      WRITE_MODE1 : string := "00";
      BLK_SEL_0   : std_logic_vector(2 downto 0) := "000";
      BLK_SEL_1   : std_logic_vector(2 downto 0) := "000";
      RESET_MODE  : string := "SYNC"
    );
    port (
      DOA     : out std_logic_vector(15 downto 0);
      DOB     : out std_logic_vector(15 downto 0);
      CLKA    : in  std_logic;
      CLKB    : in  std_logic;
      CEA     : in  std_logic;
      CEB     : in  std_logic;
      OCEA    : in  std_logic;
      OCEB    : in  std_logic;
      RESETA  : in  std_logic;
      RESETB  : in  std_logic;
      WREA    : in  std_logic;
      WREB    : in  std_logic;
      ADA     : in  std_logic_vector(13 downto 0);
      ADB     : in  std_logic_vector(13 downto 0);
      BLKSELA : in  std_logic_vector(2 downto 0);
      BLKSELB : in  std_logic_vector(2 downto 0);
      DIA     : in  std_logic_vector(15 downto 0);
      DIB     : in  std_logic_vector(15 downto 0)
    );
  end component;
end package;

library ieee;
use ieee.std_logic_1164.all;

entity ODDR is
  generic (
    INIT      : std_logic := '0';
    TXCLK_POL : std_logic := '0'
  );
  port (
    Q0  : out std_logic;
    Q1  : out std_logic;
    D0  : in  std_logic;
    D1  : in  std_logic;
    TX  : in  std_logic;
    CLK : in  std_logic
  );
end entity;

architecture sim of ODDR is
begin
  process(CLK)
  begin
    if rising_edge(CLK) then
      Q0 <= D0;
      Q1 <= D0;
    elsif falling_edge(CLK) then
      Q0 <= D1;
      Q1 <= D1;
    end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity PLLA is
  generic (
    FCLKIN         : string := "50";
    IDIV_SEL       : integer := 1;
    FBDIV_SEL      : integer := 1;
    ODIV0_SEL      : integer := 8;
    ODIV0_FRAC_SEL : integer := 0;
    ODIV1_SEL      : integer := 8;
    ODIV2_SEL      : integer := 8;
    ODIV3_SEL      : integer := 8;
    ODIV4_SEL      : integer := 8;
    ODIV5_SEL      : integer := 8;
    ODIV6_SEL      : integer := 8;
    MDIV_SEL       : integer := 8;
    CLKOUT0_EN     : string := "TRUE";
    CLKOUT1_EN     : string := "FALSE";
    CLKOUT2_EN     : string := "TRUE";
    CLKOUT3_EN     : string := "FALSE";
    CLKOUT4_EN     : string := "FALSE";
    CLKOUT5_EN     : string := "FALSE";
    CLKOUT6_EN     : string := "FALSE";
    CLKFB_SEL      : string := "INTERNAL"
  );
  port (
    CLKIN          : in  std_logic;
    CLKFB          : in  std_logic;
    RESET          : in  std_logic;
    PLLPWD         : in  std_logic;
    RESET_I        : in  std_logic;
    RESET_O        : in  std_logic;
    PSSEL          : in  std_logic_vector(2 downto 0);
    PSDIR          : in  std_logic;
    PSPULSE        : in  std_logic;
    SSCPOL         : in  std_logic;
    SSCON          : in  std_logic;
    SSCMDSEL       : in  std_logic_vector(6 downto 0);
    SSCMDSEL_FRAC  : in  std_logic_vector(2 downto 0);
    MDCLK          : in  std_logic;
    MDOPC          : in  std_logic_vector(1 downto 0);
    MDAINC         : in  std_logic;
    MDWDI          : in  std_logic_vector(7 downto 0);
    MDRDO          : out std_logic_vector(7 downto 0);
    LOCK           : out std_logic;
    CLKOUT0        : out std_logic;
    CLKOUT1        : out std_logic;
    CLKOUT2        : out std_logic;
    CLKOUT3        : out std_logic;
    CLKOUT4        : out std_logic;
    CLKOUT5        : out std_logic;
    CLKOUT6        : out std_logic;
    CLKFBOUT       : out std_logic
  );
end entity;

architecture sim of PLLA is
begin
  MDRDO <= (others => '0');
  CLKOUT1 <= '0';
  CLKOUT3 <= '0';
  CLKOUT4 <= '0';
  CLKOUT5 <= '0';
  CLKOUT6 <= '0';
  CLKFBOUT <= CLKOUT0;

  process
  begin
    LOCK <= '0';
    wait for 4 us;
    LOCK <= '1';
    wait;
  end process;

  process
  begin
    CLKOUT0 <= '0';
    wait for 40.69 ns;
    loop
      CLKOUT0 <= not CLKOUT0;
      wait for 40.69 ns;
    end loop;
  end process;

  process
  begin
    CLKOUT2 <= '0';
    wait for 5 ns;
    loop
      CLKOUT2 <= not CLKOUT2;
      wait for 5 ns;
    end loop;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MULTALU27X18 is
  generic (
    AREG_CLK        : string := "CLK0";
    AREG_CE         : string := "CE0";
    AREG_RESET      : string := "RESET0";
    BREG_CLK        : string := "CLK0";
    BREG_CE         : string := "CE0";
    BREG_RESET      : string := "RESET0";
    OREG_CLK        : string := "CLK0";
    OREG_CE         : string := "CE0";
    OREG_RESET      : string := "RESET0";
    MULT_RESET_MODE : string := "SYNC";
    C_SEL           : std_logic := '1';
    CASI_SEL        : std_logic := '0';
    ADD_SUB_0       : std_logic := '0';
    ADD_SUB_1       : std_logic := '0';
    MULT12X12_EN    : string := "FALSE"
  );
  port (
    A       : in  std_logic_vector(26 downto 0);
    SIA     : in  std_logic_vector(26 downto 0);
    B       : in  std_logic_vector(17 downto 0);
    D       : in  std_logic_vector(26 downto 0);
    C       : in  std_logic_vector(53 downto 0);
    CASI    : in  std_logic_vector(54 downto 0);
    ACCSEL  : in  std_logic;
    PSEL    : in  std_logic;
    ASEL    : in  std_logic;
    PADDSUB : in  std_logic;
    CSEL    : in  std_logic;
    CASISEL : in  std_logic;
    ADDSUB  : in  std_logic_vector(1 downto 0);
    CE      : in  std_logic_vector(1 downto 0);
    CLK     : in  std_logic_vector(1 downto 0);
    RESET   : in  std_logic_vector(1 downto 0);
    DOUT    : out std_logic_vector(47 downto 0);
    SOA     : out std_logic_vector(26 downto 0);
    CASO    : out std_logic_vector(54 downto 0)
  );
end entity;

architecture sim of MULTALU27X18 is
begin
  SOA <= A;
  CASO <= (others => '0');

  process(CLK)
    variable product_v : signed(47 downto 0);
  begin
    if rising_edge(CLK(0)) then
      if RESET(0) = '1' then
        DOUT <= (others => '0');
      elsif CE(0) = '1' then
        product_v := resize(signed(A) * signed(B), 48);
        DOUT <= std_logic_vector(product_v);
      end if;
    end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DPB is
  generic (
    BIT_WIDTH_0 : integer := 16;
    BIT_WIDTH_1 : integer := 16;
    READ_MODE0  : std_logic := '0';
    READ_MODE1  : std_logic := '0';
    WRITE_MODE0 : string := "00";
    WRITE_MODE1 : string := "00";
    BLK_SEL_0   : std_logic_vector(2 downto 0) := "000";
    BLK_SEL_1   : std_logic_vector(2 downto 0) := "000";
    RESET_MODE  : string := "SYNC"
  );
  port (
    DOA     : out std_logic_vector(15 downto 0);
    DOB     : out std_logic_vector(15 downto 0);
    CLKA    : in  std_logic;
    CLKB    : in  std_logic;
    CEA     : in  std_logic;
    CEB     : in  std_logic;
    OCEA    : in  std_logic;
    OCEB    : in  std_logic;
    RESETA  : in  std_logic;
    RESETB  : in  std_logic;
    WREA    : in  std_logic;
    WREB    : in  std_logic;
    ADA     : in  std_logic_vector(13 downto 0);
    ADB     : in  std_logic_vector(13 downto 0);
    BLKSELA : in  std_logic_vector(2 downto 0);
    BLKSELB : in  std_logic_vector(2 downto 0);
    DIA     : in  std_logic_vector(15 downto 0);
    DIB     : in  std_logic_vector(15 downto 0)
  );
end entity;

architecture sim of DPB is
  type ram_t is array (0 to 1023) of std_logic_vector(15 downto 0);
  shared variable ram : ram_t := (others => (others => '0'));
  signal doa_r : std_logic_vector(15 downto 0) := (others => '0');
  signal dob_r : std_logic_vector(15 downto 0) := (others => '0');

  function word_addr(addr : std_logic_vector(13 downto 0)) return natural is
  begin
    return to_integer(unsigned(addr(13 downto 4)));
  end function;
begin
  DOA <= doa_r;
  DOB <= dob_r;

  process(CLKA)
    variable a : natural;
  begin
    if rising_edge(CLKA) then
      if RESETA = '1' then
        doa_r <= (others => '0');
      elsif CEA = '1' then
        a := word_addr(ADA);
        if WREA = '1' then
          ram(a) := DIA;
        end if;
        if OCEA = '1' then
          doa_r <= ram(a);
        end if;
      end if;
    end if;
  end process;

  process(CLKB)
    variable a : natural;
  begin
    if rising_edge(CLKB) then
      if RESETB = '1' then
        dob_r <= (others => '0');
      elsif CEB = '1' then
        a := word_addr(ADB);
        if WREB = '1' then
          ram(a) := DIB;
        end if;
        if OCEB = '1' then
          dob_r <= ram(a);
        end if;
      end if;
    end if;
  end process;
end architecture;
