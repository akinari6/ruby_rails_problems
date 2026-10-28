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

<details>
<summary>解答・解説</summary>

```
[:int, :small, :digits, :enum, :other]
```

### 仕組み: `case/when` は `===` の糖衣構文

```ruby
case x
when A then ...
when B then ...
end
```

は、上から順に `A === x`、`B === x` を評価し、**最初に真になった節**を実行します。`===` は「`x` は `A` に該当するか」を各クラスが独自に定義しています。

| レシーバ | `===` の意味 | 例 |
|---|---|---|
| クラス / モジュール | `x.is_a?(self)` | `Integer === 5` → true |
| Range | `cover?(x)`（Ruby 2.6 以降） | `(1..10) === 5.0` → true |
| Regexp | `match?(x)`（`x` が文字列でなければ false） | `/\d/ === "12"` → true |
| Proc / lambda | `call(x)` | `->(v) { v > 0 } === 5` → true |
| その他 | `==` と同じ | `"a" === "a"` → true |

### 各要素の判定

- `5`: `Integer === 5` が true。`1..10` にも該当するが、**上の節で確定**するので `:int`
- `5.0`: Integer ではない。`(1..10) === 5.0` は `cover?` なので true → `:small`
- `"12"`: Integer でも Range でもない。正規表現がマッチ → `:digits`
- `[1]`: 正規表現は文字列以外に対して false。lambda が `respond_to?(:each)` で true → `:enum`
- `"ab"`: どれにも該当せず `:other`

### 確認方法

```ruby
Integer === 5        # => true
(1..10) === 5.0      # => true
/\A\d+\z/ === [1]    # => false（例外にはならない）
```

`when` の**順序を入れ替える**と結果が変わる点を試してみてください。`when 1..10` を先頭に持ってくると `5` は `:small` になります。

### 実務でどこに出てくるか

- `rescue` も同じ `===` で例外クラスを判定している。`rescue StandardError => e` は `StandardError === e`
- `Array#grep(pattern)` は `pattern === element` でフィルタする。`list.grep(Integer)` や `list.grep(/foo/)` と書ける
- Rails の `Rack::Request#path` に対するルーティング、`ActiveSupport::Duration` の比較など、`===` を独自定義しているクラスは多い
- Ruby 3 の**パターンマッチ**（`case/in`）は `===` に加えて構造の分解ができる。`case/when` と `case/in` は別物なので混同しない

### 関連する罠

- `when String, Symbol` はカンマ区切りで OR。`when [String, Symbol]` と書くと「配列 `[String, Symbol]` と `==` か」になり、ほぼ常に false
- `when nil` は `NilClass === x` ではなく `nil === x`（`==`）だが、結果は同じ
- `case` に引数を書かない形（`case; when x > 0 then ...`）は、各 `when` の式を真偽値として評価する。`if/elsif` の別記法
</details>

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

<details>
<summary>解答・解説</summary>

### 指摘事項

1. **SQL インジェクション（重大）**
2. **LIKE のワイルドカード（`%`, `_`）がエスケープされていない**
3. **上限なし**: `q` が空なら全ユーザーが返る
4. **大文字小文字**: DB によって `LIKE` の大文字小文字の扱いが違う

### 仕組み: 文字列補間は SQL に直接埋め込まれる

`"name LIKE '%#{params[:q]}%'"` は、Ruby の文字列補間が先に評価されてから ActiveRecord に渡されます。ActiveRecord から見ると単なる SQL 文字列なので、エスケープのしようがありません。

`params[:q]` に `' OR '1'='1` を入れると:

```sql
SELECT * FROM users WHERE name LIKE '%' OR '1'='1%'
```

となり、条件が常に真になります。`'; DROP TABLE users; --` のような複文は多くのアダプタで通りませんが、`UNION SELECT` で他テーブルを読み出す攻撃は成立します。

### 修正例

```ruby
def search
  q = params[:q].to_s.strip
  @users = if q.present?
             User.where("name LIKE ?", "%#{User.sanitize_sql_like(q)}%").limit(50)
           else
             User.none
           end
  render :index
end
```

- `where("name LIKE ?", value)`: `?` プレースホルダ形式。値はアダプタが適切にクォートする。`where("name LIKE :q", q: "...")` の名前付き形式もある
- `sanitize_sql_like`: `%` と `_` を `\%`, `\_` にエスケープする。これがないと `q = "%"` で全件一致、`q = "_"` で1文字の名前すべてに一致する
- `limit`: 検索結果に上限を付ける。実際にはページネーションにする
- `User.none`: 空の Relation を返す。`[]` と違って `.page` などをチェーンできる

### 大文字小文字

- PostgreSQL: `LIKE` は区別する。`ILIKE` で無視できる
- MySQL: 照合順序（collation）が `_ci` なら区別しない
- SQLite: ASCII 範囲のみ区別しない

本番とテストで DB が違うと挙動が変わるので、`ILIKE` を使うか `LOWER(name) LIKE LOWER(?)` で揃えます。後者はインデックスが効かないので、PostgreSQL なら `pg_trgm` 拡張と GIN インデックスを検討します。

### 確認方法

- `brakeman` は文字列補間を含む `where` を SQL Injection として検出する
- `rails console` で `User.where("name LIKE '%#{"' OR '1'='1"}%'").to_sql` を見ると、SQL が壊れているのが分かる
- `User.where("name LIKE ?", "%' OR '1'='1%").to_sql` と比べると、クォートされて無害化されているのが分かる

### 読解のコツ

`where` / `order` / `pluck` / `select` / `joins` / `having` の**文字列引数に `#{}` があったら即指摘**です。例外は定数や列名のホワイトリストから選んだ値だけで、それでもコメントで説明が必要です。特に `order("#{params[:sort]}")` は見落とされがちで、`order` は `?` プレースホルダが使えないので、許可する列名を明示的に比較する必要があります。
</details>

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

<details>
<summary>解答・解説</summary>

### 判定: 差し戻し。キャッシュが古くなるケースが2つある

速くなるのは本当ですが、**ユーザー名を変えても、コメントが増えても、画面が更新されない**バグを持ち込んでいます。

### 仕組み: `cache post` のキャッシュキー

`cache post do ... end` は、`post.cache_key_with_version` をキーにしてブロックの HTML を保存します。キーはこういう形です。

```
views/posts/_post:abc123/posts/42-20261028090000000000
```

- `abc123`: テンプレートの内容から計算されるダイジェスト。テンプレートを変えればキーが変わる
- `42`: `post.id`
- `20261028090000000000`: `post.updated_at`

つまりキャッシュが無効化されるのは **`post` 自身の `updated_at` が変わったとき**だけです。

### 指摘事項

1. **ユーザーが名前を変えてもキャッシュが残る**: `post.user.name` はブロック内で描画されていますが、キーには `user` の情報が含まれていません。ユーザーが名前を変更しても、`post.updated_at` は変わらないので古い名前が表示され続けます。

2. **コメントが増えてもキャッシュが残る**: `post.comments.size` も同じ理由で古いままです。`Comment` の `belongs_to :post` に `touch: true` がないので、コメント作成時に `post.updated_at` が更新されません。

3. **計測が正しくない可能性**: ステージングの 300ms → 40ms はキャッシュヒット時の数字です。キャッシュミス時（デプロイ直後、テンプレート変更後）は元のコードと同じく N+1 が走ります。キャッシュは N+1 の**解決にはならず**、頻度を下げるだけです。コントローラに `includes(:user, :comments)` は依然として必要です。

### 修正の選択肢

**選択肢 A: キャッシュキーに依存先を含める**

```erb
<% cache [post, post.user] do %>
```

配列を渡すと各要素の `cache_key_with_version` が連結されます。ユーザーの `updated_at` が変わればキーも変わります。コメント数は含められないので、2. は別途対処が必要です。

**選択肢 B: `touch: true` で親を更新する**

```ruby
class Comment < ApplicationRecord
  belongs_to :post, touch: true
end
```

コメントの作成・更新・削除時に `post.updated_at` を更新します。これで 2. は解決しますが、`User` → `Post` の方向には使えません（ユーザー名変更でそのユーザーの全投稿を `touch` するのは重すぎる）。

また `touch: true` は書き込みを増やし、`posts` 行のロック競合の原因になります。コメントが秒間数十件付く投稿では問題になることがあります。

**選択肢 C: counter cache を使い、キーに含める**

```ruby
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
end
```

`posts.comments_count` を更新するときに `updated_at` も更新されるので、キャッシュが無効化されます。ブロック内は `post.comments_count` に書き換えます。

### 修正例（A + C の組み合わせ）

```erb
<% cache [post, post.user] do %>
  <li>
    <%= post.title %> by <%= post.user.name %>
    (<%= post.comments_count %> comments)
  </li>
<% end %>
```

```ruby
# controller（キャッシュミス時の N+1 対策として残す）
@posts = Post.published.includes(:user).order(created_at: :desc).page(params[:page])
```

### 確認方法

- 開発環境で `rails dev:cache` を実行してキャッシュを有効にし、ユーザー名を変えてから一覧を再読み込みする
- ログに `Read fragment views/...` と `Write fragment views/...` が出るので、キーの形とヒット／ミスを確認できる

### 読解のコツ

`cache` ブロックを見たら、**ブロックの中で参照しているモデルをすべて列挙**し、それぞれが変わったときにキーが変わるかを1つずつ確認してください。キーに含まれていないモデルの属性が描画されていたら、それが stale になる経路です。
</details>
