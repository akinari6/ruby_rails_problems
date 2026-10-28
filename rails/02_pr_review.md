# Rails 02. PR レビュー — diff を読んで判断する

実際の PR のつもりで diff を読み、**approve してよいか／差し戻すならどこを直してもらうか**を書いてください。
「コードの正しさ」に加えて、「本番デプロイ時に何が起きるか」まで想像するのが目標です。

---

## Q1. メールアドレスの一意性  `★★★`

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

マイグレーションの変更はありません。

<details>
<summary>解答例</summary>

**判定: 差し戻し。** 修正の方向は正しいが、タイトルに書かれた問題を解決できていない。

1. **DB にユニークインデックスがない**: `uniqueness: true` は `SELECT ... WHERE email = ?` してから `INSERT` する、アプリケーション層のチェックに過ぎない。2つのリクエストが同時に来ると両方のチェックが通って重複が作られる。これはまさに PR が直そうとしている「重複登録」そのもの（OAuth のコールバックが二重に飛んでくるケースなど、実際に起きる）。`add_index :users, :email, unique: true` のマイグレーションが必要。
2. **既存の重複データ**: ユニークインデックスを張る前に、すでに重複している行をどう扱うか（統合するか、片方を消すか）を決めて、データ修正を先にデプロイする必要がある。インデックス追加のマイグレーションが本番で失敗する典型。
3. **`find_or_create_by_email` も競合する**: `find_by` → `create!` の間に別のリクエストが割り込める。ユニークインデックスがあれば `create!` が `ActiveRecord::RecordNotUnique` を投げるので、それを rescue して再度 `find_by` するか、`create_or_find_by` を使う。
4. **大文字小文字**: `Foo@example.com` と `foo@example.com` を同一視するか。`uniqueness: { case_sensitive: false }` と、DB 側では `LOWER(email)` への関数インデックスか `citext` 型（PostgreSQL）で揃える。保存前に `downcase` する `before_validation` を置くのも一般的。
5. 軽微: 既存の `find_or_create_by` と名前が紛らわしい。Rails 標準の `User.find_or_create_by(email: email)` で十分なら独自メソッドは不要。

**読解のコツ**: 「`validates ... uniqueness`」を見たら反射的に「対応するユニークインデックスはあるか」「既存データに重複はないか」を確認する。「マイグレーションの変更はありません」という一文は、ここでは警告として読む。
</details>
