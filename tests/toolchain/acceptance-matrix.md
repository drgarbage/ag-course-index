# 課程工具鏈跨平台驗收矩陣

| Scenario | Platform | Profile | 前置狀態 | Expected Status | Confirmation | Automated Test |
|---:|---|---|---|---|---|---|
| 1 | Windows | base | Git/GitHub CLI 已就緒、Node LTS 未安裝 | `node_lts` 詢問後安裝為 `ready`，`git_gh` 為 `ready` 不重複安裝 | 必須確認 | Pester `Get-WindowsToolState` ready 分支、`Invoke-CourseToolchainToolAction` dispatch 測試 |
| 2 | Windows | base | 全部拒絕安裝 | 每個工具回 `skipped`，report `ready=false`，未呼叫任何 WinGet | 必須確認（拒絕） | Pester `skips CLI, Docker, and GUI tools without any native install call when declined` |
| 3 | Windows | line | `cloudflared` 未安裝，同意安裝 | winget 安裝後 `cloudflared --version` 驗證通過為 `ready` | 必須確認 | Pester `Invoke-WindowsToolInstall` 既有 GREEN 測試 |
| 4 | Windows | data | WSL 2 尚未啟用 | 顯示需重開機影響說明，未經確認不變更 Windows 功能；同意後回 `needs_wsl_confirmation`／`needs_restart`，不強制重開機 | 必須確認（WSL 變更為獨立一次確認） | Pester `does not change WSL without separate WSL confirmation`、`returns needs_restart without forcing reboot when WSL changed` |
| 5 | Windows | data | WSL 2 已啟用，Docker Desktop 未安裝，同意安裝 | 安裝、啟動官方 app path，120 秒內輪詢 `docker version`＋`docker compose version` 皆成功才回 `ready` | 必須確認 | Pester `uses the fixed WinGet Docker Desktop argv...`、`Wait-WindowsDockerReady` 逾時測試 |
| 6 | Windows | full | 任一必要工具最終 `failed` | 顯示本機固定排錯訊息；有 `git_gh` 對應 error_kind 時可選擇 AI 診斷，其餘工具固定回 `CONTACT_INSTRUCTOR` | 必須詢問是否使用 AI | Pester `keeps Node, Docker, and cloudflared on the fixed contact-instructor fallback` |
| 7 | Windows | 任一 | 中途中斷網路（離線） | WinGet 安裝失敗回 `failed`，訊息不含堆疊或內部路徑 | 必須確認 | 手動驗收（無法在單元測試模擬真實離線 WinGet） |
| 8 | macOS (Apple Silicon) | base | Node LTS 未安裝、無 Homebrew | 走 vendor `.pkg` 安裝路徑，checksum 驗證通過後為 `ready` | 必須確認 | Bats `vendor fallback has fixed architecture URLs and checksums`、`install_macos_tool` GREEN 測試 |
| 9 | macOS (Apple Silicon) | data | Docker Desktop 未安裝，同意安裝 | 下載固定 arm64 dmg、checksum 驗證、掛載、複製到 `/Applications`、啟動並等待 Engine+Compose v2 就緒 | 必須確認 | Bats `Docker architecture selects only the matching official artifact`、Docker readiness 測試 |
| 10 | macOS (Intel) | data | 同上，Intel 架構 | 使用固定 x86_64 dmg／checksum，其餘同 Scenario 9 | 必須確認 | Bats `Intel Docker architecture selects only the matching official artifact` |
| 11 | macOS | line | 全部拒絕安裝 | 每個工具回 `skipped`，report `ready=false`，未觸發任何下載/brew/安裝 | 必須確認（拒絕） | Bats `CLI, Docker, and GUI tool dispatch skip cleanly without any native install call when declined` |
| 12 | macOS | full | GUI 工具（antigravity/vscode/browser）選裝 | 僅在明確選擇後才詢問並安裝；未選擇的 profile 不含 GUI 工具 | 必須確認 | Bats `GUI tools are not part of a profile unless explicitly selected`、`install_macos_gui_tool` 測試 |
| 13 | Windows/macOS | 任一 | 輸入無效 profile（如 `evil`／空白） | 重新詢問，不執行任何安裝動作，直到輸入合法 profile | 不適用 | Pester `retries when the profile input is invalid...`；Bats `an invalid profile is retried...` |
| 14 | Windows/macOS | data/full | 可用磁碟空間低於 profile 需求 | Report `disk.status=insufficient`，`ready=false`，`next_step` 提示釋放空間 | 不適用 | Pester/Bats `New-ToolchainReport`／`render_toolchain_report` 既有磁碟測試 |
| 15 | Windows/macOS | 任一 | 安裝完成後重新執行安裝器 | 已就緒工具偵測為 `ready`／`installed`，不重複安裝或詢問 | 不適用（唯讀偵測） | Pester `Get-WindowsToolState` / Bats `get_macos_tool_state` 既有 ready 測試 |

## 尚未自動化、需要人工 sandbox 驗收的部分

上述 Scenario 1–6、8–12 的「決策邏輯」已有自動化測試覆蓋（見上表最後一欄），但**沒有一個自動化測試真的執行過 `winget install`、`brew install`、下載官方 Docker/Node 安裝檔、或真的啟動 Docker Desktop**。需要在乾淨的機器上人工跑過一次完整流程，確認：

1. 乾淨 Windows 10/11 VM（無 WinGet 快取、無 Docker/Node/cloudflared）：依序跑 `base` → `line` → `data`，每個工具都同意安裝，確認實際裝好且 report 顯示 `ready`。
2. 同一台 VM 上模擬 WSL 2 尚未啟用的情況（或用未啟用過 WSL 的新 VM）：確認會先提示需要重開機、不強制重開機；手動重開機後重跑安裝器，確認能接續完成 Docker Desktop 安裝。
3. Apple Silicon 與 Intel Mac（若能取得）：在無 Homebrew 環境下各跑一次 `data`／`full`，確認 vendor `.pkg`／Docker `.dmg` 安裝與 checksum 驗證都成功。
4. 任一平台：中途拔網路線／關閉 Wi-Fi 後同意安裝，確認失敗訊息乾淨（無堆疊、無 token、無使用者路徑），且會提示是否要 AI 協助或聯絡講師。
5. 每次執行都檢查終端機輸出不含 credential、SSH key、`.env` 內容或完整檔案路徑（使用者帳號名稱）。

驗收前**不得**在真實學員環境或正式課程機器上執行完整流程；請使用可重灌／快照還原的 VM 或測試帳號。
