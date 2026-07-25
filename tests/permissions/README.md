# 權限與環境阻擋的測試方式

安裝程式會遇到的權限問題分成兩類，測試方式完全不同。搞混這兩類是最容易漏測的地方。

| 類別 | 特徵 | 測試方式 |
|---|---|---|
| **A：腳本啟動前就被擋** | 腳本一行都還沒跑，OS 就拒絕執行 | 只能真的把環境弄壞再跑，見「真實環境驗證」 |
| **B：腳本可自行偵測** | 腳本跑得起來，但某項條件不成立 | 注入替身 provider 的單元測試即可 |

## B 類：單元測試（快、每次改動都該跑）

判斷邏輯全部寫成可注入的函式，不碰真實系統。

```powershell
# Windows：62 項
Invoke-Pester -Path tests/install-support/windows.Tests.ps1 -Output Detailed
```

```bash
# macOS：需要 bats 與 python3
bats tests/install-support/macos.bats
```

涵蓋：語言模式判斷、ExecutionPolicy 狀態與群組原則鎖定、解除封鎖、
登入前置條件、GitHub token scope 三態判斷、Xcode 授權條款偵測。

> **注意**：`macos.bats` 有 9 項測試依賴 `python3`。在沒有真正 python3 的機器上
> （例如只有 Microsoft Store 版 stub 的 Windows）這 9 項會失敗，那是環境問題，
> 不是程式問題。判斷是否有回歸，請比較失敗數是否仍為 9。

## A 類：真實環境驗證（改動前置檢查時必跑）

單元測試證明「判斷邏輯正確」，但無法證明「真實的 OS 阻擋會被正確處理」。
這兩個腳本反過來做：真的把環境弄壞，再確認安裝程式有反應。

### Windows

```powershell
# 重要：不要加 -ExecutionPolicy Bypass。
# 該旗標會設定 Process 範圍政策，其優先度高於 CurrentUser，
# 會讓 Restricted 情境完全測不到（腳本會顯示 [SKIP]）。
powershell -NoProfile -File tests/permissions/verify-windows-preflight.ps1
```

驗證 4 個情境、共 16 項斷言：

1. **ConstrainedLanguage** —— 在子程序中把語言模式降級（只能降不能升，與 WDAC 效果等價），
   確認安裝程式給出可讀的中文說明、沒有殘留紅字、且未呼叫需要 .NET 的 AI 助理。
2. **MOTW 封鎖標記** —— 真的附加 `Zone.Identifier` 資料流，確認會被解除。
3. **ExecutionPolicy Restricted** —— 暫時把 CurrentUser 設為 `Restricted`，確認
   直接執行 `.ps1` 會被擋（重現學生的錯誤）、`.cmd` 啟動檔能越過、偵測邏輯回報正確。
4. **一行指令載入** —— 確認 `$PSScriptRoot` 為空時開頭區塊不會擲錯。

> 情境 3 會暫時修改你的 CurrentUser 政策，正常結束時一定會還原。
> **若中途強制中斷，政策可能卡在 `Restricted`** —— 腳本下次啟動會偵測並提醒，
> 也可手動執行 `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` 還原。

### macOS

```bash
bash tests/permissions/verify-macos-preflight.sh
```

驗證隔離標記移除、執行權限補正、Xcode 授權條款偵測、登入前置檢查。
非 macOS 環境會以結束碼 2 直接跳出。

Gatekeeper 的圖形化封鎖對話框只在 Finder 雙擊時出現，無法自動驗證，
腳本會列為手動項目。

## 手動重現各情境

需要親眼確認學生看到什麼時使用。

### Windows：ExecutionPolicy

```powershell
Set-ExecutionPolicy Restricted -Scope CurrentUser   # 弄壞
.\install-git-gh-windows.ps1                        # 應被擋下
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser # 還原
```

### Windows：下載封鎖標記

```powershell
Set-Content -Path .\install-git-gh-windows.ps1 -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
Get-Item .\install-git-gh-windows.ps1 -Stream Zone.Identifier   # 確認存在
```

### Windows：ConstrainedLanguage

```powershell
powershell -NoProfile -Command "$ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'; .\install-git-gh-windows.ps1"
```

### macOS：Gatekeeper 隔離

```bash
xattr -w com.apple.quarantine "0083;00000000;Safari;" ./install-git-gh-macos.command
xattr -l ./install-git-gh-macos.command    # 確認存在
```

### GitHub token scope 不足

```bash
# 用刻意過窄的 scope 登入，再執行安裝程式，應自動觸發 gh auth refresh
gh auth logout --hostname github.com
gh auth login --hostname github.com --git-protocol https --web -s gist
```

## 無法自動化的項目

以下屬於企業環境或 GUI 行為，只能靠支援碼與講師介入，刻意不做偵測：

- 群組原則鎖定 ExecutionPolicy（需要網域環境；邏輯本身有單元測試涵蓋）
- 防毒／SmartScreen／AppLocker 封鎖 `winget` 或 `gh.exe`
- macOS 鑰匙圈被鎖定
- Windows UAC 提示（可偵測是否已提升，但無法程式授予）
