#!/usr/bin/env python3
"""Validate release preconditions before pushing or publishing a tag."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from extract_release_notes import extract_notes


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TAG_RE = re.compile(r"^v?(?P<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$")
SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
README_FEATURE_DOCS = ("README.md", "README.en.md")
CHANGELOG_SECTION_RE = re.compile(r"^###\s+\S+")
CHANGELOG_ADDED_RE = re.compile(r"^###\s+Added\s*$", re.IGNORECASE)
CHANGELOG_BULLET_RE = re.compile(r"^\s*[-*]\s+\S")


@dataclass(frozen=True)
class Issue:
    check: str
    detail: str


@dataclass(frozen=True)
class ReadinessWarning:
    check: str
    detail: str


def normalize_version(tag: str) -> str:
    match = TAG_RE.match(tag)
    if not match:
        raise ValueError(f"expected a release tag like v0.2.3, got `{tag}`")
    return match.group("version")


def run_git(repo_root: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=10,
    )


def check_tag_reachable(repo_root: Path, tag_ref: str, main_ref: str) -> Issue | None:
    result = run_git(repo_root, ["merge-base", "--is-ancestor", tag_ref, main_ref])
    if result.returncode == 0:
        return None

    detail = result.stderr.strip()
    if detail:
        detail = f" ({detail})"
    return Issue(
        check="git-ref",
        detail=f"`{tag_ref}` is not reachable from `{main_ref}`{detail}",
    )


def check_changelog(repo_root: Path, version: str) -> Issue | None:
    changelog_path = repo_root / "CHANGELOG.md"
    if not changelog_path.exists():
        return Issue("changelog", "`CHANGELOG.md` does not exist")

    notes = extract_notes(changelog_path.read_text(encoding="utf-8"), version)
    if notes:
        return None
    return Issue(
        check="changelog",
        detail=f"`CHANGELOG.md` has no non-empty section for `{version}`",
    )


def changelog_has_added_entries(notes: str) -> bool:
    in_added = False
    for line in notes.splitlines():
        if CHANGELOG_ADDED_RE.match(line):
            in_added = True
            continue
        if in_added and CHANGELOG_SECTION_RE.match(line):
            return False
        if in_added and CHANGELOG_BULLET_RE.match(line):
            return True
    return False


def find_previous_release_tag(repo_root: Path, tag_ref: str, version: str) -> str | None:
    result = run_git(
        repo_root,
        ["tag", "--list", "v[0-9]*", "--merged", tag_ref, "--sort=-v:refname"],
    )
    if result.returncode != 0:
        return None

    for tag in result.stdout.splitlines():
        try:
            tag_version = normalize_version(tag)
        except ValueError:
            continue
        if tag_version != version:
            return tag
    return None


def readme_changes_since(repo_root: Path, base_ref: str, tag_ref: str) -> set[str] | None:
    result = run_git(
        repo_root,
        [
            "diff",
            "--name-only",
            f"{base_ref}..{tag_ref}",
            "--",
            *README_FEATURE_DOCS,
        ],
    )
    if result.returncode != 0:
        return None
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def check_readme_sync_warning(
    repo_root: Path, version: str, tag_ref: str
) -> ReadinessWarning | None:
    changelog_path = repo_root / "CHANGELOG.md"
    if not changelog_path.exists():
        return None

    notes = extract_notes(changelog_path.read_text(encoding="utf-8"), version)
    if not notes or not changelog_has_added_entries(notes):
        return None

    previous_tag = find_previous_release_tag(repo_root, tag_ref, version)
    if not previous_tag:
        return None

    changed_readmes = readme_changes_since(repo_root, previous_tag, tag_ref)
    if changed_readmes is None:
        return None

    missing = [path for path in README_FEATURE_DOCS if path not in changed_readmes]
    if not missing:
        return None

    missing_list = ", ".join(f"`{path}`" for path in missing)
    return ReadinessWarning(
        check="readme-sync",
        detail=(
            f"`CHANGELOG.md` section for `{version}` has `Added` entries, "
            f"but {missing_list} did not change since `{previous_tag}`; "
            "verify README feature highlights cover user-visible additions."
        ),
    )


def item_matches_version(item: ET.Element, version: str) -> bool:
    title = item.findtext("title")
    short_version = item.findtext(f"{SPARKLE_NS}shortVersionString")
    return title == f"v{version}" and short_version == version


def check_appcast(repo_root: Path, version: str) -> Issue | None:
    appcast_path = repo_root / "docs" / "appcast.xml"
    if not appcast_path.exists():
        return Issue("appcast", "`docs/appcast.xml` does not exist")

    try:
        root = ET.parse(appcast_path).getroot()
    except ET.ParseError as exc:
        return Issue("appcast", f"`docs/appcast.xml` is not valid XML: {exc}")

    expected_url = f"/releases/download/v{version}/YTTool.zip"
    for item in root.findall("./channel/item"):
        if not item_matches_version(item, version):
            continue
        enclosure = item.find("enclosure")
        if enclosure is None:
            return Issue(
                check="appcast",
                detail=f"`docs/appcast.xml` item for `{version}` has no enclosure",
            )
        url = enclosure.attrib.get("url", "")
        if expected_url not in url:
            return Issue(
                check="appcast",
                detail=f"`docs/appcast.xml` item for `{version}` has unexpected URL `{url}`",
            )
        return None

    return Issue(
        check="appcast",
        detail=f"`docs/appcast.xml` has no item for `{version}`",
    )


def validate(args: argparse.Namespace) -> list[Issue]:
    repo_root = args.repo_root.resolve()
    version = normalize_version(args.tag)

    issues: list[Issue] = []
    if not args.skip_git_ref_check:
        issue = check_tag_reachable(repo_root, args.tag_ref, args.main_ref)
        if issue:
            issues.append(issue)

    issue = check_changelog(repo_root, version)
    if issue:
        issues.append(issue)

    if not args.skip_appcast_check:
        issue = check_appcast(repo_root, version)
        if issue:
            issues.append(issue)

    return issues


def collect_warnings(args: argparse.Namespace, version: str) -> list[ReadinessWarning]:
    repo_root = args.repo_root.resolve()
    warnings: list[ReadinessWarning] = []

    warning = check_readme_sync_warning(repo_root, version, args.tag_ref)
    if warning:
        warnings.append(warning)

    return warnings


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate release tag, changelog, and appcast readiness."
    )
    parser.add_argument("tag", help="Release tag, e.g. v0.2.3")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=REPO_ROOT,
        help="Repository root (default: auto-detected)",
    )
    parser.add_argument(
        "--tag-ref",
        default="HEAD",
        help="Git ref that will be tagged or published (default: HEAD)",
    )
    parser.add_argument(
        "--main-ref",
        default="main",
        help="Git ref that must contain --tag-ref (default: main)",
    )
    parser.add_argument(
        "--skip-git-ref-check",
        action="store_true",
        help="Only validate CHANGELOG.md and docs/appcast.xml.",
    )
    parser.add_argument(
        "--skip-appcast-check",
        action="store_true",
        help="Skip appcast.xml check (appcast entry is a post-build artifact).",
    )
    return parser.parse_args(argv[1:])


def main(argv: list[str]) -> int:
    try:
        args = parse_args(argv)
        version = normalize_version(args.tag)
        issues = validate(args)
        warnings = collect_warnings(args, version)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if issues:
        print(f"FOUND {len(issues)} release readiness issue(s) for v{version}")
        for issue in issues:
            print(f"- {issue.check}: {issue.detail}")
        print_warnings(warnings, version)
        return 1

    print_warnings(warnings, version)
    print(f"OK: release readiness passed for v{version}")
    return 0


def print_warnings(warnings: list[ReadinessWarning], version: str) -> None:
    if not warnings:
        return
    print(f"WARN: {len(warnings)} release readiness warning(s) for v{version}")
    for warning in warnings:
        print(f"- {warning.check}: {warning.detail}")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
