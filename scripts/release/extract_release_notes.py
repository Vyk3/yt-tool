#!/usr/bin/env python3
"""Extract release notes for a specific version from CHANGELOG.md.

Usage:
    python3 scripts/release/extract_release_notes.py v0.1.3
    python3 scripts/release/extract_release_notes.py 0.1.3
    python3 scripts/release/extract_release_notes.py v0.1.3 --changelog path/to/CHANGELOG.md
    python3 scripts/release/extract_release_notes.py v0.1.3 --out notes.md

Exit codes:
    0  Success (notes written to stdout or --out file)
    1  Version not found in CHANGELOG
    2  CHANGELOG file not found
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Match: ## [0.1.3] — 2026-05-28  or  ## [Unreleased]
VERSION_HEADER_RE = re.compile(r"^## \[(.+?)\]")


def extract_notes(changelog: str, version: str) -> str | None:
    """Return the release notes section for *version*, or None if not found."""
    lines = changelog.splitlines(keepends=True)
    capture = False
    start = -1

    for i, line in enumerate(lines):
        m = VERSION_HEADER_RE.match(line)
        if m:
            if capture:
                # Hit the next version header -> stop
                break
            if m.group(1) == version:
                capture = True
                start = i
                continue
        # Section divider between versions
        if capture and line.strip() == "---":
            break

    if start == -1:
        return None

    # Collect lines from after the header to the stop point
    section = lines[start + 1 : i]

    # Strip leading/trailing blank lines
    text = "".join(section).strip()
    return text if text else None


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract release notes from CHANGELOG.md")
    parser.add_argument("version", help="Version tag, e.g. v0.1.3 or 0.1.3")
    parser.add_argument(
        "--changelog",
        default=None,
        help="Path to CHANGELOG.md (default: repo root)",
    )
    parser.add_argument("--out", default=None, help="Write output to file instead of stdout")
    args = parser.parse_args()

    # Normalize: strip leading 'v'
    version = args.version.lstrip("v")

    # Resolve CHANGELOG path
    if args.changelog:
        changelog_path = Path(args.changelog)
    else:
        # Walk up from script location to find repo root
        repo_root = Path(__file__).resolve().parent.parent.parent
        changelog_path = repo_root / "CHANGELOG.md"

    if not changelog_path.exists():
        print(f"Error: CHANGELOG not found at {changelog_path}", file=sys.stderr)
        sys.exit(2)

    changelog = changelog_path.read_text(encoding="utf-8")
    notes = extract_notes(changelog, version)

    if notes is None:
        print(f"Error: version {version} not found in {changelog_path}", file=sys.stderr)
        sys.exit(1)

    if args.out:
        Path(args.out).write_text(notes + "\n", encoding="utf-8")
    else:
        print(notes)


if __name__ == "__main__":
    main()
