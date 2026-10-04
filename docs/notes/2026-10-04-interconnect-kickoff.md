# 2026-10-04 - ESP32/FPGA interconnect kickoff

Author: An Tiet. Base commit: 3673628 (main). Status: open questions only; nothing here is decided.

## Ownership to confirm with Robel

1. Parameter CDC: who writes the synchronizer that carries the committed snapshot from the UART/control clock into the audio/DSP domain, and who writes the frame-boundary activation register? Handoff 4 in ownership.md splits the generation counter between us but does not name the crossing's owner.
2. Telemetry: Robel produces the coherent snapshot; An serializes it. Who defines the telemetry register map, and on which side does the snapshot cross clock domains?
3. Control clock: does the UART/parser run on the 100 MHz board clock, or on a clock derived from the audio MMCM?
4. One UART endpoint or two: Basys 3 USB-UART for the PC utility and a Pmod UART for the ESP32 at the same time, or one port with a mux or jumper?
5. Coefficient computation: do the PC/ESP32 send user units (Hz, dB, Q) or quantized biquad coefficients? If the controller computes coefficients, its quantization must match the Python fixed-point model bit-for-bit.
6. Top-level wiring: who owns the integration PR when the UART endpoint first meets the audio top?
7. Pin allocation: which Pmod header and row the Pmod I2S2 uses, and which pins are reserved for the ESP32 UART.

## Hardware facts to record

- Exact ESP32 module and dev board (for example ESP32-WROOM-32E DevKitC, S3, or C3), USB-serial chip, and free UART GPIOs that are not strapping, flash or PSRAM pins.
- Basys 3 board revision; verify the USB-UART RX/TX package pins against the Digilent master XDC before using them.
- ESP-IDF or PlatformIO choice and pinned version.

## Interconnect risks to design for

- ESP32 strapping pins and UART0 boot log output on the shared line.
- Back-powering: one board powered while the other is off; common ground.
- Asynchronous RX input: two-flop synchronizer and mid-bit sampling; baud-divider error budget.
- Framing resynchronization after corruption, bounded length, inter-byte timeout, CRC coverage.
- Duplicate and retried commands after a lost ACK; receipt ACK versus applied generation.
- FPGA TX arbitration between replies and unsolicited telemetry; telemetry must never block audio.
- Reset of either side mid-packet; resynchronizing controller state after reconnect.
- Web UI slider rate exceeding UART bandwidth; coalesce to latest value on the ESP32.
