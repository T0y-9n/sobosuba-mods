"""Prepare verified catalog files and a patch in a new output directory."""

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import urllib.request
import uuid

from watch_mod_releases import send_notice


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Sobosuba-Catalog-Update"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read(8 * 1024 * 1024 + 1)
    if len(body) > 8 * 1024 * 1024:
        raise ValueError("response too large")
    return body


def run_engine(command, environment):
    options = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
    process = subprocess.Popen(command, env=environment, **options)
    try:
        return process.wait(timeout=180)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=True)
        else:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=30)
        raise


def notify_rejections(args, report):
    state = json.loads(args.state.read_text(encoding="utf-8")) if args.state.exists() else {}
    errors = []
    for rejected in report["rejected"]:
        identity = json.dumps(rejected, sort_keys=True)
        key = hashlib.sha256(identity.encode()).hexdigest()
        if key in state:
            continue
        message = (f"#sobosuba #カタログ #自動更新 [SOBO-CATALOG-AUTO-20261109] "
                   f"【作者新版の拒否】{rejected['id']}の{rejected['version']}は"
                   f"検査で{rejected['reason']}となりました。この候補でカタログを変更していません。")
        try:
            send_notice(args, message, str(uuid.uuid5(uuid.NAMESPACE_URL, identity)))
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append({"id": rejected["id"], "reason": type(error).__name__})
            continue
        state[key] = rejected
        args.state.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.state.with_suffix(args.state.suffix + ".tmp")
        temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(args.state)
    report["notification_errors"] = errors


def run(args):
    source = Path(__file__).resolve().parent.parent
    args.output.mkdir(parents=True, exist_ok=False)
    origin = None
    if args.github_main:
        repository = "T0y-9n/sobosuba-mods"
        reference = json.loads(fetch(f"https://api.github.com/repos/{repository}/git/ref/heads/main"))
        main_sha = reference["object"]["sha"]
        body = fetch(f"https://raw.githubusercontent.com/{repository}/{main_sha}/catalog.json")
        args.catalog = args.output / "input-catalog.json"
        args.catalog.write_bytes(body)
        origin = {"repository": repository, "main_sha": main_sha,
                  "catalog_sha256": hashlib.sha256(body).hexdigest()}
    environment = dict(os.environ)
    for name in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        folder = args.output / "work" / name.lower()
        folder.mkdir(parents=True)
        environment[name] = str(folder)
    command = [str(args.godot), "--headless", "--path", str(source / "manager"),
               "--script", str(source / "tools/prepare_catalog_update.gd"), "--",
               str(args.catalog), str(args.output), str(args.powershell),
               str(args.baseline) if args.check_catalog else "-"]
    returncode = run_engine(command, environment)
    report_path = args.output / "report.json"
    if not report_path.exists():
        return returncode or 1
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if origin is not None:
        report["source"] = origin
    if returncode == 0 and report["changes"]:
        proposed = args.output / "catalog.json"
        bundled = args.output / "manager/catalog.json"
        bundled.parent.mkdir()
        shutil.copyfile(proposed, bundled)
        report["output_catalog_sha256"] = hashlib.sha256(proposed.read_bytes()).hexdigest()
        original = args.catalog.read_text(encoding="utf-8").splitlines(keepends=True)
        updated = proposed.read_text(encoding="utf-8").splitlines(keepends=True)
        patch = "".join("".join(difflib.unified_diff(original, updated,
                         fromfile="a/" + path, tofile="b/" + path))
                        for path in ("catalog.json", "manager/catalog.json"))
        (args.output / "catalog.patch").write_text(patch, encoding="utf-8")
    if args.notify:
        notify_rejections(args, report)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return returncode


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--catalog", type=Path)
    inputs.add_argument("--github-main", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--powershell", type=Path, required=True)
    parser.add_argument("--check-catalog", action="store_true")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--notify", action="store_true")
    parser.add_argument("--state", type=Path)
    parser.add_argument("--board-script", type=Path)
    parser.add_argument("--session")
    parser.add_argument("--to")
    options = parser.parse_args()
    if options.check_catalog and options.baseline is None:
        parser.error("--check-catalog requires --baseline")
    if options.check_catalog and options.github_main:
        parser.error("--check-catalog requires a proposed --catalog")
    if options.notify and not all((options.state, options.board_script, options.session, options.to)):
        parser.error("--notify requires --state, --board-script, --session and --to")
    for field in ("catalog", "output", "godot", "powershell"):
        if getattr(options, field) is not None:
            setattr(options, field, getattr(options, field).resolve())
    if options.baseline is not None:
        options.baseline = options.baseline.resolve()
    try:
        code = run(options)
    except (OSError, ValueError, subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        print(json.dumps({"error": "preparation_failed", "reason": type(error).__name__}))
        code = 1
    raise SystemExit(code)
