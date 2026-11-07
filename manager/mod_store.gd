extends RefCounted

const Platform = preload("platform.gd")

var game_folder := ""
var game_version := "1.3.11"
var user_data := ""
var last_result: Dictionary = {}
var backend_dir := ""

func prepare_backend() -> bool:
	var source := "res://"
	backend_dir = ProjectSettings.globalize_path("user://backend")
	if DirAccess.make_dir_recursive_absolute(backend_dir) != OK:
		return false
	for name in ["backend.ps1", "package.ps1", "transaction.ps1", "dependencies.ps1", "self_update.ps1"]:
		var bytes := FileAccess.get_file_as_bytes(source.path_join(name))
		if bytes.is_empty():
			return false
		var file := FileAccess.open(backend_dir.path_join(name), FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(bytes)
		file.close()
	return true

# Pass OS.execute arguments as an array without shell interpolation.
# The UI worker calls this function one operation at a time.
func request(action: String, extra: Dictionary = {}) -> Dictionary:
	if backend_dir.is_empty() and not prepare_backend():
		return {"ok": false, "error": "io_error", "args": []}
	var data := {"action": action, "game_folder": game_folder, "game_version": game_version}
	if not user_data.is_empty():
		data.user_data = user_data
	data.merge(extra, true)
	var request_path := ProjectSettings.globalize_path("user://request-" + str(Time.get_ticks_usec()) + ".json")
	var file := FileAccess.open(request_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "io_error", "args": []}
	file.store_string(JSON.stringify(data))
	file.close()
	var output: Array = []
	var powershell := Platform.powershell()
	if powershell.is_empty():
		DirAccess.remove_absolute(request_path)
		return {"ok":false, "error":"io_error", "args":[]}
	var code := OS.execute(powershell, Platform.shell_arguments(backend_dir.path_join("backend.ps1"), ["-RequestPath", request_path]), output, true, false)
	DirAccess.remove_absolute(request_path)
	if code == 0 and not output.is_empty():
		var parsed: Variant = JSON.parse_string(str(output[0]).strip_edges())
		if parsed is Dictionary and parsed.get("ok") is bool:
			last_result = parsed
			return parsed
	return {"ok": false, "error": "io_error", "args": []}
