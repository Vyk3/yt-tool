#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
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
        issues.extend(scan_file(path, zipapp_asset_name, actual_test_count))

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
