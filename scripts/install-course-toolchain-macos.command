#!/bin/bash

set -u

# Source the macos toolchain modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/course-toolchain-macos.command" ]; then
  printf '\033[31m找不到主套件規劃器：%s/course-toolchain-macos.command\033[0m\n' "$SCRIPT_DIR"
  exit 1
fi
source "$SCRIPT_DIR/course-toolchain-macos.command"

show_menu() {
  clear
  printf '=========================================================\n'
  printf '           \033[36m反重力 AI 課程環境一鍵安裝程式 (macOS)\033[0m\n'
  printf '=========================================================\n'
  printf ' 1) 完整安裝 (全裝) - 安裝並設定 Git/GH、Node、Cloudflared、Docker、GUI、中文化\n'
  printf ' 2) 自訂安裝 (選特定標的安裝)\n'
  printf ' 3) 執行環境 Readiness Report 檢查\n'
  printf ' 4) 結束退出\n'
  printf '=========================================================\n\n'
}

get_environment_readiness_json() {
  local results="["

  # 1. git_gh
  local git_present=false gh_present=false git_version="" gh_version="" auth_msg="" git_gh_status="failed"
  command -v git >/dev/null 2>&1 && git_present=true
  command -v gh >/dev/null 2>&1 && gh_present=true
  if [ "$git_present" = true ]; then
    git_version="$(git --version | sed 's/git version //')"
  fi
  if [ "$gh_present" = true ]; then
    gh_version="$(gh --version | head -n 1 | sed 's/gh version //')"
  fi
  
  local gh_authed=false
  if [ "$gh_present" = true ]; then
    if gh auth status --hostname github.com >/dev/null 2>&1; then
      gh_authed=true
    else
      auth_msg="GitHub CLI 尚未登入。"
    fi
  else
    auth_msg="GitHub CLI 未安裝。"
  fi

  if [ "$git_present" = true ] && [ "$gh_present" = true ] && [ "$gh_authed" = true ]; then
    git_gh_status="ready"
  elif [ "$git_present" = true ] && [ "$gh_present" = true ]; then
    git_gh_status="failed"
  else
    git_gh_status="missing"
  fi
  results+='{"tool_id":"git_gh","status":"'"$git_gh_status"'","version":"git:'"$git_version"'; gh:'"$gh_version"'","safe_message":"'"$auth_msg"'"}'

  add_tool_status() {
    local tool_id="$1" state
    state="$(get_macos_tool_state "$tool_id")"
    results+=",${state}"
  }
  
  # 2. node_lts
  add_tool_status "node_lts"
  
  # 3. cloudflared
  add_tool_status "cloudflared"
  
  # 4. docker_desktop
  local docker_status="missing"
  local docker_msg=""
  if verify_macos_docker >/dev/null 2>&1; then
    docker_status="ready"
  else
    if command -v docker >/dev/null 2>&1; then
      docker_status="failed"
      docker_msg="偵測到 Docker Desktop 已經安裝，但 Docker 守護行程（daemon）尚未啟動，請手動開啟 Docker Desktop 應用程式。"
    else
      docker_status="failed"
      docker_msg="未偵測到 Docker Desktop，請執行安裝。"
    fi
  fi
  results+=',{"tool_id":"docker_desktop","status":"'"$docker_status"'","safe_message":"'"$docker_msg"'"}'
  
  # 5. GUI tools
  for gui_id in antigravity vscode browser; do
    local gui_status="missing"
    if macos_gui_ready "$gui_id"; then
      gui_status="ready"
    fi
    results+=',{"tool_id":"'"$gui_id"'","status":"'"$gui_status"'"}'
  done
  
  results+="]"
  printf '%s\n' "$results"
}

show_readiness_report() {
  printf '\n=== 執行環境 Readiness Report 檢查 ===\n'
  local json free_bytes report
  json="$(get_environment_readiness_json)"
  free_bytes="$(python3 -c "import shutil; print(shutil.disk_usage('/').free)" 2>/dev/null || echo "")"
  report="$(render_course_toolchain_macos_readiness_report 'full' "$json" "$free_bytes")"
  
  python3 -c '
import json
import sys

try:
    report = json.loads(sys.argv[1])
except Exception:
    print("解析報告失敗。")
    sys.exit(1)

ready_text = "【就緒】" if report["ready"] else "【未就緒】"
print("總體準備狀態: " + ready_text)
print("需求設定檔等級: " + report["profile"])
if report["disk"]["free_bytes"] is not None:
    free_gb = round(report["disk"]["free_bytes"] / (1024**3), 2)
    req_gb = round(report["disk"]["required_bytes"] / (1024**3), 2)
    print(f"磁碟可用空間: {free_gb} GB (系統建議: {req_gb} GB, 狀態: {report["disk"]["status"]})")
else:
    print("磁碟可用空間: 未知")
print("下一步指引: " + report["next_step"])
print("各工具細部狀態:")
print("-" * 56)
for tool in report["tools"]:
    req_mark = "[必備]" if tool["requirement"] == "required" else "[選配]"
    ver_str = f" (版本: {tool["version"]})" if tool["version"] else ""
    print(f" {req_mark} {tool["tool_id"]}: {tool["status"]}{ver_str}")
    if tool["safe_message"]:
        print(f"   備註: {tool["safe_message"]}")
print("=" * 57)
' "$report"
}

install_git_gh() {
  printf '\n\033[36m▶ 正在啟動 Git 與 GitHub CLI 獨立安裝程序...\033[0m\n'
  local git_gh_script="$SCRIPT_DIR/install-git-gh-macos.command"
  if [ -f "$git_gh_script" ]; then
    bash "$git_gh_script"
    if [ $? -eq 0 ]; then
      printf '\033[32m✓ Git 與 GitHub CLI 安裝與設定完成。\033[0m\n'
      return 0
    else
      printf '\033[33m! Git 與 GitHub CLI 安裝程序返回錯誤碼。\033[0m\n'
      return 1
    fi
  else
    printf '\033[33m! 找不到 Git/GH 安裝指令檔：%s\033[0m\n' "$git_gh_script"
    return 1
  fi
}

install_all_tools() {
  printf '\n正在執行完整一鍵安裝 (全裝)...\n'
  
  # 1. git_gh
  install_git_gh
  
  # 2. node_lts
  printf '\n\033[36m▶ 檢查並安裝 Node.js LTS...\033[0m\n'
  local node_state
  node_state="$(get_macos_tool_state node_lts)"
  case "$node_state" in
    *'"status":"ready"'*) printf '  \033[32m✓ NodeJS 已就緒\033[0m\n' ;;
    *) install_macos_tool node_lts yes ;;
  esac
  
  # 3. cloudflared
  printf '\n\033[36m▶ 檢查並安裝 Cloudflared...\033[0m\n'
  local cf_state
  cf_state="$(get_macos_tool_state cloudflared)"
  case "$cf_state" in
    *'"status":"ready"'*) printf '  \033[32m✓ Cloudflared 已就緒\033[0m\n' ;;
    *) install_macos_tool cloudflared yes ;;
  esac
  
  # 4. docker_desktop
  printf '\n\033[36m▶ 檢查並安裝 Docker Desktop...\033[0m\n'
  install_course_toolchain_macos_docker_desktop yes
  
  # 5. GUI tools
  printf '\n\033[36m▶ 檢查並安裝 GUI 工具 (VS Code, Browser, Antigravity)...\033[0m\n'
  install_course_toolchain_macos_gui_tool vscode yes
  install_course_toolchain_macos_gui_tool browser yes
  install_course_toolchain_macos_gui_tool antigravity yes
  
  # 6. Localization
  printf '\n\033[36m▶ 檢查並安裝中文化模組...\033[0m\n'
  install_macos_localization vscode yes
  install_macos_localization antigravity_ide yes
  
  printf '警告：即將執行 Antigravity 2.0 中文化修改。確認要繼續嗎？ [y/N] '
  read -r patch_confirm
  case "$patch_confirm" in
    y|Y|yes|YES) install_macos_localization antigravity_app yes ;;
    *) install_macos_localization antigravity_app no ;;
  esac
  
  printf '\n\033[32m一鍵全裝程序執行完畢。\033[0m\n'
  show_readiness_report
}

install_custom() {
  printf '\n\033[36m自訂選擇安裝工具\033[0m\n'
  printf '請選擇要安裝的項目 (多選，以逗號或空格分隔，例如: 1,3,5):\n'
  printf ' 1) Git 與 GitHub CLI (git_gh)\n'
  printf ' 2) Node.js LTS (node_lts)\n'
  printf ' 3) Cloudflare Tunnel (cloudflared)\n'
  printf ' 4) Docker Desktop (docker_desktop)\n'
  printf ' 5) GUI 工具 (Antigravity IDE, VS Code, Browser)\n'
  printf ' 6) Antigravity 2.0 中文化\n'
  printf ' 7) Antigravity IDE 中文化 (設定教學)\n'
  printf ' 8) VS Code 中文化 (設定教學)\n\n'
  
  printf '請輸入編號: '
  read -r selection
  if [ -z "$selection" ]; then
    printf '未輸入 any 項目，返回選單。\n'
    return
  fi
  
  local clean_sel
  clean_sel="$(printf '%s' "$selection" | tr ',' ' ')"
  
  for opt in $clean_sel; do
    case "$opt" in
      1)
        install_git_gh
        ;;
      2)
        printf '\n\033[36m▶ 檢查並安裝 Node.js LTS...\033[0m\n'
        install_macos_tool node_lts yes
        ;;
      3)
        printf '\n\033[36m▶ 檢查並安裝 Cloudflared...\033[0m\n'
        install_macos_tool cloudflared yes
        ;;
      4)
        printf '\n\033[36m▶ 檢查並安裝 Docker Desktop...\033[0m\n'
        install_course_toolchain_macos_docker_desktop
        ;;
      5)
        printf '\n\033[36m▶ 檢查並安裝 GUI 工具...\033[0m\n'
        printf '請選擇：1) 全部安裝 2) 僅安裝 Antigravity 3) 僅安裝 VS Code 4) 僅安裝瀏覽器 [預設: 1]: '
        read -r choice
        if [ "$choice" = '2' ]; then
          install_course_toolchain_macos_gui_tool antigravity
        elif [ "$choice" = '3' ]; then
          install_course_toolchain_macos_gui_tool vscode
        elif [ "$choice" = '4' ]; then
          install_course_toolchain_macos_gui_tool browser
        else
          install_course_toolchain_macos_gui_tool vscode yes
          install_course_toolchain_macos_gui_tool browser yes
          install_course_toolchain_macos_gui_tool antigravity yes
        fi
        ;;
      6)
        printf '\n\033[36m▶ 檢查並執行 Antigravity 2.0 中文化...\033[0m\n'
        printf '警告：即將執行 Antigravity 2.0 中文化修改。確認要繼續嗎？ [y/N] '
        read -r patch_confirm
        case "$patch_confirm" in
          y|Y|yes|YES) install_macos_localization antigravity_app yes ;;
          *) install_macos_localization antigravity_app no ;;
        esac
        ;;
      7)
        printf '\n\033[36m▶ 檢查並執行 Antigravity IDE 中文化...\033[0m\n'
        install_macos_localization antigravity_ide yes
        ;;
      8)
        printf '\n\033[36m▶ 檢查並執行 VS Code 中文化...\033[0m\n'
        install_macos_localization vscode yes
        ;;
    esac
  done
  
  show_readiness_report
}

# Check non-interactive argument
if [ "${1:-}" = "--non-interactive" ]; then
  export NON_INTERACTIVE=true
  install_all_tools
  exit 0
fi

# Main Loop
while true; do
  show_menu
  printf '請輸入選擇編號 (1-4): '
  read -r choice
  case "$choice" in
    1)
      install_all_tools
      printf '\n執行完畢，按 Enter 繼續'
      read -r
      ;;
    2)
      install_custom
      printf '\n執行完畢，按 Enter 繼續'
      read -r
      ;;
    3)
      show_readiness_report
      printf '\n按 Enter 繼續'
      read -r
      ;;
    4)
      printf '感謝使用，再見！\n'
      break
      ;;
    *)
      printf '\033[31m無效的選擇，請輸入 1-4 之間的數字。\033[0m\n'
      sleep 1
      ;;
  esac
done
