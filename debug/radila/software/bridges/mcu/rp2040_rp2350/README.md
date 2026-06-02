# RadILA RP2040/RP2350 Bridge

This bridge runs on Raspberry Pi Pico-class boards and converts host commands to RadILA/RadDebugHub SPI or I2C bus transactions.

Default mode is UART with CRC16-CCITT framing. TCP is optional for Pico W style builds where the Pico SDK cyw43/lwIP stack is configured.

Build a UART-to-SPI bridge:

```sh
cmake -S . -B build -DPICO_SDK_PATH=/path/to/pico-sdk -DRADILA_PICO_BUS=spi
cmake --build build
```

Build a UART-to-I2C bridge:

```sh
cmake -S . -B build -DPICO_SDK_PATH=/path/to/pico-sdk -DRADILA_PICO_BUS=i2c
cmake --build build
```

Enable optional TCP transport for Pico W:

```sh
cmake -S . -B build -DPICO_SDK_PATH=/path/to/pico-sdk -DRADILA_PICO_ENABLE_TCP=ON
cmake --build build
```

Protocol:

- UART requires `*CCCC` CRC suffix by default.
- TCP uses the same `PING`, `R <addr> <len>`, and `W <addr> <hex-bytes>` commands without CRC.

Default pins:

- UART: `uart0`, TX GPIO0, RX GPIO1, 115200 baud.
- SPI: `spi0`, SCK GPIO2, MOSI GPIO3, MISO GPIO4, CS GPIO5.
- I2C: `i2c0`, SDA GPIO4, SCL GPIO5, FPGA address `0x42`.
