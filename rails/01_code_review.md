# Rails 01. コードレビュー — Controller / Model の落とし穴

各問題のコードを読み、**問題点をすべて列挙**してください。
「動くかどうか」だけでなく、パフォーマンス・セキュリティ・データ整合性・Rails の規約の観点で見ます。
解答例には観点を複数挙げているので、自分が何個拾えたかを数えてください。

---

## Q1. 投稿一覧  `★☆☆`

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

<details>
<summary>解答例</summary>

1. **N+1（user）**: `post.user` が投稿ごとに `SELECT users ...` を発行する。`includes(:user)` か `preload(:user)` で解決。
2. **N+1（comments.count）**: `count` は毎回 `SELECT COUNT(*)` を発行する。`includes(:comments)` した上で `size` を使うか、`comments_count` の counter cache を持たせる。`length` はロード済みなら SQL を発行しないが未ロードなら全件取得するので、`size` が無難。
3. **ページネーションがない**: published が増えるほど全件ロードになる。`kaminari` / `pagy` などで区切る。
4. 軽微: `where(published: true)` はスコープ `Post.published` に切り出した方が再利用しやすい。

**読解のコツ**: ビューで `each` の中に関連や集計があったら、まず「クエリ数は何回か」を数える癖をつける。`count` / `size` / `length` / `exists?` / `any?` はそれぞれ SQL の発行タイミングが違う。
</details>

---

## Q2. プロフィール更新  `★★☆`

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
<summary>解答例</summary>

1. **権限昇格**: `:role` を permit しているので、一般ユーザーがフォームを細工して `user[role]=admin` を送れば自分を admin にできる。Strong Parameters は「どのカラムを許可するか」の責務であって、「誰が変更してよいか」はコントローラ側で判断が必要。管理者専用の別アクション／別 params メソッドに分けるのが定石。
2. **Turbo との相性**: Rails 7 以降（Turbo Drive 有効）では `render :edit` に `status: :unprocessable_entity` を付けないと、バリデーションエラー時にフォームが再描画されない。
3. 軽微: `email` 変更時の再確認（確認メール）や、変更後のセッション扱いなど、業務要件によっては別途考慮。

**読解のコツ**: `permit(...)` のリストに権限・課金・状態に関わるカラム（`role`, `admin`, `plan`, `status`, `user_id`）が含まれていたら赤信号。
</details>

---

## Q3. 注文作成とコールバック  `★★★`

```ruby
class Order < ApplicationRecord
  after_create :send_confirmation_mail

  private

  def send_confirmation_mail
    OrderMailer.confirmation(self).deliver_later
  end
end

class OrdersController < ApplicationController
  def create
    Order.transaction do
      @order = Order.create!(order_params)
      PaymentGateway.charge!(@order)  # 決済失敗時は例外を投げる
    end
    redirect_to @order
  rescue PaymentGateway::Error
    redirect_to new_order_path, alert: "決済に失敗しました"
  end
end
```

<details>
<summary>解答例</summary>

1. **コミット前にジョブが enqueue される**: `after_create` はトランザクションの**中**で動く。`deliver_later` はその時点でジョブキューに積まれるので、決済失敗でロールバックしても確認メールのジョブは残る。ジョブ実行時には `Order` が存在せず `ActiveJob::DeserializationError`、あるいは（ロールバックが間に合わなければ）注文が成立していないのに確認メールが届く。`after_create_commit`（`after_commit on: :create`）を使う。
   - Rails 7.2 以降は ActiveJob の `enqueue_after_transaction_commit` 設定で緩和されるが、デフォルト設定と Rails バージョンに依存するので、コードだけでは安全と言い切れない。
2. **外部 API 呼び出しをトランザクション内で行っている**: `PaymentGateway.charge!` が遅いと DB ロックを長時間保持する。さらに「決済は成功したが DB のコミットに失敗」のケースでは課金だけ残る。決済と DB 更新の整合性は別の設計（決済 ID を先に保存、冪等キー、Outbox）が必要。
3. **`rescue` の範囲**: `Order.create!` の `ActiveRecord::RecordInvalid` は rescue されず 500 になる。意図的ならよいが、確認が必要。
4. 軽微: `@order` が `redirect_to @order` の前に nil になる経路はないか（`create!` が失敗すれば例外なので到達しない）。

**読解のコツ**: `transaction do ... end` を見たら、(a) ブロック内で外部通信していないか、(b) コールバックで副作用（メール、ジョブ、外部 API）を起こしていないか、の2点を確認する。
</details>

---

## Q4. 今日のレポート  `★★☆`

```ruby
class DailyReport
  def self.todays_posts
    Post.where("created_at >= ?", Date.today.to_s)
  end
end
```

`config/application.rb` には `config.time_zone = "Tokyo"` が設定されている。

<details>
<summary>解答例</summary>

1. **タイムゾーンの不一致**: `Date.today` はシステム（OS / `TZ` 環境変数）のタイムゾーンで「今日」を決める。本番サーバーが UTC なら、日本時間 0:00〜9:00 の間は前日扱いになる。`Date.current`（`Time.zone.today`）を使う。
2. **文字列比較の罠**: `Date.today.to_s` は `"2026-10-28"` のような日付文字列。`created_at` は UTC で保存されているので、`"2026-10-28"` 以上という比較は **UTC の 10/28 0:00 以降**を意味し、日本時間 10/28 9:00 以降の投稿しか取れない。`Time.zone` を使った時刻オブジェクトで比較すれば ActiveRecord が UTC に変換してくれる。
3. **上限がない**: 「今日以降」になっていて、未来の `created_at` があれば含まれる。`Date.current.all_day` で範囲指定する。

修正例:

```ruby
Post.where(created_at: Date.current.all_day)
```

**読解のコツ**: `Date.today` / `Time.now` / `DateTime.now` が出てきたら、`Date.current` / `Time.current` と読み替えてよいか確認する。`to_s` した日付を SQL に渡しているのも危険信号。
</details>

---

## Q5. 更新メソッドの違いを説明せよ  `★★☆`

次の4行は、どれも `user` の `name` を `"x"` に変える。それぞれの違い（バリデーション、コールバック、`updated_at`、発行される SQL）を説明してください。

```ruby
user.update(name: "x")
user.update_attribute(:name, "x")
user.update_column(:name, "x")
User.where(id: user.id).update_all(name: "x")
```

<details>
<summary>解答例</summary>

| メソッド | バリデーション | コールバック | `updated_at` | 備考 |
|---|---|---|---|---|
| `update` | 実行する | 実行する | 更新する | 失敗時は `false` を返す（`update!` は例外） |
| `update_attribute` | **スキップ** | 実行する | 更新する | `save(validate: false)` 相当。バリデーションを飛ばす必要があるか要確認 |
| `update_column` | スキップ | **スキップ** | **更新しない** | 直接 `UPDATE` を1本発行。インスタンスの属性は書き換わる |
| `update_all` | スキップ | スキップ | 更新しない | SQL を直接発行。インスタンス `user` は**古いまま**（`reload` が必要） |

**レビューで見るべき点**:
- `update_attribute` / `update_column` / `update_all` が出てきたら「なぜバリデーション／コールバックを避けたいのか」をコメントで確認する。意図的な最適化（コールバックが重い、ロックを避けたい）と、単に `update` でエラーが出たので回避した、は全く違う。
- `update_all` の後にそのインスタンスを使い続けているコードは古い値を見ている可能性がある。
- `update_column` は `updated_at` を更新しないので、キャッシュキー（`cache_key_with_version`）が変わらず、フラグメントキャッシュが古いままになる。
</details>
