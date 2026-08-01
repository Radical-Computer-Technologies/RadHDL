// Complete project-local timing constraints for the RadHDL FPiGA audio-hat example.

create_clock -name BOARD_50M -period 20.000 -waveform {0 10.000} [get_nets {CLK_50M}]

// External codec bit clock from the SSM2603 path, matching the original board SDC.
create_clock -name CODEC_BCK -period 310.366 -waveform {0 155.183} [get_nets {I2S_BCK}]

// Explicitly name the PLL output domains so CDC exceptions can refer to stable
// SDC clock names instead of Gowin's generated report-only names. The PLLA
// fractional divider is ODIV0_SEL=81 and ODIV0_FRAC_SEL=3, so the intended
// audio clock is 1000 MHz / 81.375 = 12.288786 MHz.
create_clock -name AUDIO_MCLK -period 81.375 -waveform {0 40.6875} [get_pins {u_pll/CLKOUT0}]
create_clock -name FABRIC_100M -period 10.000 -waveform {0 5.000} [get_pins {u_pll/CLKOUT2}]

// The PLL audio MCLK domain and the 100 MHz fabric domain communicate through
// explicit toggle synchronizers with stable frame buses. They are not a
// cycle-related synchronous timing pair.
set_clock_groups -asynchronous -group [get_clocks {AUDIO_MCLK}] -group [get_clocks {FABRIC_100M}]

// I2S_BCK_RPI is a generated output driven by the 100 MHz fabric domain, not an
// internal clock domain. Do not create a base clock on the output net; that makes
// Gowin report false hold paths from the BCLK output back into its fabric divider.
