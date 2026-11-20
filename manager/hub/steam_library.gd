extends RefCounted
## Read-only view of the Steam libraries on this machine: where a game is installed and which Workshop items it holds.

const SteamFolders = preload("../steam_folders.gd")
const Vdf = preload("vdf.gd")

## Steam's own folders. Only boot readers pass a cancellable process.
static func roots(process: RefCounted = null) -> Array[String]:
	var found: Array[String] = []
	if OS.get_name() == "Windows":
		var steam := "C:/Program Files (x86)/Steam"
		var output: Array = []
		var arguments := PackedStringArray(["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"])
		var exit_code: int = process.execute("reg.exe", arguments, output) if process != null else OS.execute("reg.exe", arguments, output, false, false)
		if process != null and process.cancelled():
			return found
		if exit_code == 0 and not output.is_empty():
			var pattern := RegEx.new()
			pattern.compile("SteamPath\\s+REG_SZ\\s+([^\\r\\n]+)")
			var value := pattern.search(str(output[0]))
			if value != null:
				steam = value.get_string(1).strip_edges().replace("\\", "/")
		found.append(steam)
	elif OS.get_name() == "Linux":
		var home := OS.get_environment("HOME")
		for relative in [".local/share/Steam", ".steam/steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam"]:
			var output: Array = []
			var arguments := PackedStringArray(["-e", home.path_join(relative)])
			var exit_code: int = process.execute("/usr/bin/realpath", arguments, output) if process != null else OS.execute("/usr/bin/realpath", arguments, output, false)
			if process != null and process.cancelled():
				return found
			if exit_code == 0 and not output.is_empty():
				found.append(str(output[0]).strip_edges())
	return found

## Each library once. The registry and libraryfolders.vdf spell the same Windows folder with
## different letter case; the spelling from Steam's own list is the one kept.
static func libraries(steam_roots: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var places := {}
	for root in steam_roots:
		for library in SteamFolders.library_paths(root):
			var key := library.trim_suffix("/")
			if OS.get_name() == "Windows":
				key = key.to_lower()
			if places.has(key):
				found[places[key]] = library
			else:
				places[key] = found.size()
				found.append(library)
	return found

## {} when the game is not installed. Otherwise {"library", "folder", "installdir", "buildid"}.
static func app(steam_libraries: Array[String], appid: int) -> Dictionary:
	for library in steam_libraries:
		var state: Variant = Vdf.parse_file(library.path_join("steamapps/appmanifest_%d.acf" % appid)).get("AppState")
		if state is Dictionary and str(state.get("installdir", "")) != "":
			var installdir := str(state.installdir)
			return {"library": library, "folder": library.path_join("steamapps/common").path_join(installdir), "installdir": installdir, "buildid": str(state.get("buildid", ""))}
	return {}

## One entry per installed Workshop item: {"id", "path", "size", "installed_at", "latest_at", "update"}.
## "update" is true or false when Steam recorded both times, and null when it did not.
static func workshop_items(library: String, appid: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var record: Variant = Vdf.parse_file(library.path_join("steamapps/workshop/appworkshop_%d.acf" % appid)).get("AppWorkshop")
	if not record is Dictionary:
		return items
	var installed: Variant = record.get("WorkshopItemsInstalled")
	var details: Variant = record.get("WorkshopItemDetails")
	if not installed is Dictionary:
		return items
	for id in installed:
		var entry: Variant = installed[id]
		var detail: Variant = details.get(id) if details is Dictionary else null
		if not entry is Dictionary:
			continue
		var installed_at := _time(entry.get("timeupdated"))
		var latest_at := _time(detail.get("latest_timeupdated")) if detail is Dictionary else -1
		var update: Variant = null
		if installed_at >= 0 and latest_at >= 0:
			update = latest_at > installed_at
		items.append({
			"id": str(id),
			"path": library.path_join("steamapps/workshop/content/%d" % appid).path_join(str(id)),
			"size": _time(entry.get("size")),
			"installed_at": installed_at,
			"latest_at": latest_at,
			"update": update,
		})
	return items

static func _time(value: Variant) -> int:
	return int(str(value)) if value != null and str(value).is_valid_int() else -1
