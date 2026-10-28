# Day 05

| 形式 | 目安 | テーマ |
|---|---|---|
| A. 出力予測 | 5分 | `prepend` とメソッド探索順序 |
| B. コードレビュー | 7分 | 更新メソッド4種の違い |
| C. PRレビュー | 8分 | ActiveJob のリトライと冪等性 |

---

## A. 出力予測  `★★☆`

```ruby
module Loud
  def greet = super.upcase
end

class Person
  prepend Loud
  def greet = "hi"
end

class Student < Person
  def greet = "#{super}!"
end

p Student.new.greet
p Student.ancestors.take(4)
```

<details>
<summary>解答・解説</summary>

```
"HI!"
[Student, Loud, Person, Object]
```

### 仕組み: メソッド探索は `ancestors` を上から順に見る

Ruby はメソッドを呼ぶとき、レシーバのクラスの `ancestors` 配列を先頭から順に見て、最初に見つかった定義を実行します。`super` は「`ancestors` でいま実行中の定義より**後ろ**にある同名メソッド」を呼びます。

`include` と `prepend` の違いは、モジュールが `ancestors` のどこに入るかです。

| | `ancestors` 上の位置 | クラス自身のメソッドとの関係 |
|---|---|---|
| `include M` | クラスの**後ろ** | クラスのメソッドが優先。クラス側から `super` で M を呼べる |
| `prepend M` | クラスの**前** | M のメソッドが優先。M 側から `super` でクラスを呼べる |

今回の探索順は `Student → Loud → Person → Object` なので:

1. `Student#greet` が実行される。`super` で次を探す → `Loud#greet`
2. `Loud#greet` が実行される。`super` で次を探す → `Person#greet` が `"hi"` を返す
3. `Loud` が `"HI"` にして返す
4. `Student` が `"HI!"` にして返す

`prepend` が `Person` に書かれていても、`Student` の `ancestors` にも反映される点がポイントです。

### 確認方法

```ruby
Student.instance_method(:greet).owner          # => Student
Student.instance_method(:greet).super_method.owner   # => Loud
Student.instance_method(:greet).super_method.super_method.owner  # => Person
```

`Method#super_method` で `super` の行き先を辿れます。「どこで定義されたメソッドが呼ばれているのか分からない」ときは `method(:greet).source_location` も有効です。

### 実務でどこに出てくるか

- **gem のモンキーパッチ**: `ActiveRecord::Base.prepend(MyPatch)` のような形で既存メソッドをラップしている gem があります。挙動がおかしいとき、`ancestors` を見ると自分の知らないモジュールが挟まっていることがある
- **`ActiveSupport::Concern` の `prepended do`**: Rails 6.1 以降 Concern も `prepend` に対応
- **`alias_method_chain` の置き換え**: Rails 5 で非推奨になった `alias_method_chain` は、`prepend` + `super` で書き換えるのが推奨された経緯がある
- **`Module#refine`**: ファイル単位で限定的にメソッドを差し替える仕組み。`ancestors` には現れないが、`using` したファイル内では優先される

### 関連する罠

- `include` を2回しても `ancestors` には1回しか入らない。順序を変えようとして `include` し直しても効かない
- 特異クラス（`class << self` や `extend`）は `ancestors` のさらに手前にある。`obj.singleton_class.ancestors` で確認できる
- `super` に引数を書かないと「同じ引数をそのまま渡す」。`super()` と書くと引数なしで呼ぶ。`Loud#greet` の `super` は引数なしのメソッドなのでどちらでも同じだが、引数ありのメソッドをラップするときは違いが出る
</details>

---

## B. 違いを説明せよ  `★★☆`

次の4行は、どれも `user` の `name` を `"x"` に変える。それぞれについて「バリデーション」「コールバック」「`updated_at`」「発行される SQL」「`user` インスタンスの状態」の違いを説明してください。

```ruby
user.update(name: "x")
user.update_attribute(:name, "x")
user.update_column(:name, "x")
User.where(id: user.id).update_all(name: "x")
```

<details>
<summary>解答・解説</summary>

### 比較表

| メソッド | バリデーション | コールバック | `updated_at` | SQL | インスタンス |
|---|---|---|---|---|---|
| `update` | 実行 | 実行 | 更新 | `UPDATE`（変更カラムのみ） | 更新される |
| `update_attribute` | **スキップ** | 実行 | 更新 | `UPDATE` | 更新される |
| `update_column` | スキップ | **スキップ** | **更新しない** | `UPDATE`（指定カラムのみ） | 更新される（dirty 追跡なし） |
| `update_all` | スキップ | スキップ | 更新しない | `UPDATE ... WHERE` | **古いまま** |

### それぞれの仕組み

**`update`**: `assign_attributes` → `save` と同じ。`save` は `valid?` を呼び、失敗なら `false` を返して SQL を発行しません。成功ならトランザクションの中で `before_save` → `UPDATE` → `after_save` → `COMMIT` → `after_commit` と進みます。`updated_at` は `before_save` 相当のタイミングで自動セットされます。

**`update_attribute`**: `save(validate: false)` を呼びます。バリデーションだけ飛ばして、コールバックとタイムスタンプは通常どおり。「バリデーションに引っかかる古いデータを、とりあえず1カラムだけ直したい」ときに使われますが、他のカラムに dirty な変更があるとそれも一緒に保存される点に注意。

**`update_column(s)`**: `UPDATE users SET name = 'x' WHERE id = ?` を直接発行します。`save` を通らないのでバリデーション、コールバック、`updated_at` のすべてをスキップ。インスタンスの属性は書き換わりますが、`changed?` は false のままです。レコードが保存済みでない（`new_record?`）と `ActiveRecordError` を投げます。

**`update_all`**: Relation のメソッドで、インスタンスを経由しません。SQL を1本発行して終わりです。`user` オブジェクトは `name` が古いままなので、続けて `user.name` を使うと以前の値が返ります。`user.reload` が必要です。

### 実務での使い分け

| やりたいこと | 適切なメソッド |
|---|---|
| 通常の更新 | `update` / `update!` |
| カウンタや閲覧数など、コールバック不要で頻繁に更新するカラム | `update_column` / `increment!` |
| 大量レコードを一括で更新 | `update_all`（または `in_batches.update_all`） |
| バリデーションを飛ばしたい | まずバリデーション側を直す。どうしてもなら `update_attribute` だが、理由をコメントに残す |

### レビューで見るべき点

- `update_attribute` / `update_column` / `update_all` が出てきたら「なぜバリデーションやコールバックを避けたいのか」を確認する。コールバックが重い、ロック競合を避けたい、といった**意図的な最適化**と、`update` でエラーが出たので回避した、は全く違う
- `update_column` は `updated_at` を更新しないので、`cache_key_with_version`（`updated_at` を含む）が変わらず、**フラグメントキャッシュが古いまま**になる
- `update_all` の後に同じインスタンスを使い続けているコードは、古い値を見ている可能性がある
- `update_column` で `after_save` に書かれた副作用（検索インデックスの更新、通知）がスキップされ、データの整合性が崩れる

### 確認方法

```ruby
# rails console（開発環境、SQL ログが出る）
user = User.first
user.update_column(:name, "x")   # UPDATE 1本、updated_at は変わらない
user.changed?                    # => false
User.where(id: user.id).update_all(name: "y")
user.name                        # => "x"（古い）
user.reload.name                 # => "y"
```
</details>

---

## C. PRレビュー  `★★★`

PR タイトル: 「決済ジョブが一時的なエラーで落ちた場合にリトライするようにした」

```diff
 class ChargeOrderJob < ApplicationJob
   queue_as :payments
+  retry_on StandardError, wait: :polynomially_longer, attempts: 5

   def perform(order)
     result = PaymentGateway.charge!(amount: order.total, card: order.card_token)
     order.update!(paid: true, charge_id: result.id)
     OrderMailer.receipt(order).deliver_later
   end
 end
```

approve してよいですか。

<details>
<summary>解答・解説</summary>

### 判定: 差し戻し。リトライで二重課金が起きる

リトライ自体は正しい方向です。しかしこの `perform` は**冪等ではない**ので、リトライすると同じ注文に複数回課金します。

### 仕組み: どこで落ちると何が起きるか

`perform` の中には3つの処理があり、どこで例外が出るかで結果が変わります。

| 落ちる場所 | 課金 | DB | リトライ時に起きること |
|---|---|---|---|
| `charge!` の送信前（接続失敗） | されていない | 未更新 | 正常にリトライできる |
| `charge!` の**レスポンス待ちでタイムアウト** | **されている可能性あり** | 未更新 | **二重課金** |
| `charge!` 成功後、`update!` で失敗（DB 障害、バリデーション） | されている | 未更新 | **二重課金** |
| `deliver_later` で失敗（Redis 接続失敗など） | されている | 更新済み | 再度 `charge!` → **二重課金** |

`retry_on StandardError` は、これら全部を区別せずリトライします。特に「タイムアウトしたが決済側では成功していた」は、ネットワーク越しの処理では**必ず起きる**前提で設計する必要があります。

### 指摘事項

1. **冪等キーがない**: 決済 API の多くは冪等キー（Idempotency-Key）を受け取り、同じキーのリクエストは2回目以降、最初の結果を返す仕様になっています。注文 ID から決定的に生成したキーを渡せば、タイムアウト後のリトライでも二重課金されません。

2. **実行前の状態チェックがない**: `perform` の冒頭で `return if order.paid?` としておけば、「`update!` 後にメール送信で落ちた」ケースのリトライで課金をスキップできます。

3. **`StandardError` が広すぎる**: `ActiveRecord::RecordInvalid`（バリデーション失敗）や `PaymentGateway::CardDeclined`（カード拒否）は何度やっても失敗します。リトライすべきなのはネットワーク系（`Net::OpenTimeout`, `PaymentGateway::ConnectionError` など）だけです。恒久的なエラーは `discard_on` で捨てて、別途通知する方が適切です。

4. **`attempts: 5` を使い切った後の扱い**: 5回失敗したらジョブは例外を上げて終わり（Sidekiq なら Dead キューへ）。注文は未払いのまま放置されます。`retry_on` のブロックで失敗時の処理（注文を `failed` にする、管理者に通知）を書く必要があります。

5. **`perform(order)` でモデルを渡している**: GlobalID 経由で渡されるので、実行時に注文が削除されていると `ActiveJob::DeserializationError` になります。`order_id` を渡して `perform` 内で `find` する方が、エラーの発生場所が明確になります（どちらでも動くので軽微）。

### 修正例

```ruby
class ChargeOrderJob < ApplicationJob
  queue_as :payments
  retry_on PaymentGateway::ConnectionError, Net::OpenTimeout, Net::ReadTimeout,
           wait: :polynomially_longer, attempts: 5 do |job, error|
    order = Order.find(job.arguments.first)
    order.update!(payment_status: :failed)
    PaymentAlert.notify(order, error)
  end
  discard_on PaymentGateway::CardDeclined do |job, error|
    Order.find(job.arguments.first).update!(payment_status: :declined)
  end

  def perform(order_id)
    order = Order.find(order_id)
    return if order.paid?

    result = PaymentGateway.charge!(
      amount: order.total,
      card: order.card_token,
      idempotency_key: "order-#{order.id}"
    )
    order.update!(paid: true, charge_id: result.id)
    OrderMailer.receipt(order).deliver_later
  end
end
```

これでも「`charge!` 成功 → `update!` 失敗 → リトライで `charge!`」は起きますが、冪等キーにより決済側が同じ結果を返すので、実際の課金は1回です。

### 確認方法

- ジョブのテストで `PaymentGateway.charge!` が成功した**後に**例外を注入し、`perform` を2回呼んで `charge!` の呼び出し回数と `order.paid?` を確認する
- 決済 API のドキュメントで冪等キーの仕様（有効期限、同じキーで異なる金額を送った場合の挙動）を確認する

### 読解のコツ

`retry_on` / `rescue ... retry` / Sidekiq の `sidekiq_options retry:` を見たら、「この処理を**途中から**もう一度実行して安全か」を1ステップずつ確認してください。外部 API 呼び出し、メール送信、決済、在庫の減算は、何もしなければ冪等ではありません。
</details>
