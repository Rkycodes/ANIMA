# Development workflow

## Tools

- Git and GitHub for source, issues, PR review, and CI.
- Vivado on Windows for Basys 3 synthesis, implementation, Clock Wizard, programming, and timing reports. On October 15, 2026, Vivado 2026.1 build 6511674, BASIC license access and xc7a35tcpg236-1 support were confirmed. The configuration-only clock probe is recorded in architecture; it is not synthesis or hardware validation. Use Vivado Simulator for directed waveform/debug checks once RTL/benches exist, alongside Verilator lint/regression. Do not duplicate the five-minute regression in both simulators by default.
- VS Code or another editor.
- Python 3.12 for repository checks and reference models. Add pinned model dependencies when the model exists.
- WSL Ubuntu provides /usr/bin/verilator, reported as Verilator 5.032 (2025-01-01, Debian 5.032-1) on October 15, 2026. No audio bench exists or was run. Record source lists/options when adding RTL simulation and CI.
- ESP-IDF or PlatformIO for ESP32 firmware; An selects the framework after identifying the exact board. Commit its version and target configuration.
- Serial terminal and, ideally, a logic analyzer for I2S/UART bring-up.

## Clone and check

```sh
git clone https://github.com/Rkycodes/ANIMA.git
cd ANIMA
python scripts/check_repo.py
git switch -c feat/your-task
```

On Windows, py -3.12 can be used in place of python.

If using Windows Vivado and WSL simulation, prefer separate clones synchronized through Git. Run both against the same commit when reporting a result. Do not share generated build directories.

## Build policy

No Vivado project or RTL executable exists yet. Add a source-controlled Tcl entry point and source list when the first top module exists; generate projects under ignored build/. Check in reviewed XDC constraints, not downloaded guesses.

Start CI with the checks that run today. Add lint, simulation, reference-model comparisons, and firmware builds as working targets become available. Hosted CI does not currently run Vivado.

Use synthetic impulses, tones, sweeps, silence, and seeded noise for committed vectors. Document commands so the other collaborator can reproduce results.

## Languages and branches

Use Verilog-2001 (.v) for synthesizable RTL. SystemVerilog (.sv) may be used for testbenches and verification. Reference models and serial utilities use Python; ESP32 firmware follows the selected framework.

Keep main usable. Work on focused feature branches and review each other's pull requests. Include the changed behavior and validation actually performed. Add RTL checks when executable targets exist.


## Integration follow-up

Remote main includes An Tiet's interconnect notes and gameplan, preserved with authorship, and the Python preset-lifecycle model from [PR #3](https://github.com/Rkycodes/ANIMA/pull/3). Commit 33d65ee repaired the earlier kickoff Markdown formatting; the historical CI failure is not a current unresolved formatting task. This planning checkpoint incorporates that main history without altering An's model. Later commits on python-model remain separate unless explicitly integrated.

The audio integration task remains unassigned at Robel's request. Claim it before concurrent top-level edits. This checkpoint defines intended bypass behavior and verification requirements; it does not authorize RTL/firmware implementation or claim passing audio tests.
