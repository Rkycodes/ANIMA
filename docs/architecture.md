# Architecture - planned

No audio implementation or hardware evidence exists yet. The requirements below describe intended behavior; sample formats and clock configurations remain proposals. No frozen clock tree or binary interface is documented. See the [system diagram](../README.md#planned-system), [source index](sources.md) and [verification plan](verification.md).

## Responsibilities and flow

The FPGA owns audio processing; the ESP32 owns wireless/web controls and sends parameters over UART. Wi-Fi carries no audio. Planned DSP order: input gain -> five biquads per channel -> stereo-linked compressor -> output gain/saturation.

| Boundary | Owner / integration responsibility |
| --- | --- |
| Audio clocks/reset, I2S RX/TX, frame transport, DSP and reference models | Robel |
| ESP32, FPGA UART/parser, shadow parameters, acknowledgements and serial diagnostics | An |
| Frame/parameter contract, CDC, pins and board integration | Joint review; Robel defines consumption, An defines transport |
| VGA | An: layout/control; Robel: meters/clocks/integration |

[Ownership](ownership.md) defines the full work split. VGA 640 x 480 with procedural drawing/font ROM and the web interface follow bypass/EQ; FFT remains a stretch goal.

## Audio and control contracts

| Area | Required semantics / proposed values |
| --- | --- |
| Stereo frame | Paired L[n]/R[n] from the same sample interval; channels never advance independently |
| Proposed sample format | 48 kHz, signed two's-complement 24-bit samples; two 32-bit I2S slots, 64 wire bit clocks per frame |
| Raw payload | 48 bits per stereo frame, excluding metadata; packing, metadata and handshake remain open |
| EQ | Independent history for every channel/section, even with shared coefficients |
| Compressor | One gain applied to both channels; maximum-channel envelope is a proposal pending modeling |
| Numeric policy | Floating-point reference followed by a bit-exact model before DSP RTL; widths, rounding, coefficient representation and state reset remain open in [numeric design](numerics.md) |
| UART | Control only; [protocol](protocol.md) owns framing, fields, validation and acknowledgements. Its 3.3 V/115200-baud link is a draft; pins and interfaces are not frozen |
| Activation | Validate and hold a complete shadow snapshot until accepted; activate one generation at a frame boundary, without mixing generations in flight. Later writes cannot alter a pending snapshot |
| Acknowledgements | Receipt ACK is separate from applied generation, which is reported only after audio-side acceptance |
| Telemetry | Coherent levels, gain reduction, active generation and fault snapshots; congestion may drop/coalesce updates and must never block audio |

Commit/busy behavior, snapshot transfer, generation wrap, defaults and CDC remain joint decisions. Atomic coefficient activation alone does not ensure click-free transitions; transition/state handling needs model and audio evidence.

## Preset consistency requirements

Robel confirmed D-01 and D-02; An's shared-interface review is pending. These specify required behavior, not an implementation or selected pipeline.

| ID | Requirement |
| --- | --- |
| D-01 | If B arrives while L[n] is processed under A, R[n] also uses A. B may first apply to the next stereo frame at the agreed activation boundary; receipt alone does not activate it |
| D-02 | A frame that used A in EQ must also use A in compression, even if B activates for a later frame. Retain its required parameter values until all consumers finish |

[Editable frame/preset diagram](diagrams/frame-preset-consistency.mmd): frame 10 uses A throughout; frame 11 illustrates B after a permitted activation. Arrows show logical processing order, not clock cycles or simultaneous execution. Frame index and preset generation are distinct identifiers; a generation tag alone does not retain parameter values.

Open: activation readiness/boundary, in-flight parameter retention mechanism, pending B/new C policy, parameter-crossing owner and first integration owner. First hardware milestone scope and latency endpoints/limit still need agreement; the existing sub-5-ms verification target is a proposal. An's seven [interconnect questions](https://github.com/Rkycodes/ANIMA/blob/262a492/docs/notes/2026-10-04-interconnect-kickoff.md) remain proposals for joint review.

## Clock and codec constraints

Source IDs below resolve to exact manufacturer references in [sources](sources.md).

| Source | Constraint affecting ANIMA |
| --- | --- |
| SRC-001 | Basys 3 rev. C: 100 MHz reference at W5, MRCC bank 34; MMCM/PLL use is subject to clock routing rules. This does not select a DSP frequency or connector pin |
| SRC-002 / SRC-003 | Pmod schematic A.0 exposes separate ADC/DAC MCLK, LRCK and SCLK nets; JP1 selects ADC mode through SDOUT. Verify board revision, jumper and directions; the manual remains unavailable |
| SRC-004 | CS5343: 24-bit I2S, one-bit MSB delay. Single-speed slave (4-54 kHz): MCLK/Fs 256/384/512/768; SCLK/Fs 64 at 256/512, 48 or 64 at 384/768. At 48 kHz, master mode supports those MCLK ratios with 64 SCLK/frame. Mode is sampled at startup; do not drive its clock outputs in master mode |
| SRC-005 | CS4344: synchronous MCLK/LRCK/SCLK, no prescribed mutual phase; 48 kHz MCLK/Fs 256/384/512/768/1024. External SCLK accepts up to 24-bit I2S on rising edges with the MSB delay. Internal SCLK at 256/512/1024 is 32 Fs and only 16-bit I2S. External detection needs 16 rising edges in a LRCK phase; two frames without edges revert to internal mode |
| SRC-006 / SRC-007 | Use reviewed clock resources/constraints. Wizard actual frequencies may differ from requests; fractional MMCM feedback/CLKOUT0 division has 1/8 increments. Outputs must not be used before LOCKED; reset MMCM/PLL after lock loss |

Shared 48 kHz MCLK ratios 256/384/512/768 correspond arithmetically to 12.288/18.432/24.576/36.864 MHz. The proposed 64 Fs SCLK is 3.072 MHz. These are codec-compatible requests, not proven FPGA outputs. Candidates are shared 256 Fs MCLK with external 64 Fs SCLK and ADC slave, or shared MCLK with ADC-master LRCK/SCLK forwarded to DAC. Selection, startup contention, I/O setup/hold, duty cycle and routing require review.

Record exact device/tool versions, input tolerance, legal PFD/VCO/dividers, actual frequency/error, phase/duty cycle, estimated jitter and routing before selecting clocks. Do not substitute unconstrained fabric division or alternating periods for a validated audio clock. Routed timing and measured clocks require separate evidence.

## Domains, reset and scheduling

- **Topology open:** a common processing domain with enables avoids an audio/DSP crossing; separate domains require coherent frame CDC. Both need codec I/O timing and sufficient throughput. Related clocks still require timing analysis and are not automatically asynchronous.
- **Coherence:** independently synchronizing sample bits is invalid. Transfer complete frames through a reviewed handshake or FIFO. Async FIFOs support safe CDC, not sustained producer/consumer rate correction. Independent free-running ADC/DAC sample clocks require rate correction for indefinite bypass. Buffer type/depth remain open.
- **Reset/startup:** synchronize reset release per selected domain; suppress partial/invalid frames until clocks and codecs are ready and a complete LRCK-aligned frame is available. Clock loss invalidates partial frames and requires recovery. FPGA lock does not imply codec readiness. Resolve ADC mode sampling, DAC external-clock detection/ramp/settling, mute/release, stopped-domain reset assertion, CDC flushing, generation recovery and power cycling. No codec reset pin is assumed.
- **Deadlines:** I2S cannot wait for DSP or control. Define frame alignment, handshake/backpressure, bounded delay, startup priming and transmit deadlines before coding. At an example 100 MHz/48 kHz, the average budget is 2083.33 cycles/stereo frame; 100 MHz is not selected. Throughput depends on initiation interval, not latency alone; account for both channels, stalls and the shortest actual frame interval.
- **Faults:** expose partial/malformed-frame, overflow, underflow, deadline and clock-loss counters. Silence, discard/resynchronize, repeat or restart policies remain open; never mix channel indices or conceal rate mismatch. Define output safety both with and without running clocks. Controller loss and telemetry overload must not stall audio.

UART, parameter, telemetry and display crossings need their own coherent contracts. Detailed FSMs and buffering implementation belong with the eventual modules and tests.

## Next gate: stereo bypass

First implementation: RX -> paired frame transport -> TX, without gain, EQ or compression.

| Gate | Required decision / evidence |
| --- | --- |
| Codec configuration | Robel records board revision, JP1, voltage, clock directions, ratio, serial format and electrical timing; both review wiring |
| Clock feasibility/reset | Evaluate the exact device in Vivado; select topology from actual clock results and agree constraints/startup/recovery |
| Stereo frame contract | Robel proposes payload/metadata, handshake, deadlines, buffering and faults; An reviews control interaction |
| Bypass acceptance | Bit-exact digital samples, signed extremes, channel order, MSB delay/padding, no loss/duplication, bounded delay, reset/clock-loss/underflow recovery and independence from UART/telemetry load |

Proposed hardware exit: measured clocks/serial format, channel identification, audible analog bypass and a 30-minute error-free run, with timing/CDC review and reproducible configuration. Digital equality and analog behavior are separate checks; none is achieved yet.

Next teaching/design block: trace one stereo I2S frame from clock edges to paired payload and back. An can develop UART framing and shadow/commit proposals in parallel; applied-generation integration waits for the frame contract. DSP follows accepted bypass.
