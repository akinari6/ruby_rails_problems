# Day 01 解答・解説

## A. 出力予測  `★☆☆`

```
[[1], [1], [1]]
[[1], [], []]
```

### 仕組み

`Array.new(size, obj)` は「`obj` を `size` 個並べた配列」を作りますが、`obj` は**コピーされず同じオブジェクトが共有**されます。Ruby の変数や配列の要素はすべてオブジェクトへの参照であり、`Array.new` は渡された参照をそのまま3回格納しているだけです。

`a[0] << 1` は `a[0]` が指す配列を**その場で**書き換える（破壊的メソッド）ので、同じ配列を指している `a[1]`, `a[2]` から見ても変わって見えます。

一方 `Array.new(size) { block }` はブロックを `size` 回評価し、その**戻り値**を格納します。`[]` は評価のたびに新しい配列オブジェクトを生成するリテラルなので、3つは別物になります。

### 確認方法

```ruby
a = Array.new(3, [])
a.map(&:object_id).uniq.size   # => 1  （全部同じオブジェクト）
b = Array.new(3) { [] }
b.map(&:object_id).uniq.size   # => 3
```

`object_id` か `equal?` で同一性を見るのが一番確実です。

### 実務でどこに出てくるか

- `Hash.new([])` / `Hash.new({})` で「キーごとのリスト」を作ろうとして、全キーが同じ配列を共有してしまう（Day 03 の A と同根）
- `Array.new(n, "")` に `<<` で文字列を足していく処理
- `def initialize(items = [])` のデフォルト引数は**呼び出しごとに評価される**ので安全。Python とは違う点として覚えておくと混乱しない

### 関連する罠

- `dup` は浅いコピー。`Array.new(3, []).dup` しても中の配列は共有されたまま。深いコピーには `Marshal.load(Marshal.dump(obj))` か、要素ごとに `map(&:dup)`
- 文字列リテラル `""` も評価ごとに新しいオブジェクト。ただし `# frozen_string_literal: true` があると同じリテラルは同じ凍結オブジェクトになり、`<<` は `FrozenError`

---

## B. コードレビュー  `★☆☆`

### 指摘事項

1. **N+1（`post.user`）**: 投稿が100件なら `SELECT * FROM users WHERE id = ?` が100回飛ぶ
2. **N+1（`post.comments.count`）**: `count` は呼ぶたびに `SELECT COUNT(*) FROM comments WHERE post_id = ?` を発行する。`includes` していても `count` は SQL を発行する点に注意
3. **ページネーションがない**: published の投稿が増えるほどメモリとレスポンスタイムが線形に悪化する
4. 軽微: `where(published: true)` はモデルの `scope :published` にした方が再利用しやすく、意図が読みやすい

### 仕組み: なぜ N+1 が起きるか

ActiveRecord の関連（`belongs_to :user`）は**遅延ロード**です。`post.user` を初めて呼んだ時点でそのレコードを取りに行き、投稿ごとに別々のクエリになります。`@posts` を取るクエリの時点では users テーブルには触れていません。

`includes(:user)` を付けると、投稿を取った直後に `SELECT * FROM users WHERE id IN (...)` を**1回**だけ発行し、各 `post.user` にあらかじめ紐付けておきます（preload）。`includes` は条件次第で JOIN に切り替わる（eager_load）ので、挙動を固定したいときは `preload` / `eager_load` を明示します。

### `count` / `size` / `length` の違い

| メソッド | ロード済みでない場合 | ロード済みの場合 |
|---|---|---|
| `count` | `SELECT COUNT(*)` | それでも `SELECT COUNT(*)` を発行 |
| `size` | `SELECT COUNT(*)` | ロード済み配列の要素数（SQL なし） |
| `length` | **全件ロードしてから**数える | 要素数 |

したがって `includes(:comments)` した上で `post.comments.size` と書けば、追加の SQL は発生しません。コメント本文まで読み込むのが無駄なら、`comments_count` カラムを持つ **counter cache**（`belongs_to :post, counter_cache: true`）が本命です。

### 修正例

```ruby
# app/models/post.rb
scope :published, -> { where(published: true) }

# controller
@posts = Post.published
             .includes(:user)
             .order(created_at: :desc)
             .page(params[:page])   # kaminari の場合
```

```erb
(<%= post.comments_count %> comments)  <%# counter cache を使う場合 %>
```

### 確認方法

- 開発環境のログで同じ形の `SELECT` が連続していないか見る。`config.active_record.verbose_query_logs = true` にするとクエリを発行したコードの行が出る
- `bullet` gem を入れると N+1 とその逆（不要な `includes`）を警告してくれる
- Rails 6.1 以降は `Post.strict_loading` / `config.active_record.strict_loading_by_default` で、遅延ロードを例外にできる

### 読解のコツ

ビューの `each` の中に `.` が2つ以上つながる式（`post.user.name`）や集計（`count`, `sum`, `exists?`）があったら、まず「このループで SQL は何回飛ぶか」を数える癖をつけてください。

---

## C. PRレビュー  `★★★`

### 判定: 差し戻し

修正の方向は正しいが、**PR タイトルに書かれた問題を解決できていない**。

### 指摘事項

1. **DB にユニークインデックスがない**
   `validates :email, uniqueness: true` がやっているのは、保存前に `SELECT 1 FROM users WHERE email = ? LIMIT 1` を発行して、見つからなければ `INSERT` する、という**アプリケーション層のチェック**です。2つのリクエストがほぼ同時に来ると、両方の `SELECT` が「存在しない」を返し、両方の `INSERT` が成功します。
   OAuth のコールバックはユーザーのダブルクリックやリトライで二重に飛んでくることがあり、「重複登録」はまさにこの経路で起きます。この PR は発生頻度を下げるだけで、根本解決にはなりません。
   `add_index :users, :email, unique: true` のマイグレーションが必須です。

2. **既存の重複データの扱いが決まっていない**
   すでに重複している行があると、ユニークインデックスを張るマイグレーションは本番で失敗します。「どちらを残すか」「紐づくデータを統合するか」を決めて、データ修正を**先に**デプロイしてからインデックスを張る、という手順が必要です。

3. **`find_or_create_by_email` 自体も競合する**
   `find_by` と `create!` の間に別リクエストが割り込める点は、変更前と同じです。ユニークインデックスがあれば2つ目の `create!` は `ActiveRecord::RecordNotUnique` を投げるので、それを rescue して再度 `find_by` するか、Rails 6 以降の `create_or_find_by` を使います。

   ```ruby
   User.create_or_find_by(email: email)   # INSERT を先に試み、ユニーク違反なら SELECT
   ```

4. **大文字小文字の扱い**
   `Foo@example.com` と `foo@example.com` を同一視するかが決まっていません。同一視するなら、アプリ側は `uniqueness: { case_sensitive: false }`、DB 側は `LOWER(email)` への関数インデックス（PostgreSQL）か `citext` 型で揃えます。保存前に `before_validation { email&.downcase! }` で正規化してしまうのが運用上は楽です。

5. 軽微: Rails 標準の `User.find_or_create_by(email: email)` と名前が紛らわしい。独自メソッドにする理由がないなら標準を使う。

### 修正例（マイグレーション）

```ruby
class AddUniqueIndexToUsersEmail < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!   # PostgreSQL で concurrently を使う場合に必要

  def change
    add_index :users, :email, unique: true, algorithm: :concurrently
  end
end
```

`algorithm: :concurrently` を付けないと、インデックス構築中は書き込みがブロックされます（Day 03 の C で扱います）。

### 読解のコツ

- `validates ... uniqueness` を見たら反射的に「対応するユニークインデックスはあるか」「既存データに重複はないか」を確認する
- 「マイグレーションの変更はありません」という一文は、モデルの制約を触る PR では警告として読む
- `find_by || create` のパターンは常に競合の可能性がある。ユニーク制約 + `RecordNotUnique` の rescue、または `create_or_find_by` に置き換えられないか考える

