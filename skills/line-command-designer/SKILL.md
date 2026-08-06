---
name: line-command-designer
description: 當使用者想新增或調整 LINE 機器人的操作入口——例如新功能要怎麼觸發、要不要做選單、圖文選單（Rich Menu）長怎樣——時使用這個 skill。負責評估文字指令、Quick Reply、Buttons 樣板、圖文選單（Rich Menu）之間的取捨，並協助設計與產生 6/9 宮格圖文選單。使用者沒有明確指定做法時，也要主動判斷並提出建議。
---

# LINE 互動入口設計師

你的任務是幫使用者決定「怎麼觸發一個新功能」，而不是直接動手寫功能邏輯本身（功能邏輯完成後的訊息呈現方式交給 `line-ui-designer`，是否該做成固定指令交給 `line-interact-planner` 評估）。

## 決策框架：四種觸發機制怎麼選

| 機制 | 適合情境 | 限制 |
| --- | --- | --- |
| **文字指令 `/xxx`** | 高頻、重複、使用者已經記得怎麼打字的操作；也是最省 token 的做法（可以完全不經過 Gemini） | 使用者要記得指令；建議搭配 Quick Reply 讓使用者「看得到、點得到」，不用背 |
| **Quick Reply（快速回覆按鈕）** | 針對「剛剛這則訊息」延伸出的下一步選項，用完即丟 | 最多 13 顆、label ≤ 20 字、只跟著單一則訊息出現 |
| **Buttons / Confirm 樣板** | 單一訊息內的少量固定選項（≤4 顆）、或破壞性操作前的是非確認 | 選項少、無法有大圖文並茂的版面 |
| **圖文選單（Rich Menu）** | App 常駐的主導覽、品牌識別、幫新手快速找到「有哪些功能」 | 一次只能顯示一組（可切換）、需要一張圖 |

判斷順序建議：
1. 這是「使用者剛看到某訊息後的下一步」嗎？→ Quick Reply。
2. 這是「不管在哪個對話情境都想隨時叫出來」的常駐功能，而且功能項目 ≤ 9 個、值得占用聊天室下方空間？→ 圖文選單。
3. 這是「高頻、固定、有明確語法」的操作，且你已經（或打算）幫它做成快捷指令？→ 文字指令 `/xxx`，並確保它有出現在某個 Quick Reply 或圖文選單裡讓使用者發現。
4. 都不是、選項不多且跟當前訊息綁定？→ Buttons 或 Confirm 樣板。

沒有把握時，**同時提供文字指令 + Quick Reply**（指令給熟手，按鈕給新手）通常是最保險的預設值。

## 圖文選單（Rich Menu）設計與產生流程

LINE 圖文選單圖片固定兩種尺寸：
- 大圖：2500 x 1686 px（常見）
- 小圖（可收合）：2500 x 843 px

專案內已提供兩個現成的 6 宮格 / 9 宮格版型與自動化上架腳本，設計新選單時照以下步驟走：

1. **釐清需求**：跟使用者確認要放哪幾個功能、優先順序（左上角通常是最常用的）、每格要對應的文字指令或 postback。
2. **選版型**：
   - 6 個以內功能 → 用 [`templates/richmenu/6grid.json`](../../../templates/richmenu/6grid.json)（2 列 x 3 欄）
   - 7~9 個功能 → 用 [`templates/richmenu/9grid.json`](../../../templates/richmenu/9grid.json)（3 列 x 3 欄）
   - 超過 9 個 → 考慮拆成多個 Rich Menu，用 `richmenu switch` action 讓使用者切換分頁（第一格放「更多」）
   - 複製一份版型 JSON，把每個 `area.action` 的 `label`／`text`（或改成 `postback` action）換成實際功能與對應指令。座標不用改，已經按 2500x1686 切好格線。
3. **生成選單圖片**：優先詢問使用者是否已有設計素材／品牌風格；沒有的話，使用 Gemini 圖片生成模型（`@google/genai`，模型如 `gemini-3-pro-image-preview` / `gemini-3.1-flash-image-preview`，專案已內建此套件，不需要額外安裝）依每一格的功能名稱與圖示需求生成一張完整的選單底圖，尺寸需精準對齊版型（2500x1686 或 2500x843），每一格內文字/圖示要清楚對齊格線，避免字被切到格線邊界。
4. **上架**：使用專案內建的 CLI 腳本，不用手動打 API：
   ```bash
   node scripts/richmenu.js create <你的config.json> <你的圖片路徑> --default
   ```
   其他常用指令：
   ```bash
   node scripts/richmenu.js list                       # 列出現有選單
   node scripts/richmenu.js set-default <richMenuId>    # 設為所有人預設看到的選單
   node scripts/richmenu.js link <richMenuId> <userId>  # 只給特定使用者（例如做分眾測試）
   node scripts/richmenu.js delete <richMenuId>         # 刪除
   ```
5. **驗證**：提醒使用者在手機 LINE 重新打開聊天室（圖文選單有快取，有時需要重新整理聊天室或稍等一下才會刷新）。

## 主動建議原則

使用者只講「我想加一個 XX 功能」而沒提互動方式時：
1. 先用上面的決策框架**自己判斷**最適合的機制，簡短說明理由（1~2 句即可，不用長篇分析）。
2. 直接依建議動手實作，而不是丟一堆選項讓使用者選——除非機制之間的取捨真的很兩難才需要用 `AskUserQuestion` 詢問。
3. 實作時盡量重用 `lib/lineMessages.js` 既有的 `quickReply`／`buttonsMessage`／`confirmMessage` 等 helper，維持專案風格一致。
