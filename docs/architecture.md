# Architecture

## Audio path

I2S receiver -> stereo frame FIFO -> input gain -> five biquad sections per channel -> stereo-linked compressor -> output gain with saturation -> stereo frame FIFO -> I2S transmitter.

Each channel has independent filter history. The compressor applies one gain to both channels, derived from the larger channel envelope, to preserve stereo position. EQ is the core milestone; compression follows it.

## Clock domains

Basys 3 supplies a 100 MHz reference. Plan separate DSP/system and audio domains with explicit reset synchronization and asynchronous FIFOs. Move complete stereo frames, not independent channel streams.

Proposed audio clocks are MCLK 12.288 MHz, BCLK 3.072 MHz, and LRCLK 48 kHz. Clock Wizard feasibility, jitter, codec clock requirements, and actual routing must be validated in Vivado before freezing this design. Do not approximate an audio clock with an unconstrained fabric divider.

## Control path

ESP32 web UI -> UART -> FPGA packet parser -> shadow register bank -> DSP parameter snapshot. Commit an entire preset at a frame boundary. Report an applied generation only after the DSP domain has accepted it.

Telemetry uses coherent snapshots and may drop an update; it must never block audio. Audio continues when Wi-Fi or the controller disconnects.

## Display

Target VGA 640 x 480 with procedural drawing and a font ROM. Initial content: left/right levels, gain reduction, preset, and error counters. Avoid a full framebuffer. FFT visualization is a stretch goal.
