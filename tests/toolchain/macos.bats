#!/usr/bin/env bats

setup() {
  PLANNER="$BATS_TEST_DIRNAME/../../scripts/course-toolchain-macos.command"
  MODULE="$BATS_TEST_DIRNAME/../../scripts/toolchain/macos.sh"
  REPORT="$BATS_TEST_DIRNAME/../../scripts/toolchain/report.sh"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/macos-tools.json"
  DOCKER_FIXTURE="$BATS_TEST_DIRNAME/fixtures/docker-macos.json"
  # shellcheck disable=SC1090
  source "$PLANNER"
  source "$REPORT"
}

@test "GUI tools are not part of a profile unless explicitly selected" {
  run get_course_toolchain_plan full ''
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\nvscode'* ]]
}

@test "macOS GUI installer requires confirmation" {
  load_macos_module
  run install_macos_gui_tool vscode no
  [ "$status" -eq 2 ]
  [[ "$output" == *'"status":"skipped"'* ]]
}

@test "readiness report is unready when a required tool fails" {
  run render_toolchain_report line '[{"tool_id":"cloudflared","status":"failed"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":false'* ]]
}

@test "readiness report redacts tokens and personal paths" {
  run render_toolchain_report base '[{"tool_id":"git_gh","status":"failed","safe_message":"token ghp_fake at /Users/Alice Smith/Desktop/secret.txt"}]'
  [ "$status" -eq 0 ]
  [[ "$output" != *ghp_fake* ]]
  [[ "$output" != *Alice* ]]
  [[ "$output" != *Smith* ]]
}

@test "readiness report normalizes ready and marks a complete base profile ready" {
  run render_toolchain_report base '[{"tool_id":"git_gh","status":"ready","version":"2.76.0"},{"tool_id":"node_lts","status":"updated","version":"v24.4.0"}]' 2147483648
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *'"status":"installed"'* ]]
  [[ "$output" == *'"disk":{"free_bytes":2147483648,"required_bytes":2147483648,"status":"enough"}'* ]]
}

@test "readiness report uses the restart next step" {
  run render_toolchain_report base '[{"tool_id":"git_gh","status":"installed"},{"tool_id":"node_lts","status":"needs_restart"}]' 2147483648
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *'"restart_required":true'* ]]
  [[ "$output" == *'"next_step":"請重新啟動電腦後重新執行 readiness report。"'* ]]
}

@test "readiness report blocks readiness when free disk is insufficient" {
  run render_toolchain_report base '[{"tool_id":"git_gh","status":"installed"},{"tool_id":"node_lts","status":"installed"}]' 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *'"status":"insufficient"'* ]]
  [[ "$output" == *'"next_step":"可用磁碟空間不足；請釋放空間後重新執行 readiness report。"'* ]]
}

@test "readiness report leaves disk unknown without injected free bytes" {
  run render_toolchain_report base '[]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"disk":{"free_bytes":null,"required_bytes":2147483648,"status":"unknown"}'* ]]
}

@test "readiness report treats malformed injected free bytes as unknown" {
  run render_toolchain_report base '[]' not-a-number
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"unknown"'* ]]
}

@test "readiness report uses fixed required bytes for every profile" {
  run bash -c 'source "$1"; render_toolchain_report base "[]"; render_toolchain_report line "[]"; render_toolchain_report data "[]"; render_toolchain_report full "[]"' _ "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"required_bytes":2147483648'* ]]
  [[ "$output" == *'"required_bytes":3221225472'* ]]
  [[ "$output" == *'"required_bytes":12884901888'* ]]
  [[ "$output" == *'"required_bytes":13958643712'* ]]
}

@test "readiness report preserves canonical statuses and maps ready" {
  run render_toolchain_report base '[{"tool_id":"git_gh","status":"ready"},{"tool_id":"node_lts","status":"updated"},{"tool_id":"antigravity","status":"needs_restart"},{"tool_id":"browser","status":"failed"},{"tool_id":"vscode","status":"skipped"}]'
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; print(",".join(tool["status"] for tool in json.loads(sys.argv[1])["tools"]))' "$output"
  [ "$status" -eq 0 ]
  [ "$output" = 'installed,updated,needs_restart,failed,skipped' ]
}

@test "readiness report rejects mixed-case statuses" {
  run render_toolchain_report base '[{"tool_id":"git_gh","status":"INSTALLED"},{"tool_id":"node_lts","status":"READY"}]'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -o '"status":"failed"' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "readiness report rejects uppercase profiles and ignores uppercase result tool IDs" {
  run render_toolchain_report BASE '[]'
  [ "$status" -eq 64 ]

  run render_toolchain_report base '[{"tool_id":"GIT_GH","status":"installed"},{"tool_id":"node_lts","status":"installed"}]'
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; print(",".join(tool["status"] for tool in json.loads(sys.argv[1])["tools"]))' "$output"
  [ "$status" -eq 0 ]
  [ "$output" = 'failed,installed' ]
}

@test "readiness report redacts quoted macOS profile names through the safe line" {
  run render_toolchain_report base "[{\"tool_id\":\"git_gh\",\"status\":\"failed\",\"safe_message\":\"at /Users/O'Connor/Desktop/secret.txt suffix O'Connor\"}]"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"safe_message":"at [USER_PATH]"'* ]]
  [[ "$output" != *Connor* ]]

  run render_toolchain_report base '[{"tool_id":"git_gh","status":"failed","safe_message":"at /Users/A\"B/Desktop/secret.txt suffix A\"B"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"safe_message":"at [USER_PATH]"'* ]]
  [[ "$output" != *'A\"B'* ]]
}

@test "course wrapper forwards injected free bytes" {
  run render_course_toolchain_macos_readiness_report base '[{"tool_id":"git_gh","status":"installed"},{"tool_id":"node_lts","status":"installed"}]' 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'"free_bytes":1'* ]]
  [[ "$output" == *'"status":"insufficient"'* ]]
}

@test "readiness report fails closed for non-string tool IDs and statuses" {
  run render_toolchain_report base '[{"tool_id":["git_gh"],"status":"ready"},{"tool_id":"node_lts","status":{"value":"ready"}}]'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -o '"status":"failed"' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "macOS GUI catalog uses all fixed casks" {
  run bash -c 'source "$1"; macos_gui_cask antigravity; macos_gui_cask vscode; macos_gui_cask browser' _ "$MODULE"
  [ "$status" -eq 0 ]
  [ "$output" = $'antigravity\nvisual-studio-code\ngoogle-chrome' ]
}

@test "macOS accepts either Chrome or Edge as browser ready" {
  load_macos_module
  MACOS_CHROME_APP_PATH="$BATS_TEST_TMPDIR/Google Chrome.app"
  MACOS_EDGE_APP_PATH="$BATS_TEST_TMPDIR/Microsoft Edge.app"
  mkdir -p "$MACOS_EDGE_APP_PATH"
  run macos_gui_ready browser
  [ "$status" -eq 0 ]
}

load_macos_module() {
  # shellcheck disable=SC1090
  source "$MODULE"
}

@test "full expands fixed tools and excludes GUI by default" {
  run get_course_toolchain_plan full ''
  [ "$status" -eq 0 ]
  [ "$output" = $'git_gh\nnode_lts\ncloudflared\ndocker_desktop' ]
}

@test "selected GUI tools are appended to the profile plan" {
  run get_course_toolchain_plan base 'vscode,browser'
  [ "$status" -eq 0 ]
  [ "$output" = $'git_gh\nnode_lts\nvscode\nbrowser' ]
}

@test "unknown profile is rejected" {
  run get_course_toolchain_plan evil ''
  [ "$status" -eq 64 ]
}

@test "uppercase profile and selected GUI identifiers are rejected" {
  run get_course_toolchain_plan BASE ''
  [ "$status" -eq 64 ]
  run get_course_toolchain_plan base VSCODE
  [ "$status" -eq 64 ]
}

@test "invalid catalog schema is rejected before planning" {
  invalid_catalog="$BATS_TEST_TMPDIR/unsupported-schema.json"
  printf '%s' '{"schema_version":2}' > "$invalid_catalog"

  run env COURSE_TOOLCHAIN_CATALOG="$invalid_catalog" bash -c 'source "$1"; get_course_toolchain_plan full ""' _ "$PLANNER"
  [ "$status" -eq 64 ]
}

@test "catalog tool IDs outside the allowlist are rejected" {
  invalid_catalog="$BATS_TEST_TMPDIR/unknown-tool.json"
  printf '%s' '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["evil"]},"gui_tools":["antigravity","vscode","browser"]}' > "$invalid_catalog"

  run env COURSE_TOOLCHAIN_CATALOG="$invalid_catalog" bash -c 'source "$1"; get_course_toolchain_plan base ""' _ "$PLANNER"
  [ "$status" -eq 64 ]
}

@test "uppercase catalog tool ID is rejected" {
  invalid_catalog="$BATS_TEST_TMPDIR/uppercase-tool.json"
  printf '%s' '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["GIT_GH","node_lts"],"line":["git_gh","node_lts","cloudflared"],"data":["git_gh","node_lts","docker_desktop"],"full":["git_gh","node_lts","cloudflared","docker_desktop"]},"gui_tools":["antigravity","vscode","browser"]}' > "$invalid_catalog"

  run env COURSE_TOOLCHAIN_CATALOG="$invalid_catalog" bash -c 'source "$1"; get_course_toolchain_plan base ""' _ "$PLANNER"
  [ "$status" -eq 64 ]
}

@test "duplicate catalog tool IDs are rejected" {
  invalid_catalog="$BATS_TEST_TMPDIR/duplicate-tool.json"
  printf '%s' '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["git_gh","git_gh"]},"gui_tools":["antigravity","vscode","browser"]}' > "$invalid_catalog"

  run env COURSE_TOOLCHAIN_CATALOG="$invalid_catalog" bash -c 'source "$1"; get_course_toolchain_plan base ""' _ "$PLANNER"
  [ "$status" -eq 64 ]
}

@test "GUI tool IDs outside the allowlist are rejected" {
  invalid_catalog="$BATS_TEST_TMPDIR/unknown-gui.json"
  printf '%s' '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["git_gh","node_lts"]},"gui_tools":["antigravity","vscode","evil"]}' > "$invalid_catalog"

  run env COURSE_TOOLCHAIN_CATALOG="$invalid_catalog" bash -c 'source "$1"; get_course_toolchain_plan base ""' _ "$PLANNER"
  [ "$status" -eq 64 ]
}

@test "existing compliant node is ready" {
  load_macos_module
  export TOOLCHAIN_NODE_VERSION=v24.4.0
  run get_macos_tool_state node_lts
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ready"'* ]]
}

@test "node below the local minimum is outdated" {
  load_macos_module
  export TOOLCHAIN_NODE_VERSION=v24.3.9
  run get_macos_tool_state node_lts
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"outdated"'* ]]
}

@test "no Homebrew does not bootstrap Homebrew" {
  load_macos_module
  export TOOLCHAIN_HAS_BREW=false
  run install_macos_tool cloudflared no
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/brew-install.log" ]
}

@test "unsupported architecture fails before download" {
  load_macos_module
  export TOOLCHAIN_ARCH=sparc
  run install_macos_tool node_lts yes
  [ "$status" -eq 65 ]
  [ ! -e "$BATS_TEST_TMPDIR/download.log" ]
}

@test "Homebrew installation uses the fixed Node formula" {
  load_macos_module
  stub_bin="$BATS_TEST_TMPDIR/brew-bin"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/brew" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TOOLCHAIN_BREW_LOG"
case "$1" in
  --version) exit 0 ;;
  install) exit 0 ;;
esac
exit 64
STUB
  chmod +x "$stub_bin/brew"
  export PATH="$stub_bin:$PATH"
  export TOOLCHAIN_HAS_BREW=true
  export TOOLCHAIN_NODE_VERSION=missing
  export TOOLCHAIN_BREW_LOG="$BATS_TEST_TMPDIR/brew-install.log"

  run install_macos_tool node_lts yes
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$TOOLCHAIN_BREW_LOG")" = '--version' ]
  [ "$(sed -n '2p' "$TOOLCHAIN_BREW_LOG")" = 'install node@24' ]
  [[ "$output" == *'"status":"needs_restart"'* ]]
}

@test "Homebrew node install does not fail when PATH still resolves an outdated Node" {
  load_macos_module
  stub_bin="$BATS_TEST_TMPDIR/brew-old-node-bin"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/brew" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TOOLCHAIN_BREW_LOG"
case "$1" in
  --version|install) exit 0 ;;
esac
exit 64
STUB
  chmod +x "$stub_bin/brew"
  export PATH="$stub_bin:$PATH"
  export TOOLCHAIN_HAS_BREW=true
  export TOOLCHAIN_NODE_VERSION=v24.3.9
  export TOOLCHAIN_BREW_LOG="$BATS_TEST_TMPDIR/brew-old-node.log"

  run install_macos_tool node_lts yes
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$TOOLCHAIN_BREW_LOG")" = 'install node@24' ]
  [[ "$output" == *'"status":"needs_restart"'* ]]
}

@test "vendor cleanup trap removes its temporary directory after an unexpected exit" {
  load_macos_module
  export TOOLCHAIN_VENDOR_TEST_DIR="$BATS_TEST_TMPDIR/vendor-temporary"
  mkdir -p "$TOOLCHAIN_VENDOR_TEST_DIR"
  mktemp() { printf '%s\n' "$TOOLCHAIN_VENDOR_TEST_DIR"; }
  curl() { exit 91; }

  set +e
  (macos_vendor_install cloudflared arm64)
  status=$?
  set -e
  [ "$status" -eq 91 ]
  [ ! -e "$TOOLCHAIN_VENDOR_TEST_DIR" ]
}

@test "vendor fallback has fixed architecture URLs and checksums" {
  load_macos_module
  fixture="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["node_lts"]["vendor"]["arm64"]["url"])' "$FIXTURE")"
  [ "$fixture" = 'https://nodejs.org/download/release/v24.4.0/node-v24.4.0.pkg' ]
  [ "$(macos_vendor_url node_lts arm64)" = "$fixture" ]
  [ "$(macos_vendor_sha256 node_lts arm64)" = 'bff7a6239d9c5a809f4fe4e8585144ccc930533d88f8ef2935afa0d5aa86c244' ]
  [ "$(macos_vendor_url cloudflared x86_64)" = 'https://github.com/cloudflare/cloudflared/releases/download/2025.6.1/cloudflared-amd64.pkg' ]
  [ "$(macos_vendor_sha256 cloudflared x86_64)" = '7f12892073506438fabab6f9fc075332f4f57e1ed30ba8c1ddf71f86f743a63f' ]
}

@test "vendor checksum sources are fixed HTTPS endpoints" {
  load_macos_module
  [ "$(macos_vendor_checksum_source node_lts)" = 'https://nodejs.org/download/release/v24.4.0/SHASUMS256.txt' ]
  [ "$(macos_vendor_checksum_source cloudflared)" = 'https://github.com/cloudflare/cloudflared/releases/tag/2025.6.1' ]
}

@test "vendor URL injection cannot change the fixed download allowlist" {
  load_macos_module
  export TOOLCHAIN_DOWNLOAD_URL='https://example.invalid/evil.pkg'
  [ "$(macos_vendor_url cloudflared arm64)" = 'https://github.com/cloudflare/cloudflared/releases/download/2025.6.1/cloudflared-arm64.pkg' ]
}

@test "Docker architecture selects only the matching official artifact" {
  load_macos_module
  export TOOLCHAIN_ARCH=arm64 TOOLCHAIN_DOCKER_FIXTURE="$DOCKER_FIXTURE"
  expected_filename="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["arm64"]["filename"])' "$TOOLCHAIN_DOCKER_FIXTURE")"
  expected_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["arm64"]["url"])' "$TOOLCHAIN_DOCKER_FIXTURE")"
  expected_sha256="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["arm64"]["sha256"])' "$TOOLCHAIN_DOCKER_FIXTURE")"

  run docker_macos_artifact

  [ "$status" -eq 0 ]
  [ "$output" = "$expected_filename" ]
  [[ "$output" != *'Docker-Intel.dmg'* ]]
  [ "$(macos_docker_download_url arm64)" = "$expected_url" ]
  [ "$(macos_docker_sha256 arm64)" = "$expected_sha256" ]
}

@test "Intel Docker architecture selects only the matching official artifact" {
  load_macos_module
  export TOOLCHAIN_ARCH=x86_64 TOOLCHAIN_DOCKER_FIXTURE="$DOCKER_FIXTURE"
  expected_filename="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["x86_64"]["filename"])' "$TOOLCHAIN_DOCKER_FIXTURE")"
  expected_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["x86_64"]["url"])' "$TOOLCHAIN_DOCKER_FIXTURE")"
  expected_sha256="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["x86_64"]["sha256"])' "$TOOLCHAIN_DOCKER_FIXTURE")"

  run docker_macos_artifact

  [ "$status" -eq 0 ]
  [ "$output" = "$expected_filename" ]
  [[ "$output" != *'Docker-AppleSilicon.dmg'* ]]
  [ "$(macos_docker_download_url x86_64)" = "$expected_url" ]
  [ "$(macos_docker_sha256 x86_64)" = "$expected_sha256" ]
}

@test "Docker install requires confirmation" {
  load_macos_module

  run install_macos_docker_desktop no

  [ "$status" -eq 2 ]
  [[ "$output" == *'"tool_id":"docker_desktop"'* ]]
  [[ "$output" == *'"status":"skipped"'* ]]
}

@test "legacy docker-compose does not satisfy readiness" {
  load_macos_module
  stub_bin="$BATS_TEST_TMPDIR/docker-legacy-bin"
  mkdir -p "$stub_bin"
  printf '%s\n' '#!/bin/bash' 'case "$*" in version) exit 0 ;; "compose version") exit 1 ;; *) exit 64 ;; esac' > "$stub_bin/docker"
  printf '%s\n' '#!/bin/bash' 'exit 0' > "$stub_bin/docker-compose"
  chmod +x "$stub_bin/docker" "$stub_bin/docker-compose"
  export PATH="$stub_bin:$PATH"

  run verify_macos_docker

  [ "$status" -ne 0 ]
  [[ "$output" != *'command not found'* ]]
}

@test "Docker readiness verifies Docker Engine and Compose v2 only" {
  load_macos_module
  stub_bin="$BATS_TEST_TMPDIR/docker-ready-bin"
  mkdir -p "$stub_bin"
  export TOOLCHAIN_DOCKER_LOG="$BATS_TEST_TMPDIR/docker-commands.log"
  printf '%s\n' '#!/bin/bash' 'printf '\''%s\n'\'' "$*" >> "$TOOLCHAIN_DOCKER_LOG"' 'case "$*" in version|"compose version") exit 0 ;; *) exit 64 ;; esac' > "$stub_bin/docker"
  chmod +x "$stub_bin/docker"
  export PATH="$stub_bin:$PATH"

  run verify_macos_docker

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$TOOLCHAIN_DOCKER_LOG")" = 'version' ]
  [ "$(sed -n '2p' "$TOOLCHAIN_DOCKER_LOG")" = 'compose version' ]
  [ "$(wc -l < "$TOOLCHAIN_DOCKER_LOG" | tr -d ' ')" -eq 2 ]
}

@test "Docker readiness timeout is bounded and truthful" {
  load_macos_module
  verify_macos_docker() { return 1; }

  run wait_macos_docker_ready 1

  [ "$status" -ne 0 ]
  [[ "$output" == *'"status":"failed"'* ]]
}

@test "Docker readiness clamps a timeout above two minutes" {
  load_macos_module

  run macos_docker_timeout_seconds 121

  [ "$status" -eq 0 ]
  [ "$output" = 120 ]
}

@test "Docker readiness interrupts a probe at the remaining deadline" {
  load_macos_module
  stub_bin="$BATS_TEST_TMPDIR/docker-blocking-bin"
  mkdir -p "$stub_bin"
  printf '%s\n' '#!/bin/bash' 'sleep 2' 'exit 1' > "$stub_bin/docker"
  chmod +x "$stub_bin/docker"
  export PATH="$stub_bin:$PATH"
  started_at="$(python3 -c 'import time; print(time.monotonic())')"

  run wait_macos_docker_ready 1

  finished_at="$(python3 -c 'import time; print(time.monotonic())')"
  elapsed="$(python3 -c 'import sys; print(float(sys.argv[2]) - float(sys.argv[1]))' "$started_at" "$finished_at")"
  [ "$status" -ne 0 ]
  [[ "$output" == *'"status":"failed"'* ]]
  [ "$(python3 -c 'import sys; print(float(sys.argv[1]) <= 1.5)' "$elapsed")" = True ]
}

@test "macOS Docker native commands use fixed executables and argv" {
  run python3 -c 'import sys
source = open(sys.argv[1], encoding="utf-8").read().replace(chr(39), "")
required = [
    "/usr/bin/curl --fail --location --proto =https --tlsv1.2 --output",
    "/usr/bin/shasum -a 256 -c -",
    "/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint",
    "/usr/bin/hdiutil detach",
    "/usr/bin/sudo /usr/bin/ditto",
    "/usr/bin/open \"$MACOS_DOCKER_DESKTOP_APP_PATH\"",
]
assert all(item in source for item in required)' "$MODULE"

  [ "$status" -eq 0 ]
}

@test "macOS Docker installer has no legacy Compose, login, or forced reboot commands" {
  run grep -Eiq '(^|[^[:alnum:]_-])docker-compose([^[:alnum:]_-]|$)|docker[[:space:]]+login|restart[[:space:]_-]*(computer|mac)|shutdown' "$MODULE"

  [ "$status" -eq 1 ]
}
