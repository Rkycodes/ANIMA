# Control contract â€” draft
Initial link: 3.3 V UART, 115200 baud, common ground. UART is control only. Pin choices and final framing remain undecided.

## Required behavior
- Version/identity query and status query.
- Read/write shadow parameters, validate ranges, commit a preset, and bypass.
- ACK/NACK with command sequence identifiers and a corruption check.
- Bounded parsing, timeouts, retry behavior, duplicate-request handling, and reset recovery.
- A distinction between a received command and a preset actually applied by DSP.
- Coherent telemetry: levels, gain reduction, active generation, and FIFO/frame error counters.
- Bad or partial packets cannot alter active parameters. A lost controller cannot stall audio.

## Decisions required before coding
| Decision | Owner |
| --- | --- |
| Packet delimiter, length, byte order, payload limits | An proposes; both review |
| CRC algorithm and exact covered bytes | An proposes; both review |
| Register addresses, field widths, units, valid ranges | Both |
| Fixed-point coefficient representation and sample semantics | Robel proposes; both review |
| Shadow/commit handshake, reset values, generation wrap | Both |
| UART pins and CDC boundaries | Both |

Publish example packets and expected replies once agreed. Test the FPGA endpoint using the PC utility before adding ESP32/web integration. This document intentionally contains no provisional binary register map.
