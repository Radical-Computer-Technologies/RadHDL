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
-- IP VLNV: rct.local:raddsp:raddsp_zc_chirp_frame_detector:1.0
-- IP Revision: 1

-- The following code must appear in the VHDL architecture header.

------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT raddsp_zc_chirp_frame_detector_0
  PORT (
    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC;
    frame_start : IN STD_LOGIC;
    sample_valid : IN STD_LOGIC;
    sample_i : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    sample_q : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    sample_ready : OUT STD_LOGIC;
    processing : OUT STD_LOGIC;
    peak_valid : OUT STD_LOGIC;
    peak_index : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    peak_i : OUT STD_LOGIC_VECTOR(39 DOWNTO 0);
    peak_q : OUT STD_LOGIC_VECTOR(39 DOWNTO 0);
    chirp_valid : OUT STD_LOGIC;
    chirp_index : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    chirp_i : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    chirp_q : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    chirp_done : OUT STD_LOGIC 
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
your_instance_name : raddsp_zc_chirp_frame_detector_0
  PORT MAP (
    clk => clk,
    rst => rst,
    frame_start => frame_start,
    sample_valid => sample_valid,
    sample_i => sample_i,
    sample_q => sample_q,
    sample_ready => sample_ready,
    processing => processing,
    peak_valid => peak_valid,
    peak_index => peak_index,
    peak_i => peak_i,
    peak_q => peak_q,
    chirp_valid => chirp_valid,
    chirp_index => chirp_index,
    chirp_i => chirp_i,
    chirp_q => chirp_q,
    chirp_done => chirp_done
  );
-- INST_TAG_END ------ End INSTANTIATION Template ---------

-- You must compile the wrapper file raddsp_zc_chirp_frame_detector_0.vhd when simulating
-- the core, raddsp_zc_chirp_frame_detector_0. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.



