# ANIMA — Planning & Design

Design baseline: October 23, 2026. Owners: Robel Yaee and An Tiet. This is the single design/requirements document; [Implemented & Verified](implemented.md) records what actually exists. **Selected** means a design requirement, **proposed** needs agreement/evaluation, **open** needs an answer, and **deferred** is outside the current increment. None means hardware acceptance.

## Contents

- [System and scope](#system-and-scope)
- [Hardware and connections](#hardware-and-connections)
- [Clock architecture](#clock-architecture)
- [Stereo bypass contract](#stereo-bypass-contract)
- [Reset and recovery](#reset-and-recovery)
- [Diagnostics and user interfaces](#diagnostics-and-user-interfaces)
- [DSP and numeric design](#dsp-and-numeric-design)
- [Control and preset publication](#control-and-preset-publication)
- [Acceptance plan](#acceptance-plan)
- [Ownership and delivery](#ownership-and-delivery)
- [Open decisions](#open-decisions)
- [Source register](#source-register)
- [Design history and contribution credit](#design-history-and-contribution-credit)

## System and scope

The [planned system diagram](../README.md#planned-system) separates audio, control and observations. Audio order: stereo line source → Pmod I2S2 ADC → I2S RX → coherent stereo frame → input gain → five biquads per channel → stereo-linked compressor → output gain/saturation → coherent stereo frame → I2S TX → DAC → powered speakers/amplifier.

The FPGA executes audio. The ESP32/browser requests changes over UART; Wi-Fi carries no audio. Browser controls and compact read-only VGA status are both required in the finished system. VGA follows bypass/EQ; it is not optional. FFT is a stretch goal; wireless audio streaming and custom PCBs are deferred.

**First milestone, agreed October 6:** stereo bypass, RX → paired frame transport → TX, with no DSP. Planning is agreed; implementation/acceptance are outstanding. An's independent UART work is not a dependency for the audio-bypass milestone. Recording a design does not authorize unrequested RTL/firmware implementation.

Before coding each increment, resolve its architecture, high-level interfaces, ownership, widths, signedness, units/scaling, packing/order, numeric conversions, data lifetime, handshakes, clock/reset ownership, deadlines and faults. Code-local FSM/register/mux organization can be chosen during coding. Later DSP/control formats may remain explicitly deferred while implementing bypass.

## Hardware and connections

### Inventory and applicability

| Item | Quantity | Status / use |
| --- | --- | --- |
| Digilent Basys 3 | 1 | D.1 reported by Robel; received October 14, reported October 15. D.1 schematic SRC-008; older rev. C manual SRC-001 needs applicability review |
| Intended Digilent Pmod I2S2, 410-379 | 1 | Not yet purchased, reconfirmed October 15. [Candidate Amazon listing B0CLLXNPTG](https://www.amazon.com/dp/B0CLLXNPTG) could not be retrieved; manufacturer/model, ADC/DAC, revision and pinout unverified |
| ESP32 DevKit V1 / ESP32-WROOM-32 | 1 | Designation/module confirmed October 8. Dev-board vendor/revision, pin count, USB-serial device, schematic and firmware framework/version open |
| Stereo 3.5 mm TRS male-to-male cables | 2 | Separate input/output cables; each carries both channels |
| Stereo line source | 1 | Computer/player/phone with suitable output or dongle |
| Powered speakers or amplifier | 1 | Suitable line input; verify levels/loading |
| USB data/power/programming cables | 1 per board | Match actual connectors |
| 3.3 V-compatible jumpers / Pmod extension | As needed | Verify orientation, grounding and power sequencing |
| Development computer | 1 per person preferred | Vivado, Python, simulator and selected ESP32 tools |

Multimeter, suitable logic analyzer, oscilloscope and audio capture equipment improve diagnosis. Record available instruments/limits before setting hardware acceptance tolerances.

### Reserved board connections

Selected: reserve the full 12-pin JA for audio. Mapping uses **SRC-008 sheet 6** and **SRC-002 J1**, not just the rev. B master XDC. This is a connection plan, not implemented constraints or electrical validation.

| Function | Board connection | FPGA package pin | FPGA direction |
| --- | --- | --- | --- |
| 100 MHz reference | CLK100MHZ | W5 | Input |
| DAC MCLK | JA1 / Pmod J1.1 | J1 | Output |
| DAC LRCK | JA2 / Pmod J1.2 | L2 | Output |
| DAC SCLK | JA3 / Pmod J1.3 | J2 | Output |
| DAC serial data | JA4 / Pmod J1.4 | G2 | Output |
| ADC MCLK | JA7 / Pmod J1.7 | H1 | Output |
| ADC LRCK | JA8 / Pmod J1.8 | K2 | Output |
| ADC SCLK | JA9 / Pmod J1.9 | H2 | Output |
| ADC serial data | JA10 / Pmod J1.10 | G3 | Input |
| Audio-reset request | Center button | U18 | Input |
| Diagnostic clear | Down button | U17 | Input |
| Sticky audio fault | LED0 | U16 | Output |

JA positions 5/11 are ground; 6/12 are 3.3 V. Check actual module, voltage and orientation before connecting. ADC slave mode uses JP1's ground-side SDOUT pulldown per SRC-002; physical jumper orientation remains an arrival check. Coordinated clocks go to separate ADC/DAC pins; do not externally tie FPGA outputs together. JB/JC and UART pins are unallocated.

ESP32 integration must address safe GPIOs (straps, flash/PSRAM and boot output), common ground, voltage compatibility and back-powering with one board off. Third-party pinouts do not verify this exact board's wiring. No live wiring/programming is established here.

## Clock architecture

### Manufacturer constraints

Source IDs resolve to revisions and exact locators in the [source register](#source-register).

| Source | Supported requirement / ANIMA implication |
| --- | --- |
| SRC-001 / SRC-008 | Basys reference 100 MHz at W5, clock-capable input; D.1 schematic names IC9 DSC1033CC1-100.0000T. Clock resource/routing rules still apply |
| SRC-002 | Separate ADC/DAC MCLK/LRCK/SCLK; JP1 selects ADC mode through SDOUT. Do not drive ADC clock outputs if configured as master |
| SRC-004 | CS5343 single-speed slave, 4–54 kHz: MCLK/Fs 256/384/512/768; SCLK/Fs 64 at 256/512, 48 or 64 at 384/768. At 48 kHz master mode supports those MCLK ratios with 64 SCLK/frame. 24-bit I2S, one-bit MSB delay; mode sampled at startup |
| SRC-005 | CS4344 at 48 kHz supports MCLK/Fs 256/384/512/768/1024. MCLK/LRCK/SCLK synchronous, no prescribed mutual phase. External SCLK supports 24-bit I2S on rising edges. Internal SCLK at 256/512/1024 is 32 Fs and only 16-bit I2S. External detection needs 16 rising edges in an LRCK phase; two frames without edges revert to internal mode |
| SRC-006 / SRC-007 | Review MMCM/PLL limits/constraints. Requested and actual Wizard frequencies can differ; fractional feedback/CLKOUT0 dividers use 1/8 increments. Qualify LOCKED and reset/reacquire after lock loss |
| SRC-015 | Schematic oscillator code S=1 specifies ±50 ppm, temperature code C. Source tolerance for named part, not fitted-part or frequency measurement |

Common ADC/DAC ratios at nominal 48 kHz: 256/384/512/768 Fs, arithmetically 12.288/18.432/24.576/36.864 MHz. A 64 Fs SCLK is 3.072 MHz. Supported ratios do not prove FPGA generation/timing closure. Consulted ADC datasheet is marked Draft; Pmod manual remains unavailable.

### Selected topology and first-build target

Robel selected FPGA-generated coordinated MCLK/SCLK/LRCK, ADC slave and DAC external-SCLK mode. RX/frame transport/DSP/TX use **one internal processing domain with enables**. External serial clocks still exist. Board-reference clock supervision is separate; UART/control/VGA domains remain open. [Editable clock-ownership diagram](diagrams/audio-clock-ownership.mmd).

A common domain simplifies handoffs and avoids internal audio-frame CDC. A separate DSP domain could decouple processing frequency but needs coherent crossings, reset/flush coordination and buffering analysis; it is not selected. Related clocks need timing analysis and are not automatically asynchronous. Async FIFO provides safe CDC, not correction of sustained rate mismatch. Independently synchronizing sample/coefficient bits does not preserve words. A later educational async-FIFO demonstration is only a proposal with endpoints/acceptance open.

Robel approved the October 15 probe as the **first bypass-build target**, subject to implementation checks:

| Quantity | Target / arithmetic from Wizard settings |
| --- | --- |
| Reference | Nominal 100.000 MHz |
| MMCM input divider / multiplier / CLKOUT0 divider | 1 / 7.250 / 7.375 |
| Processing | Approximately 98.3050847458 MHz |
| MCLK = processing / 8 | Approximately 12.2881355932 MHz, 256 Fs |
| SCLK = processing / 32 | Approximately 3.0720338983 MHz, 64 Fs |
| Stereo rate = processing / 2048 | Approximately 48000.529661 Hz |
| Error from 48 kHz | +11.034605 ppm, excluding oscillator tolerance |
| With schematic part's ±50 ppm | Approximately 47998.130–48002.930 Hz, −38.966 to +61.035 ppm from 48 kHz |

These are calculations/configuration, not measured frequency, jitter or routed timing. Earlier 98.304 MHz is the nominal arithmetic target; evaluated output is approximate. Actual parts, PFD/VCO/divider legality for the instantiated design, resources/routing, phase/duty/jitter requirements, external-clock realization and setup/hold remain acceptance gates. Do not substitute unchecked fabric clocks or alternating bit periods. Tool/probe reproduction is in [Implemented & Verified](implemented.md#vivado-clock-configuration-evidence).

### Serial-timing block contract

October 22, 2026: [anima_serial_timing](../rtl/audio/anima_serial_timing.v) implements this fixed timing contract. Component lint/simulation evidence and its limits are recorded in [Implemented & Verified](implemented.md#serial-timing-component). Separate RX, queue, scheduler (owning TX waiting storage) and TX blocks remain the selected partition. The first implementation review targets a simulated bypass core; physical clock supervision, I/O constraints and board integration follow. Diagnostic counters will live in the audio domain with a lifetime independent of data flush/reset; reference-side clock-loss evidence must survive until recovery. Simultaneous RX/TX watchdog expiry counts one coalesced stall incident and requests one warm reset.

The timing block has one supported configuration: 8 processing cycles/MCLK, 32/SCLK, 1024/channel slot and 2048/stereo frame. These are cycle ratios, not physical clock validation. Internal logic uses audio_clk and enables; external serial outputs are not internal clock domains.

| Port | Direction / width / representation | Meaning |
| --- | --- | --- |
| audio_clk | Input, one bit | Processing clock supplied by the testbench; eventual qualified clock wrapper is separate |
| reset_n | Input, one bit, active low | Hard timing reset: asynchronous assertion, externally synchronized release; never driven by a normal warm audio reset |
| phase_cycle | Output, unsigned 11 bits | Phase 0–2047 of the processing edge about to execute; increments once per active rising edge and wraps to zero |
| mclk / sclk / lrck | Outputs, one bit each, registered | Levels installed on the upcoming edge: low/high for 4/4 cycles, 16/16 cycles and 1024/1024 cycles respectively |
| sclk_rise_ce | Output, one bit, combinational | High before edges at phase 16, 48, 80, ...; authorizes same-edge capture |
| sclk_fall_ce | Output, one bit, combinational | High before edges at phase 0, 32, 64, ...; authorizes same-edge launch |
| left_boundary_ce | Output, one bit, combinational | High before phase-zero edge; inclusive frame-selection deadline |
| slot_bit | Output, unsigned 5 bits, combinational | Position 0–31 within the upcoming channel slot; tail at 0, payload at 1–24, padding at 25–31 |
| right_slot | Output, one bit, combinational | Upcoming channel: zero left, one right |

All registers and outputs are zero during hard reset; event enables and metadata are masked while reset_n is low. First post-reset phase zero initializes low serial levels; it is not guaranteed to be a physical falling transition. Subsequent phase-zero edges are ordinary frame boundaries. Full-system cold qualification remains required before capturing audio.

Pre-edge visibility is part of this interface. At a rising processing edge whose pre-edge phase is p, consumers sample that phase's enables/metadata and serial pins are registered for p. After nonblocking updates, phase_cycle describes the next edge. A registered enable produced after the edge is too late to authorize a transfer on that same edge.

| Pre-edge phase | Event |
| --- | --- |
| 0 | Left boundary / SCLK launch; previous-word tail |
| 32 / 48 | Left MSB launch / capture |
| 1024 | Right boundary / SCLK launch; previous-word tail |
| 1056 / 1072 | Right MSB launch / capture |
| 1808 | Right LSB capture; next left selection is 240 processing cycles away |
| 2047 → 0 | Phase wrap; next left boundary follows |

The staged timing bench checks counting first, then registered clocks, then enables/metadata, then all together. This is component verification, not completed bypass acceptance or the five-minute audio regression. RX-to-queue ingress is a nonbackpressurable complete-pair event (accept or whole-pair overflow rejection); the stored queue head uses the selected stable valid/ready interface.

## Stereo bypass contract

### Serial format and paired data

Selected nominal 48 kHz, signed two's-complement 24-bit samples, MSB first, two 32-bit slots / 64 SCLK periods per frame. LRCK low left, high right. Transfer only complete **L[n]/R[n]** from one input interval, never partial/mixed-index pairs.

TX changes data on SCLK falling edges; RX captures rising. Change LRCK on a falling edge, launch new channel MSB on the next falling edge, capture it on the following rising edge. Preserve the one-bit I2S lead (SRC-012 §§3.1–3.2); identity follows the delayed MSB, not the bit present at LRCK transition. Opposite edges give nominal half-cycle separation, not guaranteed setup/hold: include converter delays, board skew, duty cycle and routed constraints.

After each 24-bit LSB, TX sends zeros until next MSB; no sign-extension padding. Of 32 periods between LRCK transitions, first is the preceding word's tail, then 24 new payload bits and seven trailing periods. The eighth post-LSB zero is across the next LRCK transition before the following MSB. RX excludes padding. See SRC-012 §6.1 / Figure 5 and codec timing sources.

### Receiver block contract

The [I2S receiver](../rtl/audio/anima_i2s_receiver.v) uses separate signed 24-bit L/R assembly registers. The registered complete-pair event is an ingress event to the separate RX queue, not its downstream valid/ready interface. No ready input can pause the ADC or suppress frame-ID advancement.

| Port | Direction / width / representation | Contract |
| --- | --- | --- |
| audio_clk | Input, one bit | Same processing domain as timing, reset application and queue ingress |
| reset_n | Input, one bit, active low | RX hard reset: asynchronous assertion, externally synchronized release; may remain asserted while timing runs during future cold qualification |
| warm_reset_apply | Input, one bit, active high | Shared pre-edge reset action, qualified at the left boundary; clears RX data/IDs and allows fresh frame-zero assembly from that boundary |
| left_boundary_ce / sclk_rise_ce | Inputs, one bit each | Pre-edge events from the selected serial-timing block |
| slot_bit / right_slot | Inputs, unsigned 5 bits / one bit | Upcoming slot position 0–31 and channel 0 left / 1 right |
| adc_sdata | Input, one bit | ADC serial data sampled on processing edges with sclk_rise_ce; physical related-clock I/O timing still requires constraints/validation |
| left_sample / right_sample | Outputs, signed 24 bits each | Assembly values; meaningful as a complete pair only with pair_complete at the receiving edge |
| frame_id | Output, unsigned 32 bits | Completed pair's snapshotted ID; reset to zero, modulo-2^32 advancement for every complete pair regardless of queue acceptance |
| pair_complete | Output, one bit, registered | One-processing-cycle completion event; the queue samples the complete payload/ID at E+1 |

Only capture slot positions 1–24 on sclk_rise_ce. Position 0 belongs to the preceding word; padding 25–31 is ignored. After hard-reset release, ignore input until the first eligible left boundary, then collect L and R from that whole interval. This interface does not implement the cold guard: the future supervisor must qualify/release the RX reset before the selected start edge. A warm reset clears partial/published data, completion and ID state without resetting serial timing; its boundary starts fresh frame-zero capture.

On E, the final right bit enters the R register, pair_complete is registered high, frame_id snapshots the current ID and the next ID advances. On E+1, the queue sees the completed L/R and their snapshotted ID before pair_complete clears. The next serial payload starts later, so no additional output sample bank is needed for this fixed ingress contract. Values outside the completion event may be partial and have no stalled valid/ready lifetime. The queue copies an accepted pair or rejects it whole on E+1; it owns any storage needed for downstream backpressure. Of the 240-cycle capture-to-selection window, one cycle is used before queue ingress, leaving 239 to the next boundary before further queue/scheduling work.

### Custom valid/ready interface

No AXI interface is selected. Each transaction carries these fields together:

| Field | Width / representation | Meaning |
| --- | --- | --- |
| left | Signed 24 bits | L[n] |
| right | Signed 24 bits | R[n] |
| frame_id | Unsigned 32 bits | Input interval identity |
| valid / ready | One bit each | Complete pair available / receiver acceptance |

Raw stereo audio is **48 bits**, excluding metadata; bypass transaction data **80 bits**, excluding handshake. Preset metadata is deferred to DSP/control and distinct from frame ID.

Transfer exactly once on each processing rising edge with valid and ready. While valid high / ready low, hold valid and all 80 bits until accepted or defined reset flush. Acceptance transfers ownership, not a promise of playback. Receiver can accept stale data for discard; sender cannot withdraw stalled data when its deadline passes. Internal backpressure cannot pause ADC/DAC or serial clocks.

### Storage and simultaneous transfers

| Storage | Initial depth | Supported build-time depths | Capacity accounting |
| --- | --- | --- | --- |
| RX complete-pair queue | 2 | 1, 2, 4, 8 | Includes presented head; excludes partial assembly |
| TX waiting-pair storage | 1 | 1, 2, 4, 8 | Additional to RX; excludes current serialized pair |

Derive dependent widths/counts; reject unsupported depths until contract/tests extend them. Parameterization does not imply arbitrary formats/clocks/combinations or runtime resizing. Document units/default/legal relationships for new parameters. Two RX entries hold 96 raw audio bits plus metadata. Stall tolerance depends on occupancy/arrival phase, not capacity alone.

Full RX [A, B] can dequeue A and enqueue complete C on the same edge → [B, C], no overflow. If no space remains after an **actual** same-edge dequeue, reject incoming whole pair and count overflow; never overwrite stalled head. Preserve order.

TX can promote a waiting pair and accept eligible replacement on the same boundary without artificial backpressure. Empty waiting storage can accept expected data exactly on its deadline into current serialization without artificial silence. Never overwrite current output. For bypass, admit only data due for the next unfilled output slot to TX waiting; future pairs stay upstream, stale pairs transfer/discard, due data with reserved waiting slot is backpressured. Larger depths do not permit arbitrary future prefetch or change delay. Register/FSM organization remains code-local.

### RX frame queue block contract

The [RX frame queue](../rtl/audio/anima_rx_frame_queue.v) stores complete pairs before presenting them downstream; no empty-queue same-edge pass-through is selected. DEPTH is an integer build-time entry count, default 2, with only 1/2/4/8 supported. Storage entries are exactly 80 bits packed internally as frame_id[79:48], left[47:24], right[23:0]. Counter and pointer widths derive from DEPTH, including depth 1; unsupported depths cause an elaboration error.

| Port | Direction / width / representation | Contract |
| --- | --- | --- |
| audio_clk / reset_n | Inputs, one bit each | Processing clock and active-low hard reset, with asynchronous assertion and externally synchronized release |
| warm_reset_apply | Input, one bit | Shared synchronous flush, with priority over enqueue, dequeue and overflow |
| pair_complete | Input, one bit | Nonbackpressurable receiver offer sampled on ingress edge Q = E+1 |
| in_left / in_right | Inputs, signed 24 bits each | Complete offered stereo samples |
| in_frame_id | Input, unsigned 32 bits | Offered pair identity; copied opaquely without renumbering or deadline decisions |
| out_valid / out_ready | Output / input, one bit each | Stored head available / downstream acceptance on a processing rising edge |
| out_left / out_right | Outputs, signed 24 bits each | Oldest stored pair; stable with out_valid while stalled |
| out_frame_id | Output, unsigned 32 bits | Identity belonging to the presented samples |
| overflow_event | Output, one bit, combinational | Visible before an edge rejecting an incoming pair: active and pair_complete and full and no actual same-edge dequeue |

An offer accepted at Q first transfers downstream at Q+1 when ready; its head becomes visible after Q. With ready low, valid and all 80 bits remain stable until an actual transfer or reset flush. Full dequeue/enqueue retains occupancy and replaces the departing entry, including at depth 1. Full without a dequeue rejects only the incoming pair and emits overflow; it never overwrites the stalled head. Consecutive rejected offers generate an event on each rejecting edge. No queue input stalls or renumbers the receiver.

Hard reset and warm flush empty the queue; no stale payload is visible or valid after either reset. Outputs are zero when invalid. Logical flush invalidates storage; it does not require clearing every memory bit. Both resets mask transfers and overflow while asserted. The separate diagnostic consumer will sample overflow_event on the rejection edge, increment its saturating counter and retain sticky fault evidence independently of audio flush. The queue does not implement that counter, LED, stall watchdog or an automatic overflow reset.

### Frame scheduler block contract

The scheduler owns TX waiting storage; implementation stays on feat/frame-scheduler. TX_WAIT_DEPTH is a build-time integer, default 1, legal 1/2/4/8. Under the selected next-unfilled-slot policy at most one pair may be reserved; larger settings do not enable future prefetch and require no additional physical entries in bypass. The waiting register holds two signed 24-bit samples; its unsigned 32-bit identity is implicit in the expected schedule counter.

| Ports | Representation and timing |
| --- | --- |
| audio_clk / reset_n | Same processing clock; asynchronous hard-reset assertion, externally synchronized release |
| warm_reset_apply / left_boundary_ce | One-bit pre-edge shared flush / boundary enables; flush wins |
| in_valid / in_ready | One-bit pair handshake; all input data held until transfer or reset |
| in_left / in_right / in_frame_id | Signed 24-bit samples and unsigned 32-bit identity, matching RX queue |
| select_ce | One-bit pre-edge boundary strobe; TX must sample the whole selection on that edge, with no ready/backpressure |
| select_real | One bit; selected payload is real audio, otherwise whole-pair zero |
| select_left / select_right | Signed 24-bit selected samples, zero outside real selection; combinational transaction payload, not current serialized storage |
| select_frame_id | Unsigned 32-bit due ID on a runtime boundary, zero otherwise; meaningful with select_real for real samples |
| underflow_event / late_discard_event | One-bit pre-edge missing-runtime-pair / accepted-late-pair events for separate diagnostics |
| ambiguous_id_event | One-bit stream-contract violation, not a sixth diagnostic counter; integration must assert its absence, never authorize this pair |
| waiting_nonempty / waiting_progress | One-bit pre-edge occupancy / actual boundary promotion observations for the TX-waiting watchdog; excludes current serialization and empty-slot direct acceptance |

First left boundary after hard reset starts capture interval zero and selects intentional silence without underflow. Subsequent boundaries select expected IDs 0, 1, ... modulo 2^32. A warm reset at a left boundary selects intentional zeros, empties waiting storage and starts fresh capture zero; the following boundary expects zero. The external cold supervisor must hold/reset the data path through qualification; it is not implemented by this block.

Between boundaries, admit the expected ID when no pair is reserved; duplicates of a reserved ID remain backpressured. At a boundary, promote a reservation before deciding whether an incoming pair reserves the next slot. Compare incoming ID against that next unfilled admission ID: due can enter if space exists, late transfers/discards, future and exactly half-range stay upstream. Thus promotion can accept next-ID replacement, while an empty boundary accepts its due pair directly. A missed slot still advances the schedule; a pair arriving one clock later is discarded. No payload is replayed to catch up. Ambiguous input raises the violation signal; its presence must fail the integrating simulation assertion. Neither stale discard nor a future/ambiguous offer suppresses underflow for an unfilled deadline.

Hard reset masks all events and selection immediately. Warm flush masks transfer/fault events but retains the boundary selection strobe with zero payload, allowing TX to load silence. TX owns the current serialized pair and must capture this pre-edge transaction. The serializer and watchdogs are integrated in the core described below; retained-age proof remains pending; diagnostic storage is now connected as described below.

### I2S transmitter block contract

The [transmitter](../rtl/audio/anima_i2s_transmitter.v) owns the current serialized pair, separate from scheduler waiting storage. It has no valid/ready backpressure, queue, sample conversion, frame counter or tunable serial format.

| Ports | Representation and timing |
| --- | --- |
| audio_clk / reset_n | Processing clock; asynchronous active-low hard-reset assertion and externally synchronized release |
| warm_reset_apply | One-bit shared synchronous flush, qualified at the left boundary upstream; priority over selection/launch |
| select_ce | One-bit pre-edge scheduler boundary transaction, asserted every active left boundary; never asserted elsewhere |
| select_left / select_right | Signed 24-bit whole selected pair; scheduler supplies zero for startup, reset or missing data |
| sclk_fall_ce | One-bit pre-edge launch enable from serial timing |
| slot_bit / right_slot | Unsigned five-bit position 0–31 and one-bit channel, shared timing metadata |
| dac_sdata | One-bit registered serial output; asynchronously zero on hard reset, otherwise changes only on authorized falling-edge launches or shared warm flush |

Capture both samples together on select_ce. Current-pair registers remain unchanged while serializing, even if scheduler inputs change. Slot position 0 launches zero; positions 1–24 launch sample bits 23–0, left then right, on SCLK falling edges. Positions 25–31 and the following position 0 launch zero, including for negative samples. Hold serial output on all other processing edges, including SCLK rising/capture edges. The boundary capture and slot-zero launch can share an edge: no new sample bit is needed until the next falling edge, so nonblocking pair-register updates introduce no MSB delay.

Warm application clears both current samples and data output on its boundary; shared timing keeps running. Hard reset clears samples/data immediately. Missing/extra selection strobes are interface violations, not a serializer retry or underflow policy; the scheduler owns the mandatory per-boundary real-or-zero selection. Cold qualification, physical pin constraints and clock-loss handling remain external. The first-build serial format is fixed here; extending widths/slots would require coordinated timing/RX/scheduler/TX and test changes.

### Frame IDs, deadlines and late data

Advance ID for **every complete aligned pair**, including overflow rejection; preserve gaps. Cold-qualification ignored pairs consume no IDs. Audio reset flushes all data and restarts IDs **and playback schedule at zero**; controller reconnect does not. External reset epoch reporting is deferred.

Compute `(received - expected) modulo 2^32` and interpret as signed two's-complement: zero due, positive future, negative late, assuming true separation strictly below 2^31 intervals. Exactly half-range is ambiguous, violates stream contract, must fail an assertion and cannot authorize playback. Verify wrap and retained age.

Input pair n plays in the **next stereo output slot**, while RX receives n+1. Select whole pair at left LRCK boundary. Expected valid/ready transfer on its scheduling processing edge is on time; launch left MSB one SCLK period later. Missing expected pair → whole signed-zero pair plus underflow, clocks/alignment preserved. Stale/future data cannot substitute. Resume real data at whole-pair boundary when its expected data exists.

Continuously drain stale heads by receiver acceptance/discard between boundaries; do not replay late data or increase delay to catch up. Support one accepted pair per processing cycle when eligible; expose RX enqueue within one processing cycle. Throughput depends on **initiation interval**, not latency alone; budget both channels, shortest frame, stalls and drain work.

### Edge budget and progress bound

[Editable edge-budget diagram](diagrams/bypass-edge-budget.svg) is an ideal 50% duty, aligned-clock study, not measured pin timing. t=0 is R[n] LSB capture; LSB launch was −0.5 Tbit. Next left boundary +7.5 Tbit, MSB launch +8.5, DAC capture +9.

| Event | Exact 48 kHz / 3.072 MHz baseline | Processing periods at /32 SCLK |
| --- | --- | --- |
| Left boundary / selection | 2.441406 µs | 240 |
| Left MSB launch | 2.766927 µs | 272 |
| Left MSB capture | 2.929688 µs | 288 |

Approximate first-build selection/launch are 2.441379/2.766897 µs with nominal 100 MHz reference. These windows include assembly, selection, preparation, delays and margin. DAC capture gives no extra preparation time after TX launch. Illustrative 100 MHz / 48 kHz averages 2083.33 cycles/frame; **100 MHz is not selected processing**. First-build ratios give 2048 cycles/frame. Slot displacement is not full codec/acoustic latency.

Monitor each nonempty RX and TX-waiting queue independently during active operation. **2048 processing cycles without dequeue/promotion progress** counts one stall timeout, latches warm reset for next left boundary. Actual transfer, including stale discard, on threshold edge wins and resets timer. Empty/startup/reset queues excluded. Coalesce requests until reset; reset highest priority. Watchdog cannot depend on UART/browser or stalled handshake.

Verify retained-frame age bound `(RX depth + TX-waiting depth + 2)` frame periods, at most 18 supported, far below 2^31. Clock loss flushes before numbering restarts. Capacity changes do not extend deadlines, add playback delay or correct sustained rate mismatch. Later-slot fallback needs coordinated schedule/late-policy/test revision, not automatic override.

### Bypass core and progress watchdog interfaces

The [bypass core](../rtl/audio/anima_bypass_core.v) connects serial timing, reset control, RX, complete-pair queue, scheduler-owned TX waiting storage, serializer and the [watchdogs](../rtl/audio/anima_audio_watchdogs.v). RX_DEPTH defaults to 2 and TX_WAIT_DEPTH to 1, both legal 1/2/4/8; existing component elaboration guards reject unsupported values. It takes an already-generated processing clock. No DSP, ADC pacing, asynchronous FIFO or UART/control dependency is introduced.

| Core ports | Representation and meaning |
| --- | --- |
| audio_clk / reset_n | Processing clock and global audio active-low hard reset, asynchronous assertion and externally synchronized release; resets serial timing/data, not diagnostic storage |
| data_reset_n | Separate one-bit active-low data qualification reset, externally synchronized release; ANDed with reset_n for data blocks, reset controller and watchdogs. Hold low during future cold qualification while reset_n allows serial clocks to run |
| reset_request | Qualified one-bit audio-domain request; raw button conditioning and stopped-clock supervision remain upstream |
| adc_sdata / dac_sdata | One-bit serial input / registered serial output |
| mclk / sclk / lrck | Registered serial waveforms from fixed-ratio timing; unaffected by data reset or warm recovery |
| warm_reset_apply / reset_pending | One-bit shared pre-edge flush / registered pending observation |
| overflow_event / underflow_event / late_discard_event | Existing one-bit pre-edge diagnostic events |
| stall_timeout_event | One-bit registered event, high for one processing cycle after a threshold edge; simultaneous RX/TX expiry emits one event |
| ambiguous_id_event | One-bit stream violation indication for integration assertions; not an additional error counter |
| frame_select_ce / frame_real / frame_id | One-bit selection transaction / real-sample flag and unsigned 32-bit selected identity; meaningful at the selection edge, not a frozen telemetry packet map |
| diagnostic_reset_n / diagnostic_clear / recovered_clock_loss_event | Independent initialization reset / qualified clear / supervisor event, all one bit; detailed lifetime below |
| underflow_count / overflow_count / late_discard_count / stall_timeout_count / recovered_clock_loss_count / fault_sticky | Five unsigned 32-bit counts and one-bit sticky fault level; unaffected by core audio reset paths |

Each watchdog uses an unsigned 11-bit count and the fixed first-build threshold of 2048 processing edges. Count an edge only when that queue was nonempty before the edge and made no actual dequeue/promotion. The first such edge counts one; expiry is on the 2048th. Empty or actual progress clears that queue's timer; progress on the threshold edge wins. RX progress includes stale acceptance/discard. TX progress means promotion of a stored pair, not enqueue, current serialization or direct empty-slot selection. Hard reset or shared warm application clears both monitors with priority; startup/data reset leaves their queues empty or held reset.

A threshold edge registers recovery_request and stall_timeout_event. The registered request is high until warm application; no second stall event occurs during that pending incident, even if the other queue later expires. The reset controller observes the request beginning on the following processing edge and applies the shared flush at the first subsequent left boundary. If expiry itself occurs on a left-boundary edge, recovery occurs at the next left boundary, not retroactively on the expiry edge. This registered staging avoids a combinational loop through reset-masked valid/ready. Clocks keep running, reset flushes all audio ownership and numbering, and fresh frame zero is eligible for the following output slot. Diagnostic consumers sample the registered stall event on its high cycle; their counters/LED must retain evidence independently of audio reset.

Watchdog timeout is tied to the selected fixed 2048-cycle timing frame, not a runtime setting. Changing timing ratios requires coordinated review of timing, watchdog threshold/widths, budgets and tests. Board clock generation/qualification, stopped-clock detection, button conditioning and electrical constraints remain outside this core. Diagnostic storage is connected in the increment described below.

## Reset and recovery

### Warm audio reset

With healthy clocks, finish current pair; apply qualified request at next left boundary, including that boundary if request qualifies there. Keep MCLK/SCLK/LRCK running. Reset wins over same-edge transfers/playback: flush partial RX, queues and TX data; reset IDs/schedule; send whole silence. Boundary can start fresh frame-zero capture; play it at following left boundary if complete. No mixed reset epochs/replay.

Synchronize/debounce center button: one qualified press, release rearms, held press no repeats. Exact filter/state implementation is code-local. Preserve diagnostics; do not repeat healthy cold guard.

#### Warm-reset controller interface

The [warm-reset controller](../rtl/audio/anima_warm_reset_controller.v) implements the selected pending-request/left-boundary mechanism. All ports are unsigned single-bit signals; it has no frame payload, FIFO, counter or tunable timing parameter.

| Port | Direction / representation | Contract |
| --- | --- | --- |
| audio_clk | Input, clock | Same processing domain as serial timing and the audio-data consumers |
| reset_n | Input, active low | Hard reset: asynchronous assertion and externally synchronized release; clears pending state and masks application |
| reset_request | Input, active high | Qualified audio-domain request event, normally one processing-clock cycle; raw buttons and asynchronous inputs are conditioned upstream |
| left_boundary_ce | Input, active high | Timing block's pre-edge phase-zero enable, independent of available audio frames |
| reset_pending | Output, registered, active high | At least one sampled request awaits application; requests coalesce while pending |
| warm_reset_apply | Output, combinational, active high | Pre-edge reset action: reset_n and left_boundary_ce and (reset_pending or reset_request) |

An off-boundary request sets pending. On the earliest eligible left boundary, application wins and clears pending. A fresh request on that boundary applies immediately; pending plus another request on the same boundary produces one application, with no extra reset retained. Hard reset abandons pending work. Request sources must stop asserting after their event/application: a level held beyond application can request a later reset again; held-button suppression belongs upstream.

Consumers sample warm_reset_apply on the processing rising edge and give it priority over ordinary data transfers. Do not register application one cycle after the boundary. Timing and diagnostic state must not be warm-reset by this signal. The controller does not itself flush RX/queues/TX, restart IDs, synchronize/debounce buttons, detect watchdog stalls, supervise stopped clocks or perform cold qualification. The bypass core now wires shared data flush and watchdog requests; button conditioning, clock supervision and cold qualification are now implemented in the shell below; physical clock generation and hardware acceptance remain pending.


### Cold start and clock loss

Synchronize reset release per domain; suppress invalid data until qualified. LOCKED is not codec-ready. Configurable initial guard: **nominal 1000 ms after valid codec clocks begin**. Run clocks/framing with zeros, ignore input, then capture frame zero at first left boundary at/after expiry. Derive counter from processing frequency/ms, rounded up.

Guard is a design target, not ready pin. SRC-005 §§4.4–4.5 describe component-dependent VQ ramp plus about 2000 sample periods; SRC-002 shows 10 µF VQ (datasheet ramp example about 420 ms). Confirm actual module/power/settling. No codec reset pin assumed.

Clock-validity loss invalidates immediately; flush before release, independent of a stopped processing clock. Board reference supervises MMCM reset/reacquisition and synchronized release. **Automatic qualified restart** repeats cold guard; validity loss restarts guard. Implement defined inactive pads while unqualified. Absent clocks cannot carry digital silence; quiet analog output during clock/power loss is not guaranteed. Complete reference/power loss needs reinitialization.

ESP32/Wi-Fi/UART loss alone does **not** stop/reset audio or flush frames. Last active settings continue absent valid update/defined audio reset; parameter reset/reconnect remains a later control contract.

## Diagnostics and user interfaces

### Board-control shell and clock supervision

[anima_bypass_control_shell.v](../rtl/audio/anima_bypass_control_shell.v) connects center-button warm reset, down-button diagnostic clear and led0 to the core's sticky fault level. It accepts ref_clk (nominal board 100 MHz), the externally generated audio_clk, initial_reset_n and MMCM LOCKED. mmcm_reset is a request to the external MMCM. This is a logical integration shell, not a complete physical clock generator or accepted board build. Core depth defaults/legal choices are unchanged. Clock loss does not depend on UART, Wi-Fi or software.

[anima_button_event.v](../rtl/common/anima_button_event.v) synchronizes each active-high button through two ASYNC_REG stages, qualifies both press and release, and emits one audio-clock event per press. A held press cannot repeat. At startup or clock recovery, a button must first have a qualified release before arming; commands held during qualification are ignored. Warm reset does not reset this filter. Initial BUTTON_STABLE_CYCLES=983051 is a configurable approximately 10 ms target at the first-build processing rate, not a measured bounce requirement.

[anima_clock_supervisor.v](../rtl/audio/anima_clock_supervisor.v) implements the selected LOCKED-plus-heartbeat policy. A raw LOCKED drop asynchronously invalidates timing/data, while a two-stage release pipeline retains reference-side visibility of a short drop and synchronizes qualification. A toggle every HEARTBEAT_CYCLES audio clocks crosses through two ASYNC_REG reference stages. At least two observed transitions with qualified LOCKED are required before timing release. Missing heartbeat or lock loss requests MMCM reset using the continuing reference clock. The detector checks liveness, not correct sample frequency, jitter or metastability margins.

| Parameter | Initial value / units | Legal relationship / purpose |
| --- | --- | --- |
| BUTTON_STABLE_CYCLES | 983051 audio clocks | Positive integer; derived counter width, at least one bit |
| HEARTBEAT_CYCLES | 64 audio clocks per toggle | Integer at least 4; first-build clocks are near 1:1, not arbitrary-frequency CDC |
| TIMEOUT_REF_CYCLES | 1024 reference clocks without observed toggle | Integer at least 32 and at least 8 times HEARTBEAT_CYCLES; nominal 10.24 µs count plus synchronization/observation latency at 100 MHz |
| MMCM_RESET_REF_CYCLES | 16 reference clocks | Positive integer; initial reset-hold target, not a tool-validated MMCM/reset constraint |
| STARTUP_AUDIO_CYCLES | 98305085 audio clocks | Positive integer; ceil of approximately 98.3050847458 MHz × 1 second; initial qualification target subject to codec/hardware validation |

All timer widths derive from these positive integer cycle counts; invalid relationships fail elaboration. The startup guard begins only after a first high LRCK has been observed, so codec waveforms are already running. Timing continues with zero output during guard; data release is synchronized after the full guard, and the core waits for its next whole left boundary. Every loss restarts guard. [anima_reset_sync.v](../rtl/common/anima_reset_sync.v) supplies asynchronous assertion/two-stage synchronized release for each receiving clock. Diagnostic initialization reset remains independent of recoverable audio resets.

Loss evidence is latched in the reference domain after clocks have first qualified; absence of a clock before initial qualification does not fabricate a recovered-loss event. Repeated failures/qualification flaps coalesce into the same pending outage until aligned audio restart and diagnostic delivery are complete, as selected by Robel. A four-phase request/acknowledgement crosses stable one-bit levels; the audio-domain event is registered, and acknowledgement follows the edge on which diagnostics consumes it. The mailbox is not reset by audio loss: if audio stops with an unconsumed event high, that event remains until one resumed edge counts it. A pending acknowledgement is not closed while clocks/restart remain invalid. No sample words or diagnostic count buses are independently synchronized.

led0 follows only fault_sticky. Previously counted faults remain visible during an outage. A new clock-loss episode is retained in reference-side loss_pending and becomes a counted/sticky diagnostic after qualified recovery delivery; this design does not promise an immediate new LED transition while audio is stopped. Button filtering and diagnostic storage do not clear loss_pending. Complete reference-clock/power loss still requires reinitialization.

The authored [control XDC fragment](../hardware/constraints/anima_controls.xdc) maps ref_clk W5, center U18, down U17 and LED0 U16 from the existing SRC-008 pin plan and supplemental SRC-014 comparison. It is not a complete board top/constraint set: MMCM/buffers, generated clocks, audio pins, I/O delays, CDC/reset constraints and routed timing remain open implementation/acceptance work. No external code was copied. The default debounce/timeout/reset-hold values are configurable initial implementation targets; changing clock ratios requires revisiting the margins and guard arithmetic.

### Bypass diagnostics

Selected October 15: five unsigned **32-bit saturating** counters, maximum 4294967295, plus one sticky LED.

| Counter | One event means |
| --- | --- |
| underflow | Expected runtime pair missing at selection deadline |
| overflow | Complete incoming pair rejected after same-edge accounting |
| late_discard | Stale pair accepted and discarded |
| stall_timeout | Queue no-progress threshold; recovery requests coalesced until reset |
| recovered_clock_loss | Detected loss episode completes qualified recovery |

Any fault sets LED0; clock-loss detection latches evidence while reference is available for presentation after recovery. Preserve counts/LED across warm reset/recoverable loss; initialize zero at power-up/reconfiguration. Down-button diagnostic clear clears all five/LED without changing audio/IDs/clocks/queues. New event on clear wins: its counter one, LED on, others zero. Multiple classes per edge allowed; sum is not unique lost frames. Intentional startup/reset silence is not underflow. Diagnostics never block audio. Later UART/browser equivalents must retain semantics; wire map open.

### Diagnostic storage block contract

The [audio diagnostics](../rtl/audio/anima_audio_diagnostics.v) implement the selected five counters and sticky fault level. They consume events in audio_clk and have no audio-control outputs, ready/valid handshake or backpressure. Their storage reset is independent of audio timing/data resets.

| Ports | Representation and meaning |
| --- | --- |
| audio_clk | Processing clock; counter/event sampling occurs on its rising edge |
| diagnostic_reset_n | One-bit active-low initialization/reconfiguration reset with asynchronous assertion and externally synchronized release. Do not derive it from ordinary audio reset, data qualification reset or recoverable clock-lock loss |
| diagnostic_clear | Qualified one-bit audio-domain clear action, normally one clock; future board button/UART sources require their own conditioning/arbitration |
| underflow_event / overflow_event / late_discard_event | One bit each; existing pre-edge events, one increment per asserted sampling edge |
| stall_timeout_event | One-bit registered watchdog event; counted on its high cycle, including when warm application happens on that same edge |
| recovered_clock_loss_event | One-bit qualified audio-domain event after one detected loss episode completes recovery; reference-side evidence latch and acknowledged event delivery are implemented in the control shell above; the standalone core still expects a qualified event input |
| underflow_count / overflow_count / late_discard_count / stall_timeout_count / recovered_clock_loss_count | Five independent unsigned 32-bit outputs, zero at initialization and saturating at 0xffffffff |
| fault_sticky | One-bit registered fault evidence for eventual LED0; any of the five event classes sets it, retained until explicit clear or initialization |

Initialization wins over clear/events. Otherwise a clear begins a new diagnostic interval: counters for new events on that edge become 1, others become 0, and fault_sticky becomes the OR of those events. Without clear, each asserted class increments its own counter unless already saturated; no event leaves that counter unchanged and the sticky level remains set. Consecutive high event cycles represent consecutive occurrences. Multiple classes can increment together; counts are not a unique lost-frame total. Fixed 32-bit widths are selected; no runtime width/format is introduced.

The bypass core exposes these diagnostic ports and instantiates the storage separately from its audio resets. Downstream readers must later acquire a coherent status snapshot; these live outputs are not a selected UART/browser wire map. No recovered-clock event is fabricated by data reset, and the current module is not a clock-loss detector or recovery supervisor. Logical LED/button wiring, qualification and the authored control-pin fragment now exist in the shell above; physical implementation/timing validation remains pending.

### Browser, VGA and telemetry

Browser is full control/diagnostics; VGA required compact read-only applied settings/meters/faults. 640×480 procedural drawing/font ROM is planning direction, not verified target. Both use coherent FPGA status; network/display refresh never gates audio. Distinguish requested/pending/applied settings.

Proposed fields: readiness/connection/version, occupancy/high-water, frame/errors, applied generation, levels/clipping/gain reduction. Snapshot contents/units/interval, refresh/drop/coalescing, CDC owner, stale indication, VGA layout, browser framework/transport and reconnect open. WebSockets and SoftAP are proposals. Telemetry may drop/coalesce; reply arbitration must be bounded. Do not assert campus-network incompatibility without checking chosen network/framework.

## DSP and numeric design

Deferred until accepted bypass: input gain → five biquads per channel → stereo-linked compression → output gain/saturation. Independent left/right history for every EQ section, even with shared coefficients. One compressor gain applied to both channels; maximum-channel envelope remains a modeling proposal. Resource sharing/pipeline structure is open; common-domain multiple effects are possible if initiation interval/deadlines are met.

Start with floating-point audio reference, then bit-exact fixed-point model **before DSP RTL**. Candidate formats only: internal samples 32 bits / 27 fractional, coefficients 32 / 29 fractional, state 40 bits, accumulator 80 bits. Not frozen interfaces or implemented model behavior.

For every block specify width/signedness/scaling, intermediates/state, coefficient order, explicit biquad equation/feedback signs, extension/truncation, rounding, saturation/overflow and state reset. Decide user units (Hz/dB/Q) versus quantized coefficients, computation and validation ownership; match quantization to reference version.

Evaluate quantized poles, cascade boost headroom, silence limit cycles, state overflow, full-scale overload, linked dynamics and bypass/preset transitions. Atomic coefficients alone do not guarantee click-free changes. State continuity/reset/smoothing and measurable transient criteria remain open.

## Control and preset publication

### Required consistency and latest pending wins

| ID | Requirement / review state |
| --- | --- |
| D-01 | Both L[n]/R[n] use one preset even if B arrives between processing them. Robel confirmed; An's explicit shared-interface review pending |
| D-02 | A frame using A in EQ also uses A at compression/all later consumers; retain needed values through last use. Robel confirmed; An's explicit review pending |
| D-03 | Latest pending wins, jointly agreed October 6: complete validated C may replace unactivated B; partial/invalid C leaves B eligible. Protect active/in-flight values; never report superseded B as applied |

Editable logical diagrams: [frame consistency](diagrams/frame-preset-consistency.mmd), [pending policy](diagrams/pending-preset-policy.mmd), [snapshot lifetime](diagrams/preset-snapshot-lifetime.mmd). An's [Python model](implemented.md#python-preset-and-frame-model) demonstrates snapshots, not FPGA storage/physical timing.

| Logical role | Required lifetime |
| --- | --- |
| Staging/shadow | Assemble writes; validate completeness/corruption/parameters before publication |
| Pending | Latest complete eligible snapshot; atomic replacement, no partial exposure |
| Activation | Serialize replacement/publication with selection; pin one complete generation per newly admitted frame |
| Protected generations | Keep active/older in-flight values through all last consumers |

Frame 10 uses A, B is pending, complete valid C supersedes B before activation; later eligible frame may use C. Invalid C preserves B. If B already activated, C waits for later activation; B frames retain B. Do not keep admitting work under A once new preset activates; receipt alone is not activation. A generation tag refers to stored values; it does not preserve them.

Physical alternatives remain open: retained snapshots with bounded reuse, capture needed settings with frames, or finish last old consumer before storage reuse. Waiting audio buffers have separate capacity/deadline/overflow rules from pending presets. Receiver-owned transfers are immutable; replacement cannot mutate in-flight data. Define same-event replacement/activation cutoff, finite storage, readiness/delay, generation wrap and superseded reporting before hardware implementation.

### UART and controller contract

Draft: 3.3 V UART, 115200 baud, common ground. Framing, pins, control clock and PC-versus-ESP32 endpoint selection/mux remain open; no binary map selected.

Required: version/identity/status, shadow read/write, validation/commit/bypass, ACK/NACK with request identity/corruption checking, distinct **received** versus **actually applied** reporting. Bad/partial packets cannot change active values. Superseded requests cannot get applied outcomes. Coherent crossing snapshots stay stable through acceptance; independent per-bit synchronization is invalid.

An's proposal covers delimiter/length/max payload/byte order/types/version, CRC and exact coverage, bounded parser/storage, timeout/resync, sequence scope/wrap, retries/duplicates/lost ACK, either-side reset/reconnect. Review UART input synchronization/sampling and baud error. Bound reply/telemetry arbitration without starving audio or replies. Keep credentials out of Git; coalesce slider changes rather than unbounded queues.

At draft 115200 baud and 8N1, arithmetic capacity 11,520 bytes/s per direction before overhead; illustrative 32-byte packet 2.78 ms versus nominal audio frame 20.83 µs. Packet size/8N1 remain proposals, not measured throughput. Publish valid/corrupt/truncated packet bytes and expected replies once agreed; PC endpoint before ESP32 integration.

## Acceptance plan

These are **future checks/proposed targets, not passing results**. Actual checks belong in [Implemented & Verified](implemented.md#checks-actually-performed).

### Stereo bypass acceptance

| Check | Stimulus and pass condition |
| --- | --- |
| Verilator lint / simulation | Record source lists, version/options/assertions. No unexplained warnings, assertion failures or scoreboard mismatches; document accepted waivers |
| Vivado Simulator directed waveforms | Available for later targeted investigation when requested or required; current increments use Verilator only. Do not routinely duplicate regression in both simulators |
| Exact digital bypass | Known zero, signed extremes, positive/negative, alternating, distinct-channel patterns; output matches input pairs bit-for-bit in assigned slots, no loss/duplication/swaps |
| Reproducible randomization | Seeded samples/legal phase-handshake variation, assertions and independent expected-slot scoreboard; initial seeds 1, 42, 2026; retain failing seeds |
| Continuous normal operation | At least 300 seconds simulated audio after startup, zero corruption/loss/duplication/deadline misses/unexpected recovery; drain/check accepted final frames |
| Hardware serial | Measure actual MCLK/SCLK/LRCK/data, format/channel identity/rate/bypass after electrical/constraint review |
| Analog preservation | Repeatable stereo waveform, documented levels, electrical capture/listening. No unexpected swaps/dropouts/corruption; gain/response/distortion tolerances open |
| Acoustic latency | Goal 5 ms signal entry → audible speaker playback. Hard limit, exact input point, mic distance, common time reference, playback setup and tolerances open |

Five minutes means **simulated audio time**, not wall time. Nominal 48 kHz gives 14,400,000 pairs; first-build target about 14,400,159 pairs/300 seconds. Derive duration/count from actual simulation clock; drain final accepted data. Injected-fault tests are separate from normal error-free run. Placeholder commands are not evidence.

Digital equality is exact; converter/speaker recordings need tolerances. Listening cannot prove zero digital errors; simulation cannot establish acoustic latency. [Measurement scope](diagrams/bypass-measurement-scope.mmd). Keep separate digital/electrical delay for diagnosis.

### Required boundary and fault scenarios

| Area | Required observations |
| --- | --- |
| Serial / pairing | Signed payload, polarity, one-bit delay, edges/padding, distinct channels and reset phases; no partial/mixed pair |
| Valid/ready | Stable valid/all 80 bits while stalled; one acceptance per eligible edge; acceptance may mean stale discard |
| Depths | All 16 RX/TX combinations of 1/2/4/8, unsupported rejection, order/occupancy and separate partial/current accounting |
| Same edge | Full RX dequeue/enqueue no false overflow; TX promotion/replacement; empty-slot eligible deadline-edge transfer plays |
| Cutoff | Before/exactly deadline plays; one cycle after late; missing expected data gives whole silence/underflow |
| IDs / retention | Overflow gaps, wrap near 0xffffffff, due/late/future, retained-age bound; half-range never authorizes playback |
| Drain / watchdog | Eligible stale transfer/cycle, RX exposure within cycle; 2048-cycle timeout; threshold progress wins; empty/startup/reset excluded |
| Warm reset | Qualified single press, no held repeat; whole-pair/reset priority, flush/ID zero, healthy clocks/diagnostics preserved |
| Cold / loss | Zero serialization during guard, aligned restart, loss restarts guard, stopped-clock invalidation, one recovered-loss event |
| Diagnostics | Saturation, clear/new-fault collision gives one, simultaneous classes, clear independent of audio, intentional silence excluded |
| Control independence | Disconnect/malformed traffic/telemetry cannot stall/reset/flush audio by themselves |

Use independent I2S source/sink models and expected-slot scoring including injected silent slots. Before physical acceptance verify actual Pmod/JP1/revision, voltage/pins, oscillator, generated clocks, external constraints, routed timing and startup on real hardware.

### Later subsystem verification

| Subsystem | Future checks |
| --- | --- |
| EQ / numeric DSP | Floating/bit-exact comparison, impulse/tones/sweep/silence/noise, signs, quantized stability, headroom, limit cycles, overload/transitions |
| Compressor | Threshold/ratio, attack/release/envelope, equal channel gain, clipping/saturation |
| Presets | B between L/R, A retained after B activation, valid C supersedes B, invalid/partial C preserves B, already-active B retained, activation races/full storage/reset/reconnect |
| UART / web | Truncation, oversized length, bad CRC, unsupported commands/values, timeout, lost ACK/duplicates/retries, resets and congestion |
| Actual CDC | Coherent snapshots, related/asynchronous constraints, stopped clocks/resets/queues; unequal-clock FIFO tests if such a crossing is introduced |
| Release | Reproducible build/program/demo, routed timing and reviewed clock/reset/CDC/I2S constraints |

Proposed later targets: EQ within 0.5 dB of agreed reference over defined range; 30 minutes hardware operation without frame/FIFO errors. Neither achieved nor a substitute for five-minute simulation. Record commit/tools/commands/configuration/levels/instruments/plots/limits; large generated artifacts outside source control.

## Ownership and delivery

### Responsibilities

| Area | Primary owner | Review / boundary |
| --- | --- | --- |
| Audio clocks/reset, RX/TX, paired transport/buffers | Robel | An pins/shared interfaces |
| Gain/EQ/compression/saturation; audio reference/bit-exact models | Robel | An controls; shared vectors |
| ESP32, Wi-Fi/browser | An | Robel parameter meanings |
| FPGA UART/parser/shadow/ACK; PC utility | An | Robel consumption/CDC; shared faults |
| VGA | Shared | An layout/control; Robel meters/clocks/integration |
| CI plumbing | An | Both maintain checks |
| Board integration/release | Shared | Both reproduce final demo |

First bypass integration is **unassigned per Robel**. Whoever takes it claims task before concurrent top-level edits and obtains collaborator review. Block ownership does not assign unanswered crossing/activation boundaries. Robel defines consumption, An transport; agree both sides first.

### Increment sequence

| Increment | Audio / Robel direction | Control / An direction | Exit evidence |
| --- | --- | --- | --- |
| Current design gate | Codec → clock feasibility/reset → stereo contract | Framing/ownership/shadow proposal in parallel | Boundaries reviewed; missing evidence explicitly blocked/assigned |
| Stereo bypass | RX/queues/TX/reset/diagnostics | PC identity/status independently | Bypass acceptance; UART not required |
| Controlled filter | Floating/bit-exact one biquad/channel | Shadow/commit simulated consumer, then audio | Model agreement/coherent activation |
| Five-band EQ | Stereo cascade/headroom | Presets/live controls | Stable measured programmable EQ core |
| Compression | Linked dynamics | Controls/telemetry | Equal gain and verified overload/dynamics |
| Required interfaces | Meters/VGA integration | ESP32/browser/VGA layout | Coherent full controls + local status |
| Qualification | Timing/response/latency | Fault recovery/reproduction | Both reproduce release evidence |

Original 12–14-week estimate at 5–7 hours/person/week is not a deadline; re-estimate after bring-up. An's dependencies: reviewed packet contract → PC identity/status → simulated shadow/commit consumer → real audio integration → ESP32/web → telemetry/usability. Framework/pins/fields resolved for relevant slice. Simulated consumer cannot prove real DSP timing.

**Next teaching/design block:** trace one frame from final ADC right-bit capture through queue acceptance, the 240-cycle selection window, next-slot TX and resets/faults. Turn trace into source lists, independent source/sink models and expected-slot scoreboard when implementation is authorized. An can bring annotated UART packets/shadow proposals for joint review in parallel.

## Open decisions

Working fill-in list: retain prior worksheet IDs; selected bypass answers live above rather than repeated as unanswered. Blank answers mean open. Resolve later choices at their increment, not just to close bypass. Owner entries reflect existing responsibility/review, not new assignment of unanswered boundaries.

| IDs / gate | Question requiring answer/evidence | Owner / review | Answer / evidence / deferral |
| --- | --- | --- | --- |
| H-01, H-03 | Actual Pmod identity/revision/JP1/levels/orientation; rev. C manual applicability to D.1; physical pins | Robel; shared wiring | Before hardware connection/acceptance |
| H-02, H-04 | Exact ESP32 board/USB/schematic/safe GPIO/framework/version | An; Robel integration | UART/ESP32 slice |
| H-05 | Power sequencing/back-power protection and either-board-off behavior | Shared | |
| H-06, C-02 | Legal instantiated clock resources; PFD/VCO/phase/duty/jitter units/budgets, I/O delays/constraints, routed timing/measurement | Robel; shared review | Configuration only; other evidence open |
| C-03, C-04, I-01 | Control/VGA clocks, coherent endpoints/owners, reset/publication/activation/telemetry boundaries | Shared | Common audio domain selected; others open |
| C-05, C-06 | Physical startup/settling/guard, stopped-clock pad/reset implementation | Robel; shared review | Digital policy selected; physical evidence missing |
| F-01–F-06 | Shared frame/queue/reset review, schedule/retained age and timing proof | Robel; An interface review | Component scheduling and short core depth/reset/watchdog evidence recorded; full fault/retained-age and physical timing proof pending |
| P-01 | An's explicit D-01/D-02 review/additional cases | An / Robel | |
| P-02, N-01, N-03 | Snapshot validity, controller/FPGA validation, coefficient computation/reference, quantized stability/headroom | Shared; Robel numerics | Controlled-DSP slice |
| P-03, P-05, P-06 | Activation readiness/boundary/delay, immutable cutoff, same-event C replacement vs B activation | Shared | Python call ordering is not hardware contract |
| P-04, P-08 | Protected generations, last-use/reuse, finite storage/full/backpressure | Shared | Python snapshots do not select storage |
| P-07, U-05, U-06 | Received/pending/superseded/applied outcomes; sequence/generation wrap, lost-ACK/retry/duplicate/reset/reconnect | An proposes; shared review | |
| P-09 | Production startup/default/bypass, DSP state after audio reset, controller reconciliation | Shared | Python bypass/0 dB only model behavior |
| U-01 | PC/ESP32 endpoint count/pins/selection/arbitration/authority | Shared | |
| U-02–U-04, U-07 | Baud/error/framing/delimiter/length/order/version/CRC/coverage, timeout/resync, reply/telemetry scheduling, example bytes | An proposes; shared review | 3.3 V / 115200 draft; no frozen wire map |
| N-02, D-04, D-05 | Numeric units/widths/signs/order, DSP resource schedule/II, state/intermediates/rounding/saturation | Robel proposes; shared review | Candidate formats; beyond bypass |
| D-06, D-07 | Compressor algorithm/units; state/click/transient policy for preset/bypass | Robel; An controls | Modeled DSP increments |
| D-08 | Response/overload/default chain/analog tolerance | Shared | 0.5 dB proposal only |
| T-01–T-04 | Snapshot fields/interval/units/CDC owner/rate/drop, stale/reconnect behavior, VGA/browser layout/framework | Shared; An UI, Robel audio status | Required roles selected; details deferred |
| I-02, I-04 | Claim integration, source lists/build Tcl/XDC/benches/programming/evidence owner per increment | Unassigned integration; shared review | Claim before concurrent top-level edits |
| I-03, I-05 | Normal/fault walkthrough, actual blockers and readiness for next authorized slice | Shared | Acceptance matrix; tests outstanding |
| I-06 | Re-estimate after bring-up; each person's next task | Robel / An | |
| Latency / analog | Entry/playback points, mic distance/setup/instruments, hard limit and analog tolerances | Shared | 5 ms goal, hard limit intentionally open |

Closed administrative items: I-07 old kickoff formatting/branch reconciliation complete; An's outstanding Python work merged. I-08 wording now says frame transport/buffers; no internal async FIFO selected. Physical evidence and shared review remain gates; a recorded plan/passing repo check is not audio acceptance.

## Source register

Stable IDs shared across both documents. Rows record title/publisher, URL, revision/version, exact section/page, ANIMA use, reviewer/date/status. Reviewer/date means register reconciliation, not every source fetched that day; original consultation/failure dates retained. Unavailable/supplementary sources do not establish manufacturer facts. Verify actual applicability before acceptance.

| ID | Title / publisher / URL | Revision / exact locator / ANIMA use | Reviewer / date | Review status |
| --- | --- | --- | --- | --- |
| SRC-001 | [Basys 3 Reference Manual - Digilent](https://digilent.com/reference/_media/basys3:basys3_rm.pdf) | Rev. C, April 8, 2016; p. 1: revision applicability; section 4, p. 6: 100 MHz reference and clock resources. Reconsulted 2026-10-08; reviewer: Robel; physical-board applicability pending | Robel / 2026-10-15 register reconciliation | Consulted; actual hardware/application validation pending |
| SRC-002 | [Pmod I2S2 schematic - Digilent](https://digilent.com/reference/_media/reference/pmod/pmodi2s2/pmodi2s2_sch.pdf) | A.0, January 16, 2018; sheet 1, J1/JP1/IC1-IC3 and C9: connector nets, ADC mode and DAC VQ capacitor. Robel / 2026-10-15: consulted; physical-board applicability pending | Robel / 2026-10-15 register reconciliation | Consulted; actual hardware/application validation pending |
| SRC-003 | [Pmod I2S2 Reference Manual - Digilent](https://digilent.com/reference/pmod/pmodi2s2/reference-manual) | Board operation/jumper cross-check; previous access returned HTTP 403; retry on 2026-10-15 also failed, so not used as evidence | Robel / 2026-10-15 register reconciliation | Pending access; not used as evidence |
| SRC-004 | [CS5343/4 datasheet - Cirrus Logic](https://statics.cirrus.com/pubs/proDatasheet/CS5343-44_F5.pdf) | DS687F5, March 2015, marked Draft: timing pp. 9-10; sections 4.1-4.2 / Tables 1-5 / Figure 4, pp. 12-14: ADC ratios, mode and I2S. Confirm applicable released revision | Robel / 2026-10-15 register reconciliation | Consulted; Draft/released-revision confirmation pending |
| SRC-005 | [CS4344/5/8 datasheet - Cirrus Logic](https://statics.cirrus.com/pubs/proDatasheet/CS4344-45-48_F2.pdf) | DS613F2, July 2013: timing p. 9; sections 4.1-4.2 / Table 1 p. 12; Figure 7 p. 13; sections 4.4-4.5 / Figure 11 pp. 15-16: DAC ratios, external SCLK and startup | Robel / 2026-10-15 register reconciliation | Consulted; actual hardware/application validation pending |
| SRC-006 | [7 Series Clocking Resources - AMD/Xilinx](https://docs.amd.com/v/u/en-US/ug472_7Series_Clocking) ([PDF](https://docs.amd.com/api/khub/documents/1kFbRqzm2fhwGy~cLQG2yA/content)) | UG472 v1.14: primitive ports pp. 70-71; LOCKED p. 83; Clocking Wizard p. 102 | Robel / 2026-10-15 register reconciliation | Consulted; actual hardware/application validation pending |
| SRC-007 | [Clocking Wizard: Configuring Output Clocks - AMD](https://docs.amd.com/r/en-US/pg065-clk-wiz/Configuring-Output-Clocks) | PG065 v6.0, April 20, 2022; named HTML section: requested/actual frequency and fractional-divider restrictions | Robel / 2026-10-15 register reconciliation | Consulted; tool configuration is separate from timing closure |
| SRC-008 | [Basys 3 public schematic - Digilent](https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys-3-sch-public-rev-d.pdf) | Doc. 500-183, D.1, February 5, 2021; sheet 1 of 8, title block and PMOD, I/O; sheet 6, IC7C bank 34 / W5 and XC7A35T-1CPG236C: explicit revision matches Robel's reported board; connector/electrical review input. Reviewer: Robel; consulted 2026-10-08; D.1 clock/JA/button/LED netlist cross-checked on 2026-10-15 (sheet 6, IC9/IC7A/IC7C/IC7D); physical connection and electrical timing pending | Robel / 2026-10-23 local D.1 review | Consulted; actual hardware/application validation pending |
| SRC-009 | [Basys 3 online reference manual - Digilent](https://digilent.com/reference/programmable-logic/basys-3/reference-manual) | Revision and exact section unavailable: retrieval failed on 2026-10-08. Intended use: D.1 applicability and operating requirements. Reviewer: Robel; pending access, not used as evidence | Robel / 2026-10-15 register reconciliation | Pending access; not used as evidence |
| SRC-010 | [ESP32 Pinout Reference - Last Minute Engineers](https://lastminuteengineers.com/esp32-pinout-reference/) | Unversioned HTML; sections ESP32 UART Pins and ESP32 Strapping Pins. Supplementary reading for UART/boot-pin questions only; not manufacturer evidence or confirmation of this DevKit V1's wiring. Reviewer: Robel; consulted 2026-10-08; exact module/board and primary-document cross-check pending | Robel / 2026-10-15 register reconciliation | Supplementary reference/analogy; applicability limits stated |
| SRC-011 | [ESP32 DevKit pinout image - Reddit user submission](https://www.reddit.com/media?url=https%3A%2F%2Fpreview.redd.it%2Fa-better-pinout-diagram-for-esp32-devkit-development-board-v0-0u14t38nxeo21.png%3Fwidth%3D1200%26format%3Dpng%26auto%3Dwebp%26s%3D54d4999219ffd8a362a7a60208c17fd8176b8cac) | User-supplied image reference; author, revision and image content unverified because retrieval failed on 2026-10-08; no page/section available. Intended use: supplementary board identification. Reviewer: Robel; pending access, not used as wiring evidence | Robel / 2026-10-15 register reconciliation | Pending access; not used as evidence |
| SRC-012 | [I2S bus specification - NXP Semiconductors](https://www.nxp.com/docs/en/user-manual/UM11732.pdf) | UM11732 rev. 3.0, February 17, 2022; section 3.1 p. 4: MSB delay and word-length handling; section 3.2 p. 5: word select; section 6.1 p. 8 / Figure 5 p. 9: transmitter zeros after LSB. ANIMA use: 24-bit payload in 32-bit slots and transmitter zero padding. Reviewer: Robel; consulted 2026-10-08; relevant format sections reviewed, codec-specific electrical/timing integration pending | Robel / 2026-10-15 register reconciliation | Consulted; actual hardware/application validation pending |
| SRC-013 | [RFC 7005 - IETF](https://www.rfc-editor.org/rfc/rfc7005.html) | September 2013; section 3 p. 4 and section 3.2 p. 5: playout deadlines and fixed-delay buffering. ANIMA use: conceptual comparison of late-data discard versus changing playback delay; RTP is not an ANIMA interface and this source does not establish audible superiority or select a frame policy. Reviewer: Robel; consulted 2026-10-08; analogy reviewed, ANIMA policy and audio evidence pending | Robel / 2026-10-15 register reconciliation | Supplementary reference/analogy; applicability limits stated |
| SRC-014 | [Basys 3 master XDC - Digilent](https://github.com/Digilent/digilent-xdc/blob/c8644a9fe31cc803789643124545d56b3bef4600/Basys-3-Master.xdc) | master tip c8644a9fe31cc803789643124545d56b3bef4600 identified on 2026-10-15; consulted master file sections Clock signal, Buttons, LEDs and Pmod Header JA. Header calls out rev. B, so D.1 schematic SRC-008 is the pin-map authority. Reviewer: Robel / 2026-10-15; supplementary comparison only, no XDC/code copied | Robel / 2026-10-15 register reconciliation | Supplementary reference/analogy; applicability limits stated |
| SRC-015 | [DSC1033 datasheet - Discera, hosted by Microchip](https://ww1.microchip.com/downloads/en/DeviceDoc/DSC1033_Datasheet.pdf) | MK-Q-B-P-D-031809-01-8; Specifications p. 2 and Ordering Information p. 8: oscillator conditions and code S=1 (+/-50 ppm), temperature code C. ANIMA use: tolerance of IC9 part named in D.1 schematic, not a fitted-part or frequency measurement | Robel / 2026-10-15 register reconciliation | Consulted; actual hardware/application validation pending |
| SRC-016 | [Using Clock Modifying Blocks (MMCM and PLL) - AMD](https://docs.amd.com/r/2024.1-English/ug949-vivado-design-methodology/Using-Clock-Modifying-Blocks-MMCM-and-PLL) | UG949 2024.1 English, June 26, 2024; named HTML section, bullets on connecting RST to reliable-clock user logic and synchronizing LOCKED for synchronous use. ANIMA use: reference supervision/MMCM reset output and reset qualification; does not validate chosen timer defaults, primitive configuration or physical timing | Robel / 2026-10-23 | Consulted primary documentation; hardware/tool acceptance pending |

No external code is reused. Any future reuse must record its original immutable commit/release, reused paths, license/SPDX and license URL; documentation references do not grant code licenses.

Pending reading targets from An's notes, **not consulted evidence**: exact-board Espressif datasheet/strapping table and version-matched ESP-IDF UART guide; Cummings, CDC Design & Verification Techniques Using SystemVerilog (SNUG 2008); UART/framing tutorials and CRC/COBS/SLIP specifications if proposed. Add stable IDs, versions/locators and review records when consulted. No new claim here depends on those targets.

Source recheck, October 23: SRC-016 was retrieved and consulted. SRC-014's current raw master file was retrieved ([manufacturer raw file](https://raw.githubusercontent.com/Digilent/digilent-xdc/master/Basys-3-Master.xdc), Clock signal / LEDs / Buttons, lines 6-7 / 26 / 57 / 61); its header still names rev. B, and the exact current master commit was not resolved. The previous pinned SRC-014 URL could not be retrieved on this recheck. The online SRC-008 fetch failed, but Robel supplied a local PDF: Downloads/basys-3-sch-public-rev-d.pdf, SHA-256 17641d0a8d5bd688cbb54ea088dcaa6a74b450de8a643abcb2b8f7cc6cebe465. Its eight sheets identify document 500-183, revision D.1, February 5, 2021. Text extraction and rendered-sheet inspection verified sheet 6 IC7A/IC7C: BTNC U18, BTND U17, LED0 U16 and CLK100MHZ W5; sheet 1 PMOD, I/O shows active-high buttons with pull-downs, and sheet 7 FPGA POWER connects banks 14/34 to VCC3V3. This replaces the fresh D.1 source-access limitation; board fit, complete constraints and electrical timing remain unvalidated. SRC-006 PDF/API re-fetches failed; prior consultation remains historical. Control constraints were authored from pin facts; no third-party RTL/XDC code was imported, so no reused-code version/license is introduced. Reviewer: Robel, 2026-10-23.

## Design history and contribution credit

An Tiet's interconnect questions, electrical/protocol risks and delivery dependencies are incorporated above. Full original notes remain in immutable history: [October 4 kickoff](https://github.com/Rkycodes/ANIMA/blob/d77741fc47be789ec7ce2ae14417c2a0c8425738/docs/notes/2026-10-04-interconnect-kickoff.md) and [October 6 gameplan](https://github.com/Rkycodes/ANIMA/blob/e6bd0a58a294aa1bd976dd53b5025ed9aa205161/docs/notes/2026-10-06-an-gameplan.md). They were proposals/learning notes, not agreed contracts. Live requirements reside here instead of duplicate transcripts.

[Planning checkpoint ee525f9](https://github.com/Rkycodes/ANIMA/tree/ee525f973c7c4b49c893a25aae8cd69f915a8674/docs) preserves prior worksheet wording/dates. October 8 selected serial/common-domain/scheduling directions; October 15 selected widths/depths/reset/diagnostics/guard/progress and evaluated first-build clock target. Reorganization does not silently resolve open DSP/control choices.
