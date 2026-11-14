extends RefCounted

var path := ""
var enabled := true


func load_file() -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).get("enabled") is bool:
		enabled = (parsed as Dictionary).enabled


func set_enabled(value: bool) -> void:
	enabled = value
	save_file()


func save_file() -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("undo settings were not saved: %s" % path)
		return
	f.store_string(JSON.stringify({"enabled": enabled}))
	f.close()
