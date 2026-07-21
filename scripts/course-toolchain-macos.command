#!/bin/bash

# shellcheck source=toolchain/macos.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolchain/macos.sh"
# shellcheck source=toolchain/report.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolchain/report.sh"

course_toolchain_catalog_path() {
  if [ -n "${COURSE_TOOLCHAIN_CATALOG:-}" ]; then
    printf '%s\n' "$COURSE_TOOLCHAIN_CATALOG"
  else
    printf '%s/toolchain/catalog.json\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
}

get_course_toolchain_plan() {
  local profile="$1" gui_tools="${2:-}" catalog_path
  catalog_path="$(course_toolchain_catalog_path)" || return 64

  python3 -c '
import json
import re
import sys

class CatalogError(Exception):
    pass

def exact_list(actual, expected, description):
    if actual != expected:
        raise CatalogError("Invalid " + description + ".")

try:
    with open(sys.argv[1], encoding="utf-8") as catalog_file:
        catalog = json.load(catalog_file)
    if catalog.get("schema_version") != 1:
        raise CatalogError("Unsupported catalog schema version.")
    if not isinstance(catalog.get("profiles"), dict) or not isinstance(catalog.get("gui_tools"), list):
        raise CatalogError("Invalid course toolchain catalog.")

    all_tools = {"git_gh", "node_lts", "cloudflared", "docker_desktop", "antigravity", "vscode", "browser"}
    gui_allowlist = ["antigravity", "vscode", "browser"]
    profiles = {
        "base": ["git_gh", "node_lts"],
        "line": ["git_gh", "node_lts", "cloudflared"],
        "data": ["git_gh", "node_lts", "docker_desktop"],
        "full": ["git_gh", "node_lts", "cloudflared", "docker_desktop"],
    }

    for tools in catalog["profiles"].values():
        if not isinstance(tools, list):
            raise CatalogError("Invalid profile catalog.")
        seen = set()
        for tool_id in tools:
            if not isinstance(tool_id, str) or tool_id not in all_tools:
                raise CatalogError("Unknown tool ID: " + str(tool_id))
            if tool_id in seen:
                raise CatalogError("Duplicate tool ID: " + tool_id)
            seen.add(tool_id)

    seen_gui = set()
    for tool_id in catalog["gui_tools"]:
        if not isinstance(tool_id, str) or tool_id not in gui_allowlist:
            raise CatalogError("Unknown GUI tool ID: " + str(tool_id))
        if tool_id in seen_gui:
            raise CatalogError("Duplicate GUI tool ID: " + tool_id)
        seen_gui.add(tool_id)

    if catalog.get("node_lts_major") != 24:
        raise CatalogError("Invalid Node LTS major.")
    if set(catalog["profiles"]) != set(profiles):
        raise CatalogError("Invalid profile catalog.")
    for name, expected_tools in profiles.items():
        exact_list(catalog["profiles"][name], expected_tools, "profile " + name)
    exact_list(catalog["gui_tools"], gui_allowlist, "GUI tool catalog")

    profile = sys.argv[2]
    if profile not in catalog["profiles"]:
        raise CatalogError("Unknown profile: " + profile)
    requested_gui = [tool_id for tool_id in re.split(r"[\s,]+", sys.argv[3].strip()) if tool_id]
    if len(requested_gui) != len(set(requested_gui)):
        raise CatalogError("Duplicate GUI tool.")
    for tool_id in requested_gui:
        if tool_id not in catalog["gui_tools"]:
            raise CatalogError("Unknown GUI tool: " + tool_id)
    print("\n".join(catalog["profiles"][profile] + requested_gui))
except (OSError, json.JSONDecodeError, CatalogError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(64)
' "$catalog_path" "$profile" "$gui_tools"
}

install_course_toolchain_macos_docker_desktop() {
  local confirmation="${1:-}"
  if [ -z "$confirmation" ]; then
    printf '%s' 'Docker Desktop will be downloaded, copied to /Applications, and started. Continue? [y/N] ' >&2
    read -r confirmation
  fi
  case "$confirmation" in
    y|Y|yes|YES) install_macos_docker_desktop yes ;;
    *) install_macos_docker_desktop no ;;
  esac
}

install_course_toolchain_macos_gui_tool() {
  local tool_id="$1" confirmation="${2:-}"
  case "$tool_id" in
    antigravity|vscode|browser) ;;
    *) return 64 ;;
  esac
  if [ -z "$confirmation" ]; then
    printf '%s' "$tool_id will be installed only after confirmation. Continue? [y/N] " >&2
    read -r confirmation
  fi
  case "$confirmation" in
    y|Y|yes|YES) install_macos_gui_tool "$tool_id" yes ;;
    *) install_macos_gui_tool "$tool_id" no ;;
  esac
}

render_course_toolchain_macos_readiness_report() {
  render_toolchain_report "$1" "$2" "${3:-}"
}

course_toolchain_macos_support_step() {
  case "$1:$2" in
    git_gh:path|git_gh:network|git_gh:git_install|git_gh:gh_install) printf '%s\n' "$2" ;;
    *) return 64 ;;
  esac
}

new_course_toolchain_macos_safe_diagnostics() {
  local support_step="$1" result_json="$2"
  python3 - "$support_step" "$result_json" <<'PY'
import json
import re
import sys

try:
    result = json.loads(sys.argv[2])
except (TypeError, ValueError):
    result = {}
if not isinstance(result, dict):
    result = {}

def safe_text(value):
    text = "" if value is None else str(value)
    text = re.sub(r"(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b", "[REDACTED]", text)
    text = re.sub(r"(?i)\b(token|password|secret|api[_-]?key)\s*[:=]?\s*\S+", r"\1 [REDACTED]", text)
    return re.sub(r"(?im)(?:[A-Z]:\\Users\\|/(?:Users|home)/)[^\r\n]*", "[USER_PATH]", text)

exit_code = result.get("exit_code")
if isinstance(exit_code, bool) or not isinstance(exit_code, int):
    exit_code = None
error_kind = result.get("error_kind")
if error_kind not in {"path", "network", "git_install", "gh_install", "unknown"}:
    error_kind = "unknown"
print(json.dumps({
    "platform": "macos",
    "step": sys.argv[1],
    "tool_id": result.get("tool_id") if isinstance(result.get("tool_id"), str) else "",
    "found": bool(result.get("found")),
    "version": safe_text(result.get("version")),
    "exit_code": exit_code,
    "error_kind": error_kind,
    "restart_required": bool(result.get("restart_required")),
    "engine_running": bool(result.get("engine_running")),
}, separators=(",", ":")))
PY
}

resolve_course_toolchain_macos_failure() {
  local profile="$1" result_json="$2"
  local fallback_writer="${3:-course_toolchain_macos_local_fallback}"
  local consent_provider="${4:-course_toolchain_macos_support_consent}"
  local support_invoker="${5:-course_toolchain_macos_support_invoke}"
  local tool_id status error_kind support_step safe_message diagnostics support_result support_status support_code

  case "$profile" in base|line|data|full) ;; *) return 64 ;; esac
  tool_id="$(python3 -c 'import json,sys
try: value=json.loads(sys.argv[1]).get("tool_id", "")
except (TypeError,ValueError): value=""
print(value if isinstance(value,str) else "")' "$result_json")"
  status="$(python3 -c 'import json,sys
try: value=json.loads(sys.argv[1]).get("status", "")
except (TypeError,ValueError): value=""
print(value if isinstance(value,str) else "")' "$result_json")"
  case "$profile:$tool_id" in
    base:git_gh|base:node_lts|line:git_gh|line:node_lts|line:cloudflared|data:git_gh|data:node_lts|data:docker_desktop|full:git_gh|full:node_lts|full:cloudflared|full:docker_desktop) ;;
    *) printf '%s\n' '{"status":"not_applicable","support_code":null}'; return 0 ;;
  esac
  [ "$status" = failed ] || { printf '%s\n' '{"status":"not_applicable","support_code":null}'; return 0; }

  safe_message="$(python3 -c 'import json,re,sys
try: value=json.loads(sys.argv[1]).get("safe_message", "")
except (TypeError,ValueError): value=""
text="" if value is None else str(value)
text=re.sub(r"(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b", "[REDACTED]", text)
text=re.sub(r"(?i)\b(token|password|secret|api[_-]?key)\s*[:=]?\s*\S+", r"\1 [REDACTED]", text)
print(re.sub(r"(?im)(?:[A-Z]:\\Users\\|/(?:Users|home)/)[^\r\n]*", "[USER_PATH]", text))' "$result_json")"
  "$fallback_writer" "${safe_message:-本機固定排錯仍未完成。}"

  error_kind="$(python3 -c 'import json,sys
try: value=json.loads(sys.argv[1]).get("error_kind", "")
except (TypeError,ValueError): value=""
print(value if isinstance(value,str) else "")' "$result_json")"
  if ! support_step="$(course_toolchain_macos_support_step "$tool_id" "$error_kind")"; then
    "$fallback_writer" '此工具沒有可安全自動執行的支援動作；請聯絡講師。'
    printf '%s\n' '{"status":"contact_instructor","action_id":"CONTACT_INSTRUCTOR","support_code":null}'
    return 0
  fi
  case "$("$consent_provider")" in y|Y|yes|YES) ;; *) printf '%s\n' '{"status":"declined","support_code":null}'; return 0 ;; esac

  diagnostics="$(new_course_toolchain_macos_safe_diagnostics "$support_step" "$result_json")"
  if ! support_result="$("$support_invoker" "$support_step" "$diagnostics")"; then
    printf '%s\n' '{"status":"fallback","support_code":null}'
    return 0
  fi
  support_status="$(python3 -c 'import json,sys
try: value=json.loads(sys.argv[1]).get("status", "fallback")
except (TypeError,ValueError): value="fallback"
print(value if value in {"local_resolved","resolved","fallback","action_declined","contact","limit","declined"} else "fallback")' "$support_result")"
  support_code="$(python3 -c 'import json,re,sys
try: value=json.loads(sys.argv[1]).get("support_code", "")
except (TypeError,ValueError): value=""
text="" if value is None else str(value)
print(re.sub(r"(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b", "[REDACTED]", text))' "$support_result")"
  python3 -c 'import json,sys; print(json.dumps({"status":sys.argv[1],"support_code":sys.argv[2] or None},separators=(",",":")))' "$support_status" "$support_code"
}

course_toolchain_macos_local_fallback() { printf '%s\n' "$1" >&2; }
course_toolchain_macos_support_consent() { read -r -p '是否使用 AI 安裝助理？(y/N)：' answer; printf '%s' "$answer"; }
course_toolchain_macos_support_invoke() {
  if ! declare -F handle_install_failure >/dev/null; then
    printf '%s\n' '{"status":"fallback"}'
    return 0
  fi
  if handle_install_failure "$1" "$2"; then
    printf '%s\n' '{"status":"resolved"}'
  else
    case "$?" in
      3) printf '%s\n' '{"status":"action_declined"}' ;;
      5) printf '%s\n' '{"status":"limit"}' ;;
      6) printf '%s\n' '{"status":"contact"}' ;;
      *) printf '%s\n' '{"status":"fallback"}' ;;
    esac
  fi
}

course_toolchain_git_gh_state() {
  if ! command -v git >/dev/null 2>&1; then
    macos_json_state git_gh missing
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    macos_json_state git_gh missing
    return 0
  fi
  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    macos_json_state git_gh missing
    return 0
  fi
  macos_json_state git_gh ready
}

read_course_toolchain_profile_input() {
  local raw="$1" trimmed
  trimmed="${raw#"${raw%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  trimmed="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"
  case "$trimmed" in
    base|line|data|full) printf '%s\n' "$trimmed" ;;
    *) return 64 ;;
  esac
}

course_toolchain_free_bytes() {
  if [ -n "${COURSE_TOOLCHAIN_FREE_BYTES_OVERRIDE+x}" ]; then
    printf '%s\n' "$COURSE_TOOLCHAIN_FREE_BYTES_OVERRIDE"
    return 0
  fi
  df -k / 2>/dev/null | awk 'NR==2 {printf "%.0f\n", $4 * 1024}'
}

course_toolchain_tool_action_via_provider() {
  local tool_id="$1" confirmation_provider="$2" git_gh_provider="$3" confirmation
  case "$tool_id" in
    git_gh) "$git_gh_provider"; return $? ;;
    node_lts|cloudflared)
      confirmation="$("$confirmation_provider" "Install $tool_id")"
      install_macos_tool "$tool_id" "$confirmation"
      ;;
    docker_desktop)
      confirmation="$("$confirmation_provider" 'Install Docker Desktop')"
      install_course_toolchain_macos_docker_desktop "$confirmation"
      ;;
    antigravity|vscode|browser)
      confirmation="$("$confirmation_provider" "Install $tool_id")"
      install_course_toolchain_macos_gui_tool "$tool_id" "$confirmation"
      ;;
    *) macos_json_state "$tool_id" failed; return 64 ;;
  esac
}

course_toolchain_prompt_profile() {
  printf '%s' 'Select a profile (base/line/data/full): ' >&2
  read -r REPLY
  printf '%s\n' "$REPLY"
}

course_toolchain_prompt_gui_tools() {
  printf '%s' 'Optional GUI tools, comma separated (antigravity,vscode,browser) or blank: ' >&2
  read -r REPLY
  printf '%s\n' "$REPLY"
}

course_toolchain_prompt_confirmation() {
  local message="$1" answer
  printf '%s' "$message [y/N] " >&2
  read -r answer
  case "$answer" in y|Y|yes|YES) printf 'yes\n' ;; *) printf 'no\n' ;; esac
}

course_toolchain_macos_default_writer() { printf '%s\n' "$1"; }

course_toolchain_macos_default_failure_resolver() {
  resolve_course_toolchain_macos_failure "$1" "$2" >/dev/null
}

print_course_toolchain_macos_report() {
  local report_json="$1"
  python3 - "$report_json" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
print(f"\nCourse toolchain readiness (profile: {report['profile']})")
for tool in report['tools']:
    version = tool.get('version') or '-'
    print(f"  [{tool['requirement']}] {tool['tool_id']} ({version}) - {tool['status']}")
disk = report['disk']
print(f"Disk: {disk['status']} (free={disk['free_bytes']}, required={disk['required_bytes']})")
print(f"Ready: {report['ready']}")
print(f"Next step: {report['next_step']}")
PY
}

start_course_toolchain_installer() {
  local profile_provider="${1:-course_toolchain_prompt_profile}"
  local gui_provider="${2:-course_toolchain_prompt_gui_tools}"
  local confirmation_provider="${3:-course_toolchain_prompt_confirmation}"
  local git_gh_provider="${4:-course_toolchain_git_gh_state}"
  local free_bytes_provider="${5:-course_toolchain_free_bytes}"
  local writer="${6:-course_toolchain_macos_default_writer}"
  local failure_resolver="${7:-course_toolchain_macos_default_failure_resolver}"
  local tool_action_invoker="${8:-course_toolchain_tool_action_via_provider}"

  local profile="" raw_profile
  while [ -z "$profile" ]; do
    raw_profile="$("$profile_provider")"
    if profile="$(read_course_toolchain_profile_input "$raw_profile")"; then
      :
    else
      "$writer" 'Unknown profile. Choose one of: base, line, data, full.'
      profile=""
    fi
  done

  local raw_gui
  raw_gui="$("$gui_provider")"

  local plan_tools tool_id result status results_json='[]'
  plan_tools="$(get_course_toolchain_plan "$profile" "$raw_gui")" || return 64

  while IFS= read -r tool_id; do
    [ -n "$tool_id" ] || continue
    "$writer" "== $tool_id =="
    result="$("$tool_action_invoker" "$tool_id" "$confirmation_provider" "$git_gh_provider")"
    results_json="$(python3 -c '
import json, sys
arr = json.loads(sys.argv[1])
arr.append(json.loads(sys.argv[2]))
print(json.dumps(arr))
' "$results_json" "$result")"

    status="$(python3 -c '
import json, sys
try:
    value = json.loads(sys.argv[1]).get("status", "")
except (TypeError, ValueError):
    value = ""
print(value if isinstance(value, str) else "")
' "$result")"
    if [ "$status" = failed ]; then
      "$failure_resolver" "$profile" "$result"
    fi
    if [ "$tool_id" = git_gh ] && [ "$status" != ready ]; then
      "$writer" 'Git/GitHub 尚未就緒，請先執行 docs/guides/git-and-gh.md 的安裝器，再重新執行本安裝器。'
    fi
  done <<< "$plan_tools"

  local free_bytes report
  free_bytes="$("$free_bytes_provider")"
  report="$(render_toolchain_report "$profile" "$results_json" "$free_bytes")" || return 1
  print_course_toolchain_macos_report "$report"
  printf '%s\n' "$report"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  start_course_toolchain_installer "$@"
fi
