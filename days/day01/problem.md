# Day 01

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | `Array.new` の第2引数とブロック |
| B. コードレビュー | 7分 | 投稿一覧の N+1 |
| C. PRレビュー | 8分 | uniqueness バリデーションとユニークインデックス |

---

## A. 出力予測  `★☆☆`

```ruby
a = Array.new(3, [])
a[0] << 1
p a

b = Array.new(3) { [] }
b[0] << 1
p b
```

---

## B. コードレビュー  `★☆☆`

問題点をすべて挙げてください。

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.where(published: true).order(created_at: :desc)
  end
end
```

```erb
<ul>
  <% @posts.each do |post| %>
    <li>
      <%= post.title %> by <%= post.user.name %>
      (<%= post.comments.count %> comments)
    </li>
  <% end %>
</ul>
```

---

## C. PRレビュー  `★★★`

PR タイトル: 「同じメールアドレスでユーザーが重複登録できる問題を修正」

```diff
 class User < ApplicationRecord
-  validates :email, presence: true
+  validates :email, presence: true, uniqueness: true
+
+  def self.find_or_create_by_email(email)
+    find_by(email: email) || create!(email: email)
+  end
 end
```

```diff
 class SessionsController < ApplicationController
   def create
     auth = request.env["omniauth.auth"]
-    user = User.find_by(email: auth.info.email) || User.create!(email: auth.info.email)
+    user = User.find_or_create_by_email(auth.info.email)
     session[:user_id] = user.id
     redirect_to root_path
   end
 end
```

マイグレーションの変更はありません。approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
