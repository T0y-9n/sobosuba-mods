extends RefCounted
## Steam owns the item list and update timestamps.

const Readers = preload("../readers.gd")
const SteamLibrary = preload("../steam_library.gd")
const Vdf = preload("../vdf.gd")

static func read(place: Dictionary, context: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	var record := str(context.library).path_join("steamapps/workshop/appworkshop_%d.acf" % context.appid)
	if not FileAccess.file_exists(record):
		return {"items": items, "unreadable": ""}
	if not Vdf.parse_file(record).get("AppWorkshop") is Dictionary:
		return {"items": items, "unreadable": record.get_file()}
	for entry in SteamLibrary.workshop_items(context.library, context.appid):
		var row := Readers.item(place.id, entry.id)
		row.origin = "workshop"
		row.origin_id = entry.id
		row.installed_at = entry.installed_at if entry.installed_at >= 0 else null
		row.latest_at = entry.latest_at if entry.latest_at >= 0 else null
		row.update = entry.update
		row.path = entry.path if DirAccess.dir_exists_absolute(entry.path) else ""
		items.append(row)
	return {"items": items, "unreadable": ""}
