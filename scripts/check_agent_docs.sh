#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if [[ ! -f AGENTS.md ]]; then
  echo "[agent-docs] missing AGENTS.md"
  exit 1
fi

if [[ ! -e CLAUDE.md ]]; then
  echo "[agent-docs] missing CLAUDE.md"
  exit 1
fi

if [[ -L CLAUDE.md ]]; then
  target="$(readlink CLAUDE.md)"
  if [[ "$target" != "AGENTS.md" ]]; then
    echo "[agent-docs] CLAUDE.md symlink target mismatch: $target (expected AGENTS.md)"
    exit 1
  fi
  echo "[agent-docs] ok: CLAUDE.md -> AGENTS.md"
  exit 0
fi

if cmp -s AGENTS.md CLAUDE.md; then
  echo "[agent-docs] warning: CLAUDE.md is not symlink; content matches AGENTS.md (fallback accepted)"
  exit 0
fi

echo "[agent-docs] mismatch: CLAUDE.md differs from AGENTS.md"
exit 1
