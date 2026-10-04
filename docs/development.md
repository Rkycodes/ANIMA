# Development workflow

## Tools

- Git and GitHub for source, issues, PR review, and CI.
- Vivado on Windows for Basys 3 synthesis, implementation, Clock Wizard, programming, and timing reports. Record the installed release when first building.
- VS Code or another editor.
- Python 3.12 for repository checks and reference models. Add pinned model dependencies when the model exists.
- WSL2 Ubuntu with Verilator for RTL simulation once benches exist. Confirm simulator versions when adding CI.
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

## Dedicated checkout

Recommended permanent location: C:/Users/robel/Documents/Projects/ANIMA. Create that checkout in your own terminal. To preserve unpublished setup commits, clone the current local repository into that folder, then set origin to https://github.com/Rkycodes/ANIMA.git.

Once the setup branch has been published and merged, a fresh checkout elsewhere can be created with git clone. A fresh clone of GitHub before publication will contain only the existing README.
