"""Verilator TX serializer checks and simulated audio-component chain.

This is a short component regression, not five-minute bypass acceptance.
"""
import argparse
import subprocess
import sys
from run_serial_timing import ROOT, run, verilator_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint", action="store_true")
    parser.add_argument("--seed", type=int, default=2026)
    args = parser.parse_args()
    if not 1 <= args.seed <= 2147483647:
        parser.error("seed must be 1..2147483647")
    build = ROOT / "build/i2s_transmitter" / ("lint" if args.lint else "verilator")
    build.mkdir(parents=True, exist_ok=True)
    rtl = ROOT / "rtl/audio/anima_i2s_transmitter.v"
    try:
        prefix, path = verilator_environment()
        if args.lint:
            run(prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                          "--top-module", "anima_i2s_transmitter", path(rtl)], build, "lint.log")
            print("I2S transmitter Verilog-2001 lint passed.")
            return 0
        sources = [ROOT / "rtl/audio" / name for name in
                   ("anima_serial_timing.v", "anima_warm_reset_controller.v", "anima_i2s_receiver.v",
                    "anima_rx_frame_queue.v", "anima_frame_scheduler.v")]
        obj = build / "obj_dir"
        run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                      "--top-module", "anima_i2s_transmitter_tb", "--prefix", "Vtx",
                      "--Mdir", path(obj), "-j", "2"] +
            [path(p) for p in [*sources, rtl, ROOT / "sim/audio/anima_i2s_transmitter_tb.sv"]],
            build, "compile.log")
        output = run(prefix + [path(obj / "Vtx"), f"+SEED_{args.seed}"],
                     build, f"simulate-seed-{args.seed}.log")
        matches = [line for line in output.splitlines() if line.startswith(f"I2S_TX_PASS seed={args.seed} ")]
        if len(matches) != 1 or "I2S_TX_FAIL" in output:
            raise RuntimeError("TX simulation did not report a unique pass")
        print(matches[0])
        print(f"Logs: {build}")
        return 0
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"TX check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
