# Course 04－課堂用提示詞整理

來源：`class04/slides/slide.md`。本課投影片主要提供工具規格、運算規則與驗證問題。

## 租金計算規則

```text
基本租金 = 兩天一夜
加租日 = max(0, 租借天數 - 2)
租金總額 = 基本租金 + 每多一日價格 × 加租日
應付金額 = 租金總額 + 押金
```

## 商品工具規格

```text
get_products()
get_categories()
search_products(keyword)
get_product_detail(product_id)
get_products_by_category_name(category_name)
get_products_by_price_range(min_price, max_price)
calculate_rental_price(product_id, rental_days)
get_inventory_summary()
```

## 商品與費用驗證問題

```text
我預計 7/18 要去爬合歡山，想租輕量化的帳篷、背包跟睡袋，費用大概要多少？

The Two 輕量雙人帳租五天四夜多少錢？

我社團有 5 位下周要登山，要租三個雙人帳，請問有貨嗎？
```

## Policy RAG 流程要求

```text
使用者問題
→ 將問題轉 embedding
→ 與 policy_embeddings.json 逐筆計算 cosine similarity
→ 取出 top 3 相關 chunks
→ 交給 Agent 參考並禮貌回覆
```

# 其他連結
* [Plan:Google Sheet](./course04.plan.googlesheet.md)
