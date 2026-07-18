# Git 與 GitHub CLI：macOS 安裝指引

## 快速安裝（建議）

開啟「終端機」，貼上以下完整指令並按 Enter：

```bash
installer_file="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/install-git-gh-macos.command -o "$installer_file" && bash "$installer_file"; rm -f "$installer_file"
```

程式會顯示中文說明，並在需要時開啟 GitHub 官方登入頁。請保持終端機視窗開啟，直到看到「所有必要設定皆已完成」。

## 下載後執行（備用）

1. 下載 [`install-git-gh-macos.command`](../../scripts/install-git-gh-macos.command)。
2. 開啟「終端機」，切換到下載資料夾後執行：

```bash
chmod +x ./install-git-gh-macos.command
./install-git-gh-macos.command
```

3. 若 macOS 第一次安裝 Command Line Tools，系統會顯示 Apple 安裝視窗。完成後回到終端機按 Enter。
4. 依中文提示輸入 Git 姓名與信箱，並在瀏覽器完成 GitHub 授權。
5. 看到「所有必要設定皆已完成」後，關閉並重新開啟終端機。

> 這行指令會將腳本下載到系統暫存檔、執行後刪除。請只使用本專案提供的 `raw.githubusercontent.com/drgarbage/ag-course-index` 網址。

## 程式會處理的常見狀況

- 已安裝 Git 或 `gh`：保留現有安裝並繼續設定。
- 尚未安裝 Apple Command Line Tools：啟動官方安裝視窗並等待確認。
- 未安裝 Homebrew：直接從 GitHub 官方 Release 安裝 `gh` 到 `~/.local/bin`。
- PATH 未包含 `~/.local/bin`：加入 `~/.zprofile` 並立即套用。
- GitHub 憑證失效或 Git 未使用 `gh` 憑證：重新登入並設定 credential helper。
- macOS 鑰匙圈無法保存憑證：顯示警告及「鑰匙圈存取」檢查方向。

## 手動檢查

```bash
git --version
gh --version
gh auth status
git config --global user.name
git config --global user.email
git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$'
```

[返回平台選擇](git-and-gh.md) · [返回 README](../../README.md)
