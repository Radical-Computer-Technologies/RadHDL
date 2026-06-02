# RadILA Raspberry Pi Linux Bridge

`radila_linux_bridge` exposes RadILA/RadDebugHub register access through a Raspberry Pi using common Linux bus interfaces.

Supported boards use the same userspace path:

- Raspberry Pi Zero 2 W
- Raspberry Pi 3 A+
- Raspberry Pi 3 B+
- Raspberry Pi 4
- Raspberry Pi 5

Enable SPI or I2C with `raspi-config`, then verify the device nodes exist:

```sh
ls /dev/spidev0.0 /dev/i2c-1
```

Build:

```sh
cmake -S . -B build
cmake --build build
```

Serial-style stdin/stdout bridge with UART CRC enabled:

```sh
./build/radila_linux_bridge --bus spi --device /dev/spidev0.0 --serial --crc on
```

TCP bridge without extra line CRC:

```sh
./build/radila_linux_bridge --bus spi --device /dev/spidev0.0 --tcp-port 9738 --crc off
```

I2C bridge:

```sh
./build/radila_linux_bridge --bus i2c --device /dev/i2c-1 --i2c-addr 0x42 --tcp-port 9738
```

Protocol:

- `PING`
- `R <addr> <len>`
- `W <addr> <hex-bytes>`

UART/serial mode can append `*CCCC` where `CCCC` is CRC16-CCITT over the line before the `*`. TCP mode normally omits the CRC.
