# RadILA Bridge Interfaces

This tree contains bus bridge sources for RadILA/RadDebugHub. The bridges expose one host-facing command protocol and translate it to the hardware-facing SPI or I2C bus.

Host commands:

- `PING`
- `R <addr> <len>`
- `W <addr> <hex-bytes>`

UART/serial links may append `*CCCC`, where `CCCC` is CRC16-CCITT over the command before the `*`. CRC is intended for serial/UART use only. TCP mode normally omits it because TCP already protects the byte stream.

Targets:

- `mcu/rp2040_rp2350`: Raspberry Pi Pico/RP2040 and RP2350 UART bridge, with optional Pico W TCP mode.
- `linux`: Raspberry Pi Linux bridge using `/dev/spidev*` or `/dev/i2c-*`, with stdin/stdout or TCP transport.
