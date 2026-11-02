# Simplified control-path reference

This is an educational, single-clock Verilog-2001 implementation of byte buffering, packet validation, command dispatch, and shadow/pending/active configuration registers. It is a proposed protocol demonstration, not the frozen ANIMA wire format or an integrated audio controller.

## Files and module boundaries

- `rtl/control/anima_control_example.v`: top-level and four small submodules in one file for reading together.
- `anima_example_byte_fifo`: synchronous power-of-two FIFO with a combinational head output.
- `anima_example_packet_rx`: escaped framing, bounded assembly, length/CRC checking, and timeout recovery.
- `anima_example_dispatch`: semantic validation and one-entry duplicate suppression.
- `anima_example_config`: shadow and pending snapshots, frame-boundary activation.
- `sim/control/tb_anima_control_example.sv`: testbench and randomized independent FIFO scoreboard.
- `scripts/test_control_example.py`: independent Python CRC vectors and simulation runner.

## Interface and integration

All signals use `clk`. `rst_n` is an asynchronous active-low reset; release must be synchronized to this clock in a physical integration. `FIFO_ADDR_BITS` must be at least 1 and `TIMEOUT_CYCLES` must be positive. Defaults are a 16-byte FIFO and 1,000,000 parser wait cycles (10 ms at 100 MHz).

Connect the existing RX module's `received_byte` to `rx_byte`, and its `received_data_valid` to `rx_valid`. `rx_valid` is a byte event sampled on every rising edge, not a level to hold until ready. No UART serial receiver or transmitter is instantiated by this example. The existing RX does not expose a framing-error output: tie `rx_error` low until one is available. Keep the independently edited UART sources separate from this example.

`rx_error` aborts unfinished assembly and flushes queued bytes. `rx_overflow` indicates a byte arriving when the FIFO cannot accept it, and triggers the same recovery. These faults do not undo an already validated command or pending configuration. After abort, the parser ignores data until a delimiter. On malformed framing/length/escaping it discards until a delimiter; CRC failures discard that candidate. `packet_error` is a pulse indicating a discarded candidate, timeout, or receive abort; it is not a complete per-error diagnostic counter.

The parser's internal packet output uses valid/ready and remains stable during backpressure. The top-level dispatcher is always ready. The FIFO can therefore still overflow under sufficiently fast artificial byte input, especially consecutive short packets. Real UART traffic is much slower, but finite buffering is not a guarantee against unbounded stalls.

`reply_valid` is a one-cycle event carrying `reply_sequence`, `reply_status`, and `reply_generation`. `applied_valid` is a separate one-cycle event carrying `applied_sequence`; `active_generation` identifies the applied generation. Both events may occur on the same edge. Capture them in separate event buffers if adding a reply encoder. There is no reply queue, wire reply format, or TX integration here. Opcode `01` produces an OK event only; it does not construct an identity/status response payload.

`frame_start` must be synchronous to `clk` and asserted for exactly one cycle per chosen frame-admission event. Reset starts with bypass enabled, zero gain, active generation zero, and no valid shadow or pending snapshot. Gain outputs are stored parameter codes, not a hardware dB-to-linear multiplier.

## Request wire format

```text
55 | escaped(VERSION OPCODE SEQUENCE LENGTH PAYLOAD CRC_H CRC_L) | 55
```

Each header field is one byte. Version is `01`. Length counts decoded payload bytes, with a maximum of 16. Total decoded size must equal `length + 6`. Unescaped delimiters close the previous candidate and open a new one; consecutive delimiters are ignored. Outside a candidate, other bytes are ignored. Zero bytes inside a candidate are ordinary data.

Escaping applies to the complete header/payload/CRC body:

| Original byte | Wire bytes |
| --- | --- |
| `55` | `7D 75` |
| `7D` | `7D 5D` |

Other escape pairs are invalid. A delimiter after an unfinished escape aborts the candidate and establishes a new boundary. Maximum decoded storage is 22 bytes logically, represented by header registers, a 16-byte payload register, and incremental CRC state. Maximum encoded packet size is 46 bytes including delimiters.

CRC parameters: width 16, polynomial `1021`, initial value `FFFF`, no input/output reflection, final XOR `0000`, high byte transmitted first. Coverage is decoded header and payload, excluding delimiters and the transmitted CRC itself. The implementation includes received CRC bytes in its accumulator and checks zero residue. ASCII `123456789` has check value `29B1`.

Timeout counts cycles waiting for another parser input byte during unfinished assembly. It is paused while a validated output packet waits for acceptance. It is not a timestamped measurement of physical UART inter-character gaps. Timeout discards assembly and waits for a fresh delimiter.

## Commands and results

| Opcode | Payload | Effect |
| --- | --- | --- |
| `01` | Empty | OK event; no state change |
| `10` | Bypass byte, gain low byte, gain high byte | Atomically replace shadow |
| `11` | Empty | Publish an immutable copy of valid shadow as pending |

Bypass must be exactly `00` or `01`. Gain is signed 16-bit little-endian in units of 1/256 dB. The accepted range is -3072 through +3072 (-12 through +12 dB): example limits only, not established DSP limits.

| Result code | Meaning |
| --- | --- |
| `00` | OK |
| `01` | Commit accepted; generation supplied |
| `02` | Unsupported opcode |
| `03` | Incorrect command payload length |
| `04` | Invalid parameter value |
| `05` | No valid shadow configuration |
| `06` | Latest sequence reused with different contents |
| `07` | Unsupported version |

Framing/CRC failures produce `packet_error`, not a request-specific result. Structurally valid rejected commands produce a result and are cached like successful commands. An identical retry of the most recent request replays its original status/generation without executing it again. A different request using that same sequence returns conflict and preserves the cache. Any new sequence replaces the cache.

This cache assumes one unacknowledged request within a single uninterrupted session. Old retries after intervening requests, session establishment, safe sequence reuse/wrap, and reset-persistent deduplication are not implemented. Generation is 16 bits and wraps modulo 65536 without a reuse protection policy.

## Snapshot and activation semantics

A shadow write never changes pending or active settings. A commit copies shadow into pending and allocates a generation. A newer valid commit replaces an unactivated pending snapshot. Invalid input leaves existing shadow/pending/active values intact.

At `frame_start`, the previously pending snapshot becomes active. If commit and `frame_start` coincide, old pending activates and the new commit remains pending for the next frame. With no previous pending snapshot, the simultaneous commit waits until a later frame. Bypass, gain, and generation change together.

Active outputs update after that rising edge through nonblocking assignments. Another sequential consumer sampling the active outputs on that same edge sees the previous values. A future frame-admission interface must account for this, for example by capturing the snapshot on the following clock with an aligned frame-valid signal.

This demonstrates atomic parameter-register activation only. A real audio pipeline must pin these values per admitted frame or retain generation storage through every old consumer. Reading these global active registers at arbitrary later DSP stages would not guarantee frame consistency. There is no CDC, coefficient validation, gain smoothing, retained generation storage, or superseded-result notification. These are required design work before real audio integration, not claims established by this example.

## Run and evidence

Requires Python 3 and Icarus Verilog (`iverilog`, `vvp`). From the repository root:

```sh
python3 scripts/test_control_example.py
verilator --lint-only -Wall -Wno-DECLFILENAME --top-module anima_control_example rtl/control/anima_control_example.v
```

The filename warning is disabled because this teaching file intentionally contains five modules. The RTL itself uses Verilog-2001; the testbench uses SystemVerilog. Temporary stimuli/executables are removed by the runner.

Simulation covers back-to-back packets, escaped sequence values, fixed CRC vectors, CRC rejection, oversized payload rejection, malformed escapes, semantic validation, truncation at every wire-byte position, timeout/resynchronization, immutable pending storage, same-edge commit/activation, duplicate/conflicting requests, latest-pending replacement, receive aborts, forced FIFO overflow/recovery, and reset. A 2,000-cycle randomized FIFO scoreboard independently checks byte order and boundary flags. These are simulation checks, not synthesis, routed timing, CDC, UART electrical, or hardware audio validation.
