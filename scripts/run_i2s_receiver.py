"""Run Verilator lint/simulation for the I2S receiver, timing and warm reset.

Uses native Verilator or the existing WSL installation. Generated output stays
under ignored build/i2s_receiver/. No Vivado command is run.
"""
import argparse
import subprocess
import sys

from run_serial_timing import ROOT, run, verilator_environment

RECEIVER = ROOT / "rtl/audio/anima_i2s_receiver.v"
TIMING = ROOT / "rtl/audio/anima_serial_timing.v"
CONTROLLER = ROOT / "rtl/audio/anima_warm_reset_controller.v"
BENCH = ROOT / "sim/audio/anima_i2s_receiver_tb.sv"


def execute(args):
    build = ROOT / "build/i2s_receiver" / ("lint" if args.lint else "verilator")
    build.mkdir(parents=True, exist_ok=True)
    prefix, translate = verilator_environment()
    if args.lint:
        run(prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                      "--top-module", "anima_i2s_receiver", translate(RECEIVER)],
            build, "lint.log")
        print("I2S receiver Verilog-2001 lint passed.")
        return 0

    obj = build / "obj_dir"
    run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                  "--top-module", "anima_i2s_receiver_tb", "--prefix", "Vi2s_receiver",
                  "--Mdir", translate(obj), "-j", "2", translate(TIMING), translate(CONTROLLER),
                  translate(RECEIVER), translate(BENCH)], build, "compile.log")
    output = run(prefix + [translate(obj / "Vi2s_receiver"), f"+SEED_{args.seed}",
                          f"+FRAMES_{args.frames}"], build, f"simulate-seed-{args.seed}.log")
    marker = f"I2S_RX_PASS seed={args.seed} frames={args.frames} "
    matches = [line for line in output.splitlines() if line.startswith(marker)]
    if len(matches) != 1 or "I2S_RX_FAIL" in output:
        print("\n".join(output.splitlines()[-25:]), file=sys.stderr)
        raise RuntimeError("I2S receiver simulation did not report a unique pass; inspect the log.")
    print(matches[0])
    print(f"Logs: {build}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint", action="store_true", help="Lint the Verilog-2001 receiver")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--frames", type=int, default=32,
                        help="Random frame units after directed receiver/reset checks")
    args = parser.parse_args()
    if not 1 <= args.seed <= 2147483647 or not 1 <= args.frames <= 4096:
        parser.error("seed must be 1..2147483647 and frames must be 1..4096")
    try:
        return execute(args)
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"I2S receiver check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
