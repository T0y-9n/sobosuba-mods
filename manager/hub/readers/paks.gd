extends RefCounted
## Files with the same base name describe one pak group.

const Readers = preload("../readers.gd")

static func read(place: Dictionary, _context: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	var directory := DirAccess.open(place.path)
	if directory == null:
		return {"items": items, "unreadable": ""}
	var groups := {}
	for name in directory.get_files():
		var extension := name.get_extension().to_lower()
		if extension not in ["pak", "ucas", "utoc"]:
			continue
		var key := name.get_basename()
		if not groups.has(key) or extension == "pak":
			groups[key] = str(place.path).path_join(name)
	for key in groups:
		var row := Readers.item(place.id, key)
		row.path = groups[key]
		row.origin = "manual"
		row.enabled = true
		items.append(row)
	return {"items": items, "unreadable": ""}
