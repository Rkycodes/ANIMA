#!/usr/bin/env python3
"""Run the UART TX suite with Verilator (5.x, --binary/--timing); no third-party Python packages needed."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--dut', type=Path, default=ROOT / 'rtl/control/anima_uart_tx.v')
p.add_argument('--waves', action='store_true', help='Keep VCD waveforms in build/uart_tx')
p.add_argument('--baud', type=int, choices=(115200, 9600), help='Run only this configured baud')
a = p.parse_args()
cases = [(a.baud, 0)] if a.baud else [(115200, 0), (9600, 0), (115200, 1)]
wave_dir = ROOT / 'build/uart_tx'
if a.waves:
    wave_dir.mkdir(parents=True, exist_ok=True)
failed = False
with tempfile.TemporaryDirectory(prefix='anima-uart-') as tmp:
    for baud, use_default in cases:
        build = Path(tmp) / f'tx-{baud}-{use_default}'
        output = build / 'uart_tx_sim'
        command = ['verilator', '--binary', '--timing', '-Wall', '-Wno-fatal',
                   '--top-module', 'tb_anima_uart_tx', f'-GBAUD={baud}', f'-GUSE_DEFAULT={use_default}',
                   '--Mdir', str(build), '-o', 'uart_tx_sim',
                   str(a.dut.resolve()), str(ROOT / 'sim/uart/tb_anima_uart_tx.sv')]
        if a.waves:
            command.append('--trace-vcd')
        print(f'=== UART TX: {baud} baud, default={use_default} ===', flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            failed = True
            continue
        run_command = [str(output)]
        if a.waves:
            wave = wave_dir / f'tx-{baud}-default{use_default}.vcd'
            run_command.append(f'+WAVE_FILE={wave}')
            print(f'Waveform: {wave}', flush=True)
        result = subprocess.run(run_command, cwd=ROOT, timeout=180)
        failed |= result.returncode != 0
raise SystemExit(1 if failed else 0)
