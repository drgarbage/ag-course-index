#!/bin/bash

set -u

step() { printf '\n\033[36m▶ %s\033[0m\n' "$1"; }
ok() { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }
fail() {
  printf '\n\033[31m安裝未完成：%s\033[0m\n' "$1"
  printf '\033[33m建議處理方式：%s\033[0m\n' "$2"
  local diagnostics
  diagnostics="$(collect_install_diagnostics "${3:-network}" "$1")"
  if handle_install_failure "${3:-network}" "$diagnostics"; then
    ok 'AI 安裝助理已完成排錯。'
    exit 0
  fi
  read -r -p "按 Enter 結束"
  exit 1
}
has_command() { command -v "$1" >/dev/null 2>&1; }

INSTALL_SUPPORT_BASE_URL="https://gemini.printii.com/api/install-support"
INSTALL_SUPPORT_PATTERN_FILE="${INSTALL_SUPPORT_PATTERN_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-support-patterns.json}"

json_field() {
  python3 -c 'import json,sys
value=json.loads(sys.argv[1]).get(sys.argv[2], "")
print(value if isinstance(value,str) else json.dumps(value,separators=(",",":")))' "$1" "$2"
}

json_path() {
  python3 -c 'import json,sys
value=json.loads(sys.argv[1])
for key in sys.argv[2].split("."):
    value=value.get(key, "") if isinstance(value, dict) else ""
print(str(value).lower() if isinstance(value, bool) else value)' "$1" "$2"
}

json_path_type() {
  python3 -c 'import json,sys
value=json.loads(sys.argv[1])
for key in sys.argv[2].split("."):
    value=value.get(key, None) if isinstance(value,dict) else None
print("boolean" if isinstance(value,bool) else "string" if isinstance(value,str) else "number" if isinstance(value,(int,float)) else "null" if value is None else "other")' "$1" "$2"
}

collect_install_diagnostics() {
  local support_step="$1"
  local last_error="${2:-}"
  local safe_error
  safe_error="$(printf '%s' "$last_error" | sed -E 's#/Users/[^/[:space:]]+#/Users/<USER>#g' | cut -c 1-4000)"
  local git_found=false gh_found=false xcode_tools_available=false local_bin_in_path=false
  local github_auth_state=unknown credential_helper_state=unknown raw_github_network=unknown
  has_command git && git_found=true
  has_command gh && gh_found=true
  xcode-select -p >/dev/null 2>&1 && xcode_tools_available=true
  case ":$PATH:" in *":$HOME/.local/bin:"*) local_bin_in_path=true ;; esac
  if [ "$support_step" = github_auth ] && [ "$gh_found" = true ]; then
    if gh auth status --hostname github.com >/dev/null 2>&1; then github_auth_state=authenticated; else github_auth_state=not_logged_in; fi
  fi
  if [ "$support_step" = credential_helper ] && [ "$git_found" = true ]; then
    if git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' >/dev/null 2>&1; then credential_helper_state=configured; else credential_helper_state=missing; fi
  fi
  if [ "$support_step" = network ]; then
    if curl --head --silent --show-error --max-time 5 https://raw.githubusercontent.com >/dev/null 2>&1; then raw_github_network=ok; else raw_github_network=blocked; fi
  fi
  python3 -c 'import json,sys; print(json.dumps({
    "platform":"macos", "step":sys.argv[1],
    "git_found":sys.argv[2] == "true", "gh_found":sys.argv[3] == "true",
    "xcode_tools_available":sys.argv[4] == "true", "local_bin_in_path":sys.argv[5] == "true",
    "github_auth_state":sys.argv[6], "credential_helper_state":sys.argv[7],
    "raw_github_network":sys.argv[8], "stderr":sys.argv[9]
  }, separators=(",", ":")))' \
    "$support_step" "$git_found" "$gh_found" "$xcode_tools_available" "$local_bin_in_path" \
    "$github_auth_state" "$credential_helper_state" "$raw_github_network" "$safe_error"
}

new_install_support_session() {
  local installer_version="$1"
  local body
  body="$(python3 -c 'import json,sys; print(json.dumps({"platform":"macos","installer_version":sys.argv[1]}, separators=(",", ":")))' "$installer_version")"
  curl --fail-with-body --silent --show-error --connect-timeout 5 --max-time 20 \
    -X POST -H 'Content-Type: application/json' --data "$body" \
    "$INSTALL_SUPPORT_BASE_URL/sessions"
}

invoke_install_diagnosis() {
  local session_id="$1" session_token="$2" support_step="$3" attempt="$4" diagnostics="$5"
  local previous_action="${6:-null}"
  local body
  body="$(python3 -c 'import json,sys; print(json.dumps({
    "session_id":sys.argv[1], "step":sys.argv[2], "attempt":int(sys.argv[3]),
    "diagnostics":json.loads(sys.argv[4]), "previous_action":json.loads(sys.argv[5])
  }, separators=(",", ":")))' "$session_id" "$support_step" "$attempt" "$diagnostics" "$previous_action")"
  curl --fail-with-body --silent --show-error --connect-timeout 5 --max-time 20 \
    -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $session_token" \
    --data "$body" "$INSTALL_SUPPORT_BASE_URL/diagnose"
}

install_support_run_command() { command "$@"; }

install_support_install_gh() {
  local release_json gh_url temp_dir gh_binary architecture
  case "$(uname -m)" in arm64) architecture=arm64 ;; x86_64) architecture=amd64 ;; *) return 65 ;; esac
  release_json="$(curl --fail-with-body --silent --show-error --connect-timeout 5 --max-time 20 \
    https://api.github.com/repos/cli/cli/releases/latest)" || return
  gh_url="$(printf '%s' "$release_json" | python3 -c 'import json,sys
arch=sys.argv[1]
for asset in json.load(sys.stdin).get("assets", []):
    url=asset.get("browser_download_url", "")
    if url.endswith("_macOS_" + arch + ".zip"):
        print(url); break' "$architecture")"
  [ -n "$gh_url" ] || return 65
  temp_dir="$(mktemp -d)" || return
  curl --fail-with-body --silent --show-error --connect-timeout 5 --max-time 20 \
    "$gh_url" -o "$temp_dir/gh.zip" || { rm -rf "$temp_dir"; return 1; }
  unzip -q "$temp_dir/gh.zip" -d "$temp_dir/unpacked" || { rm -rf "$temp_dir"; return 1; }
  gh_binary="$(find "$temp_dir/unpacked" -type f -path '*/bin/gh' -print -quit)"
  [ -n "$gh_binary" ] || { rm -rf "$temp_dir"; return 65; }
  mkdir -p "$HOME/.local/bin" && cp "$gh_binary" "$HOME/.local/bin/gh" && chmod 755 "$HOME/.local/bin/gh"
  local result=$?
  rm -rf "$temp_dir"
  return "$result"
}

run_allowlisted_action() {
  local action_id="$1" confirmation="${2:-no}"
  local requires_confirmation=false
  case "$action_id" in
    CHECK_GIT_VERSION) set -- git --version ;;
    CHECK_GH_VERSION) set -- gh --version ;;
    CHECK_XCODE_TOOLS) set -- xcode-select -p ;;
    CHECK_GITHUB_NETWORK) set -- curl --head --max-time 10 https://github.com ;;
    CHECK_RAW_GITHUB_NETWORK) set -- curl --head --max-time 10 https://raw.githubusercontent.com ;;
    CHECK_GH_AUTH_STATUS) set -- gh auth status --hostname github.com ;;
    CHECK_GIT_CREDENTIAL_HELPER) set -- git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' ;;
    OPEN_MACOS_KEYCHAIN_ACCESS) set -- open -a 'Keychain Access' ;;
    CONTACT_INSTRUCTOR) set -- __no_op__ ;;
    INSTALL_XCODE_TOOLS_MACOS) requires_confirmation=true; set -- xcode-select --install ;;
    INSTALL_GH_MACOS) requires_confirmation=true; set -- __install_gh__ ;;
    GH_AUTH_LOGIN_WEB) requires_confirmation=true; set -- gh auth login --hostname github.com --git-protocol https --web ;;
    GH_AUTH_SETUP_GIT) requires_confirmation=true; set -- gh auth setup-git --hostname github.com ;;
    GH_AUTH_SWITCH) requires_confirmation=true; set -- gh auth switch --hostname github.com ;;
    CLEAR_STALE_GITHUB_CREDENTIAL_MACOS) requires_confirmation=true; set -- __open_keychain_manual__ ;;
    RESTART_TERMINAL_REQUIRED) requires_confirmation=true; set -- __no_op__ ;;
    *) printf 'Unknown install support action: %s\n' "$action_id" >&2; return 64 ;;
  esac
  if [ "$requires_confirmation" = true ] && [ "$confirmation" != yes ]; then
    printf 'Explicit confirmation is required.\n' >&2
    return 2
  fi
  case "$1" in
    __no_op__) return 0 ;;
    __install_gh__) install_support_install_gh ;;
    __open_keychain_manual__) install_support_run_command open -a 'Keychain Access' >/dev/null 2>&1; return 3 ;;
    *) install_support_run_command "$@" ;;
  esac
}

macos_action_requires_confirmation() {
  case "$1" in
    INSTALL_XCODE_TOOLS_MACOS|INSTALL_GH_MACOS|GH_AUTH_LOGIN_WEB|GH_AUTH_SETUP_GIT|GH_AUTH_SWITCH|CLEAR_STALE_GITHUB_CREDENTIAL_MACOS|RESTART_TERMINAL_REQUIRED) return 0 ;;
    CHECK_GIT_VERSION|CHECK_GH_VERSION|CHECK_XCODE_TOOLS|CHECK_GITHUB_NETWORK|CHECK_RAW_GITHUB_NETWORK|CHECK_GH_AUTH_STATUS|CHECK_GIT_CREDENTIAL_HELPER|OPEN_MACOS_KEYCHAIN_ACCESS|CONTACT_INSTRUCTOR) return 1 ;;
    *) return 64 ;;
  esac
}

invoke_local_install_pattern() {
  local support_step="$1" diagnostics="$2" rules_path="${3:-$INSTALL_SUPPORT_PATTERN_FILE}"
  local confirmation_provider="${4:-install_support_confirmation}" action_runner="${5:-run_allowlisted_action}"
  [ -f "$rules_path" ] || { printf '{"matched":false}'; return 0; }
  local match
  match="$(python3 -c 'import json,sys
doc=json.load(open(sys.argv[1])); diagnostics=json.loads(sys.argv[3])
allowed_fields={"pattern_key","platform","step","all","action_id","risk","requires_confirmation","summary_zh_tw"}
allowed_values={True,False,"missing","expired","blocked","not_logged_in",0,1}
allowed_actions={"CHECK_GIT_VERSION","CHECK_GH_VERSION","CHECK_XCODE_TOOLS","CHECK_GITHUB_NETWORK","CHECK_RAW_GITHUB_NETWORK","CHECK_GH_AUTH_STATUS","CHECK_GIT_CREDENTIAL_HELPER","INSTALL_XCODE_TOOLS_MACOS","INSTALL_GH_MACOS","GH_AUTH_LOGIN_WEB","GH_AUTH_SETUP_GIT","GH_AUTH_SWITCH","CLEAR_STALE_GITHUB_CREDENTIAL_MACOS","OPEN_MACOS_KEYCHAIN_ACCESS","RESTART_TERMINAL_REQUIRED","CONTACT_INSTRUCTOR"}
if doc.get("schema_version") != 1: raise SystemExit(0)
for p in doc.get("patterns",[]):
  if set(p) - allowed_fields or p.get("platform") != "macos" or p.get("step") != sys.argv[2]: continue
  if p.get("action_id") not in allowed_actions or p.get("risk") not in {"read_only","low","medium"}: continue
  if bool(p.get("requires_confirmation")) != (p.get("risk") in {"low","medium"}): continue
  if any(v not in allowed_values for v in p.get("all",{}).values()): continue
  if all(diagnostics.get(k) == v for k,v in p.get("all",{}).items()):
    print("\t".join([p["pattern_key"],p["action_id"],str(p["requires_confirmation"]).lower()])); break' \
    "$rules_path" "$support_step" "$diagnostics")" || { printf '{"matched":false}'; return 0; }
  [ -n "$match" ] || { printf '{"matched":false}'; return 0; }
  local pattern_key action_id requires_confirmation confirmation=no exit_code
  pattern_key="$(printf '%s' "$match" | cut -f1)"
  action_id="$(printf '%s' "$match" | cut -f2)"
  requires_confirmation="$(printf '%s' "$match" | cut -f3)"
  if [ "$requires_confirmation" = true ]; then
    confirmation="$($confirmation_provider)"
    case "$confirmation" in y|Y|yes|YES) confirmation=yes ;; *) confirmation=no ;; esac
  fi
  if "$action_runner" "$action_id" "$confirmation" >/dev/null; then exit_code=0; else exit_code=$?; fi
  python3 -c 'import json,sys; print(json.dumps({
    "matched":True,"local_pattern_key":sys.argv[1],"action_id":sys.argv[2],
    "exit_code":int(sys.argv[3]),"succeeded":int(sys.argv[3]) == 0
  },separators=(",",":")))' "$pattern_key" "$action_id" "$exit_code"
}

install_support_consent() {
  local answer
  read -r -p '是否使用 AI 安裝助理？(y/N)：' answer
  printf '%s' "$answer"
}

install_support_confirmation() {
  local answer
  read -r -p '是否執行上述動作？(y/N)：' answer
  printf '%s' "$answer"
}

handle_install_failure() {
  local support_step="$1" diagnostics="$2"
  local local_provider="${3:-invoke_local_install_pattern}" consent_provider="${4:-install_support_consent}"
  local session_provider="${5:-new_install_support_session}" diagnosis_provider="${6:-invoke_install_diagnosis}"
  local confirmation_provider="${7:-install_support_confirmation}"
  local consent session_json session_id session_token previous_action=null support_code=''
  local local_result
  local_result="$($local_provider "$support_step" "$diagnostics")"
  if [ "$(json_field "$local_result" matched)" = true ]; then
    if [ "$(json_field "$local_result" succeeded)" = true ]; then return 0; fi
    previous_action="$(python3 -c 'import json,sys
r=json.loads(sys.argv[1]); print(json.dumps({k:r[k] for k in ("local_pattern_key","action_id","exit_code","succeeded")},separators=(",",":")))' "$local_result")"
  fi
  consent="$($consent_provider)"
  case "$consent" in y|Y|yes|YES) ;; *) return 3 ;; esac

  if ! session_json="$($session_provider '1.0.0')"; then
    printf 'AI 診斷目前無法連線；原本的靜態排錯說明仍然有效。\n'
    return 4
  fi
  session_id="$(json_field "$session_json" session_id)"
  session_token="$(json_field "$session_json" session_token)"
  [ -n "$session_id" ] && [ -n "$session_token" ] || {
    printf 'AI 診斷回應格式錯誤；原本的靜態排錯說明仍然有效。\n'
    return 4
  }

  local attempt diagnosis action_id requires_confirmation confirmation exit_code
  for attempt in $(seq 1 15); do
    if ! diagnosis="$($diagnosis_provider "$session_id" "$session_token" "$support_step" "$attempt" "$diagnostics" "$previous_action")"; then
      printf 'AI 診斷目前無法連線；原本的靜態排錯說明仍然有效。\n'
      return 4
    fi
    support_code="$(json_field "$diagnosis" support_code)"
    [ -n "$(json_field "$diagnosis" summary_zh_tw)" ] && printf '%s\n' "$(json_field "$diagnosis" summary_zh_tw)"
    [ -n "$(json_field "$diagnosis" explanation_zh_tw)" ] && printf '%s\n' "$(json_field "$diagnosis" explanation_zh_tw)"
    [ "$(json_path_type "$diagnosis" resolved)" = boolean ] || {
      printf 'AI 診斷回應格式錯誤；原本的靜態排錯說明仍然有效。\n'
      return 4
    }
    [ "$(json_field "$diagnosis" resolved)" = true ] && return 0

    action_id="$(json_path "$diagnosis" action.id)"
    [ -n "$action_id" ] || {
      printf 'AI 診斷回應格式錯誤；原本的靜態排錯說明仍然有效。\n'
      return 4
    }
    [ -n "$(json_path "$diagnosis" action.title_zh_tw)" ] && printf '%s\n' "$(json_path "$diagnosis" action.title_zh_tw)"
    [ -n "$(json_path "$diagnosis" action.impact_zh_tw)" ] && printf '%s\n' "$(json_path "$diagnosis" action.impact_zh_tw)"
    [ "$action_id" = CONTACT_INSTRUCTOR ] && {
      printf '請將支援碼 %s 提供給講師。\n' "$support_code"
      return 6
    }
    confirmation=no
    if macos_action_requires_confirmation "$action_id"; then
      requires_confirmation=true
    else
      local policy_status=$?
      [ "$policy_status" -eq 1 ] || {
        printf 'AI 診斷回應包含不允許的動作；原本的靜態排錯說明仍然有效。\n'
        return 4
      }
      requires_confirmation=false
    fi
    if [ "$requires_confirmation" = true ]; then
      confirmation="$($confirmation_provider)"
      case "$confirmation" in y|Y|yes|YES) confirmation=yes ;; *) return 3 ;; esac
    fi

    if run_allowlisted_action "$action_id" "$confirmation"; then exit_code=0; else exit_code=$?; fi
    previous_action="$(python3 -c 'import json,sys; print(json.dumps({
      "action_id":sys.argv[1], "exit_code":int(sys.argv[2]), "succeeded":int(sys.argv[2]) == 0
    }, separators=(",", ":")))' "$action_id" "$exit_code")"
  done
  printf '已達診斷次數上限，請將支援碼 %s 提供給講師。\n' "$support_code"
  return 5
}

COURSE_GITHUB_SCOPES="repo,read:org,workflow"

# 從瀏覽器下載的 .command 會被標記隔離，雙擊時 Gatekeeper 會直接擋掉。
clear_own_quarantine() {
  local target="${1:-}"
  [ -n "$target" ] && [ -f "$target" ] || return 1
  has_command xattr || return 1
  xattr -p com.apple.quarantine "$target" >/dev/null 2>&1 || return 1
  xattr -d com.apple.quarantine "$target" >/dev/null 2>&1
}

# 透過瀏覽器下載後執行位元常會遺失，導致 permission denied。
ensure_own_executable_bit() {
  local target="${1:-}"
  [ -n "$target" ] && [ -f "$target" ] || return 1
  [ -x "$target" ] && return 1
  chmod +x "$target" >/dev/null 2>&1
}

# 未同意 Xcode 授權條款時，git 每次都會以錯誤結束，且需要管理員權限才能同意。
xcode_license_state() {
  local probe_output
  probe_output="$(git --version 2>&1)" || {
    if printf '%s' "$probe_output" | grep -qi 'license'; then
      printf 'not_accepted'
      return 0
    fi
    printf 'unknown'
    return 0
  }
  printf 'accepted'
}

default_browser_available() {
  has_command open || return 1
  # LaunchServices 沒有 https handler 時 open 會失敗，先做無害探測。
  open -Ra Safari >/dev/null 2>&1 && return 0
  [ -n "$(mdfind -name 'kMDItemCFBundleIdentifier == com.google.Chrome' 2>/dev/null | head -n 1)" ] && return 0
  return 1
}

# 回傳 ready 或以空白分隔的阻擋原因（network／browser）。
github_login_prerequisite() {
  local network_probe="${1:-default_github_network_probe}"
  local browser_probe="${2:-default_browser_available}"
  local blockers=''
  "$network_probe" || blockers="network"
  "$browser_probe" || blockers="${blockers:+$blockers }browser"
  [ -n "$blockers" ] || { printf 'ready'; return 0; }
  printf '%s' "$blockers"
}

default_github_network_probe() {
  has_command curl || return 0
  curl --head --silent --show-error --max-time 10 https://github.com >/dev/null 2>&1
}

# 回傳 not_logged_in、insufficient_scope:<缺少的 scope>，或 authenticated。
github_auth_state() {
  local required_scopes="${1:-$COURSE_GITHUB_SCOPES}"
  local status_provider="${2:-default_gh_auth_status}"
  local status_text granted missing scope
  if ! status_text="$("$status_provider" 2>&1)"; then
    printf 'not_logged_in'
    return 0
  fi
  granted="$(printf '%s' "$status_text" \
    | sed -nE 's/.*[Tt]oken scopes:[[:space:]]*(.*)$/\1/p' \
    | tr -d "'\"" | tr ',' ' ' | tr -s ' ')"
  # gh 未回報 scope 行時無從判斷，視為足夠以免誤擋已經可用的環境。
  [ -n "$(printf '%s' "$granted" | tr -d '[:space:]')" ] || { printf 'authenticated'; return 0; }
  missing=''
  for scope in $(printf '%s' "$required_scopes" | tr ',' ' '); do
    printf ' %s ' "$granted" | grep -Fq " $scope " || missing="${missing:+$missing,}$scope"
  done
  [ -n "$missing" ] && { printf 'insufficient_scope:%s' "$missing"; return 0; }
  printf 'authenticated'
}

default_gh_auth_status() { gh auth status --hostname github.com 2>&1; }

printf '\033[1mGit 與 GitHub CLI 課程環境安裝程式\033[0m\n'
printf '程式只會安裝官方工具、設定 Git，並開啟 GitHub 官方登入頁。\n'

step "檢查執行環境權限"
SELF_PATH="${BASH_SOURCE[0]:-$0}"
if clear_own_quarantine "$SELF_PATH"; then
  ok "已移除下載檔案的隔離標記（Gatekeeper）"
fi
if ensure_own_executable_bit "$SELF_PATH"; then
  ok "已補上檔案執行權限"
fi
case "$(xcode_license_state)" in
  not_accepted)
    warn "尚未同意 Xcode 命令列工具授權條款，Git 目前無法使用。"
    printf '  請執行下列指令並輸入你的 Mac 密碼，同意條款後回到這裡：\n'
    printf '  \033[36msudo xcodebuild -license accept\033[0m\n'
    read -r -p "完成後按 Enter 繼續："
    [ "$(xcode_license_state)" = not_accepted ] && \
      fail "Xcode 授權條款仍未同意，Git 無法使用。" "在終端機執行 sudo xcodebuild -license accept，輸入 Mac 密碼並同意條款後，再重新執行本程式。" xcode_tools
    ok "Xcode 授權條款已同意"
    ;;
  accepted) ok "Xcode 命令列工具授權條款已同意" ;;
esac

step "檢查並安裝 Git"
if xcode-select -p >/dev/null 2>&1 && has_command git; then
  ok "已安裝：$(git --version)"
else
  warn "尚未安裝 Apple Command Line Tools。系統即將顯示 Apple 官方安裝視窗。"
  xcode-select --install >/dev/null 2>&1 || true
  printf '  請在系統視窗按「安裝」，等待安裝完成後回到這裡。\n'
  read -r -p "完成後按 Enter 繼續："
  if ! xcode-select -p >/dev/null 2>&1 || ! has_command git; then
    fail "仍找不到 Git。" "到「系統設定 → 一般 → 軟體更新」完成 Command Line Tools 更新，重新開機後再執行本程式。" xcode_tools
  fi
  if [ "$(xcode_license_state)" = not_accepted ]; then
    fail "Git 已安裝，但尚未同意 Xcode 授權條款。" "在終端機執行 sudo xcodebuild -license accept，輸入 Mac 密碼並同意條款後，再重新執行本程式。" xcode_tools
  fi
  ok "安裝完成：$(git --version)"
fi

step "檢查並安裝 GitHub CLI"
LOCAL_BIN="$HOME/.local/bin"
if has_command gh; then
  ok "已安裝：$(gh --version | head -n 1)"
else
  has_command curl || fail "找不到 curl，無法下載 GitHub CLI。" "先完成 macOS 系統更新，再重新執行本程式。" gh_install
  has_command unzip || fail "找不到 unzip，無法解壓縮 GitHub CLI。" "先完成 macOS 系統更新，再重新執行本程式。" gh_install
  case "$(uname -m)" in
    arm64) GH_ARCH="arm64" ;;
    x86_64) GH_ARCH="amd64" ;;
    *) fail "不支援的處理器架構：$(uname -m)" "請從 https://cli.github.com/ 依官方說明手動安裝。" gh_install ;;
  esac
  printf '  正在查詢 GitHub 官方最新版本並下載，請稍候。\n'
  RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest)" || \
    fail "無法連線到 GitHub API。" "確認網路、VPN、防火牆或學校代理伺服器設定後重試。" network
  GH_URL="$(printf '%s' "$RELEASE_JSON" | sed -nE 's/.*"browser_download_url": "([^"]*_macOS_'"$GH_ARCH"'\.zip)".*/\1/p' | head -n 1)"
  [ -n "$GH_URL" ] || fail "找不到適合這台 Mac 的 GitHub CLI 安裝檔。" "GitHub 的套件格式可能已變更，請從 https://cli.github.com/ 手動安裝並通知講師更新腳本。" gh_install
  TMP_DIR="$(mktemp -d)" || fail "無法建立暫存資料夾。" "確認磁碟空間與使用者權限後重試。" gh_install
  trap 'rm -rf "$TMP_DIR"' EXIT
  curl -fL "$GH_URL" -o "$TMP_DIR/gh.zip" || fail "GitHub CLI 下載失敗。" "確認網路連線後重試。" network
  unzip -q "$TMP_DIR/gh.zip" -d "$TMP_DIR/unpacked" || fail "GitHub CLI 解壓縮失敗。" "刪除下載檔並重新執行本程式。" gh_install
  GH_BINARY="$(find "$TMP_DIR/unpacked" -type f -path '*/bin/gh' -print -quit)"
  [ -n "$GH_BINARY" ] || fail "下載內容中找不到 gh。" "請從 https://cli.github.com/ 手動安裝並通知講師。" gh_install
  mkdir -p "$LOCAL_BIN" || fail "無法建立 $LOCAL_BIN。" "確認個人資料夾權限後重試。" path
  cp "$GH_BINARY" "$LOCAL_BIN/gh" && chmod 755 "$LOCAL_BIN/gh" || \
    fail "無法將 gh 安裝到 $LOCAL_BIN。" "確認個人資料夾權限與磁碟空間後重試。" path
  export PATH="$LOCAL_BIN:$PATH"
  PROFILE_FILE="$HOME/.zprofile"
  PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
  if ! grep -Fq "$PATH_LINE" "$PROFILE_FILE" 2>/dev/null; then
    printf '\n%s\n' "$PATH_LINE" >> "$PROFILE_FILE" || fail "無法更新 $PROFILE_FILE。" "請手動將 $LOCAL_BIN 加入 PATH。" path
  fi
  has_command gh || fail "GitHub CLI 已下載，但目前仍找不到 gh。" "關閉終端機、重新開啟後再執行本程式。" path
  ok "安裝完成：$(gh --version | head -n 1)"
fi

step "檢查 GitHub 登入"
AUTH_STATE="$(github_auth_state "$COURSE_GITHUB_SCOPES")"
case "$AUTH_STATE" in
  authenticated)
    ok "GitHub CLI 已登入且授權範圍足夠"
    gh auth status --hostname github.com
    ;;
  insufficient_scope:*)
    MISSING_SCOPES="${AUTH_STATE#insufficient_scope:}"
    warn "已登入，但授權範圍不足（缺少：$MISSING_SCOPES）。課程操作會在後續步驟失敗，現在補齊授權。"
    printf '  即將開啟瀏覽器補授權，不需要重新登入。\n'
    gh auth refresh --hostname github.com -s "$COURSE_GITHUB_SCOPES" || \
      fail "GitHub 授權範圍補齊失敗（缺少：$MISSING_SCOPES）。" "請自行執行 gh auth refresh --hostname github.com -s $COURSE_GITHUB_SCOPES，完成後重新執行本程式。" github_auth
    ok "授權範圍已補齊"
    ;;
esac
if [ "$AUTH_STATE" = not_logged_in ]; then
  warn "尚未登入、授權已失效，或系統鑰匙圈中的舊憑證無法使用。接下來會協助你登入 GitHub。"

  PREREQUISITE="$(github_login_prerequisite)"
  case "$PREREQUISITE" in
    *network*)
      fail "目前無法連線到 github.com，登入流程一定會失敗。" "確認網路、VPN、防火牆或學校代理伺服器設定，能用瀏覽器開啟 https://github.com 之後再重新執行本程式。" network
      ;;
  esac
  case "$PREREQUISITE" in
    *browser*)
      warn "找不到可用的預設瀏覽器；若登入頁沒有自動開啟，請手動複製畫面上的網址到瀏覽器。"
      ;;
  esac

  read -r -p "你是否已經有 GitHub 帳號？(Y/n，若不確定就按 Enter)：" HAS_ACCOUNT
  if printf '%s' "$HAS_ACCOUNT" | grep -Eiq '^(n|no|否)$'; then
    printf '  尚未有帳號沒關係，先完成註冊再繼續。\n'
    printf '  即將開啟 GitHub 註冊頁面：https://github.com/signup\n'
    printf '  若你想直接用 Google／Gmail 帳號註冊，請在該頁面選擇「Continue with Google」，並完成畫面上要求的使用者名稱等設定。\n'
    open "https://github.com/signup" >/dev/null 2>&1 || true
    read -r -p "完成註冊（包含設定使用者名稱）後，按 Enter 繼續："
  fi

  LOGGED_IN=0
  MAX_ATTEMPTS=3
  for ATTEMPT in $(seq 1 "$MAX_ATTEMPTS"); do
    printf '  正在開啟 GitHub 網頁登入（第 %s/%s 次）。請登入正確帳號並完成裝置授權；完成前不要關閉這個視窗。\n' "$ATTEMPT" "$MAX_ATTEMPTS"
    if gh auth login --hostname github.com --git-protocol https --web -s "$COURSE_GITHUB_SCOPES"; then
      LOGGED_IN=1
      break
    fi
    warn "這次登入沒有成功。常見原因：註冊尚未完成（例如用 Google 登入後還沒設定 GitHub 使用者名稱）、瀏覽器分頁忘記按授權、或是等待逾時。"
    if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
      read -r -p "要再試一次嗎？(Y/n)：" RETRY
      if printf '%s' "$RETRY" | grep -Eiq '^(n|no|否)$'; then break; fi
    fi
  done

  [ "$LOGGED_IN" -eq 1 ] || {
    printf '\n你可以自行複製下列指令，在本視窗貼上並執行，完成登入後再重新執行本程式：\n'
    printf '  \033[36mgh auth login --hostname github.com --git-protocol https --web\033[0m\n'
    printf '  若瀏覽器授權一直失敗，可改用互動模式並選擇貼上權杖（Paste an authentication token）：\n'
    printf '  \033[36mgh auth login --hostname github.com --git-protocol https\033[0m\n'
    printf '  若這台電腦上有多個 GitHub 帳號，請先切換帳號：\n'
    printf '  \033[36mgh auth switch --hostname github.com\033[0m\n'
    fail "GitHub 網頁登入未完成。" "在本視窗執行 gh auth login --hostname github.com --git-protocol https --web 完成登入；若剛用 Google 帳號註冊，請先確認已設定好 GitHub 使用者名稱。若鑰匙圈一直詢問密碼，請開啟「鑰匙圈存取」確認登入鑰匙圈已解鎖。" github_auth
  }
fi

step "設定 Git 提交身分"
CURRENT_NAME="$(git config --global user.name 2>/dev/null || true)"
CURRENT_EMAIL="$(git config --global user.email 2>/dev/null || true)"
[ -n "$CURRENT_NAME" ] && printf '  目前姓名：%s\n' "$CURRENT_NAME"
while :; do
  if [ -n "$CURRENT_NAME" ]; then read -r -p "Git 顯示姓名（直接按 Enter 保留目前設定）：" INPUT_NAME
  else read -r -p "Git 顯示姓名（必填）：" INPUT_NAME; fi
  [ -n "$INPUT_NAME" ] && CURRENT_NAME="$INPUT_NAME"
  [ -n "$CURRENT_NAME" ] && break
done
[ -n "$CURRENT_EMAIL" ] && printf '  目前信箱：%s\n' "$CURRENT_EMAIL"
while :; do
  if [ -n "$CURRENT_EMAIL" ]; then read -r -p "Git 提交信箱（直接按 Enter 保留目前設定）：" INPUT_EMAIL
  else read -r -p "Git 提交信箱（必填）：" INPUT_EMAIL; fi
  [ -n "$INPUT_EMAIL" ] && CURRENT_EMAIL="$INPUT_EMAIL"
  if printf '%s' "$CURRENT_EMAIL" | grep -Eq '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'; then break; fi
  warn "信箱格式看起來不正確，請重新輸入。"
  CURRENT_EMAIL=""
done
git config --global user.name "$CURRENT_NAME" || fail "無法保存 Git 姓名。" "確認個人資料夾中的 .gitconfig 權限。"
git config --global user.email "$CURRENT_EMAIL" || fail "無法保存 Git 信箱。" "確認個人資料夾中的 .gitconfig 權限。"
git config --global init.defaultBranch main
ok "Git 身分與預設分支已設定"

step "讓 Git 使用 GitHub CLI 保存 HTTPS 憑證"
gh config set git_protocol https --host github.com || fail "無法設定 HTTPS。" "執行 gh auth status 確認登入狀態。" credential_helper
gh auth setup-git --hostname github.com || \
  fail "無法設定 Git credential helper。" "執行 gh auth status，再執行 gh auth setup-git。若仍失敗，檢查「鑰匙圈存取」中的舊 GitHub 項目。" credential_helper
ok "Git 不應再於每次 pull／push 時重複要求登入"

step "最終驗證"
FAILED=0
has_command git || { warn "找不到 Git"; FAILED=1; }
has_command gh || { warn "找不到 GitHub CLI"; FAILED=1; }
FINAL_AUTH_STATE="$(github_auth_state "$COURSE_GITHUB_SCOPES")"
case "$FINAL_AUTH_STATE" in
  not_logged_in) warn "GitHub 授權驗證失敗"; FAILED=1 ;;
  insufficient_scope:*) warn "GitHub 授權範圍不足（缺少：${FINAL_AUTH_STATE#insufficient_scope:}）"; FAILED=1 ;;
esac
HELPER="$(git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' 2>/dev/null || true)"
[ -n "$HELPER" ] || { warn "找不到 Git 憑證助手設定"; FAILED=1; }
[ "$FAILED" -eq 0 ] || fail "部分檢查未通過。" "重新執行本程式；若仍失敗，將畫面中的黃色訊息提供給講師。" credential_helper

printf '\n\033[32m所有必要設定皆已完成。\033[0m\n'
printf 'Git：%s\n' "$(git --version)"
printf 'GitHub CLI：%s\n' "$(gh --version | head -n 1)"
printf 'Git 姓名：%s\n' "$(git config --global user.name)"
printf 'Git 信箱：%s\n' "$(git config --global user.email)"
gh auth status --hostname github.com
printf '\n請關閉並重新開啟終端機，之後即可進行課程的 git 與 gh 操作。\n'
read -r -p "按 Enter 結束"
