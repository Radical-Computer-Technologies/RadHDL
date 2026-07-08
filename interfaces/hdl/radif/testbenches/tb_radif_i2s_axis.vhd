library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library radif;

-- Exercises the I2S/AXI-Stream bridge in internally clocked loopback mode.
-- The waveform shows register-controlled clock dividers, generated MCLK/BCLK/LRCK, AXI input acceptance, I2S serial output, looped-back serial input, and AXI output frame generation.
entity tb_radif_i2s_axis is
end entity;

architecture sim of tb_radif_i2s_axis is
  signal clk           : std_logic := '0';
  signal rstn          : std_logic := '0';
  signal reg_wr_addr   : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_rd_addr   : std_logic_vector(15 downto 0) := (others => '0');
  signal reg_wr_en     : std_logic := '0';
  signal reg_rd_en     : std_logic := '0';
  signal reg_data_in   : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_data_out  : std_logic_vector(31 downto 0);
  signal reg_wr_rdy    : std_logic;
  signal reg_rd_rdy    : std_logic;
  signal reg_wr_valid  : std_logic;
  signal reg_rd_valid  : std_logic;
  signal reg_error     : std_logic;
  signal mclk          : std_logic;
  signal mclk_oe       : std_logic;
  signal bclk          : std_logic;
  signal bclk_oe       : std_logic;
  signal lrck          : std_logic;
  signal lrck_oe       : std_logic;
  signal sdata_o       : std_logic;
  signal sdata_i       : std_logic := '0';
  signal sdata_oe      : std_logic;
  signal m_axis_tdata  : std_logic_vector(15 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '0';
  signal m_axis_tlast  : std_logic;
  signal s_axis_tdata  : std_logic_vector(15 downto 0) := x"A55A";
  signal s_axis_tvalid : std_logic := '0';
  signal s_axis_tready : std_logic;
  signal s_axis_tlast  : std_logic := '1';
begin
  clk <= not clk after 5 ns;

  dut : entity radif.radif_i2s_axis
    generic map (
      SAMPLE_WIDTH => 8,
      AXIS_DATA_WIDTH => 16,
      DEFAULT_MCLK_DIV => 1,
      DEFAULT_BCLK_DIV => 1,
      DEFAULT_LRCK_BITS => 16
    )
    port map (
      clk => clk,
      rstn => rstn,
      reg_wr_addr => reg_wr_addr,
      reg_rd_addr => reg_rd_addr,
      reg_wr_en => reg_wr_en,
      reg_rd_en => reg_rd_en,
      reg_data_in => reg_data_in,
      reg_data_out => reg_data_out,
      reg_wr_rdy => reg_wr_rdy,
      reg_rd_rdy => reg_rd_rdy,
      reg_wr_valid => reg_wr_valid,
      reg_rd_valid => reg_rd_valid,
      reg_error => reg_error,
      i2s_mclk_i => '0',
      i2s_mclk_o => mclk,
      i2s_mclk_oe => mclk_oe,
      i2s_bclk_i => bclk,
      i2s_bclk_o => bclk,
      i2s_bclk_oe => bclk_oe,
      i2s_lrck_i => lrck,
      i2s_lrck_o => lrck,
      i2s_lrck_oe => lrck_oe,
      i2s_sdata_i => sdata_i,
      i2s_sdata_o => sdata_o,
      i2s_sdata_oe => sdata_oe,
      m_axis_tdata => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast => m_axis_tlast,
      s_axis_tdata => s_axis_tdata,
      s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      s_axis_tlast => s_axis_tlast
    );

  process
    variable left_pattern  : std_logic_vector(7 downto 0) := x"A5";
    variable right_pattern : std_logic_vector(7 downto 0) := x"5A";
    variable bit_index     : integer range 0 to 7 := 0;
  begin
    wait until rstn = '1';
    loop
      wait until rising_edge(bclk);
      if lrck = '0' then
        sdata_i <= left_pattern(7 - bit_index);
      else
        sdata_i <= right_pattern(7 - bit_index);
      end if;
      if bit_index = 7 then
        bit_index := 0;
      else
        bit_index := bit_index + 1;
      end if;
    end loop;
  end process;

  process
    procedure reg_write(addr : std_logic_vector(15 downto 0); data : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_wr_addr <= addr;
      reg_data_in <= data;
      reg_wr_en <= '1';
      wait until rising_edge(clk);
      reg_wr_en <= '0';
    end procedure;

    procedure reg_read(addr : std_logic_vector(15 downto 0)) is
    begin
      wait until rising_edge(clk);
      reg_rd_addr <= addr;
      reg_rd_en <= '1';
      wait until rising_edge(clk);
      reg_rd_en <= '0';
      wait until rising_edge(clk);
    end procedure;
  begin
    wait for 40 ns;
    rstn <= '1';
    reg_write(x"0008", x"00000001");
    reg_write(x"000C", x"00000001");
    reg_write(x"0010", x"00000010");
    reg_write(x"0000", x"00000003");

    wait until rising_edge(clk);
    s_axis_tvalid <= '1';
    while s_axis_tready = '0' loop
      wait until rising_edge(clk);
    end loop;
    wait until rising_edge(clk);
    s_axis_tvalid <= '0';

    for i in 0 to 1000 loop
      wait until rising_edge(clk);
      exit when m_axis_tvalid = '1';
    end loop;
    assert mclk_oe = '1' and bclk_oe = '1' and lrck_oe = '1' report "I2S generated clocks not enabled" severity failure;
    assert m_axis_tvalid = '1' report "I2S loopback did not emit AXI frame" severity failure;
    m_axis_tready <= '1';
    reg_read(x"0018");
    assert unsigned(reg_data_out) > 0 report "I2S transmit counter did not increment" severity failure;
    report "PASS tb_radif_i2s_axis";
    finish;
  end process;
end architecture;
