#!/usr/bin/env python3
"""Run the UART RX suite with Verilator (5.x, --binary/--timing); no third-party Python packages needed."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--dut', type=Path, default=ROOT / 'rtl/display/anima_uart_rx.v')
a = p.parse_args()
failed = False
with tempfile.TemporaryDirectory(prefix='anima-uart-') as tmp:
    for baud in (115200, 9600):
        build = Path(tmp) / f'rx-{baud}'
        output = build / 'uart_rx_sim'
        command = ['verilator', '--binary', '--timing', '-Wall', '-Wno-fatal',
                   '--top-module', 'tb_anima_uart_rx', f'-GBAUD={baud}',
                   '--Mdir', str(build), '-o', 'uart_rx_sim',
                   str(a.dut.resolve()), str(ROOT / 'sim/uart/tb_anima_uart_rx.sv')]
        print(f'=== UART RX: {baud} baud ===', flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            failed = True
            continue
        result = subprocess.run([str(output)], cwd=ROOT, timeout=180)
        failed |= result.returncode != 0
raise SystemExit(1 if failed else 0)
