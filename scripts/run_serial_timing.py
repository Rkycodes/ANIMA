"""Run focused lint and simulation checks for the serial-timing component.

Default: native Verilator or the existing WSL installation. Vivado Simulator
remains available through --simulator vivado when explicitly requested. All generated output stays under build/.
"""
import argparse
import base64
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl/audio/anima_serial_timing.v"
BENCH = ROOT / "sim/audio/anima_serial_timing_tb.sv"


def command_for_batch(command):
    """Pass Windows batch-tool arguments literally through PowerShell."""
    if sys.platform != "win32" or Path(command[0]).suffix.lower() != ".bat":
        return command
    quoted = ["'" + str(item).replace("'", "''") + "'" for item in command]
    script = "& " + " ".join(quoted) + "; exit $LASTEXITCODE"
    encoded = base64.b64encode(script.encode("utf-16le")).decode("ascii")
    return ["powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]


def run(command, directory, log_name):
    result = subprocess.run(command_for_batch(command), cwd=directory,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace")
    (directory / log_name).write_text(result.stdout, encoding="utf-8", newline="\n")
    if result.returncode:
        print("\n".join(result.stdout.splitlines()[-50:]), file=sys.stderr)
        raise RuntimeError(f"Tool failed ({result.returncode}); see {directory / log_name}")
    return result.stdout


def verilator_environment():
    if shutil.which("verilator"):
        return [], lambda path: str(path)
    if sys.platform == "win32" and shutil.which("wsl.exe"):
        def translate(path):
            result = subprocess.run(["wsl.exe", "--exec", "wslpath", "-u", str(path)],
                                    capture_output=True, text=True, check=True)
            return result.stdout.strip()
        return ["wsl.exe", "--exec"], translate
    raise RuntimeError("Verilator is unavailable; use installed Vivado Simulator instead")


def vivado_tool(name, directory):
    located = shutil.which(name) or shutil.which(name + ".bat")
    if directory:
        located = str(directory / (name + (".bat" if sys.platform == "win32" else "")))
    if not located:
        candidate = Path("C:/AMDDesignTools/2026.1/Vivado/bin") / (name + ".bat")
        if sys.platform == "win32" and candidate.is_file():
            located = str(candidate)
    if not located or not Path(located).is_file():
        raise RuntimeError(f"Cannot locate {name}; supply --vivado-bin with the installed bin directory")
    return located


def execute(args):
    build = ROOT / "build/serial_timing" / ("lint" if args.lint else args.simulator)
    build.mkdir(parents=True, exist_ok=True)
    if args.lint:
        prefix, translate = verilator_environment()
        run(prefix + ["verilator", "--lint-only", "--Wall", "--language", "1364-2001",
                      "--top-module", "anima_serial_timing", str(translate(RTL))], build, "lint.log")
        print("Timing RTL lint passed (syntax/style only; run simulation for behavioral checks).")
        return 0

    plusargs = [f"CASE_{args.case}", f"SEED_{args.seed}", f"FRAMES_{args.frames}"]
    if args.simulator == "vivado":
        xvlog = vivado_tool("xvlog", args.vivado_bin)
        xelab = vivado_tool("xelab", args.vivado_bin)
        xsim = vivado_tool("xsim", args.vivado_bin)
        run([xvlog, str(RTL)], build, "compile_rtl.log")
        run([xvlog, "--sv", str(BENCH)], build, "compile_bench.log")
        run([xelab, "work.anima_serial_timing_tb", "--snapshot", "serial_timing_tb",
             "--debug", "typical"], build, "elaborate.log")
        command = [xsim, "serial_timing_tb", "--onerror", "quit", "--onfinish", "quit"]
        if args.waves:
            batch = build / "run_waves.tcl"
            batch.write_text("log_wave -r /anima_serial_timing_tb/*\nrun all\nquit\n",
                             encoding="utf-8", newline="\n")
            command += ["--tclbatch", batch.as_posix()]
        else:
            command += ["--runall"]
        for arg in plusargs:
            command += ["--testplusarg", arg]
        output = run(command, build, "simulate.log")
    else:
        prefix, translate = verilator_environment()
        obj = build / "obj_dir"
        run(prefix + ["verilator", "--binary", "--timing", "--assert", "--Wall",
                      "--top-module", "anima_serial_timing_tb", "--prefix", "Vserial_timing",
                      "--Mdir", translate(obj), "-j", "2", translate(RTL), translate(BENCH)],
            build, "compile.log")
        output = run(prefix + [translate(obj / "Vserial_timing")] + ["+" + arg for arg in plusargs],
                     build, "simulate.log")

    marker = f"TIMING_PASS case={args.case} seed={args.seed} frames={args.frames} "
    matches = [line for line in output.splitlines() if line.startswith(marker)]
    if len(matches) != 1 or "FAIL case=" in output:
        print("\n".join(output.splitlines()[-25:]), file=sys.stderr)
        raise RuntimeError("Simulation did not report a unique pass; inspect the log.")
    print(matches[0])
    print(f"Logs: {build}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("phase", "clocks", "events", "all"), default="phase")
    parser.add_argument("--simulator", choices=("vivado", "verilator"), default="verilator")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--frames", type=int, default=8)
    parser.add_argument("--vivado-bin", type=Path)
    parser.add_argument("--lint", action="store_true", help="Verilator lint of the Verilog-2001 RTL only")
    parser.add_argument("--waves", action="store_true", help="Record Vivado waveform database under build/")
    args = parser.parse_args()
    if not 1 <= args.seed <= 2147483647 or not 1 <= args.frames <= 1024:
        parser.error("seed must be 1..2147483647 and frames must be 1..1024")
    if args.waves and (args.simulator != "vivado" or args.lint):
        parser.error("--waves is for Vivado simulation; use --simulator vivado")
    try:
        return execute(args)
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"Timing check: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
