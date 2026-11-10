# Sobosuba Mod Manager 0.3.0-alpha.9

Checked on Windows with dedicated test game and user-data folders.

- Original-game credit and purchase links appear in MOD details and installation confirmations in all 22 manager languages.
- Missing or incorrect package credit displays a warning. The confirmation button remains available. Required MODs retain their own warnings after installation.
- The real author-release and automatic-update paths were exercised, including update preferences and preservation of existing settings and save-marker files.
- Final checks covered 37 package assertions, 448 visible-interface assertions, 36 author-release assertions and 26 automatic-update assertions, all with zero failures. The final processes exited with code 0, no logged errors and no shutdown resource warnings.
- Earlier test attempts encountered a test-data selection error, Windows path-length failures and 14 shader-cache file errors. The corrected test setup produced the final results above.
- TypeScript checking succeeded. The broader server suite retains failures caused by missing runtime configuration and existing source-check mismatches. Two version-document checks were corrected and checked again.

Linux desktop behavior, gameplay, smartphone hardware, long sessions and every MOD combination remain unverified. Export and packaged startup are checked separately before publication.
