library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

library raddsp;

-- Verifies the AM IQ modulator and demodulator as independent blocks and as a loop.
entity tb_raddsp_axis_am_iq is
end entity;

architecture sim of tb_raddsp_axis_am_iq is
  constant C_WIDTH : positive := 16;
  constant C_FRAC  : natural := 14;
  constant C_ONE   : integer := 2 ** C_FRAC;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal carrier_i : std_logic_vector(C_WIDTH - 1 downto 0) := std_logic_vector(to_signed(C_ONE, C_WIDTH));
  signal carrier_q : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal in_data  : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal in_last  : std_logic := '0';
  signal iq_valid : std_logic;
  signal iq_ready : std_logic := '1';
  signal iq_data  : std_logic_vector((2 * C_WIDTH) - 1 downto 0);
  signal iq_last  : std_logic;
  signal env_valid : std_logic;
  signal env_ready : std_logic := '1';
  signal env_data  : std_logic_vector(C_WIDTH - 1 downto 0);
  signal env_last  : std_logic;
begin
  clk <= not clk after 5 ns;

  u_mod : entity raddsp.raddsp_axis_am_iq_modulator
    generic map (
      SAMPLE_WIDTH => C_WIDTH,
      FRAC_BITS => C_FRAC,
      VENDOR => "GENERIC"
    )
    port map (
      clk => clk,
      rst => rst,
      carrier_i_i => carrier_i,
      carrier_q_i => carrier_q,
      s_axis_tvalid => in_valid,
      s_axis_tready => in_ready,
      s_axis_tdata => in_data,
      s_axis_tlast => in_last,
      m_axis_tvalid => iq_valid,
      m_axis_tready => iq_ready,
      m_axis_tdata => iq_data,
      m_axis_tlast => iq_last
    );

  u_demod : entity raddsp.raddsp_axis_am_iq_demodulator
    generic map (
      SAMPLE_WIDTH => C_WIDTH,
      VENDOR => "GENERIC"
    )
    port map (
      clk => clk,
      rst => rst,
      s_axis_tvalid => iq_valid,
      s_axis_tready => open,
      s_axis_tdata => iq_data,
      s_axis_tlast => iq_last,
      m_axis_tvalid => env_valid,
      m_axis_tready => env_ready,
      m_axis_tdata => env_data,
      m_axis_tlast => env_last
    );

  stim : process
    type sample_array_t is array (natural range <>) of integer;
    constant samples : sample_array_t := (4096, 8192, 12000, 16384);
    variable expected : integer;
    variable observed : integer;
  begin
    wait for 100 ns;
    rst <= '0';
    wait until rising_edge(clk);

    for i in samples'range loop
      wait until rising_edge(clk);
      in_data <= std_logic_vector(to_signed(samples(i), C_WIDTH));
      if i = samples'high then
        in_last <= '1';
      else
        in_last <= '0';
      end if;
      in_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when in_ready = '1';
      end loop;
      in_valid <= '0';
      in_last <= '0';
      loop
        wait until rising_edge(clk);
        exit when env_valid = '1';
      end loop;
      expected := samples(i);
      observed := to_integer(unsigned(env_data));
      assert abs(observed - expected) <= 1
        report "AM IQ demodulated envelope mismatch"
        severity failure;
      if i = samples'high then
        assert env_last = '1' report "AM IQ tlast was not preserved" severity failure;
      end if;
    end loop;

    report "tb_raddsp_axis_am_iq passed" severity note;
    finish;
  end process;
end architecture;
