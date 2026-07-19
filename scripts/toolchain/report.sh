#!/bin/bash

render_toolchain_report() {
  local profile="$1" results_json="$2"
  python3 - "$profile" "$results_json" <<'PY'
import json
import re
import sys

PROFILES = {
    "base": ["git_gh", "node_lts"],
    "line": ["git_gh", "node_lts", "cloudflared"],
    "data": ["git_gh", "node_lts", "docker_desktop"],
    "full": ["git_gh", "node_lts", "cloudflared", "docker_desktop"],
}
GUI_TOOLS = ("antigravity", "vscode", "browser")
STATUSES = {"installed", "updated", "skipped", "needs_restart", "failed"}

def safe_text(value):
    text = "" if value is None else str(value)
    text = re.sub(r"(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b", "[REDACTED]", text)
    text = re.sub(r"(?i)\b(token|password|secret|api[_-]?key)\s*[:=]?\s*\S+", r"\1 [REDACTED]", text)
    text = re.sub(r"(?i)[A-Z]:\\Users\\[^\\\s]+", "[USER_PATH]", text)
    return re.sub(r"(?i)/(?:Users|home)/[^/\s]+", "[USER_PATH]", text)

profile = sys.argv[1]
if profile not in PROFILES:
    sys.exit(64)
try:
    results = json.loads(sys.argv[2])
except json.JSONDecodeError:
    sys.exit(64)
if not isinstance(results, list):
    sys.exit(64)

known_tools = set(PROFILES[profile]) | set(GUI_TOOLS)
by_tool = {}
for result in results:
    if not isinstance(result, dict):
        continue
    tool_id = result.get("tool_id")
    if tool_id in known_tools and tool_id not in by_tool:
        by_tool[tool_id] = result

tools = []
for tool_id in PROFILES[profile] + sorted(tool for tool in GUI_TOOLS if tool in by_tool):
    result = by_tool.get(tool_id)
    status = "failed" if result is None else result.get("status")
    if status not in STATUSES:
        status = "failed"
    version = ""
    message = "未取得工具結果。" if result is None else result.get("safe_message", "")
    if result is not None:
        for field in ("installed_version", "detected_version", "version"):
            if result.get(field) not in (None, ""):
                version = result[field]
                break
    tools.append({
        "tool_id": tool_id,
        "requirement": "required" if tool_id in PROFILES[profile] else "optional",
        "version": safe_text(version),
        "status": status,
        "needs_restart": status == "needs_restart",
        "safe_message": safe_text(message),
    })

required = [tool for tool in tools if tool["requirement"] == "required"]
ready = all(tool["status"] in {"installed", "updated"} for tool in required)
restart_required = any(tool["needs_restart"] for tool in tools)
next_step = (
    "請依報告中的固定安裝流程重試；仍失敗請聯絡講師。" if not ready else
    "請重新啟動電腦後重新執行 readiness report。" if restart_required else
    "課程工具鏈已就緒；依課程指引開啟專案。"
)
print(json.dumps({
    "profile": profile,
    "ready": ready,
    "disk": "not_assessed",
    "restart_required": restart_required,
    "next_step": next_step,
    "tools": tools,
}, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
PY
}
