# Course 07－課堂用提示詞整理

來源：`class07/slides/slide.md`。

## 🛠️ 開發環境 Skill 安裝指引

本單元實作建議安裝以下 Agent Skills，以協助 AI 自動化開發與防止常見 SDK 錯誤：

* **gemini-agent-dev-support**: 防止常見 Gemini API 調用與金鑰洩漏錯誤。
* **free-live-dev**: 自動化開發、憑證收集與預覽部署協同工具。

在你的專案根目錄下，開啟終端機並執行以下指令完成安裝：

```bash
# 專案本地安裝 (推薦)
npx skills add https://github.com/drgarbage/ag-course-index --skill gemini-agent-dev-support
npx skills add https://github.com/drgarbage/ag-course-index --skill free-live-dev

# 或全域安裝 (套用至所有專案)
npx skills add https://github.com/drgarbage/ag-course-index --skill gemini-agent-dev-support -g
npx skills add https://github.com/drgarbage/ag-course-index --skill free-live-dev -g
```

---


## 採購比價助手 RFP

```text
請建立一個「採購比價助手」。

使用者輸入商品需求、數量、預算與必要規格後，
系統要協助搜尋公開網頁上的候選供應商與價格資訊，
整理成比較表，並產生採購建議報告。

報告必須包含：
1. 規格對齊檢查
2. 價格與總成本估算
3. 供應商可信度評分
4. 前三名推薦與不推薦理由
5. 資料來源、查詢時間與限制聲明

如果資料不足，請列出需要人工確認的問題，
不要自行假裝已取得報價。
```

## 到手成本規則

```text
到手成本 / 片 =
  商品單價
+ 打樣費或版費 / 數量
+ 國際運費 / 數量
+ 稅費與平台手續費 / 數量
+ 匯率與金流成本
```
