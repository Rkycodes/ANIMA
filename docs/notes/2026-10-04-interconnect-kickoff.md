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


## Concerns to think through

### Electrical

- Strapping pins: some ESP32 pins are read at power-up to choose the boot mode. On the original ESP32, GPIO12 even sets the flash voltage. What happens if the FPGA is holding one of those pins high when the ESP32 resets?
- UART0 is the ESP32's USB console, and its boot ROM prints a log on it. If you wire that port to the FPGA, your parser receives garbage on every ESP32 reboot. That argues for UART1 or UART2 on remapped pins, and for a parser that recovers from garbage anyway.
- Back-powering: if the ESP32 is powered and the Basys 3 is off, the ESP32's TX line can push current into the FPGA's unpowered I/O through its protection diodes. You'll also need a common ground. Check what the Basys 3 reference manual says about the Pmod pins.

### FPGA side

- The RX pin is an asynchronous input, so it needs a 2-flop synchronizer. Why does one flop isn't enough?
- Baud math, as an exercise: 100 MHz ÷ 115200 isn't an integer. Work out the error with a full-bit divider and with 16× oversampling. How much error can UART tolerate before it samples the wrong bit? (Hint: count how far the sampling point drifts by the 10th bit.)
Multi-bit clock crossing: you can't put a synchronizer on each bit of a 32-bit coefficient. Why not? Look up the req/ack toggle handshake.
- One TX line, two talkers: ACK replies and unsolicited telemetry share the same wire, so you need message types and an arbiter. Telemetry has to be droppable, because it can never block audio.

### Protocol

- Resynchronizing after corruption: after a bad byte, how does the parser find the next packet start? This is the core argument between delimiter framing (SLIP/COBS) and length-prefix framing.
- Lost-ACK retries: if the ESP32 resends a command, the FPGA must not apply it twice. That's what sequence numbers are for.
- "Received" vs "applied": these are two different acknowledgements, and the architecture doc is strict about it.
- Who holds the true state after a reset? If either side reboots, how do the two sides agree on parameters again?

### ESP32 / web

- Bandwidth: at 115200 baud with 8N1 framing, how many bytes per second can you send? A web slider fires events faster than that, so coalesce to the latest value on the ESP32 instead of queueing every event.
- Wi-Fi: the ESP32 can't easily join UVA's eduroam (WPA2-Enterprise). Plan on SoftAP mode for demos, and keep credentials out of Git.
Reading list
- UART at the bit level: start, data, stop bits, oversampling, and a Verilog UART receiver. Nandland's UART tutorial is a good start.

### Readings
- Metastability and CDC: Clifford Cummings, "Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog" (SNUG 2008). Read the sections on synchronizers and multi-bit handshakes.
- Framing: COBS vs SLIP. CRC-8 vs CRC-16/CCITT, and what "covered bytes" means.
- Datasheets for your exact ESP32 variant: the strapping-pins table, and the UART chapter of the ESP-IDF docs.
- Basys 3 reference manual: the USB-UART section and the Pmod section. The on-board USB-UART is what lets you test your UART from a PC before the ESP32 is involved.