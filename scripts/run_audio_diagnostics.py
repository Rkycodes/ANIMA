"""Verilator checks for five fixed 32-bit diagnostic counters and sticky fault.

Core reset-retention and audio-independence checks live in run_bypass_core.py.
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
    build = ROOT / "build/audio_diagnostics" / ("lint" if args.lint else "verilator")
    build.mkdir(parents=True, exist_ok=True)
    try:
        prefix, path = verilator_environment()
        rtl = ROOT / "rtl/audio/anima_audio_diagnostics.v"
        if args.lint:
            run(prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                          "--top-module", "anima_audio_diagnostics", path(rtl)], build, "lint.log")
            print("Audio diagnostics Verilog-2001 lint passed.")
            return 0
        obj = build / "obj_dir"
        run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                      "--top-module", "anima_audio_diagnostics_tb", "--prefix", "Vdiagnostics",
                      "--Mdir", path(obj), "-j", "2", path(rtl),
                      path(ROOT / "sim/audio/anima_audio_diagnostics_tb.sv")], build, "compile.log")
        output = run(prefix + [path(obj / "Vdiagnostics"), f"+SEED_{args.seed}"],
                     build, f"simulate-seed-{args.seed}.log")
        matches = [line for line in output.splitlines()
                   if line.startswith(f"DIAGNOSTICS_PASS seed={args.seed} ")]
        if len(matches)!=1 or "DIAGNOSTICS_FAIL" in output:
            raise RuntimeError("Diagnostic suite did not report a unique pass")
        print(matches[0]); print(f"Logs: {build}")
        return 0
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"Diagnostics check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
