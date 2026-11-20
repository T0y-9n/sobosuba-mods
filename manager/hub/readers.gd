extends RefCounted
## Read-only dispatch for the mod locations described by each game.

const SCRIPTS = {
	"workshop": "res://hub/readers/workshop.gd",
	"bepinex": "res://hub/readers/bepinex.gd",
	"ue4ss": "res://hub/readers/ue4ss.gd",
	"paks": "res://hub/readers/paks.gd",
	"oni": "res://hub/readers/oni.gd",
	"x4": "res://hub/readers/x4.gd",
}

static func read(place: Dictionary, context: Dictionary) -> Dictionary:
	var reader := str(place.get("reader", ""))
	if not SCRIPTS.has(reader):
		return {"items": [], "unreadable": reader}
	return load(SCRIPTS[reader]).read(place, context)

static func item(place_id: String, key: String) -> Dictionary:
	return {
		"place": place_id, "key": key, "name": key,
		"version": null, "origin": null, "origin_id": "",
		"enabled": null, "installed_at": null, "latest_at": null,
		"update": null, "path": "",
	}
