extends SceneTree

const Catalog = preload("../../manager/catalog.gd")
const Main = preload("../../manager/main.gd")

class DownloadFixture extends Catalog:
	var response: Dictionary = {}
	func request_bytes(_url: String, _limit: int = 32 * 1024 * 1024) -> Dictionary:
		return response

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	print("MANAGER_DOWNLOAD_CHECK ", "OK " if condition else "FAIL ", message)
	if not condition:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var body := "download fixture".to_utf8_buffer()
	var http := Catalog.response_bytes([HTTPRequest.RESULT_SUCCESS, 504, PackedStringArray(), body])
	check(http.error == ERR_CANT_CONNECT and http.body.is_empty(), "HTTP failure preserves the existing error and empty body")
	check(http.failure == "http" and http.http_status == 504, "HTTP 504 retains its cause and status")
	var connection := Catalog.response_bytes([HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), body])
	check(connection.failure == "connection" and connection.request_result == HTTPRequest.RESULT_CANT_CONNECT, "connection failure retains its request result")
	var success := Catalog.response_bytes([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body])
	check(success.error == OK and success.body == body, "successful response preserves bytes")
	var catalog := DownloadFixture.new()
	var invalid: Dictionary = await catalog.download_verified({}, "invalid")
	check(invalid.error == ERR_INVALID_DATA and invalid.failure == "sha256_invalid", "invalid SHA is distinct from downloaded byte mismatch")
	catalog.response = http
	var unavailable: Dictionary = await catalog.download_verified({}, "0".repeat(64))
	check(unavailable.http_status == 504 and unavailable.failure == "http", "verified download preserves HTTP cause")
	catalog.response = success
	var mismatch: Dictionary = await catalog.download_verified({}, "0".repeat(64))
	check(mismatch.error == ERR_INVALID_DATA and mismatch.failure == "sha256", "mismatched downloaded bytes remain rejected")
	var screen := Main.new()
	screen.words.set_locale("ja")
	var cases := [
		[http, "HTTP 504"],
		[connection, "通信"],
		[{"error":ERR_INVALID_PARAMETER, "failure":"request"}, "開始"],
		[invalid, "形式"],
		[mismatch, "一致"],
		[{"error":ERR_CANT_CREATE, "failure":"storage"}, "保存"]
	]
	for item in cases:
		var error: Dictionary = screen.download_error(item[0], "prime_sobo", "1.3.11-1.0.4")
		var message: String = screen.words.error_word(error.error, error.args)
		check(not error.ok and error.error == "dependency_download", "download failure retains the existing display contract")
		check(message.contains(item[1]) and not message.contains("https://"), "Japanese message identifies the failure without a URL")
	var translations: Dictionary = screen.words.translations
	for locale in translations:
		for key in ["download_request", "download_connection", "download_http", "download_sha256_invalid", "download_sha256", "download_storage"]:
			check(translations[locale].has(key), "download cause exists for " + locale + " " + key)
	catalog.free()
	screen.catalog.free()
	screen.self_update.free()
	screen.free()
	print("MANAGER_DOWNLOAD_CHECKS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
