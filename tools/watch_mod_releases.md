# Catalog release watcher

Run watch_mod_releases.py once with Python 3.9 or later, --catalog pointing to the reviewed local catalog and --state pointing to a persistent writable JSON path. The command reads each named GitHub repository once and prints the newer release candidates. It never edits the catalog or installs a ZIP.

To send new candidates to the shared board, add --notify, --board-script pointing to the existing Code-Rei bin/board.mjs, --session with the assigned full seat UUID, and --to with the coordinator UUID. Node must be on PATH. Only a successful board command is remembered. Candidate-specific operation keys prevent duplicate posts after a lost response.

A failed board command is listed in the JSON error summary and remains eligible for retry. The run continues with the other candidates and exits with code 1 when any request or notification failed.

The Thor operator should schedule this single-run command four times per day using the existing scheduler. A systemd oneshot service and timer can prevent overlapping runs. This repository does not install or start a host service. Keep the reviewed source and state paths in that host's existing service configuration. The catalog baseline remains subject to manual review, including the author's README, ZIP credit, game versions and SHA256.
