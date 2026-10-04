# Roadmap

Planning estimate: 12-14 weeks at roughly 5-7 hours per person per week. Re-estimate after hardware bring-up.

| Phase | Weeks | Robel | An | Exit criterion |
| --- | --- | --- | --- | --- |
| Setup and contracts | 1 | Clock/sample/numeric proposals | Firmware/toolchain and protocol proposal | Both reproduce repository checks; agree interfaces |
| Independent bring-up | 2-3 | Tone output, I2S RX/TX, stereo bypass | UART identity/status and ESP32 transport | Stable stereo bypass; PC and ESP32 can query FPGA |
| Controlled filter | 4-5 | One modeled biquad per channel | Shadow writes, commit, ACK/NACK | Live filter changes with coherent frame-boundary updates |
| Core EQ | 6-7 | Five-band stereo cascade, headroom | Presets and usable controls | Measured responses match models; stable core demo |
| Compression | 8-9 | Stereo-linked envelope/gain | Compressor controls and telemetry | Stereo linking and overload behavior verified |
| User interface | 10-11 | Meter data, VGA integration | Web interface and display layout | Demo controllable and understandable without a laptop terminal |
| Qualification | 12-14 | Timing, CDC, response/latency | Recovery, protocol faults, reproducibility | Both reproduce release build and evidence |

## Scope gates

The first resume-ready demonstration is the programmable stereo EQ with real I2S audio, live control, reproducible models, and measured results. Add compression and VGA only after that path works. Defer FFT, wireless audio streaming, and custom PCBs.

First tasks: identify the exact ESP32 board; obtain/check the codec; record installed Vivado version; validate audio clock generation; agree protocol framing and numeric formats; bring up UART and audio independently.
