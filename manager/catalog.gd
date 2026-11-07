extends Node

const DEFAULT_URL := "https://raw.githubusercontent.com/T0y-9n/sobosuba-mods/main/catalog.json"
const Manifest = preload("manifest.gd")
const Versions = preload("versions.gd")

var mods: Array = []
var error_message := ""

func request_bytes(url: String, limit: int = 32 * 1024 * 1024) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": ERR_INVALID_PARAMETER, "body": PackedByteArray()}
	var request := HTTPRequest.new()
	request.timeout = 30.0
	request.body_size_limit = limit
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
		if mod.has("sha256") and (not mod.sha256 is String or not valid_hash(mod.sha256)):
			return invalid_catalog(source)
		if mod.has("game_versions") and (not mod.game_versions is Array or mod.game_versions.any(func(value): return not value is String)):
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
	return not latest.is_empty() and Versions.newer(latest.version, installed.version)

static func valid_hash(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-fA-F0-9]{64}$")
	return pattern.search(value) != null

func download_verified(entry: Dictionary, sha256: String, limit: int = 32 * 1024 * 1024) -> Dictionary:
	if not valid_hash(sha256):
		return {"error":ERR_INVALID_DATA}
	var result: Dictionary = await request_bytes(str(entry.get("zip", "")), limit)
	if result.error != OK:
		return result
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(result.body)
	if context.finish().hex_encode() != sha256.to_lower():
		return {"error":ERR_INVALID_DATA}
	var folder := ProjectSettings.globalize_path("user://packages")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"error":ERR_CANT_CREATE}
	var path := folder.path_join(sha256.to_lower() + ".zip")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error":ERR_CANT_CREATE}
	file.store_buffer(result.body)
	file.flush()
	var error := file.get_error()
	file.close()
	return {"error":error, "zip":path}
