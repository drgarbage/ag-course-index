---
name: gemini-api-dev
description: 使用 Gemini API 開發或更新文字、多模態、函式呼叫與結構化輸出功能時，查詢最新官方文件並採用現行 SDK 與模型。
---

# Gemini API 開發

## 原則

1. 先使用 Gemini Docs MCP 的 `search_documentation`（若實際提供的工具名稱是 `search_docs`，則使用該工具）查詢相關官方文件，再設計或修改程式。
2. MCP 無法使用時，從 `https://ai.google.dev/gemini-api/docs/llms.txt` 尋找並讀取相關官方文件。
3. 以查詢結果為準選擇目前可用的模型、API 與參數；不要只憑既有知識猜測，也不要自行捏造名稱。
4. 使用現行 Google Gen AI SDK：Python 為 `google-genai`，JavaScript／TypeScript 為 `@google/genai`。除非專案相容性明確要求，不使用舊版 `google-generativeai` 或 `@google/generative-ai`。
5. 延續現有專案的語言、套件管理方式、程式風格與錯誤處理；密鑰只從環境變數或既有的祕密管理機制讀取，不寫入原始碼。

## 工作流程

1. 先讀取專案相關檔案與依賴版本。
2. 查詢此次功能所需的最新官方文件與範例。
3. 說明將採用的模型、SDK 與主要 API；若選擇會影響成本、速度或品質，簡短交代理由。
4. 實作最小且完整的變更，並加入必要的錯誤處理。
5. 執行適合的測試或最小驗證；若無法執行，清楚說明未驗證之處。

## 專用情境

若需求是即時雙向音訊、影片或文字串流，應改用專門的 Gemini Live API skill（若已安裝），並同樣先查詢官方文件。
