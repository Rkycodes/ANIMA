#!/usr/bin/env python3
"""Run the UART RX suite with Icarus; no third-party Python packages needed."""
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
        output = Path(tmp) / f'rx-{baud}.vvp'
        command = ['iverilog', '-g2005-sv', '-Wall', '-s', 'tb_anima_uart_rx',
                   f'-Ptb_anima_uart_rx.BAUD={baud}', '-o', str(output),
                   str(a.dut.resolve()), str(ROOT / 'sim/uart/tb_anima_uart_rx.sv')]
        print(f'=== UART RX: {baud} baud ===', flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            failed = True
            continue
        result = subprocess.run(['vvp', str(output)], cwd=ROOT, timeout=180)
        failed |= result.returncode != 0
raise SystemExit(1 if failed else 0)
