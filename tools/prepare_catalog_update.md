# Verified catalog proposal

Run prepare_catalog_update.py with --github-main to read the authoritative GitHub catalog at an immutable main SHA. Use --catalog for a reviewed local copy. Set --output to a new empty destination, --godot to Godot 4.7.2 and --powershell to the host's PowerShell executable. The command runs one headless engine and invokes the existing manager release selection, verification and package reader. It downloads archives for inspection. Package scripts are never executed.

The command writes report.json with accepted changes, rejected candidate versions and reasons, and communication or source errors. A successful run with accepted changes also writes catalog.json, an identical manager/catalog.json and catalog.patch. Only version, zip, sha256, game_versions and game_credit change within each accepted existing row or variant. Other fields and variants retain their values. A run with no accepted change writes only the report and temporary download data. Source and communication errors produce a nonzero exit and no patch. Rejected candidates can coexist with accepted ones in a successful report.

The report records the authoritative repository, main SHA and original catalog SHA256 when --github-main is used. Existing source defaults come from the reviewed manager catalog for verification and are kept out of the five-field update. Add --notify with --state, --board-script, --session and --to to announce each rejected candidate and reason once through the shared board. Failed announcements remain eligible for retry and are recorded separately from verification results.

Use --check-catalog --catalog proposed.json --baseline original.json to verify changed or added entries in an author PR. That mode checks the proposed version against its actual release, digest, archive and README. Its nonzero exit rejects the proposal. The GitHub workflow runs only the base commit's verification code and reads the PR's catalogs as data. Its success artifact identifies the PR head, base, run and input checksum. New MOD submissions require human review.

After preparing an authoritative proposal, run submit_catalog_update.py with --report and --catalog to perform a read-only dry run. Explicit --submit creates or reuses a GitHub PR for existing entries only. The fixed sender branch serializes submissions, and overlapping candidates in open PRs stop a duplicate proposal. The sender verifies that the main SHA is current and that only the five verified fields differ. It requests automatic merge only after validating the latest trusted workflow run's successful artifact for that exact PR head and catalog. A newer queued, running or failed run blocks that request. Missing authentication or disabled automatic merge stops submission. Automatic merge also requires the catalog-validation check on main and strict up-to-date branch protection. A trusted workflow publishes the successful validation record on the current PR head. Initial deployment must confirm that a changed base blocks merge until the PR is updated and checked again. Token creation and storage belong to the operator. These commands do not install MODs or alter input files.

GitHub main is the catalog authority. GitCo's root and bundled catalogs are synchronized copies. Before replacing those copies, reviewed source declarations must also exist in the GitHub catalog so a synchronization retains author discovery. The initial publication of the trusted verifier and workflow needs its own reviewed deployment. The previous single-run watcher remains deployed until the coordinator replaces the schedule with this preparation and submission flow.

Use the host's existing engine scheduling and whole-process-tree timeout around this command. The command also stops the engine process tree after its 180-second limit. On Thor, both the engine and PowerShell must already be available. The command does not register GitCo credentials or install runtimes. Its isolated application-data and download files are under output/work. After retaining the result in the board or maintained documentation, remove that temporary output according to the host's cleanup instructions.

## 運用

--github-mainでGitHub正本の不変SHAを読み、--catalogで手元の写しを検査します。--outputには新しい出力先、--godotにはGodot 4.7.2、--powershellにはホストの実行ファイルを指定します。管理アプリの既存の検査とZIP読取りを直接使い、採用した既存項目の5フィールドだけを変更します。拒否理由はreport.json、採用した案は同じバイトの2つのカタログとcatalog.patchへ保存します。

作者PRは--check-catalog、--catalog、--baselineで検査します。GitHubの検査は基底側のコードを使い、PRのカタログをデータとして読みます。新しいMODの合流は人が判断します。作者は正本だけを編集でき、同梱の写しも変更する場合は正本と同じバイトにします。Thorの更新PRは両方をそろえます。

送信は別のsubmit_catalog_update.pyです。既定は読取りだけで、--submitを付けたときにPRを作成します。開いているPRとの更新対象の重複を確認し、固定の送信枝で同時送信を制限します。成功した検査のPR、版、基底、入力SHAを照合し、mainのcatalog-validation必須設定と最新基底への追随必須を確認してから自動合流を依頼します。読み取り専用検査の最新の実行と成功記録を信頼した別workflowが照合し、現在のPR headへ検査中・失敗・成功を渡します。新しい検査が失敗した場合は古い成功へ後退しません。最初の運用では、基底変更後に合流が止まり、PRを最新化して再検査されることを実際に確認する必要があります。

GitHubが正本で、GitCoの2つのカタログは写しです。GitHubで合流した不変SHAから両方を取り、同じバイトへそろえ、GitCoの通常PRで写しだけを合わせます。写しを正本へ逆送しません。source宣言をGitHubへ先に反映してから同期します。

Thorの認証値の作成と置き場、GitHubの運用設定、最初の検証コードとworkflowの公開は司令官の判断が必要です。配置と定期実行の差し替えは統括が行います。ホストの実機枠とプロセス木の時間制限を使い、専用出力を片付ける際はホストの保持境界に従ってください。
