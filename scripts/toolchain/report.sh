#!/bin/bash

render_toolchain_report() {
  local profile="$1" results_json="$2" free_bytes="${3:-}"
  python3 - "$profile" "$results_json" "$free_bytes" <<'PY'
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
REQUIRED_BYTES = {
    "base": 2147483648,
    "line": 3221225472,
    "data": 12884901888,
    "full": 13958643712,
}

def safe_text(value):
    text = "" if value is None else str(value)
    text = re.sub(r"(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b", "[REDACTED]", text)
    text = re.sub(r"(?i)\b(token|password|secret|api[_-]?key)\s*[:=]?\s*\S+", r"\1 [REDACTED]", text)
    text = re.sub(r'''(?i)[A-Z]:\\Users\\[^\r\n"']+''', "[USER_PATH]", text)
    return re.sub(r'''(?i)/(?:Users|home)/[^\r\n"']+''', "[USER_PATH]", text)

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
    if not isinstance(tool_id, str):
        continue
    if tool_id in known_tools and tool_id not in by_tool:
        by_tool[tool_id] = result

tools = []
for tool_id in PROFILES[profile] + sorted(tool for tool in GUI_TOOLS if tool in by_tool):
    result = by_tool.get(tool_id)
    status = "failed" if result is None else result.get("status")
    if not isinstance(status, str):
        status = "failed"
    if status == "ready":
        status = "installed"
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
required_bytes = REQUIRED_BYTES[profile]
try:
    free_bytes = int(sys.argv[3]) if sys.argv[3] else None
except ValueError:
    free_bytes = None
if free_bytes is not None and not 0 <= free_bytes <= 9223372036854775807:
    free_bytes = None
disk_status = "unknown" if free_bytes is None else "enough" if free_bytes >= required_bytes else "insufficient"
tools_ready = all(tool["status"] in {"installed", "updated"} for tool in required)
ready = tools_ready and disk_status != "insufficient"
restart_required = any(tool["needs_restart"] for tool in tools)
next_step = (
    "可用磁碟空間不足；請釋放空間後重新執行 readiness report。" if disk_status == "insufficient" else
    "請重新啟動電腦後重新執行 readiness report。" if restart_required else
    "請依報告中的固定安裝流程重試；仍失敗請聯絡講師。" if not ready else
    "課程工具鏈已就緒；依課程指引開啟專案。"
)
print(json.dumps({
    "profile": profile,
    "ready": ready,
    "disk": {"free_bytes": free_bytes, "required_bytes": required_bytes, "status": disk_status},
    "restart_required": restart_required,
    "next_step": next_step,
    "tools": tools,
}, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
PY
}
