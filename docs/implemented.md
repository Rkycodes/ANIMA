# ANIMA — Implemented & Verified

Evidence baseline: October 23, 2026. Maintained by Robel Yaee and An Tiet. This document describes current repository behavior and actual checks. [Planning & Design](planning.md) owns requirements, future acceptance and open decisions. A passing model test is not audio or FPGA validation.

## Contents

- [Current implementation](#current-implementation)
- [Serial-timing component](#serial-timing-component)
- [Warm-reset controller](#warm-reset-controller)
- [I2S receiver](#i2s-receiver)
- [RX frame queue](#rx-frame-queue)
- [Frame scheduler](#frame-scheduler)
- [I2S transmitter](#i2s-transmitter)
- [Bypass core and watchdogs](#bypass-core-and-watchdogs)
- [Diagnostic counters](#diagnostic-counters)
- [Python preset and frame model](#python-preset-and-frame-model)
- [Reproduce current checks](#reproduce-current-checks)
- [Checks actually performed](#checks-actually-performed)
- [Vivado clock-configuration evidence](#vivado-clock-configuration-evidence)
- [Tools and workflow](#tools-and-workflow)
- [Repository map](#repository-map)
- [Evidence still missing](#evidence-still-missing)

## Current implementation

| Area | What exists | Practical limit |
| --- | --- | --- |
| System design | Selected bypass contracts, proposals/open decisions, source register and diagrams | Requirements, not implemented audio |
| Python control behavior | Preset lifecycle, validation, immutable snapshots, frame snapshot references and 20 tests | Software behavioral model; no fixed-point DSP or bounded FPGA storage |
| Repository tooling | Standard-library checker and GitHub Actions repository-check job | Hosted CI does not run model tests, RTL simulation or Vivado |
| Vivado investigation | Device/version/license query and in-memory Clocking Wizard probe | No synthesis, implementation, routed timing or audio executable |
| Hardware | Basys 3 D.1 on hand, reported by Robel | No board programming, measured clocks or accepted audio result |
| Timing RTL | Fixed-ratio serial-timing component and independent component testbench; lint and six seeded simulation runs passed | Integrated processing-clock core below; no board clock/pad wrapper or XDC |
| Warm-reset RTL | Pending-request controller, timing-connected bench and Verilator runner; lint and three seeded runs passed | Core RX/queue/scheduler/TX flush below; button conditioning and clock supervision remain pending; diagnostic storage is now connected below |
| I2S receiver RTL | Separate L/R assembly, registered E+1 pair event and snapshotted 32-bit ID; lint and three Verilator seeds passed | RX queue and short DAC-side component-chain checks below; no cold supervisor or physical ADC validation |
| RX frame queue RTL | Stored-head 80-bit FIFO, default depth 2; lint and 12 depth/seed cases plus three receiver-to-queue runs passed | Core watchdog/recovery integration below; counters/sticky flag connected below; no LED pad or hardware timing evidence |
| Frame scheduler RTL | Expected-ID selection and owned next-due waiting register | Waiting-state watchdog observations and core integration below; no cold supervisor or accepted board bypass build |
| I2S transmitter RTL | Captures scheduler-selected L/R and serializes 24-bit I2S with zero padding | Component/chain simulation described below; no board build or hardware acceptance |
| Bypass core / watchdog RTL | Processing-clock core and independent 2048-cycle RX/TX progress monitors | Functional simulation only; no clock generator, cold supervisor, pad wrapper or hardware acceptance; counters are connected below |
| Diagnostic RTL | Five unsigned 32-bit saturating counters, independent evidence reset, sticky fault and qualified clear | Functional storage/core integration; physical LED/buttons, clock-loss detector and telemetry snapshot remain pending |
| Firmware / host UART | Directory scaffold only | No firmware or serial utility |

Planning history from docs/planning and An's outstanding python-model commits is included in main at [36dd5d0](https://github.com/Rkycodes/ANIMA/commit/36dd5d07e64754fa7fb265113c94a33a4a0c0f85). An's original commits/authorship are retained; integration corrected whitespace only in two incoming Python files. No model behavior was changed by that merge or this documentation rewrite.

## Serial-timing component

Implemented October 22, 2026: [anima_serial_timing.v](../rtl/audio/anima_serial_timing.v) advances an unsigned 11-bit phase modulo 2048. Registered MCLK/SCLK/LRCK take pre-edge phase bits 2/4/10; combinational enables and channel/slot metadata describe the edge about to execute. Hard reset asynchronously clears phase/pins and masks enables/metadata. The existing ports and fixed cycle ratios are unchanged; their exact representations and pre-edge convention are in the [block contract](planning.md#serial-timing-block-contract).

All internal logic uses audio_clk; the serial outputs are external waveforms. The block has no warm-reset input, so the later audio-data reset must not drive its hard reset. Warm-reset application now has a separate [controller component](#warm-reset-controller). A physical clock generator, synchronized hard-reset-release wrapper and complete RX-to-TX data path remain unimplemented.

The independent [SystemVerilog bench](../sim/audio/anima_serial_timing_tb.sv) uses elapsed processing edges to check the public interface, with no reads of internal DUT state. It tests frame wrap, all bit/channel boundaries, reset without a clock edge, pin/event alignment and seeded reset offsets. Default seed is 2026; initial regression seeds remain 1, 42 and 2026. This bench validates timing only, not sample transport or five minutes of audio.

The [focused runner](../scripts/run_serial_timing.py) supports Windows Vivado Simulator and native/WSL Verilator. From the root, with Python 3.12:

```sh
python scripts/run_serial_timing.py --lint
python scripts/run_serial_timing.py --case phase
python scripts/run_serial_timing.py --case clocks
python scripts/run_serial_timing.py --case events
python scripts/run_serial_timing.py --case all --simulator verilator --seed 2026
```

Verilator is the default simulator. Current increments use Verilator only; Vivado remains an explicit option for later investigation. If explicitly using Vivado, set --vivado-bin if its installation differs from the detected location. Use --waves with Vivado to record a waveform database. Generated logs/builds stay under ignored build/serial_timing/. The runner requires a unique TIMING_PASS marker as well as successful tool execution, so a simulator returning zero after a fatal assertion cannot falsely pass.

**Component results, October 22:** Verilator Verilog-2001 lint passed. The checked-in implementation passed case all for seeds 1, 42 and 2026 in both Vivado Simulator and WSL Verilator, using the existing independent bench unchanged except for its introductory comment. Each run used eight directed frames plus four seeded reset sequences; observed edge totals were 28,439 / 27,284 / 27,817 respectively in each simulator. Checks cover phase advance/wrap, pin ratios, pre-edge enable/metadata timing, 64 SCLK rises and falls per frame, channel boundaries and asynchronous hard-reset masking. Per-seed simulation logs are under ignored build/serial_timing/{vivado,verilator}/simulate-seed-<seed>.log. These component runs are not the required five minutes of simulated audio. Touched-file UTF-8/no-BOM, LF, whitespace, Python parsing, Markdown structure and 74 local-file/heading links passed. At the commit boundary, repository checks and the Verilator-default lint/seed-2026 run passed. The Python regression result is recorded below; it is not fully passing.

**Historical harness checks, October 17:** the unfinished starter compiled but failed its phase test as expected. A temporary reference passed seeds 1, 42 and 2026 in both simulators, and Vivado waveform recording worked. Four deliberately faulty variants were rejected: advance-by-two, wrong MCLK ratio, late capture enable and synchronous-only reset. Temporary reference sources were removed. These earlier results establish harness checks; the October 22 results above test the actual implementation.

## Warm-reset controller

Implemented October 22, 2026: [anima_warm_reset_controller.v](../rtl/audio/anima_warm_reset_controller.v) stores a qualified request until the next left boundary. Its pre-edge combinational application includes a fresh request on the boundary itself, coalesces further pending requests and clears pending on application. Hard reset clears pending and masks application asynchronously. The exact single-bit input/output contract is in [Planning & Design](planning.md#warm-reset-controller-interface).

This component selects an edge; it does not reset the timing generator. The receiver component below now consumes warm-reset application and tests RX assembly/ID restart. The RX queue now also consumes that reset in the component integration test below. Scheduler/TX and shared core flush are now implemented and checked in the later sections. Button synchronization/debounce, cold qualification and stopped-clock supervision remain pending; diagnostic storage is connected below.

The independent [SystemVerilog bench](../sim/audio/anima_warm_reset_controller_tb.sv) instantiates the real timing block and assigns each request an absolute edge deadline based on elapsed edges. It checks the public interfaces without reading internal DUT state. A stand-in data register checks same-edge reset priority over ordinary work; it is not an audio source/sink or complete data-path model. Directed cases cover no-request operation, short off-boundary requests, repeated-request coalescing, requests on/just after/just before a boundary, pending plus a new boundary request, consecutive requested boundaries, hard reset while pending/application is visible and final drain. Seeded requests and hard resets add randomized timing coverage. The bench continuously checks that timing phase, serial pins and enables continue correctly across warm-reset application.

Run with native/WSL Verilator; no Vivado command is used:

```sh
python scripts/run_warm_reset.py --lint
python scripts/run_warm_reset.py --seed 2026
```

Default random duration is 16 frame units, in addition to directed checks; --frames changes this component stimulus duration. It does not represent an audio-duration acceptance test. The runner requires successful tool execution and exactly one WARM_RESET_PASS marker. Per-seed logs are under ignored build/warm_reset/verilator/simulate-seed-<seed>.log.

**Actual results:** Verilog-2001 controller lint passed. Seeds 1, 42 and 2026 passed, each with 64,790 processing edges. Applied/coalesced/hard-reset-aborted counts respectively were 19/230/10, 21/218/8 and 19/234/11. The existing timing block is unchanged from [4b26b15](https://github.com/Rkycodes/ANIMA/commit/4b26b155ae086d1071c529e768a752250184ce47). Only focused controller checks were run after that commit; the Python model error recorded below remains unresolved. No full bypass, five-minute audio run, synthesis or hardware validation is established.

## I2S receiver

Implemented October 22, 2026: [anima_i2s_receiver.v](../rtl/audio/anima_i2s_receiver.v) captures MSB-first payload positions 1–24 into separate signed 24-bit L/R registers. It ignores the preceding-word tail and padding. On final right-bit capture edge E, it registers pair_complete, snapshots the unsigned 32-bit ID and increments the next ID modulo 2^32. The queue-side consumer samples the completed values and event on E+1. There is no ready input; an eventual full queue must reject a complete offer without pausing capture or its ID sequence. Exact representations and lifetime are in the [receiver contract](planning.md#receiver-block-contract).

RX hard reset asynchronously clears assembly, ID and completion state; after release, collection waits for a left boundary. Its reset can stay asserted while serial timing runs, leaving cold qualification to the future supervisor. The shared warm-reset controller clears RX state at its boundary and starts fresh frame-zero collection in that same interval. This is tested component integration, not completed cold startup or a bypass top.

The [receiver bench](../sim/audio/anima_i2s_receiver_tb.sv) supplies ADC data after modeled falling serial edges, then independently scores expected source L/R values and IDs at E+1. Its default mode uses the real timing/reset components and an admission witness; the optional queue suite below additionally connects the implemented FIFO. Directed vectors include zero, signed extremes, LSB-sensitive and distinct-channel patterns; later pairs are seeded random values. Nonzero tail/padding, held RX reset while clocks run, mid-frame reset release, warm reset around channel/payload/handoff boundaries, pending-offer hard-reset cancellation and queue-rejected offers are checked. A continuous 258-frame segment exercises the low-byte ID carry. One explicit test-only hierarchical force/release seeds the next-ID register to 0xfffffffe for bounded full-width rollover coverage; subsequent public pair IDs/data are independently scored. This is not a run of 2^32 frames and adds no production seed port or parameter.

```sh
python scripts/run_i2s_receiver.py --lint
python scripts/run_i2s_receiver.py --seed 2026
```

The [Verilator-only runner](../scripts/run_i2s_receiver.py) defaults to 32 randomized frame units after directed cases, requires a unique I2S_RX_PASS marker and keeps logs under ignored build/i2s_receiver/verilator/simulate-seed-<seed>.log. **Actual results:** Verilog-2001 lint passed; all three seeds passed with these processing-edge / published-pair / admission-rejection / warm-reset counts: seed 1, 706631 / 324 / 8 / 27; seed 42, 706638 / 326 / 10 / 33; seed 2026, 706617 / 327 / 10 / 33. Each run covered one cancelled offer and one seeded 32-bit rollover. Rejections count witness decisions, not implemented hardware overflow counters. Clock/reset and existing model sources were preserved. No full repository/model rerun was performed in this component increment; the existing Python model error remains recorded below.

The RX queue is now implemented and tested below. Scheduler/transmitter/core integration follows below. Queue-overflow counters/LED, five-minute simulated audio, synthesized implementation and hardware audio results remain pending.

## RX frame queue

Implemented October 23, 2026: [anima_rx_frame_queue.v](../rtl/audio/anima_rx_frame_queue.v) stores complete 80-bit L/R/ID entries in a synchronous FIFO. DEPTH defaults to 2; only 1/2/4/8 are legal. Pointer/count widths derive from DEPTH with depth-1-safe wrapping. Head data and valid depend on stored state, not incoming data or ready. Enqueue on Q first permits downstream acceptance on Q+1; for the receiver this is E+2 after final right-bit capture, leaving 238 processing cycles to the next left boundary before remaining scheduling work. The exact interface is in the [queue contract](planning.md#rx-frame-queue-block-contract).

A full FIFO can dequeue and enqueue on the same edge without overflow, including depth 1. Otherwise it preserves the stalled head and rejects the new whole pair. Its combinational overflow_event is available before the rejecting edge; repeated rejected offers count as separate edge-qualified events. The queue has no overflow counter, LED or watchdog. Hard reset and shared warm flush clear occupancy/pointers and mask valid, data and overflow. Payload storage need not be erased because invalid entries cannot be exposed or replayed.

The independent [queue cases](../sim/audio/anima_rx_frame_queue_tb.sv) compare the public interface against a SystemVerilog dynamic-list model at each edge, without inspecting RTL storage/pointers. Each depth has directed empty-ready arrival, stall, overflow, full replacement, sustained transfer, pointer wrap, hard-reset and warm-reset collision checks plus seeded random offers/ready/flushes and hard resets. Inputs continue changing while the output head stalls. A positive seed plus depth initializes a nonzero xorshift state.

With ANIMA_RX_QUEUE_TEST defined, the existing [receiver bench](../sim/audio/anima_i2s_receiver_tb.sv) also instantiates all four queue cases and a [real receiver-to-queue monitor](../sim/audio/anima_rx_queue_chain_probe.sv). The original independent ADC source/sample/ID scoreboard remains active. The chain monitor separately scores accepted/rejected queue offers, stored output order and flushes at default depth 2. Together they check final-bit capture on E, queue ingress on E+1, stored-head downstream transfer from E+2, random stalls, complete-pair rejection and aligned reset/ID restart. The receiver's original standalone mode remains available without this define.

```sh
python scripts/run_rx_frame_queue.py --lint
python scripts/run_rx_frame_queue.py --seed 2026
```

The [Verilator-only runner](../scripts/run_rx_frame_queue.py) defaults to 10000 randomized cycles per queue depth, in addition to directed cases and the existing 32-frame-unit receiver stimulus. --cycles accepts 1–100000 and does not represent simulated audio duration. Lint covers all four supported depths and checks that depth 3 fails elaboration. Generated logs remain under ignored build/rx_frame_queue/. Success requires unique pass markers for all four depth cases and the complete suite; the chain itself checks a final empty queue before reporting success.

**Validation status:** strict Verilog-2001 lint passed at depths 1/2/4/8; unsupported depth 3 was rejected with the intended configuration diagnostic. The receiver bench also passed timing-aware lint in its standalone mode. With the corrected nonzero random generator, seeds 1/42/2026 each passed all four depths (12 cases), each using 10000 random cycles plus directed checks. The real receiver-to-default-depth queue chains accepted 322/324/325 pairs respectively, each reporting two deliberate overflow events, and all drained cleanly. The original independent receiver checks also passed in those runs. The initial test-only zero-state seed issue was corrected; queue RTL did not change. Per-seed logs are build/rx_frame_queue/verilator/simulate-seed-<seed>.log. Touched-file UTF-8/LF/whitespace, Python parsing, Markdown structure and 100 local links passed. At the October 23 commit boundary, the repository checker and queue lint/seeded regressions passed again. The Python model regression reported 19 passing tests and the previously recorded end_frame signature error; model/test sources remain unchanged. No scheduler, TX, diagnostic counter/LED, five-minute audio acceptance, synthesis or hardware result is established.

## Frame scheduler

Implemented October 23: [anima_frame_scheduler.v](../rtl/audio/anima_frame_scheduler.v) owns one next-due waiting pair and the unsigned 32-bit playback schedule. It advances only on runtime left boundaries, selects whole-pair zero on underflow, drains late data, blocks future data, and supports empty-slot deadline-edge acceptance plus promotion/replacement. The first hard-reset boundary and warm-reset boundary select intentional silence without underflow. Samples are signed 24 bits. The pre-edge selection transaction must be captured by the future TX serializer; it is not a registered current-output buffer. [Exact interface](planning.md#frame-scheduler-block-contract).

TX_WAIT_DEPTH accepts 1/2/4/8 and rejects unsupported values. The next-unfilled-slot policy permits only one reservation, so larger configurations do not allocate extra bypass storage or authorize future prefetch. Half-range IDs raise ambiguous_id_event and cannot transfer or play. The integration assertion must reject this stream violation; no sixth error counter is introduced.

The [case bench](../sim/audio/anima_frame_scheduler_case.sv) uses an independent interval/reservation-list model and the real timing block. The [suite](../sim/audio/anima_frame_scheduler_tb.sv) instantiates all four configurations. Directed checks cover startup, reserved-head backpressure, promotion/replacement, exact-edge direct acceptance, missed deadlines, stale/future inputs, warm reset and modulo-ID rollover. Rollover uses one explicit test-only counter seed, not billions of frames or a production test port. Each case then runs 120000 randomized processing edges with stable stalled offers and boundary-qualified resets. A separate negative run makes the half-range input fail the integrating assertion.

```sh
python scripts/run_frame_scheduler.py --lint
python scripts/run_frame_scheduler.py --seed 2026
```

The [runner](../scripts/run_frame_scheduler.py) uses Verilator only and saves build/logs under ignored build/frame_scheduler/. **Actual results:** strict Verilog-2001 lint passed at depths 1/2/4/8 and unsupported depth 3 failed elaboration as intended. Final bench seeds 1/42/2026 each passed all four configurations: 12 cases, each with 120000 randomized edges plus directed checks and final drain, totaling 147461 processing edges per case. Each seed also rejected the deliberately ambiguous half-range stream through the integrating assertion. No lint warnings were waived. Touched-file UTF-8/no-BOM, LF/whitespace, Python parsing and 107 local-file/heading links passed. At the authorized scheduler commit boundary, the repository checker and all scheduler lint/seeded checks passed again. The Python model suite, run from the repository root, reported 19 passing tests and the unchanged known end_frame signature error; no model sources were changed. This is component scheduling verification, not receiver-to-TX integration, 300 seconds of simulated audio, synthesis, routed timing or hardware audio validation. No watchdog, diagnostic counters, serializer or cold-start supervisor is implemented here.

## I2S transmitter

Implemented October 23: [anima_i2s_transmitter.v](../rtl/audio/anima_i2s_transmitter.v) captures the scheduler-selected signed 24-bit L/R pair together, then drives one registered serial bit on each authorized SCLK falling edge. Slots 1–24 emit bits 23–0; slot 0 and slots 25–31 emit zero. Inputs may change while current serialization continues; no ready/valid handshake or future-pair storage exists in this block. Shared warm reset clears the current pair/data at a left boundary without resetting serial timing. [Port contract](planning.md#i2s-transmitter-block-contract).

The [testbench](../sim/audio/anima_i2s_transmitter_tb.sv) checks a directly driven transmitter while changing its selection bus every processing clock. An independent elapsed-edge oracle checks every output-bit launch, rising-edge capture, intervening hold cycle, channel position and serial clock waveform. It also connects the real timing, warm-reset controller, ADC receiver, RX queue, scheduler and a second TX. A behavioral ADC supplies signed extrema, zero, alternating bits and asymmetric frame/channel patterns, with arbitrary tail/padding bits. A DAC-side decoder reconstructs actual output-pin samples and compares whole pairs against source-derived next-slot expectations, including schedule IDs. It does not feed TX output back into the expected source.

Directed tests cover asynchronous hard reset during right payload and padding, off-boundary/coalesced reset requests, same-boundary application and intentional startup/reset zeros. Randomized requests run for 96 frame units, followed by completion of the current interval and two complete frames. Every pair in those checked slots is decoded, including intentional silence. Acquisition continues during the final two checked output frames, so a newly captured pair can remain buffered when simulation ends; this does not establish final drain for full bypass acceptance. This is a short behavioral component-chain regression, not a 300-second acceptance run or a board-ready top-level design. Watchdog integration is covered below. Five-minute regression, diagnostic counters, cold qualification, physical clock supervision, I/O constraints and board integration remain outstanding.

```sh
python scripts/run_i2s_transmitter.py --lint
python scripts/run_i2s_transmitter.py --seed 2026
```

The [runner](../scripts/run_i2s_transmitter.py) uses Verilator only, requires a unique pass marker and stores logs/builds under ignored build/i2s_transmitter/. **Actual results:** Verilog-2001 lint passed without waivers. Seeds 1/42/2026 each passed 212296 processing edges, reconstructing 103 stereo pairs from each transmitter (standalone and connected chain), with three asynchronous hard resets per run. Warm-reset applications were 27/22/19 respectively. The initial run reached the end with bit/pair checks passing but failed an overly high normal-frame coverage threshold; the test-only threshold was corrected because intentional warm-reset slots are excluded from that normal-frame count. All three results above use the corrected bench; serializer RTL was unchanged. The six touched files passed UTF-8/no-BOM, LF/whitespace and Python parsing checks; 114 local-file/heading links passed. At the authorized TX commit boundary, repository checks, TX lint and all three seeded TX/component-chain regressions passed again. The unchanged Python model suite reported 19 passing tests and the previously recorded end_frame signature error; no model files were changed. No synthesis, routed timing, programmed FPGA or hardware audio result is claimed.

## Bypass core and watchdogs

Implemented October 23: [anima_bypass_core.v](../rtl/audio/anima_bypass_core.v) wires timing, reset control, receiver, RX queue, scheduler and transmitter in production RTL. It accepts a processing clock, global reset and separate data qualification reset. Serial clocks run during data reset and warm recovery. No test stall controls, DSP or control-interface dependency are added. RX_DEPTH/TX_WAIT_DEPTH retain defaults 2/1 and legal depths 1/2/4/8. [Interface and exact edge rules](planning.md#bypass-core-and-progress-watchdog-interfaces).

[anima_audio_watchdogs.v](../rtl/audio/anima_audio_watchdogs.v) maintains separate unsigned 11-bit RX/TX no-progress timers. RX observes actual accepted head transfers, including stale discard. TX observes scheduler waiting occupancy and actual promotion through two added one-bit observation outputs; current serialization and direct empty-slot selection are excluded. The first pre-edge nonempty/no-progress observation counts one, and the 2048th registers one event/request. Progress or empty on the threshold edge prevents expiry. Requests coalesce until shared warm reset; simultaneous expiry emits one event. Registered request staging avoids reset/handshake combinational feedback. Diagnostic storage is now connected below; board LED wiring remains pending.

The [watchdog bench](../sim/audio/anima_audio_watchdogs_tb.sv) uses integer elapsed-age reference counters, with no DUT-state reads. Directed checks cover each timeout alone, simultaneous expiry, progress/empty on the threshold edge, reset on expiry, hard reset of pending recovery and suppression of repeated events; 10000 randomized monitor cycles follow. The [recovery bench](../sim/audio/anima_bypass_recovery_tb.sv) holds data reset while timing runs, releases between boundaries, then injects an RX-only stall before first reservation and a TX-promotion stall after a complete pair enters waiting storage. It forces only the scheduler's internal started state for fault injection, then releases that force before the shared reset edge. Public clock/event/selection observations verify one pending request and boundary application per incident, fresh frame IDs 0/1 after each recovery and no serial-clock reset. This is an explicitly bounded fault injection, not a production stall input or proof against arbitrary corruption.

The [core bench](../sim/audio/anima_bypass_core_tb.sv) adapts the independent ADC/DAC oracle from the TX bench and instantiates all 16 RX/TX depth combinations. Every core's serial bits, clocks, boundary selection and expected frame IDs are checked against elapsed-edge/source-derived expectations; normal operation also requires no overflow, underflow, late-discard, ambiguous-ID or timeout events. Known signed patterns and arbitrary ADC padding, 96 randomized-request frame units, directed resets and two final output frames remain the short serial regression. Reference clock edges use behavioral testbench time steps, not an assertion of the first-build physical clock frequency. Acquisition continues at test end, so the separate 300-second acceptance test still needs a finite scoring horizon/final drain.

```sh
python scripts/run_bypass_core.py --lint
python scripts/run_bypass_core.py --seed 2026
```

[run_bypass_core.py](../scripts/run_bypass_core.py) uses Verilator only and saves logs under ignored build/bypass_core/. Lint passed for all 16 legal configurations. **Actual results:** final seeds 1/42/2026 each passed 212296 processing edges across all 16 depth configurations, checking 103 stereo pairs per configuration against source-derived expected bits; the reference configuration also reconstructs the complete DAC-side words. The watchdog reference passed 32535 test edges per seed, including five directed incidents and 10000 randomized monitor cycles. Each core-recovery run passed 20513 edges with two timeout incidents, two boundary applications, four verified fresh playback IDs and zero overflows. Warm applications in the normal depth matrix were 27/22/19, with three global hard resets per seed. No warnings were waived. Scheduler observation-output compatibility passed legal-depth lint and seed 2026 at all four depths, including the negative half-range assertion test. Existing TX standalone/connected-chain compatibility passed seed 2026 (212296 edges, 103 decoded pairs per transmitter, 19 warm applications and three hard resets). The 12 touched files passed UTF-8/no-BOM, LF/whitespace and Python parsing checks; 128 local-file/heading links passed. At the authorized core/watchdog commit boundary, the repository checker, 16-depth lint and three seeded core/watchdog/recovery suites passed again. The unchanged Python model reported 19 passing tests and the known end_frame signature error; no model files were changed. No 300-second acceptance, synthesis, routed timing, programmed FPGA or hardware audio validation is established.

## Diagnostic counters

Implemented October 23: [anima_audio_diagnostics.v](../rtl/audio/anima_audio_diagnostics.v) stores independent unsigned 32-bit underflow, overflow, late-discard, stall-timeout and recovered-clock-loss counts plus a sticky fault level. Each count saturates at 0xffffffff. Clear/new-event collisions yield 1 for affected counters, 0 for the rest and a set sticky flag. No event, counter or readout can stall audio. [Detailed port/reset contract](planning.md#diagnostic-storage-block-contract).

The bypass core now wires its four audio fault event classes into this storage and accepts a qualified recovered_clock_loss_event input. diagnostic_reset_n is a separate initialization/reconfiguration reset; neither the global audio reset, data reset nor warm application resets this evidence. diagnostic_clear is a qualified audio-domain action. These are concrete core ports, not a UART packet map, asynchronous button interface or implemented clock supervisor. The sticky output is available for future LED0 board wiring; no physical LED behavior is claimed.

The [independent bench](../sim/audio/anima_audio_diagnostics_tb.sv) uses wider integer arithmetic to score every counter and sticky state. Directed cases exercise each class, simultaneous classes, consecutive event edges, all 32 same-edge clear/event masks, idle retention, asynchronous initialization and initialization priority. Saturation uses an explicit bounded hierarchical seed of the five output registers to 0xfffffffe, then checks maximum/hold/clear; it does not simulate billions of events or add a production debug port. Each seed also runs 10000 randomized event/clear cycles with randomized diagnostic initialization.

Core integration extends the existing tests: all 16 depth configurations receive random clear actions while source-derived serial playback continues unchanged and counters stay zero during normal/reset silence. The recovery bench checks two actual watchdog incidents survive both warm recoveries and a later data/global audio reset. A synthetic qualified supervisor event checks recovered-clock counting and clear/new-event priority; it is not evidence that stopped-clock detection, reference-side retention or CDC has been implemented.

```sh
python scripts/run_audio_diagnostics.py --lint
python scripts/run_audio_diagnostics.py --seed 2026
python scripts/run_bypass_core.py --seed 2026
```

The [diagnostic runner](../scripts/run_audio_diagnostics.py) uses Verilator only and saves logs under ignored build/audio_diagnostics/. Diagnostic Verilog-2001 lint passed. Seeds 1/42/2026 passed 10104 test edges each, including 10000 randomized event cycles; sampled class-event totals were 25387/25153/25103, clear actions 178/205/191 and initialization actions 151/152/168. Integrated core lint passed all 16 legal depth combinations. Updated core seeds 1/42/2026 passed all 16 depth combinations again: 212296 processing edges and 103 checked stereo pairs per configuration, including random clear actions without playback changes. Each extended recovery run passed 20548 edges, preserved both actual timeout counts through warm/data/global audio resets, and passed synthetic recovered-clock and clear/new-event checks. The unchanged watchdog reference still passed five directed incidents per seed. No lint warnings were waived. The 10 touched files passed UTF-8/no-BOM, LF/whitespace and Python parsing; 136 local-file/heading links passed. At the authorized diagnostics commit boundary, repository checks, diagnostic lint/three-seed tests and integrated core lint/three-seed tests passed again. The Python model remains unchanged with 19 passing tests and the known end_frame signature error. No button conditioning, clock-loss supervision, live telemetry, 300-second acceptance, synthesis, routed timing or hardware audio result is established.

## Python preset and frame model

An Tiet's code lives in [sim/fpga_control_logic](../sim/fpga_control_logic). It is a call-driven model, not a clocked simulation.

| File | Implemented behavior |
| --- | --- |
| [preset.py](../sim/fpga_control_logic/preset.py) | Frozen PresetConfig and PresetSnapshot; mutable wrapper with DRAFT/PENDING/ACTIVE/SUPERSEDED/REJECTED/RETIRED states |
| [preset_manager.py](../sim/fpga_control_logic/preset_manager.py) | Validate, copy accepted fields into immutable snapshots, latest valid pending replacement, activation and frame snapshot assignment |
| [audio_frame.py](../sim/fpga_control_logic/audio_frame.py) | AudioFrame carries ID, L/R values, snapshot reference and RECEIVED/EQ_DONE/COMPLETE label |
| [test_preset_manager.py](../sim/fpga_control_logic/test_preset_manager.py) | 12 lifecycle/validation tests |
| [test_frame_snapshots.py](../sim/fpga_control_logic/test_frame_snapshots.py) | 8 startup, snapshot lifetime/immutability and generation tests |

Construction submits a pending startup preset (bypass true, input gain 0 dB), generation 1. It remains pending until activation; a valid user preset may supersede it. submit accepts only draft requests and validates Boolean bypass plus finite numeric input gain within **example** ±12 dB limits. Boolean gain, wrong types, NaN/infinity and out-of-range/huge integers are rejected without replacing valid pending/active values. These limits are not frozen production DSP controls.

Each valid submission copies fields into a frozen snapshot and allocates an increasing Python integer generation. Replacing the caller's mutable request config after validation cannot alter that accepted snapshot. Invalid submissions do not consume generations; superseded generations may be skipped at activation. activate retires the old request, installs pending/snapshot and clears pending; with none pending it does nothing.

begin_frame calls activate and gives a new frame the active snapshot reference. Frames without updates share one snapshot. Tests demonstrate frame 10 retaining A after frame 11 begins under B, including A after end_frame marks frame 10 COMPLETE. Retiring a request does not invalidate an older frame's snapshot. end_frame changes a label; it does not manage a hardware bank or execute DSP.

### Model limitations

Model frame IDs are strings and L/R values are Python floats, unlike the hardware contract's unsigned 32-bit ID and signed 24-bit samples. Generations are unbounded Python integers. Calls establish ordering; there is no processing clock, serial timing, frame-slot schedule, valid/ready, reset/clock-loss model, CDC or hardware reclamation.

Python references retain snapshots without a finite protected-generation capacity/full policy. Request wrappers and AudioFrame objects remain mutable; this is not adversarial API isolation. Snapshot values are the accepted authority, even if a wrapper is later edited. EQ_DONE is not implemented EQ. Direct activate calls are possible; no physical frame-boundary enforcement or simultaneous replacement/activation arbitration is proven. Frozen snapshots demonstrate retention without selecting the FPGA mechanism. Production defaults, generation wrap/reconnect, parameter maps and DSP arithmetic remain [open decisions](planning.md#open-decisions).

## Reproduce current checks

Use Python 3.12 from the repository root:

```sh
python scripts/check_repo.py
python -B -m unittest discover -s sim/fpga_control_logic -v
```

Windows may use py -3.12 in place of python. The explicit nested directory matters: discovery from sim alone currently finds zero tests because fpga_control_logic is not a Python package. Some inherited test docstrings still show that old command; use the command above and confirm **20 tests** rather than accepting an empty run. No extra model dependencies are required.

The checker validates required files/configuration, UTF-8/text formatting, Markdown structure, local file/heading links and diagram assets. External URLs have review records in the [source register](planning.md#source-register); offline checking does not establish current remote availability. The checker is not a Mermaid renderer, behavioral test runner, RTL linter or hardware test.

The workflow [.github/workflows/ci.yml](../.github/workflows/ci.yml) currently runs the repository checker on main pushes, PRs and manual dispatch with Python 3.12 and pinned actions. Model tests are separate; adding them to hosted CI remains a future tooling task.

## Checks actually performed

| Check / scope | Result and limits |
| --- | --- |
| Branch integration, October 15 | All fetched local/remote tips were ancestors of main after 36dd5d0; origin/main pushed. Existing branch names retained |
| Repository checker, merged Python branch | Passed after incoming whitespace corrections; no model behavior change |
| Python model regression, October 15 | 20 tests passed with nested-directory command; historical behavioral-model result |
| Commit boundary, October 22 | Repository checker and timing lint/default Verilator simulation passed; Python model: 19 passed, one error in test_frame_10_retains_a_until_completion_while_frame_11_uses_b because PresetManager.end_frame lacks self. Model/test files match base c9a2c1c and were not changed in this increment |
| Prior planning checkpoint | Repository and supplemental local-file/heading/UTF-8 checks passed; six diagram assets checked. Timing SVG rendered with sharp and visually inspected |
| Vivado / device | 2026.1 SW 6511674 / IP 6504888; BASIC license detected; xc7a35tcpg236-1 recognized |
| Clock configuration | In-memory Clocking Wizard 6.0 returned settings below; no synthesis or physical clock measurement |
| Verilator availability | WSL Ubuntu /usr/bin/verilator previously reported 5.032, 2025-01-01, Debian 5.032-1; now used for component lint/regression as recorded below |
| Serial timing, October 22 | Verilog-2001 lint and case all, seeds 1/42/2026, passed in both Vivado Simulator and WSL Verilator; timing component only |
| Warm reset, October 22 | Verilator Verilog-2001 lint and seeds 1/42/2026 passed; real timing plus stand-in consumer, not complete audio integration |
| I2S receiver, October 22 | Verilator lint and seeds 1/42/2026 passed; E+1 pair/data/ID scoreboard, real timing/reset, admission witness and explicit bounded rollover seed |
| RX frame queue, October 23 | Verilog-2001 lint depths 1/2/4/8 passed, depth 3 rejected; seeds 1/42/2026 passed all four depths and real receiver-to-queue integration. Original receiver standalone mode passed timing-aware lint |
| Mermaid rendering | Mermaid/mmdc unavailable; manually reviewed syntax and retained editable sources. No rendered-Mermaid verification claimed |

Consolidation checks passed on October 15: repository formatting/local-file/heading links and diagram integrity; a valid checker fixture plus nine deliberate failure cases (broken heading/file/path, invalid UTF-8/LF, SVG, Mermaid header, metadata and missing required document); exact preservation of all 15 source-register rows. The Mermaid header check is not rendering. No five-minute audio simulation, synthesis, timing closure, board programming, analog capture or acoustic latency result exists.

## Vivado clock-configuration evidence

The October 15 probe used nominal 100.000 MHz input, requested 98.304 MHz output and xc7a35tcpg236-1. Temporary configuration files were outside the repository; project in memory. Returned MMCM input divider 1, feedback multiplier 7.250, output-0 divider 7.375.

Arithmetic gives processing 98.3050847458 MHz, /8 MCLK 12.2881355932 MHz, /32 SCLK 3.0720338983 MHz, /2048 stereo 48000.529661 Hz, or +11.034605 ppm from 48 kHz excluding oscillator tolerance. These are calculations from configuration, not measured clocks. Source-tolerance range and first-build requirements are in [Clock architecture](planning.md#clock-architecture).

### Reproduce configuration-only investigation

Save the following Tcl outside the repository or in ignored scratch storage, then run Vivado batch mode with that file as its source. Use a fresh temporary directory per run; this recipe adds a process-specific name. It does not generate/synthesize a design.

```tcl
create_project -in_memory -part xc7a35tcpg236-1
set probe_dir [file join $::env(TEMP) anima-clock-probe-[pid]]
file mkdir $probe_dir
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name anima_clock_probe -dir $probe_dir
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {98.304}] [get_ips anima_clock_probe]
report_property [get_ips anima_clock_probe]
```

Installed Windows entry: C:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat. Invoke with -mode batch -source followed by the saved Tcl path; run from ignored/scratch storage so logs do not become source files. Record version/options and preserve useful properties with future reports.

Wizard configuration does not prove routed resources, output pads, setup/hold, jitter compliance or codec readiness. Raw estimated jitter/phase-error fields were not promoted to claims because their units were unconfirmed. No legal operating-frequency or timing-closure claim is made from this probe.

## Tools and workflow

Use Verilator for current lint and simulation increments. Windows Vivado remains available for later clock investigation, simulation when specifically needed, synthesis, implementation, timing and programming; routinely running both simulators is not required. Current WSL use includes Verilator lint and timing-component simulation on this checkout; Vivado Simulator runs on Windows. If using separate Windows/WSL clones, synchronize commits and keep generated directories separate; report the same source revision for comparisons.

Synthesizable RTL uses Verilog-2001 (.v); SystemVerilog (.sv) may be used for verification. Audio models and host utilities use Python. Select/pin ESP32 board/framework/version before firmware; keep credentials out of Git. Pin model dependencies when introduced.

The focused timing runner compiles and simulates the implemented timing component. A processing-clock bypass core and reproducible Verilator source list now exist; a board build target is still missing. Add source-controlled Tcl and reviewed XDC with the board-level audio top; generate under ignored build/. Check exact hardware rather than downloaded guesses. Use synthetic impulses, tones, sweeps, silence and seeded noise for vectors.

Keep main usable, use focused PRs and report actual validation. Obtain Robel's approval before each commit boundary; new commits use his configured identity while preserving collaborator authorship. Run appropriate checks at commit boundaries rather than after every prose edit. Shared top-level wiring needs one claimed integration owner per increment.

## Repository map

| Path | Present purpose / state |
| --- | --- |
| [README.md](../README.md) | Entry point and planned system diagram |
| [planning.md](planning.md) / this document | Design requirements versus current evidence |
| [diagrams/](diagrams) | Five editable Mermaid sources and timing SVG |
| [config/project.json](../config/project.json) | Planning metadata; draft baud is not a frozen protocol |
| [rtl/](../rtl) | Timing, reset control, RX/queue/scheduler/TX, bypass core and progress watchdogs; diagnostic storage is connected; board integration and DSP remain pending |
| [model/](../model) | Reserved audio reference/bit-exact models |
| [sim/fpga_control_logic/](../sim/fpga_control_logic) | Current Python model/tests |
| [sim/audio/](../sim/audio) | Audio component benches, 16-depth core checks, watchdog reference and injected recovery checks |
| [firmware/esp32/](../firmware/esp32) | Reserved firmware area |
| [tools/serial_host/](../tools/serial_host) | Reserved PC UART diagnostics |
| [hardware/](../hardware) | Reserved assets; live inventory is in Planning & Design |
| [scripts/check_repo.py](../scripts/check_repo.py) | Repository checker |
| [scripts/run_serial_timing.py](../scripts/run_serial_timing.py) | Focused timing lint/simulation runner; Verilator default |
| [scripts/run_warm_reset.py](../scripts/run_warm_reset.py) | Focused Verilator-only warm-reset lint/simulation runner |
| [scripts/run_i2s_receiver.py](../scripts/run_i2s_receiver.py) | Focused Verilator-only receiver lint/simulation runner |
| [scripts/run_rx_frame_queue.py](../scripts/run_rx_frame_queue.py) | Verilator-only queue depths and real receiver integration runner |
| [scripts/run_frame_scheduler.py](../scripts/run_frame_scheduler.py) | Verilator-only scheduler depth/seed/invalid-ID runner |
| [scripts/run_i2s_transmitter.py](../scripts/run_i2s_transmitter.py) | Verilator-only TX and short audio-component-chain runner |
| [scripts/run_bypass_core.py](../scripts/run_bypass_core.py) | Verilator-only bypass depth matrix, watchdog thresholds and recovery runner |
| [scripts/run_audio_diagnostics.py](../scripts/run_audio_diagnostics.py) | Verilator-only fixed-width saturation, clear/event priority and sticky fault runner |
| [scripts/vivado/](../scripts/vivado) | Reserved build tooling |
| [results/](../results) | Reserved measured/release evidence; no audio measurements |
| [.github/](../.github) | CI and operational issue/PR templates, retained separately |

Former folder indexes, duplicate contract files and learning-note copies are folded into the two main documents. Empty scaffold areas retain .gitkeep files. Full An note history/credit is linked in [design history](planning.md#design-history-and-contribution-credit). Collaborator code/history is preserved.

## Evidence still missing

First audio milestone still needs button qualification/physical diagnostic wiring, actual codec/JP1/electrical checks, board clock/reset supervision and constraints, broader fault/retained-age verification, 300 seconds simulated audio with final drain, synthesis/routed timing and physical serial/audio measurements. The processing-clock bypass core and short component/integration benches exist; their results are above. Vivado directed investigation remains available when requested or needed. Analog/acoustic setup, tolerances and hard latency limit remain open; **5 ms is a goal**.

No working audio, DSP, deployed browser/VGA, firmware, synthesized design or hardware acceptance is claimed. Next: [codec → clock/reset → frame contract → bypass acceptance](planning.md#ownership-and-delivery), with An's UART/shadow proposal in parallel.
