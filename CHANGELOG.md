# Changelog

Mod versions are `<sobosuba version>-<mod version>`. Server changes need no new download.

### Mod Manager 0.3.0-alpha.10, 2026-11-13

- Set the mod load order from the mod details: move a mod earlier or later. The order is saved as `mod_load_order.json` in the game's user data folder. Mods released with the new loader follow it, starting with Sobo Crash Fix 1.3.11-1.0.0. Other mods keep their current order until their next release.
- Fix updates that stopped with a file conflict when the newer release's files had already been copied in by hand. Files that already match the new release no longer count as changed. A managed file you edited yourself still stops the update.

### Sobo Crash Fix 1.3.11-1.0.0, 2026-11-13

- First release. Stops a game crash when a sobo is removed, by a merge or at the end of a run, while the game is still pushing it apart from another sobo. Changes nothing else. Works with or without other mods. Not needed once the game fixes the crash.

### Catalog update automation, unreleased

- Bind validation results to the workflow run's pull-request head and recorded base separately, while requiring the base to remain current main.
- Prepare updates to existing catalog entries through the manager's release verification and package reader. Record rejected releases with their reasons and produce matching catalog copies and a reviewable patch for accepted releases.
- Add bilingual GitHub contribution instructions, a PR template, an issue form and read-only catalog validation using trusted base code.
- Add a separate GitHub PR sender with explicit submission, duplicate-update checks and required up-to-date validation. Deployment requires operator-approved credentials and GitHub repository settings.

### Mod Manager 0.3.0-alpha.9, 2026-11-10

- Show the original game's creator and store link in mod details and installation confirmations. Missing or incorrect package credit now produces a warning and allows installation, including dependencies and author-release updates. GitHub README credit checks also warn in the manager. Catalog contribution checks still require the credit.
- Check the catalog's named GitHub repositories for newer compatible mod releases, verify their release digests and package metadata, and use the existing per-mod automatic update settings. Keep the last check result available offline and show why a release could not be accepted.
- Add a single-run release watcher for Thor to report catalog updates without changing the catalog.
- Keep verified author updates available when their display history cannot be saved, and show the storage error. Continue checking other candidates after a watcher notification fails.

### Mod Manager 0.3.0-alpha.8, 2026-11-09

- Fixed labels disappearing when a checked control is hovered or a selection menu is open. The shared theme now supplies matching text and background colors for these states.
- Download errors now distinguish connection failures, HTTP responses, invalid SHA256 metadata, conflicting dependency and catalog hashes, mismatched bytes and storage failures in all 22 manager languages.

### Special Sobos 1.3.11-0.6.2, 2026-11-12

- Add tornado, liquid and dark matter sobos. Tornado stirs the sobos around it, liquid spreads out and sinks, and dark matter hides its shape (random) and its number. It merges only with the same number.
- The three new kinds have settings too, with their own switches and frequencies.

### Special Sobos 1.3.11-0.5.7, 2026-11-10

- Add **Import settings** under **Export settings**. Choose a `special_sobos_settings_*.json` file in the in-game file window, opened in Downloads. Values outside the allowed range, or of the wrong type, stay as they are. Readable values are saved and applied to the current board and the next run. A file that is not JSON, or not a settings file, changes nothing.

### Special Sobos 1.3.11-0.5.6, 2026-11-10

- Add **Export settings** to the Special Sobos settings screen. Save the current switches, kind choices and numeric values as JSON in Downloads, with the mod version and export time.
- Show the saved file path. Keep earlier exports and fall back to the game's user-data folder when Downloads is unavailable. Show an error if neither location can be written.

### Special Sobos 1.3.11-0.5.5, 2026-11-10

- Add the original-game credit and purchase link to the package metadata and included README. Include this changelog. Gameplay is unchanged.

### 1.3.11-1.0.7, 2026-11-12

- 7 now appears at the same weight as 3. A 7 merges only with a 7 into 14, and can keep doubling up to 458752. It stays gray. It does not score.
- From 14 up (14 + 2 = 16, 28 + 4 = 32, 56 + 8 = 64 ...), it merges with these sobos and becomes an ordinary sobo.
- The prime balls switch is only under Settings → game. The same switch on the game's how-to-play screen is removed.

### 1.2.3-1.0.6 and 1.3.11-1.0.5, 2026-11-10

- Include the original-game credit, purchase link and current changelog in both game-version packages. Add the missing credit to the 1.2.3 package metadata. Gameplay is unchanged.

### Special Sobos 1.3.11-0.5.4, 2026-11-09

Added: If the game freezes, the log now shows what Special Sobos was doing.

### 1.3.11-1.0.4, 2026-11-09

Added: If the game freezes, the log now shows what Prime Sobos was doing.

### 1.2.3-1.0.5, 2026-11-09

Added: If the game freezes, the log now shows what Prime Sobos was doing.
Changed: On game 1.2.3, prime sobos use nearby native sizes. Existing saved prime sobos are adjusted when loaded.

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

### 管理アプリ0.3.0-alpha.10、2026-11-13

- MOD の説明欄で、読み込みの順を前後に動かせるようにした。順はゲームのユーザーデータの `mod_load_order.json` に保存する。従うのは新しい読み込みの仕組みで出した MOD で、まず Sobo Crash Fix 1.3.11-1.0.0。ほかの MOD は次の版から従う。
- 新しい版のファイルを手で写した後の更新が、ファイルの競合で止まらないようにした。新しい版と同じ中身のファイルは、変えたファイルとして扱わない。自分で書き換えた管理中のファイルがあれば、今までどおり更新を止める。

### Sobo Crash Fix 1.3.11-1.0.0、2026-11-13

- 初めての公開。ソボが合体や回の終わりで消えるとき、本家がそのソボを別のソボから押し離している途中だと、ゲームがクラッシュする。それを止めるようにした。ほかは何も変えない。ほかの MOD があってもなくても使える。本家で直れば要らなくなる。

### Special Sobos 1.3.11-0.6.2、2026-11-12

- トルネード・液体・ダークマターのソボを追加しました。トルネードは周りのソボをかき混ぜ、液体は広がって沈み、ダークマターは形状（ランダム）と数字が隠されています。同じ数字とだけ合体します。
- 新しい 3 種にも設定を用意し、スイッチと出現比率を用意しています。

### 管理アプリ0.3.0-alpha.9、2026-11-10

- 原作の作者表示と購入先を説明欄と導入確認に表示します。作者表示が欠けたZIPは警告を表示して導入を続けられます。依存MODと作者Releaseの更新でも同じ扱いです。GitHub READMEの作者表示を確認できない場合も警告します。カタログへの掲載検査では作者表示を引き続き確認します。

### Special Sobos 1.3.11-0.5.5、2026-11-10

- 配布ZIPの定義書とREADMEに原作の作者表示と購入先を追加し、チェンジログを同梱しました。

### 1.3.11-1.0.7、2026-11-12

- 7 を、3 と同じ重みで出現するようになります。7 は 7 とだけ合体して 14 になり、458752 まで倍になりえます。灰色のままです。点は入りません。
- 14 以上で（14 + 2 = 16、28 + 4 = 32、56 + 8 = 64 ・・・）これらのソボと合体して、普通のソボになります。
- 素数の玉のスイッチを「設定 → ゲーム」だけにした。本家の遊び方の画面にあった同じスイッチを外しました。

### 1.2.3-1.0.6と1.3.11-1.0.5、2026-11-10

- 両方の配布ZIPに原作の作者表示、購入先、今回のチェンジログをそろえました。1.2.3版の定義書にも作者表示を追加しました。

### Special Sobos 1.3.11-0.5.4、2026-11-09

- 固まったとき、特別なソボがどこを処理していたかと盤面をログへ出す機能を追加しました。

### 1.3.11-1.0.4、2026-11-09

- 固まったとき、素数ソボがどこを処理していたかと盤面をログへ出す機能を追加しました。

### 1.2.3-1.0.5、2026-11-09

- 固まったとき、素数ソボがどこを処理していたかと盤面をログへ出す機能を追加しました。
- 素数の玉を近い本家の大きさへ変更し、保存済みの素数玉も読込み時に合わせます。

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
