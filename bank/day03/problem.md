# Day 03

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | `Hash.new` のデフォルト値と `||=` |
| B. コードレビュー | 7分 | トランザクション内のコールバックと外部 API |
| C. PRレビュー | 8分 | インデックス追加と NOT NULL 制約のマイグレーション |

---

## A. 出力予測  `★★☆`

```ruby
h = Hash.new { |hash, k| hash[k] = k * 2 }
h[1]
h[2] ||= 100
p h

g = Hash.new(0)
g[:a] += 1
g[:b]
p g
```

---

## B. コードレビュー  `★★★`

問題点をすべて挙げてください。

```ruby
class Order < ApplicationRecord
  after_create :send_confirmation_mail

  private

  def send_confirmation_mail
    OrderMailer.confirmation(self).deliver_later
  end
end

class OrdersController < ApplicationController
  def create
    Order.transaction do
      @order = Order.create!(order_params)
      PaymentGateway.charge!(@order)  # 決済失敗時は例外を投げる
    end
    redirect_to @order
  rescue PaymentGateway::Error
    redirect_to new_order_path, alert: "決済に失敗しました"
  end
end
```

---

## C. PRレビュー  `★★★`

PR タイトル: 「posts.user_id にインデックスと NOT NULL 制約を追加」

```diff
+class AddIndexAndNotNullToPostsUserId < ActiveRecord::Migration[7.1]
+  def change
+    add_index :posts, :user_id
+    change_column_null :posts, :user_id, false
+  end
+end
```

DB は PostgreSQL、`posts` テーブルは約 3,000 万行、サービスは 24 時間稼働です。approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
