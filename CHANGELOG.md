# Changelog

Mod versions are `<sobosuba version>-<mod version>`. Server changes need no new download.

### README, 2026-10-31

- How to install on Linux: put `override.cfg` next to the game's executable and change the path inside it. The mod and the zip are unchanged, so there is nothing to reinstall.

### 1.2.3-1.0.0, 2026-10-31

- The version name now matches the game. sobosuba's version is 1.2.3, so this mod is `1.2.3-1.0.0`. The first release was named `1.23-1.0.0` by mistake.
- It plays the same as `1.23-1.0.0`. If you already have that one, you don't have to reinstall, and its scores still go to the world ranking. The new zip only changes the version it reports and fixes the developers' self-test.

### Server, 2026-10-31

- The world ranking reads much less from its database per request. A game end used to read about 12 rows for every player on the board; now it reads about one row for each player ranked above you. This keeps the ranking within the free plan's daily limit as more people play.
- Ranks and the order are the same as before. The mod and the zip are unchanged, so there is nothing to reinstall.

### 1.23-1.0.0, 2026-10-31

- First public release, made for sobosuba 1.2.3 (named `1.23` by mistake).

## 日本語

MOD の版は `<sobosuba の版>-<MOD の版>` です。サーバの変更では、入れ直しは要りません。

### README、2026-10-31

- Linux での入れ方を足しました。`override.cfg` をゲームの実行ファイルの横に置き、中のパスを直します。MOD と zip は変わっていないので、入れ直しは要りません。

### 1.2.3-1.0.0、2026-10-31

- 版の名前を本家に合わせました。sobosuba の版は 1.2.3 なので、この MOD は `1.2.3-1.0.0` です。最初の公開版は誤って `1.23-1.0.0` と名付けていました。
- 遊び方は `1.23-1.0.0` と同じです。すでに入れている人は入れ直さなくてかまいません。点数もこれまでどおり世界ランキングに届きます。新しい zip で変わるのは、送る版の名前と、開発用の自己試験の直しだけです。

### サーバ、2026-10-31

- 世界ランキングのサーバが、1 回に読むデータを大きく減らしました。試合が終わるたびに、ランキングに載っている人数の約 12 倍の行を読んでいたのを、自分より上の人数ぶんほどに減らしました。遊ぶ人が増えても、無料の枠の 1 日の上限に届きにくくなります。
- 順位の付け方は今までと同じです。MOD と zip は変わっていないので、入れ直しは要りません。

### 1.23-1.0.0、2026-10-31

- 初めての公開版。sobosuba 1.2.3 向け (名前は誤って `1.23` としていました)。
