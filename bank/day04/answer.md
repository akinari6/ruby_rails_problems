# Day 04 解答・解説

## A. 出力予測  `★★☆`

```
2
11
10
```

### 仕組み

Ruby の `return` は「**それを書いた場所を囲んでいるメソッド**から戻る」のが基本です。ブロックと `proc` はメソッドではないので、その中の `return` は外側のメソッドを抜けます。`lambda` だけが例外で、メソッドのように振る舞い、自分自身から戻ります。

| | `return` の挙動 | 引数の数 |
|---|---|---|
| ブロック | 定義元のメソッドから戻る | 緩い（足りなければ nil、多ければ無視） |
| `proc` / `Proc.new` | 定義元のメソッドから戻る | 緩い |
| `lambda` / `->` | lambda 自身から戻る | **厳密**（違えば `ArgumentError`） |

- `m1`: `each` のブロック内で `x = 2` のとき `return 2` が実行され、`m1` 全体がその場で終了。`:done` には到達しない
- `m2`: lambda の `return` は lambda から値を返すだけ。`r = 10`、戻り値は `11`
- `m3`: proc の `return` は `m3` から戻る。`r + 1` は実行されず、戻り値は `10`

### 確認方法

```ruby
pr = proc { return 1 }
pr.call   # => LocalJumpError (unexpected return)
```

メソッドの外で作った proc を `call` すると、「戻る先のメソッド」が存在しないので `LocalJumpError` になります。`lambda { return 1 }.call` は `1` を返します。`Proc#lambda?` で見分けられます。

### 実務でどこに出てくるか

- `each` の中で `return` を使って早期脱出するパターンは `m1` そのもの。`find` / `any?` / `break` で書けないか考える。`break` はブロックを抜けて `each` の呼び出し元（メソッド内）に戻るので、`return` とは戻る先が違う
- `scope :recent, -> { where(...) }` のような Rails の DSL は lambda。`scope :recent, proc { ... }` でも動くが `return` の意味が変わる
- `define_method(:foo) { return 1 }` のブロック内 `return` は、そのメソッド（foo）から戻る扱いになる。ブロックが「メソッド本体」に変換されるため

### 関連する罠

- `Proc.new` と `proc` は同じ。`lambda` と `->(x) { }` は同じ
- `&block` でメソッドに渡されたブロックは proc として扱われる。`block.call` 内の `return` はブロックを**書いた**メソッドから戻る（`yield` している側ではない）
- `next` はブロックから値を返して次の繰り返しへ。ブロック内で「この要素はスキップ」なら `next`、「ループを終わらせる」なら `break`、「メソッドごと終わらせる」なら `return`

---

## B. コードレビュー  `★★☆`

### 指摘事項

1. **`Date.today` はシステムのタイムゾーンで「今日」を決める**
2. **`to_s` した日付文字列を UTC の `created_at` と比較している**
3. **上限がない**（「今日」ではなく「今日以降」になっている）

### 仕組み: Rails には3つの「時刻」がある

| 層 | タイムゾーン | 例 |
|---|---|---|
| OS / Ruby の `Time.now`, `Date.today` | `TZ` 環境変数（本番では UTC が多い） | `Date.today` |
| Rails の `Time.zone` | `config.time_zone`（ここでは Tokyo） | `Time.current`, `Date.current`, `Time.zone.now` |
| DB に保存される値 | 常に UTC（`config.active_record.default_timezone` のデフォルト） | `created_at` |

ActiveRecord は `Time.zone` 付きの時刻オブジェクトを受け取ると、自動的に UTC に変換して SQL に埋め込みます。しかし**文字列**を渡すとそのまま埋め込むしかないので、変換は起きません。

### 何が起きるか

本番（OS が UTC）で日本時間 10/28 の朝 8:00 にこのメソッドを呼ぶと:
- `Date.today` は UTC の日付なので **10/27**
- `"2026-10-27"` と `created_at`（UTC）を比較するので、UTC 10/27 0:00 = 日本時間 10/27 9:00 以降の投稿が返る

日本時間 10/28 の 10:00 に呼ぶと:
- `Date.today` は 10/28、比較は UTC 10/28 0:00 = 日本時間 10/28 9:00 以降

つまり「今日の投稿」のつもりが、呼ぶ時刻によって範囲が変わり、しかも日本時間 0:00〜9:00 の投稿は常に含まれません。開発機（OS が JST）では再現しないので気付きにくい、典型的な本番だけのバグです。

### 修正例

```ruby
def self.todays_posts
  Post.where(created_at: Date.current.all_day)
end
```

- `Date.current` は `Time.zone.today`。Rails のタイムゾーン設定で「今日」を決める
- `all_day` は `beginning_of_day..end_of_day` の Range（`Time.zone` 付き）を返す
- Range を `where` に渡すと `BETWEEN` になり、ActiveRecord が UTC に変換する

発行される SQL:
```sql
WHERE created_at BETWEEN '2026-10-27 15:00:00' AND '2026-10-28 14:59:59.999999'
```

### 確認方法

```ruby
# rails console
Date.today      # OS の TZ
Date.current    # Rails の TZ
Time.now.zone   # => "UTC"
Time.current.zone  # => "JST"
```

`rubocop-rails` の `Rails/Date` と `Rails/TimeZone` cop が `Date.today` / `Time.now` を検出してくれます。導入していないプロジェクトなら、`grep -rn "Date.today\|Time.now\|DateTime.now" app/` で棚卸しする価値があります。

### 読解のコツ

- `Date.today`, `Time.now`, `DateTime.now`, `Time.parse` が出てきたら、`Date.current`, `Time.current`, `Time.zone.parse` に置き換えてよいか確認する
- `to_s` や `strftime` した日付を SQL に渡しているのも危険信号。時刻オブジェクトのまま渡す
- 「日付」の境界が絡む処理（日次集計、締め日、有効期限）は、JST 0:00〜9:00 のケースをテストに入れる

---

## C. PRレビュー  `★★★`

### 判定: 差し戻し。`default_scope` の影響範囲が広すぎる

論理削除の実装方針としては一般的で動きますが、`default_scope` はアプリ全体の `Post` へのクエリを**黙って**書き換えます。この PR の diff には現れない場所で挙動が変わるので、その洗い出しがされていない限り approve できません。

### `default_scope` が効く場所、効かない場所

**効く**（`deleted_at IS NULL` が付く）:
- `Post.find(id)`、`Post.where(...)`、`Post.count` などクラスから始まるクエリ
- `user.posts`（関連経由）
- `Post.where(...).update_all` / `delete_all`
- `comment.post` のような `belongs_to` の参照 → 削除済み投稿なら **nil** が返る

**効かない**:
- `Post.unscoped`
- **`validates :xxx, uniqueness: true`** の重複チェック（`unscoped` で検索するため、削除済みの投稿と同じ値は「重複」扱いになる）
- SQL を直接書いている箇所（`find_by_sql`、`connection.execute`）
- 他モデルからの `joins(:posts)`（JOIN 条件には付かない）

### 指摘事項

1. **管理画面や集計が黙って変わる**: 「削除済みも含めた全投稿数」を出していた管理画面、月次レポート、`Post.count` を使った監視などが、この PR で**削除済みを除外**するようになります。これが意図通りかは、全呼び出し元を見ないと判断できません。

2. **`comment.post` が nil になる**: 削除済み投稿に紐づくコメントから `comment.post.title` を呼ぶと `NoMethodError` になります。コメント一覧、通知、メールテンプレートなど、`belongs_to` 経由で投稿を参照している箇所がすべて影響を受けます。

3. **`unscoped` の罠**: 「削除済みも見たい」場所で `user.posts.unscoped` と書くと、`default_scope` だけでなく **`user_id = ?` の条件も消えて**全ユーザーの投稿が返ります。`unscoped` は全スコープを外すためです。正しくは `Post.unscoped.where(user: user)` か、`Post.unscoped { user.posts }` のブロック形式です。この罠は PR の後、別の人が踏みます。

4. **コメントはどうするか**: `has_many :comments, dependent: :destroy` のままなので、`soft_delete!` ではコメントは消えず、`destroy` が呼ばれる経路が残っていれば物理削除されます。論理削除を投稿だけに適用するのか、コメントにも伝播させるのか、仕様が決まっていません。

5. **復元の手段がない**: 論理削除の目的が「復元できること」なら `restore!` と、復元時の一意性（削除中に同じ slug で新規作成された場合など）を考える必要があります。

6. **`Post.new` に `deleted_at: nil` が入る**: 害はありませんが、`default_scope` の `where` 条件は新規オブジェクトの属性初期値になります。`default_scope { where(status: "draft") }` のようなものだと `create` の挙動に影響します。

### 代替案

`default_scope` を使わず、明示的なスコープにする。

```ruby
scope :kept, -> { where(deleted_at: nil) }
scope :discarded, -> { where.not(deleted_at: nil) }
```

一覧やユーザー向け画面では `Post.kept` を書く手間が増えますが、「どこで削除済みを除外しているか」が grep で追えます。`discard` gem はこの方針で、`default_scope` を使わないことを明示的に推奨しています。`paranoia` gem は `default_scope` を使う方針で、上に挙げた罠をそのまま抱えています。

### 確認方法

PR を approve する前に、最低限これを grep して影響を洗い出す。

```bash
grep -rn "Post\.\|\.post\b\|posts\." app/ lib/ --include=*.rb --include=*.erb | wc -l
```

件数が多いなら、`default_scope` の方針自体を見直す根拠になります。

### 読解のコツ

`default_scope` の追加は、diff 上は1行でも**そのモデルを参照するすべてのコードの変更**と同じです。「削除済みを含めるべき場所」を列挙できていない PR は差し戻してください。

