extends RefCounted

const Platform = preload("platform.gd")
const BootTrace = preload("hub/boot_trace.gd")

var game_folder := ""
var game_version := "1.3.11"
var user_data := ""
var last_result: Dictionary = {}
var backend_dir := ""
var boot_process: RefCounted

func prepare_backend() -> bool:
	if boot_process != null and boot_process.cancelled():
		return false
	var source := "res://"
	backend_dir = ProjectSettings.globalize_path("user://backend")
	if DirAccess.make_dir_recursive_absolute(backend_dir) != OK:
		return false
	for name in ["backend.ps1", "package.ps1", "transaction.ps1", "dependencies.ps1", "self_update.ps1", "catalog.json"]:
		if boot_process != null and boot_process.cancelled():
			return false
		var trace := BootTrace.begin("worker_sobosuba", "prepare_backend/" + name)
		var bytes := FileAccess.get_file_as_bytes(source.path_join(name))
		if bytes.is_empty():
			return false
		var file := FileAccess.open(backend_dir.path_join(name), FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(bytes)
		file.close()
		BootTrace.end("worker_sobosuba", "prepare_backend/" + name, trace)
	return true

# Pass OS.execute arguments as an array without shell interpolation.
# The UI worker calls this function one operation at a time.
func request(action: String, extra: Dictionary = {}) -> Dictionary:
	var trace := BootTrace.begin("worker_sobosuba", action + "/request")
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
	var arguments := Platform.shell_arguments(backend_dir.path_join("backend.ps1"), ["-RequestPath", request_path])
	var code: int
	var process_trace := BootTrace.begin("worker_sobosuba", action + "/powershell")
	if boot_process != null and action in ["detect", "list"]:
		code = boot_process.execute(powershell, Platform.shell_arguments(backend_dir.path_join("backend.ps1"), ["-RequestPath", request_path], true), output)
	else:
		code = OS.execute(powershell, arguments, output, true, false)
	BootTrace.end("worker_sobosuba", action + "/powershell", process_trace)
	DirAccess.remove_absolute(request_path)
	BootTrace.end("worker_sobosuba", action + "/request", trace)
	if code == 0 and not output.is_empty():
		var parsed: Variant = JSON.parse_string(str(output[0]).strip_edges())
		if parsed is Dictionary and parsed.get("ok") is bool:
			last_result = parsed
			return parsed
	return {"ok": false, "error": "io_error", "args": []}
