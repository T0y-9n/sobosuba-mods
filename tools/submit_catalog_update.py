"""Open a verified catalog update PR. Writes require --submit."""

import argparse
import base64
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlencode
import zipfile


REPOSITORY = "T0y-9n/sobosuba-mods"
WORKFLOW_PATH = ".github/workflows/catalog-check.yml"
FIELDS = {"version", "zip", "sha256", "game_versions", "game_credit"}
PATHS = {"catalog.json", "manager/catalog.json"}
SUBMISSION_BRANCH = "catalog-update/verified-releases"


class SubmissionError(Exception):
    pass


class GitHub:
    def __init__(self, executable):
        self.executable = executable
        self.environment = dict(os.environ, GH_HOST="github.com", GH_PROMPT_DISABLED="1")

    def command(self, arguments, body=None):
        try:
            result = subprocess.run(
                [self.executable, *arguments],
                input=json.dumps(body).encode("utf-8") if body is not None else None,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.environment,
                timeout=90, check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            raise SubmissionError("github_cli_unavailable") from None
        return result

    def api(self, endpoint, body=None, method="GET", missing=False, raw=False, repository=REPOSITORY):
        arguments = ["api", "--hostname", "github.com", "--method", method,
                     "repos/" + repository + ("/" + endpoint if endpoint else "")]
        if body is not None:
            arguments.extend(["--input", "-"])
        result = self.command(arguments, body)
        if result.returncode:
            if missing and b"HTTP 404" in result.stderr:
                return None
            reason = "github_auth_required" if b"HTTP 401" in result.stderr else "github_api_failed"
            raise SubmissionError(reason)
        if raw:
            return result.stdout
        try:
            return json.loads(result.stdout)
        except (ValueError, UnicodeDecodeError):
            raise SubmissionError("github_response_invalid") from None

    def pages(self, endpoint, field=None):
        entries = []
        page = 1
        while True:
            document = self.api(endpoint + ("&" if "?" in endpoint else "?") + urlencode({"per_page": 100, "page": page}))
            rows = document.get(field) if field else document
            if not isinstance(rows, list):
                raise SubmissionError("github_response_invalid")
            entries.extend(rows)
            if len(rows) < 100:
                return entries
            page += 1

    def catalog(self, reference, path="catalog.json", repository=REPOSITORY, missing=False):
        document = self.api("contents/" + path + "?" + urlencode({"ref": reference}), repository=repository, missing=missing)
        if document is None:
            return None
        if document.get("encoding") != "base64" or not isinstance(document.get("content"), str):
            raise SubmissionError("github_catalog_invalid")
        try:
            return base64.b64decode("".join(document["content"].split()), validate=True)
        except ValueError:
            raise SubmissionError("github_catalog_invalid") from None


def digest(content):
    return hashlib.sha256(content).hexdigest()


def validate_changes(original, proposed, changes):
    if not isinstance(changes, list) or not changes:
        raise SubmissionError("verified_changes_required")
    expected = copy.deepcopy(original)
    seen = set()
    for change in changes:
        mod_id, variant = change.get("id"), change.get("variant")
        if not isinstance(mod_id, str) or type(variant) is not int or variant < -1:
            raise SubmissionError("change_identity_invalid")
        key = (mod_id, variant)
        rows = [row for row in expected["mods"] if row.get("id") == mod_id]
        if key in seen or len(rows) != 1:
            raise SubmissionError("existing_mod_required")
        seen.add(key)
        row = rows[0]
        if variant >= 0:
            variants = row.get("variants", [])
            if variant >= len(variants):
                raise SubmissionError("existing_variant_required")
            row = variants[variant]
        before, after = change.get("before"), change.get("after")
        if not isinstance(before, dict) or not isinstance(after, dict) or set(before) != FIELDS or set(after) != FIELDS:
            raise SubmissionError("only_release_fields_allowed")
        if before != {field: row.get(field) for field in FIELDS} or before["version"] == after["version"]:
            raise SubmissionError("verified_baseline_mismatch")
        row.update(after)
    if expected != proposed:
        raise SubmissionError("catalog_contains_unverified_changes")


def catalog_entries(content):
    if content is None:
        return {}
    document = json.loads(content)
    entries = {}
    for row in document["mods"]:
        root = copy.deepcopy(row)
        root.pop("variants", None)
        entries[(row["id"], -1)] = root
        for index, variant in enumerate(row.get("variants", [])):
            entries[(row["id"], index)] = variant
    return entries


def changed_entries(before, after):
    old, new = catalog_entries(before), catalog_entries(after)
    return {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}


def matching_pull_request(github, changes):
    requested = {(change["id"], change["variant"]) for change in changes}
    matching = None
    for pull in github.pages("pulls?state=open"):
        files = github.pages("pulls/" + str(pull["number"]) + "/files")
        paths = {item["filename"] for item in files}
        paths.update(item["previous_filename"] for item in files if "previous_filename" in item)
        touched = set()
        root_before = root_after = None
        baseline = pull["base"]["sha"]
        if paths & PATHS:
            comparison = github.api("compare/" + baseline + "..." + pull["head"]["sha"])
            baseline = comparison["merge_base_commit"]["sha"]
        canonical_before = github.catalog(baseline) if paths & PATHS else None
        for path in sorted(paths & PATHS):
            before = canonical_before
            after = github.catalog(pull["head"]["sha"], path, repository=pull["head"]["repo"]["full_name"], missing=True)
            touched.update(changed_entries(before, after))
            if path == "catalog.json":
                root_before, root_after = before, after
        if not requested & touched:
            if pull["head"]["repo"]["full_name"] == REPOSITORY and pull["head"]["ref"] == SUBMISSION_BRANCH:
                raise SubmissionError("submission_branch_busy")
            continue
        if (matching is not None or touched != requested or not paths <= PATHS or root_before is None
                or root_after is None or pull["base"]["ref"] != "main"
                or pull["head"]["repo"]["full_name"] != REPOSITORY
                or not pull["head"]["ref"].startswith("catalog-update/")):
            raise SubmissionError("overlapping_open_pull_request")
        previous, proposed = catalog_entries(root_before), catalog_entries(root_after)
        replay = []
        for change in changes:
            key = (change["id"], change["variant"])
            before = {field: previous.get(key, {}).get(field) for field in FIELDS}
            after = {field: proposed.get(key, {}).get(field) for field in FIELDS}
            if after != change["after"]:
                raise SubmissionError("overlapping_open_pull_request")
            replay.append({"id": key[0], "variant": key[1], "before": before, "after": after})
        validate_changes(json.loads(root_before), json.loads(root_after), replay)
        matching = pull
    return matching


def validate_pull_request(github, pull, branch, content):
    if (pull["base"]["ref"] != "main" or pull["base"]["repo"]["full_name"] != REPOSITORY
            or pull["head"]["ref"] != branch or pull["head"]["repo"]["full_name"] != REPOSITORY):
        raise SubmissionError("pull_request_identity_mismatch")
    head = pull["head"]["sha"]
    files = github.pages("pulls/" + str(pull["number"]) + "/files")
    names = {item["filename"] for item in files}
    if not {"catalog.json"} <= names <= PATHS or len(files) > 2:
        raise SubmissionError("pull_request_files_mismatch")
    for path in sorted(PATHS):
        if github.catalog(head, path) != content:
            raise SubmissionError("pull_request_content_mismatch")
    return head


def verified_ci(github, pull, head, content):
    workflow = github.api("actions/workflows/catalog-check.yml", missing=True)
    if workflow is None or workflow.get("path") != WORKFLOW_PATH:
        return {}
    runs = github.pages("actions/workflows/" + str(workflow["id"]) + "/runs?" + urlencode(
        {"event": "pull_request_target", "head_sha": pull["base"]["sha"]}), field="workflow_runs")
    title = "Catalog PR #" + str(pull["number"]) + " at " + head
    matching = [run for run in runs
                if run.get("workflow_id") == workflow["id"] and run.get("event") == "pull_request_target"
                and str(run.get("path", "")).split("@", 1)[0] == WORKFLOW_PATH
                and run.get("display_title") == title and run.get("head_sha") == pull["base"]["sha"]
                and run.get("repository", {}).get("full_name") == REPOSITORY]
    if not matching:
        return {}
    run = max(matching, key=lambda item: (item.get("run_started_at") or item.get("created_at", ""),
                                         item["id"], item["run_attempt"]))
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        return {}
    artifacts = github.api("actions/runs/" + str(run["id"]) + "/artifacts?per_page=100")
    for artifact in artifacts.get("artifacts", []):
        if (artifact.get("name") != "catalog-validation-" + head or artifact.get("expired")
                or not 0 < artifact.get("size_in_bytes", 0) <= 1024 * 1024):
            continue
        archive_bytes = github.api("actions/artifacts/" + str(artifact["id"]) + "/zip", raw=True)
        if len(archive_bytes) > 1024 * 1024:
            continue
        try:
            with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
                if archive.namelist() != ["catalog-validation.json"] or archive.infolist()[0].file_size > 65536:
                    continue
                proof = json.loads(archive.read("catalog-validation.json"))
        except (ValueError, zipfile.BadZipFile, RuntimeError):
            continue
        expected = {"repository": REPOSITORY, "pull_request_number": pull["number"],
                    "head_repository": REPOSITORY, "head_sha": head, "base_sha": pull["base"]["sha"],
                    "run_id": run["id"], "run_attempt": run["run_attempt"],
                    "checker_exit_code": 0, "input_sha256": digest(content), "conclusion": "success",
                    "event_name": "pull_request_target"}
        if (isinstance(proof, dict) and all(proof.get(key) == value for key, value in expected.items())
                and all(type(proof.get(key)) is int for key in ["pull_request_number", "run_id", "run_attempt", "checker_exit_code"])):
            return proof
    return {}


def strict_catalog_protection(github):
    unreadable = False
    try:
        rules = github.api("rules/branches/main")
        if any(rule.get("type") == "required_status_checks"
               and rule.get("parameters", {}).get("strict_required_status_checks_policy") is True
               and any(check.get("context") == "catalog-validation"
                       for check in rule.get("parameters", {}).get("required_status_checks", [])) for rule in rules):
            return ""
    except SubmissionError:
        unreadable = True
    try:
        protection = github.api("branches/main/protection/required_status_checks", missing=True)
        if protection is not None and protection.get("strict") is True:
            contexts = set(protection.get("contexts", []))
            contexts.update(check.get("context") for check in protection.get("checks", []))
            if "catalog-validation" in contexts:
                return ""
    except SubmissionError:
        unreadable = True
    return "strict_catalog_protection_unverified" if unreadable else "strict_catalog_protection_required"


def request_merge(github, pull, head, content):
    current = github.api("pulls/" + str(pull["number"]))
    if current["state"] != "open" or current["head"]["sha"] != head or current["base"]["sha"] != pull["base"]["sha"]:
        raise SubmissionError("pull_request_changed_revalidate")
    proof = verified_ci(github, pull, head, content)
    if not proof:
        return "ci_pending"
    protection_error = strict_catalog_protection(github)
    if protection_error:
        return protection_error
    checks = github.api("commits/" + head + "/check-runs?" + urlencode(
        {"check_name": "catalog-validation", "filter": "latest", "per_page": 100}))
    external_id = "catalog-validation:" + str(proof["run_id"]) + ":" + str(proof["run_attempt"]) + ":" + proof["base_sha"]
    details_url = "https://github.com/" + REPOSITORY + "/actions/runs/" + str(proof["run_id"])
    if not any(check.get("name") == "catalog-validation" and check.get("head_sha") == head
               and check.get("app", {}).get("slug") == "github-actions"
               and check.get("status") == "completed" and check.get("conclusion") == "success"
               and check.get("external_id") == external_id and check.get("details_url") == details_url
               for check in checks.get("check_runs", [])):
        return "published_head_check_pending"
    result = github.command(["pr", "merge", str(pull["number"]), "--repo", "https://github.com/" + REPOSITORY,
                             "--auto", "--squash", "--match-head-commit", head])
    if result.returncode:
        raise SubmissionError("auto_merge_request_failed")
    return "auto_merge_requested"


def run(args):
    report = json.loads(args.report.read_text(encoding="utf-8"))
    content = args.catalog.read_bytes()
    source = report.get("source", {})
    if source.get("repository") != REPOSITORY or report.get("errors") != []:
        raise SubmissionError("verified_source_required")
    if digest(content) != report.get("output_catalog_sha256"):
        raise SubmissionError("verified_output_mismatch")
    github = GitHub(args.gh)
    main = github.api("git/ref/heads/main")["object"]["sha"]
    if main != source.get("main_sha"):
        raise SubmissionError("main_changed_revalidate")
    original_content = github.catalog(main)
    if digest(original_content) != source.get("catalog_sha256"):
        raise SubmissionError("verified_source_mismatch")
    changes = report.get("changes")
    validate_changes(json.loads(original_content), json.loads(content), changes)
    pull = matching_pull_request(github, changes)
    branch = pull["head"]["ref"] if pull else SUBMISSION_BRANCH
    auto_merge_enabled = github.api("").get("allow_auto_merge") is True
    if not args.submit:
        return {"state": "dry_run", "repository": REPOSITORY, "main_sha": main,
                "branch": branch, "changes": len(changes), "auto_merge_enabled": auto_merge_enabled,
                "pull_request": pull["number"] if pull else None}
    if not auto_merge_enabled:
        raise SubmissionError("repository_auto_merge_not_enabled")
    if github.api("git/ref/heads/main")["object"]["sha"] != main:
        raise SubmissionError("main_changed_revalidate")
    reference = github.api("git/ref/heads/" + branch, missing=True)
    if reference is None:
        reference = github.api("git/refs", {"ref": "refs/heads/" + branch, "sha": main}, method="POST")
    head = reference["object"]["sha"]
    existing_content = github.catalog(head)
    if head != main:
        comparison = github.api("compare/" + main + "..." + head)
        if not {item["filename"] for item in comparison.get("files", [])} <= PATHS:
            raise SubmissionError("existing_branch_files_mismatch")
    if pull is None and head != main:
        history = github.pages("pulls?" + urlencode({"state": "closed", "head": REPOSITORY.split("/")[0] + ":" + branch}))
        closed = [item for item in history if item["head"]["sha"] == head]
        if closed and not closed[0].get("merged_at"):
            raise SubmissionError("previous_pull_request_closed")
        if not closed:
            if existing_content != content or any(github.catalog(head, path, missing=True) != content for path in PATHS):
                raise SubmissionError("submission_branch_busy")
    commit_data = github.api("git/commits/" + head)
    ready = (existing_content == content and any(parent["sha"] == main for parent in commit_data["parents"])
             and all(github.catalog(head, path, missing=True) == content for path in PATHS))
    if not ready:
        blob = github.api("git/blobs", {"content": base64.b64encode(content).decode(), "encoding": "base64"}, method="POST")
        base_tree = github.api("git/commits/" + main)["tree"]["sha"]
        tree = github.api("git/trees", {"base_tree": base_tree, "tree": [
            {"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]} for path in sorted(PATHS)]}, method="POST")
        parents = [head] if head == main else [head, main]
        commit = github.api("git/commits", {"message": "Update verified catalog releases", "tree": tree["sha"], "parents": parents}, method="POST")
        github.api("git/refs/heads/" + branch, {"sha": commit["sha"], "force": False}, method="PATCH")
    pull = matching_pull_request(github, changes)
    if github.api("git/ref/heads/main")["object"]["sha"] != main:
        raise SubmissionError("main_changed_revalidate")
    current_head = github.api("git/ref/heads/" + branch)["object"]["sha"]
    comparison = github.api("compare/" + main + "..." + current_head)
    names = {item["filename"] for item in comparison.get("files", [])}
    if not {"catalog.json"} <= names <= PATHS:
        raise SubmissionError("existing_branch_files_mismatch")
    if pull is None:
        summary = "\n".join("- " + change["id"] + " " + str(change["before"]["version"]) + " → " + str(change["after"]["version"]) for change in changes)
        body = ("Update existing catalog entries after checking the author release ZIP, digest, metadata and README.\n\n"
                "作者の公開ZIP、digest、定義書、READMEを検査した既存項目の更新です。\n\n" + summary)
        pull = github.api("pulls", {"title": "Update verified catalog releases", "body": body, "head": branch, "base": "main"}, method="POST")
    head = validate_pull_request(github, pull, branch, content)
    state = request_merge(github, pull, head, content)
    return {"state": state, "repository": REPOSITORY, "pull_request": pull["number"],
            "url": pull["html_url"], "head_sha": head}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--gh", default="gh")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--submit", action="store_true")
    mode.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        result = run(args)
    except (SubmissionError, OSError, ValueError, KeyError, TypeError, IndexError, AttributeError) as error:
        reason = str(error) if isinstance(error, SubmissionError) else "invalid_input_or_response"
        print(json.dumps({"state": "blocked", "reason": reason}))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
