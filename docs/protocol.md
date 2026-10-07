# Control contract - draft

Initial link: 3.3 V UART, 115200 baud, common ground. UART is control only. Pin choices and final framing remain undecided.

## Required behavior

- Version/identity query and status query.
- Read/write shadow parameters, validate ranges, commit a preset, and bypass.
- ACK/NACK with command sequence identifiers and a corruption check.
- Bounded parsing, timeouts, retry behavior, duplicate-request handling, and reset recovery.
- A distinction between a received command and a preset actually applied by DSP.
- Coherent telemetry: levels, gain reduction, active generation, and FIFO/frame error counters.
- Bad or partial packets cannot alter active parameters. A lost controller cannot stall audio.

## Pending preset policy

**D-03 - latest pending wins:** Robel and An agreed in discussion; reported by Robel on 2026-10-06. Not implemented. If B has not activated and a complete validated preset C becomes eligible to replace it, C supersedes B; B need not activate. Partial or invalid input does not supersede a valid pending preset. Active or in-flight generations remain protected until their last consumer finishes.

This is a behavioral policy, not a selected queue/banking/CDC implementation. The cutoff between replaceable pending data and an immutable activation transfer, arbitration with activation, and reporting superseded requests remain open. A superseded preset must not be reported as applied.

[Editable pending-preset diagram](diagrams/pending-preset-policy.mmd).

Implementation sketch for discussion; physical storage count, clock topology and enforcement are not selected:

| Logical role | Rule |
| --- | --- |
| Staging / shadow | Assemble incoming writes; check completeness, corruption and parameter validity before publication |
| Pending | Latest complete eligible snapshot, awaiting activation; replacement is atomic and cannot expose a partially written set |
| Activation | Serialize publication/replacement with frame-boundary selection; pin a complete generation for the admitted stereo frame |
| Protected snapshots | Retain active and older in-flight values until all consumers finish; pending replacement cannot overwrite them |

Example: frame 10 uses A; B becomes pending; complete valid C supersedes B before activation; frame 11 may use C at the next eligible boundary. If C is incomplete or fails validation, B remains pending. If B has already activated, C waits for a later activation instead. Generation tags refer to retained values; they do not store them.

Any cross-domain snapshot transfer must remain coherent and stable through acceptance. A transfer already owned by a receiver cannot be mutated in place to implement replacement. Define when C becomes eligible at the activation owner, including simultaneous replacement/activation and superseded-request reporting. Receipt does not promise application; only actual activation may produce an applied acknowledgement. Audio continues with its assigned preset while a replacement is being assembled.

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
