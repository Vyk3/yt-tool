#!/usr/bin/env bash

set -euo pipefail

# 这个脚本用于统一查询当前仓库“最近一次相关 CI”的状态。
#
# 设计目标：
# 1. 给 Claude / 人类开发者一个稳定、单一的查询入口，避免在不同地方零散调用
#    `gh pr checks`、`gh run list`、`gh run view` 等多个命令。
# 2. 默认只做“一次查询”，不在脚本里偷偷长时间轮询，从而减少等待和噪音。
# 3. 优先按“当前分支”推断关联的 CI；如果当前分支没有 pull_request 事件的 CI，
#    再回退到 push 事件的 CI。
#
# 典型使用方式：
# - `bash tools/check_ci.sh`
#     查询当前分支最近一次相关 CI
# - `bash tools/check_ci.sh --branch some-branch`
#     查询指定分支最近一次相关 CI
# - `bash tools/check_ci.sh --repo owner/name --branch some-branch`
#     查询指定仓库、指定分支最近一次相关 CI
# - `bash tools/check_ci.sh --json`
#     以 JSON 形式输出，适合后续被脚本或自动化消费


# 先切到仓库根目录，确保从任意目录调用时都能获得一致行为。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"


# -----------------------------
# 参数解析
# -----------------------------

OUTPUT_MODE="text"
REPO_ARG=""
BRANCH_ARG=""
WATCH_MODE=0
WATCH_INTERVAL_SEC=60
WATCH_TIMEOUT_SEC=300

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_MODE="json"
      shift
      ;;
    --watch)
      WATCH_MODE=1
      shift
      ;;
    --interval)
      WATCH_INTERVAL_SEC="${2:-}"
      shift 2
      ;;
    --timeout)
      WATCH_TIMEOUT_SEC="${2:-}"
      shift 2
      ;;
    --repo)
      REPO_ARG="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_ARG="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
用法：
  bash tools/check_ci.sh [--repo owner/name] [--branch branch-name] [--json]
  bash tools/check_ci.sh --watch [--interval 60] [--timeout 300] [--repo owner/name] [--branch branch-name]

说明：
  默认查询当前仓库、当前分支最近一次相关 CI。
  查询顺序：
  1. pull_request 事件的 CI
  2. push 事件的 CI

输出：
  默认输出简洁文本；
  使用 --json 时输出机器可读 JSON。

watch 模式：
  仅在显式传入 --watch 时启用。
  启用后脚本会按 interval 周期重复查询，直到：
  - CI 进入终态（passed / failed）
  - 查询结果明确为 unavailable / not_found
  - 超过 timeout
EOF
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      exit 2
      ;;
  esac
done

# watch 参数必须是正整数，避免出现 0 秒或非法值导致空转。
case "${WATCH_INTERVAL_SEC}" in
  ''|*[!0-9]*)
    echo "--interval 必须是正整数秒。" >&2
    exit 2
    ;;
esac

case "${WATCH_TIMEOUT_SEC}" in
  ''|*[!0-9]*)
    echo "--timeout 必须是正整数秒。" >&2
    exit 2
    ;;
esac

if [[ "${WATCH_INTERVAL_SEC}" -le 0 || "${WATCH_TIMEOUT_SEC}" -le 0 ]]; then
  echo "--interval 和 --timeout 都必须大于 0。" >&2
  exit 2
fi


# -----------------------------
# 前置依赖检查
# -----------------------------

# 这个脚本依赖 gh，因为 GitHub Actions run 的结构化查询对 gh 最直接。
if ! command -v gh >/dev/null 2>&1; then
  echo "未找到 gh 命令，无法查询 GitHub Actions 状态。" >&2
  exit 1
fi

# Python 只用于稳妥解析 JSON，避免依赖 jq。
if ! command -v python3 >/dev/null 2>&1; then
  echo "未找到 python3，无法解析 gh 返回的 JSON 数据。" >&2
  exit 1
fi


# -----------------------------
# 仓库与分支解析
# -----------------------------

# 如果用户没有显式指定 repo，就从 git remote 自动推断当前仓库。
if [[ -n "${REPO_ARG}" ]]; then
  REPO="${REPO_ARG}"
else
  REPO="$(python3 -c 'import re, subprocess, sys
out = subprocess.check_output(["git", "remote", "get-url", "origin"], text=True).strip()
m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", out)
if not m:
    print("", end="")
    sys.exit(1)
print(m.group(1))')"
fi

# 如果用户没有显式指定 branch，就读取当前 git 分支名。
if [[ -n "${BRANCH_ARG}" ]]; then
  BRANCH="${BRANCH_ARG}"
else
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi


# -----------------------------
# watch 模式
# -----------------------------

# watch 模式下，脚本会再次调用自己，但只调用“单次查询”模式。
# 也就是说：
# - 默认模式：查一次就退出
# - watch 模式：显式启用后，按固定间隔反复执行默认模式
#
# 这样可以把“查询逻辑”和“轮询逻辑”保持解耦，避免默认调用就悄悄进入轮询。
if [[ "${WATCH_MODE}" -eq 1 ]]; then
  WATCH_START_TS="$(date +%s)"
  LAST_SUMMARY=""

  while true; do
    NOW_TS="$(date +%s)"
    ELAPSED_SEC="$((NOW_TS - WATCH_START_TS))"

    # 这里明确调用“单次查询”模式，避免 watch 递归叠加。
    QUERY_JSON="$(
      bash "${BASH_SOURCE[0]}" \
        --json \
        --repo "${REPO}" \
        --branch "${BRANCH}" \
        2>/dev/null || true
    )"

    # 如果 JSON 解析失败，说明脚本返回内容异常，直接按 unavailable 处理。
    SUMMARY="$(
      python3 - <<'PY' "${QUERY_JSON}"
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("unavailable")
    raise SystemExit(0)

print(data.get("summary", "unknown"))
PY
    )"

    # 只在首次观察到状态，或状态发生变化时打印，减少轮询噪音。
    if [[ "${OUTPUT_MODE}" != "json" && "${SUMMARY}" != "${LAST_SUMMARY}" ]]; then
      python3 - <<'PY' "${QUERY_JSON}" "${ELAPSED_SEC}"
import json
import sys

data = json.loads(sys.argv[1])
elapsed = sys.argv[2]

print(
    f"[CI-WATCH] summary={data.get('summary')} | "
    f"branch={data.get('branch')} | elapsed={elapsed}s"
)
if data.get("url"):
    print(f"url: {data['url']}")
if data.get("message"):
    print(f"message: {data['message']}")
PY
      LAST_SUMMARY="${SUMMARY}"
    fi

    case "${SUMMARY}" in
      passed)
        if [[ "${OUTPUT_MODE}" == "json" ]]; then
          python3 - <<'PY' "${QUERY_JSON}" "${ELAPSED_SEC}" "${WATCH_INTERVAL_SEC}"
import json
import sys

data = json.loads(sys.argv[1])
data["watch_mode"] = True
data["watch_elapsed_sec"] = int(sys.argv[2])
data["watch_interval_sec"] = int(sys.argv[3])
print(json.dumps(data, ensure_ascii=False))
PY
        fi
        exit 0
        ;;
      failed)
        if [[ "${OUTPUT_MODE}" == "json" ]]; then
          python3 - <<'PY' "${QUERY_JSON}" "${ELAPSED_SEC}" "${WATCH_INTERVAL_SEC}"
import json
import sys

data = json.loads(sys.argv[1])
data["watch_mode"] = True
data["watch_elapsed_sec"] = int(sys.argv[2])
data["watch_interval_sec"] = int(sys.argv[3])
print(json.dumps(data, ensure_ascii=False))
PY
        fi
        exit 1
        ;;
      not_found)
        if [[ "${OUTPUT_MODE}" == "json" ]]; then
          python3 - <<'PY' "${QUERY_JSON}" "${ELAPSED_SEC}" "${WATCH_INTERVAL_SEC}"
import json
import sys

data = json.loads(sys.argv[1])
data["watch_mode"] = True
data["watch_elapsed_sec"] = int(sys.argv[2])
data["watch_interval_sec"] = int(sys.argv[3])
print(json.dumps(data, ensure_ascii=False))
PY
        fi
        exit 4
        ;;
      unavailable)
        if [[ "${OUTPUT_MODE}" == "json" ]]; then
          python3 - <<'PY' "${QUERY_JSON}" "${ELAPSED_SEC}" "${WATCH_INTERVAL_SEC}"
import json
import sys

data = json.loads(sys.argv[1])
data["watch_mode"] = True
data["watch_elapsed_sec"] = int(sys.argv[2])
data["watch_interval_sec"] = int(sys.argv[3])
print(json.dumps(data, ensure_ascii=False))
PY
        fi
        exit 3
        ;;
      pending|unknown)
        ;;
    esac

    if [[ "${ELAPSED_SEC}" -ge "${WATCH_TIMEOUT_SEC}" ]]; then
      if [[ "${OUTPUT_MODE}" == "json" ]]; then
        python3 - <<'PY' "${REPO}" "${BRANCH}" "${ELAPSED_SEC}" "${WATCH_INTERVAL_SEC}" "${WATCH_TIMEOUT_SEC}"
import json
import sys

payload = {
    "summary": "timeout",
    "repo": sys.argv[1],
    "branch": sys.argv[2],
    "watch_mode": True,
    "watch_elapsed_sec": int(sys.argv[3]),
    "watch_interval_sec": int(sys.argv[4]),
    "watch_timeout_sec": int(sys.argv[5]),
    "message": "watch 模式超时，CI 在限定时间内未进入终态。",
}
print(json.dumps(payload, ensure_ascii=False))
PY
      else
        echo "[CI-WATCH] timeout | branch=${BRANCH} | waited=${ELAPSED_SEC}s"
      fi
      exit 2
    fi

    sleep "${WATCH_INTERVAL_SEC}"
  done
fi


# -----------------------------
# 查询逻辑
# -----------------------------

# 这里只取“最新一条”相关 CI。
# 优先看 pull_request 事件，因为你当前主要关心的是 PR 上的 CI。
#
# 同时我们保留 stderr：
# - 如果 GitHub API 连不上，应该返回“unavailable”
# - 如果只是确实没有该分支的 CI，才返回“not_found”
PR_ERR_FILE="$(mktemp)"
PUSH_ERR_FILE="$(mktemp)"
trap 'rm -f "${PR_ERR_FILE}" "${PUSH_ERR_FILE}"' EXIT

PR_RUN_JSON="$(
  gh run list \
    --repo "${REPO}" \
    --branch "${BRANCH}" \
    --event pull_request \
    --workflow CI \
    --limit 1 \
    --json databaseId,workflowName,displayTitle,event,status,conclusion,createdAt,updatedAt,headBranch,headSha,url \
    2>"${PR_ERR_FILE}" || true
)"

# 如果分支上没有 pull_request 事件的 CI，再回退看 push 事件。
PUSH_RUN_JSON="$(
  gh run list \
    --repo "${REPO}" \
    --branch "${BRANCH}" \
    --event push \
    --workflow CI \
    --limit 1 \
    --json databaseId,workflowName,displayTitle,event,status,conclusion,createdAt,updatedAt,headBranch,headSha,url \
    2>"${PUSH_ERR_FILE}" || true
)"

PR_ERR="$(cat "${PR_ERR_FILE}")"
PUSH_ERR="$(cat "${PUSH_ERR_FILE}")"


# 下面这段 Python 负责：
# 1. 从两份 JSON 中挑出优先级更高的一条 run
# 2. 计算运行时长
# 3. 统一生成文本或 JSON 输出
python3 - <<'PY' "${OUTPUT_MODE}" "${REPO}" "${BRANCH}" "${PR_RUN_JSON}" "${PUSH_RUN_JSON}" "${PR_ERR}" "${PUSH_ERR}"
import datetime as dt
import json
import sys


def parse_first(raw: str):
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if isinstance(data, list) and data:
        return data[0]
    return None


def parse_time(value: str | None):
    if not value:
        return None
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def normalize(run: dict | None, source: str):
    if not run:
        return None
    created = parse_time(run.get("createdAt"))
    updated = parse_time(run.get("updatedAt"))
    duration_sec = None
    if created and updated:
        duration_sec = int((updated - created).total_seconds())

    status = run.get("status") or "unknown"
    conclusion = run.get("conclusion")

    if status != "completed":
        summary = "pending"
    elif conclusion == "success":
        summary = "passed"
    elif conclusion:
        summary = "failed"
    else:
        summary = "unknown"

    return {
        "source": source,
        "summary": summary,
        "status": status,
        "conclusion": conclusion,
        "workflow": run.get("workflowName"),
        "title": run.get("displayTitle"),
        "event": run.get("event"),
        "branch": run.get("headBranch"),
        "sha": run.get("headSha"),
        "run_id": run.get("databaseId"),
        "url": run.get("url"),
        "created_at": run.get("createdAt"),
        "updated_at": run.get("updatedAt"),
        "duration_sec": duration_sec,
    }


output_mode, repo, branch, pr_raw, push_raw, pr_err, push_err = sys.argv[1:8]

record = normalize(parse_first(pr_raw), "pull_request")
if record is None:
    record = normalize(parse_first(push_raw), "push")

if record is None:
    had_error = bool((pr_err or "").strip() or (push_err or "").strip())
    payload = {
        "summary": "unavailable" if had_error else "not_found",
        "repo": repo,
        "branch": branch,
        "message": (
            "查询 GitHub Actions 失败，请检查网络或 gh 认证。"
            if had_error
            else "未找到该分支最近一次 CI 记录。"
        ),
        "error": pr_err.strip() or push_err.strip() or None,
    }
    if output_mode == "json":
        print(json.dumps(payload, ensure_ascii=False))
    else:
        print(f"[CI] {payload['summary']} | repo={repo} | branch={branch}")
        print(f"message: {payload['message']}")
        if payload["error"]:
            print(f"error: {payload['error']}")
    sys.exit(1)

payload = {
    "summary": record["summary"],
    "repo": repo,
    "branch": branch,
    "source": record["source"],
    "status": record["status"],
    "conclusion": record["conclusion"],
    "workflow": record["workflow"],
    "title": record["title"],
    "url": record["url"],
    "duration_sec": record["duration_sec"],
    "created_at": record["created_at"],
    "updated_at": record["updated_at"],
    "run_id": record["run_id"],
    "sha": record["sha"],
}

if output_mode == "json":
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(0)

duration_text = (
    f"{record['duration_sec']}s" if record["duration_sec"] is not None else "unknown"
)
print(
    f"[CI] {payload['summary']} | repo={repo} | branch={branch} | "
    f"source={record['source']} | duration={duration_text}"
)
if record["title"]:
    print(f"title: {record['title']}")
if record["url"]:
    print(f"url: {record['url']}")
PY
