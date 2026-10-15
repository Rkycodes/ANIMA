"""Validate repository scaffolding; does not validate RTL or hardware."""
from pathlib import Path
import json
import re
import sys
from urllib.parse import unquote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    "README.md", "config/project.json",
    "docs/planning.md", "docs/implemented.md",
    "docs/diagrams/audio-clock-ownership.mmd",
    "docs/diagrams/bypass-edge-budget.svg",
    "docs/diagrams/bypass-measurement-scope.mmd",
    "docs/diagrams/frame-preset-consistency.mmd",
    "docs/diagrams/pending-preset-policy.mmd",
    "docs/diagrams/preset-snapshot-lifetime.mmd",
    ".github/workflows/ci.yml",
)


def heading_ids(content):
    """GitHub-style IDs for the plain headings used in project documents."""
    ids = set()
    in_fence = False
    for line in content.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
        elif not in_fence and re.match(r"^#{1,6} ", line):
            title = re.sub(r"^#{1,6} ", "", line).strip().lower()
            slug = re.sub(r"[^\w\s-]", "", title)
            slug = slug.replace(" ", "-")
            candidate = slug
            suffix = 0
            while candidate in ids:
                suffix += 1
                candidate = f"{slug}-{suffix}"
            ids.add(candidate)
    return ids


def check():
    errors = []
    for name in REQUIRED:
        if not (ROOT / name).is_file():
            errors.append(f"Missing required file: {name}")
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if any(part in {".git", ".venv", "__pycache__", "build", "obj_dir"} for part in relative.parts):
            continue
        if not path.is_file() or path.suffix not in {".md", ".py", ".json", ".yml", ".yaml", ".mmd", ".svg"}:
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
        if path.suffix in {".md", ".mmd", ".svg"} and "\r" in content:
            errors.append(f"{relative}: expected LF line endings")
        if path.suffix == ".svg":
            try:
                svg = ET.fromstring(content)
                if svg.tag != "{http://www.w3.org/2000/svg}svg":
                    errors.append(f"{relative}: expected SVG root element")
            except ET.ParseError as exc:
                errors.append(f"{relative}: invalid SVG XML: {exc}")
        if path.suffix == ".mmd" and not re.match(r"^flowchart\s+(?:LR|TD)\b", content):
            errors.append(f"{relative}: expected project flowchart header (not a Mermaid render check)")
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
            # Validate local destinations and heading fragments, including same-file TOCs.
            # Remote URLs are reviewed in the source register, not fetched by this check.
            for link in re.findall(r"\[[^\]]*\]\(([^)]+)\)", content):
                if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", link):
                    continue
                destination, _, fragment = link.partition("#")
                target = (path.parent / unquote(destination)).resolve() if destination else path
                if not target.is_relative_to(ROOT) or not target.exists():
                    errors.append(f"{relative}: invalid local link {link}")
                    continue
                if fragment and target.suffix == ".md":
                    try:
                        anchors = heading_ids(target.read_text(encoding="utf-8"))
                    except (OSError, UnicodeDecodeError):
                        errors.append(f"{relative}: unreadable linked Markdown {link}")
                        continue
                    if unquote(fragment) not in anchors:
                        errors.append(f"{relative}: invalid local heading {link}")
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
