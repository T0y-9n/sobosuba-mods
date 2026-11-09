# Changelog

Mod versions are `<sobosuba version>-<mod version>`. Server changes need no new download.

### 1.3.11-1.0.3, 2026-11-09

Fixed: Prime Balls now only works in classic (radix 2). Other modes, including Radix 3 and classic threes, play like the base game again, whether prime mode is on or off.
Fixed: The prime level text no longer jumps between the top and the bottom right.
Changed: 5s now appear more often.

### Special Sobos 1.3.11-0.5.3, 2026-11-09

- Fixed: Special Sobos now only works in classic (radix 2). Other modes, including Radix 3, play like the base game again.

### Unreleased

- Preserved Prime best-score sharing and friend updates in menus and classic runs with prime balls disabled.
- Limited Prime Sobos and Special Sobos to the default classic modes. Other modes, including Radix 3, keep their normal colors, merging, guides and scores with prime balls enabled or disabled.
- Fixed the prime level label switching between panels during play. It follows the native score panel in portrait and landscape layouts and stays in place while the layout is unchanged.
- Increased the weight of 5 in both Prime Sobos versions. Weights for 3, 5, 11, 13 and 19 are now 4:6:2:2:1, so 5 accounts for 40% of prime selections. The overall prime spawn chance is unchanged.

### 1.2.3-1.0.4 and 1.3.11-1.0.2, 2026-11-09

- Added save screenshots directly below send scores in desktop and mobile settings, with labels and descriptions in all 11 game languages.
- Automatic Steam screenshots are now off by default, including for existing settings. Enable the switch to save future game-over screens.

### 1.3.11-1.0.1 and 1.2.3-1.0.3, 2026-11-09

- Smartphone layout support: native mobile settings switches, screen-fitting guide and level labels, and mobile ranking controls.
- Checked with Windows phone-size layouts. Real mobile input and safe areas, and the 1.2.3 native display, remain unverified.

### Special Sobos 1.3.11-0.5.2, 2026-11-09

- Smartphone layout support: mobile settings entry and Back destination, plus portrait and landscape titles that fit. Real-device touch and keyboard checks remain open.

### 1.2.3-1.0.2, 2026-11-02

- More fixes to how a run's mode is saved, found in testing. The mod plays the same.
- After a rare save failure, a normal run is no longer mistaken for a prime run once the disk recovers (which would have kept your score off the game's own leaderboard).

### 1.2.3-1.0.1, 2026-11-01

- Bug fixes found in testing. The mod plays the same, and these are behind-the-scenes fixes, so if `1.2.3-1.0.0` works for you there is no rush to reinstall.
- After sending a score, if the ranking could not be read, it no longer looks as if the score was not sent.
- The end-of-run screenshot is no longer taken for the wrong run when a new run starts during the short delay.
- A rare save failure no longer lets a restart read a prime run as the normal game.
- The scores screen no longer copies stale row data when it is cloned.

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

### 1.2.3-1.0.4 と 1.3.11-1.0.2、2026-11-09

- PCと携帯の設定画面で、send scoresの直下にsave screenshotsを追加しました。ラベルと説明は11言語に対応しています。
- Steamへの自動撮影は既定でオフです。既存の設定にも適用されます。オンにすると、それからの試合終了画面を保存します。

### 1.3.11-1.0.1 と 1.2.3-1.0.3、2026-11-09

- スマートフォン向けに設定入口、案内、レベル表示、ランキング画面の配置を修正しました。Windows上の携帯寸法で確認し、実携帯の入力・安全領域と1.2.3本体の実画面は未確認です。

### Special Sobos 1.3.11-0.5.2、2026-11-09

- 携帯設定への入口と戻り先、縦横の見出しを修正しました。実端末のタッチとキーボード表示時は未確認です。

### 1.2.3-1.0.2、2026-11-02

- 試合のモードの保存まわりのバグ直し (試験で見つけた)。遊び方は同じです。
- まれに保存に失敗した後、通常の試合が素数の試合と間違えられ、点数が本家のランキングに送られなくなることがありました。ディスクが戻れば正しく読まれるように直しました。

### 1.2.3-1.0.1、2026-11-01

- 試験で見つかったバグの直しです。遊び方は同じで、裏側の直しなので、`1.2.3-1.0.0` で困っていなければ急いで入れ直す必要はありません。
- 点数を送った後、ランキングが読めなかったときに、送れていないように見えることがなくなりました。
- 試合終わりのスクショが、短い待ちの間に次の試合が始まると別の試合のものになることがなくなりました。
- まれな保存の失敗で、再開時に素数試合を通常試合として読むことがなくなりました。
- スコア画面を複製するときに、古い行のデータを写すことがなくなりました。

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
