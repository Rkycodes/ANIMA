"""Verilator-only checks for frame scheduling and owned TX waiting storage."""
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
    build = ROOT / "build/frame_scheduler" / ("lint" if args.lint else "verilator")
    build.mkdir(parents=True, exist_ok=True)
    prefix, path = verilator_environment()
    rtl = ROOT / "rtl/audio/anima_frame_scheduler.v"
    try:
        if args.lint:
            base = prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                             "--top-module", "anima_frame_scheduler"]
            for depth in (1, 2, 4, 8):
                run(base + [f"-GTX_WAIT_DEPTH={depth}", path(rtl)], build, f"depth-{depth}.log")
            bad = subprocess.run(base + ["-GTX_WAIT_DEPTH=3", path(rtl)], cwd=build,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, encoding="utf-8", errors="replace")
            (build / "invalid-depth.log").write_text(bad.stdout, encoding="utf-8")
            if not bad.returncode or "ANIMA_TX_WAIT_DEPTH_MUST_BE_1_2_4_OR_8" not in bad.stdout:
                raise RuntimeError("Invalid depth was not rejected")
            print("Scheduler lint passed at depths 1/2/4/8; depth 3 rejected.")
            return 0
        obj = build / "obj_dir"
        run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                      "--top-module", "anima_frame_scheduler_tb", "--prefix", "Vscheduler",
                      "--Mdir", path(obj), "-j", "2", path(rtl),
                      path(ROOT / "rtl/audio/anima_serial_timing.v"),
                      path(ROOT / "sim/audio/anima_frame_scheduler_tb.sv"),
                      path(ROOT / "sim/audio/anima_frame_scheduler_case.sv")], build, "compile.log")
        output = run(prefix + [path(obj / "Vscheduler"), f"+SEED_{args.seed}"],
                     build, f"simulate-seed-{args.seed}.log")
        if output.splitlines().count("SCHEDULER_PASS depths=1,2,4,8") != 1 or "SCHEDULER_FAIL" in output:
            raise RuntimeError("Scheduler suite did not pass")
        for depth in (1, 2, 4, 8):
            if sum(line.startswith(f"SCHEDULER_CASE_PASS depth={depth} seed={args.seed} ")
                   for line in output.splitlines()) != 1:
                raise RuntimeError("Missing depth result")
        negative = subprocess.run(prefix + [path(obj / "Vscheduler"), f"+SEED_{args.seed}",
                                            "+REJECT_AMBIGUOUS"], cwd=build,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, encoding="utf-8", errors="replace", timeout=30)
        (build / f"ambiguous-seed-{args.seed}.log").write_text(negative.stdout, encoding="utf-8")
        if "SCHEDULER_EXPECTED_AMBIGUOUS_ASSERT" not in negative.stdout or "SCHEDULER_PASS depths=" in negative.stdout:
            raise RuntimeError("Ambiguous-ID assertion did not reject the invalid stream")
        print("Ambiguous-ID negative assertion test rejected the invalid stream.")
        print("\n".join(line for line in output.splitlines() if line.startswith("SCHEDULER_")))
        return 0
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"Scheduler check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
