# Wiring plan â€” validate before use
Source stereo line output â†’ TRS cable â†’ Pmod I2S2 line input.
Pmod I2S2 line output â†’ second TRS cable â†’ powered speakers or amplifier line input.

Use a compatible Basys 3 Pmod connection with 3.3 V power and ground. Configure the codec ADC for slave operation according to the exact Pmod manual. The FPGA supplies the required audio clocks and transmits DAC data; the ADC returns sampled data.

ESP32 TX â†’ FPGA UART RX; FPGA UART TX â†’ ESP32 RX; share ground. Both interfaces must use 3.3 V logic. Prefer the development boards' normal power connections; do not connect their power rails together casually.

## Required pin worksheet
Before adding XDC, record:
- Basys 3 connector and package pin for every signal.
- Pmod connector orientation, signal direction, ADC/DAC clock connections, and jumper settings.
- ESP32 board pin assignments; avoid unavailable, flash-connected, or boot-sensitive pins.
- Clock constraints, I/O standard, reset behavior, and codec timing requirements.

No package-pin assignment is supplied here; a reviewed wiring worksheet and constraints are a phase-one deliverable.
