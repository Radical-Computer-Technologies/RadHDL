library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Simulation testbench for measuring Xilinx FFT 1024-point latency.
-- Drives representative frames through the generated FFT IP and records timing behavior for comparison with RadFFT alternatives.
entity tb_xfft_1024_latency is
end entity;

architecture sim of tb_xfft_1024_latency is
  constant C_POINTS : natural := 1024;
  signal aclk : std_logic := '0';
  signal aclken : std_logic := '1';
  signal aresetn : std_logic := '0';

  signal s_axis_config_tdata : std_logic_vector(15 downto 0) := (others => '0');
  signal s_axis_config_tvalid : std_logic := '0';
  signal s_axis_config_tready : std_logic;
  signal s_axis_data_tdata : std_logic_vector(63 downto 0) := (others => '0');
  signal s_axis_data_tvalid : std_logic := '0';
  signal s_axis_data_tready : std_logic;
  signal s_axis_data_tlast : std_logic := '0';
  signal m_axis_data_tdata : std_logic_vector(63 downto 0);
  signal m_axis_data_tvalid : std_logic;
  signal m_axis_data_tlast : std_logic;
  signal event_frame_started : std_logic;
  signal event_tlast_unexpected : std_logic;
  signal event_tlast_missing : std_logic;
  signal event_data_in_channel_halt : std_logic;

  signal done : boolean := false;
begin
  aclk <= not aclk after 5 ns;

  dut_i : entity work.radfft_xfft_1024
    port map (
      aclk => aclk,
      aclken => aclken,
      aresetn => aresetn,
      s_axis_config_tdata => s_axis_config_tdata,
      s_axis_config_tvalid => s_axis_config_tvalid,
      s_axis_config_tready => s_axis_config_tready,
      s_axis_data_tdata => s_axis_data_tdata,
      s_axis_data_tvalid => s_axis_data_tvalid,
      s_axis_data_tready => s_axis_data_tready,
      s_axis_data_tlast => s_axis_data_tlast,
      m_axis_data_tdata => m_axis_data_tdata,
      m_axis_data_tvalid => m_axis_data_tvalid,
      m_axis_data_tlast => m_axis_data_tlast,
      event_frame_started => event_frame_started,
      event_tlast_unexpected => event_tlast_unexpected,
      event_tlast_missing => event_tlast_missing,
      event_data_in_channel_halt => event_data_in_channel_halt
    );

  stim : process
    variable first_in_time : time := 0 ns;
    variable last_in_time : time := 0 ns;
  begin
    wait for 100 ns;
    wait until rising_edge(aclk);
    aresetn <= '1';

    -- bit 0 = forward transform. bits 10:1 are the scaling schedule.
    s_axis_config_tdata <= (others => '0');
    s_axis_config_tdata(0) <= '1';
    s_axis_config_tdata(10 downto 1) <= "1010101011";
    s_axis_config_tvalid <= '1';
    loop
      wait until rising_edge(aclk);
      exit when s_axis_config_tready = '1';
    end loop;
    s_axis_config_tvalid <= '0';

    for i in 0 to C_POINTS - 1 loop
      s_axis_data_tdata <= std_logic_vector(to_signed(i + 1, 32)) & std_logic_vector(to_signed(i + 1, 32));
      s_axis_data_tlast <= '1' when i = C_POINTS - 1 else '0';
      s_axis_data_tvalid <= '1';
      loop
        wait until rising_edge(aclk);
        exit when s_axis_data_tready = '1';
      end loop;
      if i = 0 then
        first_in_time := now;
        report "XFFT first input @" & time'image(first_in_time);
      elsif i = C_POINTS - 1 then
        last_in_time := now;
        report "XFFT last input @" & time'image(last_in_time);
      end if;
    end loop;
    s_axis_data_tvalid <= '0';
    s_axis_data_tlast <= '0';

    wait until done;
    report "XFFT input frame duration " & time'image(last_in_time - first_in_time);
    wait for 100 ns;
    finish;
  end process;

  monitor : process(aclk)
    variable first_out_seen : boolean := false;
    variable first_out_time : time := 0 ns;
    variable last_out_time : time := 0 ns;
    variable first_in_reference : time := 0 ns;
    variable out_count : natural := 0;
  begin
    if rising_edge(aclk) then
      if event_frame_started = '1' then
        first_in_reference := now;
        report "XFFT event_frame_started @" & time'image(now);
      end if;

      if m_axis_data_tvalid = '1' then
        if not first_out_seen then
          first_out_seen := true;
          first_out_time := now;
          report "XFFT first output @" & time'image(first_out_time);
          if first_in_reference /= 0 ns then
            report "XFFT frame-start to first-output latency " & time'image(first_out_time - first_in_reference);
          end if;
        end if;
        out_count := out_count + 1;
        if m_axis_data_tlast = '1' then
          last_out_time := now;
          report "XFFT last output @" & time'image(last_out_time);
          report "XFFT output samples " & integer'image(out_count);
          report "XFFT output frame duration " & time'image(last_out_time - first_out_time);
          done <= true;
        end if;
      end if;
    end if;
  end process;
end architecture;
