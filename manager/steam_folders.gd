extends RefCounted

static func library_paths(steam: String) -> Array[String]:
	var libraries: Array[String] = [steam.replace("\\", "/")]
	var path := steam.path_join("steamapps/libraryfolders.vdf")
	if not FileAccess.file_exists(path):
		return libraries
	var pattern := RegEx.new()
	pattern.compile('"(?:path|[0-9]+)"\\s+"([^"\\r\\n]+)"')
	for match_value in pattern.search_all(FileAccess.get_file_as_string(path)):
		var library: String = match_value.get_string(1).replace("\\\\", "\\").replace("\\", "/")
		if library.is_absolute_path() and library not in libraries:
			libraries.append(library)
	return libraries

static func find_game() -> String:
	var steam := "C:/Program Files (x86)/Steam"
	if OS.get_name() == "Windows":
		var output: Array = []
		var exit_code := OS.execute("reg.exe", ["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"], output, false, false)
		if exit_code == 0 and not output.is_empty():
			var pattern := RegEx.new()
			pattern.compile("SteamPath\\s+REG_SZ\\s+([^\\r\\n]+)")
			var found := pattern.search(str(output[0]))
			if found != null:
				steam = found.get_string(1).strip_edges().replace("\\", "/")
	for library in library_paths(steam):
		var game := library.path_join("steamapps/common/sobosuba")
		if FileAccess.file_exists(game.path_join("sobosuba.exe")):
			return game
	return ""
