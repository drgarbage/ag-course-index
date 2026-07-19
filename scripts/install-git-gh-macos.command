#!/bin/bash

set -u

step() { printf '\n\033[36m▶ %s\033[0m\n' "$1"; }
ok() { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }
fail() {
  printf '\n\033[31m安裝未完成：%s\033[0m\n' "$1"
  printf '\033[33m建議處理方式：%s\033[0m\n' "$2"
  read -r -p "按 Enter 結束"
  exit 1
}
has_command() { command -v "$1" >/dev/null 2>&1; }

printf '\033[1mGit 與 GitHub CLI 課程環境安裝程式\033[0m\n'
printf '程式只會安裝官方工具、設定 Git，並開啟 GitHub 官方登入頁。\n'

step "檢查並安裝 Git"
if xcode-select -p >/dev/null 2>&1 && has_command git; then
  ok "已安裝：$(git --version)"
else
  warn "尚未安裝 Apple Command Line Tools。系統即將顯示 Apple 官方安裝視窗。"
  xcode-select --install >/dev/null 2>&1 || true
  printf '  請在系統視窗按「安裝」，等待安裝完成後回到這裡。\n'
  read -r -p "完成後按 Enter 繼續："
  if ! xcode-select -p >/dev/null 2>&1 || ! has_command git; then
    fail "仍找不到 Git。" "到「系統設定 → 一般 → 軟體更新」完成 Command Line Tools 更新，重新開機後再執行本程式。"
  fi
  ok "安裝完成：$(git --version)"
fi

step "檢查並安裝 GitHub CLI"
LOCAL_BIN="$HOME/.local/bin"
if has_command gh; then
  ok "已安裝：$(gh --version | head -n 1)"
else
  has_command curl || fail "找不到 curl，無法下載 GitHub CLI。" "先完成 macOS 系統更新，再重新執行本程式。"
  has_command unzip || fail "找不到 unzip，無法解壓縮 GitHub CLI。" "先完成 macOS 系統更新，再重新執行本程式。"
  case "$(uname -m)" in
    arm64) GH_ARCH="arm64" ;;
    x86_64) GH_ARCH="amd64" ;;
    *) fail "不支援的處理器架構：$(uname -m)" "請從 https://cli.github.com/ 依官方說明手動安裝。" ;;
  esac
  printf '  正在查詢 GitHub 官方最新版本並下載，請稍候。\n'
  RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest)" || \
    fail "無法連線到 GitHub API。" "確認網路、VPN、防火牆或學校代理伺服器設定後重試。"
  GH_URL="$(printf '%s' "$RELEASE_JSON" | sed -nE 's/.*"browser_download_url": "([^"]*_macOS_'"$GH_ARCH"'\.zip)".*/\1/p' | head -n 1)"
  [ -n "$GH_URL" ] || fail "找不到適合這台 Mac 的 GitHub CLI 安裝檔。" "GitHub 的套件格式可能已變更，請從 https://cli.github.com/ 手動安裝並通知講師更新腳本。"
  TMP_DIR="$(mktemp -d)" || fail "無法建立暫存資料夾。" "確認磁碟空間與使用者權限後重試。"
  trap 'rm -rf "$TMP_DIR"' EXIT
  curl -fL "$GH_URL" -o "$TMP_DIR/gh.zip" || fail "GitHub CLI 下載失敗。" "確認網路連線後重試。"
  unzip -q "$TMP_DIR/gh.zip" -d "$TMP_DIR/unpacked" || fail "GitHub CLI 解壓縮失敗。" "刪除下載檔並重新執行本程式。"
  GH_BINARY="$(find "$TMP_DIR/unpacked" -type f -path '*/bin/gh' -print -quit)"
  [ -n "$GH_BINARY" ] || fail "下載內容中找不到 gh。" "請從 https://cli.github.com/ 手動安裝並通知講師。"
  mkdir -p "$LOCAL_BIN" || fail "無法建立 $LOCAL_BIN。" "確認個人資料夾權限後重試。"
  cp "$GH_BINARY" "$LOCAL_BIN/gh" && chmod 755 "$LOCAL_BIN/gh" || \
    fail "無法將 gh 安裝到 $LOCAL_BIN。" "確認個人資料夾權限與磁碟空間後重試。"
  export PATH="$LOCAL_BIN:$PATH"
  PROFILE_FILE="$HOME/.zprofile"
  PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
  if ! grep -Fq "$PATH_LINE" "$PROFILE_FILE" 2>/dev/null; then
    printf '\n%s\n' "$PATH_LINE" >> "$PROFILE_FILE" || fail "無法更新 $PROFILE_FILE。" "請手動將 $LOCAL_BIN 加入 PATH。"
  fi
  has_command gh || fail "GitHub CLI 已下載，但目前仍找不到 gh。" "關閉終端機、重新開啟後再執行本程式。"
  ok "安裝完成：$(gh --version | head -n 1)"
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

step "檢查 GitHub 登入"
if gh auth status --hostname github.com >/dev/null 2>&1; then
  ok "GitHub CLI 已登入"
  gh auth status --hostname github.com
else
  warn "尚未登入、授權已失效，或系統鑰匙圈中的舊憑證無法使用。接下來會協助你登入 GitHub。"

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
    if gh auth login --hostname github.com --git-protocol https --web; then
      LOGGED_IN=1
      break
    fi
    warn "這次登入沒有成功。常見原因：註冊尚未完成（例如用 Google 登入後還沒設定 GitHub 使用者名稱）、瀏覽器分頁忘記按授權、或是等待逾時。"
    if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
      read -r -p "要再試一次嗎？(Y/n)：" RETRY
      if printf '%s' "$RETRY" | grep -Eiq '^(n|no|否)$'; then break; fi
    fi
  done

  [ "$LOGGED_IN" -eq 1 ] || \
    fail "GitHub 網頁登入未完成。" "先確認你能用瀏覽器正常登入 github.com（若剛用 Google 帳號註冊，請確認已設定好 GitHub 使用者名稱）。若鑰匙圈一直詢問密碼，請開啟「鑰匙圈存取」確認登入鑰匙圈已解鎖，再重新執行本程式。"
fi

step "讓 Git 使用 GitHub CLI 保存 HTTPS 憑證"
gh config set git_protocol https --host github.com || fail "無法設定 HTTPS。" "執行 gh auth status 確認登入狀態。"
gh auth setup-git --hostname github.com || \
  fail "無法設定 Git credential helper。" "執行 gh auth status，再執行 gh auth setup-git。若仍失敗，檢查「鑰匙圈存取」中的舊 GitHub 項目。"
ok "Git 不應再於每次 pull／push 時重複要求登入"

step "最終驗證"
FAILED=0
has_command git || { warn "找不到 Git"; FAILED=1; }
has_command gh || { warn "找不到 GitHub CLI"; FAILED=1; }
gh auth status --hostname github.com >/dev/null 2>&1 || { warn "GitHub 授權驗證失敗"; FAILED=1; }
HELPER="$(git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' 2>/dev/null || true)"
[ -n "$HELPER" ] || { warn "找不到 Git 憑證助手設定"; FAILED=1; }
[ "$FAILED" -eq 0 ] || fail "部分檢查未通過。" "重新執行本程式；若仍失敗，將畫面中的黃色訊息提供給講師。"

printf '\n\033[32m所有必要設定皆已完成。\033[0m\n'
printf 'Git：%s\n' "$(git --version)"
printf 'GitHub CLI：%s\n' "$(gh --version | head -n 1)"
printf 'Git 姓名：%s\n' "$(git config --global user.name)"
printf 'Git 信箱：%s\n' "$(git config --global user.email)"
gh auth status --hostname github.com
printf '\n請關閉並重新開啟終端機，之後即可進行課程的 git 與 gh 操作。\n'
read -r -p "按 Enter 結束"
