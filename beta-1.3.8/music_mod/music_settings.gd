extends RefCounted

var path := ""
var song := ""
var playing := false
var beat := 1.0
var tone := 0.5

func load_file() -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if data.get("song") is String:
		song = data.song
	playing = data.get("playing") == true
	beat = clampf(float(data.get("beat", beat)), 0.0, 2.0)
	tone = clampf(float(data.get("tone", tone)), 0.0, 2.0)

func save_file() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("music sobo: settings were not saved")
		return
	file.store_string(JSON.stringify({"song": song, "playing": playing, "beat": beat, "tone": tone}))
	file.close()
