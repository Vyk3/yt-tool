#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

OUTPUT_MODE="text"
REPO_ARG=""
RULESET_NAME="protect-main"
ENVIRONMENT_NAME="dependency-release"
EXPECTED_RULESET_INCLUDE="~DEFAULT_BRANCH"
EXPECTED_ENVIRONMENT_BRANCH="main"
EXPECT_PREVENT_SELF_REVIEW="false"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_MODE="json"
      shift
      ;;
    --repo)
      REPO_ARG="${2:-}"
      shift 2
      ;;
    --ruleset)
      RULESET_NAME="${2:-}"
      shift 2
      ;;
    --environment)
      ENVIRONMENT_NAME="${2:-}"
      shift 2
      ;;
    --expected-ruleset-include)
      EXPECTED_RULESET_INCLUDE="${2:-}"
      shift 2
      ;;
    --expected-environment-branch)
      EXPECTED_ENVIRONMENT_BRANCH="${2:-}"
      shift 2
      ;;
    --expect-prevent-self-review)
      EXPECT_PREVENT_SELF_REVIEW="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  bash scripts/check_github_governance.sh [options]

Options:
  --json                              Output machine-readable JSON
  --repo owner/name                   Override repo inferred from origin
  --ruleset NAME                      Expected ruleset name (default: protect-main)
  --environment NAME                  Expected environment name (default: dependency-release)
  --expected-ruleset-include VALUE    Expected ruleset include ref (default: ~DEFAULT_BRANCH)
  --expected-environment-branch NAME  Expected deployment branch policy (default: main)
  --expect-prevent-self-review BOOL   Expected environment prevent_self_review value (default: false)

Checks:
  - ruleset exists exactly once by name
  - ruleset enforcement is active
  - ruleset target is branch
  - ruleset include/exclude match expected main-only shape
  - required status checks rule exists
  - environment exists
  - required reviewers rule exists and is non-empty
  - prevent_self_review matches expectation
  - environment branch policy is custom and targets the expected branch exactly
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing gh command." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3 command." >&2
  exit 1
fi

if [[ -n "${REPO_ARG}" ]]; then
  REPO="${REPO_ARG}"
else
  REPO="$(python3 -c 'import re, subprocess, sys
out = subprocess.check_output(["git", "remote", "get-url", "origin"], text=True).strip()
m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", out)
if not m:
    sys.exit(1)
print(m.group(1))')"
fi

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/github-governance.XXXXXX")"
cleanup() {
  rm -rf "${TMPROOT}"
}
trap cleanup EXIT

api_get() {
  local path="$1"
  local body_file="$2"
  local error_file="$3"

  if gh api --method GET "${path}" >"${body_file}" 2>"${error_file}"; then
    return 0
  fi

  return 1
}

RULESETS_JSON="${TMPROOT}/rulesets.json"
RULESETS_ERR="${TMPROOT}/rulesets.err"
RULESET_JSON="${TMPROOT}/ruleset.json"
RULESET_ERR="${TMPROOT}/ruleset.err"
ENV_JSON="${TMPROOT}/environment.json"
ENV_ERR="${TMPROOT}/environment.err"
BRANCH_POLICIES_JSON="${TMPROOT}/branch-policies.json"
BRANCH_POLICIES_ERR="${TMPROOT}/branch-policies.err"

RULESETS_OK=0
RULESET_OK=0
ENV_OK=0
BRANCH_POLICIES_OK=0

if api_get "repos/${REPO}/rulesets?per_page=100" "${RULESETS_JSON}" "${RULESETS_ERR}"; then
  RULESETS_OK=1
fi

RULESET_ID=""
if [[ "${RULESETS_OK}" -eq 1 ]]; then
  RULESET_ID="$(
    python3 - <<'PY' "${RULESETS_JSON}" "${RULESET_NAME}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rulesets = json.load(fh)

name = sys.argv[2]
matches = [str(item["id"]) for item in rulesets if item.get("name") == name]

if len(matches) == 1:
    print(matches[0])
PY
  )"
fi

if [[ -n "${RULESET_ID}" ]]; then
  if api_get "repos/${REPO}/rulesets/${RULESET_ID}" "${RULESET_JSON}" "${RULESET_ERR}"; then
    RULESET_OK=1
  fi
fi

if api_get "repos/${REPO}/environments/${ENVIRONMENT_NAME}" "${ENV_JSON}" "${ENV_ERR}"; then
  ENV_OK=1
fi

if [[ "${ENV_OK}" -eq 1 ]]; then
  if python3 - <<'PY' "${ENV_JSON}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

policy = data.get("deployment_branch_policy") or {}
raise SystemExit(0 if policy.get("custom_branch_policies") else 1)
PY
  then
    if api_get \
      "repos/${REPO}/environments/${ENVIRONMENT_NAME}/deployment-branch-policies" \
      "${BRANCH_POLICIES_JSON}" \
      "${BRANCH_POLICIES_ERR}"
    then
      BRANCH_POLICIES_OK=1
    fi
  fi
fi

python3 - <<'PY' \
  "${OUTPUT_MODE}" \
  "${REPO}" \
  "${RULESET_NAME}" \
  "${ENVIRONMENT_NAME}" \
  "${EXPECTED_RULESET_INCLUDE}" \
  "${EXPECTED_ENVIRONMENT_BRANCH}" \
  "${EXPECT_PREVENT_SELF_REVIEW}" \
  "${RULESETS_OK}" \
  "${RULESET_OK}" \
  "${ENV_OK}" \
  "${BRANCH_POLICIES_OK}" \
  "${RULESETS_JSON}" \
  "${RULESETS_ERR}" \
  "${RULESET_JSON}" \
  "${RULESET_ERR}" \
  "${ENV_JSON}" \
  "${ENV_ERR}" \
  "${BRANCH_POLICIES_JSON}" \
  "${BRANCH_POLICIES_ERR}"
import json
import sys
from pathlib import Path


def read_text(path_str: str) -> str:
    path = Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def read_json(path_str: str):
    path = Path(path_str)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def issue(target: str, detail: str):
    issues.append({"target": target, "detail": detail})


(
    output_mode,
    repo,
    expected_ruleset_name,
    expected_environment_name,
    expected_ruleset_include,
    expected_environment_branch,
    expected_prevent_self_review,
    rulesets_ok,
    ruleset_ok,
    environment_ok,
    branch_policies_ok,
    rulesets_json_path,
    rulesets_err_path,
    ruleset_json_path,
    ruleset_err_path,
    environment_json_path,
    environment_err_path,
    branch_policies_json_path,
    branch_policies_err_path,
) = sys.argv[1:]

issues = []

rulesets = read_json(rulesets_json_path) if rulesets_ok == "1" else None
ruleset_detail = read_json(ruleset_json_path) if ruleset_ok == "1" else None
environment_detail = read_json(environment_json_path) if environment_ok == "1" else None
branch_policies = read_json(branch_policies_json_path) if branch_policies_ok == "1" else None

ruleset_summary = {
    "name": expected_ruleset_name,
    "id": None,
    "enforcement": None,
    "target": None,
    "ref_include": [],
    "ref_exclude": [],
    "required_checks": [],
}

environment_summary = {
    "name": expected_environment_name,
    "reviewers": [],
    "prevent_self_review": None,
    "custom_branch_policies": None,
    "protected_branches": None,
    "branch_policies": [],
}

if rulesets is None:
    issue("ruleset", f"failed to list rulesets: {read_text(rulesets_err_path) or 'unknown error'}")
else:
    matches = [item for item in rulesets if item.get("name") == expected_ruleset_name]
    if not matches:
        issue("ruleset", f"ruleset `{expected_ruleset_name}` not found")
    elif len(matches) > 1:
        issue("ruleset", f"ruleset `{expected_ruleset_name}` matched {len(matches)} entries")
    elif ruleset_detail is None:
        issue("ruleset", f"failed to read ruleset detail: {read_text(ruleset_err_path) or 'unknown error'}")
    else:
        ruleset_summary["id"] = ruleset_detail.get("id")
        ruleset_summary["enforcement"] = ruleset_detail.get("enforcement")
        ruleset_summary["target"] = ruleset_detail.get("target")
        conditions = ruleset_detail.get("conditions") or {}
        ref_name = conditions.get("ref_name") or {}
        ruleset_summary["ref_include"] = ref_name.get("include") or []
        ruleset_summary["ref_exclude"] = ref_name.get("exclude") or []

        required_checks = []
        for rule in ruleset_detail.get("rules") or []:
            if rule.get("type") != "required_status_checks":
                continue
            params = rule.get("parameters") or {}
            for item in params.get("required_status_checks") or []:
                context = item.get("context")
                if context:
                    required_checks.append(context)
        ruleset_summary["required_checks"] = required_checks

        if ruleset_summary["enforcement"] != "active":
            issue("ruleset", f"ruleset `{expected_ruleset_name}` enforcement is `{ruleset_summary['enforcement']}`")
        if ruleset_summary["target"] != "branch":
            issue("ruleset", f"ruleset `{expected_ruleset_name}` target is `{ruleset_summary['target']}`")
        accepted_includes = [[expected_ruleset_include]]
        if expected_ruleset_include == "~DEFAULT_BRANCH":
            accepted_includes.append([f"refs/heads/{expected_environment_branch}"])

        if ruleset_summary["ref_include"] not in accepted_includes:
            issue(
                "ruleset",
                "ruleset "
                f"`{expected_ruleset_name}` include refs are {ruleset_summary['ref_include']}, "
                f"expected one of {accepted_includes}",
            )
        if ruleset_summary["ref_exclude"] != []:
            issue("ruleset", f"ruleset `{expected_ruleset_name}` exclude refs are not empty: {ruleset_summary['ref_exclude']}")
        if not ruleset_summary["required_checks"]:
            issue("ruleset", f"ruleset `{expected_ruleset_name}` has no required status checks")

if environment_detail is None:
    issue("environment", f"failed to read environment `{expected_environment_name}`: {read_text(environment_err_path) or 'unknown error'}")
else:
    policy = environment_detail.get("deployment_branch_policy") or {}
    protection_rules = environment_detail.get("protection_rules") or []
    required_reviewers_rule = next(
        (rule for rule in protection_rules if rule.get("type") == "required_reviewers"),
        None,
    )

    environment_summary["custom_branch_policies"] = policy.get("custom_branch_policies")
    environment_summary["protected_branches"] = policy.get("protected_branches")

    if required_reviewers_rule is None:
        issue("environment", f"environment `{expected_environment_name}` has no required_reviewers rule")
    else:
        reviewers = []
        for entry in required_reviewers_rule.get("reviewers") or []:
            r = entry.get("reviewer", {})
            name = r.get("login") or r.get("slug")
            if name:
                reviewers.append(name)
        environment_summary["reviewers"] = sorted(reviewers)
        environment_summary["prevent_self_review"] = required_reviewers_rule.get("prevent_self_review")

        if not environment_summary["reviewers"]:
            issue("environment", f"environment `{expected_environment_name}` has no required reviewers")
        expected_bool = expected_prevent_self_review.lower()
        if expected_bool not in {"true", "false"}:
            issue("environment", f"invalid expected prevent_self_review value `{expected_prevent_self_review}`")
        else:
            expected_value = expected_bool == "true"
            if environment_summary["prevent_self_review"] != expected_value:
                issue(
                    "environment",
                    f"environment `{expected_environment_name}` prevent_self_review is `{environment_summary['prevent_self_review']}`, expected `{expected_value}`",
                )

    if environment_summary["custom_branch_policies"] != True:
        issue(
            "environment",
            f"environment `{expected_environment_name}` custom_branch_policies is `{environment_summary['custom_branch_policies']}`",
        )

    if branch_policies is None:
        if environment_summary["custom_branch_policies"] is True:
            issue(
                "environment",
                "failed to read deployment branch policies: "
                + (read_text(branch_policies_err_path) or "unknown error"),
            )
    else:
        branch_entries = branch_policies.get("branch_policies") or []
        environment_summary["branch_policies"] = sorted(
            entry.get("name") for entry in branch_entries if entry.get("name")
        )
        if environment_summary["branch_policies"] != [expected_environment_branch]:
            issue(
                "environment",
                f"environment `{expected_environment_name}` branch policies are {environment_summary['branch_policies']}, expected ['{expected_environment_branch}']",
            )

summary = "passed" if not issues else "failed"
payload = {
    "summary": summary,
    "repo": repo,
    "ruleset": ruleset_summary,
    "environment": environment_summary,
    "issues": issues,
}

if output_mode == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    raise SystemExit(0 if not issues else 1)

if issues:
    print(f"FOUND {len(issues)} github governance issue(s) for {repo}")
    for entry in issues:
        print(f"- {entry['target']}: {entry['detail']}")
    print("")
else:
    print(f"OK: github governance checks passed for {repo}")
    print("")

print("Observed ruleset:")
print(f"- name: {ruleset_summary['name']}")
print(f"- id: {ruleset_summary['id']}")
print(f"- enforcement: {ruleset_summary['enforcement']}")
print(f"- target: {ruleset_summary['target']}")
print(f"- include: {ruleset_summary['ref_include']}")
print(f"- exclude: {ruleset_summary['ref_exclude']}")
print(f"- required checks: {ruleset_summary['required_checks']}")
print("")
print("Observed environment:")
print(f"- name: {environment_summary['name']}")
print(f"- reviewers: {environment_summary['reviewers']}")
print(f"- prevent_self_review: {environment_summary['prevent_self_review']}")
print(f"- custom_branch_policies: {environment_summary['custom_branch_policies']}")
print(f"- protected_branches: {environment_summary['protected_branches']}")
print(f"- branch_policies: {environment_summary['branch_policies']}")

raise SystemExit(0 if not issues else 1)
PY
