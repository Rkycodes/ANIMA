# Architecture - planned

No audio RTL or hardware-validation evidence exists yet. The bypass format, handoff and fault behavior below are selected design requirements. The October 15 Clocking Wizard probe is configuration evidence only; it does not establish implementation timing or measured audio. Later DSP/control interfaces remain explicitly open. See the [system diagram](../README.md#planned-system), [source index](sources.md) and [verification plan](verification.md).

## Responsibilities and flow

The FPGA owns audio processing; the ESP32 owns wireless/web controls and sends parameters over UART. Wi-Fi carries no audio. Planned DSP order: input gain -> five biquads per channel -> stereo-linked compressor -> output gain/saturation.

| Boundary | Owner / integration responsibility |
| --- | --- |
| Audio clocks/reset, I2S RX/TX, frame transport, DSP and reference models | Robel |
| ESP32, FPGA UART/parser, shadow parameters, acknowledgements and serial diagnostics | An |
| Frame/parameter contract, CDC, pins and board integration | Joint review; Robel defines consumption, An defines transport |
| VGA | An: layout/control; Robel: meters/clocks/integration |

[Ownership](ownership.md) defines the full work split. Robel confirmed on 2026-10-08 that the browser interface and VGA status display are both required for the planned system; VGA is not an optional stretch feature. They follow bypass/EQ in the roadmap and do not expand the agreed first stereo-bypass milestone. Existing VGA 640 x 480 procedural drawing/font ROM remains the planning direction; FFT remains a stretch goal.

## Audio and control contracts

| Area | Required semantics / proposed values |
| --- | --- |
| Stereo frame | Paired L[n]/R[n] from the same sample interval; channels never advance independently. Robel confirmed on 2026-10-08 that a frame is eligible for handoff only after both complete 24-bit samples from that interval have been captured; partial or mismatched pairs are ineligible |
| Sample format | Robel selected nominal 48 kHz, signed two's-complement 24-bit samples and two 32-bit I2S slots / 64 bit periods per stereo frame. Selected edge, alignment and zero-padding rules are specified below; physical I/O timing and shared-interface review remain pending |
| Raw payload | 48 audio bits per stereo frame. On 2026-10-15 Robel selected separate signed 24-bit left/right sample fields and an unsigned 32-bit frame ID, transferred together under valid/ready: 80 data bits excluding handshake. Preset generation metadata is deferred to the DSP/control increment |
| EQ | Independent history for every channel/section, even with shared coefficients |
| Compressor | One gain applied to both channels; maximum-channel envelope is a proposal pending modeling |
| Numeric policy | Floating-point reference followed by a bit-exact model before DSP RTL; widths, rounding, coefficient representation and state reset remain open in [numeric design](numerics.md) |
| UART | Control only; [protocol](protocol.md) owns framing, fields, validation and acknowledgements. Its 3.3 V/115200-baud link is a draft; pins and interfaces are not frozen |
| Activation | Validate and hold a complete shadow snapshot until accepted; activate one generation at a frame boundary, without mixing generations in flight. Later writes cannot alter a pending snapshot |
| Acknowledgements | Receipt ACK is separate from applied generation, which is reported only after audio-side acceptance |
| Telemetry | Coherent levels, gain reduction, active generation and fault snapshots; congestion may drop/coalesce updates and must never block audio |

Commit/busy behavior, snapshot transfer, generation wrap, defaults and CDC remain joint decisions. Atomic coefficient activation alone does not ensure click-free transitions; transition/state handling needs model and audio evidence.

## I2S payload and padding

Robel selected transmitter zero padding on 2026-10-08: transmit each signed 24-bit sample MSB first, followed by zeros until the next sample MSB. Keep the I2S one-bit delay after each LRCK transition; do not restart the sample at the transition or sign-extend the transmitted padding. Two 32-bit channel slots provide eight non-payload periods per sample. Measured from one LRCK transition to the next, the first period belongs to the preceding word's tail, then come 24 new sample bits and seven trailing periods; the eighth zero after that sample falls after the next LRCK transition, before the following MSB. This describes steady-state serialization, not a startup/reset policy.

SRC-012 section 3.1 specifies MSB placement and word-length handling; section 6.1 illustrates zero output after the LSB. Receive exactly the 24 payload bits and exclude the non-payload periods from the sample value. Robel selected falling-edge serial-data launch and rising-edge capture on 2026-10-08: FPGA TX changes data on SCLK falling edges; FPGA RX captures ADC data on rising edges. Verify the ADC output timing and DAC input setup/hold against SRC-004/SRC-005 before implementation. Opposite-edge scheduling provides nominal half-cycle separation, not a timing guarantee; account for clock-to-output delay, board delays, skew, duty cycle and reviewed external I/O constraints. Robel also selected falling-edge LRCK transitions on 2026-10-08: change LRCK on a SCLK falling edge, launch the new channel MSB on the next falling edge, and capture that MSB on the following rising edge. This preserves the one-bit I2S lead; codec LRCK setup/hold still needs verification. Robel selected LRCK low for left and high for right on 2026-10-08, matching SRC-012 section 3.2. Channel identity follows the delayed sample MSB, not immediate reinterpretation of the data bit at the LRCK transition. Receiver fault checks, startup and pin timing remain open; no implementation or hardware evidence exists.

## Stereo-frame handoff direction

Robel selected a custom valid/ready interface carrying a whole stereo pair on 2026-10-08, rather than adopting AXI4-Stream. This is an internal audio/DSP-domain interface; it does not select the UART/control interface. The selected single audio/DSP domain avoids an internal frame CDC requirement, subject to clock feasibility.

Robel agreed on 2026-10-08 that one whole pair transfers exactly once at each internal processing-clock rising edge where valid and ready are both asserted. While valid is asserted and ready is low, the sender retains valid and holds both samples and any associated metadata unchanged until acceptance. Ready low applies internal backpressure; it cannot pause external audio. The bypass fields are separate signed 24-bit left/right samples, unsigned 32-bit frame ID, and one-bit valid/ready. They form one transaction; all 80 data bits remain stable during a stall. Preset metadata is deferred. The transfer/storage bounds and reset/deadline rules below apply. Valid/ready does not permit pausing external ADC/DAC clocks; finite storage can absorb only bounded stalls. No interface RTL is implemented.

## RX frame-buffer direction

Robel agreed on 2026-10-08 to parameterize the RX handoff buffer depth in complete stereo pairs. Use FRAME_BUFFER_DEPTH as the proposed configuration name, with two complete-pair entries as the initial depth proposal pending the worst-case stall/deadline budget. The entries include the oldest complete pair presented on valid/ready; partially received serial data remains separate RX assembly state. This does not select additional DSP inter-stage buffers; separate configurable TX waiting storage is described below.

At the selected nominal format, two entries contain 96 raw payload bits plus any metadata. Capacity is not guaranteed stall tolerance: available space depends on occupancy and arrival phase. Preserve whole-pair ordering and the agreed acceptance/stability rules across supported depths. Robel selected rejecting the newly arriving complete stereo pair when the buffer has no capacity on 2026-10-08: preserve queued pairs, discard both incoming channels together and report overflow without blocking audio. Never overwrite a pair held on valid while stalled. Queued pairs remain subject to the selected late-pair discard policy; overflow handling does not extend their playback deadlines. Robel agreed on 2026-10-08 to simultaneous RX dequeue/enqueue: a consumer acceptance frees capacity for a complete incoming pair on the same processing-clock edge. A full buffer [A, B] becomes [B, C] if A transfers out while C arrives; this is not overflow. Reject C only when no space exists after accounting for an actual same-edge dequeue. Preserve ordering and the stable stalled output pair. On 2026-10-15 Robel selected supported RX and TX-waiting depths of 1, 2, 4 and 8 complete pairs, with initial RX depth 2 and TX-waiting depth 1. Other values are unsupported until the contract and checks are extended. Capacity counts complete stored pairs including the presented head; partial RX assembly and TX-owned storage are separate. Reset flushes all data storage as specified below. Increased capacity does not automatically change the fixed playback delay, permit missed output deadlines or correct sustained rate mismatch. No FIFO RTL or particular memory implementation is selected.

## TX waiting storage and configurable values

Robel agreed on 2026-10-08 to configurable TX waiting-pair capacity, with one complete waiting pair as the initial proposal pending timing/ownership walkthroughs. Waiting storage is separate from the current pair being serialized and additional to the proposed two-entry RX buffer. A newly accepted pair must not overwrite the current output pair. Select the expected waiting pair or silence only at a whole-pair output boundary. Capacity does not itself add a frame of playback delay. Robel agreed on 2026-10-08 to same-edge removal and replacement when a boundary promotes the expected waiting pair and an incoming pair is eligible under the scheduling contract. Treat the freed waiting capacity as available for that edge; do not insert backpressure solely because the slot was occupied before the edge. The promoted pair becomes current output and the replacement remains waiting, without overwriting current serialization state. When waiting storage is empty, an expected pair accepted on its boundary-inclusive deadline becomes current output for that slot, rather than causing an artificial silent pair. This specifies observable transfer behavior, not a selected register/mux implementation. Supported depths are 1, 2, 4 and 8 pairs as selected on October 15. Warm reset has priority at its apply boundary. For this bypass increment, accept only a pair due for the next unfilled output slot into TX waiting storage; leave future pairs upstream, accept/discard stale pairs, and backpressure a due pair when its waiting slot is already reserved. Larger configured depths remain legal storage capacity, not permission to prefetch future output slots. Exact register/FSM organization may be designed during coding.

Robel requests parameterization of values reasonably expected to vary. Use build-time parameters for reviewed structural choices such as buffer capacities; derive dependent widths/counts where appropriate. Runtime user controls are a separate contract. For each configurable value, document units, default, legal values/relationships and externally observable effects, and verify the supported configurations. Do not expose arbitrary combinations as supported. A parameter does not defer agreement on the instantiated widths, signedness, packing, clocks, reset or transfer semantics required before coding. The selected 24-bit audio payload, 32-bit slots and unsigned 32-bit frame ID remain the current system contract; parameterizing module internals does not silently renegotiate those interfaces. Final clock frequencies and a change to playback delay require coordinated feasibility/contract updates rather than an unchecked parameter override.

## Frame identity and playback scheduling

Robel provisionally agreed on 2026-10-08 to advance the input frame ID for every complete aligned stereo pair, including pairs rejected on overflow. Frame identity refers to the input interval, not successful buffer admission and not preset generation. Preserve gaps so dropped content is not concealed by renumbering later frames. Robel selected restarting input frame numbering at zero and restarting the corresponding playback schedule together after an audio reset on 2026-10-08. Frame zero is the first complete aligned input pair after readiness; its output is assigned to the next stereo slot, with silence before it. Control reconnection alone does not restart numbering. Robel selected a 32-bit audio frame ID with explicit wraparound support on 2026-10-08. Robel also selected unsigned IDs with modular comparison: subtract expected ID from received ID modulo 2^32, then interpret the result as a signed two's-complement difference. Zero is due, a positive difference is future, and a negative difference is late, provided the true separation is strictly less than 2^31 frame intervals. The exactly-half-range difference is ambiguous and must not be treated as a valid ordering. The progress watchdog and FIFO ordering bound retention; verify modular ordering across wrap in simulation. An exactly-half-range comparison violates the valid-stream contract and must fail an assertion; it must not authorize playback. External reset-epoch reporting is deferred from bypass. The aligned frame-zero restart is specified below.

Robel agreed that a receiver can accept a stale pair through valid/ready and then discard it. Acceptance transfers ownership; it does not promise playback. The sender must not withdraw or replace a stalled valid pair simply because its deadline passed. Robel selected continuous receiver-side stale-pair draining on 2026-10-08 rather than checking only at stereo-frame boundaries. During normal operation, accept and discard a late head pair as soon as the receiver can, accept a pair due for the next unfilled output slot into available TX-owned storage, and hold a future pair until its slot becomes eligible. These transfers do not move the fixed playback boundaries or permit mid-pair changes. Receiver-side draining must be bounded so stale queued pairs do not prevent a due pair from reaching TX. Modular frame-ID comparison is selected as above; the October 15 bounds below fix drain throughput and timeout precedence. External reset epochs are deferred because bypass does not export frame IDs across a reset boundary.

Robel selected the following bypass timing target on 2026-10-08, revisitable if feasibility/timing results require it: play input frame n in the next stereo output slot, while RX receives frame n+1. TX selects a complete pair or a whole silent pair at that output slot's left LRCK transition. A valid/ready transfer of the expected pair on the internal processing-clock rising edge that schedules that LRCK transition counts as on time. A pair accepted earlier into TX waiting storage is selected from there. When that slot is empty, an eligible same-edge transfer may directly supply current output as already agreed. In either case, commit the whole output pair at the boundary and launch its left MSB one SCLK bit period later. If the expected pair is unavailable by that inclusive deadline, select silence and report underflow as agreed. A stale or future pair is not a substitute for the expected pair.

The target shifts corresponding RX/TX slot starts by one nominal frame interval (20.833333 microseconds at 48 kHz). This is not complete-system latency or codec latency. The ideal aligned study gives approximately 2.441406 microseconds from right-payload capture to selection and one additional bit period before left-MSB launch. No achieved timing or fixed clock configuration is claimed. The bounded transfer, startup, reset-priority and storage-accounting rules below apply. Physical clock phase and routed I/O timing remain evidence gates. Any change to the playback delay must update frame-slot mapping, late detection and acceptance tests together; changing buffer capacity alone does not change that mapping.

## Bypass startup alignment

Robel selected the following startup behavior on 2026-10-08. Discard any initial partial stereo frame; do not pair R[n] with L[n+1]. Establish serial alignment, capture a complete L[n]/R[n] pair from one sample interval, and only then make that pair eligible for handoff. While valid I2S clocks/framing are running but no complete eligible pair is available at startup, the transmitter sends signed zero samples on both channels with the agreed padding. Do not transmit stale or uninitialized payloads.

This is digital silence, not evidence of analog mute or click-free startup. Robel also selected a whole-pair startup transition: finish the current silent stereo pair, then start the first available complete audio pair at the next left-channel slot boundary, preserving the agreed one-bit I2S MSB delay. Never combine a silent left sample with an audio right sample. Use the boundary-inclusive transmit selection target in frame identity and playback scheduling; the first post-readiness left boundary begins capture of frame zero, whose output slot is the next left boundary. No extra queue-depth-dependent priming is selected. Warm-reset and cold-start rules are specified below. Clock-loss, runtime underflow and fault recovery policies are not selected by this startup rule; behavior without running clocks needs separate definition.

## Reset and stereo alignment

Robel confirmed on 2026-10-08 that reset during an incomplete stereo pair discards that pair coherently. Do not retain the pre-reset left sample and combine it with a post-reset right sample. Resume capture at a fresh left-channel boundary after valid clocks and codec readiness are established, collecting both channels from the same new interval. Transmit whole silent pairs while awaiting a complete pair for its assigned output slot, then transition at a whole-pair boundary using the selected I2S delay and playback schedule. The next boundary means the next eligible aligned boundary after readiness, not an unconditional restart before clocks/codecs are ready.

Coordinated RX/TX reset release in the common audio/DSP domain and an audio-ready condition govern restart. Operating readiness is distinct from valid for an individual frame. Robel agreed to a full audio-data flush on audio reset: clear partial RX assembly, queued stereo pairs and any TX-held pair so pre-reset audio is not replayed after restart. Robel selected coordinated restart of input frame numbering and playback scheduling at zero after an audio reset; the first complete aligned pair after readiness is frame zero. Warm-reset requests, cold qualification and clock-loss recovery are specified below. External reset-epoch reporting is deferred. Reset synchronizer and clock-resource implementation require review; detailed state encoding and FSM organization may be designed during coding.

## Normal audio reset versus clock recovery

Robel selected the following behavior on 2026-10-15. A normal audio-path reset request while clocks are healthy keeps codec MCLK/SCLK/LRCK running. Finish the current output stereo pair; apply the reset at the next left-channel boundary. At that boundary reset takes priority over same-edge frame acceptance or playback selection: flush partial/queued/TX-held audio, restart frame numbering and the corresponding schedule at zero, and send a whole silent pair. That boundary may begin capture of fresh frame zero (its first MSB occurs later under I2S timing); play it at the following left boundary if complete. A qualified request coinciding with a left boundary applies there; otherwise latch it for the next left boundary. The selected board button is synchronized and debounced; one qualified press produces one request, with release required before another request. Debounce implementation is local to the input conditioner; it cannot generate repeated resets while held.

Clock loss or clock-generator reset uses a separate full recovery sequence. Robel selected automatic recovery after valid clocks return on October 15. Invalidate audio data immediately on loss of qualified clock validity, flush before release, reset/reacquire the MMCM using the board reference and synchronize release into the audio domain. Clock supervision uses the 100 MHz reference; it is separate from the single audio/DSP data domain. Do not wait for a stopped audio clock to assert invalid/reset state. The clock/pad implementation must establish defined inactive outputs while unqualified; absent clocks cannot carry valid digital silence, and no quiet analog-output guarantee is made. Complete reference/power loss requires board recovery and reinitialization.

Robel selected a configurable nominal 1000 ms cold-start silence interval after valid codec clocks begin. Restart this interval if clock validity is lost; warm audio reset does not restart healthy clocks or repeat the cold interval. Keep serial clocks/framing and zero data running during qualification; then start frame-zero capture at the first left boundary at or after guard expiry. Input pairs during cold qualification are ignored and do not consume frame IDs. Compute the guard counter from the selected processing frequency and requested milliseconds, rounding up. This is a conservative qualification target, not a codec-ready pin or hardware proof: SRC-005 sections 4.4-4.5 describe component-dependent reference ramping and approximately 2000 sample periods. SRC-002 shows a 10 uF DAC VQ capacitor; the actual purchased board and power sequence must be checked before hardware acceptance.

## Bypass runtime underflow

Robel selected the missing-output-pair behavior on 2026-10-08: if no complete eligible stereo pair is available by the transmit selection deadline, transmit one whole pair of signed zero samples with the agreed padding and report an underflow. Keep valid I2S clocks, framing and channel alignment running; a missing pair alone does not trigger serial realignment. Do not transmit a partial pair or substitute only one channel. Underflow reporting must not block audio.

Robel selected discarding late stereo pairs on 2026-10-08: after a pair misses its assigned transmit deadline and silence is substituted, discard that late pair as a unit rather than playing it in a later output slot. Preserve the established playback schedule and never discard only one channel. This is a fault policy, not evidence of audible superiority; normal-operation acceptance still requires zero underflows. The next-slot, boundary-inclusive target, modular frame ordering and continuous stale draining apply. Resume real audio on a whole-pair boundary as soon as its expected complete pair is available; do not replay missed IDs or add latency to catch up. Diagnostic events are defined below. This rule applies to unavailable output data while serial clocks/framing remain valid; clock loss or malformed framing requires a separate recovery policy.

## Persistent queue-stall recovery

On 2026-10-15 Robel selected automatic warm recovery if a nonempty audio queue makes no transfer progress for one stereo-frame period. Request the agreed next-whole-pair audio reset, preserve diagnostics, flush audio data at the reset boundary and restart with silence and aligned frame zero. This is distinct from an isolated underflow, which retains the serial schedule and substitutes a silent pair. Queue progress includes an accepted stale-pair discard. Robel selected one accepted pair per processing cycle when eligible, and RX enqueue-to-present latency no greater than one processing cycle. Monitor each nonempty RX and TX-waiting queue independently while audio operation is active: count 2048 processing cycles without dequeue/promotion progress. A real progress event on the threshold edge resets the timer; it does not time out. Empty queues and intentional startup/reset are not stalled queues. At threshold without progress, count a stall timeout once and latch a warm-reset request for the next left boundary; coalesce further timeout requests until reset applies. Reset has highest priority. The watchdog is independent of the stalled interface and browser/UART service.

These limits also protect modular ordering: with FIFO storage depths at most 8 each, each head either progresses within one frame period or initiates a reset no later than the following left boundary. The implementation/testbench must verify a conservative retained-frame age bound of (RX depth + TX-waiting depth + 2) stereo periods, at most 18 for supported depths, far below 2^31. The current serialized pair cannot block queue cleanup indefinitely; clock loss flushes before numbering restarts. No claim of measured stall tolerance is made.

## Control, status and debug displays

Robel selected the following product roles on 2026-10-08. The ESP32 Wi-Fi browser interface provides the full user controls and detailed diagnostics; the FPGA VGA output is a required compact read-only local status display. The browser requests changes through ESP32/UART; the FPGA owns audio execution and reports actual activation. Both views derive from coherent FPGA status, without making audio wait for display refresh, network delivery or controller connectivity. Robel clarified on 2026-10-08 that loss of ESP32, Wi-Fi or UART does not by itself stop/reset audio or flush audio data. The existing active settings remain in effect absent a valid update or defined audio reset; reconnect/status recovery and parameter reset behavior remain open. VGA is required in the planned final system, scheduled after the bypass/EQ foundation rather than included in the first bypass milestone.

Robel also agreed to one sticky audio-fault LED on the Basys 3 alongside dashboard diagnostics. On 2026-10-15 Robel selected preserving error counters and this LED across normal audio resets. Clear them only through an explicit diagnostic-clear action or FPGA reinitialization/power-up. On 2026-10-15 Robel selected five unsigned 32-bit saturating counters (maximum 4294967295), separate board-button actions and the diagnostics contract below. Later control-interface equivalents must preserve these semantics; no UART register map is selected here.

Proposed browser content includes system readiness/connection/version information, frame and underflow/overflow/late-discard counters, buffer occupancy/high-water mark, requested/pending/applied settings and later audio levels/clipping/gain-reduction meters. Proposed VGA content is a compact subset of applied settings, meters and faults. The bypass fault counters and reset/clear semantics are defined below. Later meter fields/units, refresh rates, snapshot/CDC ownership, reconnect behavior, browser transport/framework and VGA layout remain open. WebSockets are only a discussion proposal. No UI or diagnostic hardware implementation exists.

## Bypass diagnostics and board reservations

Robel approved these diagnostic fields on October 15, 2026. Each is an unsigned 32-bit saturating event count; the sticky LED is one bit.

| Field | Count one event when |
| --- | --- |
| underflow | One expected runtime output pair is unavailable at its selection deadline |
| overflow | One complete incoming pair is rejected because capacity remains full after same-edge dequeue accounting |
| late_discard | One stale pair transfers to the receiver and is discarded |
| stall_timeout | One monitored queue times out as defined above; coalesce requests until recovery applies |
| recovered_clock_loss | One detected clock-loss episode completes qualified recovery; latch detection while the reference remains available |

Any of these faults sets the sticky LED; clock-loss detection also latches fault evidence for presentation after recovery. Preserve counters/LED across warm audio reset and recoverable clock loss. Power-up/reconfiguration initializes them to zero. Explicit diagnostic clear clears all five counters and the LED without resetting audio, IDs, clocks or queues. If clear and a new event coincide, preserve that event: its counter becomes one and LED remains set; other counters clear. Several distinct event classes may count on one edge. They are not a sum of unique lost frames. Intentional startup/reset silence is not underflow. Counters must not block audio. Browser/UART packet fields and snapshot CDC are deferred to their increment.

JA is reserved for the intended Digilent Pmod I2S2. The following mapping is checked against SRC-008 sheet 6 and SRC-002 J1, not merely the older master XDC. All signal I/O uses the reviewed 3.3 V interface; final electrical and routed timing constraints remain hardware gates.

| Function | Board connection | FPGA package pin | Direction at FPGA |
| --- | --- | --- | --- |
| Board reference | CLK100MHZ | W5 | Input |
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

JA/Pmod positions 5/11 are ground and 6/12 are 3.3 V. Check connector orientation and actual module before connection. Use ADC slave selection at JP1; SRC-002 identifies ground-side selection for the SDOUT pulldown, but physical jumper orientation is an arrival check. MCLK/SCLK/LRCK are coordinated copies to separate ADC/DAC connector pins, not outputs tied together externally. JB/JC remain unallocated. Synchronize/debounce button inputs; one press gives one action and stable release rearms it. Detailed debounce implementation and FPGA register/FSM organization remain coding mechanics. No board was programmed or electrically tested here.

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

Shared 48 kHz MCLK ratios 256/384/512/768 correspond arithmetically to 12.288/18.432/24.576/36.864 MHz. The proposed 64 Fs SCLK is 3.072 MHz. These are codec-compatible requests, not proven FPGA outputs. Robel selected FPGA ownership of ADC/DAC MCLK, SCLK and LRCK with the ADC in slave mode on 2026-10-08 (option A). Coordinated converter clocks are the intended arrangement, subject to feasibility; this is not tool or hardware evidence. Shared 256 Fs MCLK with external 64 Fs SCLK remains a candidate, not a selected ratio. ADC-generated LRCK/SCLK (option B) was considered but is not the chosen direction. Exact rates/ratios, clock-generation resources, startup, I/O setup/hold, duty cycle and routing require review; An's shared-interface review remains pending. See the [clock-ownership diagram](diagrams/audio-clock-ownership.mmd).

Record exact device/tool versions, input tolerance, legal PFD/VCO/dividers, actual frequency/error, phase/duty cycle, estimated jitter and routing before selecting clocks. Do not substitute unconstrained fabric division or alternating periods for a validated audio clock. Routed timing and measured clocks require separate evidence.

## Clock configuration investigation - October 15, 2026

Vivado 2026.1, SW build 6511674 / IP build 6504888, starts with a detected BASIC license and recognizes xc7a35tcpg236-1. An in-memory Clocking Wizard 6.0 configuration probe used a nominal 100.000 MHz input and requested 98.304 MHz output. Temporary IP configuration files were outside the repository; no audio RTL, synthesis, implementation, programming or measurement was performed.

| Reported configuration / derived quantity | Value |
| --- | --- |
| Selected primitive | MMCM |
| Input divider | 1 |
| Feedback multiplier | 7.250 |
| Output 0 divider | 7.375 |
| Nominal output calculated from those settings | 98.3050847458 MHz |
| Candidate MCLK, processing / 8 | 12.2881355932 MHz |
| Candidate SCLK, processing / 32 | 3.0720338983 MHz |
| Candidate stereo rate, processing / 2048 | 48000.529661 Hz |
| Arithmetic error relative to nominal 48 kHz | +11.034605 ppm, excluding reference-oscillator tolerance |

Robel selected these evaluated settings as the first bypass-build target on 2026-10-15, subject to implementation acceptance checks. For the schematic oscillator part, SRC-015 specifies +/-50 ppm; combining that source range with the evaluated ratio gives approximately 47998.130-48002.930 Hz, or -38.966 to +61.035 ppm relative to 48 kHz, not a measured rate. Actual fitted-part verification, jitter/phase/duty requirements, legal routing, derived external-clock implementation, I/O constraints and timing closure remain acceptance checks. The settings returned by Clocking Wizard are configuration evidence, not proof of working clocks or audio. The earlier exact 98.304 MHz relationships remain nominal arithmetic targets; the evaluated settings above are approximate.

Clock-probe reproduction (Vivado Tcl; temporary directory, no synthesis):

```tcl
create_project -in_memory -part xc7a35tcpg236-1
set probe_dir [file join $::env(TEMP) anima-clock-probe]
file mkdir $probe_dir
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name anima_clock_probe -dir $probe_dir
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {98.304}] [get_ips anima_clock_probe]
report_property [get_ips anima_clock_probe]
```

## Bypass timing-budget study

On 2026-10-08 Robel requested a 100 MHz processing-clock target for evaluation. This is a target, not demonstrated timing closure or a selected audio/DSP domain topology. SRC-001 section 4 documents the Basys 3 100 MHz board reference; SRC-008 sheet 6 identifies the D.1 FPGA/package and W5 clock-capable pin. SRC-008 sheet 6 identifies IC9 DSC1033CC1-100.0000T driving CLK100MHZ / W5; SRC-015 ordering code S=1 specifies +/-50 ppm for the schematic part (commercial temperature code C); actual fitted part and frequency are not measured. A 100 MHz processing period is nominally 10 ns. At 48 kHz the average budget is 2083.33 processing cycles per stereo frame; actual deadlines and worst-case initiation interval must be checked. An integer divider of 100 MHz cannot generate exactly 3.072 MHz: the ratio is approximately 32.552083.  Legal clock resources, actual frequency/error, phase/duty cycle and codec timing remain feasibility work.

Robel proposed evaluating a processing clock below 100 MHz that is an integer multiple of nominal 3.072 MHz SCLK. A candidate for discussion is 98.304 MHz = 32 * 3.072 MHz: it gives 2048 processing cycles per 48 kHz stereo frame and, if paired with the candidate 256 Fs MCLK, integer ratios of processing / 8 = 12.288 MHz MCLK, processing / 32 = 3.072 MHz SCLK and processing / 2048 = 48 kHz LRCK. These are arithmetic relationships only; they do not select an MMCM/PLL configuration, fabric-generated clocks or the exact enable schedule. Robel subsequently selected a common internal audio/DSP domain with enables, subject to feasibility. Generating the candidate from the board reference, actual error/jitter, legal resources and external timing require tool evidence. The earlier 100 MHz target is an evaluation baseline. Vivado 2026.1 and an approximate Clocking Wizard configuration were evaluated on October 15; see the clock configuration investigation above. The first-build target uses the evaluated settings above; approval of implementation timing still requires the remaining checks.

[Editable edge timing diagram](diagrams/bypass-edge-budget.svg) shows an ideal 50-percent-duty SCLK study with aligned RX/TX LRCK phases and the selected next-slot, boundary-inclusive timing target; it is not selected clock circuitry or measured pin timing. Let Tbit = 1 / (48000 * 64) = approximately 325.521 ns. Set t = 0 at capture of R[n]'s LSB. Under the agreed one-bit I2S delay, R[n]'s MSB was launched 23.5 bit periods earlier; its LSB launched at -0.5 Tbit. The next left LRCK transition occurs at +7.5 Tbit, the next left MSB launches at +8.5 Tbit, and that MSB is captured at +9 Tbit. The ADC then sends L[n+1] while TX sends L[n] under the selected next-slot target, or zero if the expected pair misses its deadline. A valid/ready transfer of the expected pair on the left LRCK scheduling edge counts as on time. These are intended semantics, subject to feasibility, not achieved latency.

| Event relative to final right-payload capture | Ideal interval | Nominal time |
| --- | --- | --- |
| Next left-slot LRCK transition | 7.5 Tbit | 2.441406 microseconds |
| Next left MSB launch | 8.5 Tbit | 2.766927 microseconds |
| Next left MSB capture at DAC | 9 Tbit | 2.929688 microseconds |

The first two intervals correspond to approximately 244.14 and 276.69 nominal 100 MHz periods. At the first-build target of approximately 98.305085 MHz, Tbit still spans 32 processing periods: the selection window spans 240 periods, MSB launch 272 and DAC capture 288. Using a nominal 100 MHz reference, the first-build target gives approximately 2.441379 microseconds to selection and 2.766897 microseconds to MSB launch; the table retains the exact-48-kHz baseline for comparison. These are arithmetic windows, not guaranteed usable cycles: capture/assembly, pair selection, TX preparation, clock phase, external delays and margin consume time. No internal frame CDC is planned in the selected common audio/DSP domain. DAC capture time is not an extra preparation allowance after the required TX launch edge. The selected pair-selection target is the next left LRCK transition, inclusive of an eligible transfer on its scheduling edge. If the next slot cannot be met reliably, a later fixed output slot adds 20.833333 microseconds per frame interval and requires a coordinated contract revision. Final clock-generation resources, detailed schedule, worst-case handoff/drain budget and timing evidence remain open; buffer depths remain initial proposals. No executable RTL, synthesis or hardware validation is established by this diagram.

## Domains, reset and scheduling

- **Selected audio/DSP direction:** Robel selected one internal audio/DSP processing clock domain with enables on 2026-10-08, subject to clock-generation and codec I/O timing feasibility. RX, frame transport, DSP and TX use this domain; enables schedule external serial-clock/data activity. External codec clocks still exist. First-build clock settings and reset behavior are specified above; detailed clock-resource realization, enable implementation and pin timing require implementation review; UART/control and VGA domain choices are separate and unresolved. No async FIFO is required at internal frame boundaries by this selected direction. Related clocks still require timing analysis and are not automatically asynchronous.
- **Coherence:** independently synchronizing sample bits is invalid. Transfer complete frames through a reviewed handshake or FIFO. Async FIFOs support safe CDC, not sustained producer/consumer rate correction. Independent free-running ADC/DAC sample clocks require rate correction for indefinite bypass. Buffer type/depth remain open.
- **Reset/startup:** synchronize reset release per selected domain; suppress partial/invalid frames until clocks and codecs are ready and a complete LRCK-aligned frame is available. Clock loss invalidates partial frames and requires recovery. FPGA lock does not imply codec readiness. Resolve ADC mode sampling, DAC external-clock detection/ramp/settling, mute/release, stopped-domain reset assertion, CDC flushing, generation recovery and power cycling. No codec reset pin is assumed.
- **Deadlines:** I2S cannot wait for DSP or control. Define frame alignment, handshake/backpressure, bounded delay, startup priming and transmit deadlines before coding. At an example 100 MHz/48 kHz, the average budget is 2083.33 cycles/stereo frame; 100 MHz is not selected. Throughput depends on initiation interval, not latency alone; account for both channels, stalls and the shortest actual frame interval.
- **Faults:** the selected bypass counters, silence/discard policies, warm recovery and clock-loss recovery are defined above. Partial frames are ineligible; never mix channel indices or conceal rate mismatch. Additional later-subsystem fault fields remain deferred. Define output safety both with and without running clocks. Controller loss and telemetry overload must not stall audio.

Robel expressed interest in an optional async FIFO demonstration on 2026-10-08. Keep it as a later educational proposal, not a required audio-path crossing or permission to implement one. Its purpose, endpoints, clocks and acceptance criteria remain open; it must not weaken the selected bypass scope or imply correction of sustained rate mismatch.

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
| [ ] | H-01 | What are the exact Basys 3 and Pmod I2S2 revisions, ADC jumper setting and supply/interface voltages? Do the consulted schematic/manual revisions apply? | 2026-10-08: Robel confirms audio board is awaiting purchase; candidate listing recorded in [materials](../hardware/BOM.md), identity unverified. Basys 3 physical revision D.1 reported by Robel; supplied manufacturer schematic explicitly identifies D.1 (SRC-008). Supplied PDF manual applies to rev. C; its applicability to D.1 remains unverified. Codec revision, jumper and electrical configuration remain open | Robel: hardware confirmation; shared review pending |
| [ ] | H-02 | What exact ESP32 module/dev board, USB-serial device and firmware framework/version will be used? | 2026-10-08: Robel identifies ESP32 DevKit V1 with ESP32-WROOM-32 module, resolving the earlier module-identification deferral. Dev-board manufacturer/revision, pin count, USB-serial chip and framework/version remain open; An to verify exact board wiring before ESP32 UART pin allocation or electrical integration. Supplied third-party pinout references do not establish that wiring | An: board/toolchain confirmation; Robel reviews integration |
| [ ] | H-03 | Which Pmod header/row and FPGA package pins are reserved for audio, UART and other functions? Who checks the source pin table and conflicting uses? | 2026-10-15: JA reserved for audio; source-checked package/button/LED table above. Actual module/orientation and electrical validation pending. | |
| [ ] | H-04 | Which ESP32 GPIOs are safe for the chosen UART, considering straps, flash/PSRAM, boot output and board-specific connections? | | |
| [ ] | H-05 | What are clock/data directions, common-ground requirements and power sequencing? What happens when only one board is powered or either board resets? | | |
| [ ] | H-06 | Which Vivado/device/IP, Python and simulator versions are available? What codec documentation or tool access remains unavailable? | 2026-10-15: Vivado 2026.1 installed, BASIC license detected, selected FPGA recognized; Clocking Wizard probe recorded. WSL Ubuntu / Verilator 5.032 is available; no audio simulation was run. Source lists and commands belong with the first executable bench. | |

### 2. Clocks and reset/recovery

Record selected topology and assumptions here; keep tool evidence in [results](../results/README.md). Documented ratios are not clock-feasibility evidence.

| Done | ID | Question to answer | Answer / evidence or blocker | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | C-01 | Who generates ADC/DAC MCLK, SCLK and LRCK? Which codec modes, ratios and sample rate are selected? How are the converter rates coordinated? | 2026-10-08: Robel selects FPGA-generated coordinated MCLK/SCLK/LRCK for ADC and DAC; ADC slave mode (option A), nominal sample-rate target 48 kHz. Candidate 256 Fs MCLK and the October 15 clock probe are recorded above; one internal audio/DSP domain and configurable buffer directions are selected. Final clock approval and external timing remain open | Robel: clock proposal; An: shared-interface review pending |
| [ ] | C-02 | What clock-generation configuration is legal for the exact FPGA? What actual frequencies/error, phase, duty cycle, estimated jitter and routing does the tool report? | 2026-10-15: First-build MMCM probe and nominal calculated error recorded above. Routed timing, oscillator tolerance and physical clock evidence are not established. | |
| [ ] | C-03 | What clocks run audio, DSP, UART/parser and VGA? Which are common, related or asynchronous, and what timing assumptions establish that classification? | 2026-10-08: Robel requests 100 MHz processing target for evaluation, followed by an integer-related candidate below 100 MHz (98.304 MHz proposed). Robel selects one internal audio/DSP domain with enables, subject to feasibility; final frequency/resources and UART/control/VGA domains remain open. See bypass timing-budget study | Robel: audio/processing; An: control implications review pending |
| [ ] | C-04 | Where are coherent crossings required for frames, parameters, acknowledgements and telemetry? Who owns and reviews each side of each crossing? | | |
| [ ] | C-05 | What is held safe during startup, how is reset released per domain, and what establishes codec readiness and the first complete valid frame? | 2026-10-15: Whole-pair warm reset keeps clocks running and has transfer priority. Cold start uses a configurable 1000 ms zero-data qualification, then aligned frame zero; hardware readiness validation pending. | Robel: audio startup; shared review pending |
| [ ] | C-06 | What happens on clock loss or either-side reset, including stopped-domain reset assertion, partial-frame invalidation, buffering flush and restart? | 2026-10-15: Automatic clock recovery selected, repeating cold qualification and flushing data before numbering restarts. No quiet analog-output claim while clocks/power are absent. | |

### 3. Stereo-frame contract and scheduling

Record the system contract here and its checks in [verification](verification.md). Local implementation mechanics can wait for module design.

| Done | ID | Question to answer | Answer / evidence or blocker | Owner / reviewer |
| --- | --- | --- | --- | --- |
| [ ] | F-01 | Are the proposed 48 kHz, signed 24-bit samples and two 32-bit slots adopted? What are LRCK polarity/channel order, MSB delay, sampling edges and padding behavior? | 2026-10-08: Robel selects nominal 48 kHz, signed 24-bit samples and two 32-bit I2S slots (64 serial bit periods per stereo frame). Transmitter zero padding selected by Robel; see I2S payload and padding. Falling-edge data launch / rising-edge capture selected by Robel. Falling-edge LRCK transitions with a one-bit lead and LRCK low = left / high = right also selected by Robel. Clock feasibility, shared review, external I/O timing and startup remain open | Robel: audio format; An: shared-interface review pending |
| [ ] | F-02 | How is the paired 48-bit raw payload packed? What metadata is required, and how are frame index and preset generation distinguished? | 2026-10-08: provisional input frame ID advances for every complete aligned pair, even on overflow rejection; distinct from preset generation. Audio reset restarts input frame IDs and playback schedule together at zero; control reconnect does not. 32-bit audio frame ID with explicit wraparound selected by Robel; distinct from preset generation. Unsigned IDs and modulo-2^32 signed-difference ordering selected, requiring true separation below 2^31 frames. On 2026-10-15 Robel selected separate signed 24-bit left/right fields plus unsigned 32-bit ID under the shared handshake (80 data bits). Enforced age/comparison bounds, later metadata and any external reset epoch remain open | Robel: frame representation; shared review pending |
| [ ] | F-03 | What event means a frame is valid, accepted and released? What remains stable while waiting, and is any backpressure permitted? | 2026-10-15: Separate signed 24-bit left/right and unsigned 32-bit ID under one-bit valid/ready; rising-edge acceptance, stall stability and reset precedence specified above. | Robel: frame contract; An: shared-interface review pending |
| [ ] | F-04 | What are receive, processing and transmit deadlines and bounded delays? What initiation interval/resource schedule meets them for both channels? | 2026-10-08: ideal aligned RX/TX edge study recorded; 7.5 bit periods from R LSB capture to next left LRCK transition and 8.5 to left MSB launch. Robel selects next-slot playback with expected-pair transfer on the left LRCK scheduling edge counting as on time, subject to feasibility. Worst-case budget, exact schedule, startup alignment and tool evidence remain open | Robel: timing budget; shared review pending |
| [ ] | F-05 | Is buffering needed, of what type and justified capacity? How are occupancy, startup priming and sustained rate mismatch handled? | 2026-10-15: Depths 1/2/4/8 supported, defaults RX=2 and TX-waiting=1; partial RX/current TX storage excluded. Simultaneous dequeue/enqueue, overflow rejection and bounded progress specified above. | Robel: buffer contract; shared review pending |
| [ ] | F-06 | What are observable output/recovery behaviors for missing, duplicate, malformed or late frames, overflow and underflow? Which counters expose them? | 2026-10-08: Robel selects a whole silent output pair and an underflow report when a complete pair misses its transmit deadline; retain running clocks/framing/alignment rather than realigning solely for missing data. Late stereo pairs are discarded together rather than shifted into a later output slot, preserving the playback schedule. Next-slot boundary-inclusive deadline target selected; stale pairs transfer ownership to the receiver for discard. ID comparisons, stale-drain timing, return-to-audio conditions, report format and other faults remain open | Robel: audio fault policy; An: reporting integration review pending |

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
| [ ] | T-04 | How is controller disconnection/reconnection handled while audio continues? What additional display behavior can be deferred? | 2026-10-15: Browser controls/diagnostics and read-only VGA are required in the finished system. Bypass has five 32-bit saturating fault counters and sticky LED, preserved across warm reset; exact later UI/CDC/reconnect details deferred. | Shared display contract; An: UI/control; Robel: audio status/integration |

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
| [ ] | I-02 | Who owns the first top-level integration and which independently testable blocks must each collaborator deliver? | 2026-10-15: Robel requests leaving this as open work for whichever collaborator takes it. Claim the integration task before concurrent top-level edits; no person assigned here | Unassigned per Robel; collaborator review required |
| [ ] | I-03 | Which normal/fault walkthroughs establish readiness: framing, deadline miss, D-01/D-02/D-03, incomplete C, lost ACK, duplicate commit, resets and clock restart? | | |
| [ ] | I-04 | Which required diagrams/contracts and executable tests belong to the next increment? Who provides reproducible build/programming commands and records evidence? | | |
| [ ] | I-05 | Which remaining questions block the first increment, which have bounded experiments, and which are explicitly deferred with an owner and revisit point? | | |
| [ ] | I-06 | Does the roadmap need re-estimation after tonight's scope and hardware/clock findings? What is each person's next task? | | |
| [ ] | I-07 | Who reconciles this planning branch with An's merged kickoff and corrects its CI formatting errors? See [integration follow-up](development.md#integration-follow-up) | | |
| [ ] | I-08 | Does the ownership wording "stereo FIFOs" describe only an area of responsibility, or a selected mechanism? Reconcile it with the still-open topology without silently choosing hardware | 2026-10-15: Ownership wording reconciled to coherent frame transport/buffers in the selected common audio/DSP domain; no internal async FIFO selected. | |

Planning exit is not marked complete by this checkpoint: physical board identity/timing checks and shared-interface review are still evidence gates. For the first increment, both must explain its audio/control boundary; critical hardware/clock evidence is available or explicitly blocked; relevant interfaces have reviewed ownership, timing/reset/fault contracts; D-01/D-02/D-03 have a credible proposed enforcement and acceptance scenarios; and remaining work has explicit owners/dependencies. Marking this worksheet complete is not evidence of working audio, synthesis, timing closure or hardware validation.
