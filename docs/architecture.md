# Architecture - planned

This repository is a scaffold. The following is intended behavior, not implemented audio, synthesis, timing closure, or hardware evidence. Manufacturer findings use stable IDs in the [shared source register](sources.md); proposals and unresolved choices are identified below.

## Ownership and audio frames

Robel owns audio clocks/reset, I2S reception/transmission, frame transport, gain, EQ, compression, saturation, and reference models. An owns ESP32 communications/web controls, FPGA UART/parser, shadow parameters, acknowledgements, and serial diagnostics. Both review the frame/parameter boundary, CDC, pins, and integration. VGA is shared: An owns layout/control; Robel owns meters/clocks/integration. See [ownership](ownership.md).

Planned chain: I2S receiver -> stereo frame handoff -> input gain -> five biquad sections per channel -> stereo-linked compressor -> output gain/saturation -> stereo frame handoff -> I2S transmitter. A frame pairs L[n] with R[n] from the same sample interval; neither channel advances alone. EQ histories are independent for each channel and section even when coefficients match. The compressor applies one shared gain to both channels; deriving its envelope from the larger channel level is a proposal pending model evaluation.

Proposed format: 48 kHz, signed two's-complement 24-bit samples, in two 32-bit I2S slots. The raw internal stereo payload is 2 x 24 = 48 bits, excluding validity, sequence, generation, timestamps, and fault metadata. The wire frame occupies 64 bit clocks. Payload packing, handshake, backpressure, metadata, DSP widths, rounding, coefficient representation, and filter-state reset remain open; [numeric formats](numerics.md) are candidates rather than contracts.

## Manufacturer-supported clock and serial requirements

- **SRC-001:** Basys 3 rev. C has a 100 MHz reference at W5, an MRCC input in bank 34. MMCM/PLL clock generation is available subject to placement/routing rules. This identifies the board reference, not a selected DSP frequency or new pin assignment.
- **SRC-002:** Pmod I2S2 schematic A.0 exposes separate ADC and DAC MCLK/LRCK/SCLK nets through J1. JP1 selects ADC master/slave through its SDOUT mode circuit. These clocks are not shown as already tied together; verify the physical board revision and jumper before wiring. **SRC-003** manual access remains pending (HTTP 403).
- **SRC-004:** CS5343 uses I2S, with 24-bit two's-complement data and a one-bit MSB delay after the LRCK transition. In single-speed slave mode (4-54 kHz), MCLK/LRCK supports 256, 384, 512, 768; SCLK/LRCK is 64 for 256/512 and 48 or 64 for 384/768. At 48 kHz, master mode also supports those MCLK ratios and generates 64 SCLK per frame. Its mode selection is sampled at startup; avoid driving outputs when configured as master. Review electrical timing on pp. 9-10, not only nominal ratios. The consulted F5 PDF is marked Draft.
- **SRC-005:** CS4344 requires synchronous MCLK, LRCK, and SCLK (no particular mutual phase specified). At 48 kHz its table lists MCLK/LRCK 256, 384, 512, 768, 1024. External SCLK accepts up to 24-bit I2S, sampled on rising edges with the I2S MSB delay. At 256/512/1024, internal SCLK mode is 32 Fs and only 16-bit I2S: do not use it for the proposed 24-bit/32-slot link. External mode detection requires 16 SCLK rising edges during a LRCK phase; two frames without edges return it to internal mode. Review setup/hold and duty-cycle limits on p. 9.

The shared 48 kHz MCLK ratios are therefore 256/384/512/768. Their arithmetic frequencies are 12.288/18.432/24.576/36.864 MHz; 64 Fs gives SCLK 3.072 MHz and LRCK 48 kHz. These are codec-compatible requests, not proven FPGA outputs. A candidate is common 256 Fs MCLK with external 64 Fs SCLK and ADC slave mode. An alternative is ADC master mode, forwarding its LRCK/SCLK to the DAC while sharing MCLK; direction, startup contention, routing and timing need review before selecting it. Independent free-running ADC/DAC sample clocks are unsuitable for indefinite bypass without rate correction.

**SRC-006/SRC-007:** 7-series MMCM/PLL and dedicated clock buffers are the appropriate resources to investigate. Clocking Wizard can return best-attempt actual frequencies rather than requested values. It supports MMCM fractional feedback and CLKOUT0 division in 1/8 increments; this does not prove the candidate frequencies achievable. Record the exact part, Vivado/IP version, input tolerance, legal PFD/VCO/dividers, actual output/error, phase/duty cycle, estimated jitter and clock routing before choosing a clock tree. Routed timing and hardware clock measurements are separate evidence. Avoid an unconstrained fabric divider or alternating periods presented as an exact low-jitter audio clock.

## Domain topology, reset and startup

Choose topology after codec configuration and clock feasibility review:

| Candidate | Benefits | Obligations before selection |
| --- | --- | --- |
| Common processing domain | I2S state machines and bypass/DSP use one suitable clock with enables; frame handoff can remain synchronous | Show codec edge timing, legal clock distribution and sufficient processing throughput; serial pins still require I/O timing constraints |
| Separate audio and DSP domains | DSP frequency can be chosen independently of serial timing | Transfer coherent complete frames through a reviewed CDC mechanism; define resets, bounded buffering and clock relationships |

Related clocks still need timing analysis; they are not automatically asynchronous. An asynchronous FIFO can safely cross asynchronous domains, but cannot correct sustained producer/consumer rate mismatch. Independently synchronizing sample bits does not preserve word coherence. A coherent handshake or FIFO must preserve the whole frame; mechanism and FIFO depth remain undecided. UART, parameter, telemetry, and display crossings also need explicit contracts.

Robel proposes a startup state sequence for joint review: safe output/invalid frames -> clock generation/reset -> stable lock -> codec initialization -> complete LRCK-aligned frame -> bypass running. Reset deassertion must be synchronized to each selected domain; clock loss must invalidate partial frames and invoke reviewed recovery. SRC-006 says clock outputs must not be used before LOCKED, and MMCM/PLL must be reset after lock loss. Define how reset is asserted when a domain stops, how both ends of any CDC are flushed, and how active generations recover.

SRC-005 initialization requires MCLK/LRCK and includes output ramp/settling; FPGA lock does not imply codec readiness. Startup wait, ADC mode sampling, DAC external-SCLK detection, mute/release policy and power-cycle handling must be resolved from the board configuration and datasheets. No codec reset pin is assumed. Use zero output while clocks remain valid as a candidate safe state; define behavior when clocks themselves are unavailable.

## Scheduling and faults

I2S traffic is periodic and cannot wait for control or processing. A proposed scheduler accepts a complete stereo frame, processes both channels, and presents a complete output before its assigned transmit deadline. Agree frame alignment, fixed/bounded delay, ready/valid or equivalent semantics, stall limits, buffer occupancy and startup priming before coding.

At an example 100 MHz processing clock and 48 kHz frame rate, the average budget is 100,000,000 / 48,000 = 2083.33 cycles per stereo frame. This is arithmetic, not an integer fixed schedule or a frozen DSP clock. Throughput depends on initiation interval: a pipeline with long latency may still accept frames fast enough, whereas low latency alone does not establish sustained throughput. Account for both channels, all stages, stalls, resource sharing, and the shortest actual frame interval; prove deadlines separately from end-to-end latency.

Define and expose counters for malformed/partial frames, overflow, underflow, missed deadlines and clock loss. Candidate recovery is silence on unavailable output, discarding partial frames and resynchronizing on a complete stereo boundary; whether to drop, repeat, mute or restart must be agreed and tested. Never pair L[n] with R[n+1] or silently conceal a rate mismatch. Telemetry overload and a disconnected controller cannot stall audio.

## Parameter activation and observations

An proposes UART framing, bounded parsing, corruption checks and shadow writes; Robel defines parameter consumption. Jointly agree validation, field widths/units, snapshot lifetime, commit/busy behavior, generation wrap, reset defaults, CDC and acknowledgement semantics in [protocol](protocol.md). Do not treat its draft baud rate or interfaces as frozen.

Planned atomic activation: validate a complete shadow set, hold its snapshot stable until accepted, then switch all affected stages to one generation at an agreed frame boundary. In-flight frames must not mix generations; choose draining, generation tagging or another demonstrated scheme. Report applied generation only after audio-side acceptance, separately from receipt ACK. Later writes cannot modify a pending snapshot. Atomic coefficient activation does not guarantee click-free transitions; smoothing, crossfade or state handling requires model and audio evidence.

Telemetry is a coherent snapshot of levels, reduction, generation and faults. It may be dropped/coalesced under congestion and never blocks audio. The transfer/refresh mechanisms and register map remain open. VGA 640 x 480, procedural drawing/font ROM and an ESP32 web interface remain proposals after bypass/EQ; FFT remains a stretch goal.

## Next design gate and first implementation milestone

Recommended teaching/design block: trace one stereo I2S frame from codec clock edges to paired payload and back, then compare clock ownership alternatives with their startup and deadline requirements.

1. **Codec configuration:** Robel records board revisions, JP1 setting, clock directions, selected ratio/serial mode, voltage and datasheet timing. Both review; resolve SRC-003 manual availability. Do not select FPGA connector pins by inference.
2. **Clock feasibility/reset:** Robel evaluates candidate clocks for the exact device in Vivado, records actual frequency/error and tool estimates, proposes clock constraints and reset/startup/recovery states. Choose common or separate domains based on evidence; do not infer achievable frequency, jitter or timing closure from arithmetic.
3. **Stereo frame contract:** Robel proposes paired payload/metadata, handshakes, deadlines, buffering, fault policy and resets; An reviews control interaction. Freeze only the reviewed bypass contract, not speculative DSP widths or FIFO depths.
4. **Stereo bypass acceptance:** first implementation is RX -> paired frame transport -> TX without gain, EQ or compressor. Require simulated bit-exact signed samples, channel order, MSB delay and padding; no frame loss/duplication during the agreed run; bounded documented delay; reset/clock-loss/underflow recovery; and independence from UART/telemetry load. Proposed hardware exit includes measured clocks/serial format, channel identification, audible analog bypass and a 30-minute error-free run, supported by timing/CDC review and reproducible configuration. Digital equality and analog codec behavior are different checks. None has been achieved here.

An can develop the UART framing and shadow/commit proposal in parallel, including identity/status examples and malformed/duplicate/reset behavior. Transport design can proceed before audio integration; applied-generation behavior waits for the reviewed frame contract. Build DSP only after stereo bypass acceptance.
