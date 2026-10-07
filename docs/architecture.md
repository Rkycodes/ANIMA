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

Robel confirmed D-01 and D-02; An's explicit shared-interface review of these two requirements remains pending. D-03 was agreed by Robel and An; its authoritative definition is in [protocol](protocol.md#pending-preset-policy). These specify required behavior, not an implementation or selected pipeline.

| ID | Requirement |
| --- | --- |
| D-01 | If B arrives while L[n] is processed under A, R[n] also uses A. B may first apply to the next stereo frame at the agreed activation boundary; receipt alone does not activate it |
| D-02 | A frame that used A in EQ must also use A in compression, even if B activates for a later frame. Retain its required parameter values until all consumers finish |

[Editable frame/preset diagram](diagrams/frame-preset-consistency.mmd): frame 10 uses A throughout; frame 11 illustrates B after a permitted activation. Arrows show logical processing order, not clock cycles or simultaneous execution. Frame index and preset generation are distinct identifiers; a generation tag alone does not retain parameter values.

Alternatives under discussion; none selected:

| Approach | Preservation rule / tradeoff |
| --- | --- |
| Retain snapshots | Keep each generation's values while any frame still needs them; requires bounded storage and a reuse policy |
| Capture needed settings | Preserve needed values with the frame before overwriting shared storage; requires complete capture and frame-owned storage |
| Finish old work first | Robel confirmed that replacement must wait for the last use of A, including compression. New-frame scheduling and deadline impact still need evaluation |

[Snapshot lifetime example](diagrams/preset-snapshot-lifetime.mmd) illustrates the first alternative, without selecting banking, capacity, CDC or scheduling.

Robel's scheduling intent: do not keep extending old-generation work indefinitely during a switch; frames admitted after B activates use B. Receipt/validation alone is not activation, and the activation delay remains open. Buffering waiting audio frames and pending presets is suggested, not selected: these hold different data, add finite capacity, and need separate full/overflow policies. Audio buffering adds latency; continuous audio deadlines still apply. Robel and An agreed latest-pending-wins (D-03), as reported by Robel; see the [control contract](protocol.md#pending-preset-policy). Storage and activation mechanisms remain open.

Open: activation readiness/boundary, in-flight parameter retention mechanism, pending replacement/activation arbitration and acknowledgements, parameter-crossing owner and first integration owner. First hardware milestone is stereo bypass. Latency runs from signal entry through audible playback; exact measurement setup and maximum remain open. The latency goal is 5 ms; the hard acceptance limit remains open until the measurement setup is defined. An's [interconnect kickoff](https://github.com/Rkycodes/ANIMA/blob/d77741fc47be789ec7ce2ae14417c2a0c8425738/docs/notes/2026-10-04-interconnect-kickoff.md) remains An Tiet's work; its questions are included in the worksheet below. Use the [architecture worksheet](#architecture-worksheet) to record answers before the next implementation increment.

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

First milestone is stereo bypass, agreed by Robel and An. Acceptance planning is in [verification](verification.md#stereo-bypass-milestone): Verilator lint/simulation, randomized stimulus/assertion checking, deterministic expected pairs and a five-minute error-free simulated-audio run. This is simulated audio time, not simulator wall time; hardware/audio measurements follow when hardware is available. The later 30-minute qualification proposal is separate; no acceptance evidence exists yet.

Next teaching/design block: trace one stereo I2S frame from clock edges to paired payload and back. An can develop UART framing and shadow/commit proposals in parallel; applied-generation integration waits for the frame contract. DSP follows accepted bypass.

## Before-coding data contract

Robel and An require the following to be resolved for every interface/state boundary included in the implementation increment before coding. Record values in the owning architecture/protocol/numeric contract; do not invent them to satisfy this checklist. Later DSP formats may remain explicitly deferred while implementing bypass.

- Payload and metadata bit widths, signedness, units/scaling, representation, packing, channel/field order and any serialization byte/bit order.
- Intermediate/state widths and numeric conversion rules where used: extension, truncation, rounding, saturation and overflow behavior.
- Source/destination, clock/reset ownership, complete-frame pairing and any coherent clock-domain crossing.
- Validity, acceptance and completion events; data stability/lifetime; handshake timing; allowed backpressure and buffering limits.
- Startup/reset values, invalid/partial data behavior, deadlines and agreed overflow/underflow/recovery semantics.

Code-local FSM organization and other implementation mechanics may be designed during coding once those externally observable contracts are fixed. This gate does not select any currently unresolved value.

## Architecture worksheet

Working questions for Robel and An, October 6, 2026. First-milestone planning is recorded in [roadmap](roadmap.md#first-milestone---agreed) and [verification](verification.md#stereo-bypass-milestone); its completed question section has been removed. The remaining prompts are unanswered, not selected designs. Fill the answer/evidence and owner/review cells together. Mark a box only after the answer has been reviewed and recorded in the authoritative document named below. For an evidence-dependent item, record a blocker and the experiment/owner needed rather than guessing.

The immediate goal is readiness for a small first implementation increment, not completion of every later DSP design. Sections 1-7 cover first-increment contracts; section 8 may be explicitly deferred until the corresponding DSP increment. Section 9 records handoff and planning-exit checks. Do not treat a deferred question as answered.

Confirmed so far: stereo-safe frames and coherent preset replacement are goals; D-01/D-02 are Robel-confirmed and await An's explicit review. D-03 latest-pending-wins is agreed by both: complete valid C may supersede pending B, while incomplete/invalid C leaves B eligible. Latency goal: 5 ms from signal entry to audible playback; precise measurement locations and the hard acceptance limit remain open. No storage mechanism, clock tree, binary map or RTL implementation is selected here.

### 1. Hardware, wiring and tools

Record physical facts in [materials](../hardware/BOM.md), pin/clock contracts here, and new manufacturer evidence in [sources](sources.md). An's kickoff is an input, not a verified board configuration.

| Done | ID | Question to answer | Answer / evidence or blocker | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | H-01 | What are the exact Basys 3 and Pmod I2S2 revisions, ADC jumper setting and supply/interface voltages? Do the consulted schematic/manual revisions apply? | | |
| [ ] | H-02 | What exact ESP32 module/dev board, USB-serial device and firmware framework/version will be used? | | |
| [ ] | H-03 | Which Pmod header/row and FPGA package pins are reserved for audio, UART and other functions? Who checks the source pin table and conflicting uses? | | |
| [ ] | H-04 | Which ESP32 GPIOs are safe for the chosen UART, considering straps, flash/PSRAM, boot output and board-specific connections? | | |
| [ ] | H-05 | What are clock/data directions, common-ground requirements and power sequencing? What happens when only one board is powered or either board resets? | | |
| [ ] | H-06 | Which Vivado/device/IP, Python and simulator versions are available? What codec documentation or tool access remains unavailable? | | |

### 2. Clocks and reset/recovery

Record selected topology and assumptions here; keep tool evidence in [results](../results/README.md). Documented ratios are not clock-feasibility evidence.

| Done | ID | Question to answer | Answer / evidence or blocker | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | C-01 | Who generates ADC/DAC MCLK, SCLK and LRCK? Which codec modes, ratios and sample rate are selected? How are the converter rates coordinated? | | |
| [ ] | C-02 | What clock-generation configuration is legal for the exact FPGA? What actual frequencies/error, phase, duty cycle, estimated jitter and routing does the tool report? | | |
| [ ] | C-03 | What clocks run audio, DSP, UART/parser and VGA? Which are common, related or asynchronous, and what timing assumptions establish that classification? | | |
| [ ] | C-04 | Where are coherent crossings required for frames, parameters, acknowledgements and telemetry? Who owns and reviews each side of each crossing? | | |
| [ ] | C-05 | What is held safe during startup, how is reset released per domain, and what establishes codec readiness and the first complete valid frame? | | |
| [ ] | C-06 | What happens on clock loss or either-side reset, including stopped-domain reset assertion, partial-frame invalidation, buffering flush and restart? | | |

### 3. Stereo-frame contract and scheduling

Record the system contract here and its checks in [verification](verification.md). Local implementation mechanics can wait for module design.

| Done | ID | Question to answer | Answer / evidence or blocker | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | F-01 | Are the proposed 48 kHz, signed 24-bit samples and two 32-bit slots adopted? What are LRCK polarity/channel order, MSB delay, sampling edges and padding behavior? | | |
| [ ] | F-02 | How is the paired 48-bit raw payload packed? What metadata is required, and how are frame index and preset generation distinguished? | | |
| [ ] | F-03 | What event means a frame is valid, accepted and released? What remains stable while waiting, and is any backpressure permitted? | | |
| [ ] | F-04 | What are receive, processing and transmit deadlines and bounded delays? What initiation interval/resource schedule meets them for both channels? | | |
| [ ] | F-05 | Is buffering needed, of what type and justified capacity? How are occupancy, startup priming and sustained rate mismatch handled? | | |
| [ ] | F-06 | What are observable output/recovery behaviors for missing, duplicate, malformed or late frames, overflow and underflow? Which counters expose them? | | |

### 4. Parameter lifetime and activation

Record parameter transport behavior in [protocol](protocol.md), audio consumption here, and shared ownership in [ownership](ownership.md). D-03 is already selected; the questions below concern its enforcement.

| Done | ID | Question to answer | Answer / evidence or explicit deferral | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | P-01 | Does An explicitly approve D-01 and D-02? Are any qualifications or additional scenarios needed? | | |
| [ ] | P-02 | What makes a snapshot complete and valid? What validation is done by the controller versus FPGA, and who owns each check? | | |
| [ ] | P-03 | What is the exact activation boundary and readiness condition? What limits receipt-to-activation delay? | | |
| [ ] | P-04 | How are values preserved for both channels and all stages of an in-flight frame: retained snapshots, captured settings or completion before activation? What is the reuse condition? | | |
| [ ] | P-05 | How is pending replacement made atomic, and when does a transfer become immutable? How is coherent publication/acceptance enforced across any selected domains? | | |
| [ ] | P-06 | If C becomes eligible on the same event as B activation, which wins? What ordering/cutoff makes this repeatable and testable? | | |
| [ ] | P-07 | How are received, validated/pending, superseded and applied outcomes represented? What does the controller learn if B was acknowledged but never activated? | | |
| [ ] | P-08 | What finite storage/backpressure is needed while incoming writes, pending values and protected generations coexist? What happens when storage is unavailable? | | |
| [ ] | P-09 | What are default active settings, bypass behavior and generation lifecycle after FPGA/controller reset or reconnect? | | |

### 5. UART transport and command contract

An leads transport proposals; both review integration. Record answers in [protocol](protocol.md) and ownership assignments in [ownership](ownership.md).

| Done | ID | Question to answer | Answer / evidence or explicit deferral | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | U-01 | Are PC USB-UART and ESP32 UART simultaneous endpoints, or is one selected? What selects/arbitrates them and who may change settings? | | |
| [ ] | U-02 | What baud/framing, asynchronous-input handling and baud-error budget apply to the selected clocks? | | |
| [ ] | U-03 | What packet delimiter/length, maximum payload, byte order, message types and versioning are used? What are the exact corruption-check algorithm and covered bytes? | | |
| [ ] | U-04 | What are parser timeout, malformed/truncated-input handling, resynchronization and rejection behavior? Can any partial command change active settings? | | |
| [ ] | U-05 | What do sequence identifiers identify, and how are retries, duplicate writes/commits and lost acknowledgements handled? | | |
| [ ] | U-06 | How do sequence/generation wrap and reset/reconnect avoid stale acknowledgements or duplicate activation? | | |
| [ ] | U-07 | How do replies and unsolicited telemetry share TX without starving replies or blocking audio? What exact packets/replies demonstrate the contract? | | |

### 6. Parameter meaning and numeric boundary

Record numeric semantics in [numeric design](numerics.md) and serialized fields in [protocol](protocol.md). Do not freeze a register map before these meanings are agreed.

| Done | ID | Question to answer | Answer / evidence or explicit deferral | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | N-01 | Does the controller send user units or quantized coefficients? Where are coefficients computed and which reference algorithm/version defines them? | | |
| [ ] | N-02 | What are field units, ranges, widths, signedness, coefficient order and feedback-sign convention? Which details are necessary for the first increment? | | |
| [ ] | N-03 | Who validates range, quantized stability and overload/headroom? What happens on rejection, and how will controller/model values be compared? | | |

### 7. Telemetry and audio independence

Record system guarantees here and wire representation in [protocol](protocol.md).

| Done | ID | Question to answer | Answer / evidence or explicit deferral | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | T-01 | What does one coherent snapshot contain, over what interval, and in what units? Which fields are needed for the first increment? | | |
| [ ] | T-02 | Where is the snapshot taken, where does it cross domains, and who owns capture, transfer and serialization? | | |
| [ ] | T-03 | What refresh/rate limits and drop/coalescing policy apply? How are stale values and congestion exposed without stalling audio? | | |
| [ ] | T-04 | How is controller disconnection/reconnection handled while audio continues? What additional display behavior can be deferred? | | |

### 8. Later DSP questions: resolve or explicitly defer

Record model/representation decisions in [numeric design](numerics.md) and acceptance criteria in [verification](verification.md). These are not permission to add DSP to the first milestone.

| Done | ID | Question to answer | Answer / deferral, dependency and revisit point | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | D-04 | What DSP resource-sharing/pipeline structure will be evaluated, and what model/timing evidence is needed before choosing it? | | |
| [ ] | D-05 | What sample, coefficient, state and accumulator formats, rounding and saturation rules meet stability and headroom needs? | | |
| [ ] | D-06 | What linked-compressor envelope/gain behavior and parameter units are selected? How are left/right gain equality and state verified? | | |
| [ ] | D-07 | What happens to EQ/compressor state during preset changes or bypass transitions? What click/transient acceptance criteria and evidence are needed? | | |
| [ ] | D-08 | What response/latency/overload criteria apply to each modeled processing increment, and which configuration defines the default chain? | | |

### 9. Ownership, integration and planning exit

Record assignments in [ownership](ownership.md), dependencies in [roadmap](roadmap.md) and acceptance in [verification](verification.md).

| Done | ID | Question to answer | Answer / evidence or blocker | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | I-01 | Who owns parameter CDC/publication, audio-side activation and coherent telemetry crossing? Who reviews each interface? | | |
| [ ] | I-02 | Who owns the first top-level integration and which independently testable blocks must each collaborator deliver? | | |
| [ ] | I-03 | Which normal/fault walkthroughs establish readiness: framing, deadline miss, D-01/D-02/D-03, incomplete C, lost ACK, duplicate commit, resets and clock restart? | | |
| [ ] | I-04 | Which required diagrams/contracts and executable tests belong to the next increment? Who provides reproducible build/programming commands and records evidence? | | |
| [ ] | I-05 | Which remaining questions block the first increment, which have bounded experiments, and which are explicitly deferred with an owner and revisit point? | | |
| [ ] | I-06 | Does the roadmap need re-estimation after tonight's scope and hardware/clock findings? What is each person's next task? | | |
| [ ] | I-07 | Who reconciles this planning branch with An's merged kickoff and corrects its CI formatting errors? See [integration follow-up](development.md#integration-follow-up) | | |
| [ ] | I-08 | Does the ownership wording "stereo FIFOs" describe only an area of responsibility, or a selected mechanism? Reconcile it with the still-open topology without silently choosing hardware | | |

Planning exit for the first increment: both can explain its audio/control boundary; critical hardware/clock evidence is available or explicitly blocked; relevant interfaces have reviewed ownership, timing/reset/fault contracts; D-01/D-02/D-03 have a credible proposed enforcement and acceptance scenarios; and remaining work has explicit owners/dependencies. Marking this worksheet complete is not evidence of working audio, synthesis, timing closure or hardware validation.
