library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- RADIF-accessible debug hub for the RadILA capture engine.
-- Provides a bus-neutral register target for analyzer control, trigger setup,
-- live status, and capture-buffer readback. External RADIF bridges such as
-- AXI-Lite, SPI, I2C, and SMI can all drive this same register contract.
entity RadDebugHub is
  generic (
    -- Register data width for the RADIF register target.
    DATA_WIDTH         : integer := 32;
    -- Register byte-address width for the RADIF register target.
    REG_ADDR_WIDTH     : integer := 16;
    -- Total captured sample bus width in bits.
    SAMPLE_WIDTH       : integer := 32;
    -- Width of event/trigger metadata sampled beside each captured value.
    EVENT_WIDTH        : integer := 8;
    -- Number of samples stored in the RadILA capture RAM.
    DEPTH              : integer := 1024;
    -- Capture RAM address width.
    ADDR_WIDTH         : integer := 10;
    -- Narrow command link width between RadDebugHub and RadILA.
    CMD_LANES          : integer := 4;
    -- Vendor selector used by generate blocks for vendor-specific primitives.
    VENDOR_TAG         : string  := "XILINX";
    -- Device-family selector used by vendor primitive wrappers.
    PRODUCT_SERIES_TAG : string  := "7SERIES"
  );
  port (
    -- Sample clock for the observed logic and capture RAM write side.
    sample_clk     : in  std_logic;
    -- Active-low reset for the sample clock domain.
    sample_rstn    : in  std_logic;
    -- Input sample vector captured by the analyzer.
    sample_i       : in  std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
    -- Event or trigger metadata associated with the current sample stream.
    event_i        : in  std_logic_vector(EVENT_WIDTH - 1 downto 0);
    -- Interrupt asserted when capture completion is enabled and the core is done.
    irq_o          : out std_logic;
    -- Clock for the RADIF register interface and capture RAM read side.
    reg_clk        : in  std_logic;
    -- Active-low reset for the RADIF register interface.
    reg_rstn       : in  std_logic;
    -- Register write address.
    reg_wr_addr    : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- Register read address.
    reg_rd_addr    : in  std_logic_vector(REG_ADDR_WIDTH - 1 downto 0);
    -- One-cycle register write request.
    reg_wr_en      : in  std_logic;
    -- One-cycle register read request.
    reg_rd_en      : in  std_logic;
    -- Register write data.
    reg_data_in    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Register read data.
    reg_data_out   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Write-side ready indication.
    reg_wr_rdy     : out std_logic;
    -- Read-side ready indication.
    reg_rd_rdy     : out std_logic;
    -- Write response valid pulse.
    reg_wr_valid   : out std_logic;
    -- Read response valid pulse.
    reg_rd_valid   : out std_logic;
    -- Address or transaction error flag for the current response.
    reg_error      : out std_logic
  );
end entity;

architecture rtl of RadDebugHub is
  constant C_REG_ID          : natural := 16#00#;
  constant C_REG_VERSION     : natural := 16#04#;
  constant C_REG_CONTROL     : natural := 16#08#;
  constant C_REG_STATUS      : natural := 16#0C#;
  constant C_REG_TRIG_MASK   : natural := 16#10#;
  constant C_REG_TRIG_VALUE  : natural := 16#14#;
  constant C_REG_PRETRIG     : natural := 16#18#;
  constant C_REG_POSTTRIG    : natural := 16#1C#;
  constant C_REG_DATA_INDEX  : natural := 16#20#;
  constant C_REG_SAMPLE_DATA0: natural := 16#24#;
  constant C_REG_SAMPLE_NOW0 : natural := 16#28#;
  constant C_REG_EVENT_NOW   : natural := 16#2C#;
  constant C_REG_CAPS        : natural := 16#30#;
  constant C_REG_SAMPLE_DATA1: natural := 16#34#;
  constant C_REG_SAMPLE_DATA2: natural := 16#38#;
  constant C_REG_SAMPLE_DATA3: natural := 16#3C#;

  constant CMD_WIDTH    : integer := 4 + (2 * EVENT_WIDTH) + ADDR_WIDTH;
  constant STATUS_WIDTH : integer := 4 + ADDR_WIDTH + 1;
  constant SAMPLE_WORDS : integer := (SAMPLE_WIDTH + 31) / 32;

  type cmd_state_t is (CMD_IDLE, CMD_SEND, CMD_TOGGLE, CMD_WAIT_ACK);

  function default_posttrig(width : natural) return unsigned is
    variable value : unsigned(width - 1 downto 0) := (others => '1');
  begin
    if width >= 8 then
      return to_unsigned(255, width);
    end if;
    return value;
  end function;

  signal control     : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal trig_mask   : std_logic_vector(EVENT_WIDTH - 1 downto 0) := (others => '0');
  signal trig_value  : std_logic_vector(EVENT_WIDTH - 1 downto 0) := (others => '0');
  signal pretrig     : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal posttrig    : unsigned(ADDR_WIDTH - 1 downto 0) := default_posttrig(ADDR_WIDTH);
  signal data_index  : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');

  signal cmd_state   : cmd_state_t := CMD_IDLE;
  signal cmd_frame   : std_logic_vector(CMD_WIDTH - 1 downto 0) := (others => '0');
  signal cmd_bit     : natural range 0 to CMD_WIDTH - 1 := 0;
  signal cmd_pending : std_logic := '0';
  signal cmd_req     : std_logic_vector(2 downto 0) := (others => '0');
  signal cmd_data_reg : std_logic_vector(CMD_LANES - 1 downto 0) := (others => '0');
  signal cmd_toggle_reg : std_logic := '0';
  signal cmd_ack_reg : std_logic;
  signal cmd_ack_seen : std_logic := '0';
  signal cmd_data_sample : std_logic_vector(CMD_LANES - 1 downto 0);
  signal cmd_toggle_sample : std_logic;
  signal cmd_ack_sample : std_logic;
  signal cmd_data_meta1 : std_logic_vector(CMD_LANES - 1 downto 0) := (others => '0');
  signal cmd_data_meta2 : std_logic_vector(CMD_LANES - 1 downto 0) := (others => '0');
  signal cmd_toggle_meta1 : std_logic := '0';
  signal cmd_toggle_meta2 : std_logic := '0';
  signal cmd_ack_meta1 : std_logic := '0';
  signal cmd_ack_meta2 : std_logic := '0';

  signal sample_data : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
  signal sample_now_s : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
  signal event_now_s : std_logic_vector(EVENT_WIDTH - 1 downto 0);
  signal sample_now_reg : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
  signal event_now_reg : std_logic_vector(EVENT_WIDTH - 1 downto 0);

  signal armed_s     : std_logic;
  signal capturing_s : std_logic;
  signal done_s      : std_logic;
  signal overflow_s  : std_logic;
  signal count_s     : unsigned(ADDR_WIDTH downto 0);
  signal status_s    : std_logic_vector(STATUS_WIDTH - 1 downto 0);
  signal status_reg  : std_logic_vector(STATUS_WIDTH - 1 downto 0);
  signal status_meta1 : std_logic_vector(STATUS_WIDTH - 1 downto 0) := (others => '0');
  signal status_meta2 : std_logic_vector(STATUS_WIDTH - 1 downto 0) := (others => '0');
  signal sample_now_meta1 : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal sample_now_meta2 : std_logic_vector(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
  signal event_now_meta1 : std_logic_vector(EVENT_WIDTH - 1 downto 0) := (others => '0');
  signal event_now_meta2 : std_logic_vector(EVENT_WIDTH - 1 downto 0) := (others => '0');
  signal armed       : std_logic;
  signal capturing   : std_logic;
  signal done        : std_logic;
  signal overflow    : std_logic;
  signal count       : unsigned(ADDR_WIDTH downto 0);

  signal rd_data_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_valid_r  : std_logic := '0';
  signal rd_valid_r  : std_logic := '0';
  signal error_r     : std_logic := '0';

  function reg_index(addr : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(addr(7 downto 0)));
  end function;

  function word32(v : std_logic_vector; word : natural) return std_logic_vector is
    variable r : std_logic_vector(31 downto 0) := (others => '0');
  begin
    for i in 0 to 31 loop
      if i + (word * 32) <= v'high then
        r(i) := v(i + (word * 32));
      end if;
    end loop;
    return r;
  end function;

  function pad_word(v : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  begin
    if DATA_WIDTH >= 32 then
      r(31 downto 0) := v;
    else
      r := v(DATA_WIDTH - 1 downto 0);
    end if;
    return r;
  end function;

  function make_cmd(
    arm_req       : std_logic;
    clear_req     : std_logic;
    sw_req        : std_logic;
    auto_rearm    : std_logic;
    mask_v        : std_logic_vector(EVENT_WIDTH - 1 downto 0);
    value_v       : std_logic_vector(EVENT_WIDTH - 1 downto 0);
    post_v        : unsigned(ADDR_WIDTH - 1 downto 0)
  ) return std_logic_vector is
    variable frame : std_logic_vector(CMD_WIDTH - 1 downto 0) := (others => '0');
  begin
    frame(0) := arm_req;
    frame(1) := clear_req;
    frame(2) := sw_req;
    frame(3) := auto_rearm;
    frame(3 + EVENT_WIDTH downto 4) := mask_v;
    frame(3 + (2 * EVENT_WIDTH) downto 4 + EVENT_WIDTH) := value_v;
    frame(CMD_WIDTH - 1 downto 4 + (2 * EVENT_WIDTH)) := std_logic_vector(post_v);
    return frame;
  end function;
begin
  reg_wr_rdy <= '1';
  reg_rd_rdy <= '1';
  reg_wr_valid <= wr_valid_r;
  reg_rd_valid <= rd_valid_r;
  reg_error <= error_r;
  reg_data_out <= rd_data_r;
  irq_o <= done and control(4);

  status_s <= std_logic_vector(count_s) & overflow_s & done_s & capturing_s & armed_s;
  count <= unsigned(status_reg(STATUS_WIDTH - 1 downto 4));
  overflow <= status_reg(3);
  done <= status_reg(2);
  capturing <= status_reg(1);
  armed <= status_reg(0);

  process(sample_clk)
  begin
    if rising_edge(sample_clk) then
      cmd_data_meta1 <= cmd_data_reg;
      cmd_data_meta2 <= cmd_data_meta1;
      cmd_data_sample <= cmd_data_meta2;
      cmd_toggle_meta1 <= cmd_toggle_reg;
      cmd_toggle_meta2 <= cmd_toggle_meta1;
      cmd_toggle_sample <= cmd_toggle_meta2;
    end if;
  end process;

  process(reg_clk)
  begin
    if rising_edge(reg_clk) then
      cmd_ack_meta1 <= cmd_ack_sample;
      cmd_ack_meta2 <= cmd_ack_meta1;
      cmd_ack_reg <= cmd_ack_meta2;
      status_meta1 <= status_s;
      status_meta2 <= status_meta1;
      status_reg <= status_meta2;
      sample_now_meta1 <= sample_now_s;
      sample_now_meta2 <= sample_now_meta1;
      sample_now_reg <= sample_now_meta2;
      event_now_meta1 <= event_now_s;
      event_now_meta2 <= event_now_meta1;
      event_now_reg <= event_now_meta2;
    end if;
  end process;

  u_radila : entity work.RadILA
    generic map (
      SAMPLE_WIDTH       => SAMPLE_WIDTH,
      EVENT_WIDTH        => EVENT_WIDTH,
      DEPTH              => DEPTH,
      ADDR_WIDTH         => ADDR_WIDTH,
      CMD_LANES          => CMD_LANES,
      VENDOR_TAG         => VENDOR_TAG,
      PRODUCT_SERIES_TAG => PRODUCT_SERIES_TAG
    )
    port map (
      sample_clk       => sample_clk,
      sample_rstn      => sample_rstn,
      axi_clk          => reg_clk,
      axi_rstn         => reg_rstn,
      sample_i         => sample_i,
      event_i          => event_i,
      cmd_data_i       => cmd_data_sample,
      cmd_toggle_i     => cmd_toggle_sample,
      cmd_ack_toggle_o => cmd_ack_sample,
      rd_index_i       => data_index,
      rd_data_o        => sample_data,
      sample_now_o     => sample_now_s,
      event_now_o      => event_now_s,
      armed_o          => armed_s,
      capturing_o      => capturing_s,
      done_o           => done_s,
      overflow_o       => overflow_s,
      count_o          => count_s
    );

  process(reg_clk)
    variable next_control : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable next_mask    : std_logic_vector(EVENT_WIDTH - 1 downto 0);
    variable next_value   : std_logic_vector(EVENT_WIDTH - 1 downto 0);
    variable next_post    : unsigned(ADDR_WIDTH - 1 downto 0);
    variable next_req     : std_logic_vector(2 downto 0);
    variable next_cmd_data : std_logic_vector(CMD_LANES - 1 downto 0);
    variable bit_index     : natural;
    variable idx           : natural;
  begin
    if rising_edge(reg_clk) then
      wr_valid_r <= '0';
      rd_valid_r <= '0';
      error_r <= '0';

      if reg_rstn = '0' then
        control <= (others => '0');
        trig_mask <= (others => '0');
        trig_value <= (others => '0');
        pretrig <= (others => '0');
        posttrig <= default_posttrig(ADDR_WIDTH);
        data_index <= (others => '0');
        cmd_state <= CMD_IDLE;
        cmd_frame <= (others => '0');
        cmd_bit <= 0;
        cmd_pending <= '0';
        cmd_req <= (others => '0');
        cmd_data_reg <= (others => '0');
        cmd_toggle_reg <= '0';
        cmd_ack_seen <= cmd_ack_reg;
        rd_data_r <= (others => '0');
      else
        next_control := control;
        next_mask := trig_mask;
        next_value := trig_value;
        next_post := posttrig;
        next_req := cmd_req;

        if cmd_state = CMD_IDLE and cmd_pending = '1' then
          cmd_frame <= make_cmd(cmd_req(0), cmd_req(1), cmd_req(2),
                                control(3), trig_mask, trig_value, posttrig);
          next_req := (others => '0');
          cmd_pending <= '0';
          cmd_bit <= 0;
          cmd_state <= CMD_SEND;
        elsif cmd_state = CMD_SEND then
          next_cmd_data := (others => '0');
          for lane in 0 to CMD_LANES - 1 loop
            bit_index := cmd_bit + lane;
            if bit_index < CMD_WIDTH then
              next_cmd_data(lane) := cmd_frame(bit_index);
            end if;
          end loop;
          cmd_data_reg <= next_cmd_data;
          cmd_state <= CMD_TOGGLE;
        elsif cmd_state = CMD_TOGGLE then
          cmd_toggle_reg <= not cmd_toggle_reg;
          cmd_state <= CMD_WAIT_ACK;
        elsif cmd_state = CMD_WAIT_ACK then
          if cmd_ack_reg /= cmd_ack_seen then
            cmd_ack_seen <= cmd_ack_reg;
            if cmd_bit + CMD_LANES >= CMD_WIDTH then
              cmd_state <= CMD_IDLE;
            else
              cmd_bit <= cmd_bit + CMD_LANES;
              cmd_state <= CMD_SEND;
            end if;
          end if;
        end if;

        if reg_wr_en = '1' then
          wr_valid_r <= '1';
          idx := reg_index(reg_wr_addr);
          case idx is
            when C_REG_CONTROL =>
              next_control := reg_data_in;
              if reg_data_in(0) = '1' then
                next_req(0) := '1';
              end if;
              if reg_data_in(1) = '1' then
                next_req(2) := '1';
              end if;
              if reg_data_in(2) = '1' then
                next_req(1) := '1';
              end if;
              cmd_pending <= '1';
            when C_REG_TRIG_MASK =>
              next_mask := reg_data_in(EVENT_WIDTH - 1 downto 0);
              cmd_pending <= '1';
            when C_REG_TRIG_VALUE =>
              next_value := reg_data_in(EVENT_WIDTH - 1 downto 0);
              cmd_pending <= '1';
            when C_REG_PRETRIG =>
              pretrig <= unsigned(reg_data_in(ADDR_WIDTH - 1 downto 0));
            when C_REG_POSTTRIG =>
              next_post := unsigned(reg_data_in(ADDR_WIDTH - 1 downto 0));
              cmd_pending <= '1';
            when C_REG_DATA_INDEX =>
              data_index <= unsigned(reg_data_in(ADDR_WIDTH - 1 downto 0));
            when others =>
              error_r <= '1';
          end case;
        end if;

        if reg_rd_en = '1' then
          rd_valid_r <= '1';
          idx := reg_index(reg_rd_addr);
          case idx is
            when C_REG_ID =>
              rd_data_r <= pad_word(x"52414449");
            when C_REG_VERSION =>
              rd_data_r <= pad_word(x"00020800");
            when C_REG_CONTROL =>
              rd_data_r <= control;
            when C_REG_STATUS =>
              rd_data_r <= pad_word(std_logic_vector(resize(count, 16)) & x"000" & overflow & done & capturing & armed);
            when C_REG_TRIG_MASK =>
              rd_data_r <= (others => '0');
              rd_data_r(EVENT_WIDTH - 1 downto 0) <= trig_mask;
            when C_REG_TRIG_VALUE =>
              rd_data_r <= (others => '0');
              rd_data_r(EVENT_WIDTH - 1 downto 0) <= trig_value;
            when C_REG_PRETRIG =>
              rd_data_r <= (others => '0');
              rd_data_r(ADDR_WIDTH - 1 downto 0) <= std_logic_vector(pretrig);
            when C_REG_POSTTRIG =>
              rd_data_r <= (others => '0');
              rd_data_r(ADDR_WIDTH - 1 downto 0) <= std_logic_vector(posttrig);
            when C_REG_DATA_INDEX =>
              rd_data_r <= (others => '0');
              rd_data_r(ADDR_WIDTH - 1 downto 0) <= std_logic_vector(data_index);
            when C_REG_SAMPLE_DATA0 =>
              rd_data_r <= pad_word(word32(sample_data, 0));
            when C_REG_SAMPLE_NOW0 =>
              rd_data_r <= pad_word(word32(sample_now_reg, 0));
            when C_REG_EVENT_NOW =>
              rd_data_r <= (others => '0');
              rd_data_r(EVENT_WIDTH - 1 downto 0) <= event_now_reg;
            when C_REG_CAPS =>
              rd_data_r <= pad_word(std_logic_vector(to_unsigned(SAMPLE_WIDTH, 16)) &
                                    std_logic_vector(to_unsigned(EVENT_WIDTH, 16)));
            when C_REG_SAMPLE_DATA1 =>
              if SAMPLE_WORDS > 1 then
                rd_data_r <= pad_word(word32(sample_data, 1));
              else
                rd_data_r <= (others => '0');
              end if;
            when C_REG_SAMPLE_DATA2 =>
              if SAMPLE_WORDS > 2 then
                rd_data_r <= pad_word(word32(sample_data, 2));
              else
                rd_data_r <= (others => '0');
              end if;
            when C_REG_SAMPLE_DATA3 =>
              if SAMPLE_WORDS > 3 then
                rd_data_r <= pad_word(word32(sample_data, 3));
              else
                rd_data_r <= (others => '0');
              end if;
            when others =>
              rd_data_r <= (others => '0');
              error_r <= '1';
          end case;
        end if;

        control <= next_control;
        trig_mask <= next_mask;
        trig_value <= next_value;
        posttrig <= next_post;
        cmd_req <= next_req;
      end if;
    end if;
  end process;
end architecture;
