extends RefCounted
## Stores the selected game separately from the existing manager settings.

const PATH := "user://hub.json"

static func load_selected() -> String:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return "sobosuba"
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return "sobosuba"
	var saved: Dictionary = json.data
	if saved.get("format_version") != 1 or not saved.get("selected") is String:
		return "sobosuba"
	return saved.selected

static func save_selected(id: String) -> void:
	var temporary := PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"format_version": 1, "selected": id}, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		DirAccess.rename_absolute(temporary, PATH)
