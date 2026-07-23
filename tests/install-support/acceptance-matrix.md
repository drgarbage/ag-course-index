# Install Support 跨平台驗收矩陣

| Scenario | Platform | Fixture／狀態 | Expected Action | Risk | Confirmation | Automated Test／Fallback |
|---:|---|---|---|---|---|---|
| 1 | Windows | `git_found=false`, `gh_found=false` | `INSTALL_GIT_WINDOWS` | medium | 必須確認 | Pester `maps Windows scenario actions`; 失敗時保留靜態 Git 安裝說明 |
| 2 | Windows | `git_found=true`, `gh_found=false`, `winget_available=true` | `INSTALL_GH_WINDOWS` | medium | 必須確認 | Pester `maps Windows scenario actions`; 未確認時不呼叫 WinGet |
| 3 | Windows | `credential_helpers=[]` | `GH_AUTH_SETUP_GIT` | low | 必須確認 | Pester `maps Windows scenario actions`; 失敗時保留 credential helper 說明 |
| 4 | Windows | `github_auth_state=token_expired` | `GH_AUTH_LOGIN_WEB` | medium | 必須確認 | Pester `maps Windows scenario actions`; 失敗時顯示 support code |
| 5 | Windows | PATH 尚未刷新且找不到 Git | `REFRESH_WINDOWS_PATH` | low | 必須確認 | Pester `maps Windows scenario actions`; 不啟動任意 shell |
| 6 | Windows | `winget_available=false` | `CONTACT_INSTRUCTOR` | read_only | 不需確認 | 後端 fixture scenario 6；安裝器保留 Microsoft Store 靜態說明 |
| 7 | macOS | `xcode_tools_available=false` | `INSTALL_XCODE_TOOLS_MACOS` | medium | 必須確認 | Bats `macOS acceptance actions`; 未確認時不執行 `xcode-select` |
| 8 | macOS | `local_bin_in_path=false` | `RESTART_TERMINAL_REQUIRED` | low | 必須確認 | Bats confirmation gate；保留重新開啟終端機說明 |
| 9 | Windows/macOS | Raw GitHub blocked | `CHECK_RAW_GITHUB_NETWORK` | read_only | 不需確認 | Pester 與 Bats fixed dispatcher tests；離線時回靜態說明 |
| 10 | Windows/macOS | GitHub account mismatch | `GH_AUTH_SWITCH` | medium | 必須確認 | Pester 與 Bats fixed dispatcher tests；不得由 response 提供帳號參數 |
| 11 | Windows | stale Credential Manager entry | `CLEAR_STALE_GITHUB_CREDENTIAL_WINDOWS` | medium | 必須確認 | Pester dispatcher test；僅允許固定 GitHub credential target |
| 12 | macOS | API／LiteLLM timeout | `CONTACT_INSTRUCTOR` | read_only | 不需確認 | Bats `offline API keeps the static fallback`; 不重試模型 |
| 13 | Windows | fake `ghp_…` token in stderr | `CHECK_GH_AUTH_STATUS` | read_only | 不需確認 | Pester collector/redaction 與後端 scenario 13；token 不得送出 |
| 14 | macOS | response action=`RUN_ARBITRARY_COMMAND` | `CONTACT_INSTRUCTOR` | read_only | 不需確認 | Bats `unknown action never executes response command`; 回靜態說明 |
| 15 | Windows/macOS | session rate limit／15 輪上限 | `CONTACT_INSTRUCTOR` | read_only | 不需確認 | Pester/Bats loop-limit tests；顯示 support code 並停止 API 呼叫 |
| 16 | Windows/macOS | 任一 low／medium action 未確認 | 不執行狀態變更 | low/medium | 必須確認 | Pester/Bats confirmation tests；回傳拒絕結果 |

手動 sandbox 驗收需在無真實 credential 的 Windows VM 與 macOS 測試帳號執行：拒絕 AI、接受 AI/read-only、拒絕 medium、API DNS failure。檢查輸出不得包含 session token、`.env`、Keychain/Credential Manager secret 或 SSH private key。
