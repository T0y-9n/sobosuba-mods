# Manager alpha.7 validation

This release adds game-specific catalog variants without changing the original mod ZIPs or their install layouts.

The catalog regression ran against the earlier reader first: 5 checks, 1 failure because game-specific selection was absent. After the change, all 44 checks succeeded. Independent review then found that an original catalog row without game_versions was excluded from exact dependency lookup. The expanded 48-check regression reproduced that failure and succeeded after the narrow correction. The checks cover both game families, exact dependency versions, SHA selection, malformed variants, ambiguous choices and update isolation.

The actual manager scene was exercised with the original published Prime Sobos ZIPs in dedicated game and user-data folders. The initial run reproduced the missing modern release and install action. The updated scene downloaded the original 1.3.11 ZIP from its catalog URL, checked its SHA, opened the normal installation plan and installed it while preserving the 1.2.3 payload and receipt.

One UI assertion initially counted other mods as Prime Sobos rows; the test was corrected to count only the Prime Sobos ID. That correction initially had a test-script type inference error, which was fixed with an explicit Array type. The final actual-scene run succeeded on all 15 checks. Successful runs had no errors or shutdown resource warnings.

The test fixtures use an empty sobosuba.exe marker, as permitted for manager-only tests. No real game or personal save folder was opened. Original Prime ZIPs retain their published hashes:

- 1.2.3-1.0.2: `7a7130cf61b2e494d6208446c149cf96b1379e85f0cc6b84dfb2eaacc3115df0`.
- 1.3.11-1.0.0: `8c1a9925472d8a1c9c089f7af65b1fe6848c9227bafc98d0a7361e0dce12d35e`.

Game 1.3.10 has historical operation evidence, but the current 1.3.11 ZIP declares only 1.3.11. This release does not alter that declaration. Real gameplay, every mod combination, Linux desktop operation and long sessions are outside these checks.

To reproduce the manager checks on Windows, create a new empty QA destination with `python server/test/prepare_catalog_variants.py <QA-folder>`. Use isolated APPDATA and LOCALAPPDATA beneath that folder for each Godot run. Run `server/test/catalog_variants.gd` with arguments `<manager-source-folder> <QA-folder>`. For `server/test/catalog_variants_ui.gd`, open the manager project and set PRIME_QA to the same QA folder. The UI test refuses to run when its application data directory is outside PRIME_QA.
