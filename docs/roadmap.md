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

## First milestone - agreed

First-milestone planning is agreed; implementation and acceptance evidence are still outstanding. Robel and An selected stereo bypass on October 6, 2026: I2S RX -> coherent stereo-frame transport -> I2S TX, without DSP. See [bypass acceptance planning](verification.md#stereo-bypass-milestone) for the requested Verilator/randomized/deterministic checks and five-minute simulated-audio run. Latency goal is 5 ms from signal entry to audible playback; exact test setup and hard acceptance limit remain open. An's independent UART work can proceed in parallel; its delivery is not required to claim the selected audio-bypass milestone.

Before coding, resolve architecture and the [data/transfer contract](architecture.md#before-coding-data-contract), including bit widths, signedness, representation and movement/handshake rules. Code-local mechanics and FSM structure may be worked out during implementation. No RTL implementation is authorized by recording this milestone.

## Scope gates

The first resume-ready demonstration is the programmable stereo EQ with real I2S audio, live control, reproducible models, and measured results. Add compression and VGA only after that path works. Defer FFT, wireless audio streaming, and custom PCBs.

First tasks: identify the exact ESP32 board; obtain/check the codec; record installed Vivado version; validate audio clock generation; agree protocol framing and numeric formats; bring up UART and audio independently.
