# Day 04

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | ブロック・lambda・proc の `return` |
| B. コードレビュー | 7分 | 日付とタイムゾーン |
| C. PRレビュー | 8分 | `default_scope` による論理削除 |

---

## A. 出力予測  `★★☆`

```ruby
def m1
  [1, 2, 3].each { |x| return x if x > 1 }
  :done
end

def m2
  l = lambda { |x| return x * 2 }
  r = l.call(5)
  r + 1
end

def m3
  pr = proc { |x| return x * 2 }
  r = pr.call(5)
  r + 1
end

p m1, m2, m3
```

---

## B. コードレビュー  `★★☆`

問題点をすべて挙げてください。`config/application.rb` には `config.time_zone = "Tokyo"` が設定されており、本番サーバーの OS タイムゾーンは UTC です。

```ruby
class DailyReport
  def self.todays_posts
    Post.where("created_at >= ?", Date.today.to_s)
  end
end
```

---

## C. PRレビュー  `★★★`

PR タイトル: 「投稿の論理削除に対応」

```diff
 class Post < ApplicationRecord
   belongs_to :user
   has_many :comments, dependent: :destroy
+
+  default_scope { where(deleted_at: nil) }
+
+  def soft_delete!
+    update!(deleted_at: Time.current)
+  end
 end
```

```diff
 class PostsController < ApplicationController
   def destroy
-    @post.destroy
+    @post.soft_delete!
     redirect_to posts_path
   end
 end
```

`deleted_at` カラムを追加するマイグレーションは含まれています。approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
