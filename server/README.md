# Ranking server / ランキングサーバ

[English](#english) | [日本語](#日本語)

## English

The world ranking server for the Prime Balls mod, on Cloudflare Workers (TypeScript) and D1.
The `wrangler.toml` in this repository is for running it locally. It has no production account or database.

### Run it locally

You need Node.js 24 and npm 11. In `server/`:

```powershell
npm ci --ignore-scripts
$env:WRANGLER_SEND_METRICS = 'false'
# Secret used when hashing IPs for rate limiting. Created once.
if (-not (Test-Path -LiteralPath '.dev.vars')) {
  $salt = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
  [IO.File]::WriteAllText((Join-Path $PWD '.dev.vars'), 'IP_HASH_SECRET=' + $salt)
}
npm run migrate:local
npm run dev
```

If `http://127.0.0.1:8787/v1/health` returns `{"ok":true}`, it's running. If you change the port, change `server_url` in the mod's `online.cfg` too (plain HTTP works for loopback).

### Tests

```powershell
$env:GODOT_BIN = '<Godot 4.7.2 console exe>'
$env:POWERSHELL_BIN = (Get-Process -Id $PID).Path   # PowerShell 7.2 or later
$env:SOBOSUBA_QA_ROOT = '<folder for test work files>'
$env:SOBOSUBA_GAME_PCK = '<the game folder>\sobosuba.exe'   # optional, see below
npm test
npm run check
```

`npm test` starts a real workerd with a local D1 and talks to it over HTTP. The mod's network and settings scripts run in a standalone [Godot 4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) against the real server (not the game exe). Test work folders go under `SOBOSUBA_QA_ROOT` and are not cleaned up automatically.

With `SOBOSUBA_GAME_PCK` set, `npm test` also runs the mod's self-test to the end in the standalone Godot, headless, reading the game's data out of a copy of `sobosuba.exe` (the exe itself is never started). The standalone Godot is a debug build and catches script errors the game's own build lets through. Without it that test is reported as skipped.

`npm test` doesn't run the game. The mod's self-test checks part of what happens inside the game (the screens, the flow of a run, Steam submissions staying off), but it doesn't replace playing the game.

### API

Everything is JSON. Errors look like `{"ok":false,"error":"<reason>"}`. Every response has `Cache-Control: no-store`.

| Route | Returns |
| --- | --- |
| `GET /v1/health` | `{ok}` |
| `POST /v1/scores` | `{ok,rank,best,players}` |
| `GET /v1/leaderboard?mod=prime_sobo&limit=10&offset=0` | `{ok,entries,players}` |
| `GET /v1/leaderboard/around?mod=prime_sobo&player_id=<Steam ID>&span=3` | `{ok,entries,rank,players}` |
| `GET /v1/leaderboard/friends?mod=prime_sobo&ids=<Steam ID,...>` | `{ok,entries}` |

- `limit` is 1-50, `offset` 0-10000, `span` 0-24, and `ids` takes 1-100 IDs. Anything else is `INVALID_QUERY`.
- Rows are `{rank, steam_id, name, best}`. Rows from around also have `you` on your own row. In friends, `rank` is the world rank.
- The POST body has `mod`, `mod_version`, `player_id` (SteamID64), `player_key` (32 random bytes as hex), `name`, `score`, `duration_s` and `prime_chance`, up to 4096 bytes.
- Names lose control characters and are cut to 24 characters. An empty name becomes `anon`.
- Scores are even numbers from 0 to 10,000,000, at most 50 points per second, for runs of 10 seconds to a day.
- The first key that arrives for a Steam ID is remembered, and a different key gets `KEY_MISMATCH`. There is no Steam-side identity check.
- Per IP: 10 POSTs and 60 GETs per 60 seconds. Per player: one submission every 20 seconds.

The server only checks that the numbers are in range and not sent too often. It can't prove a score was really played.

### What is stored

| Table | Contents |
| --- | --- |
| `players` | Steam ID, SHA-256 of the key, Steam name, best score and when it was set |
| `submissions` | Accepted scores (rejections keep only the reason and time). Deleted after 30 days |
| `rate` | The 20-second window per player |

The key itself and IP addresses are not stored. IPs are only hashed with a secret, briefly, to count requests. The friend list sent by friends only is not stored either.

### Deploy

Use `scripts/deploy.ps1` (PowerShell 7.2 or later). With no options, or with `-DryRun`, it only prints the steps.

```powershell
pwsh -NoProfile -File scripts/deploy.ps1 -DryRun
pwsh -NoProfile -File scripts/deploy.ps1 -Execute -AccountId <account id> -HealthUrl https://<worker host>/v1/health
```

With `-Execute` it creates the D1 database if needed, applies migrations, sets the secret, deploys and checks health. The production settings go in `wrangler.production.toml`, which Git ignores. Run `wrangler login` first.

The mod doesn't call the Worker's own host. It calls a Cloudflare Pages entrance (`pages/`) that hands every request to the Worker through a service binding, so the Worker still sees each player's IP for its limits. Deploy the Worker first, then the entrance:

```powershell
cd pages
npx wrangler pages project create sobosuba-ranking --production-branch main --force   # first time only
npx wrangler pages deploy --branch main --force
```

## 日本語

素数の玉 MOD の世界ランキング用のサーバです。Cloudflare Workers (TypeScript) と D1 で動きます。
リポジトリの `wrangler.toml` は手元で動かすための設定で、本番のアカウントやデータベースは入っていません。

### 手元で動かす

Node.js 24 と npm 11 を使います。`server/` で次を実行します。

```powershell
npm ci --ignore-scripts
$env:WRANGLER_SEND_METRICS = 'false'
# Secret used when hashing IPs for rate limiting. Created once.
if (-not (Test-Path -LiteralPath '.dev.vars')) {
  $salt = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
  [IO.File]::WriteAllText((Join-Path $PWD '.dev.vars'), 'IP_HASH_SECRET=' + $salt)
}
npm run migrate:local
npm run dev
```

`http://127.0.0.1:8787/v1/health` が `{"ok":true}` を返せば動いています。ポートを変えたときは、MOD の `online.cfg` の `server_url` も合わせてください (ループバックなら HTTP でつながります)。

### 試験

```powershell
$env:GODOT_BIN = '<Godot 4.7.2 console exe>'
$env:POWERSHELL_BIN = (Get-Process -Id $PID).Path   # PowerShell 7.2 or later
$env:SOBOSUBA_QA_ROOT = '<試験の作業フォルダ>'
$env:SOBOSUBA_GAME_PCK = '<ゲームのフォルダ>\sobosuba.exe'   # 任意。下を参照
npm test
npm run check
```

`npm test` は本物の workerd とローカルの D1 を立てて HTTP で試します。MOD 側の通信や設定の部品は、[Godot 4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) を単体で動かして本物のサーバに当てます (ゲームの exe は使いません)。試験の作業フォルダは `SOBOSUBA_QA_ROOT` に作られ、自動では消えません。

`SOBOSUBA_GAME_PCK` を指すと、`npm test` は MOD の自己試験も単体の Godot で窓を出さずに最後まで流します。ゲームのデータは `sobosuba.exe` の写しから読みます (exe そのものは起動しません)。単体の Godot は検査つきの版なので、ゲームの書き出しでは素通りするスクリプトの誤りも捕まえます。指さないときは、その試験は飛ばしたと表示されます。

`npm test` はゲームを動かしません。ゲームの中での動き (画面、試合の流れ、Steam への送信を止めていること) の一部は MOD の自己試験で確かめますが、実際に遊んで確かめることの代わりにはなりません。

### API

すべて JSON で、失敗のときは `{"ok":false,"error":"<理由>"}` を返します。どの応答も `Cache-Control: no-store` です。

| 経路 | 返り値 |
| --- | --- |
| `GET /v1/health` | `{ok}` |
| `POST /v1/scores` | `{ok,rank,best,players}` |
| `GET /v1/leaderboard?mod=prime_sobo&limit=10&offset=0` | `{ok,entries,players}` |
| `GET /v1/leaderboard/around?mod=prime_sobo&player_id=<Steam ID>&span=3` | `{ok,entries,rank,players}` |
| `GET /v1/leaderboard/friends?mod=prime_sobo&ids=<Steam ID,...>` | `{ok,entries}` |

- `limit` は 1〜50、`offset` は 0〜10000、`span` は 0〜24、`ids` は 1〜100 個です。範囲の外は `INVALID_QUERY` になります。
- 表の行は `{rank, steam_id, name, best}` です。around の行には自分かどうかの `you` が付きます。friends の `rank` は世界での順位です。
- POST の本文には `mod`、`mod_version`、`player_id` (SteamID64)、`player_key` (32 バイトの乱数を 16 進で)、`name`、`score`、`duration_s`、`prime_chance` を入れます。4096 バイトまでです。
- 名前は制御文字を除いて 24 文字までに切ります。空なら `anon` になります。
- 点数は 0〜10,000,000 の偶数で、1 秒あたり 50 点まで、試合時間は 10 秒〜1 日です。
- 最初に届いた鍵でその Steam ID を覚え、違う鍵が来たら `KEY_MISMATCH` で断ります。Steam 側での本人確認はしていません。
- 同じ IP からは POST が 60 秒に 10 回、GET が 60 秒に 60 回まで、同じ人の送信は 20 秒に 1 回までです。

サーバは送られた数字の範囲と送る頻度を見るだけで、本当にその点を取ったかまでは確かめられません。

### 保存するもの

| 表 | 中身 |
| --- | --- |
| `players` | Steam ID、鍵の SHA-256、Steam の名前、最高点とその時刻 |
| `submissions` | 受け付けた点数の記録 (断ったものは理由と時刻だけ)。30 日で消えます |
| `rate` | 同じ人の 20 秒の枠 |

鍵そのものと IP アドレスは保存しません。IP は回数を数えるために、秘密を混ぜたハッシュにして一時的に使うだけです。friends only で受け取ったフレンドの一覧も保存しません。

### 配備

`scripts/deploy.ps1` (PowerShell 7.2 以上) を使います。何も付けずに、または `-DryRun` を付けて実行すると、手順を表示するだけで何もしません。

```powershell
pwsh -NoProfile -File scripts/deploy.ps1 -DryRun
pwsh -NoProfile -File scripts/deploy.ps1 -Execute -AccountId <アカウント ID> -HealthUrl https://<Worker のホスト>/v1/health
```

`-Execute` を付けると、D1 の作成 (無ければ)、マイグレーション、秘密の登録、配備、health の確認を順に行います。本番の設定は `wrangler.production.toml` に書かれ、Git には入りません。先に `wrangler login` を済ませておいてください。

MOD は Worker のホストを直には呼びません。Cloudflare Pages の入口 (`pages/`) を呼び、入口はすべての問い合わせをサービスバインディングで Worker へ渡します。Worker には遊んでいる人の IP がそのまま届くので、回数の制限も効きます。Worker を配備してから、入口を配備します。

```powershell
cd pages
npx wrangler pages project create sobosuba-ranking --production-branch main --force   # 初回だけ
npx wrangler pages deploy --branch main --force
```
