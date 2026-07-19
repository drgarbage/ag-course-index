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
  render_toolchain_report "$1" "$2"
}
