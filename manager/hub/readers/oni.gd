extends RefCounted
## ONI's mod list provides distribution and DLC-enabled state.

const Readers = preload("../readers.gd")
const SteamLibrary = preload("../steam_library.gd")
const ORIGINS = {0: "local", 1: "workshop", 4: "dev"}
const FOLDERS = {0: "Local", 1: "Steam", 4: "Dev"}

static func read(place: Dictionary, context: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	var record := str(place.path).path_join("mods.json")
	if not DirAccess.dir_exists_absolute(place.path) or not FileAccess.file_exists(record):
		return {"items": items, "unreadable": ""}
	var file := FileAccess.open(record, FileAccess.READ)
	if file == null:
		return {"items": items, "unreadable": "mods.json"}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary or not json.data.get("mods") is Array:
		return {"items": items, "unreadable": "mods.json"}
	var workshop := {}
	for entry in SteamLibrary.workshop_items(context.library, context.appid):
		workshop[entry.id] = entry
	for mod in json.data.mods:
		if not mod is Dictionary or not mod.get("label") is Dictionary:
			continue
		var label: Dictionary = mod.label
		var platform := int(label.get("distribution_platform", -1))
		var origin: Variant = ORIGINS.get(platform)
		var id := str(label.get("id", ""))
		var row := Readers.item(place.id, "%s/%s" % [origin if origin != null else "unknown", id])
		row.name = str(label.get("title", row.key))
		row.origin = origin
		var version: Variant = label.get("version")
		if version != null and str(version) != "":
			row.version = str(version)
		var dlc: Variant = mod.get("enabledForDlc")
		if dlc is Array:
			row.enabled = not dlc.is_empty()
		if origin == "workshop":
			row.origin_id = id
			if workshop.has(id):
				var entry: Dictionary = workshop[id]
				row.installed_at = entry.installed_at if entry.installed_at >= 0 else null
				row.latest_at = entry.latest_at if entry.latest_at >= 0 else null
				row.update = entry.update
		if FOLDERS.has(platform):
			var path := str(place.path).path_join(FOLDERS[platform]).path_join(id)
			if DirAccess.dir_exists_absolute(path):
				row.path = path
		items.append(row)
	return {"items": items, "unreadable": ""}
