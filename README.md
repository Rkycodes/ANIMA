# ANIMA
**Artix Networked I2S Multiband Audio Processor**

A stereo audio processor on the Basys 3 Artix-7 FPGA, with ESP32 wireless control.

**Status:** repository scaffold. Audio RTL, firmware, board constraints, and hardware validation are not implemented yet.

## Planned system
Stereo line input â†’ Pmod I2S2 ADC â†’ FPGA input gain â†’ five-band EQ â†’ stereo-linked compressor â†’ output gain â†’ Pmod I2S2 DAC â†’ powered speakers or amplifier.

Target: 48 kHz, 24-bit stereo samples in 32-bit I2S slots. The FPGA processes audio; the ESP32 hosts controls and sends parameter updates over UART. Wi-Fi carries control traffic only. VGA meters and an ESP32 web interface follow the working audio core. Guitar input is outside the initial scope.

## Repository layout
| Path | Purpose |
| --- | --- |
| [rtl/](rtl/README.md) | Synthesizable SystemVerilog: audio, DSP, control, display, common blocks |
| [model/](model/README.md) | Floating-point reference and bit-exact fixed-point models |
| [sim/](sim/README.md) | RTL testbenches, scoreboards, test vectors |
| [firmware/esp32/](firmware/esp32/README.md) | ESP32 control firmware and web interface |
| [tools/serial_host/](tools/serial_host/README.md) | PC serial control and protocol diagnostics |
| [hardware/](hardware/README.md) | Materials, wiring, and validated constraints |
| [docs/](docs/README.md) | Architecture, ownership, roadmap, interface contracts, verification |
| [scripts/](scripts/README.md) | Repository checks and future reproducible build scripts |
| [results/](results/README.md) | Measurement summaries and release evidence |

## Start here
1. Read the [work split](docs/ownership.md) and [roadmap](docs/roadmap.md).
2. Follow the [development workflow](docs/development.md).
3. Agree on [control protocol](docs/protocol.md), [numeric formats](docs/numerics.md), and clock ownership before writing their consumers.
4. Build a stereo bypass path and independent UART identity/status exchange before integrating DSP controls.

Run the available repository check with Python 3.12:
```sh
python scripts/check_repo.py
```
See [CONTRIBUTING.md](CONTRIBUTING.md) for branches and review expectations. CI currently checks documentation links and scaffold integrity; it does not prove FPGA synthesis, audio correctness, or timing.
