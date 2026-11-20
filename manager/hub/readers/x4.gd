extends RefCounted
## X4 extension metadata and per-user enabled overrides.

const Readers = preload("../readers.gd")

static func read(place: Dictionary, _context: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	var directory := DirAccess.open(place.path)
	if directory == null:
		return {"items": items, "unreadable": ""}
	var overrides := {}
	var conflicts := {}
	var users := DirAccess.open(str(place.get("user", "")))
	if users != null:
		for user in users.get_directories():
			var record := str(place.user).path_join(user).path_join("content.xml")
			if not FileAccess.file_exists(record):
				continue
			var parsed := _elements(record, "extension")
			if not parsed.ok:
				return {"items": [], "unreadable": "content.xml"}
			for entry in parsed.entries:
				if not entry.has("enabled"):
					continue
				var id := str(entry.get("id", ""))
				var value: Variant = _enabled(entry.get("enabled"))
				if overrides.has(id) and overrides[id] != value:
					conflicts[id] = true
				overrides[id] = value
	for name in directory.get_directories():
		var path := str(place.path).path_join(name)
		var record := path.path_join("content.xml")
		if not FileAccess.file_exists(record):
			continue
		var parsed := _elements(record, "content")
		if not parsed.ok or parsed.entries.is_empty():
			return {"items": [], "unreadable": "content.xml"}
		var entry: Dictionary = parsed.entries[0]
		var id := str(entry.get("id", ""))
		var row := Readers.item(place.id, id)
		row.name = str(entry.get("name", name))
		row.version = entry.get("version")
		row.path = path
		row.origin = "manual"
		if id.begins_with("ego_dlc"):
			row.origin = "official"
		elif id.begins_with("ws_"):
			row.origin = "workshop"
			var number := id.trim_prefix("ws_")
			if number.is_valid_int():
				row.origin_id = number
		row.enabled = overrides.get(id, _enabled(entry.get("enabled")))
		if conflicts.has(id):
			row.enabled = null
		items.append(row)
	return {"items": items, "unreadable": ""}

static func _enabled(value: Variant) -> Variant:
	if value in ["1", "true"]:
		return true
	if value in ["0", "false"]:
		return false
	return null

static func _elements(path: String, tag: String) -> Dictionary:
	var entries: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"entries": entries, "ok": false}
	var parser := XMLParser.new()
	var error := parser.open_buffer(file.get_buffer(file.get_length()))
	file.close()
	if error != OK:
		return {"entries": entries, "ok": false}
	error = parser.read()
	while error == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == tag:
			var attributes := {}
			for index in range(parser.get_attribute_count()):
				attributes[parser.get_attribute_name(index)] = parser.get_attribute_value(index)
			entries.append(attributes)
		error = parser.read()
	return {"entries": entries, "ok": error == ERR_FILE_EOF}
