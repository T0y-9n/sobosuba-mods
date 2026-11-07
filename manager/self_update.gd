extends Node

const Platform = preload("platform.gd")
const Versions = preload("versions.gd")
const Catalog = preload("catalog.gd")
const RELEASES := "https://api.github.com/repos/T0y-9n/sobosuba-mods/releases?per_page=100&page="
const BASE := "https://github.com/T0y-9n/sobosuba-mods/releases/download/"
var pending: Dictionary = {}
var blocked_sha := ""
var last_error := ""

static func state_path() -> String:
	return "user://self-update/state-" + Platform.path_key(OS.get_executable_path()).sha256_text() + ".json"

func helper_path() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var scripts: Array[String] = ["self_update.ps1", "package.ps1", "transaction.ps1"]
	for name in scripts:
		context.update(FileAccess.get_file_as_bytes("res://" + name))
	var folder := ProjectSettings.globalize_path("user://update-helpers/" + context.finish().hex_encode())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return ""
	for name in scripts:
		var source := "res://" + name
		var destination := folder.path_join(name)
		if FileAccess.file_exists(destination):
			if FileAccess.get_sha256(destination) != FileAccess.get_sha256(source):
				return ""
			continue
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			return ""
		file.store_buffer(FileAccess.get_file_as_bytes(source))
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK:
			return ""
	return folder.path_join("self_update.ps1")

static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func uses_setup_updates() -> bool:
	if OS.get_name() != "Windows":
		return false
	var marker := OS.get_executable_path().get_base_dir().path_join(".sobosuba-manager-install")
	if not FileAccess.file_exists(marker):
		return false
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker))
	return record is Dictionary and record.get("application", "") == "Sobosuba Mod Manager" and record.get("scope", "") == "machine"

func select_release(releases: Array, current: String, setup: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var stable := not current.contains("-")
	for release in releases:
		if not release is Dictionary or release.get("draft", true):
			continue
		var tag := str(release.get("tag_name", ""))
		if not tag.begins_with("manager-v"):
			continue
		var version := tag.trim_prefix("manager-v")
		if stable and (release.get("prerelease", true) or version.contains("-")):
			continue
		if not Versions.newer(version, current) or (not best.is_empty() and not Versions.newer(version, best.version)):
			continue
		if not release.get("assets") is Array:
			continue
		var name := "Sobosuba-Mod-Manager-" + Platform.asset_platform() + "-v" + version + ".zip"
		if setup:
			name = "Sobosuba-Mod-Manager-Setup-Windows-v" + version + ".exe"
		for asset in release.assets:
			if not asset is Dictionary or asset.get("name", "") != name:
				continue
			var url := str(asset.get("browser_download_url", ""))
			var digest := str(asset.get("digest", ""))
			if url != BASE + tag + "/" + name or not digest.begins_with("sha256:") or not Catalog.valid_hash(digest.trim_prefix("sha256:")):
				continue
			if int(asset.get("size", 0)) <= 0 or int(asset.get("size", 0)) > 128 * 1024 * 1024:
				continue
			best = {"version":version, "zip":url, "sha256":digest.trim_prefix("sha256:").to_lower(), "installer":setup}
	return best

func save_state() -> bool:
	var path := ProjectSettings.globalize_path(state_path())
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"pending":pending, "blocked_sha":blocked_sha}))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(path + ".tmp", path) == OK

func load_state() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path())) if FileAccess.file_exists(state_path()) else null
	if data is Dictionary:
		pending = data.get("pending", {}) if data.get("pending") is Dictionary else {}
		blocked_sha = str(data.get("blocked_sha", ""))
	if pending.is_empty():
		return
	var job := str(pending.get("job", ""))
	var base := ProjectSettings.globalize_path("user://self-update/jobs").replace("\\", "/") + "/"
	if not job.replace("\\", "/").begins_with(base):
		pending = {}
		return
	var request_path := job.path_join("request.json")
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(request_path)) if FileAccess.file_exists(request_path) else null
	if not request is Dictionary or Platform.path_key(str(request.get("target", ""))) != Platform.path_key(OS.get_executable_path()):
		pending = {}
		save_state()
		return
	# An unfinished journal takes priority over a result and must remain recoverable.
	if FileAccess.file_exists(OS.get_executable_path() + ".sobo-update.json"):
		last_error = "manager_update_failed"
		return
	if not Versions.newer(str(pending.get("version", "")), current_version()):
		pending = {}
		save_state()
		return
	var result_path := job.path_join("result.json")
	if FileAccess.file_exists(result_path):
		var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		if result is Dictionary:
			if not result.get("ok", false):
				blocked_sha = str(pending.get("sha256", ""))
				last_error = "manager_update_failed"
			pending = {}
			save_state()

func helper(mode: String, job: String) -> Dictionary:
	var script := helper_path()
	if script.is_empty():
		return {"ok":false}
	var output: Array = []
	var shell := Platform.powershell()
	if shell.is_empty():
		return {"ok":false}
	var code := OS.execute(shell, Platform.shell_arguments(script, ["-Mode", mode, "-Job", job]), output, true, false)
	if code == 0 and not output.is_empty():
		var parsed: Variant = JSON.parse_string(str(output[0]).strip_edges())
		if parsed is Dictionary:
			return parsed
	return {"ok":false}

func run_helper(mode: String, job: String) -> Dictionary:
	var worker := Thread.new()
	if worker.start(helper.bind(mode, job)) != OK:
		return {"ok":false}
	while worker.is_alive():
		await get_tree().create_timer(0.03).timeout
	return worker.wait_to_finish()

func check_update(catalog: Node) -> bool:
	if OS.has_feature("editor") or OS.get_name() not in ["Windows", "Linux"]:
		return true
	if not pending.is_empty():
		return true
	var candidate: Dictionary = {}
	var setup := uses_setup_updates()
	for page in range(1, 101):
		var response: Dictionary = await catalog.request_bytes(RELEASES + str(page), 8 * 1024 * 1024)
		if response.error != OK:
			return false
		var releases: Variant = JSON.parse_string(response.body.get_string_from_utf8())
		if not releases is Array:
			return false
		var found := select_release(releases, current_version(), setup)
		if not found.is_empty() and (candidate.is_empty() or Versions.newer(found.version, candidate.version)):
			candidate = found
		if releases.size() < 100:
			break
		if page == 100:
			return false
	if candidate.is_empty() or candidate.sha256 == blocked_sha:
		return true
	var download: Dictionary = await catalog.download_verified(candidate, candidate.sha256, 128 * 1024 * 1024)
	if download.error != OK:
		return false
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	var job := ProjectSettings.globalize_path("user://self-update/jobs/" + nonce)
	var package_name := "package.exe" if setup else "package.zip"
	if DirAccess.make_dir_recursive_absolute(job) != OK or DirAccess.copy_absolute(download.zip, job.path_join(package_name)) != OK:
		return false
	var request := {"version":candidate.version, "sha256":candidate.sha256, "target":OS.get_executable_path(), "old_sha256":FileAccess.get_sha256(OS.get_executable_path()), "parent_pid":OS.get_process_id(), "restart":false, "installer":setup}
	var file := FileAccess.open(job.path_join("request.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(request))
	file.close()
	var prepared := await run_helper("prepare", job)
	if not prepared.get("ok", false):
		return false
	pending = {"job":job, "version":candidate.version, "sha256":candidate.sha256}
	if not save_state():
		pending = {}
		return false
	return true

func handoff(restart: bool = false) -> bool:
	if pending.is_empty() or OS.has_feature("editor"):
		return true
	if not save_state():
		return false
	var job := str(pending.job)
	var path := job.path_join("request.json")
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not request is Dictionary or Platform.path_key(str(request.target)) != Platform.path_key(OS.get_executable_path()):
		return false
	if request.old_sha256 != FileAccess.get_sha256(OS.get_executable_path()) and not FileAccess.file_exists(OS.get_executable_path() + ".sobo-update.json"):
		return false
	request.parent_pid = OS.get_process_id()
	request.restart = restart
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(request))
	file.close()
	var ready := job.path_join("ready.json")
	if FileAccess.file_exists(ready):
		DirAccess.remove_absolute(ready)
	var shell := Platform.powershell()
	var script := helper_path()
	if script.is_empty():
		return false
	if shell.is_empty():
		return false
	var arguments := Platform.shell_arguments(script, ["-Mode", "apply", "-Job", job], true)
	var pid := OS.create_process(shell, arguments, false)
	if pid <= 0:
		return false
	for attempt in 200:
		if FileAccess.file_exists(ready):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ready))
			if data is Dictionary and int(data.get("parent_pid", 0)) == OS.get_process_id() and int(data.get("helper_pid", 0)) == pid:
				return true
		if not OS.is_process_running(pid):
			return false
		await get_tree().create_timer(0.05).timeout
	if OS.is_process_running(pid):
		OS.kill(pid)
	return false
