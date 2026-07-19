#!/usr/bin/env bats

setup() {
  PLANNER="$BATS_TEST_DIRNAME/../../scripts/course-toolchain-macos.command"
  MODULE="$BATS_TEST_DIRNAME/../../scripts/toolchain/macos.sh"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/macos-tools.json"
  # shellcheck disable=SC1090
  source "$PLANNER"
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
