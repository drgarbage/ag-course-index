#!/usr/bin/env bats

setup() {
  PLANNER="$BATS_TEST_DIRNAME/../../scripts/course-toolchain-macos.command"
  # shellcheck disable=SC1090
  source "$PLANNER"
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
