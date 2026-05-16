#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DOC_PATHS = (
    REPO_ROOT / "README.md",
    REPO_ROOT / "README.en.md",
    REPO_ROOT / "CHANGELOG.md",
    REPO_ROOT / "docs",
    REPO_ROOT / "swift" / "DEVLOG.md",
    REPO_ROOT / "swift" / "docs",
)
ZIPAPP_SOURCE = REPO_ROOT / "swift" / "YTTool" / "Services" / "YtDlpUpdateService.swift"
TEST_ROOT = REPO_ROOT / "swift" / "Tests"
MARKDOWN_SUFFIXES = {".md", ".markdown"}
TEST_COUNT_PATTERNS = (
    re.compile(r"(?P<count>\d+)\s*个测试通过"),
    re.compile(r"Executed\s+(?P<count>\d+)\s+tests"),
    re.compile(r"(?P<count>\d+)\s+tests\s+passed", re.IGNORECASE),
)


@dataclass(frozen=True)
class Issue:
    path: Path
    line_number: int
    reason: str
    line: str


def resolve_doc_paths(args: list[str]) -> list[Path]:
    if args:
        return [Path(arg).resolve() for arg in args]

    paths: list[Path] = []
    for candidate in DEFAULT_DOC_PATHS:
        if candidate.is_dir():
            paths.extend(
                path
                for path in sorted(candidate.rglob("*"))
                if path.is_file() and path.suffix.lower() in MARKDOWN_SUFFIXES
            )
        elif candidate.is_file():
            paths.append(candidate)
    return paths


def derive_zipapp_asset_name() -> str:
    content = ZIPAPP_SOURCE.read_text(encoding="utf-8")
    match = re.search(r'zipappAssetName\s*=\s*"([^"]+)"', content)
    if not match:
        raise RuntimeError(f"Could not derive zipapp asset name from {ZIPAPP_SOURCE}")
    return match.group(1)


def count_swift_tests() -> int:
    total = 0
    for path in sorted(TEST_ROOT.rglob("*Tests.swift")):
        content = path.read_text(encoding="utf-8")
        total += len(re.findall(r"^[ \t]*func test[A-Za-z0-9_]+", content, flags=re.MULTILINE))
    return total


def is_zipapp_drift(line: str, zipapp_asset_name: str) -> bool:
    if zipapp_asset_name not in line and "zipapp" not in line.lower():
        if "yt-dlp_macos" not in line and "standalone" not in line.lower():
            return False
    lowered = line.lower()
    if "yt-dlp_macos" in line:
        return True
    if "standalone" in lowered and "yt-dlp" in lowered:
        if any(token in lowered for token in ("old", "legacy", "switched", "切换", "旧")):
            return False
        return True
    return False


def is_arm64_claim_drift(line: str) -> bool:
    lowered = line.lower()
    if not any(token in line for token in ("Intel", "x86_64", "universal")):
        return False
    if any(token in lowered for token in ("not supported", "unsupported", "removed", "remove", "arm64-only")):
        return False
    if any(token in line for token in ("不支持", "不在", "不属于", "不再提供", "移除", "仅", "只")):
        return False
    return True


def extract_test_count(line: str) -> int | None:
    for pattern in TEST_COUNT_PATTERNS:
        match = pattern.search(line)
        if match:
            return int(match.group("count"))
    return None


# --- Path reference checks ---

MARKDOWN_LINK_PATTERN = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
CODE_PATH_PATTERN = re.compile(
    r"(?:^|\s)(?:bash|python3?|cat|source|open|cd)\s+([^\s|;&>]+)"
)


def check_path_references(path: Path, content: str) -> list[Issue]:
    """Check that file paths referenced in docs actually exist."""
    issues: list[Issue] = []
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        # Markdown links
        for _text, target in MARKDOWN_LINK_PATTERN.findall(raw_line):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            # Strip anchor fragments
            target_path = target.split("#")[0]
            if not target_path:
                continue
            resolved = (path.parent / target_path).resolve()
            if not resolved.exists():
                issues.append(
                    Issue(
                        path=path,
                        line_number=line_number,
                        reason=f"broken link: `{target_path}` does not exist",
                        line=raw_line,
                    )
                )

        # Command-line path references in code blocks or inline
        for match in CODE_PATH_PATTERN.finditer(raw_line):
            ref = match.group(1).strip("`\"'")
            # Skip variables, flags, URLs
            if ref.startswith(("-", "$", "http", "~")):
                continue
            # Only check paths that look like relative file references
            if "/" in ref and not ref.startswith("/"):
                resolved = (REPO_ROOT / ref).resolve()
                if not resolved.exists() and not any(
                    c in ref for c in ("*", "{", "}", "<", ">")
                ):
                    issues.append(
                        Issue(
                            path=path,
                            line_number=line_number,
                            reason=f"broken path reference: `{ref}` not found in repo",
                            line=raw_line,
                        )
                    )
    return issues


# --- Changelog completeness check ---

CHANGELOG_DATE_PATTERN = re.compile(r"##\s*\[.*?\]\s*(?:—|–|-)\s*(\d{4}-\d{2}-\d{2})")
PR_MERGE_PATTERN = re.compile(r"^[0-9a-f]+\s+.*\(#(\d+)\)$")


def check_changelog_completeness() -> list[Issue]:
    """Check if merged PRs since last changelog date are documented."""
    changelog_path = REPO_ROOT / "CHANGELOG.md"
    if not changelog_path.exists():
        return []

    content = changelog_path.read_text(encoding="utf-8")

    # Find the most recent dated entry (skip [Unreleased])
    last_date = None
    for match in CHANGELOG_DATE_PATTERN.finditer(content):
        last_date = match.group(1)
        break  # first match is the most recent

    if not last_date:
        return []

    # Get PRs merged strictly after that date (next day onward)
    try:
        # Parse date and add one day to get "strictly after"
        entry_date = datetime.strptime(last_date, "%Y-%m-%d")
        after_date = entry_date.strftime("%Y-%m-%d")
        result = subprocess.run(
            ["git", "log", f"--after={after_date} 23:59:59", "--oneline", "--first-parent", "main"],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
            timeout=10,
        )
        if result.returncode != 0:
            return []
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        return []

    # Only flag user-visible changes (feat/fix), skip docs/chore/refactor
    skip_prefixes = ("docs:", "chore:", "refactor:", "style:", "ci:", "test:")
    merged_prs: list[str] = []
    for line in result.stdout.strip().splitlines():
        pr_match = PR_MERGE_PATTERN.match(line)
        if pr_match:
            # Extract commit message (after the hash + space)
            msg = line.split(" ", 1)[1] if " " in line else ""
            if not any(msg.lower().startswith(p) for p in skip_prefixes):
                merged_prs.append(f"#{pr_match.group(1)}")

    if not merged_prs:
        return []

    # Check which PRs are already mentioned in changelog
    undocumented = [pr for pr in merged_prs if pr not in content]

    if not undocumented:
        return []

    # Find the line of the last dated entry for reporting
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        if last_date in raw_line:
            return [
                Issue(
                    path=changelog_path,
                    line_number=line_number,
                    reason=f"PRs merged after {last_date} not in changelog: {', '.join(undocumented)}",
                    line=raw_line,
                )
            ]

    return []


def scan_file(path: Path, zipapp_asset_name: str, actual_test_count: int) -> list[Issue]:
    issues: list[Issue] = []
    content = path.read_text(encoding="utf-8")
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        if is_zipapp_drift(line, zipapp_asset_name):
            issues.append(
                Issue(
                    path=path,
                    line_number=line_number,
                    reason=f"mentions standalone asset wording, but code uses yt-dlp zipapp asset `{zipapp_asset_name}`",
                    line=raw_line,
                )
            )
        if is_arm64_claim_drift(line):
            issues.append(
                Issue(
                    path=path,
                    line_number=line_number,
                    reason="suggests Intel/x86_64/universal release support, but release scripts are arm64-only",
                    line=raw_line,
                )
            )
        documented_count = extract_test_count(line)
        if documented_count is not None and documented_count != actual_test_count:
            issues.append(
                Issue(
                    path=path,
                    line_number=line_number,
                    reason=f"documents {documented_count} tests, but swift/Tests currently contains {actual_test_count} test methods",
                    line=raw_line,
                )
            )
    return issues


def main(argv: list[str]) -> int:
    try:
        doc_paths = resolve_doc_paths(argv[1:])
        zipapp_asset_name = derive_zipapp_asset_name()
        actual_test_count = count_swift_tests()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    issues: list[Issue] = []
    seen_paths: set[Path] = set()
    for path in doc_paths:
        if path in seen_paths or not path.is_file():
            continue
        seen_paths.add(path)
        content = path.read_text(encoding="utf-8")
        issues.extend(scan_file(path, zipapp_asset_name, actual_test_count))
        issues.extend(check_path_references(path, content))

    # Changelog completeness (runs once, not per-file)
    issues.extend(check_changelog_completeness())

    if not issues:
        print(
            f"OK: no docs coherence issues found in {len(seen_paths)} files "
            f"(zipapp asset: {zipapp_asset_name}, test methods: {actual_test_count})"
        )
        return 0

    print(
        f"FOUND {len(issues)} docs coherence issue(s) "
        f"(zipapp asset: {zipapp_asset_name}, test methods: {actual_test_count})"
    )
    for issue in issues:
        rel_path = issue.path.relative_to(REPO_ROOT)
        print(f"- {rel_path}:{issue.line_number}: {issue.reason}")
        print(f"  {issue.line.rstrip()}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
