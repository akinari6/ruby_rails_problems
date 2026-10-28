# Day 05

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | `prepend` とメソッド探索順序 |
| B. コードレビュー | 7分 | 更新メソッド4種の違い |
| C. PRレビュー | 8分 | ActiveJob のリトライと冪等性 |

---

## A. 出力予測  `★★☆`

```ruby
module Loud
  def greet = super.upcase
end

class Person
  prepend Loud
  def greet = "hi"
end

class Student < Person
  def greet = "#{super}!"
end

p Student.new.greet
p Student.ancestors.take(4)
```

---

## B. 違いを説明せよ  `★★☆`

次の4行は、どれも `user` の `name` を `"x"` に変える。それぞれについて「バリデーション」「コールバック」「`updated_at`」「発行される SQL」「`user` インスタンスの状態」の違いを説明してください。

```ruby
user.update(name: "x")
user.update_attribute(:name, "x")
user.update_column(:name, "x")
User.where(id: user.id).update_all(name: "x")
```

---

## C. PRレビュー  `★★★`

PR タイトル: 「決済ジョブが一時的なエラーで落ちた場合にリトライするようにした」

```diff
 class ChargeOrderJob < ApplicationJob
   queue_as :payments
+  retry_on StandardError, wait: :polynomially_longer, attempts: 5

   def perform(order)
     result = PaymentGateway.charge!(amount: order.total, card: order.card_token)
     order.update!(paid: true, charge_id: result.id)
     OrderMailer.receipt(order).deliver_later
   end
 end
```

approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
