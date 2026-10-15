# An's control-system learning and delivery plan

Prepared October 6, 2026 from the current repository. This is a proposed personal work plan, not an agreed interface contract. Robel's forthcoming kickoff responses must be reconciled before freezing shared interfaces. The repository remains a scaffold.

Your central responsibility is to make a continuously running FPGA audio engine configurable, observable, and recoverable from software. Success means a controller can request a change, know whether it took effect, and recover from errors without interrupting audio.

The existing [ownership split](../ownership.md) assigns you FPGA UART, packet parsing, shadow registers and acknowledgements; the Python serial utility; ESP32 firmware and web controls; CI plumbing; and VGA layout/control. Robel owns the audio transport, DSP and reference models. CDC implementation, activation registers, telemetry crossing and top-level integration ownership remain unresolved in the [kickoff](2026-10-04-interconnect-kickoff.md).

```text
Your PC utility OR ESP32 controller
                |
              UART
                |
Your FPGA RX/TX -> parser -> validated shadow parameters
                                      |
                           stable commit snapshot
                                      |
                   jointly defined crossing / activation
                                      |
                       Robel's audio/DSP engine
                                      |
                   applied generation + coherent telemetry
                                      |
                     your reply/status path -> controller
```

The diagram is logical: simultaneous physical PC and ESP32 endpoints are not decided. Wi-Fi carries controls, not audio.

## What to work on immediately

Aim for these outputs in your next 5-7 available hours, adjusting for your starting experience. These are time boxes, not promised implementation dates.

1. **Hardware inventory, 45 minutes.** Record the exact ESP32 module/dev board, Basys revision, available tools and simulator versions. Identify candidate UART pins from that board's documentation; mark them unapproved until the shared allocation is reviewed.
2. **Trace one command, 60 minutes.** Draw what happens from a preset request through validation, staging, commit, audio acceptance and status readback. Include lost reply, duplicate request and either board resetting. Distinguish command sequence identifiers from applied parameter generations.
3. **Protocol proposal, 90 minutes.** Prepare a reviewable proposal for framing, bounded length, byte order, CRC definition and coverage, identity/status messages, errors, timeouts and retries. Include one annotated valid packet and corrupted/truncated examples with expected behavior. Keep unknown parameter units and addresses explicitly unresolved.
4. **UART learning exercise, 90 minutes.** Draw an 8N1 waveform and a receive state machine. Calculate sampling points and baud error. If RTL is new, first simulate a counter and a small state machine before attempting a complete receiver. A standalone UART exercise can use a stated example clock without choosing the production clock.
5. **Verification matrix and review preparation, 60 minutes.** List inputs, expected replies and forbidden side effects. Group Robel's pending answers by which deliverable they unblock. Reserve remaining time to reproduce the repository check and write down findings.

Do not freeze protocol consumers before review: the current [protocol draft](../protocol.md) explicitly requires decisions first. Before agreement, write proposals, test vectors and isolated exercises; afterward implement the endpoint and host against the same contract.

## Learn in this order, with something observable at each step

| Priority | Concepts | Exercise / evidence of understanding |
| --- | --- | --- |
| 1 | Synchronous RTL: registers, combinational logic, nonblocking assignments, counters, FSMs, reset, clock enables | Simulate a small FSM; explain what changes on each clock edge. Keep synthesizable logic in Verilog-2001 and benches in Verilog/SystemVerilog. |
| 2 | UART: idle/start/data/stop, asynchronous input, midpoint sampling, divider error, framing errors | Transmit and receive known bytes in simulation; vary phase and baud within a documented test range and inject bad stop bits and reset. |
| 3 | Packet transport: boundaries, lengths, byte order, CRC, timeout, bounded buffers | Explain how the parser recovers after garbage. Show that malformed traffic cannot modify active parameters. |
| 4 | Hardware/software contracts: registers, validation, idempotence, sequence numbers, state machines | Define retry behavior. A sequence field only works when the receiver remembers and handles duplicates; define its scope and reset behavior. |
| 5 | Shadow/pending/active state and CDC: metastability, coherent buses, req/ack handshake, snapshot lifetime | Draw a timing trace in which shadow edits continue while an earlier snapshot waits for acceptance. Pending data must remain stable. |
| 6 | Essential DSP vocabulary: sample/frame, gain in dB, frequency/Q, fixed point, coefficient signs, saturation | Explain what every exposed control means and encode/decode agreed numeric examples against Robel's model. Coefficient generation ownership is still open. |
| 7 | Embedded firmware: UART buffering/events, bounded queues, reconnect state, coalescing | Use ESP32 identity/status transactions, then show that rapid UI changes do not create an indefinitely growing command queue. |
| 8 | Verification and FPGA implementation: assertions, waveforms, constraints, timing/CDC reports, instrumentation | Reproduce a test and build from a commit; distinguish simulation success from timing closure and hardware evidence. |

At the draft 115200 baud, 8N1 uses ten wire bits per byte, so capacity is 11,520 bytes/second in each direction before packet overhead. A 32-byte packet occupies about 2.78 ms. At the target 48 kHz, an audio frame occurs about every 20.83 microseconds. These are arithmetic examples, not selected packet sizes or measured performance. They explain why controls need buffering/coalescing and must not gate audio progress.

A two-flop synchronizer reduces the probability that metastability propagates for a single-bit signal; it does not guarantee coherent multi-bit words. Independently synchronizing each coefficient bit can yield a combination never sent. Learn a stable-bus handshake or other reviewed transfer method. The selected topology determines whether a particular boundary actually needs CDC.

You need enough DSP understanding to send correct parameters and reason about transitions. Deep filter architecture and compressor implementation remain Robel's primary work. Atomic updates prevent mixed parameter sets; they do not by themselves prevent audible clicks.

## Delivery sequence and acceptance gates

| Order | Your deliverable | Done when | Dependency |
| --- | --- | --- | --- |
| A | Reviewed transport contract and Python packet tests | Both agree example bytes, errors, CRC, retry and reset semantics | Joint protocol review; DSP addresses can remain outside the first identity/status slice |
| B | FPGA UART/parser and PC identity/status utility | Valid requests return expected replies; garbage, timeout, corruption and reset recover predictably in simulation and then on the board | Clock/reset and PC UART pin decisions; reviewed constraints |
| C | Shadow/commit logic with a simulated audio-side consumer | Invalid updates have no active effect; pending snapshots cannot be overwritten; duplicate commit handling is defined; applied generation follows acceptance | Shared snapshot/activation contract; simulation is not actual audio validation |
| D | Integration with the real audio engine | A whole parameter generation activates at the agreed boundary; in-flight frames obey the agreed policy; disconnected or overloaded controls do not stall audio | Robel's working bypass and parameter consumer |
| E | ESP32 transport, then minimal web controls | ESP32 reproduces PC transactions; UI distinguishes requested and applied values; reconnect reads actual state | Exact board/framework and UART wiring; approved control units |
| F | Telemetry, usability and release evidence | Status remains coherent under load; replies and telemetry are scheduled without blocking audio; both people reproduce the demo | Shared telemetry map, buffering/drop policy and integration |

Test failures deliberately: truncated packets, oversized lengths, bad CRC, unsupported commands, invalid values, lost replies, duplicate commits, reset during a packet, reset during a pending commit, reconnect and telemetry saturation. Set concrete expected behavior before writing each test. A simulated audio consumer can validate your side early but cannot prove the real DSP's frame-boundary behavior.

Keep VGA polish, elaborate web graphics and presets behind a working serial-controlled EQ. Compression follows the core EQ; FFT, wireless audio streaming and custom PCB work remain deferred under the project roadmap.

## How to use Robel's responses

| Decision group | What it unblocks |
| --- | --- |
| Control clock, reset, endpoint count and pins | Production UART integration and constraints |
| CDC owner, activation owner, snapshot lifetime, busy policy and acceptance signal | Safe commit implementation and applied-generation reporting |
| User units versus coefficients; widths, ranges, signs and quantization | Parameter schema, encoding and UI-to-DSP translation |
| Telemetry map, snapshot producer and crossing owner | Coherent status serialization and display refresh |
| One named top-level integration owner for the PR | Predictable wiring and shared debugging |

Record agreed answers in the relevant contract documents, with unresolved items still marked open. Do not interpret an unanswered question as an assignment to either person. The first review goal is a minimal identity/status slice plus clear ownership of the later commit boundary.

## Why this is relevant to industry

Your part develops embedded firmware, FPGA control RTL, hardware/software interface design, verification and system integration. The engineering problem is keeping a time-sensitive datapath dependable while software configures it and observes it.

AMD explicitly describes programmable logic isolating critical industrial control timing from unpredictable network/software activity in its [industrial architecture overview](https://www.amd.com/de/solutions/industrial/silicon-architecture.html). Its [embedded HMI paper](https://docs.amd.com/api/khub/documents/egTfGufa~5e_WaZ1wMJzzA/content) discusses processor/FPGA combinations for interfaces, acquisition, control and accelerated computation. ANIMA's split is a small educational instance of that broader separation.

The following are transferable design analogies, not claims that ANIMA meets production or safety requirements:

| ANIMA work | Comparable engineering need |
| --- | --- |
| Commit a coherent EQ preset while audio continues | Change configuration in a running signal-processing or acquisition system at a defined boundary |
| Separate receipt from actual activation | Let host software determine when a hardware operation has truly taken effect |
| Validate commands and recover after disconnect/reset | Keep remotely managed embedded equipment diagnosable and recoverable |
| Coalesce telemetry and prioritize replies | Provide operator visibility without letting monitoring disrupt real-time work |
| Python fault injection, reproducible simulation and measured results | Give another engineer evidence that an interface works beyond its happy path |

Later, memory-mapped registers and AXI4-Lite are useful extensions of these control-interface ideas, but are not prerequisites for this project's UART milestone. The strongest portfolio evidence will be a working command path, waveforms and negative tests, an explained commit/CDC contract, and demonstrated audio continuity under control faults. Claim only results actually measured.

## Focused reading

Read the project's [protocol](../protocol.md), [architecture parameter activation section](../architecture.md), [numeric draft](../numerics.md) and [verification plan](../verification.md) alongside each exercise. These define the problems you are solving.

Use the [ESP-IDF UART guide](https://docs.espressif.com/projects/esp-idf/en/v5.3.4/esp32/api-reference/peripherals/uart.html) to study driver setup, pin configuration, buffering and events. This linked page is a versioned original-ESP32 example; use the corresponding documentation for the board and framework version you actually choose. It does not select your toolchain.

The kickoff already identifies Cummings' CDC paper and the Basys manual as reading targets. Focus first on single-bit synchronizers, multi-bit coherent handshakes and reset behavior. Verify actual electrical and pin decisions against the exact board manuals before connecting hardware.
