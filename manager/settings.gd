extends RefCounted

const DEFAULT_CATALOG := "https://raw.githubusercontent.com/T0y-9n/sobosuba-mods/main/catalog.json"

var path := "user://manager.json"
var game_folder := ""
var game_version := "1.3.10"
var locale := ""
var user_data := ""
var catalog_url := DEFAULT_CATALOG

func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		if parsed.get("game_folder") is String:
			game_folder = parsed.game_folder
		if parsed.get("game_version") is String and parsed.game_version in ["1.2.3", "1.3.10"]:
			game_version = parsed.game_version
		if parsed.get("locale") is String:
			locale = parsed.locale
		if parsed.get("user_data") is String:
			user_data = parsed.user_data
		if parsed.get("catalog_url") is String and not parsed.catalog_url.is_empty():
			catalog_url = parsed.catalog_url

func save() -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"game_folder": game_folder, "catalog_url": catalog_url, "game_version": game_version, "locale": locale, "user_data": user_data}, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	return error
