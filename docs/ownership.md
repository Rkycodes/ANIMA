# Work split

| Area | Primary owner | Review / handoff |
| --- | --- | --- |
| Audio clocks, resets, I2S RX/TX, stereo FIFOs | Robel | An reviews pin and interface contracts |
| Gain, biquads, compression, saturation | Robel | An reviews control integration |
| Python reference and bit-exact audio models | Robel | Shared test-vector review |
| ESP32 firmware, Wi-Fi and web controls | An | Robel checks parameter meanings |
| FPGA UART, parser, shadow registers, acknowledgements | An | Robel reviews CDC and commit behavior |
| PC serial utility and protocol tests | An | Shared fault injection |
| VGA | Shared | An: layout/control; Robel: meters, clocks, integration |
| CI plumbing | An | Both maintain checks for their code |
| Board integration and release measurements | Shared | Both reproduce final demo |

## Handoffs

1. Robel defines sample/frame handshake and DSP parameter consumption; An defines packet transport and shadow-bank interface. Agree together before implementation.
2. An delivers a UART endpoint testable from a PC before ESP32 integration.
3. Robel delivers a single biquad per channel with model comparison before the full EQ cascade.
4. An provides a coherent parameter snapshot with a request generation. Robel returns the applied generation from the DSP domain.
5. Each owner supplies tests and documentation for their blocks. Integration does not transfer all debugging to Robel.

Keep shared interfaces small. Do not have both people editing the same top-level wiring concurrently; choose one integration owner per PR.
