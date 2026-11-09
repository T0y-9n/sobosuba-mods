extends Node

const DEFAULT_URL := "https://raw.githubusercontent.com/T0y-9n/sobosuba-mods/main/catalog.json"
const Manifest = preload("manifest.gd")
const Versions = preload("versions.gd")
const ReleaseSource = preload("release_source.gd")

var mods: Array = []
var error_message := ""
var _trusted_catalog := false
var _base_mods: Array = []
var _release_source := ReleaseSource.new()

func request_bytes(url: String, limit: int = 32 * 1024 * 1024) -> Dictionary:
	if not url.begins_with("https://"):
		return {"error": ERR_INVALID_PARAMETER, "body": PackedByteArray(), "failure":"request"}
	var request := HTTPRequest.new()
	request.timeout = 30.0
	request.body_size_limit = limit
	add_child(request)
	var error := request.request(url)
	if error != OK:
		request.queue_free()
		return {"error": error, "body": PackedByteArray(), "failure":"request"}
	var response: Array = await request.request_completed
	request.queue_free()
	return response_bytes(response)

static func response_bytes(response: Array) -> Dictionary:
	var result := {"error":OK, "body":response[3], "request_result":int(response[0]), "http_status":int(response[1])}
	if result.request_result != HTTPRequest.RESULT_SUCCESS or result.http_status != 200:
		result.error = ERR_CANT_CONNECT
		result.body = PackedByteArray()
		result.failure = "connection" if result.request_result != HTTPRequest.RESULT_SUCCESS else "http"
	return result

func refresh(source: String = DEFAULT_URL) -> int:
	mods = []
	var previous_trust := _trusted_catalog
	_trusted_catalog = false
	var bytes := PackedByteArray()
	if source.begins_with("https://"):
		var result: Dictionary = await request_bytes(source)
		if result.error != OK:
			error_message = "Cannot check for updates: " + source
			restore_minimum(source, previous_trust)
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
		restore_minimum(source, not _base_mods.is_empty())
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
		if mod.has("variants"):
			if not mod.variants is Array:
				return invalid_catalog(source)
			for variant in mod.variants:
				if not valid_variant(variant, mod.id):
					return invalid_catalog(source)
			var owners := {}
			var candidates := release_candidates(mod)
			for index in candidates.size():
				for game in candidates[index].get("game_versions", []):
					if owners.has(game) and owners[game] != index:
						return invalid_catalog(source)
					owners[game] = index
		ids.append(mod.id)
	mods = parsed.mods
	_trusted_catalog = source == DEFAULT_URL
	if _trusted_catalog:
		add_source_defaults(mods)
		_base_mods = mods.duplicate(true)
	error_message = ""
	return OK

func bundled_mods() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	return parsed.mods if parsed is Dictionary and parsed.get("mods") is Array else []

func add_source_defaults(entries: Array) -> void:
	var bundled := bundled_mods()
	for row: Dictionary in entries:
		var defaults: Array = []
		for original: Dictionary in bundled:
			if original.get("id") == row.id:
				defaults = release_candidates(original)
		var candidates: Array = [row]
		for variant: Dictionary in row.get("variants", []):
			candidates.append(variant)
		for candidate: Dictionary in candidates:
			if candidate.has("source"):
				continue
			for original: Dictionary in defaults:
				if original.has("source") and ReleaseSource.valid_source(original.source) and entry_layout(candidate) == entry_layout(original) and ReleaseSource.valid_location(candidate, original.source) and valid_hash(str(candidate.get("sha256", ""))):
					candidate.source = original.source.duplicate(true)
					break

func restore_minimum(source: String, previous_trust: bool) -> void:
	if source != DEFAULT_URL:
		return
	mods = _base_mods.duplicate(true) if previous_trust else bundled_mods().duplicate(true)
	_trusted_catalog = not mods.is_empty()
	if _trusted_catalog:
		add_source_defaults(mods)
		_base_mods = mods.duplicate(true)

func refresh_latest(game_version: String, inspect: Callable) -> Dictionary:
	var result := await _release_source.refresh(self, mods, game_version, inspect, _trusted_catalog)
	mods = result.mods
	return result

func release_status(mod_id: String, game_version: String) -> Dictionary:
	var family := entry_layout({"game_versions":[game_version]})
	return _release_source.statuses.get(mod_id + "|" + family, {})

func invalid_catalog(source: String) -> int:
	error_message = "Invalid catalog: " + source
	restore_minimum(source, not _base_mods.is_empty())
	return ERR_INVALID_DATA

static func valid_variant(value: Variant, mod_id: String) -> bool:
	if not value is Dictionary or value.has("variants"):
		return false
	if value.has("id") and value.id != mod_id:
		return false
	for field in ["version", "zip", "sha256"]:
		if not value.get(field) is String or value[field].strip_edges().is_empty():
			return false
	if not value.zip.begins_with("https://") or not valid_hash(value.sha256):
		return false
	for field in ["name", "summary"]:
		if value.has(field) and (not value[field] is String or value[field].is_empty()):
			return false
	return not entry_layout(value).is_empty()

static func entry_layout(entry: Dictionary) -> String:
	var declared: Variant = entry.get("game_versions", [])
	if not declared is Array or declared.is_empty():
		return ""
	var layout := ""
	for game in declared:
		if not game is String:
			return ""
		var family := "game-autoload"
		if game != "1.2.3":
			var parsed := Versions.parse(game)
			if parsed.is_empty() or parsed.core[0] != 1 or parsed.core[1] != 3 or game != "1.3." + str(parsed.core[2]):
				return ""
			family = "user-data-styles"
		if not layout.is_empty() and layout != family:
			return ""
		layout = family
	return layout

static func release_candidates(mod: Dictionary) -> Array:
	var original := mod.duplicate(true)
	original.erase("variants")
	var candidates: Array = [original]
	for variant in mod.get("variants", []):
		var candidate := original.duplicate(true)
		candidate.erase("source")
		candidate.merge(variant, true)
		candidate.id = mod.id
		candidates.append(candidate)
	return candidates

static func matching_releases(mod: Dictionary, game_version: String, mod_version: String) -> Array:
	var exact: Array = []
	var compatible: Array = []
	for candidate in release_candidates(mod):
		if not mod_version.is_empty() and candidate.version != mod_version:
			continue
		if game_version.is_empty():
			exact.append(candidate)
			continue
		# Original undeclared dependency rows are checked by package inspection.
		if not mod_version.is_empty() and not candidate.has("game_versions") and mod.get("variants", []).is_empty():
			exact.append(candidate)
			continue
		if entry_layout(candidate).is_empty():
			continue
		var declared: Array = candidate.get("game_versions", [])
		if declared.has(game_version):
			exact.append(candidate)
		elif Versions.supports_game(declared, game_version):
			compatible.append(candidate)
	return exact if not exact.is_empty() else compatible

func for_game(game_version: String) -> Array:
	var selected: Array = []
	for mod in mods:
		var candidates := matching_releases(mod, game_version, "")
		if candidates.size() == 1:
			selected.append(candidates[0])
		elif candidates.is_empty():
			# Keep the earlier row for the existing optional locked-version display.
			selected.append(release_candidates(mod)[0])
	return selected

func find(mod_id: String, game_version: String = "", mod_version: String = "") -> Dictionary:
	for mod in mods:
		if mod.id == mod_id:
			if game_version.is_empty() and mod_version.is_empty():
				return mod
			var candidates := matching_releases(mod, game_version, mod_version)
			return candidates[0] if candidates.size() == 1 else {}
	return {}

func has_update(installed: Dictionary, game_version: String = "") -> bool:
	var latest := find(installed.id, game_version)
	if latest.is_empty() or not Versions.newer(latest.version, installed.version):
		return false
	var layout := str(installed.get("layout", entry_layout(installed)))
	if layout.is_empty():
		# Older callers supplied only an ID and mod version, using the original row.
		return game_version.is_empty() and not installed.has("layout") and not installed.has("game_versions")
	return layout == entry_layout(latest)

static func valid_hash(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-fA-F0-9]{64}$")
	return pattern.search(value) != null

func download_verified(entry: Dictionary, sha256: String, limit: int = 32 * 1024 * 1024) -> Dictionary:
	if not valid_hash(sha256):
		return {"error":ERR_INVALID_DATA, "failure":"sha256_invalid"}
	var result: Dictionary = await request_bytes(str(entry.get("zip", "")), limit)
	if result.error != OK:
		return result
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(result.body)
	if context.finish().hex_encode() != sha256.to_lower():
		return {"error":ERR_INVALID_DATA, "failure":"sha256"}
	var folder := ProjectSettings.globalize_path("user://packages")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"error":ERR_CANT_CREATE, "failure":"storage"}
	var path := folder.path_join(sha256.to_lower() + ".zip")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error":ERR_CANT_CREATE, "failure":"storage"}
	file.store_buffer(result.body)
	file.flush()
	var error := file.get_error()
	file.close()
	return {"error":error, "zip":path, "failure":"storage" if error != OK else ""}
