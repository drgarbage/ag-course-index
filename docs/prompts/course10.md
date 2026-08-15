# Course 10－課堂用提示詞整理

## 前往 [官方範例](https://github.com/drgarbage/gemini-live-api-examples)

```
幫我 clone 並安裝執行範例 gemini-live-genai-python-sdk
https://github.com/drgarbage/gemini-live-api-examples.git
```

## 🛠️ 開發環境 Skill 安裝指引

本單元實作建議安裝以下 Agent Skills，以協助 AI 自動化開發與防止常見 SDK 錯誤：

* **gemini-agent-dev-support**: 防止常見 Gemini API 調用與金鑰洩漏錯誤
* **ai-agent-ui-support**: 規範 Agent 聊天介面
* **live-dev-init**: 預檢與環境初始化
* **live-dev-storage-init**: Firebase與Firestore資料庫配置 (若需要Firestore)
* **live-dev-config**: GitHub與Vercel專案配置與憑證安全收集
* **live-dev-deploy**: 本機自動測試、自癒與 Git Flow 部署發行

在你的專案根目錄下，開啟終端機並執行以下指令完成安裝：

```bash
# 專案本地安裝 (推薦)
npx skills add drgarbage/ag-course-index --skill gemini-agent-dev-support
npx skills add drgarbage/ag-course-index --skill ai-agent-ui-support
npx skills add drgarbage/ag-course-index --skill live-dev-init
npx skills add drgarbage/ag-course-index --skill live-dev-storage-init
npx skills add drgarbage/ag-course-index --skill live-dev-config
npx skills add drgarbage/ag-course-index --skill live-dev-deploy
npx skills add affaan-m/ECC --skill frontend-design-direction
```

## 通用螢幕協作 Agent

```text
/grill-me /gemini-live-api-dev

請進入 Plan Mode，先不要直接寫程式。

# 設計一個「通用螢幕協作 Agent」。

我希望她像一位長期合作的工作夥伴：
當我正在查資料、閱讀文件、寫企劃、整理專案，或與 AI 工具討論時，
她可以理解我目前正在看的畫面與工作脈絡。

我可以用文字或語音叫她：
- 幫我記下這個結論
- 翻譯這段英文
- 把目前討論整理成 memo
- 幫我查一下這個資料
- 把這段補到專案紀錄

她應該在低干涉的情況下提供協助：
平時主畫面最小化到背景 (使用者自己控制)，
以 PIP Window & Web Notification 這類方式提供資訊，
當需要檢視紀錄時才自行切換回完整主畫面。

## 請先幫我整理：
1. 使用者流程
2. UI 狀態
3. memo note 資料格式
4. 可使用的 Workspace 資料來源
5. 需要哪些 AI 能力
6. 驗收清單

## 限制：
- 先規劃，不要直接寫程式
- 以課堂可實作的範圍為主
- 保留文字輸入作為語音輸入備援
- memo note 要能保存截圖、摘要、翻譯、標籤、待辦與使用者備註
- 最後要能整理成 Markdown 工作摘要
- 現為 2026 年 8 月，規劃前應先查閱 gemini 最新文件，使用最新模型，不應依賴訓練記憶，應先確認模型是否已停止服務。
- 禁止 Mock 機制，禁止模擬數據、禁止模擬 API 存取，一律以真實存取實作，無法使用時應顯示錯誤訊息。
- 禁止提供 fallback 模型，固定模型列表

## 技術選擇
- Document PIP Window, Always on Top, <iframe allow-scripts allow-same-origin />
- @google/genai, gemini-3.1-flash-live-preview, ai.live.connect( ... )
- Memo CRUD, Card View + Memo Editor + Markdown View & Plan-text Editor
```
