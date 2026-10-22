# UART receiver behavioral tests

Run from the repository root with Verilator 5.x, a C++ compiler, and make installed:

```sh
python3 scripts/test_uart_rx.py
```

The runner compiles the existing receiver and SystemVerilog bench separately for
115200 and 9600 baud, assuming a 100 MHz receiver clock. It uses temporary build
files and returns nonzero on compilation errors or required assertion failures.
This does not select the production UART clock. The runner uses `verilator --binary --timing` to execute the SystemVerilog
bench directly. Warnings remain visible but are nonfatal (`-Wno-fatal`), so
functional checks can run on work-in-progress RTL. Passing this suite is not
a lint-clean or strict Verilog-2001 certification. Verilator primarily uses
two-state simulation; the known-value assertion does not prove X propagation.

## Coverage and assumptions

- Active-low asynchronous `rst`: immediate idle, zero counter/index, valid low;
  held reset with RX low; reset during reception and while valid is asserted.

- Start detection: reject a quarter-bit glitch, check start confirmation near the
  wire midpoint, and verify eight data sampling events per nominal frame.

- Independent real-time serial driver: 8N1, LSB first, varied start phases,
  back-to-back frames, patterns 51/FF/00/55/AA/80/01/FE.

- Scoreboard: byte equality, no unexpected or missing bytes, known valid output,
  one-clock valid pulse. Output data is consumed only while valid is asserted.

- Sampling time: internal state/counter probes compared to the independently
  calculated wire midpoint, allowing -1 to +5 receiver clocks for
  synchronizer and FSM latency, plus accumulated integer-divider rounding. These probes must change if the
  receiver's internal state encoding or counter architecture changes.

- Malformed stop: no valid byte; subsequent valid traffic recovers. There is no
  framing-error output on the current DUT, so explicit error reporting is **not
  tested**. No ready/backpressure or overflow interface exists either.

- Baud offset: 16 back-to-back alternating AA/55 bytes at each of +/-1 through
  +/-5 percent transmitter baud. Positive means faster transmission. +/-1 and
  +/-2 are proposed required test targets; +/-3 through +/-5 are characterization
  only, reported but excluded from the final pass/fail total. Passing these
  finite streams does not guarantee a universal drift tolerance.

- Watchdog prevents an indefinitely stalled simulation.

The bench checks digital behavior, not analog metastability, physical timing,
noise immunity, or hardware operation. Reset release in the bench occurs away
from the active clock edge; reset synchronization remains an integration task.

To validate the bench against a temporary receiver variant without changing the
working RTL, use `python3 scripts/test_uart_rx.py --dut /absolute/path/receiver.v`.

## Validation during authoring

Icarus Verilog 13.0 ran both baud configurations. The working receiver produced
six reset assertion failures per configuration: state could leave idle while
reset was held, and reset did not reliably clear counter/index state. Nominal
reconstruction, midpoint checks, false-start rejection, malformed-stop rejection,
and the exercised baud-offset streams passed.

A temporary copy with an exclusive reset/normal-operation branch, explicit
counter/index/valid reset assignments, and a wire output declaration passed both
configurations. The working receiver was not edited by this testbench task.
These results are a snapshot; rerun after receiver edits.

After switching the runner to Verilator 5.052, both baud configurations compiled
and ran. Each reported the same six reset-check failures; all other exercised
functional checks and baud-offset streams passed. Warnings remain visible.
