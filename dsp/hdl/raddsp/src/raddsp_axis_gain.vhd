library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library raddsp;
use raddsp.raddsp_axis_pkg.all;

-- Multi-channel AXI-stream fixed-point gain stage.
-- Multiplies each sample lane by an independent programmable coefficient, scales by fractional bits, saturates, and forwards frame metadata.
entity raddsp_axis_gain is
  generic (
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR          : string  := "xilinx";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    DEVICE_FAMILY   : string  := "generic";
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH      : positive := 16;
    -- Sets the bit width for COEFF WIDTH values carried by this module.
    COEFF_WIDTH     : positive := 18;
    -- Sets coefficient precision or coefficient count for the fixed-point DSP operation.
    COEFF_FRAC_BITS : natural  := 15;
    -- Sets the number of parallel sample lanes processed per handshake beat.
    CHANNEL_COUNT   : positive := 1
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk           : in  std_logic;
    -- Active-high synchronous reset for this clock domain.
    rst           : in  std_logic;
    -- Packed fixed-point gain coefficient input, one coefficient per channel.
    gain_i        : in  std_logic_vector((CHANNEL_COUNT * COEFF_WIDTH) - 1 downto 0);
    -- Input AXI-stream valid qualifier for the current sample beat.
    s_axis_tvalid : in  std_logic;
    -- Input AXI-stream ready response indicating this block can accept a beat.
    s_axis_tready : out std_logic;
    -- Input AXI-stream payload containing packed sample or feature lanes.
    s_axis_tdata  : in  std_logic_vector((CHANNEL_COUNT * DATA_WIDTH) - 1 downto 0);
    -- Input AXI-stream frame marker for the final beat of a frame.
    s_axis_tlast  : in  std_logic;
    -- Output AXI-stream valid qualifier for the current result beat.
    m_axis_tvalid : out std_logic;
    -- Output AXI-stream ready input from the downstream block.
    m_axis_tready : in  std_logic;
    -- Output AXI-stream payload containing packed processed result lanes.
    m_axis_tdata  : out std_logic_vector((CHANNEL_COUNT * DATA_WIDTH) - 1 downto 0);
    -- Output AXI-stream frame marker aligned with the processed result beat.
    m_axis_tlast  : out std_logic
  );
end entity;

architecture rtl of raddsp_axis_gain is
  type sample_array_t is array (natural range <>) of signed(DATA_WIDTH - 1 downto 0);
  type coeff_array_t is array (natural range <>) of signed(COEFF_WIDTH - 1 downto 0);
  type product_array_t is array (natural range <>) of signed(47 downto 0);

  function sample_at(data : std_logic_vector; index : natural) return signed is
    variable value : signed(DATA_WIDTH - 1 downto 0);
    variable lo    : natural;
  begin
    lo := index * DATA_WIDTH;
    value := signed(data(lo + DATA_WIDTH - 1 downto lo));
    return value;
  end function;

  function coeff_at(data : std_logic_vector; index : natural) return signed is
    variable value : signed(COEFF_WIDTH - 1 downto 0);
    variable lo    : natural;
  begin
    lo := index * COEFF_WIDTH;
    value := signed(data(lo + COEFF_WIDTH - 1 downto lo));
    return value;
  end function;
begin
  assert COEFF_FRAC_BITS < DATA_WIDTH + COEFF_WIDTH
    report "COEFF_FRAC_BITS is too large"
    severity failure;

  gen_xilinx_vendor : if VENDOR = "xilinx" or VENDOR = "XILINX" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector((CHANNEL_COUNT * DATA_WIDTH) - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal busy_r      : std_logic := '0';
    signal ready_i     : std_logic;
    signal mul_valid   : std_logic_vector(0 to CHANNEL_COUNT - 1) := (others => '0');
    signal mul_last    : std_logic_vector(0 to CHANNEL_COUNT - 1) := (others => '0');
    signal mul_a       : sample_array_t(0 to CHANNEL_COUNT - 1) := (others => (others => '0'));
    signal mul_b       : coeff_array_t(0 to CHANNEL_COUNT - 1) := (others => (others => '0'));
    signal mul_p       : product_array_t(0 to CHANNEL_COUNT - 1);
    signal mul_p_valid : std_logic_vector(0 to CHANNEL_COUNT - 1);
    signal mul_p_last  : std_logic_vector(0 to CHANNEL_COUNT - 1);
    signal unused_sub  : std_logic_vector(0 to CHANNEL_COUNT - 1);
  begin
    assert DATA_WIDTH <= 25
      report "DSP48 gain direct multiplier supports DATA_WIDTH <= 25"
      severity failure;
    assert COEFF_WIDTH <= 18
      report "DSP48 gain direct multiplier supports COEFF_WIDTH <= 18"
      severity failure;

    ready_i <= '1' when busy_r = '0' and (out_valid_r = '0' or m_axis_tready = '1') else '0';
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    gen_mul_lanes : for channel in 0 to CHANNEL_COUNT - 1 generate
    begin
      dsp_mul_i: entity raddsp.raddsp_xilinx_dsp48_mul
        generic map (
          DEVICE_FAMILY => DEVICE_FAMILY,
          A_WIDTH => DATA_WIDTH,
          B_WIDTH => COEFF_WIDTH
        )
        port map (
          clk => clk,
          rst => rst,
          valid_i => mul_valid(channel),
          subtract_i => '0',
          last_i => mul_last(channel),
          a_i => mul_a(channel),
          b_i => mul_b(channel),
          valid_o => mul_p_valid(channel),
          subtract_o => unused_sub(channel),
          last_o => mul_p_last(channel),
          p_o => mul_p(channel)
        );
    end generate;

    process(clk)
      variable scaled_v : signed(47 downto 0);
      variable out_v    : std_logic_vector((CHANNEL_COUNT * DATA_WIDTH) - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
          busy_r <= '0';
          mul_valid <= (others => '0');
          mul_last <= (others => '0');
          mul_a <= (others => (others => '0'));
          mul_b <= (others => (others => '0'));
        else
          mul_valid <= (others => '0');
          mul_last <= (others => '0');

          if out_valid_r = '1' and m_axis_tready = '1' then
            out_valid_r <= '0';
          end if;

          if mul_p_valid(0) = '1' then
            out_v := (others => '0');
            for channel in 0 to CHANNEL_COUNT - 1 loop
              scaled_v := shift_right(mul_p(channel), COEFF_FRAC_BITS);
              out_v(((channel + 1) * DATA_WIDTH) - 1 downto channel * DATA_WIDTH) :=
                std_logic_vector(raddsp_sat_signed_vec(scaled_v, DATA_WIDTH));
            end loop;
            out_data_r <= out_v;
            out_last_r <= mul_p_last(0);
            out_valid_r <= '1';
            busy_r <= '0';
          end if;

          if s_axis_tvalid = '1' and ready_i = '1' then
            for channel in 0 to CHANNEL_COUNT - 1 loop
              mul_a(channel) <= sample_at(s_axis_tdata, channel);
              mul_b(channel) <= coeff_at(gain_i, channel);
              mul_valid(channel) <= '1';
              mul_last(channel) <= s_axis_tlast;
            end loop;
            busy_r <= '1';
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_generic_vendor : if VENDOR /= "xilinx" and VENDOR /= "XILINX" generate
    signal out_valid_r : std_logic := '0';
    signal out_data_r  : std_logic_vector((CHANNEL_COUNT * DATA_WIDTH) - 1 downto 0) := (others => '0');
    signal out_last_r  : std_logic := '0';
    signal ready_i     : std_logic;
  begin
    ready_i <= (not out_valid_r) or m_axis_tready;
    s_axis_tready <= ready_i;
    m_axis_tvalid <= out_valid_r;
    m_axis_tdata <= out_data_r;
    m_axis_tlast <= out_last_r;

    process(clk)
      variable product : signed(DATA_WIDTH + COEFF_WIDTH - 1 downto 0);
      variable scaled  : signed(DATA_WIDTH + COEFF_WIDTH - 1 downto 0);
      variable out_v   : std_logic_vector((CHANNEL_COUNT * DATA_WIDTH) - 1 downto 0);
    begin
      if rising_edge(clk) then
        if rst = '1' then
          out_valid_r <= '0';
          out_data_r <= (others => '0');
          out_last_r <= '0';
        elsif ready_i = '1' then
          out_valid_r <= s_axis_tvalid;
          out_last_r <= s_axis_tlast;
          if s_axis_tvalid = '1' then
            out_v := (others => '0');
            for channel in 0 to CHANNEL_COUNT - 1 loop
              product := sample_at(s_axis_tdata, channel) * coeff_at(gain_i, channel);
              scaled := shift_right(product, COEFF_FRAC_BITS);
              out_v(((channel + 1) * DATA_WIDTH) - 1 downto channel * DATA_WIDTH) :=
                std_logic_vector(raddsp_sat_signed(to_integer(scaled), DATA_WIDTH));
            end loop;
            out_data_r <= out_v;
          end if;
        end if;
      end if;
    end process;
  end generate;
end architecture;
