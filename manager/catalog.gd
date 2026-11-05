extends Node

const DEFAULT_URL := "https://raw.githubusercontent.com/T0y-9n/sobosuba-mods/main/catalog.json"
const Manifest = preload("manifest.gd")

var mods: Array = []
var error_message := ""

func request_bytes(url: String) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": ERR_INVALID_PARAMETER, "body": PackedByteArray()}
	var request := HTTPRequest.new()
	request.timeout = 30.0
	request.body_size_limit = 64 * 1024 * 1024
	add_child(request)
	var error := request.request(url)
	if error != OK:
		request.queue_free()
		return {"error": error, "body": PackedByteArray()}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return {"error": ERR_CANT_CONNECT, "body": PackedByteArray()}
	return {"error": OK, "body": response[3]}

func refresh(source: String = DEFAULT_URL) -> int:
	mods = []
	var bytes := PackedByteArray()
	if source.begins_with("https://"):
		var result: Dictionary = await request_bytes(source)
		if result.error != OK:
			error_message = "Cannot check for updates: " + source
			return result.error
		bytes = result.body
	else:
		if not FileAccess.file_exists(source):
			error_message = "Cannot read catalog: " + source
			return ERR_FILE_NOT_FOUND
		bytes = FileAccess.get_file_as_bytes(source)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("mods") is Array:
		error_message = "Invalid catalog: " + source
		return ERR_INVALID_DATA
	var ids: Array = []
	for mod in parsed.mods:
		if not mod is Dictionary:
			return invalid_catalog(source)
		for field in ["id", "name", "version", "zip", "summary"]:
			if not mod.get(field) is String or mod[field].is_empty():
				return invalid_catalog(source)
		if not Manifest.valid_id(mod.id) or mod.id in ids or not mod.zip.begins_with("https://"):
			return invalid_catalog(source)
		ids.append(mod.id)
	mods = parsed.mods
	error_message = ""
	return OK

func invalid_catalog(source: String) -> int:
	error_message = "Invalid catalog: " + source
	return ERR_INVALID_DATA

func find(mod_id: String) -> Dictionary:
	for mod in mods:
		if mod.id == mod_id:
			return mod
	return {}

func has_update(installed: Dictionary) -> bool:
	var latest := find(installed.id)
	return not latest.is_empty() and installed.version != latest.version
