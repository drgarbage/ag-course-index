#!/bin/bash
# 在真實 macOS 環境中驗證安裝程式「檢查執行環境權限」的行為。
#
# bats 測試（tests/install-support/macos.bats）用替身函式驗證判斷邏輯，
# 但無法證明真實的 Gatekeeper 隔離標記與檔案權限會被正確處理。
# 這個腳本反過來做：真的把檔案弄壞，再確認安裝程式有正確反應。
#
# 不需要 sudo，也不會修改工作目錄以外的任何東西。
#
# 用法：bash tests/permissions/verify-macos-preflight.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${1:-$SCRIPT_DIR/../../scripts/install-git-gh-macos.command}"
PASSED=0
FAILED=0

pass() { printf '  \033[32m[PASS]\033[0m %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail_case() {
  printf '  \033[31m[FAIL]\033[0m %s\n' "$1"
  [ -n "${2:-}" ] && printf '         %s\n' "$2"
  FAILED=$((FAILED + 1))
}
assert() { if [ "$1" = true ]; then pass "$2"; else fail_case "$2" "${3:-}"; fi; }

if [ "$(uname -s)" != Darwin ]; then
  printf '\033[33m這個腳本只能在 macOS 上執行（目前為 %s）。\033[0m\n' "$(uname -s)"
  printf '判斷邏輯本身的測試請執行：bats tests/install-support/macos.bats\n'
  exit 2
fi

[ -f "$INSTALLER" ] || { printf '找不到安裝程式：%s\n' "$INSTALLER"; exit 1; }
INSTALLER="$(cd "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

printf '\n\033[36m=== 真實環境權限前置檢查驗證（macOS）===\033[0m\n'
printf '安裝程式：%s\n\n' "$INSTALLER"

# 只載入橫幅之前的函式庫，避免執行真正的安裝流程。
LIBRARY="$WORK_DIR/library.sh"
awk '/^printf .*Git 與 GitHub CLI 課程環境安裝程式/{exit} {print}' "$INSTALLER" > "$LIBRARY"
# shellcheck disable=SC1090
source "$LIBRARY"

# ---------------------------------------------------------------------------
printf '\033[36m情境 1：下載檔案帶有 Gatekeeper 隔離標記\033[0m\n'
SAMPLE="$WORK_DIR/sample.command"
cp "$INSTALLER" "$SAMPLE"
# 這正是瀏覽器下載時附加的擴充屬性格式。
xattr -w com.apple.quarantine "0083;00000000;Safari;" "$SAMPLE" 2>/dev/null

if xattr -p com.apple.quarantine "$SAMPLE" >/dev/null 2>&1; then
  pass "測試前置：隔離標記已成功附加"
  if clear_own_quarantine "$SAMPLE"; then
    assert "$(xattr -p com.apple.quarantine "$SAMPLE" >/dev/null 2>&1 && echo false || echo true)" \
      "移除隔離標記後 com.apple.quarantine 已消失" \
      "$(xattr -l "$SAMPLE" 2>&1)"
  else
    fail_case "clear_own_quarantine 回報失敗" "$(xattr -l "$SAMPLE" 2>&1)"
  fi
  # 沒有標記時應回報「未做任何事」，避免顯示多餘訊息。
  assert "$(clear_own_quarantine "$SAMPLE" && echo false || echo true)" \
    "已無隔離標記時不重複回報"
else
  printf '  \033[33m[SKIP]\033[0m 這個檔案系統不支援擴充屬性，無法驗證隔離標記\n'
fi

# ---------------------------------------------------------------------------
printf '\n\033[36m情境 2：下載後遺失執行權限\033[0m\n'
NOEXEC="$WORK_DIR/noexec.command"
cp "$INSTALLER" "$NOEXEC"
chmod -x "$NOEXEC"
assert "$([ -x "$NOEXEC" ] && echo false || echo true)" "測試前置：執行權限已移除"
assert "$(ensure_own_executable_bit "$NOEXEC" && echo true || echo false)" "補上執行權限時回報有修改"
assert "$([ -x "$NOEXEC" ] && echo true || echo false)" "檔案確實變為可執行"
assert "$(ensure_own_executable_bit "$NOEXEC" && echo false || echo true)" "已可執行時不重複回報"

# ---------------------------------------------------------------------------
printf '\n\033[36m情境 3：Xcode 授權條款尚未同意\033[0m\n'
FAKE_BIN="$WORK_DIR/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/git" <<'FAKE'
#!/bin/bash
echo "Agreeing to the Xcode/iOS license requires admin privileges, please run 'sudo xcodebuild -license'" >&2
exit 69
FAKE
chmod +x "$FAKE_BIN/git"
LICENSE_STATE="$(PATH="$FAKE_BIN:$PATH" bash -c "source '$LIBRARY'; xcode_license_state")"
assert "$([ "$LICENSE_STATE" = not_accepted ] && echo true || echo false)" \
  "偵測到未同意的 Xcode 授權條款" "state=$LICENSE_STATE"

cat > "$FAKE_BIN/git" <<'FAKE'
#!/bin/bash
echo "git: command not found" >&2
exit 127
FAKE
chmod +x "$FAKE_BIN/git"
OTHER_STATE="$(PATH="$FAKE_BIN:$PATH" bash -c "source '$LIBRARY'; xcode_license_state")"
assert "$([ "$OTHER_STATE" = unknown ] && echo true || echo false)" \
  "不把其他 git 失敗誤判為授權問題" "state=$OTHER_STATE"

# ---------------------------------------------------------------------------
printf '\n\033[36m情境 4：登入前置條件\033[0m\n'
NET_STATE="$(github_login_prerequisite default_github_network_probe default_browser_available)"
printf '  目前這台機器的偵測結果：%s\n' "$NET_STATE"
assert "$([ -n "$NET_STATE" ] && echo true || echo false)" "前置檢查有回傳結果"

# ---------------------------------------------------------------------------
printf '\n\033[36m情境 5：受隔離的檔案實際雙擊行為\033[0m\n'
printf '  \033[33m[手動]\033[0m Gatekeeper 的圖形化封鎖只在 Finder 雙擊時出現，無法自動驗證。\n'
printf '         請手動確認：對受隔離的 .command 按兩下，應出現「無法打開」對話框；\n'
printf '         而用「快速安裝」的一行指令則完全不受影響。\n'

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32m=== 結果：%s 通過、%s 失敗 ===\033[0m\n' "$PASSED" "$FAILED"
else
  printf '\033[31m=== 結果：%s 通過、%s 失敗 ===\033[0m\n' "$PASSED" "$FAILED"
  exit 1
fi
