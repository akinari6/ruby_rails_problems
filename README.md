# Ruby / Rails 読解力トレーニング問題集

「書く」のではなく「読む」力を鍛えるための問題集です。
**1日20分、3問**を1セットにし、**GitHub の PR 上でコメントして解く**運用にしています。

## 毎日の流れ

1. 毎朝 7:00（JST）に GitHub Actions が「Day NN」の PR を自動で開く（前の Day が未完了なら開かない）
2. PR の「Files changed」で問題を読み、**インラインコメント**で回答する
   - **A. 出力予測**（5分）: コードブロックの最後の行に、予測した出力をコメント
   - **B. コードレビュー**（7分）: 問題のある行に指摘をコメント。実際のレビューと同じ要領
   - **C. PRレビュー**（8分）: Approve / Request changes を選び、理由を書く
3. 書き終えたら PR に `/answer` とコメント → 解答・解説がコメントで投稿され、PR はマージされる
4. 自分のコメントと解答例を見比べ、拾えなかった観点を `PROGRESS.md` の弱点メモに残す

## 復習（忘却曲線に合わせた自動スケジュール）

Day の PR がマージされると、**1日後・7日後・30日後**に同じ問題の「復習 Day NN」PR が自動で開きます。
元の PR のコメントは見ずに最初から解き、同じく `/answer` で答え合わせします。

- 1日後: 短期記憶から中期記憶へ。解説を読んだ直後なので「理解した気」の確認
- 7日後: ここで解けなければ理解が定着していない。解説を読み直す
- 30日後: 長期記憶の確認。ここで解ければ卒業

復習 PR は 1 日に 1 つずつしか開かないので、溜まることはありません。

## 問題の形式と鍛えられること

| 形式 | 問い方 | 鍛えられること |
|---|---|---|
| A. 出力予測 | 「このコードは何を出力する？」 | Ruby の言語仕様の正確な理解（参照、スコープ、メソッド探索、引数） |
| B. コードレビュー | 「このコードの問題点をすべて挙げよ」 | Rails の落とし穴を嗅ぎ分ける力（N+1、トランザクション、権限、タイムゾーン） |
| C. PRレビュー | 「この diff を approve してよいか？」 | 変更の影響範囲と本番で起きることを想像する力 |

A は Ruby 3.3 で実行して解答を検証しています。B と C は「答えが1つに決まらない」ものも含むので、解答例の観点を自分の答えと突き合わせてください。
解説は「仕組み → 確認方法 → 修正例 → 読解のコツ」の順です。

難易度の目安:

- ★☆☆ … 基本。間違えたら該当トピックの復習が必要
- ★★☆ … 実務で踏みやすい。レビューで指摘できれば合格
- ★★★ … 仕様の細部や複数要因の組み合わせ

## 問題一覧

| Day | A. 出力予測 | B. コードレビュー | C. PRレビュー |
|---|---|---|---|
| 01 | `Array.new` と共有オブジェクト | 投稿一覧の N+1 | uniqueness とユニークインデックス |
| 02 | 破壊的メソッドと参照 | Strong Parameters と権限昇格 | `dependent: :destroy` の追加 |
| 03 | `Hash.new` のデフォルト値 | トランザクション内のコールバック | インデックス追加と NOT NULL のマイグレーション |
| 04 | ブロック・lambda・proc の `return` | 日付とタイムゾーン | `default_scope` による論理削除 |
| 05 | `prepend` とメソッド探索 | 更新メソッド4種の違い | ActiveJob のリトライと冪等性 |
| 06 | `case/when` と `===` | 検索と SQL インジェクション | フラグメントキャッシュのキー |
| 07 | ブロックのスコープとクロージャ | 全件更新のバッチ処理 | `after_commit` と dirty tracking |

## ディレクトリ構成

```
bank/dayNN/problem.md   問題（PR の diff になる）
bank/dayNN/answer.md    解答・解説（/answer で PR にコメント投稿される）
days/dayNN/             解いた Day の問題（PR マージで積み上がる記録）
reviews/dayNN/rN/       復習の記録
scripts/daily.rb        毎朝の PR 作成と復習スケジュール
scripts/reveal.rb       /answer の処理
.github/workflows/      上記を動かす Actions
```

`bank/` の解答はリポジトリ上で見えるので、自分で開かないようにしてください（解く前に見ない、という自己管理が前提です）。

## 初回セットアップ

1. このリポジトリの **Settings → Actions → General → Workflow permissions** で
   「Read and write permissions」と「Allow GitHub Actions to create and approve pull requests」を有効にする
2. **Actions → Daily problem → Run workflow** を手動で1回実行すると、その場で Day 01 の PR が開く
   （以降は毎朝 7:00 JST に自動実行）

## 手元で確認する

```bash
DRY_RUN=1 PR_LIST_JSON='[]' ruby scripts/daily.rb
```

`git` / `gh` を実行せず、実行されるはずのコマンドだけを表示します。

## 今後の追加候補

- A: Enumerable の遅延評価と `lazy`、`method_missing` / `respond_to_missing?`、`Comparable` と `<=>`、`ensure` と `return` の評価順、`freeze` と定数、`Struct` / `Data`、パターンマッチ
- B: 楽観ロック・悲観ロック、`scope` が nil を返すとき、`has_many through` の `dependent:`、`rescue_from` の順序、`params` のネスト、API のシリアライズ
- C: 外部キー追加のマイグレーション、`enum` の値変更、`config/` 変更の影響、Gemfile の major バージョンアップ、`before_action` の追加・削除

問題を足すときは `bank/dayNN/problem.md` と `answer.md` を追加するだけで、翌朝から自動で出題されます。
