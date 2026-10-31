# sobosuba-mods

[English](#english) | [日本語](#日本語)

## English

A mod that mixes prime numbers into [sobosuba](https://store.steampowered.com/app/1946560/sobosuba).

You need the game. No game files are included here.
keepee, the developer, said mods are fine as long as they need the game, that GitHub and streaming are fine, and that mod scores should go to our own server. Thanks, keepee!

Version `1.2.3-1.0.0` is mod version 1.0.0, made for sobosuba 1.2.3. What changed is in [CHANGELOG.md](CHANGELOG.md).

### Prime balls

In sobosuba every ball is a power of two: 1, 2, 4, 8 and so on. With this mod, some spawns are a grey 3, 5, 11, 13 or 19 instead.

How many depends on the prime level, shown under your score. The game already lets bigger balls spawn as a run goes on, in seven stages. Each stage is one prime level, and the share of prime spawns climbs through the primes: 11%, 13%, 17%, 19%, 23%, 29% and 31%.

Prime balls don't merge with anything, so they mostly get in your way. The only exception is a pair that adds up to a power of two. Those merge into a normal ball:

- 3 + 5 = 8
- 3 + 13 = 16
- 5 + 11 = 16
- 13 + 19 = 32

Those merges count towards your score. There is no 7, since nothing could ever clear it.

### Install

1. Copy the `mods` folder into the game folder (`C:\Program Files (x86)\Steam\steamapps\common\sobosuba\`).
2. Put `override.cfg` next to `sobosuba.exe`. If your Steam library is on another drive, fix the path inside it.
3. Start the game from Steam as usual.

### Playing the original game

Turn off `prime balls` in Settings → game and you're back to the normal game, with the mod still installed. No prime balls, and your scores and achievements go to Steam as usual.

The switch applies from your next run. If you flip it in the middle of a run, that run finishes with prime balls, so a prime run never ends up on the official leaderboard. A run you continue from a save keeps the mode it started with.

The same switch also sits under the how-to-play guide at the start of a run. Pressing it there flips the mode and starts the run again right away.

The mod's text follows the game's language setting. The translations other than English and Japanese haven't been checked by native speakers yet, so corrections are welcome.

### Scores screen

While prime balls are on, the scores menu opens a prime version of the scores screen. It works like the original one, with a `prime scores` title and bluish-grey rows.

- local: your top 10 prime runs on this PC
- world: the prime world ranking (see below)
- friends only: just you and your Steam friends on the world ranking

To see the official Steam leaderboard, turn `prime balls` off.

When a run ends, a small board at the top shows this run, your best, and your friends' and world ranks. A screenshot of it is saved to your Steam screenshots, tagged with your prime score. Uploading it is up to you.

### World ranking

To send your prime scores, turn on `send scores` in Settings → game, right under `prime balls`. It's off by default. While it's off no score is sent, and the board after a run says so.

Scores go to this mod's own server (see [Where scores go](#where-scores-go)), never to the official leaderboard. As with the official Steam leaderboard, your Steam ID, Steam name, best score and rank are public. Nothing is sent while Steam isn't running.

A score that has been sent can't be removed later. Turning `send scores` off only stops the runs after that from being sent.

Looking at the world ranking sends no score, but it does send Steam IDs: yours to show your rank, and yours and your friends' for friends only. To turn the world ranking off completely, set `enabled` to `false` in `mods/prime_sobo/online.cfg`.

The first time you send a score, a key is saved in `%APPDATA%\Godot\app_userdata\sobosuba\prime_sobo_online.json`. The server ties your Steam ID to the first key it sees, so keep that file to yourself, and copy it over if you play on another PC. The server can't ask Steam whether an ID is really yours, so whoever sends a score for a Steam ID first holds that row.

The server keeps your Steam ID, Steam name, a hash of the key, your best score, and a log of submitted scores that is deleted after 30 days. It doesn't store your IP address or the key itself. Please don't bother keepee about the ranking.

The server only checks that a score looks possible: an even number, at most 50 points a second, from a run of 10 seconds to a day. The score itself is counted in the game, so a made-up score within those limits can't be told apart.

### Where scores go

- The mod talks to one place only: `sobosuba-ranking.pages.dev`, the ranking server for this mod. It's the `server_url` in `mods/prime_sobo/online.cfg`. The mod's author runs it on Cloudflare. It isn't run by keepee, and it isn't part of Steam.
- What the mod sends there:
  - When a run ends with `send scores` on: your Steam ID, Steam name, score, run length, prime chance, the mod version and the key above.
  - When you open the world ranking: your Steam ID, and your friends' Steam IDs for friends only.
- The author uses Steam IDs only to run the ranking. Like the official one, the ranking shows them to everyone, but they aren't sold, gathered for anything else, or used to look up or contact players.
- The server can't ask Steam whether an ID is yours: whoever sends a score for a Steam ID first holds that row (that's what the key above is for).
- To use your own server instead, run `server/` (see [server/README.md](server/README.md)) and change `server_url`.

### Uninstall

Delete `override.cfg` and the game is back to normal.

One catch: if you have a saved run with prime balls on the board, the game crashes when it loads that save without the mod. Finish that run first. Just turning `prime balls` off is fine.

### For developers

- Put an empty `mods/prime_sobo/selftest.flag` in place and start the game. It runs a self-test, writes `selftest_result.txt` and quits. Remove the flag afterwards.
- `server/` is the ranking server (Cloudflare Workers + D1). See [server/README.md](server/README.md).

### Special thanks

- keepee, for making sobosuba and saying yes to mods
- Kinkan（Maccha）, test player

### License

MIT, see [LICENSE](LICENSE). The license covers only the code written for this mod. sobosuba and its code, art, sounds and text belong to keepee. Parts of this mod follow and adapt the game's own code (such as the scores screen); those parts stay keepee's and are not licensed here. This is an unofficial mod and not part of sobosuba. If keepee asks us to change or take down anything, we will.

## 日本語

[sobosuba](https://store.steampowered.com/app/1946560/sobosuba) に素数の玉を混ぜる MOD です。

ゲーム本体が必要です。このリポジトリにゲームのファイルは入っていません。
作者の keepee さんから「ゲーム本体が要る作りならよい、GitHub と配信もよい、MOD の点数は自前のサーバで」と了承をもらっています。

版の `1.2.3-1.0.0` は、sobosuba 1.2.3 向けに作った MOD の 1.0.0 という意味です。変わったことは [CHANGELOG.md](CHANGELOG.md) にあります。

### 素数の玉

sobosuba の玉は 1, 2, 4, 8… と 2 の累乗しかありません。この MOD では、ときどき 3・5・11・13・19 の灰色の玉が出てきます。

どれくらい出るかは、点数の下に出る素数レベルで決まります。本家は試合が進むにつれて大きい玉を出すようにしていき、それが 7 段階あります。その 1 段階が素数レベルの 1 つで、素数の玉の割合も素数で上がっていきます: 11%・13%・17%・19%・23%・29%・31%。

素数の玉は普段は何ともくっつかない邪魔な玉です。足して 2 の累乗になる組だけが合体して、普通の玉になります。

- 3 + 5 = 8
- 3 + 13 = 16
- 5 + 11 = 16
- 13 + 19 = 32

合体した分は点数に入ります。7 は相手がいなくて消せないので入れていません。

### 入れ方

1. `mods` フォルダをゲームのフォルダ (`C:\Program Files (x86)\Steam\steamapps\common\sobosuba\`) にコピーします。
2. `override.cfg` を `sobosuba.exe` と同じ場所に置きます。Steam のライブラリが別のドライブにあるときは、中に書いてあるパスを直してください。
3. いつもどおり Steam から起動します。

### 本家のまま遊びたいとき

設定 → game の `prime balls` を切ると、MOD を入れたまま本家と同じ遊び方に戻ります。素数の玉は出なくなり、Steam のランキングと実績も本家どおりに記録されます。

切り替えは次の試合から効きます。遊んでいる途中で切っても、その試合は素数の玉ありのまま終わります。素数の玉が出た試合の点が、本家のランキングに載らないようにするためです。続きから再開した試合も、始めたときのモードのままです。

試合の始めに出る操作方法の案内の下にも、同じトグルがあります。そこで押すと、モードが切り替わって、すぐに試合をやり直します。

MOD の文字はゲームの言語の設定に合わせて変わります。英語と日本語以外の訳は、その言語を話す人にまだ見てもらっていません。直してもらえるとうれしいです。

### スコア画面

素数モードの間、メニューの scores は素数ver のスコア画面になります。中身は本家のスコア画面と同じで、タイトルが `prime scores`、色が青みのある灰色になっています。

- local: この PC での素数モードの上位 10 件
- world: 素数ver の世界ランキング (下を参照)
- friends only: 世界ランキングのうち、自分と Steam のフレンドだけ

本家の Steam のランキングを見たいときは `prime balls` を切ってください。

試合が終わると、画面の上に今回の点と自己ベスト、フレンドと世界の順位が出ます。そのときの盤面は素数モードの点の印 (日本語なら「素数モード N点」) を付けて Steam のスクリーンショットに保存されます。アップロードするかどうかは自分で決められます。

### 世界ランキング

素数モードの点数を送るときは、設定 → game の `send scores` (`prime balls` のすぐ下) を入れてください。最初は切ってあります。切っている間は点数を送らず、試合後の表にもそう出ます。

点数はこの MOD のサーバ ([点数の送り先](#点数の送り先)) に送られ、本家のランキングには送られません。本家の Steam のランキングと同じように、Steam ID と Steam の名前、最高点、順位が誰でも見られる形で載ります。Steam を起動していないときは送りません。

送った点数は、あとから消せません。`send scores` を切ると、それから後の試合が送られなくなるだけです。

世界ランキングを見るときは、点数は送りませんが Steam ID は送ります。自分の順位を出すときは自分の Steam ID を、friends only では自分とフレンドの Steam ID を送ります。世界ランキングをまったく使わないときは、`mods/prime_sobo/online.cfg` の `enabled` を `false` にしてください。

初めて送ったときに `%APPDATA%\Godot\app_userdata\sobosuba\prime_sobo_online.json` に鍵ができます。サーバは最初に届いた鍵でその Steam ID を覚えるので、このファイルは人に渡さないでください。別の PC で遊ぶときはこのファイルを写してください。サーバは Steam に本人かどうかを確かめられないので、ある Steam ID で最初に点数を送った人がその行を持つことになります。

サーバに残るのは Steam ID、Steam の名前、鍵のハッシュ、最高点と、届いた点数の記録 (30 日で消えます) です。IP アドレスと鍵そのものは保存しません。ランキングのことで、ゲームの作者さんへ連絡するのはご遠慮ください。

サーバが確かめるのは、点数がありうる形かどうか (偶数で、1 秒あたり 50 点まで、試合は 10 秒〜1 日) だけです。点数はゲームの中で数えるので、この枠に収まる作り物の点数は見分けられません。

### 点数の送り先

- MOD が通信する先は 1 か所だけです。この MOD のランキングサーバ `sobosuba-ranking.pages.dev` で、`mods/prime_sobo/online.cfg` の `server_url` に書いてあります。MOD の作者が Cloudflare の上で動かしています。ゲームの作者 (keepee) さんのサーバでも、Steam のサーバでもありません。
- そこへ送るもの:
  - `send scores` を入れて試合が終わったとき: Steam ID、Steam の名前、点数、試合の長さ、素数の確率、MOD の版、上の鍵。
  - 世界ランキングを開いたとき: 自分の Steam ID と、friends only ではフレンドの Steam ID。
- MOD の作者は、Steam ID をランキングを動かすことにだけ使います。ランキングには本家と同じように誰でも見られる形で載りますが、売ったり、ほかの用途のために集めたり、遊んでいる人を調べたり連絡したりすることには使いません。
- サーバは Steam に本人かどうかを確かめられません。ある Steam ID で最初に点数を送った人が、その行を持ちます (上の鍵はそのためのものです)。
- 自分のサーバを使いたいときは、`server/` を動かして ([server/README.md](server/README.md))、`server_url` を書き換えてください。

### 外し方

`override.cfg` を消せば元に戻ります。

ただし、素数の玉が盤に残った試合のセーブがあると、外したあとに続きを読み込んだときにゲームが落ちます。その試合を終えてから外してください。`prime balls` を切るだけなら落ちません。

### 開発者向け

- `mods/prime_sobo/selftest.flag` (空のファイル) を置いて起動すると、自己試験をして `selftest_result.txt` に結果を書き、ゲームを終了します。終わったら flag は消してください。
- `server/` はランキングサーバ (Cloudflare Workers + D1) です。詳しくは [server/README.md](server/README.md)。

### 謝辞

- sobosuba を作り、MOD を認めてくれた keepee さん
- テストプレイヤーの Kinkan（Maccha）さん

### ライセンス

MIT。詳しくは [LICENSE](LICENSE)。このライセンスが及ぶのは、この MOD のために書いたコードだけです。sobosuba 本体と、そのコード・絵・音・文字は作者の keepee さんのものです。この MOD の一部 (スコア画面など) は本家のコードをなぞって手を加えたもので、その部分は keepee さんのものとし、ここでは許していません。非公式の MOD で、sobosuba の一部ではありません。keepee さんから直しや取り下げを求められたら従います。
