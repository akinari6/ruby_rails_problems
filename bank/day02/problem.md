# Day 02

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | 破壊的メソッドと参照、`equal?` |
| B. コードレビュー | 7分 | プロフィール更新と Strong Parameters |
| C. PRレビュー | 8分 | `dependent: :destroy` の追加 |

---

## A. 出力予測  `★☆☆`

```ruby
s = "abc"
t = s
t << "d"
u = s + "e"
p s, t, u
p s.equal?(t), s.equal?(u)
```

---

## B. コードレビュー  `★★☆`

問題点をすべて挙げてください。

```ruby
class UsersController < ApplicationController
  before_action :authenticate_user!

  def update
    @user = current_user
    if @user.update(user_params)
      redirect_to @user, notice: "更新しました"
    else
      render :edit
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :role)
  end
end
```

```ruby
class User < ApplicationRecord
  enum role: { member: 0, admin: 1 }
end
```

---

## C. PRレビュー  `★★☆`

PR タイトル: 「ユーザー削除時にコメントが残ってしまう問題を修正」

```diff
 class User < ApplicationRecord
-  has_many :comments
+  has_many :comments, dependent: :destroy
 end
```

```ruby
# 参考: 既存のコード
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post
  has_many :likes, dependent: :destroy
  after_destroy :decrement_post_comments_count
end
```

`comments` テーブルには約 500 万行、アクティブなユーザーは1人あたり最大数千件のコメントを持ちます。approve してよいですか。

---

回答が終わったら、この PR に `/answer` とコメントしてください。解答・解説がコメントで投稿され、PR がマージされます。
