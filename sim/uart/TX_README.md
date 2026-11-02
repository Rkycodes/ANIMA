# UART transmitter tests

Run from the repository root with Verilator 5.x, a C++ compiler and make:

```sh
python3 scripts/test_uart_tx.py
```

Runs at 100 MHz with explicitly configured 115200/9600 baud dividers, plus a
separate test of the DUT's default divider against the documented 115200 target.
Uses `--binary --timing`; warnings are visible but nonfatal. Compilation or
required behavioral failures produce nonzero exit status. No RX loopback is used.

## Assumed interface contract

An idle `data_available` pulse is accepted on a rising clock edge. TX captures
`data_byte` and asserts `TX_Active`; it ignores a request pulse entirely within
busy time. No internal request queue is assumed. `transmission_done` pulses for
one clock at completion, no earlier than the last processing edge of the stop
slot. Reset is asynchronous active-low: abort transmission, drive the line high,
and clear busy/done. These are test assumptions for review, not a frozen protocol.
Requests held across completion and exact cleanup-edge request acceptance remain
unspecified; this bench does not claim to validate a ready/valid interface.

## Checks

- Idle-high output and inactive flags, including reset held across clocks.

- Start bit low, eight data bits LSB first, stop high; every processing cycle of
  each slot checked against an independent expected waveform. Start must appear
  within eight clocks after an idle request. Slot length is the rounded nominal
  divider, not a value read from DUT internals.

- Patterns 51/FF/00/55/AA/80/01/FE, followed by repeated fresh requests.

- Input byte changed immediately after acceptance: the outgoing byte must stay
  equal to the captured request. A request pulsed while busy must not corrupt the
  current frame or cause a later unsolicited transmission.

- Active duration, one-clock completion, exactly one completion per accepted
  request, and return to idle.

- Reset in start/data/stop phases, no completion for an aborted frame, and fresh
  transmission after reset. A watchdog bounds simulation time.

Verilator's two-state simulation does not prove X propagation or physical timing.
This is a digital functional bench, not synthesis/timing or hardware acceptance.

Use `--dut /absolute/path/anima_uart_tx.v` to test another source copy. Builds
are temporary; production RTL is never rewritten by the runner.

## Authoring validation

Verilator 5.052 rejects the working source's procedural writes to wire-declared
TX_Active. A temporary copy changing only the output declarations compiled and
failed the functional checks. Another temporary copy correcting reset outputs,
per-bit counter restart, completion clearing and the default divider passed all
three configurations. These copies were outside the repository; working RTL was
left unchanged. Repository checks also passed.

## GTKWave

Generate a VCD for the configured 115200-baud test:

```sh
python3 scripts/test_uart_tx.py --waves --baud 115200
gtkwave build/uart_tx/tx-115200-default0.vcd
```

`--waves` enables Verilator tracing and the bench's conditional `$dumpvars`.
Omit `--baud` to generate separate files for all three configurations. Waveforms
stay in ignored `build/uart_tx` after temporary executables are removed. Behavioral
failures still return nonzero; their waveforms can be opened for debugging.

In GTKWave, expand `TOP` / `tb_anima_uart_tx` and add `clk`, `rst`, `request`,
`data`, `active`, `serial`, and `done`. Under `configured.dut`, add `TX_State`,
`clk_counter`, `bit_index`, and `TX_Byte`. Display byte buses in hexadecimal and
counters in unsigned decimal. Zoom into the first request/start transition;
868 clocks at 100 MHz correspond to an 8.68 microsecond bit. State encodings are
0=IDLE, 1=START, 2=TRANSMITTING, 3=STOP, 4=CLEANUP. Save a GTKWave `.gtkw` view
in the build directory to preserve signal selection and zoom.
