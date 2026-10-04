"""Validate repository scaffolding; does not validate RTL or hardware."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    "README.md", "config/project.json",
    "docs/architecture.md", "docs/ownership.md", "docs/roadmap.md",
    "docs/protocol.md", "docs/numerics.md", "docs/verification.md",
    "hardware/BOM.md", "rtl/README.md",
    "model/README.md", "sim/README.md", "firmware/esp32/README.md",
    ".github/workflows/ci.yml",
)


def check():
    errors = []
    for name in REQUIRED:
        if not (ROOT / name).is_file():
            errors.append(f"Missing required file: {name}")
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if any(part in {".git", ".venv", "__pycache__", "build", "obj_dir"} for part in relative.parts):
            continue
        if not path.is_file() or path.suffix not in {".md", ".py", ".json", ".yml"}:
            continue
        try:
            content = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"{relative}: invalid UTF-8")
            continue
        if path.suffix == ".md" and any(
            marker in content for marker in ("\u00e2\u20ac", "\u00e2\u2020", "\ufffd")
        ):
            errors.append(f"{relative}: possible corrupted text encoding")
        if not content.endswith("\n"):
            errors.append(f"{relative}: missing final newline")
        if any(line.rstrip() != line for line in content.splitlines()):
            errors.append(f"{relative}: trailing whitespace")
        if path.suffix == ".md":
            lines = content.splitlines()
            in_fence = False
            for index, line in enumerate(lines):
                if line.startswith("```"):
                    in_fence = not in_fence
                    continue
                if in_fence:
                    continue
                if re.match(r"^#{1,6} ", line):
                    if index and lines[index - 1]:
                        errors.append(f"{relative}:{index + 1}: heading needs a preceding blank line")
                    if index + 1 < len(lines) and lines[index + 1]:
                        errors.append(f"{relative}:{index + 1}: heading needs a following blank line")
                if index and (line.startswith("|") or re.match(r"^(?:- |\d+\. )", line)):
                    previous = lines[index - 1]
                    same_block = previous.startswith("|") if line.startswith("|") else re.match(r"^(?:- |\d+\. )", previous)
                    if previous and not same_block:
                        errors.append(f"{relative}:{index + 1}: table/list needs a preceding blank line")
            if in_fence:
                errors.append(f"{relative}: unclosed code fence")
            for link in re.findall(r"\[[^\]]*\]\(([^)]+)\)", content):
                if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", link) or link.startswith("#"):
                    continue
                target = (path.parent / link.split("#", 1)[0]).resolve()
                if not target.is_relative_to(ROOT) or not target.exists():
                    errors.append(f"{relative}: invalid local link {link}")
    try:
        project = json.loads((ROOT / "config/project.json").read_text(encoding="utf-8"))
        if project["i2s_slot_bits"] < project["sample_bits"]:
            errors.append("I2S slot must hold the sample")
        if project["channels"] != 2:
            errors.append("ANIMA requires stereo configuration")
        if project["target_sample_rate_hz"] <= 0:
            errors.append("Sample rate must be positive")
    except (OSError, ValueError, KeyError, TypeError) as exc:
        errors.append(f"Invalid project metadata: {exc}")
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Repository checks passed (scaffold only; no RTL/hardware validation).")
    return 0


if __name__ == "__main__":
    sys.exit(check())
