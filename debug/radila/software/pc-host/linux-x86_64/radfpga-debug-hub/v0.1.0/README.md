# RadFPGA Debug Hub Linux Installer

This directory contains the Linux x86_64 installer payload for RadFPGA Debug Hub.

## Install

Install for the current user:

```sh
./install.sh --prefix "$HOME/.local/opt/radfpga-debug-hub" --bindir "$HOME/.local/bin"
```

Install system-wide:

```sh
sudo ./install.sh --prefix /opt/radtools/radfpga-debug-hub --bindir /usr/local/bin
```

## Dependencies

On Ubuntu 22.04:

```sh
sudo apt-get update
sudo apt-get install -y libqt5widgets5 libqt5network5 libqt5serialport5
```

The payload is built against system Qt5 and does not bundle Qt libraries.

## Programs

- `radfpga_debug_hub`: Qt UI.
- `radfpga_debug_hubd`: daemon used by the UI.

Run the daemon directly:

```sh
radfpga_debug_hubd --host 127.0.0.1 --port 9737
```
