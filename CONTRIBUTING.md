# Contributing
Keep main usable. Work on focused branches such as feat/i2s-rx, feat/uart-control, or docs/protocol. Open a pull request and have the other collaborator review it before merging.

Include the problem, changed behavior, validation performed, and remaining limitations. For RTL, include relevant simulation commands and evidence. For an interface change, update the contract and both consumers together.

Use synthesizable SystemVerilog for hardware. Keep simulation-only constructs in sim/. Use explicit signed arithmetic, widths, rounding, saturation, and reset behavior. Never cross clock domains with an unqualified multibit bus. Keep left and right samples paired.

Do not commit generated Vivado projects, bitstreams, caches, waveforms, credentials, or captured copyrighted audio. Commit source, scripts, and small synthetic vectors. Store concise measured results in results/ and large release artifacts with releases.

Run python scripts/check_repo.py before opening a PR. Hardware and RTL checks are added as those implementations become available.
