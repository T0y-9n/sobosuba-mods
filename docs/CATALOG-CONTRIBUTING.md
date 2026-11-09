# Catalog contributions / カタログへの掲載

The authoritative catalog is `catalog.json` on this GitHub repository’s `main` branch. Authors request additions through a GitHub PR. A maintainer reviews and merges each new MOD entry. The issue form can help authors prepare a PR.
カタログの正本は、このGitHubリポジトリの`main`にある`catalog.json`です。作者はGitHubのPRで追加を申請してください。新しいMODは人が確認して合流します。PRの準備を依頼するIssueフォームも利用できます。

[Catalog / 正本のカタログ](https://github.com/T0y-9n/sobosuba-mods/blob/main/catalog.json) · [Open a PR / PRを作る](https://github.com/T0y-9n/sobosuba-mods/compare) · [Request help / 掲載準備を依頼する](https://github.com/T0y-9n/sobosuba-mods/issues/new?template=catalog-request.yml)

## Required evidence / 必要な情報

- Publish a GitHub Release with a nonempty ZIP asset of at most 32 MiB. Its API asset `digest` must be `sha256:` followed by 64 hexadecimal characters and match the downloaded ZIP. Put the 64-character hash in the catalog’s `sha256` field.
  GitHub Releaseに空ではない32 MiB以下のZIP資材を公開してください。APIの資材`digest`は`sha256:`と64桁の16進数で、実際に取得したZIPと一致する必要があります。カタログの`sha256`には64桁のハッシュを記載します。
- Give each row and variant a `source` identifying the author repository, tag prefix and ZIP filename pattern. The ZIP URL must belong to that repository’s Release and match the pattern. `{version}` appears once and expands to the metadata version. Set `prerelease` to `true` when that source should include prereleases.
  各行とvariantの`source`に、作者のリポジトリ、タグの接頭辞、ZIP名の型を指定してください。ZIPのURLはそのリポジトリのReleaseに属し、型と一致する必要があります。`{version}`は1か所に置き、定義書の版へ置き換えます。先行公開版も対象にする公開元では`prerelease`を`true`にします。

```json
{
  "source": {
    "github": "owner/repository",
    "tag_prefix": "v",
    "asset": "Example-{version}.zip"
  }
}
```

- The ZIP metadata read by the manager (`mod-package.json`, or `mods/<id>/mod.json` for that layout) must have the catalog `id`, the version derived from the Release tag, and a `game_versions` array compatible with the selected game version. Updates must retain the listed installation layout.
  管理アプリが読むZIP内の定義書（`mod-package.json`、またはその導入形式の`mods/<id>/mod.json`）に、カタログと同じ`id`、Releaseのタグに対応する版、選択したゲーム版に対応する`game_versions`配列が必要です。更新では掲載済みの導入形式を保ちます。
- The ZIP metadata must contain these exact `game_credit` values. The author repository’s README at the Release tag must name sobosuba and keepee and include the same Steam store URL, so players can reach the original game.
  ZIPの定義書には、次の固定値と完全に一致する`game_credit`が必要です。Releaseのタグ時点の作者リポジトリのREADMEにも、sobosuba、原作者keepeeさん、同じSteam購入先を記載してください。MODから原作へたどれるようにするための条件です。

```json
{
  "game_credit": {
    "text": "sobosuba by keepee",
    "store_url": "https://store.steampowered.com/app/1946560/sobosuba"
  }
}
```

## Review and updates / 検査と更新

Include the author repository, Release, ZIP, digest and tagged README in the PR. Edit `catalog.json`. If you also change `manager/catalog.json`, keep it byte-identical to `catalog.json`. Checks fetch the actual API data, ZIP and README and apply the manager’s release-verification rules. New MOD additions require human review and merge.
PRには作者リポジトリ、Release、ZIP、digest、タグ時点のREADMEを添えてください。`catalog.json`を編集します。`manager/catalog.json`も変更する場合は、`catalog.json`と同じバイトにそろえます。検査では実際のAPI情報・ZIP・READMEを取得し、管理アプリと同じ受入条件で確認します。新しいMODの追加は、人が確認して合流します。

Thor can propose newer releases of already listed MODs through GitHub PRs. Those update PRs may merge automatically after the same checks succeed.
掲載済みMODの新版は、ThorがGitHubへ更新PRを作ります。同じ検査が通った更新PRは自動で合流できます。
