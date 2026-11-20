extends RefCounted
## Plugin folders and enabled or renamed DLLs directly under plugins.

const Readers = preload("../readers.gd")

static func read(place: Dictionary, _context: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	var directory := DirAccess.open(place.path)
	if directory == null:
		return {"items": items, "unreadable": ""}
	for name in directory.get_directories():
		var row := Readers.item(place.id, name)
		row.path = str(place.path).path_join(name)
		row.origin = "manual"
		row.enabled = true
		var manifest := FileAccess.open(str(row.path).path_join("manifest.json"), FileAccess.READ)
		if manifest != null:
			var json := JSON.new()
			if json.parse(manifest.get_as_text()) == OK and json.data is Dictionary and json.data.get("version_number") is String:
				row.version = json.data.version_number
			manifest.close()
		items.append(row)
	for name in directory.get_files():
		var lower := name.to_lower()
		var disabled_suffix := lower.find(".dll.")
		if not lower.ends_with(".dll") and (disabled_suffix < 0 or disabled_suffix + 5 == lower.length()):
			continue
		var row := Readers.item(place.id, name)
		row.name = name.left(lower.find(".dll"))
		row.path = str(place.path).path_join(name)
		row.origin = "manual"
		row.enabled = lower.ends_with(".dll")
		items.append(row)
	return {"items": items, "unreadable": ""}
