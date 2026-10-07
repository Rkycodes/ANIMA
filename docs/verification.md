# Verification and release evidence

## Block checks

- I2S: known positive/negative samples, channel order, one-bit delay, slot padding, framing and reset.
- FIFOs/CDC: unequal clocks, reset in each domain, backpressure, overflow/underflow visibility.
- DSP: impulse, tones, sweep, silence, seeded noise, extremes; RTL equals the fixed-point model under defined rounding.
- EQ: response and stability after quantization, headroom and overload, live parameter transitions.
- Compression: attack/release, threshold/ratio, equal gain on both channels, saturation.
- Control: malformed/partial/duplicate packets, bad CRC, timeout, reset, retry, commit acknowledgement.
- Integration: disconnected controller and telemetry saturation leave audio running.

## Stereo bypass milestone

Robel and An selected stereo bypass as the first milestone on October 6, 2026. Requirements: testbenches passing Verilator lint and simulation, randomized inputs with assertion checking, known input/expected-output pairs, five consecutive minutes of simulated audio time without errors, and later hardware/audio preservation checks. The current continuous-run target is simulation only, not simulator wall time or a completed hardware run. No testbench or passing result exists yet.

The bypass acceptance plan below records the completed milestone-planning discussion; measurement tolerances and fault-contract details still need definition. They define observations, not RTL/FSM implementation. Fault expectations depend on agreeing the frame/reset contract before coding.

| Check | Stimulus / comparison | Proposed pass condition |
| --- | --- | --- |
| Verilator lint and simulation | Agreed source lists, tool version and enabled assertions; record exact commands/options | Lint and simulation succeed; no unexplained warnings, assertion failures or scoreboard mismatches; any accepted waivers documented |
| Deterministic digital bypass | Known paired L/R samples: zero, positive/negative values, signed limits, alternating patterns and distinct channel sequences | Decoded transmitted sample pairs equal received pairs bit-for-bit after the agreed delay, with correct order and no loss/duplication |
| I2S framing | Independent source/receiver models using agreed edge, LRCK, slot and padding rules | Correct channel identity, one-bit I2S delay and full payload; agreed padding; no frame slips |
| Reproducible randomized checks | Recorded random seeds; random sample pairs and legal timing/handshake variation; assertions plus independent expected-output scoreboard | Exact digital pairing/order/data checks hold across the agreed seeds and frame counts; no illegal stimulus is mistaken for a DUT fault |
| Startup/reset and fault recovery | Reset at different serial/frame phases; agreed missing/late-frame and clock-loss scenarios | Agreed safe output, no mixed or stale partial frames, visible errors and recovery within the agreed bound; behavior remains to be specified |
| Continuous run | Repeated deterministic vectors plus seeded random frames; log duration/frame count, seeds and error counters | Five consecutive minutes of simulated audio time without normal-operation corruption, loss, duplication, deadline misses or unexpected recovery; 14,400,000 stereo frames at the proposed 48 kHz; drain/check all accepted frames at run end |
| Hardware serial observation | Capture MCLK/SCLK/LRCK/data and identify left/right channels on the actual setup | Measured rates/format and observed digital bypass match the agreed contract; electrical/clock feasibility must be established |
| Analog/audio preservation | Repeatable two-channel reference waveform, electrical output capture where available and listening comparison at documented levels | Same intended channel content, no unexpected dropouts/swaps or audible corruption; waveform alignment, gain/frequency/distortion tolerances and capture method remain to be agreed |
| Acoustic end-to-end latency | Timestamp signal entry and capture corresponding speaker playback using a reproducible test waveform and common time reference | Report measured delay against the 5 ms goal; hard acceptance limit, exact input point, microphone location/distance and playback configuration remain open |

The latency requirement includes audible playback, not only FPGA RX-to-TX delay. [Editable measurement-scope diagram](diagrams/bypass-measurement-scope.mmd) shows the intended scope and unresolved endpoints. Speaker/playback processing and acoustic distance affect that measurement; keep a separate digital/electrical delay measurement for diagnosis.

Digital bypass equality is exact at the sample interfaces. Analog and acoustic recordings pass through converters and playback hardware, so they need agreed comparison tolerances rather than bit-for-bit equality. Listening alone cannot demonstrate no digital errors. Randomization must be reproducible, and assertions need defined expected properties, not randomly changing pass criteria.

Remaining test-setup details: hard latency acceptance limit (5 ms is the goal); exact entry/playback measurement points; available instruments; test seeds/coverage; analog tolerances. The agreed run is five minutes of simulated audio time: at the proposed 48 kHz this represents 14,400,000 stereo frames. Simulator runtime may differ. Simulation cannot establish the acoustic entry-to-audible-playback latency; that measurement remains a later hardware check. The existing 30-minute qualification target below is separate and remains proposed.

## Proposed acceptance targets

Targets require measurement; none have been achieved yet.

- Digital EQ response within 0.5 dB of the agreed reference over the specified operating range.
- Latency goal: 5 ms from signal entry to audible playback; hard acceptance limit and exact measurement setup remain open.
- 30 minutes of continuous operation without FIFO errors or missed audio frames.
- Routed timing closure and reviewed CDC, clock, reset, and I2S timing constraints.
- Reproducible programming and demonstration from a release commit.

Record commit, tool versions, configuration, commands, input level, instruments, plots, and limitations in results/. Distinguish digital simulation from analog loopback measurements. Report codec/instrument limits when interpreting noise and distortion.

## Preset acceptance scenarios - planned

These are future checks of [D-01/D-02](architecture.md#preset-consistency-requirements) and [D-03](protocol.md#pending-preset-policy), not executed tests. Exact activation/transport arbitration still needs agreement.

| Scenario | Required observation |
| --- | --- |
| B arrives between left/right processing under A | Both channels of that frame use A |
| Frame 10 used A in EQ; a later frame activates B | Frame 10 still obtains A's compressor settings |
| Complete valid C supersedes pending B before activation | B need not activate; a later eligible frame can use C; B is never falsely reported applied |
| C is incomplete or invalid at an activation boundary | B remains the valid eligible preset; partial C is never exposed |
| B already activated when C becomes eligible | Existing B frames retain B; C can activate only for a later frame |
| Replacement races activation or a snapshot transfer | Observe the agreed arbitration/cutoff, coherent data and acknowledgement outcomes; expected ordering remains open |
| Storage is saturated, controller disconnects or telemetry stalls | Existing audio does not wait for control; observe the agreed bounded-storage/recovery policy |
