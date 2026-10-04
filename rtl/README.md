# RTL
Synthesizable SystemVerilog lives here. Planned directories:
- audio/: clocks, I2S receiver/transmitter, stereo frame transport.
- dsp/: gain, biquad engine, cascade, linked compressor, saturation.
- control/: UART, packet parser, shadow register bank, coherent commit.
- display/: VGA timing, font and meter rendering.
- common/: reusable synchronizers and infrastructure.

Top-level integration follows the first tested blocks. No placeholder top module is supplied, so there is no synthesis target yet. Keep testbenches in sim/.
