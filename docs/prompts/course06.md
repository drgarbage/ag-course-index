# Course 06－課堂用提示詞整理

來源：`class06/slides/slide.md`。

## Google Calendar 與聯絡人

```text
請幫我把 LINE 行動 AI 祕書整合 Google Calendar API 與 People API。

需求：
1. 使用 OAuth 讓使用者授權本機範例操作自己的 Google 日曆與聯絡人。
2. Calendar 工具要支援建立、查詢、修改、刪除行程，
   並支援參與者、地點與提醒時間。
3. People 工具要支援搜尋、建立、更新、刪除聯絡人。
4. 請建立 .env.example、README 設定步驟，
   並協助排查 API 未啟用、redirect URI 不符、
   scope 不足、token 過期等問題。
5. 尚未完成 Google 授權時，
   LINE 回覆要清楚提示，不要假裝已寫入真實資料。
```

## 多模態 LINE 輸入

```text
請幫我擴充 LINE 行動 AI 祕書，讓它能接收多種輸入。

需求：
1. 支援 LINE 的文字、照片、語音、影片、位置、檔案與 vCard 聯絡人分享。
2. 照片可能是名片、發票、收據或其他文件；
   請用 Gemini 判斷類型並抽出結構化欄位。
3. 語音要先整理逐字稿，再判斷使用者要記筆記、
   排行程、設定提醒、查聯絡人或記帳。
4. 位置訊息要保存 latitude / longitude，
   並可產生地圖連結。
5. 每種輸入都要回覆使用者「我辨識到什麼」，
   必要時用 Flex / Template 要求確認。
```

## LINE 回覆 UI

```text
請幫我擴充 LINE 行動 AI 祕書的回覆介面。

需求：
1. 依照回覆內容，自動選擇合適的 LINE UI：
   - 短摘要用 Text message
   - 清單或多筆資料用 Flex Message
   - 需要確認的動作用 Template / Buttons / Confirm
   - 常用下一步用 Quick reply
2. LINE UI 由 message JSON schema 控制，
   請產生正確的 message payload，
   不需要為每一種 UI 額外建立一個 AI 工具。
3. 能讓使用者點選完成的地方，就提供按鈕或 quick reply。
4. 像 /待辦、/我的、/說明 這種固定指令，
   直接由程式處理，不必送進 Gemini，
   以節省 token 並提升回覆速度。
```
