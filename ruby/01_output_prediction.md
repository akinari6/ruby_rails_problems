# Ruby 01. 出力予測 — 参照・スコープ・メソッド探索・引数

各問題のコードを読み、**出力を正確に予測**してください。
`p` の出力形式（文字列はダブルクォート付き、シンボルは `:` 付き）まで書けると理想です。
解答はすべて Ruby 3.3 で実行して確認しています。

---

## Q1. `Array.new` の第2引数とブロック  `★☆☆`

```ruby
a = Array.new(3, [])
a[0] << 1
p a

b = Array.new(3) { [] }
b[0] << 1
p b
```

<details>
<summary>解答</summary>

```
[[1], [1], [1]]
[[1], [], []]
```

**ポイント**: `Array.new(3, [])` は**同じ配列オブジェクト**を3つの要素として共有する。`a[0] << 1` は破壊的変更なので、共有している全要素に反映される。
ブロック形式 `Array.new(3) { [] }` はブロックが3回評価され、毎回新しい配列が作られる。

`Hash.new([])` でも同じ罠がある（Q3 参照）。レビューで `Array.new(n, mutable_object)` を見たら要注意。
</details>

---

## Q2. 破壊的メソッドと参照  `★☆☆`

```ruby
s = "abc"
t = s
t << "d"
u = s + "e"
p s, t, u
p s.equal?(t), s.equal?(u)
```

<details>
<summary>解答</summary>

```
"abcd"
"abcd"
"abcde"
true
false
```

**ポイント**: `t = s` は参照のコピーなので `t << "d"` は `s` にも影響する。`+` は新しい文字列を返す。
`equal?` はオブジェクト同一性（`object_id` が同じか）、`==` は値の等価性。`eql?` はさらに型も見る（`1 == 1.0` は true、`1.eql?(1.0)` は false）。

`# frozen_string_literal: true` が付いているファイルなら `t << "d"` は `FrozenError` になる。Rails アプリの多くのファイルにはこのマジックコメントがある。
</details>

---

## Q3. `Hash.new` のデフォルト値と `||=`  `★★☆`

```ruby
h = Hash.new { |hash, k| hash[k] = k * 2 }
h[1]
h[2] ||= 100
p h

g = Hash.new(0)
g[:a] += 1
g[:b]
p g
```

<details>
<summary>解答</summary>

```
{1=>2, 2=>4}
{:a=>1}
```

**ポイント**:
- ブロック付き `Hash.new` は、存在しないキーを参照した時点でブロックが実行され、ブロック内で `hash[k] = ...` しているのでキーが**実際に格納される**。`h[2] ||= 100` は `h[2] || (h[2] = 100)` と等価で、`h[2]` の参照時点でデフォルトブロックが走って `4` が入り、真なので `100` は代入されない。
- `Hash.new(0)` はデフォルト**値**を返すだけで格納はしない。`g[:b]` は `0` を返すが `g` には追加されない。`g[:a] += 1` は `g[:a] = g[:a] + 1` なので格納される。

`Hash.new([])` と書くと Q1 と同じく全キーでオブジェクトを共有するので、`h[:x] << 1` が全体に漏れる。グルーピング処理のレビューで頻出。
</details>

---

## Q4. ブロック・lambda・proc の `return`  `★★☆`

```ruby
def m1
  [1, 2, 3].each { |x| return x if x > 1 }
  :done
end

def m2
  l = lambda { |x| return x * 2 }
  r = l.call(5)
  r + 1
end

def m3
  pr = proc { |x| return x * 2 }
  r = pr.call(5)
  r + 1
end

p m1, m2, m3
```

<details>
<summary>解答</summary>

```
2
11
10
```

**ポイント**:
- ブロック内の `return` は**ブロックを定義したメソッド**から戻る。`m1` は `each` の途中で `2` を返して終了し、`:done` には到達しない。
- `lambda` 内の `return` は lambda 自身から戻るだけ。`r = 10` となり `11`。
- `proc` 内の `return` はブロックと同じく**定義元のメソッド**（`m3`）から戻る。`r + 1` は実行されず `10`。

`proc` をメソッド外で作って後から `call` すると `LocalJumpError` になる。引数の数のチェックも lambda は厳密、proc は緩い（足りなければ nil）。
</details>

---

## Q5. `prepend` とメソッド探索順序  `★★☆`

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
<summary>解答</summary>

```
"HI!"
[Student, Loud, Person, Object]
```

**ポイント**: `prepend` はモジュールをクラス**より前**に挿入する（`include` は後ろ）。探索順は `Student → Loud → Person`。
1. `Student#greet` が `super` を呼ぶ → 次は `Loud#greet`
2. `Loud#greet` が `super` を呼ぶ → `Person#greet` が `"hi"` を返す
3. `Loud` が `"HI"` にして返す → `Student` が `"HI!"` にする

Rails の `ActiveSupport::Concern` の `prepended do` や、gem がモンキーパッチで `prepend` を使っているときにこの順序を読めないとデバッグできない。`Student.instance_method(:greet).super_method` で辿ると確認できる。
</details>

---

## Q6. `case/when` と `===`  `★★☆`

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
<summary>解答</summary>

```
[:int, :small, :digits, :enum, :other]
```

**ポイント**: `when` は `条件 === x` を上から順に評価し、最初に真になったものを採用する。
- `Integer === 5` → true（クラスは `===` で `is_a?` 判定）。`5` は `1..10` にも該当するが、先に `Integer` で確定。
- `5.0` は Integer ではないが `(1..10) === 5.0` は true（Range は `cover?` 相当）。
- `Regexp === "12"` はマッチで true。
- `Proc === x` は `call` して判定する。配列は `each` を持つ。
- `"ab"` はどれにも該当しない。

`when` の**順序**で結果が変わる点が読解の肝。`when String, Symbol` のようにカンマ区切りは OR。
</details>

---

## Q7. 引数の割り当て規則  `★★☆`

```ruby
def f(a, b = 2, *rest, c:, d: 4, **opts)
  [a, b, rest, c, d, opts]
end

p f(1, c: 3)
p f(1, 9, 8, 7, c: 3, e: 5)
```

<details>
<summary>解答</summary>

```
[1, 2, [], 3, 4, {}]
[1, 9, [8, 7], 3, 4, {:e=>5}]
```

**ポイント**: 位置引数は「必須 → デフォルト付き → 可変長」の順に埋まる。キーワード引数は名前で対応し、`c:` はデフォルトがないので省略すると `ArgumentError`。未知のキーワードは `**opts` に集まる。

Ruby 3 以降、位置引数とキーワード引数は分離されている。`f(1, {c: 3})` のようにハッシュを渡すと `b` に入ってしまい `missing keyword: :c` になる（Ruby 2 では自動変換されていた）。古い gem やアップグレード直後のアプリのバグ読解で必要になる知識。
</details>

---

## Q8. ブロックのスコープとクロージャ  `★★★`

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
<summary>解答</summary>

```
13
10
2
```

**ポイント**:
- ブロックは外側のローカル変数を**参照で**捕捉するので `x` は書き換わる（`13`）。
- `|i; y|` のセミコロン以降は**ブロックローカル変数**の宣言。外側の `y` とは別物になり、外側は `10` のまま。
- `counter` 内の2つの lambda は**同じ** `count` を共有している（同じスコープで作られたクロージャ）。`counter` から戻った後もその変数は生き続ける。

`def` はスコープを切るのでブロックと違って外側のローカル変数は見えない。`define_method` はブロックなので見える。この違いがメタプログラミングのコード（Rails の `scope` や `delegate` の実装）を読むときに効いてくる。
</details>
