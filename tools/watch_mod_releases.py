"""Check named catalog repositories once. Never modify the catalog or install mods."""

import argparse
import datetime
import json
import re
import subprocess
import urllib.request
import uuid
from pathlib import Path


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def send_notice(args, message, operation_key):
    command = ["node", str(args.board_script), "decide", "--session", args.session,
               "--repo", "sobosuba-mods", "--scope", "sobosuba", "--to", args.to,
               "--what", message, "--why", "指定された作者Releaseの確認結果。",
               "--operation-key", operation_key]
    subprocess.run(command, check=True)


def fetch_releases(repository):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/releases?per_page=100",
        headers={"User-Agent": "Sobosuba-Catalog-Watcher", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read(8 * 1024 * 1024 + 1)
    if len(body) > 8 * 1024 * 1024:
        raise ValueError("release response too large")
    releases = json.loads(body)
    if not isinstance(releases, list):
        raise ValueError("invalid release list")
    return releases


def version_parts(value):
    match = re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", value)
    if not match or any(len(match[i]) > 9 for i in (1, 2, 3)):
        return None
    pre = match[4].replace("-", ".").split(".") if match[4] else []
    if any(part.isdigit() and (len(part) > 9 or (len(part) > 1 and part[0] == "0")) for part in pre):
        return None
    return tuple(int(match[i]) for i in (1, 2, 3)), pre


def newer(candidate, current):
    left, right = version_parts(candidate), version_parts(current)
    if left is None or right is None:
        return False
    if left[0] != right[0]:
        return left[0] > right[0]
    if not left[1] or not right[1]:
        return bool(right[1]) and not left[1]
    for a, b in zip(left[1], right[1]):
        if a == b:
            continue
        return a.isdigit() and b.isdigit() and int(a) > int(b)
    return len(left[1]) > len(right[1])


def latest(entry, releases):
    source = entry["source"]
    repository, prefix, pattern = source["github"], source.get("tag_prefix", ""), source["asset"]
    best = None
    for release in releases:
        if not isinstance(release, dict) or release.get("draft", True):
            continue
        if release.get("prerelease", True) and source.get("prerelease") is not True:
            continue
        tag = release.get("tag_name", "")
        if not isinstance(tag, str) or not tag.startswith(prefix):
            continue
        # Game-version prefixes stay in the MOD version. Strip only a nonnumeric wrapper.
        version = tag.removeprefix("v")
        if version_parts(version) is None:
            wrapper = re.match(r"^[^0-9]+", prefix)
            version = tag.removeprefix(wrapper[0]) if wrapper else ""
        if not newer(version, entry["version"]) or (best and not newer(version, best["version"])):
            continue
        name = pattern.replace("{version}", version)
        for asset in release.get("assets", []):
            digest = asset.get("digest", "")
            url = f"https://github.com/{repository}/releases/download/{tag}/{name}"
            if (asset.get("name") == name and asset.get("browser_download_url") == url
                    and isinstance(digest, str) and re.fullmatch(r"sha256:[a-fA-F0-9]{64}", digest)
                    and isinstance(asset.get("size"), int) and 0 < asset["size"] <= 32 * 1024 * 1024):
                best = {"id": entry["id"], "version": version, "baseline": entry["version"],
                        "repository": repository, "tag": tag, "zip": url, "digest": digest.lower()}
    return best


def run(args):
    catalog = read_json(args.catalog)
    state = read_json(args.state) if args.state.exists() else {"announced": {}}
    announced = state.get("announced", {})
    repositories, candidates, errors = {}, [], []
    for mod in catalog["mods"]:
        for variant in [mod, *mod.get("variants", [])]:
            entry = {**mod, **variant}
            source = variant.get("source")
            if not source:
                continue
            repository = source.get("github", "")
            if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", repository)
                    or not isinstance(source.get("asset"), str)
                    or source["asset"].count("{version}") != 1
                    or not source["asset"].endswith(".zip")
                    or not isinstance(source.get("tag_prefix", ""), str)):
                errors.append({"id": entry["id"], "reason": "invalid_source"})
                continue
            entry["source"] = source
            if repository not in repositories:
                try:
                    repositories[repository] = fetch_releases(repository)
                except (OSError, ValueError) as error:
                    repositories[repository] = None
                    errors.append({"repository": repository, "reason": type(error).__name__})
            if repositories[repository] is None:
                continue
            candidate = latest(entry, repositories[repository])
            if candidate:
                candidates.append(candidate)
    for candidate in candidates:
        key = candidate["id"] + "|" + candidate["baseline"]
        fingerprint = candidate["version"] + "|" + candidate["digest"]
        if not args.notify or announced.get(key) == fingerprint:
            continue
        message = (f"#sobosuba #カタログ [SOBO-AUTO-FOLLOW-20261109] 【作者の新版候補】"
                   f"{candidate['id']}はカタログ{candidate['baseline']}に対し、"
                   f"{candidate['repository']}の{candidate['tag']}が出ています。"
                   "カタログは変更していません。掲載前に作者READMEとZIPの作者表示・対応版を確認してください。")
        try:
            send_notice(args, message, str(uuid.uuid5(uuid.NAMESPACE_URL, candidate["zip"] + "|" + candidate["digest"])))
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append({"id": candidate["id"], "reason": "notification_failed",
                           "error": type(error).__name__})
            continue
        announced[key] = fingerprint
        args.state.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.state.with_suffix(args.state.suffix + ".tmp")
        temporary.write_text(json.dumps({"announced": announced}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(args.state)
    print(json.dumps({"checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      "repositories": len(repositories), "candidates": candidates, "errors": errors}, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--notify", action="store_true")
    parser.add_argument("--board-script", type=Path)
    parser.add_argument("--session")
    parser.add_argument("--to")
    arguments = parser.parse_args()
    if arguments.notify and not all((arguments.board_script, arguments.session, arguments.to)):
        parser.error("--notify requires --board-script, --session and --to")
    raise SystemExit(run(arguments))
