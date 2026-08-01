# Colorlight i9 RADIF SPI Smoke

This project is the first RadHDL open-source ECP5 bringup target for the Colorlight i9 v7.2. It builds a small RADIF SPI register endpoint with a scratch/control register path and drives board LED D2 from a writable control bit.

The project intentionally targets simulation plus bitstream generation first. Programming is represented in metadata as `colorlight-i9`, but flashing hardware is a follow-up step.

## Build

```sh
cd /media/jvincent/Kingspec512/repos/RadHDL/projects/colorlight_i9_radif_spi_smoke
/media/jvincent/Kingspec512/repos/RadBuild/radbuild/.tools/v0.2.1/radbuild.py project validate
/media/jvincent/Kingspec512/repos/RadBuild/radbuild/.tools/v0.2.1/radbuild.py build fpga --system colorlight-i9-radif-spi
```

Artifacts are written to `.radmeta/ecp5/colorlight-i9-radif-spi/`.

## Board Pins

- `clk_25m_i`: P3, onboard 25 MHz oscillator.
- `led_o`: L2, board LED D2.
- `spi_cs_n_i`, `spi_sclk_i`, `spi_mosi_i`, `spi_miso_o`: SODIMM/extension pins selected for host SPI bringup.
