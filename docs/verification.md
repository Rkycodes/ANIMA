# Verification and release evidence

## Block checks

- I2S: known positive/negative samples, channel order, one-bit delay, slot padding, framing and reset.
- FIFOs/CDC: unequal clocks, reset in each domain, backpressure, overflow/underflow visibility.
- DSP: impulse, tones, sweep, silence, seeded noise, extremes; RTL equals the fixed-point model under defined rounding.
- EQ: response and stability after quantization, headroom and overload, live parameter transitions.
- Compression: attack/release, threshold/ratio, equal gain on both channels, saturation.
- Control: malformed/partial/duplicate packets, bad CRC, timeout, reset, retry, commit acknowledgement.
- Integration: disconnected controller and telemetry saturation leave audio running.

## Proposed acceptance targets

Targets require measurement; none have been achieved yet.

- Digital EQ response within 0.5 dB of the agreed reference over the specified operating range.
- End-to-end latency below 5 ms for the default chain without intentional delay.
- 30 minutes of continuous operation without FIFO errors or missed audio frames.
- Routed timing closure and reviewed CDC, clock, reset, and I2S timing constraints.
- Reproducible programming and demonstration from a release commit.

Record commit, tool versions, configuration, commands, input level, instruments, plots, and limitations in results/. Distinguish digital simulation from analog loopback measurements. Report codec/instrument limits when interpreting noise and distortion.
