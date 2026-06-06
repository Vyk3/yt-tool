#!/usr/bin/env python3
"""Update docs/appcast.xml with a signed release entry.

Usage:
    python3 scripts/release/update_appcast.py \
        --version 0.2.0 \
        --build 3 \
        --signature "base64..." \
        --length 81869575

Reads the existing docs/appcast.xml, finds the <item> matching the version
(by sparkle:shortVersionString), and updates its edSignature and length.
If no matching item exists, inserts a new one.

Exit codes:
    0  Success
    1  appcast.xml not found
    2  Invalid arguments
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
APPCAST_PATH = REPO_ROOT / "docs" / "appcast.xml"

DOWNLOAD_URL_TEMPLATE = (
    "https://github.com/Vyk3/yt-tool/releases/download/v{version}/YTTool.zip"
)


def update_existing_entry(xml: str, version: str, signature: str, length: int) -> str | None:
    """Update edSignature and length for an existing version entry."""
    pattern = re.compile(
        r"(<item>\s*"
        rf"<title>v{re.escape(version)}</title>.*?"
        r"<enclosure[^>]*)"
        r'sparkle:edSignature="[^"]*"'
        r"(\s*)"
        r'length="[^"]*"'
        r"([^>]*/>\s*</item>)",
        re.DOTALL,
    )
    match = pattern.search(xml)
    if not match:
        return None

    replacement = (
        f"{match.group(1)}"
        f'sparkle:edSignature="{signature}"'
        f"{match.group(2)}"
        f'length="{length}"'
        f"{match.group(3)}"
    )
    return xml[: match.start()] + replacement + xml[match.end() :]


def create_new_entry(
    xml: str, version: str, build: str, signature: str, length: int
) -> str:
    """Insert a new <item> for a version that doesn't exist yet."""
    pub_date = format_datetime(datetime.now(timezone.utc), usegmt=True)
    url = DOWNLOAD_URL_TEMPLATE.format(version=version)

    new_item = (
        f"    <item>\n"
        f"      <title>v{version}</title>\n"
        f"      <pubDate>{pub_date}</pubDate>\n"
        f"      <sparkle:version>{build}</sparkle:version>\n"
        f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"      <description><![CDATA[\n"
        f"        <h2>v{version}</h2>\n"
        f"      ]]></description>\n"
        f"      <enclosure\n"
        f'        url="{url}"\n'
        f'        type="application/octet-stream"\n'
        f'        sparkle:edSignature="{signature}"\n'
        f'        length="{length}"\n'
        f"      />\n"
        f"    </item>\n"
    )

    # Insert before the first existing <item>
    first_item = re.search(r"^(\s*)<item>", xml, re.MULTILINE)
    if first_item:
        pos = first_item.start()
        return xml[:pos] + new_item + xml[pos:]

    # Fallback: insert before </channel>
    channel_close = xml.rfind("</channel>")
    if channel_close == -1:
        raise ValueError("No </channel> found in appcast.xml")
    return xml[:channel_close] + new_item + xml[channel_close:]


def main() -> None:
    parser = argparse.ArgumentParser(description="Update appcast.xml with release signature")
    parser.add_argument("--version", required=True, help="Version string, e.g. 0.2.0")
    parser.add_argument("--build", required=True, help="Build number, e.g. 3")
    parser.add_argument("--signature", required=True, help="Ed25519 signature (base64)")
    parser.add_argument("--length", required=True, type=int, help="File size in bytes")
    parser.add_argument("--appcast", default=None, help="Path to appcast.xml (default: docs/appcast.xml)")
    args = parser.parse_args()

    appcast_path = Path(args.appcast) if args.appcast else APPCAST_PATH
    if not appcast_path.exists():
        print(f"Error: appcast.xml not found at {appcast_path}", file=sys.stderr)
        sys.exit(1)

    xml = appcast_path.read_text(encoding="utf-8")
    updated = update_existing_entry(xml, args.version, args.signature, args.length)

    if updated is None:
        print(f"Version {args.version} not found, creating new entry")
        updated = create_new_entry(xml, args.version, args.build, args.signature, args.length)

    appcast_path.write_text(updated, encoding="utf-8")
    print(f"Updated appcast.xml: v{args.version} signature={args.signature[:20]}... length={args.length}")


if __name__ == "__main__":
    main()
