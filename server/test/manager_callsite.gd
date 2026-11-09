extends SceneTree

# Run against an isolated copy of the manager project. Main's entry points stay real.
const MOD_ID := "prime_sobo"
const MOD_VERSION := "1.3.11-1.0.4"
const PIN := "0000000000000000000000000000000000000000000000000000000000000000"
const OTHER_PIN := "1111111111111111111111111111111111111111111111111111111111111111"

class CatalogFixture extends "res://catalog.gd":
	var downloaded_result: Dictionary = {}
	var bytes_result: Dictionary = {}
	var dependency: Dictionary = {}
	var verified_calls: Array[Dictionary] = []
	var bytes_calls: Array[String] = []
	var refresh_calls := 0

	func download_verified(entry: Dictionary, sha256: String, _limit: int = 32 * 1024 * 1024) -> Dictionary:
		verified_calls.append({"entry":entry.duplicate(true), "sha256":sha256})
		return downloaded_result.duplicate(true)

	func request_bytes(url: String, _limit: int = 32 * 1024 * 1024) -> Dictionary:
		bytes_calls.append(url)
		return bytes_result.duplicate(true)

	func find(_mod_id: String, _game_version: String = "", _mod_version: String = "") -> Dictionary:
		return dependency.duplicate(true)

	func refresh(_source: String = DEFAULT_URL) -> int:
		refresh_calls += 1
		return ERR_CANT_CONNECT

class MainFixture extends "res://main.gd":
	var calls: Array[String] = []
	var busy_states: Array[bool] = []
	var inspected: Array[String] = []
	var rendered_notices: Array[String] = []
	var dependency_pin := ""

	func invoke(operation: String, _extra: Dictionary = {}) -> Dictionary:
		calls.append(operation)
		if operation == "resolve":
			return {"ok":false, "error":"dependency_missing", "args":["prime_sobo", "1.3.11-1.0.4", dependency_pin]}
		if operation == "find_dependency":
			return {"ok":true, "data":{"zip":""}}
		return {"ok":false, "error":"invalid_request", "args":[]}

	func set_busy(value: bool) -> void:
		busy = value
		busy_states.append(value)

	func render_notice() -> void:
		rendered_notices.append(words.error_word(notice_error, notice_args))

	func inspect_zip(path: String) -> void:
		inspected.append(path)

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	print("MANAGER_CALLSITE_CHECK ", "OK " if condition else "FAIL ", message)
	if not condition:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func entry(verified: bool = true) -> Dictionary:
	var mod := {"id":MOD_ID, "version":MOD_VERSION, "zip":"https://example.invalid/private-download", "layout":"user-data-styles"}
	if verified:
		mod.sha256 = PIN
	return mod

func make_screen(result: Dictionary) -> MainFixture:
	var screen := MainFixture.new()
	screen.catalog.free()
	var download := CatalogFixture.new()
	download.downloaded_result = result
	download.bytes_result = result
	download.dependency = entry()
	screen.catalog = download
	screen.words.set_locale("ja")
	screen.dependency_pin = PIN
	return screen

func dispose(screen: MainFixture) -> void:
	screen.catalog.free()
	screen.self_update.free()
	screen.free()

func check_error(screen: MainFixture, result: Dictionary, fragment: String, label: String) -> void:
	check(not result.get("ok", true) and result.get("error") == "dependency_download", label + " retains the error contract")
	var args: Array = result.get("args", [])
	check(args.size() == 3 and args[0] == MOD_ID and args[1] == MOD_VERSION, label + " preserves mod identity and adds one cause")
	var message: String = screen.words.error_word(str(result.get("error", "")), args)
	check(message.contains(fragment) and not message.contains("https://") and not message.contains("private-download"), label + " shows the cause without the URL")

func manual_case(result: Dictionary, verified: bool, fragment: String) -> void:
	var screen := make_screen(result)
	var download := screen.catalog as CatalogFixture
	await screen.download_mod(entry(verified))
	var label := "manual verified=" + str(verified) + " " + fragment
	check_error(screen, {"ok":false, "error":screen.notice_error, "args":screen.notice_args}, fragment, label)
	check(screen.busy_states == [true, false] and not screen.busy, label + " releases busy state")
	check(screen.rendered_notices.size() == 1 and screen.inspected.is_empty() and screen.calls.is_empty(), label + " renders once and stops before inspection or install")
	check(download.verified_calls.size() == (1 if verified else 0) and download.bytes_calls.size() == (0 if verified else 1), label + " uses the intended download branch")
	if verified and download.verified_calls.size() == 1:
		check(download.verified_calls[0].sha256 == PIN and download.verified_calls[0].entry == entry(), label + " keeps the catalog entry and SHA pin")
	if not verified and download.bytes_calls.size() == 1:
		check(download.bytes_calls[0] == entry(false).zip, label + " keeps the original download URL")
	dispose(screen)

func update_case(result: Dictionary, fragment: String) -> void:
	var screen := make_screen(result)
	var download := screen.catalog as CatalogFixture
	var installed := entry()
	installed.version = "1.3.11-1.0.3"
	var error: Dictionary = await screen.auto_update_mod(installed, entry())
	check_error(screen, error, fragment, "automatic update " + fragment)
	check(download.verified_calls.size() == 1 and screen.calls.is_empty() and screen.inspected.is_empty(), "automatic update stops before inspect, resolve and install")
	if download.verified_calls.size() == 1:
		check(download.verified_calls[0].sha256 == PIN and download.verified_calls[0].entry == entry(), "automatic update keeps the catalog entry and SHA pin")
	dispose(screen)

func dependency_case(result: Dictionary, fragment: String, metadata_conflict: bool = false) -> void:
	var screen := make_screen(result)
	var download := screen.catalog as CatalogFixture
	if metadata_conflict:
		download.dependency.sha256 = OTHER_PIN
	var error: Dictionary = await screen.prepare_plan({"zip":"fixture.zip", "sha256":PIN})
	check_error(screen, error, fragment, "dependency " + fragment)
	check(screen.calls == ["resolve", "find_dependency"] and download.refresh_calls == 0, "dependency follows the missing-local-package path and stops")
	check(download.verified_calls.size() == (0 if metadata_conflict else 1), "dependency metadata conflict stops before downloading")
	if not metadata_conflict and download.verified_calls.size() == 1:
		check(download.verified_calls[0].sha256 == PIN and download.verified_calls[0].entry == entry(), "dependency keeps the catalog entry and exact SHA pin")
	if metadata_conflict:
		check(screen.words.translations.ja.has("download_sha256_metadata"), "metadata conflict has its own translation")
		var args: Array = error.get("args", [])
		check(args.size() == 3 and args[2] == screen.words.word("download_sha256_metadata") and args[2] != screen.words.word("download_sha256"), "metadata conflict is distinct from downloaded byte mismatch")
	dispose(screen)

func unverified_storage_case() -> void:
	var destination := ProjectSettings.globalize_path("user://catalog-mod.zip")
	if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		check(false, "isolated storage fixture path starts empty")
		return
	var created := DirAccess.make_dir_recursive_absolute(destination)
	check(created == OK, "a directory blocks the unverified ZIP destination")
	if created != OK:
		return
	await manual_case({"error":OK, "body":"fixture".to_utf8_buffer()}, false, "保存")
	check(DirAccess.dir_exists_absolute(destination), "failed storage preserves the blocking fixture")
	check(DirAccess.remove_absolute(destination) == OK, "remove only the directory created by this storage case")

func run() -> void:
	var scenarios := [
		[{"error":ERR_CANT_CONNECT, "body":PackedByteArray(), "request_result":HTTPRequest.RESULT_SUCCESS, "http_status":504, "failure":"http"}, "HTTP 504"],
		[{"error":ERR_CANT_CONNECT, "body":PackedByteArray(), "request_result":HTTPRequest.RESULT_CANT_CONNECT, "http_status":0, "failure":"connection"}, "通信"],
		[{"error":ERR_INVALID_DATA, "failure":"sha256"}, "一致"],
		[{"error":ERR_CANT_CREATE, "failure":"storage"}, "保存"]
	]
	for scenario in scenarios:
		await manual_case(scenario[0], true, scenario[1])
		await update_case(scenario[0], scenario[1])
		await dependency_case(scenario[0], scenario[1])
	for index: int in [0, 1]:
		await manual_case(scenarios[index][0], false, scenarios[index][1])
	await unverified_storage_case()
	await dependency_case({}, "SHA256", true)
	print("MANAGER_CALLSITE_CHECKS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
