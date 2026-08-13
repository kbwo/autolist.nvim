# autolist.nvim コア機能の分析

作り直しの出発点として、既存の [kbwo/autolist.nvim](https://github.com/kbwo/autolist.nvim)（commit `3394996`、gaoDean/autolist.nvim の fork）が実際に何をしているかを読んだ結果をまとめる。
以下の行番号はすべて上記 commit の内容を指す。

## 全体像

markdown / text / tex / norg のようなプレーンテキストで「リストの見た目の保守」を自動化するプラグイン。
やっていることは 3 つに集約できる。

1. **継続** — 改行したときに、直前の行のマーカー（`-`, `1.`, `a)`, `I.`, `\item`, チェックボックス）を引き継いだ新しい行頭を作る。
2. **再計算** — 順序付きリストの番号を、インデント階層ごとに振り直す。削除・並べ替え・インデント変更のあとに呼ぶ。
3. **変換** — チェックボックスのトグル、リストマーカー種別の巡回（`-` → `*` → `1.` → …）。いずれも最後に再計算を走らせて一覧全体を揃える。

実装は Lua 約 840 行、5 ファイルのみ。

| ファイル | 役割 |
| --- | --- |
| `lua/autolist/init.lua` | `setup()`。設定を反映し、`auto.lua` の公開関数から `Autolist*` コマンドを自動生成する |
| `lua/autolist/auto.lua` | ユーザーが呼ぶ機能本体（継続・再計算・タブ・チェックボックス・巡回） |
| `lua/autolist/utils.lua` | 行のリスト判定、マーカーの取得・書き換え、リスト先頭行の探索 |
| `lua/autolist/numbers.lua` | ローマ数字 ⇔ アラビア数字の変換 |
| `lua/autolist/treesitter.lua` | markdown のコードフェンス内かどうかの判定 |

### 起動と公開インターフェース

`setup()` は `auto.lua` の全関数を舐めて、snake_case を PascalCase に変換した `Autolist<Name>` コマンドを定義する（`init.lua:10-21`）。
つまり公開 API の一覧＝`auto.lua` の `M.*` そのもので、コマンドと Lua 関数は常に 1 対 1 に対応する。

- `AutolistNewBullet` / `new_bullet`
- `AutolistNewBulletBefore` / `new_bullet_before`
- `AutolistRecalculate` / `recalculate`
- `AutolistToggleCheckbox` / `toggle_checkbox`
- `AutolistCycleNext` / `AutolistCyclePrev`、および dot-repeat 版 `cycle_next_dr` / `cycle_prev_dr`
- `AutolistTab` / `AutolistShiftTab`

キーマップは一切定義せず、README の例（`README.md:55-76`）のようにユーザーが自分で貼る前提。
たとえば継続は `vim.keymap.set("i", "<CR>", "<CR><cmd>AutolistNewBullet<cr>")`、つまり **Neovim に普通に改行させたあと、できた行を後追いで書き換える** 方式（`README.md:58`）。

## コア機能の詳細

### 1. 行がリストかどうかの判定 — `utils.is_list` (`utils.lua:224-248`)

すべての機能がこの関数の上に乗っている。

- 判定は filetype ごとの Lua パターン配列（`config.lists[filetype]`）に対する総当たりで、**配列の順序が優先順位**（`utils.lua:232`）。
- パターンは `"^%s*(" .. pat .. ").*$"` の形で当てる。行頭の空白のみを許容するので、`> - item` のような引用中のリストはマッチしない。
- マッチしても、**マーカーの直後が空白か行末でなければリストとみなさない**（`utils.lua:239-245`）。これは `**bold**` が `*` の unordered list として誤検出されるのを防ぐための fork 側の修正。
- 空行は常に false（`utils.lua:231`）。
- 戻り値は `true, パターン, マッチしたマーカー文字列` の 3 値で、呼び出し側は `select(2, ...)` / `select(3, ...)` で取り出す（`utils.lua:132-138`）。

filetype ごとの既定パターン（`config.lua:1-56`）:

| 名前 | パターン | 例 |
| --- | --- | --- |
| unordered | `[-+*]` | `- ` `+ ` `* ` |
| digit | `%d+[.)]` | `1.` `2)` |
| ascii | `%a[.)]` | `a)` `b)` |
| roman | `%u+[.)]` | `I.` `IV.` |
| neorg_1..5 | `%-` 〜 `%-%-%-%-%-` | `-` 〜 `-----` |
| latex_item | `\item` | `\item` |

markdown の登録順は unordered → digit → ascii → roman なので、`I. foo` は先に ascii パターン `%a[.)]` にマッチする。
マーカーの置換は結局マーカー全体を差し替えるので実害はないが、パターン同士が重複していること自体は把握しておいたほうがよい。

順序付きリストの「値」の解釈は `is_list` とは別系統で、`exec_ordered`（`utils.lua:46-65`）が数字 `%d+`・小文字 `%l`・大文字連 `%u+` を個別に見分けている。

### 2. 継続 — `new_bullet` (`auto.lua:150-174`)

`<CR>` が済んだ **あと** に呼ばれる前提の関数。処理順は次のとおり。

1. filetype にリスト定義がなければ何もしない。markdown のコードフェンス内でも何もしない（`auto.lua:151-153`、判定は treesitter）。
2. 直前の行（`new_bullet_before` の場合は直後の行）から行頭部分を切り出す（`get_bullet_from`, `auto.lua:108-122`）。切り出しは 3 パターンを試し、**チェックボックス付き → マーカー＋空白 → 行末までマーカーだけ** の順で採用する。
3. 切り出した文字列が行全体と同じ長さ、つまり **中身が空のリスト行だったら、その行を削除して継続をやめる**（`auto.lua:136-142`）。「空の項目で Enter を押すとリストを抜ける」挙動はここ。
4. 順序付きなら番号を +1 する（`get_ordered_add`, `utils.lua:158-170`）。数字・アルファベット・ローマ数字それぞれに加算処理がある。
5. 直前の行が `:` で終わっていれば、マーカーではなく **1 段深いインデント＋`config.colon.preferred`（既定 `-`）** を作る（`auto.lua:163-168`）。`colon.indent_raw` が true ならリスト外でも効く。
6. チェックボックスは必ず未チェックにして引き継ぐ（`auto.lua:171`）。
7. 現在行の先頭空白を捨てて、作った行頭を貼り付ける（`auto.lua:172`）。

### 3. 再計算 — `recalculate` (`auto.lua:39-102`)

このプラグインで一番込み入っている部分。

- まず `get_indent_list_start`（`utils.lua:193-219`）で、**カーソル行と同じインデント階層のリストの先頭行**まで遡る。遡りは `getline` が範囲外で `""` を返すこと（確認済み）に依存して停止する。
- 先頭行の番号を **必ず 1 にリセットする**（`auto.lua:49-60`）。`3.` 始まりのリストも 1 に矯正される。
- そこから下方向に走査し、
  - 同じインデントのリスト行 → 連番を振る。マーカーの書式は **先頭行のものをコピー**する（`auto.lua:76-81`）。先頭を `a)` に書き換えて再計算すればリスト全体が `a)` 形式になるのはこの仕組み。
  - インデントがちょうど `config.tabstop` 分深い行 → その行を起点に **再帰**して子リストを処理する（`auto.lua:84-92`）。
  - リストでない行 → 打ち切り（`auto.lua:94-96`）。空行もリストでないので、そこでスコープが切れる。
- 走査は先頭から `config.list_cap`（既定 50 行、`config.lua:78`）で頭打ち。
- 順序なしリストは `set_ordered_value` が何もしないので、内容が変わらない。

### 4. インデント — `tab` / `shift_tab` (`auto.lua:183-204`)

「リスト行で、かつカーソルが行末にあるとき」だけリスト操作、それ以外はただのタブ入力、という分岐（`auto.lua:188-189`）。
リスト操作の場合は `<c-t>` / `<c-d>` を `feedkeys` で送り、`vim.loop.new_timer()` の 0ms タイマー経由で `recalculate` を遅延実行する（`auto.lua:177-181`）。
feedkeys で送ったキーが処理される前に再計算が走ってしまうのを避けるための順序合わせ。

### 5. チェックボックス — `toggle_checkbox` (`auto.lua:214-225`)

現在行の `[x]` ↔ `[ ]` を入れ替えるだけ。区切り文字と埋め文字は `config.checkbox.left/right/fill` で変えられる（`config.lua:57-61`）。
ただし **パターン文字列は `auto.lua` の読み込み時に組み立てられる**（`auto.lua:5-13`）。

### 6. マーカー種別の巡回 — `cycle` (`auto.lua:235-287`)

`config.cycle`（既定 `- * 1. 1) a) I.`）の中で現在のマーカーの位置を探し、次／前の要素をリスト先頭行に書き込んで `recalculate` を呼ぶ（`auto.lua:254-255`）。
再計算がマーカー書式を先頭行からコピーする性質を使って、1 行書き換えるだけでリスト全体を変換している。
dot-repeat 版は `operatorfunc` に自分を設定して `g@l` を返す定番の手法（`auto.lua:260-279`）。

### 7. 付随機能

- **ローマ数字** (`numbers.lua`): 減算記法（`IV`, `IX`, `CM`）に対応した相互変換。`MXIII` のような大きな値も継続できる。
- **コードフェンス除外** (`treesitter.lua`): markdown のときだけ、カーソル位置のノードを親方向に辿って `fenced_code_block` / `code_fence_content` に入っていないか調べる。パーサ未導入なら `nil` を返して黙って無効化される。

## 設定 (`config.lua`)

ユーザーに見えるのは `enabled` / `colon` / `cycle` / `lists` / `checkbox` の 5 つ。
`update()` は既定値と deep-extend したうえで、内部専用の値を足す（`config.lua:68-93`）。

- `list_cap = 50` — 再計算の走査上限行数
- `tabstop`, `tab` — `expandtab` なら `tabstop` 個の空白、そうでなければ `"\t"`。インデント 1 段の実体
- `recal_full = false` — 現状どこからも読まれていない

## テスト

plenary.nvim の busted 互換ランナーを使い、`make test` で headless 実行（`Makefile:3-4`）。
`spec/fork_behaviors_spec.lua` は fork で直した 16 箇所の挙動を、実装ではなく「あるべき挙動」として書いた回帰テストになっているので、作り直すときの受け入れ条件としてそのまま使える。
`spec/run_tests.lua` は plenary なしでも動かせるよう describe/it/assert を自前で用意した予備のランナー。

## 作り直すときに引き継ぐか切るかを決めるべき点

いずれも上記コードから読み取った事実で、「気に入らない細部」の候補になりそうなもの。

1. **`<CR>` 後の事後書き換え方式**（`README.md:58`, `auto.lua:150-174`）。改行そのものは Neovim に任せ、できた行を書き換える。他プラグインとのマッピング順序に依存し、README 自身が「autolist を最後に読み込め」とトラブルシュートに書いている（`README.md:243`）。
2. **再計算が先頭を必ず 1 に矯正する**（`auto.lua:49-60`）。`3.` から始めたいリストを保てない。
3. **走査上限 50 行**（`config.lua:78`, `auto.lua:72`）。長いリストは途中から番号が揃わない。
4. **子リストの判定がインデント差ちょうど 1 段の一致**（`auto.lua:87`）。2 スペースと 4 スペースが混ざる文書や、`tabstop` と実際のインデント幅がずれる文書で崩れる。
5. **空行でリストスコープが切れる**（`utils.lua:231`, `auto.lua:94-96`）。項目間に空行を入れる、いわゆる loose list を 1 つのリストとして扱えない。
6. **引用ブロック内のリストが非対応**（`utils.lua:233` のパターンが行頭空白しか許さない）。
7. **チェックボックスのパターンがモジュール読み込み時に固定される**（`auto.lua:5-13`）。`setup()` を後から呼び直しても `config.checkbox` の変更が反映されない。
8. **マーカー書き換え時にカーソルが行末へ飛ぶ**（`utils.lua:87` の `reset_cursor_column(fn.col("$"))`）。
9. **`is_list` が 3 値を返し `select()` で取り出す**（`utils.lua:132-138`）。呼び出し側が読みにくい。
10. **`fn.getline` / `fn.setline` とカーソル位置に強く依存**した実装で、`nvim_buf_*` API を使っていない。範囲外の `getline` が `""` を返す挙動に依存した終了条件もある（`utils.lua:179-189`, `utils.lua:200-215`）。
11. **タブ処理が `feedkeys` + 0ms タイマー**（`auto.lua:177-196`）という順序合わせのハックになっている。
12. **自動発火が一切ない**。再計算は `dd` や `>>` にユーザーが自分でぶら下げる必要がある（`README.md:73-76`）。
