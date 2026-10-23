"""Verilator bypass core: 16 depth combinations, watchdog thresholds and recovery.

Short component/integration regression only; not 300 seconds of simulated audio.
"""
import argparse
import subprocess
import sys
from run_serial_timing import ROOT, run, verilator_environment

RTL_NAMES = ("anima_serial_timing.v", "anima_warm_reset_controller.v", "anima_i2s_receiver.v",
             "anima_rx_frame_queue.v", "anima_frame_scheduler.v", "anima_i2s_transmitter.v",
             "anima_audio_watchdogs.v", "anima_bypass_core.v")
BENCH_NAMES = ("anima_bypass_core_tb.sv", "anima_audio_watchdogs_tb.sv", "anima_bypass_recovery_tb.sv")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint", action="store_true")
    parser.add_argument("--seed", type=int, default=2026)
    args = parser.parse_args()
    if not 1 <= args.seed <= 2147483647:
        parser.error("seed must be 1..2147483647")
    build = ROOT / "build/bypass_core" / ("lint" if args.lint else "verilator")
    build.mkdir(parents=True, exist_ok=True)
    try:
        prefix, path = verilator_environment()
        sources = [ROOT / "rtl/audio" / name for name in RTL_NAMES]
        if args.lint:
            base = prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                             "--top-module", "anima_bypass_core"]
            for rx_depth in (1, 2, 4, 8):
                for tx_depth in (1, 2, 4, 8):
                    run(base + [f"-GRX_DEPTH={rx_depth}", f"-GTX_WAIT_DEPTH={tx_depth}"] +
                        [path(p) for p in sources], build, f"rx-{rx_depth}-tx-{tx_depth}.log")
            print("Bypass core Verilog-2001 lint passed for all 16 depth configurations.")
            return 0
        obj = build / "obj_dir"
        run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                      "--top-module", "anima_bypass_core_tb", "--prefix", "Vbypass",
                      "--Mdir", path(obj), "-j", "2"] +
            [path(p) for p in sources + [ROOT / "sim/audio" / name for name in BENCH_NAMES]],
            build, "compile.log")
        output = run(prefix + [path(obj / "Vbypass"), f"+SEED_{args.seed}"],
                     build, f"simulate-seed-{args.seed}.log")
        for marker in (f"BYPASS_PASS seed={args.seed} ", f"WATCHDOG_PASS seed={args.seed} ",
                       "BYPASS_RECOVERY_PASS "):
            if sum(line.startswith(marker) for line in output.splitlines()) != 1:
                raise RuntimeError(f"Missing unique result: {marker}")
        if "BYPASS_FAIL" in output:
            raise RuntimeError("Bypass simulation reported a failure")
        print("\n".join(line for line in output.splitlines()
                        if line.startswith(("BYPASS_PASS", "WATCHDOG_PASS", "BYPASS_RECOVERY_PASS"))))
        print(f"Logs: {build}")
        return 0
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"Bypass check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
