extends RefCounted

const DEFAULT_CATALOG := "https://raw.githubusercontent.com/T0y-9n/sobosuba-mods/main/catalog.json"

var path := "user://manager.json"
var game_folder := ""
var mod_folder := ""
var game_version := "1.3.11"
var locale := ""
var user_data := ""
var catalog_url := DEFAULT_CATALOG
var mod_auto_updates: Dictionary = {}
var manager_auto_update := true

func mod_updates_enabled(key: String) -> bool:
	return mod_auto_updates.get(key, false) == true

func load_file() -> void:
	if not FileAccess.file_exists(path) and path == "user://manager.json":
		var old_folder := "Godot" if OS.get_name() == "Windows" else "godot"
		var previous := OS.get_data_dir().path_join(old_folder + "/app_userdata/Sobo Mod Manager/manager.json")
		if FileAccess.file_exists(previous):
			if DirAccess.copy_absolute(previous, path + ".import") == OK:
				DirAccess.rename_absolute(path + ".import", path)
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		if parsed.get("mod_auto_updates") is Dictionary:
			for key in parsed.mod_auto_updates:
				if parsed.mod_auto_updates[key] is bool:
					mod_auto_updates[key] = parsed.mod_auto_updates[key]
		if parsed.get("manager_auto_update") is bool:
			manager_auto_update = parsed.manager_auto_update
		if parsed.get("mod_folder") is String:
			mod_folder = parsed.mod_folder
		if parsed.get("game_folder") is String:
			game_folder = parsed.game_folder
		if parsed.get("game_version") is String and parsed.game_version in ["1.2.3", "1.3.10", "1.3.11"]:
			game_version = parsed.game_version
		if parsed.get("locale") is String:
			locale = parsed.locale
		if parsed.get("user_data") is String:
			user_data = parsed.user_data
		if parsed.get("catalog_url") is String and not parsed.catalog_url.is_empty():
			catalog_url = parsed.catalog_url

func save() -> int:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"mod_auto_updates":mod_auto_updates, "manager_auto_update":manager_auto_update, "mod_folder":mod_folder, "game_folder": game_folder, "catalog_url": catalog_url, "game_version": game_version, "locale": locale, "user_data": user_data}, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary, path)
