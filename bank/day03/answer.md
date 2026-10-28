# Day 03 解答・解説

## A. 出力予測  `★★☆`

```
{1=>2, 2=>4}
{:a=>1}
```

### 仕組み

`Hash.new` には3つの形があります。

| 形 | 未知のキーを参照したとき | ハッシュに格納されるか |
|---|---|---|
| `Hash.new` | `nil` を返す | されない |
| `Hash.new(obj)` | `obj` を返す | **されない** |
| `Hash.new { \|h, k\| ... }` | ブロックの戻り値を返す | ブロック内で `h[k] = ...` した場合のみ |

**前半**: `h[1]` を参照した時点でブロックが走り、`hash[1] = 2` が実行されて格納されます。
`h[2] ||= 100` は `h[2] || (h[2] = 100)` に展開されます。左辺の `h[2]` を評価した時点でブロックが走って `4` が格納され、`4` は真なので右辺の代入は**行われません**。結果 `{1=>2, 2=>4}`。

**後半**: `Hash.new(0)` は未知のキーに対して `0` を返すだけで、格納はしません。
`g[:a] += 1` は `g[:a] = g[:a] + 1` なので、`0 + 1` の結果が格納されます。
`g[:b]` は `0` を返しますが代入がないので格納されず、`p g` には現れません。

### 確認方法

```ruby
g = Hash.new(0)
g[:x]          # => 0
g.key?(:x)     # => false
g.fetch(:x)    # => KeyError  （fetch はデフォルト値を無視する）
```

`key?` と `fetch` はデフォルト値の影響を受けないので、「本当に格納されているか」を確かめるのに使えます。

### 実務でどこに出てくるか

- **集計**: `counts = Hash.new(0); items.each { counts[item.kind] += 1 }` は定番。`tally` や `group_by` で置き換えられることも多い
- **グルーピング**: `groups = Hash.new { |h, k| h[k] = [] }; groups[key] << item`。ここで `Hash.new([])` と書くと Day 01 と同じ共有の罠にはまり、全キーが同じ配列を指す
- **メモ化**: `@cache = Hash.new { |h, n| h[n] = expensive(n) }` でフィボナッチのような再帰のメモ化に使える

### 関連する罠

- `Hash.new(0)` を JSON にしたり `to_a` したりしても、参照しただけのキーは出てこない。「画面には 0 と出ていたのに保存されない」という形で現れる
- デフォルト値付きハッシュに `h[k].nil?` で存在判定すると常に false になる。`key?` を使う
- `||=` は「nil か false のときだけ代入」。`0` や `""` は真なので代入されない（Ruby で偽は `nil` と `false` だけ）

---

## B. コードレビュー  `★★★`

### 指摘事項

1. **コミット前にメールのジョブが enqueue される**（データ整合性）
2. **外部 API 呼び出しがトランザクションの中にある**（ロック保持、課金と DB の不整合）
3. **`rescue` の範囲**: `ActiveRecord::RecordInvalid` は捕まえていない

### 仕組み: コールバックとトランザクションの順序

`Order.create!` を呼んだときの実行順はこうです。

```
BEGIN
  before_validation → validate → before_save → before_create
  INSERT INTO orders ...
  after_create  ← ここで deliver_later が走る
  after_save
COMMIT          ← after_commit はここ
```

`after_create` は `INSERT` の直後、**まだトランザクションの中**で実行されます。`deliver_later` はその時点でジョブをキューに積みます。続く `PaymentGateway.charge!` が例外を投げるとトランザクションはロールバックされ、`orders` の行は消えますが、**キューに積まれたジョブは消えません**。

結果として起きること:
- ジョブは `Order` を GlobalID で参照しているので、実行時に `ActiveJob::DeserializationError` になる（ロールバック済みのため）
- キューが速くて、ロールバック前にジョブが走ってしまった場合は、成立していない注文の確認メールが届く
- Sidekiq の場合はジョブ失敗がリトライされ続け、Dead キューに溜まる

修正は `after_create_commit`（`after_commit on: :create` の別名）です。コミット後にしか走らないので、ロールバックされた注文のメールは送られません。

```ruby
after_create_commit :send_confirmation_mail
```

**Rails 7.2 以降の注意**: `config.active_job.enqueue_after_transaction_commit` が導入され、設定次第でトランザクション内の `deliver_later` / `perform_later` がコミット後まで自動的に遅延されます。ただしアダプタとバージョンに依存する挙動なので、コードを読むだけで安全と判断せず、設定を確認してください。

### 外部 API をトランザクション内で呼ぶ問題

`PaymentGateway.charge!` が 5 秒かかれば、その間 `orders` の行ロック（と関連するインデックスのロック）が保持されます。同時に注文が集中すると DB のコネクションが枯渇します。

さらに厄介なのが「決済は成功したが、その後の `COMMIT` が失敗した」ケースです。課金だけが残り、注文レコードがない状態になります。逆に「決済 API がタイムアウトしたが実際には課金されていた」もあります。

決済と DB 更新の整合性は、トランザクションでは保証できません。一般的な設計:
1. 注文を `pending` 状態で**先にコミット**する
2. 決済 API を**トランザクション外**で呼ぶ。冪等キー（注文 ID）を渡して二重課金を防ぐ
3. 成功したら `paid` に更新。失敗したら `failed` に更新
4. 途中で落ちた `pending` を定期的に決済側へ照会して回収する

### `rescue` の範囲

`Order.create!` がバリデーションで失敗すると `ActiveRecord::RecordInvalid` が上がりますが、`rescue PaymentGateway::Error` では捕まらず 500 エラーになります。意図的かどうか、PR の説明で確認が必要です。

### 確認方法

テストで再現できます。

```ruby
it "決済失敗時に確認メールを送らない" do
  allow(PaymentGateway).to receive(:charge!).and_raise(PaymentGateway::Error)
  expect {
    post orders_path, params: { order: valid_params }
  }.not_to have_enqueued_mail(OrderMailer, :confirmation)
end
```

`after_create` のままだとこのテストは落ちます。ただし `use_transactional_fixtures` が有効なテストでは `after_commit` が走るタイミングに注意が必要です（Rails 5 以降はテスト内でも疑似的に `after_commit` が呼ばれます）。

### 読解のコツ

`transaction do ... end` を見たら2つ確認してください。
- (a) ブロック内で**外部通信**（HTTP、メール送信、ジョブ投入）をしていないか
- (b) ブロック内で保存されるモデルの**コールバック**に副作用（メール、ジョブ、外部 API、キャッシュ削除）がないか

(b) は diff の外にあるので、モデルファイルを開いて `after_save` / `after_create` を grep する習慣が必要です。

---

## C. PRレビュー  `★★★`

### 判定: 差し戻し。本番でサービス停止を引き起こす可能性が高い

変更内容自体は望ましい（外部キーカラムにはインデックスがあるべきだし、NULL を許す理由がないなら NOT NULL にすべき）。問題はその**やり方**です。

### 指摘事項

1. **`add_index` が書き込みをブロックする**
   PostgreSQL の通常の `CREATE INDEX` は、構築が終わるまでテーブルに **SHARE ロック**をかけます。読み取りはできますが `INSERT` / `UPDATE` / `DELETE` はすべて待たされます。3,000 万行なら数分から数十分かかり、その間、投稿の作成と更新が全部止まります。
   `algorithm: :concurrently` を付けると、書き込みを止めずにインデックスを作れます。ただし `CREATE INDEX CONCURRENTLY` はトランザクション内で実行できないので、マイグレーションクラスに `disable_ddl_transaction!` が必要です。

2. **`change_column_null` の前に NULL 行の確認がない**
   `user_id` が NULL の行が1行でもあると、`ALTER TABLE ... SET NOT NULL` は失敗し、マイグレーションが途中で止まります。しかも 1. と同じトランザクションなら、インデックスはロールバックされます。
   事前に `Post.where(user_id: nil).count` を確認し、あるなら「削除するのか、ダミーユーザーに付け替えるのか」を決めてデータ修正を先に出す必要があります。

3. **`SET NOT NULL` 自体のロック**
   `ALTER TABLE ... SET NOT NULL` は **ACCESS EXCLUSIVE ロック**を取り、全行をスキャンして NULL がないことを検証します。3,000 万行のスキャン中、読み取りも含めて全アクセスが止まります。
   PostgreSQL 12 以降では、先に `CHECK (user_id IS NOT NULL) NOT VALID` 制約を追加 → `VALIDATE CONSTRAINT`（こちらは弱いロック）→ `SET NOT NULL`（CHECK 制約があればスキャンを省略）の手順で、停止時間をほぼゼロにできます。Rails では `add_check_constraint ... validate: false` と `validate_check_constraint` で書けます。

4. **1つのマイグレーションに重い操作が2つ入っている**
   どちらかが失敗したときの切り分けとやり直しがしにくい。別マイグレーションに分けるのが無難です。

### 修正例

```ruby
# 1本目
class AddIndexToPostsUserId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :posts, :user_id, algorithm: :concurrently
  end
end

# 2本目（NULL 行の掃除をデプロイした後）
class AddNotNullToPostsUserId < ActiveRecord::Migration[7.1]
  def up
    add_check_constraint :posts, "user_id IS NOT NULL", name: "posts_user_id_null", validate: false
    validate_check_constraint :posts, name: "posts_user_id_null"
    change_column_null :posts, :user_id, false
    remove_check_constraint :posts, name: "posts_user_id_null"
  end

  def down
    change_column_null :posts, :user_id, true
  end
end
```

### 確認方法

- `strong_migrations` gem を入れると、この PR のマイグレーションは実行前にエラーで止まり、安全な書き方を提示してくれます。レビューの負担が大きく減るので導入を検討する価値があります
- ステージングに本番相当のデータ量があるなら、そこで `rails db:migrate` の所要時間を測る
- PostgreSQL の公式ドキュメント「ALTER TABLE」のロックレベルの表を一度読んでおくと、どの操作が危ないか判断できるようになります

### 読解のコツ

マイグレーションのレビューでは「正しいスキーマになるか」ではなく「**実行中に何が起きるか**」を考えます。見るべきは、対象テーブルの行数、取られるロックの種類、既存データが制約を満たしているか、の3つです。

