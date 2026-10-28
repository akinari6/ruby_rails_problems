# Day 06

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | `case/when` と `===` |
| B. コードレビュー | 7分 | 検索機能と SQL インジェクション |
| C. PRレビュー | 8分 | フラグメントキャッシュとキャッシュキー |

---

## A. 出力予測  `★★☆`

```ruby
def kind(x)
  case x
  when Integer then :int
  when 1..10 then :small
  when /\A\d+\z/ then :digits
  when ->(v) { v.respond_to?(:each) } then :enum
  else :other
  end
end

p [5, 5.0, "12", [1], "ab"].map { kind(_1) }
```

---

## B. コードレビュー  `★★☆`

問題点をすべて挙げてください。

```ruby
class UsersController < ApplicationController
  def search
    @users = User.where("name LIKE '%#{params[:q]}%'")
    render :index
  end
end
```

---

## C. PRレビュー  `★★☆`

PR タイトル: 「投稿一覧の表示を高速化（フラグメントキャッシュ導入）」

```diff
 <ul>
   <% @posts.each do |post| %>
-    <li>
-      <%= post.title %> by <%= post.user.name %>
-      (<%= post.comments.size %> comments)
-    </li>
+    <% cache post do %>
+      <li>
+        <%= post.title %> by <%= post.user.name %>
+        (<%= post.comments.size %> comments)
+      </li>
+    <% end %>
   <% end %>
 </ul>
```

```ruby
# 参考: 既存のモデル（変更なし）
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments
end

class Comment < ApplicationRecord
  belongs_to :post
end
```

ステージングで計測したところ、レスポンスが 300ms から 40ms に改善したとのことです。approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
