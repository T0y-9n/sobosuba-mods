extends RefCounted
## UE4SS 3.0.1 uses mods.txt and per-mod enabled.txt markers.

const Readers = preload("../readers.gd")

static func read(place: Dictionary, _context: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	var directory := DirAccess.open(place.path)
	if directory == null:
		return {"items": items, "unreadable": ""}
	var enabled := {}
	var mods_file := str(place.path).path_join("mods.txt")
	if FileAccess.file_exists(mods_file):
		var pattern := RegEx.new()
		pattern.compile("^([^;:][^:]*)\\s*:\\s*1\\s*$")
		for line in FileAccess.get_file_as_string(mods_file).split("\n"):
			var entry := pattern.search(line.strip_edges())
			if entry != null:
				enabled[entry.get_string(1).strip_edges()] = true
	for name in directory.get_directories():
		var row := Readers.item(place.id, name)
		row.path = str(place.path).path_join(name)
		row.origin = "manual"
		row.enabled = enabled.has(name) or FileAccess.file_exists(str(row.path).path_join("enabled.txt"))
		items.append(row)
	return {"items": items, "unreadable": ""}
