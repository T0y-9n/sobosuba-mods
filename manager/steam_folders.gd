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

static func find_game(process: RefCounted = null) -> String:
	var steam := "C:/Program Files (x86)/Steam"
	var roots: Array[String] = []
	if OS.get_name() == "Windows":
		var output: Array = []
		var arguments := PackedStringArray(["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"])
		var exit_code: int = process.execute("reg.exe", arguments, output) if process != null else OS.execute("reg.exe", arguments, output, false, false)
		if process != null and process.cancelled():
			return ""
		if exit_code == 0 and not output.is_empty():
			var pattern := RegEx.new()
			pattern.compile("SteamPath\\s+REG_SZ\\s+([^\\r\\n]+)")
			var found := pattern.search(str(output[0]))
			if found != null:
				steam = found.get_string(1).strip_edges().replace("\\", "/")
		roots.append(steam)
	elif OS.get_name() == "Linux":
		var home := OS.get_environment("HOME")
		for relative in [".local/share/Steam", ".steam/steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam"]:
			var output: Array = []
			var arguments := PackedStringArray(["-e", home.path_join(relative)])
			var exit_code: int = process.execute("/usr/bin/realpath", arguments, output) if process != null else OS.execute("/usr/bin/realpath", arguments, output, false)
			if process != null and process.cancelled():
				return ""
			if exit_code == 0 and not output.is_empty():
				roots.append(str(output[0]).strip_edges())
	for root in roots:
		for library in library_paths(root):
			var game := library.path_join("steamapps/common/sobosuba")
			var executable := "sobosuba.x86_64" if OS.get_name() == "Linux" else "sobosuba.exe"
			if FileAccess.file_exists(game.path_join(executable)):
				return game
	return ""
