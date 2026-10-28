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

<details>
<summary>解答・解説</summary>

```
"abcd"
"abcd"
"abcde"
true
false
```

### 仕組み

`t = s` は文字列をコピーしません。`s` が指しているオブジェクトへの参照を `t` にも持たせるだけです。`<<` はレシーバの文字列を**その場で**延長する破壊的メソッドなので、`s` から見ても `"abcd"` になります。

`+` はレシーバを変更せず、連結した**新しい文字列**を返します。`u` は別オブジェクトです。

### 3種類の等価性

| メソッド | 意味 | 例 |
|---|---|---|
| `equal?` | 同一オブジェクトか（`object_id` が同じ） | `"a".equal?("a")` → false |
| `==` | 値として等しいか | `1 == 1.0` → true |
| `eql?` | 値も型も等しいか（Hash のキー比較に使われる） | `1.eql?(1.0)` → false |

`equal?` は上書きしてはいけないメソッドとされています。`==` は各クラスが定義し、ActiveRecord では「同じクラスで同じ `id`」なら true になります。

### 確認方法

```ruby
s = "abc"; t = s
s.object_id == t.object_id   # => true
s.frozen?                    # => false（マジックコメントがなければ）
```

### 実務でどこに出てくるか

- `name = user.name; name << " (admin)"` のように、モデルの属性を受け取った変数に `<<` すると**モデル側の属性も変わる**。`user.name` は同じ文字列オブジェクトを返すため。`user.changed?` が true になって意図しない `UPDATE` が走ることもある
- Rails アプリの多くのファイルには `# frozen_string_literal: true` があり、リテラル由来の文字列は凍結されている。この場合 `t << "d"` は `FrozenError` になる。`+""` や `dup` で解凍したコピーを作ってから操作する
- `String#+` をループで繰り返すと毎回新しいオブジェクトが作られる。大量連結なら `<<` か `Array#join` が速い

### 関連する罠

- 破壊的メソッドには `!` が付くとは限らない（`<<`, `concat`, `push`, `delete`, `clear`, `[]=` は `!` なしで破壊的）。逆に `!` が付いていても「破壊的」ではなく「変更がなければ nil を返す」の意味のものがある（`strip!`, `sub!`）
- `Symbol` と `Integer` は常に同一オブジェクト（`:a.equal?(:a)` → true）。`String` は違う
</details>

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

<details>
<summary>解答・解説</summary>

### 指摘事項

1. **権限昇格（重大）**: `:role` を permit しているので、一般ユーザーが `user[role]=admin` をリクエストに混ぜるだけで自分を管理者にできる
2. **Turbo との相性**: `render :edit` に `status: :unprocessable_entity` がないと、Turbo Drive 有効時にバリデーションエラー画面が表示されない
3. 業務要件次第: メールアドレス変更時の確認メール、ログイン中セッションの扱い

### 仕組み: Strong Parameters が守ってくれる範囲

Strong Parameters は「**どのキーを**モデルに渡してよいか」をホワイトリストで宣言する仕組みです。`permit` に書いたキーは、フォームに項目があるかどうかに関係なく、HTTP リクエストに含まれていれば通ります。ブラウザの開発者ツールで hidden input を追加するか、curl で送れば済みます。

```bash
curl -X PATCH https://example.com/users/1 \
  -d "user[name]=me" -d "user[role]=admin" -b "session=..."
```

「**誰が**そのキーを変更してよいか」は Strong Parameters の責務外で、コントローラ側で判断が必要です。

### 修正例

管理者だけが変えられるカラムは、params メソッドを分けるのが定石です。

```ruby
def user_params
  permitted = [:name, :email]
  permitted << :role if current_user.admin?
  params.require(:user).permit(*permitted)
end
```

ただし「管理者が自分の role を member に落とせてしまう」といった別問題が残るので、役割変更は管理画面の専用アクション（`Admin::UserRolesController#update`）に分離し、一般ユーザーの `update` からは完全に外す方が安全です。

### Turbo と `status:`

Rails 7 以降の Turbo Drive は、フォーム送信のレスポンスが **200 OK** だと「成功した」とみなしてページを置き換えません（リダイレクトを期待している）。バリデーションエラーでフォームを再描画するときは `422 Unprocessable Entity` を返す必要があります。

```ruby
render :edit, status: :unprocessable_entity
```

`rails g scaffold` が生成するコードもこの形になっています。古い記事をコピーしたコードや、Rails 6 から上げたアプリでよく抜けています。

### 確認方法

- `rails routes` で `users#update` のパスを確認し、開発環境で `curl` に `role=admin` を混ぜて送ってみる
- `brakeman` を走らせると Mass Assignment の警告として検出されることがある（`role` や `admin` という名前は特に見ている）

### 読解のコツ

`permit(...)` のリストに、権限・課金・状態・所有者を表すカラムが含まれていたら赤信号です。

- 権限: `role`, `admin`, `permissions`
- 課金: `plan`, `credits`, `price`
- 状態: `status`, `approved`, `published_at`
- 所有者: `user_id`, `account_id`, `organization_id`

これらが「フォームに項目がないから大丈夫」と説明されていたら、それは大丈夫ではありません。
</details>

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

<details>
<summary>解答・解説</summary>

### 判定: 条件付きで差し戻し。「何を解決したいか」と「削除の規模」の確認が必要

この1行は正しく動きますが、本番で動かしたときに何が起きるかを PR の説明が考慮していません。

### `dependent:` の選択肢と挙動

| オプション | 挙動 | コールバック | クエリ数 |
|---|---|---|---|
| `:destroy` | 子を1件ずつロードして `destroy` | 実行される | 子の数だけ `DELETE`（さらに孫の分も） |
| `:delete_all` | `DELETE FROM comments WHERE user_id = ?` を1本 | **実行されない** | 1 |
| `:nullify` | `user_id` を NULL に更新 | 実行されない | 1 |
| `:restrict_with_exception` | 子がいれば `ActiveRecord::DeleteRestrictionError` | - | 1（存在確認） |
| `:restrict_with_error` | 子がいれば `errors` に追加して削除失敗 | - | 1 |
| `:destroy_async` (6.1+) | ActiveJob で非同期に `destroy` | 実行される | ジョブ内で `:destroy` と同じ |

### 指摘事項

1. **削除のコストが読めていない**: 数千件のコメントを持つユーザーを `destroy` すると、コメント数千件のロード、それぞれの `likes` の削除、`after_destroy` の実行が**1つのトランザクション内で**走ります。リクエスト内で実行するとタイムアウトし、しかもトランザクションが長いので `comments` / `posts`（`decrement_post_comments_count` で更新）の行ロックが長時間保持されます。
   `dependent: :destroy_async` にしてバックグラウンドで実行するか、ユーザー削除自体をジョブ化するのが現実的です。

2. **`:delete_all` にできない理由を確認する**: `Comment` には `has_many :likes, dependent: :destroy` と `after_destroy` があるので、`:delete_all` にすると likes が孤児になり、`comments_count` が狂います。つまりこの PR で `:destroy` を選んだのは正しい。ただしレビューでは「`:delete_all` では駄目な理由」が説明に書かれているべきです。

3. **DB の外部キーとの関係**: `comments.user_id` に外部キー制約があるなら、変更前はユーザー削除時に `ActiveRecord::InvalidForeignKey` が出ていたはずで、「コメントが残る」という症状とは一致しません。外部キーがないなら、`add_foreign_key :comments, :users` を追加するかどうかも論点になります。外部キーに `on_delete: :cascade` を付ければ DB 側で一括削除できますが、Rails のコールバックは走らないので今回のケースでは使えません。

4. **既存の孤児レコード**: この PR は「これから削除されるユーザー」にしか効きません。すでに `user_id` が存在しないユーザーを指しているコメントの掃除は別途必要です。

5. **そもそも物理削除でよいか**: コメントが他ユーザーの投稿に付いているなら、ユーザーを消してもコメントは「退会したユーザー」として残す（`nullify` か論理削除）という仕様もあり得ます。これは実装の問題ではなく仕様確認です。

### 修正例

```ruby
class User < ApplicationRecord
  has_many :comments, dependent: :destroy_async
end
```

`destroy_async` は `ActiveRecord::DestroyAssociationAsyncJob` をキューに入れ、ジョブ内で子を `destroy` します。親の削除は即座に完了し、子の削除はキューに任せます。`config.active_record.destroy_association_async_batch_size` でバッチサイズを調整できます（7.1 以降）。

### 読解のコツ

`dependent:` の変更は1行でも、「削除対象の数 × 子のコールバック × 孫の関連」の掛け算で実行コストが決まります。diff の外にある子モデルの定義とテーブルの規模を必ず見に行ってください。
</details>
