"""Verilator logical control-shell/button/clock-loss checks; no MMCM or board build."""
import argparse
import subprocess
import sys
from run_serial_timing import ROOT, run, verilator_environment
from run_bypass_core import RTL_NAMES


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint",action="store_true")
    parser.add_argument("--seed",type=int,default=2026)
    args=parser.parse_args()
    if not 1<=args.seed<=2147483647:
        parser.error("seed must be 1..2147483647")
    build=ROOT/"build/board_controls"/("lint" if args.lint else "verilator")
    build.mkdir(parents=True,exist_ok=True)
    try:
        prefix,path=verilator_environment()
        sources=[ROOT/"rtl/audio"/name for name in RTL_NAMES]
        sources += [ROOT/name for name in ("rtl/common/anima_reset_sync.v", "rtl/common/anima_button_event.v",
                    "rtl/audio/anima_clock_supervisor.v", "rtl/audio/anima_bypass_control_shell.v")]
        source_paths=[path(p) for p in sources]
        if args.lint:
            base=prefix+["verilator","--lint-only","--Wall","--language","1364-2001",
                         "--top-module","anima_bypass_control_shell"]
            run(base+source_paths,build,"lint.log")
            invalids={"BUTTON_STABLE_CYCLES=0":"ANIMA_BUTTON_STABLE_CYCLES_MUST_BE_POSITIVE",
                      "HEARTBEAT_CYCLES=1":"ANIMA_CLOCK_SUPERVISOR_INVALID_PARAMETERS",
                      "TIMEOUT_REF_CYCLES=31":"ANIMA_CLOCK_SUPERVISOR_INVALID_PARAMETERS",
                      "MMCM_RESET_REF_CYCLES=0":"ANIMA_CLOCK_SUPERVISOR_INVALID_PARAMETERS",
                      "STARTUP_AUDIO_CYCLES=0":"ANIMA_CLOCK_SUPERVISOR_INVALID_PARAMETERS"}
            for setting,marker in invalids.items():
                bad=subprocess.run(base+["-G"+setting]+source_paths,cwd=build,
                                   stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                   text=True,encoding="utf-8",errors="replace")
                (build/("invalid-"+setting.replace("=","-")+".log")).write_text(bad.stdout,encoding="utf-8")
                if not bad.returncode or marker not in bad.stdout:
                    raise RuntimeError(f"Invalid configuration was not rejected: {setting}")
            print("Control shell/buttons/supervisor Verilog-2001 lint passed; five invalid configurations rejected.")
            return 0
        obj=build/"obj_dir"
        benches=[ROOT/"sim/audio"/name for name in ("anima_button_event_tb.sv","anima_bypass_control_shell_tb.sv")]
        run(prefix+["verilator","--binary","--timing","--assert","--Wall",
                    "--top-module","anima_bypass_control_shell_tb","--prefix","Vcontrols",
                    "--Mdir",path(obj),"-j","2"]+[path(p) for p in sources+benches],build,"compile.log")
        output=run(prefix+[path(obj/"Vcontrols"),f"+SEED_{args.seed}"],build,f"simulate-seed-{args.seed}.log")
        for marker in (f"BOARD_CONTROL_PASS seed={args.seed} ",f"BUTTON_PASS seed={args.seed} "):
            if sum(line.startswith(marker) for line in output.splitlines())!=1:
                raise RuntimeError(f"Missing unique result: {marker}")
        if "BOARD_FAIL" in output:
            raise RuntimeError("Control regression failed")
        print("\n".join(line for line in output.splitlines() if line.startswith(("BOARD_CONTROL_PASS","BUTTON_PASS"))))
        return 0
    except (OSError,subprocess.SubprocessError,RuntimeError) as exc:
        print(f"Control check: {exc}",file=sys.stderr)
        return 1


if __name__=="__main__":
    sys.exit(main())
