# Day 07

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | ブロックのスコープとクロージャ |
| B. コードレビュー | 7分 | 全件更新のバッチ処理 |
| C. PRレビュー | 8分 | `after_commit` と dirty tracking |

---

## A. 出力予測  `★★★`

```ruby
x = 10
[1, 2].each { |i| x += i }

y = 10
[1, 2].each { |i; y| y = i }

p x, y

def counter
  count = 0
  increment = -> { count += 1 }
  get = -> { count }
  [increment, get]
end

inc, get = counter
inc.call
inc.call
p get.call
```

---

## B. コードレビュー  `★★☆`

問題点をすべて挙げてください。これは本番で1回実行する予定の rake タスクで、`users` テーブルは約 200 万行です。

```ruby
namespace :users do
  desc "全ユーザーのスコアを再計算する"
  task recalculate_scores: :environment do
    User.all.each do |user|
      user.update(score: ScoreCalculator.new(user).calculate)
    end
    puts "done"
  end
end
```

---

## C. PRレビュー  `★★★`

PR タイトル: 「メールアドレス変更時に旧アドレスへ通知メールを送る」

```diff
 class User < ApplicationRecord
   validates :email, presence: true, uniqueness: true
+
+  after_commit :notify_email_change
+
+  private
+
+  def notify_email_change
+    return unless email_changed?
+
+    UserMailer.email_changed(self, email_was).deliver_later
+  end
 end
```

テストは含まれていません。PR の説明には「rails console で `update!` して動作確認済み」とあります。

approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
