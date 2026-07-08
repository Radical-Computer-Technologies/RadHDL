library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI4-Lite slave bridge to the RadIF register transaction interface.
-- Turns AXI read/write handshakes into one-cycle register request pulses and returns ready/valid responses to the bus.
entity radif_axi_lite_to_reg is
  generic (
    -- Sets the bit width for DATA WIDTH values carried by this module.
    DATA_WIDTH         : integer := 32;
    -- Sets the bit width for ADDR WIDTH values carried by this module.
    ADDR_WIDTH         : integer := 16;
    -- Sets the bit width for AXI ADDR WIDTH values carried by this module.
    AXI_ADDR_WIDTH     : integer := 16;
    -- Selects the vendor-specific implementation path, usually XILINX for DSP48/XPM-backed builds or generic for portable RTL.
    VENDOR_TAG         : string  := "XILINX";
    -- Identifies the target FPGA family so wrappers can choose the correct primitive or conservative portable behavior.
    PRODUCT_SERIES_TAG : string  := "GENERIC"
  );
  port (
    -- Clock for the associated synchronous logic and handshake domain.
    clk          : in  std_logic;
    -- Active-low reset for this clock domain.
    rstn         : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awaddr : in  std_logic_vector(AXI_ADDR_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awprot : in  std_logic_vector(2 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awvalid: in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_awready: out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wdata  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wstrb  : in  std_logic_vector((DATA_WIDTH / 8) - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wvalid : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_wready : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bresp  : out std_logic_vector(1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bvalid : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_bready : in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_araddr : in  std_logic_vector(AXI_ADDR_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arprot : in  std_logic_vector(2 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arvalid: in  std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_arready: out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rdata  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rresp  : out std_logic_vector(1 downto 0);
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rvalid : out std_logic;
    -- AXI4-Lite slave-channel signal used for host register access.
    s_axi_rready : in  std_logic;
    -- Register write address issued to the internal RadIF register target.
    reg_wr_addr  : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- Register read address issued to the internal RadIF register target.
    reg_rd_addr  : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    -- One-cycle write request pulse for the internal register target.
    reg_wr_en    : out std_logic;
    -- One-cycle read request pulse for the internal register target.
    reg_rd_en    : out std_logic;
    -- Write data presented to the internal register target.
    reg_data_in  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Read data returned by the internal register target.
    reg_data_out : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Write-side ready indication from the internal register target.
    reg_wr_rdy   : in  std_logic;
    -- Read-side ready indication from the internal register target.
    reg_rd_rdy   : in  std_logic;
    -- Write response valid indication from the internal register target.
    reg_wr_valid : in  std_logic;
    -- Read response valid indication from the internal register target.
    reg_rd_valid : in  std_logic;
    -- Register target error flag converted into the external bus error response.
    reg_error    : in  std_logic
  );
end entity;

architecture rtl of radif_axi_lite_to_reg is
  type wr_state_t is (WR_IDLE, WR_WAIT);
  type rd_state_t is (RD_IDLE, RD_WAIT, RD_RESP);

  signal wr_state : wr_state_t := WR_IDLE;
  signal rd_state : rd_state_t := RD_IDLE;
  signal awready_r : std_logic := '0';
  signal wready_r  : std_logic := '0';
  signal bvalid_r  : std_logic := '0';
  signal arready_r : std_logic := '0';
  signal rvalid_r  : std_logic := '0';
  signal bresp_r   : std_logic_vector(1 downto 0) := "00";
  signal rresp_r   : std_logic_vector(1 downto 0) := "00";
  signal rdata_r   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal reg_wr_addr_r : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal reg_rd_addr_r : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal reg_wdata_r : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal wr_pulse : std_logic := '0';
  signal rd_pulse : std_logic := '0';

  function resize_addr(a : std_logic_vector) return std_logic_vector is
    variable outv : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
  begin
    if a'length >= ADDR_WIDTH then
      outv := a(ADDR_WIDTH - 1 downto 0);
    else
      outv(a'length - 1 downto 0) := a;
    end if;
    return outv;
  end function;
begin
  s_axi_awready <= awready_r;
  s_axi_wready <= wready_r;
  s_axi_bvalid <= bvalid_r;
  s_axi_bresp <= bresp_r;
  s_axi_arready <= arready_r;
  s_axi_rvalid <= rvalid_r;
  s_axi_rresp <= rresp_r;
  s_axi_rdata <= rdata_r;
  reg_wr_addr <= reg_wr_addr_r;
  reg_rd_addr <= reg_rd_addr_r;
  reg_data_in <= reg_wdata_r;
  reg_wr_en <= wr_pulse;
  reg_rd_en <= rd_pulse;

  gen_xilinx_vendor : if VENDOR_TAG = "XILINX" generate
  begin
  end generate;

  gen_generic_vendor : if VENDOR_TAG /= "XILINX" generate
  begin
  end generate;

  process(clk)
  begin
    if rising_edge(clk) then
      awready_r <= '0';
      wready_r <= '0';
      arready_r <= '0';
      wr_pulse <= '0';
      rd_pulse <= '0';

      if rstn = '0' then
        wr_state <= WR_IDLE;
        rd_state <= RD_IDLE;
        bvalid_r <= '0';
        rvalid_r <= '0';
        bresp_r <= "00";
        rresp_r <= "00";
        rdata_r <= (others => '0');
      else
        case wr_state is
          when WR_IDLE =>
            if bvalid_r = '1' and s_axi_bready = '1' then
              bvalid_r <= '0';
            end if;
            if bvalid_r = '0' and s_axi_awvalid = '1' and s_axi_wvalid = '1' and reg_wr_rdy = '1' then
              awready_r <= '1';
              wready_r <= '1';
              reg_wr_addr_r <= resize_addr(s_axi_awaddr);
              reg_wdata_r <= s_axi_wdata;
              wr_pulse <= '1';
              wr_state <= WR_WAIT;
            end if;

          when WR_WAIT =>
            if reg_wr_valid = '1' then
              bvalid_r <= '1';
              if reg_error = '1' then
                bresp_r <= "10";
              else
                bresp_r <= "00";
              end if;
              wr_state <= WR_IDLE;
            end if;
        end case;

        case rd_state is
          when RD_IDLE =>
            if s_axi_arvalid = '1' and reg_rd_rdy = '1' and rvalid_r = '0' and wr_state = WR_IDLE then
              arready_r <= '1';
              reg_rd_addr_r <= resize_addr(s_axi_araddr);
              rd_pulse <= '1';
              rd_state <= RD_WAIT;
            end if;

          when RD_WAIT =>
            if reg_rd_valid = '1' then
              rdata_r <= reg_data_out;
              if reg_error = '1' then
                rresp_r <= "10";
              else
                rresp_r <= "00";
              end if;
              rvalid_r <= '1';
              rd_state <= RD_RESP;
            end if;

          when RD_RESP =>
            if s_axi_rready = '1' then
              rvalid_r <= '0';
              rd_state <= RD_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
