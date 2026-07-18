# Visual Studio Code：Windows 安裝指引

## 安裝步驟

1. 前往 [VS Code 官方下載頁](https://code.visualstudio.com/download)。
2. 在 Windows 區域下載適合電腦架構的 **User Installer**。多數電腦使用 x64；ARM Windows 裝置則選 Arm64。
3. 執行下載的安裝程式並閱讀授權條款。
4. 在「選取其他工作」頁面，建議勾選：
   - 將「使用 Code 開啟」加入檔案右鍵選單
   - 將「使用 Code 開啟」加入目錄右鍵選單
   - 將 VS Code 加入 PATH
5. 完成安裝並重新開啟 PowerShell 或命令提示字元。
6. 啟動 VS Code，選擇 **File → Open Folder** 開啟課程資料夾。

## 驗證 `code` 指令

在新開啟的 PowerShell 執行：

```powershell
code --version
```

若顯示版本號，即可在專案目錄使用 `code .` 開啟 VS Code。若找不到指令，請重新執行安裝程式並確認已勾選加入 PATH。

## 建議設定與確認

- 只安裝課程或專案需要的擴充套件。
- 開啟陌生專案前先確認來源，再決定是否信任工作區。
- 使用 **Terminal → New Terminal** 開啟 PowerShell。
- 新增 `test.md`、儲存檔案並確認整合式終端機可正常輸入指令。

## 官方參考

- [Windows 安裝說明](https://code.visualstudio.com/docs/setup/windows)
- [VS Code 入門文件](https://code.visualstudio.com/docs/getstarted/getting-started)

[返回平台選擇](visual-studio-code.md) · [返回 README](../../README.md)
