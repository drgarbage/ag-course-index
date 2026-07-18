# Visual Studio Code：macOS 安裝指引

## 安裝步驟

1. 選擇 Apple 選單 ** → 關於這台 Mac**，確認「晶片」或「處理器」資訊。
2. 前往 [VS Code 官方下載頁](https://code.visualstudio.com/download)。
3. Apple 晶片選 **Apple silicon**，Intel 處理器選 **Intel chip**；不確定時可選 **Universal**。
4. 開啟下載的 `.zip` 檔，將 Visual Studio Code 拖入「應用程式」資料夾。
5. 從「應用程式」啟動 VS Code。若 macOS 顯示安全提示，請確認檔案來自官網後再允許開啟。
6. 選擇 **File → Open Folder** 開啟課程資料夾。

## 設定 `code` 指令

1. 在 VS Code 按 `Command + Shift + P` 開啟命令選擇區。
2. 執行 **Shell Command: Install 'code' command in PATH**。
3. 關閉並重新開啟「終端機」，執行：

```bash
code --version
```

若顯示版本號，即可在專案目錄使用 `code .` 開啟 VS Code。

## 建議設定與確認

- 只安裝課程或專案需要的擴充套件。
- 開啟陌生專案前先確認來源，再決定是否信任工作區。
- 使用 **Terminal → New Terminal** 開啟 zsh。
- 新增 `test.md`、儲存檔案並確認整合式終端機可正常輸入指令。

## 官方參考

- [macOS 安裝說明](https://code.visualstudio.com/docs/setup/mac)
- [VS Code 入門文件](https://code.visualstudio.com/docs/getstarted/getting-started)

[返回平台選擇](visual-studio-code.md) · [返回 README](../../README.md)
