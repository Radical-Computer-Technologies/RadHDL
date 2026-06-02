-- (c) Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- (c) Copyright 2022-2026 Advanced Micro Devices, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
-- DO NOT MODIFY THIS FILE.

-- IP VLNV: rct.local:raddsp:raddsp_fft_radix2_batch_core:1.0
-- IP Revision: 1

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY raddsp_fft_radix2_batch_core_0 IS
  PORT (
    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC;
    start_frame : IN STD_LOGIC;
    sample_valid : IN STD_LOGIC;
    sample_re : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    sample_im : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    sample_ready : OUT STD_LOGIC;
    twiddle_addr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    twiddle_re : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    twiddle_im : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    busy : OUT STD_LOGIC;
    done : OUT STD_LOGIC;
    output_valid : OUT STD_LOGIC;
    output_index : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    output_re : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    output_im : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
  );
END raddsp_fft_radix2_batch_core_0;

ARCHITECTURE raddsp_fft_radix2_batch_core_0_arch OF raddsp_fft_radix2_batch_core_0 IS
  ATTRIBUTE DowngradeIPIdentifiedWarnings : STRING;
  ATTRIBUTE DowngradeIPIdentifiedWarnings OF raddsp_fft_radix2_batch_core_0_arch: ARCHITECTURE IS "yes";
  COMPONENT raddsp_fft_radix2_batch_core IS
    GENERIC (
      VENDOR : STRING;
      DEVICE_FAMILY : STRING;
      G_POINTS : INTEGER;
      G_MAX_POINTS : INTEGER;
      G_INPUT_WIDTH : INTEGER;
      G_TWIDDLE_WIDTH : INTEGER;
      G_OUTPUT_WIDTH : INTEGER;
      G_SCALE_EACH_STAGE : BOOLEAN
    );
    PORT (
      clk : IN STD_LOGIC;
      rst : IN STD_LOGIC;
      start_frame : IN STD_LOGIC;
      sample_valid : IN STD_LOGIC;
      sample_re : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      sample_im : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      sample_ready : OUT STD_LOGIC;
      twiddle_addr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      twiddle_re : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      twiddle_im : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      busy : OUT STD_LOGIC;
      done : OUT STD_LOGIC;
      output_valid : OUT STD_LOGIC;
      output_index : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      output_re : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      output_im : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
  END COMPONENT raddsp_fft_radix2_batch_core;
  ATTRIBUTE X_INTERFACE_INFO : STRING;
  ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
  ATTRIBUTE X_INTERFACE_PARAMETER OF clk: SIGNAL IS "XIL_INTERFACENAME clk, ASSOCIATED_RESET rst, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0";
  ATTRIBUTE X_INTERFACE_INFO OF clk: SIGNAL IS "xilinx.com:signal:clock:1.0 clk CLK";
  ATTRIBUTE X_INTERFACE_PARAMETER OF rst: SIGNAL IS "XIL_INTERFACENAME rst, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  ATTRIBUTE X_INTERFACE_INFO OF rst: SIGNAL IS "xilinx.com:signal:reset:1.0 rst RST";
BEGIN
  U0 : raddsp_fft_radix2_batch_core
    GENERIC MAP (
      VENDOR => "xilinx",
      DEVICE_FAMILY => "ultrascale+",
      G_POINTS => 32,
      G_MAX_POINTS => 32,
      G_INPUT_WIDTH => 16,
      G_TWIDDLE_WIDTH => 16,
      G_OUTPUT_WIDTH => 32,
      G_SCALE_EACH_STAGE => true
    )
    PORT MAP (
      clk => clk,
      rst => rst,
      start_frame => start_frame,
      sample_valid => sample_valid,
      sample_re => sample_re,
      sample_im => sample_im,
      sample_ready => sample_ready,
      twiddle_addr => twiddle_addr,
      twiddle_re => twiddle_re,
      twiddle_im => twiddle_im,
      busy => busy,
      done => done,
      output_valid => output_valid,
      output_index => output_index,
      output_re => output_re,
      output_im => output_im
    );
END raddsp_fft_radix2_batch_core_0_arch;
