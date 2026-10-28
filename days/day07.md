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

<details>
<summary>解答・解説</summary>

```
13
10
2
```

### 仕組み: ブロックは外側のローカル変数を「参照」で捕捉する

ブロック（および proc / lambda）は、作られた時点のスコープにあるローカル変数を**値のコピーではなく変数そのもの**として捕捉します。これをクロージャと呼びます。

- **前半 `x`**: ブロック内の `x += i` は外側の `x` を直接書き換える。`10 + 1 + 2 = 13`
- **`y`**: `|i; y|` のセミコロンより後ろは**ブロックローカル変数**の宣言。外側に同名の変数があっても、ブロック内では別の変数として扱われる。外側の `y` は `10` のまま
- **`counter`**: 2つの lambda は同じスコープで作られたので、**同じ `count` 変数**を共有している。`counter` メソッドが終わっても変数は lambda から参照されている限り生き続ける。`inc` を2回呼ぶと `count` は `2` になり、`get` もそれを見ている

### `def` との違い

```ruby
x = 10
def show = x    # NameError: undefined local variable or method `x'
```

`def` は新しいスコープを**切る**ので、外側のローカル変数が見えません。`define_method(:show) { x }` ならブロックなので見えます。この違いが、Rails の `scope`、`delegate`、`has_many` などの DSL（内部で `define_method` や `class_eval` を使っている）を読むときに効いてきます。

| 構文 | 外側のローカル変数 |
|---|---|
| `def` | 見えない |
| `class` / `module` | 見えない |
| ブロック、`proc`、`lambda` | 見える |
| `define_method` + ブロック | 見える |
| `Class.new do ... end` | 見える |
| `instance_eval` / `class_eval` + ブロック | 見える（`self` は変わる） |

### 確認方法

```ruby
x = 1
blk = proc { x }
x = 2
blk.call   # => 2（コピーではなく参照なので、後から変えた値が見える）

blk.binding.local_variables   # => [:x, :blk]
```

`Proc#binding` でブロックが捕捉しているスコープを覗けます。

### 実務でどこに出てくるか

- **ループ内で lambda を作る**: `handlers = []; [1,2,3].each { |i| handlers << -> { i } }` は各 lambda が別の `i`（ブロック引数は呼び出しごとに新しい変数）を持つので `[1, 2, 3]`。しかし `i = nil; [1,2,3].each { |j| i = j; handlers << -> { i } }` と書くと全部 `3` になる
- **メモリリーク**: 大きなオブジェクトを参照しているスコープで作った lambda を長く持つと、そのオブジェクトが GC されない。Rails のイニシャライザで `config.after_initialize { ... }` に大きなデータを閉じ込めるとプロセスの起動後ずっと残る
- **`ActiveSupport::Callbacks`**: `before_action -> { ... }` の lambda はコントローラの `instance_exec` で実行されるので、`self` はコントローラになる。ただし捕捉したローカル変数も見える

### 関連する罠

- ブロック引数 `|i|` が外側の変数と同名でも、ブロック引数は常に新しい変数（Ruby 1.9 以降）。外側は書き換わらない。警告 `shadowing outer local variable` が出ることがある
- ブロック内で初めて代入した変数は、ブロックの外では見えない。`[1].each { z = 1 }; z` は `NameError`
- `1.times { x = 5 }` のつもりで外側の `x` を書き換えたいなら、外側で先に `x = nil` などと宣言しておく必要がある
</details>

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

<details>
<summary>解答・解説</summary>

### 指摘事項

1. **`User.all.each` が全件をメモリにロードする**
2. **`update` の失敗が無視される**
3. **1件ごとにトランザクションとコールバックが走る**
4. **途中で落ちたときに再開できない、進捗が分からない**
5. **`ScoreCalculator` が内部で発行するクエリ（N+1）**

### 仕組み: `each` と `find_each` の違い

`User.all.each` は、`User.all` が Relation なので、`each` を呼んだ時点で `SELECT * FROM users` を発行し、**200 万件すべて**を ActiveRecord オブジェクトとして生成してから繰り返します。1オブジェクトが 1KB 程度でも 2GB で、メモリ不足でプロセスが落ちるか、スワップで極端に遅くなります。

`find_each` は内部で `find_in_batches` を使い、デフォルト 1,000 件ずつ `WHERE id > ? ORDER BY id LIMIT 1000` で取り出します。メモリ使用量はバッチサイズで頭打ちになります。

```ruby
User.find_each(batch_size: 1000) do |user|
  ...
end
```

`find_each` の注意点:
- 主キー順に処理される。`order` を付けても無視される（警告が出る）
- 処理中に他プロセスが行を追加・削除しても、主キー基準なので取りこぼしや二重処理は起きにくい
- `in_batches` を使うと Relation 単位で受け取れるので、`in_batches.update_all(...)` のような SQL 一括更新ができる

### `update` の戻り値

`update` はバリデーションに失敗すると `false` を返すだけで、例外を投げません。このタスクは失敗を一切記録しないので、「done」と出ても何件が更新されていないか分かりません。`update!` にして例外で止めるか、失敗した ID をログに残して続行するかは要件次第ですが、どちらかは必要です。

### コールバックとトランザクション

`update` は1件ごとに `BEGIN` → `UPDATE` → `COMMIT` を発行します。200 万回のトランザクションはそれだけで時間がかかり、さらに `User` に `after_save` で検索インデックス更新やキャッシュ削除があると、その回数分だけ実行されます。スコアの更新だけが目的で副作用が不要なら `update_column`、スコアが SQL で計算できるなら `in_batches.update_all` が桁違いに速くなります。

ただし「コールバックを飛ばしてよいか」は、`User` モデルを開いて確認が必要です（Day 05 の B を参照）。

### 再開可能性と進捗

200 万件の処理は数時間かかる可能性があります。途中でネットワーク断やデプロイで落ちたとき、最初からやり直すのは避けたい。

- 最後に処理した `id` をログに出し、`start: id` 引数で再開できるようにする
- 1,000 件ごとに進捗を出力する
- 可能なら「再計算が必要なユーザー」を絞り込む条件を付けて対象を減らす

### `ScoreCalculator` の中身

`ScoreCalculator.new(user).calculate` が `user.posts.count` や `user.comments.sum(:likes)` のようなクエリを発行しているなら、200 万 × クエリ数の SQL が飛びます。`find_each` に `includes` を付けるか、集計を SQL 側でまとめて行うか、計算クラスの中身を見ないと判断できません。

### 修正例

```ruby
task :recalculate_scores, [:start_id] => :environment do |_t, args|
  scope = User.where("id >= ?", args[:start_id].to_i)
  failed = []

  scope.find_each(batch_size: 1000).with_index do |user, i|
    score = ScoreCalculator.new(user).calculate
    user.update_column(:score, score)   # コールバック不要と確認済みの場合
  rescue => e
    failed << user.id
    Rails.logger.error("recalculate_scores: user=#{user.id} #{e.class}: #{e.message}")
  ensure
    puts "processed #{i + 1} (last id: #{user.id})" if (i + 1) % 1000 == 0
  end

  puts "done. failed: #{failed.size} #{failed.first(20).inspect}"
end
```

### 確認方法

- ステージングで対象件数を絞って（`User.limit(10_000)`）実行し、1件あたりの所要時間とメモリを計測する。200 万件分に換算して許容できるか判断する
- 開発環境で `User.all.each { break }` と `User.find_each { break }` の SQL ログを比較する

### 読解のコツ

rake タスクやジョブで `Model.all.each` / `Model.where(...).each` / `Model.all.map` を見たら、まず対象件数を確認し、`find_each` に置き換えられないか考えます。次に、ループの中の1件あたりの SQL 発行数と、`update` 系メソッドの戻り値の扱いを見ます。
</details>

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

<details>
<summary>解答・解説</summary>

### 判定: 差し戻し。本番では通知が1通も送られない

テストが通っているのに本番で動かない、というタイプの問題です。

### 仕組み: dirty tracking のライフサイクル

ActiveRecord は属性の変更を追跡していて、`save` の**前後**で見えるものが変わります。

| 時点 | `email_changed?` | `email_was` | `saved_change_to_email?` | `email_before_last_save` |
|---|---|---|---|---|
| `user.email = "new"` の直後 | true | `"old"` | false | nil |
| `before_save` / `before_update` | true | `"old"` | false | nil |
| **`after_save` / `after_update`** | **false** | `"new"` | true | `"old"` |
| **`after_commit`** | **false** | `"new"` | true | `"old"` |
| 次の `save` の後 | false | - | false（リセット） | - |

`save` が成功した瞬間に `changes_applied` が呼ばれ、「変更中」の情報は「直前の保存で変更された」情報（`saved_changes`）に移されます。`after_save` 以降で `email_changed?` は常に false です。

### 「console で確認済み」をどう読むか

`after_commit` の中で `email_changed?` が true になることはないので、console で本当に `update!` → `deliver_later` の enqueue を確認したのなら、このコードは動いていないはずです。考えられるのは次のどれかです。

- `user.email = "x"` のあと、保存**前**に `user.send(:notify_email_change)` を直接呼んで確認した（この時点では `email_changed?` は true）
- 確認したのは別のブランチ、または `after_save` で書いていた時点のコード
- enqueue されたことを確認せず、例外が出なかったことを「動いた」と解釈した

いずれにせよ、**「動作確認済み」は証拠にならない**ので、テストで検証します。この PR に書くべきテストは後述しますが、素直に書いたテストは落ちるはずです。

### 指摘事項

1. **`email_changed?` → `saved_change_to_email?`** に、**`email_was` → `email_before_last_save`** に直す
2. **`after_commit` は作成時にも走る**: `on:` を指定しない `after_commit` は create / update / destroy のすべてで呼ばれます。ユーザー登録時には `saved_change_to_email?` が true（nil → 値）なので、「変更通知」が新規登録の瞬間に飛びます。`after_update_commit`（`after_commit on: :update`）にする
3. **`deliver_later` の引数**: `email_was` の値（文字列）を渡しているのは正しい。`self` は GlobalID で渡され、ジョブ実行時に再ロードされるので、その時点での `email` は新しい方になる。旧アドレスを文字列で渡す必要があるという判断は合っている
4. **`saved_changes` は直前の `save` 1回分しか持たない**: トランザクション内で `user.update!(email: "a")` → `user.update!(name: "b")` と2回保存すると、`after_commit` の時点では2回目の `saved_changes` しか見えず、メール変更が検知されません。頻度は低いが知っておくべき挙動
5. テストがない。「変更時に送る」「作成時には送らない」「他の属性の変更では送らない」の3つが最低限必要

### 修正例

```ruby
after_update_commit :notify_email_change, if: :saved_change_to_email?

private

def notify_email_change
  UserMailer.email_changed(self, email_before_last_save).deliver_later
end
```

```ruby
it "メール変更時に旧アドレスへ通知する" do
  user = create(:user, email: "old@example.com")
  expect {
    user.update!(email: "new@example.com")
  }.to have_enqueued_mail(UserMailer, :email_changed).with(user, "old@example.com")
end

it "作成時には通知しない" do
  expect { create(:user) }.not_to have_enqueued_mail(UserMailer, :email_changed)
end

it "他の属性の変更では通知しない" do
  user = create(:user)
  expect { user.update!(name: "x") }.not_to have_enqueued_mail(UserMailer, :email_changed)
end
```

### 確認方法

```ruby
# rails console
u = User.first
u.email = "x@example.com"
u.email_changed?            # => true
u.save!
u.email_changed?            # => false
u.saved_change_to_email?    # => true
u.email_before_last_save    # => 元の値
```

### 読解のコツ

`after_save` / `after_commit` の中に `xxx_changed?` / `xxx_was` / `changes` があったら、ほぼ確実にバグです。`saved_change_to_xxx?` / `xxx_before_last_save` / `saved_changes` に読み替えてください。逆に `before_save` の中で `saved_change_to_xxx?` を使っていたら、それは**前回**の保存の情報を見ています。
</details>
