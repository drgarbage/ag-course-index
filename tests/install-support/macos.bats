#!/usr/bin/env bats

setup() {
  INSTALLER="$BATS_TEST_DIRNAME/../../scripts/install-git-gh-macos.command"
  LIBRARY="$BATS_TEST_TMPDIR/install-support-library.sh"
  awk '/^printf .*Git 與 GitHub CLI 課程環境安裝程式/{exit} {print}' "$INSTALLER" > "$LIBRARY"
  # shellcheck disable=SC1090
  source "$LIBRARY"
}

@test "collector redacts macOS homes and truncates stderr" {
  long_error="failed at /Users/alice/project $(printf '%04100d' 0)"
  diagnostics="$(collect_install_diagnostics github_auth "$long_error")"
  run json_field "$diagnostics" stderr
  [ "$status" -eq 0 ]
  [ "${#output}" -le 4000 ]
  [[ "$output" == *'/Users/<USER>/project'* ]]
  [[ "$output" != *'/Users/alice/'* ]]
}

@test "session has no Authorization while diagnosis uses bearer token and timeouts" {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$INSTALL_SUPPORT_CURL_LOG"
case "$*" in
  *'/sessions'*) printf '{"session_id":"is_fake","session_token":"signed-fake","expires_at":"2026-07-19T12:30:00Z"}' ;;
  *) printf '{"action":{"id":"CHECK_GH_VERSION","requires_confirmation":false},"resolved":false}' ;;
esac
STUB
  chmod +x "$STUB_BIN/curl"
  export PATH="$STUB_BIN:$PATH"
  export INSTALL_SUPPORT_CURL_LOG="$BATS_TEST_TMPDIR/curl.log"

  session_json="$(new_install_support_session 1.0.0)"
  session_id="$(json_field "$session_json" session_id)"
  session_token="$(json_field "$session_json" session_token)"
  run invoke_install_diagnosis "$session_id" "$session_token" github_auth 1 '{}'
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$INSTALL_SUPPORT_CURL_LOG" | tr -d ' ')" -eq 2 ]
  first_call="$(sed -n '1p' "$INSTALL_SUPPORT_CURL_LOG")"
  second_call="$(sed -n '2p' "$INSTALL_SUPPORT_CURL_LOG")"
  [[ "$first_call" == *'--connect-timeout 5'* ]]
  [[ "$first_call" == *'--max-time 20'* ]]
  [[ "$first_call" != *'Authorization:'* ]]
  [[ "$second_call" == *'Authorization: Bearer signed-fake'* ]]
}

@test "unknown action never executes response command" {
  export INSTALL_SUPPORT_COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
  run run_allowlisted_action RUN_ARBITRARY_COMMAND yes
  [ "$status" -eq 64 ]
  [ ! -e "$INSTALL_SUPPORT_COMMAND_LOG" ]
}

@test "medium action requires exact confirmation" {
  export INSTALL_SUPPORT_COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
  run run_allowlisted_action INSTALL_GH_MACOS no
  [ "$status" -eq 2 ]
  [ ! -e "$INSTALL_SUPPORT_COMMAND_LOG" ]
}

@test "read-only action maps to fixed argv" {
  install_support_run_command() {
    printf '%s|' "$1" >> "$INSTALL_SUPPORT_COMMAND_LOG"
    shift
    printf '%s\n' "$*" >> "$INSTALL_SUPPORT_COMMAND_LOG"
    printf 'gh version fake'
  }
  export -f install_support_run_command
  export INSTALL_SUPPORT_COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"

  run run_allowlisted_action CHECK_GH_VERSION no
  [ "$status" -eq 0 ]
  [ "$(cat "$INSTALL_SUPPORT_COMMAND_LOG")" = 'gh|--version' ]
  [ "$output" = 'gh version fake' ]
}

@test "script contains no eval" {
  run grep -E '(^|[;&|[:space:]])eval([;&|[:space:]]|$)' "$INSTALLER"
  [ "$status" -eq 1 ]
}

@test "declining optional AI creates no session" {
  install_support_consent() { printf 'no'; }
  new_install_support_session() { touch "$INSTALL_SUPPORT_SESSION_LOG"; }
  export -f install_support_consent new_install_support_session
  export INSTALL_SUPPORT_SESSION_LOG="$BATS_TEST_TMPDIR/session.log"

  run handle_install_failure github_auth '{}'
  [ "$status" -eq 3 ]
  [ ! -e "$INSTALL_SUPPORT_SESSION_LOG" ]
}

@test "existing static failure handler offers optional AI recovery" {
  run awk '/^fail\(\)/,/^}/' "$INSTALLER"
  [ "$status" -eq 0 ]
  [[ "$output" == *'handle_install_failure'* ]]
}

@test "offline API keeps the static fallback" {
  install_support_consent() { printf 'yes'; }
  new_install_support_session() { return 7; }
  export -f install_support_consent new_install_support_session

  run handle_install_failure github_auth '{}'
  [ "$status" -eq 4 ]
  [[ "$output" == *'原本的靜態排錯說明仍然有效'* ]]
}

@test "AI recovery stops after fifteen diagnosis requests" {
  install_support_consent() { printf 'yes'; }
  new_install_support_session() { printf '{"session_id":"is_fake","session_token":"signed-fake"}'; }
  invoke_install_diagnosis() {
    printf 'call\n' >> "$INSTALL_SUPPORT_DIAGNOSIS_LOG"
    printf '{"action":{"id":"CHECK_GH_VERSION","requires_confirmation":false},"resolved":false,"support_code":"SUP-LIMIT2"}'
  }
  run_allowlisted_action() { return 1; }
  export -f install_support_consent new_install_support_session invoke_install_diagnosis run_allowlisted_action
  export INSTALL_SUPPORT_DIAGNOSIS_LOG="$BATS_TEST_TMPDIR/diagnosis.log"

  run handle_install_failure github_auth '{}'
  [ "$status" -eq 5 ]
  [ "$(wc -l < "$INSTALL_SUPPORT_DIAGNOSIS_LOG" | tr -d ' ')" -eq 15 ]
  [[ "$output" == *'SUP-LIMIT2'* ]]
}
