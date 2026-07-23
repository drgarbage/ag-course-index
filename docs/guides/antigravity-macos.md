# Antigravity 2.0 與 Antigravity IDE：macOS 安裝指引

## 安裝前準備

- 個人 Gmail 帳號（參考 [Google 帳號註冊指引](google-account.md)）
- Chrome 瀏覽器
- 安裝軟體的系統權限
- 確認 Mac 使用 Apple 晶片或 Intel 處理器：選擇 Apple 選單 ** → 關於這台 Mac** 查看

## 安裝步驟

1. 前往 [Antigravity 官方下載頁](https://antigravity.google/download)。
2. 選擇 Antigravity 或 Antigravity IDE，下載符合 Mac 處理器的版本。
3. 開啟下載檔，將應用程式拖入「應用程式」資料夾。
4. 從「應用程式」啟動；若 macOS 阻擋開啟，請確認檔案來自官網，再到 **系統設定 → 隱私權與安全性** 選擇允許開啟。
5. 若已安裝 Antigravity，也可從應用程式右上角選擇 **Install IDE**。
6. 使用個人 Google 帳號登入並選擇佈景主題。
7. 初次設定代理程式權限時，建議選擇 **Review-driven development**。
8. 只安裝課程需要的擴充套件與外掛。

## 繁體中文化支援

本課程的一鍵安裝器提供了開發環境與 Antigravity 2.0 桌面版的繁體中文化：
- **語言包擴充功能**：自動中文化 VS Code 與 Antigravity IDE 的開發介面。
- **ASAR 注入修補檔**：基於安全釘選的 Commit 程式碼，將 Antigravity 桌面程式的主選單、設定與狀態匣切換成繁體中文。
- 詳細使用指引請參考 [macOS 課程環境一鍵安裝器指引](course-toolchain-macos.md)。

## 安裝確認

1. 開啟一個測試資料夾。
2. 從選單開啟新終端機，確認 zsh 可正常使用。
3. 建立並儲存一個測試檔案。
4. 從代理面板送出簡短問題，確認登入與網路連線正常。

## 安全提醒

- 執行代理程式提出的終端機指令前，先確認內容及影響範圍。
- 不要把密碼、API 金鑰或 `.env` 內容貼進對話。
- 僅開啟來源可信的專案，並保留人工審查設定。

## 官方參考

- [Antigravity 下載頁](https://antigravity.google/download)
- [Antigravity IDE 官方入門教學](https://codelabs.developers.google.com/getting-started-agy-ide?hl=zh-tw)

[返回平台選擇](antigravity.md) · [返回 README](../../README.md)
