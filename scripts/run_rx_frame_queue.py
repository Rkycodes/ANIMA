"""Run Verilator RX queue checks at depths 1/2/4/8 plus real receiver integration.

Generated output stays under ignored build/rx_frame_queue/. The default suite
reuses the independent ADC receiver bench without changing its normal mode.
"""
import argparse
import subprocess
import sys

from run_serial_timing import ROOT, run, verilator_environment

RTL = ROOT / "rtl/audio/anima_rx_frame_queue.v"
SOURCES = [ROOT / "rtl/audio" / name for name in
           ("anima_serial_timing.v", "anima_warm_reset_controller.v", "anima_i2s_receiver.v")]
BENCHES = [ROOT / "sim/audio" / name for name in
           ("anima_i2s_receiver_tb.sv", "anima_rx_frame_queue_tb.sv", "anima_rx_queue_chain_probe.sv")]


def execute(args):
    build = ROOT / "build/rx_frame_queue" / ("lint" if args.lint else "verilator")
    build.mkdir(parents=True, exist_ok=True)
    prefix, translate = verilator_environment()
    if args.lint:
        base = prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                         "--top-module", "anima_rx_frame_queue"]
        for depth in (1, 2, 4, 8):
            run(base + [f"-GDEPTH={depth}", translate(RTL)], build, f"depth-{depth}.log")
        invalid = subprocess.run(base + ["-GDEPTH=3", translate(RTL)], cwd=build,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, encoding="utf-8", errors="replace")
        (build / "invalid-depth-3.log").write_text(invalid.stdout, encoding="utf-8", newline="\n")
        if invalid.returncode == 0 or "ANIMA_RX_QUEUE_DEPTH_MUST_BE_1_2_4_OR_8" not in invalid.stdout:
            raise RuntimeError("Unsupported depth 3 did not fail with the intended configuration diagnostic")
        print("RX queue Verilog-2001 lint passed at depths 1/2/4/8; unsupported depth 3 rejected.")
        return 0
    obj = build / "obj_dir"
    run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                  "-DANIMA_RX_QUEUE_TEST", "--top-module", "anima_i2s_receiver_tb",
                  "--prefix", "Vrx_queue", "--Mdir", translate(obj), "-j", "2"] +
        [translate(path) for path in [*SOURCES, RTL, *BENCHES]], build, "compile.log")
    output = run(prefix + [translate(obj / "Vrx_queue"), f"+SEED_{args.seed}",
                          f"+QUEUE_CYCLES_{args.cycles}"], build, f"simulate-seed-{args.seed}.log")
    lines = output.splitlines()
    marker = f"RX_QUEUE_PASS seed={args.seed} depths=1,2,4,8"
    if lines.count(marker) != 1 or "RX_QUEUE_FAIL" in output or "I2S_RX_FAIL" in output:
        raise RuntimeError("Queue suite did not report a unique pass; inspect the simulation log")
    for depth in (1, 2, 4, 8):
        prefix_match = f"RX_QUEUE_CASE_PASS depth={depth} seed={args.seed} cycles={args.cycles} "
        if sum(line.startswith(prefix_match) for line in lines) != 1:
            raise RuntimeError(f"Missing unique pass for depth {depth}")
    for line in lines:
        if line.startswith(("RX_QUEUE_CASE_PASS", "RX_QUEUE_CHAIN_PASS", "RX_QUEUE_PASS", "I2S_RX_PASS")):
            print(line)
    print(f"Logs: {build}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint", action="store_true")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--cycles", type=int, default=10000)
    args = parser.parse_args()
    # Unit clocks finish before the surrounding receiver bench ends its suite.
    if not 1 <= args.seed <= 2147483647 or not 1 <= args.cycles <= 100000:
        parser.error("seed must be 1..2147483647 and cycles must be 1..100000")
    try:
        return execute(args)
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"RX queue check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
