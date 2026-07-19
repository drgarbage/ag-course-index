#!/usr/bin/env bats

setup() {
  INSTALLER="$BATS_TEST_DIRNAME/../../scripts/install-git-gh-macos.command"
  LIBRARY="$BATS_TEST_TMPDIR/install-support-library.sh"
  awk '/^printf .*Git 與 GitHub CLI 課程環境安裝程式/{exit} {print}' "$INSTALLER" > "$LIBRARY"
  # shellcheck disable=SC1090
  source "$LIBRARY"
}

fake_local_provider() { printf '%s' "$FAKE_LOCAL_RESULT"; }
fake_consent_provider() { printf '%s' "$FAKE_CONSENT"; }
fake_session_provider() { printf '%s' "$FAKE_SESSION"; }
fake_diagnosis_provider() {
  printf '%s' "$6" > "$INSTALL_SUPPORT_PREVIOUS_LOG"
  printf '%s' "$FAKE_DIAGNOSIS"
}
fake_confirmation_provider() {
  touch "$INSTALL_SUPPORT_CONFIRMATION_LOG"
  printf '%s' "$FAKE_CONFIRMATION"
}
forbidden_consent_provider() { touch "$INSTALL_SUPPORT_CONSENT_LOG"; }
forbidden_session_provider() { touch "$INSTALL_SUPPORT_SESSION_LOG"; }

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

@test "static failure handler uses a backend-allowlisted default step" {
  run grep -F 'final_verification' "$INSTALLER"
  [ "$status" -eq 1 ]
}

@test "localized backend contract fields are displayed" {
  export FAKE_LOCAL_RESULT='{"matched":false}'
  export FAKE_CONSENT=yes
  export FAKE_SESSION='{"session_id":"is_fake","session_token":"signed-fake"}'
  export FAKE_DIAGNOSIS='{"summary_zh_tw":"繁中摘要","explanation_zh_tw":"繁中說明","action":{"id":"CONTACT_INSTRUCTOR","title_zh_tw":"聯絡講師","impact_zh_tw":"提供支援碼","requires_confirmation":false},"resolved":false,"support_code":"SUP-CONTRACT"}'
  export INSTALL_SUPPORT_PREVIOUS_LOG="$BATS_TEST_TMPDIR/previous.json"
  run handle_install_failure network '{}' fake_local_provider fake_consent_provider fake_session_provider fake_diagnosis_provider
  [ "$status" -eq 6 ]
  [[ "$output" == *'繁中摘要'* ]]
  [[ "$output" == *'繁中說明'* ]]
  [[ "$output" == *'聯絡講師'* ]]
  [[ "$output" == *'提供支援碼'* ]]
}

@test "stale credential action never deletes a keychain item automatically" {
  run awk '/CLEAR_STALE_GITHUB_CREDENTIAL_MACOS\)/{print; exit}' "$INSTALLER"
  [ "$status" -eq 0 ]
  [[ "$output" != *'security delete-'* ]]
  install_support_run_command() { return 0; }
  run run_allowlisted_action CLEAR_STALE_GITHUB_CREDENTIAL_MACOS yes
  [ "$status" -eq 3 ]
}

@test "macOS uses local confirmation policy when backend says false" {
  export FAKE_LOCAL_RESULT='{"matched":false}' FAKE_CONSENT=yes
  export FAKE_SESSION='{"session_id":"is_fake","session_token":"signed-fake"}'
  export FAKE_DIAGNOSIS='{"action":{"id":"INSTALL_GH_MACOS","requires_confirmation":false},"resolved":false,"support_code":"SUP-SAFE02"}'
  export FAKE_CONFIRMATION=no INSTALL_SUPPORT_CONFIRMATION_LOG="$BATS_TEST_TMPDIR/confirmation.log"
  export INSTALL_SUPPORT_PREVIOUS_LOG="$BATS_TEST_TMPDIR/previous.json"
  run handle_install_failure gh_install '{}' fake_local_provider fake_consent_provider fake_session_provider fake_diagnosis_provider fake_confirmation_provider
  [ "$status" -eq 3 ]
  [ -f "$INSTALL_SUPPORT_CONFIRMATION_LOG" ]
}

@test "macOS rejects string resolved values" {
  export FAKE_LOCAL_RESULT='{"matched":false}' FAKE_CONSENT=yes
  export FAKE_SESSION='{"session_id":"is_fake","session_token":"signed-fake"}'
  export FAKE_DIAGNOSIS='{"action":{"id":"CONTACT_INSTRUCTOR","requires_confirmation":false},"resolved":"true","support_code":"SUP-BADBOOL"}'
  export INSTALL_SUPPORT_PREVIOUS_LOG="$BATS_TEST_TMPDIR/previous.json"
  run handle_install_failure network '{}' fake_local_provider fake_consent_provider fake_session_provider fake_diagnosis_provider
  [ "$status" -eq 4 ]
}

@test "collector emits blocked Raw GitHub enum without response body" {
  STUB_BIN="$BATS_TEST_TMPDIR/raw-bin"
  mkdir -p "$STUB_BIN"
  printf '#!/bin/bash\nexit 7\n' > "$STUB_BIN/curl"
  chmod +x "$STUB_BIN/curl"
  export PATH="$STUB_BIN:$PATH"
  diagnostics="$(collect_install_diagnostics network blocked)"
  [ "$(json_field "$diagnostics" raw_github_network)" = blocked ]
  [[ "$diagnostics" != *'network_body'* ]]
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

@test "acceptance matrix documents sixteen unique scenarios" {
  matrix="$BATS_TEST_DIRNAME/acceptance-matrix.md"
  [ -f "$matrix" ]
  [ "$(awk -F'|' '/^\|[[:space:]]*[0-9]+[[:space:]]*\|/{count++} END{print count+0}' "$matrix")" -eq 16 ]
  run grep -Eiq '同上|ditto' "$matrix"
  [ "$status" -eq 1 ]
}

@test "macOS acceptance actions use only the fixed dispatcher" {
  install_support_run_command() {
    printf '%s %s\n' "$1" "$2" >> "$INSTALL_SUPPORT_COMMAND_LOG"
  }
  install_support_install_gh() {
    printf '__install_gh__\n' >> "$INSTALL_SUPPORT_COMMAND_LOG"
  }
  export -f install_support_run_command install_support_install_gh
  export INSTALL_SUPPORT_COMMAND_LOG="$BATS_TEST_TMPDIR/acceptance-commands.log"

  run_allowlisted_action INSTALL_XCODE_TOOLS_MACOS yes
  run_allowlisted_action INSTALL_GH_MACOS yes
  run_allowlisted_action GH_AUTH_SETUP_GIT yes
  run_allowlisted_action GH_AUTH_LOGIN_WEB yes
  run_allowlisted_action CHECK_RAW_GITHUB_NETWORK no
  run_allowlisted_action GH_AUTH_SWITCH yes

  [ "$(wc -l < "$INSTALL_SUPPORT_COMMAND_LOG" | tr -d ' ')" -eq 6 ]
  run run_allowlisted_action CLEAR_STALE_GITHUB_CREDENTIAL_MACOS no
  [ "$status" -eq 2 ]
}

@test "known local pattern succeeds without API or consent" {
  export FAKE_LOCAL_RESULT='{"matched":true,"local_pattern_key":"macos.xcode_tools_missing.v1","action_id":"INSTALL_XCODE_TOOLS_MACOS","exit_code":0,"succeeded":true}'
  export INSTALL_SUPPORT_CONSENT_LOG="$BATS_TEST_TMPDIR/consent.log"
  export INSTALL_SUPPORT_SESSION_LOG="$BATS_TEST_TMPDIR/session.log"
  [ "$(json_field "$(fake_local_provider)" matched)" = true ]

  handle_install_failure xcode_tools '{"xcode_tools_available":false}' fake_local_provider forbidden_consent_provider forbidden_session_provider
  status=$?
  [ "$status" -eq 0 ]
  [ ! -e "$INSTALL_SUPPORT_CONSENT_LOG" ]
  [ ! -e "$INSTALL_SUPPORT_SESSION_LOG" ]
}

@test "failed local pattern is sent as first previous action after opt-in" {
  export FAKE_LOCAL_RESULT='{"matched":true,"local_pattern_key":"macos.gh_missing.v1","action_id":"INSTALL_GH_MACOS","exit_code":1,"succeeded":false}'
  export FAKE_CONSENT=yes
  export FAKE_SESSION='{"session_id":"is_fake","session_token":"signed-fake"}'
  export FAKE_DIAGNOSIS='{"action":{"id":"CONTACT_INSTRUCTOR","requires_confirmation":false},"resolved":false,"support_code":"SUP-LOCAL2"}'
  export INSTALL_SUPPORT_PREVIOUS_LOG="$BATS_TEST_TMPDIR/previous.json"
  [ "$(json_field "$(fake_local_provider)" local_pattern_key)" = 'macos.gh_missing.v1' ]

  set +e
  handle_install_failure gh_install '{"gh_found":false}' fake_local_provider fake_consent_provider fake_session_provider fake_diagnosis_provider
  status=$?
  set -e
  [ "$status" -eq 6 ]
  [ "$(json_field "$(cat "$INSTALL_SUPPORT_PREVIOUS_LOG")" local_pattern_key)" = 'macos.gh_missing.v1' ]
}

@test "versioned rules file has strict schema and no executable fields" {
  rules="$BATS_TEST_DIRNAME/../../scripts/install-support-patterns.json"
  [ -f "$rules" ]
  run python3 -c 'import json,sys
doc=json.load(open(sys.argv[1]))
assert doc["schema_version"] == 1
assert all(set(p) <= {"pattern_key","platform","step","all","action_id","risk","requires_confirmation","summary_zh_tw"} for p in doc["patterns"])
assert all(set(p["all"].values()) <= {True,False,"missing","expired","blocked","not_logged_in",0,1} for p in doc["patterns"])' "$rules"
  [ "$status" -eq 0 ]
  run grep -Eiq '"(command|script|url|regex|expression)"' "$rules"
  [ "$status" -eq 1 ]
}
