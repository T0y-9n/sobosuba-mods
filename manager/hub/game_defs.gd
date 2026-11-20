extends RefCounted
## Game definitions and their installed Steam locations.

const SteamLibrary = preload("steam_library.gd")

static func load_all(folder: String = "res://games") -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	var directory := DirAccess.open(folder)
	if directory == null:
		return definitions
	for filename in directory.get_files():
		if filename.get_extension().to_lower() != "json":
			continue
		var file := FileAccess.open(folder.path_join(filename), FileAccess.READ)
		if file == null:
			continue
		var json := JSON.new()
		var error := json.parse(file.get_as_text())
		file.close()
		if error != OK or not json.data is Dictionary:
			continue
		var definition: Dictionary = json.data
		if definition.get("format_version") != 1:
			continue
		definitions.append(definition)
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.get("id") == "sobosuba") != (b.get("id") == "sobosuba"):
			return a.get("id") == "sobosuba"
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return definitions

static func installed(defs: Array[Dictionary], libraries: Array[String]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for definition in defs:
		var app := SteamLibrary.app(libraries, int(definition.get("steam_appid", 0)))
		if app.is_empty() or not DirAccess.dir_exists_absolute(app.folder):
			continue
		var entry := definition.duplicate(true)
		entry["app"] = app
		found.append(entry)
	return found

static func context(definition: Dictionary) -> Dictionary:
	var app: Dictionary = definition.get("app", {})
	return {
		"appid": int(definition.get("steam_appid", 0)),
		"game": str(app.get("folder", "")),
		"library": str(app.get("library", "")),
		"documents": OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
	}

static func resolve(template: String, values: Dictionary) -> String:
	return template.replace("{game}", str(values.get("game", ""))).replace("{documents}", str(values.get("documents", "")))
