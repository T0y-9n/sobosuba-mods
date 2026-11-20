extends RefCounted
## Only filesystem/process work. No active nodes or rendering objects enter this worker.

const Settings = preload("../settings.gd")
const Platform = preload("../platform.gd")
const SteamFolders = preload("../steam_folders.gd")
const GameDefs = preload("game_defs.gd")
const SteamLibrary = preload("steam_library.gd")
const HubSettings = preload("hub_settings.gd")
const BootTrace = preload("boot_trace.gd")

static func discover(process: RefCounted) -> Dictionary:
	if process.cancelled():
		return {}
	var started := Time.get_ticks_msec()
	var trace := BootTrace.begin("worker_discover", "settings")
	var settings := Settings.new()
	settings.load_file()
	BootTrace.end("worker_discover", "settings", trace)
	if cancelled_after(process, "settings", started):
		return {}
	started = Time.get_ticks_msec()
	trace = BootTrace.begin("worker_discover", "game_folder")
	var folder: String = settings.game_folder
	if folder.is_empty():
		folder = SteamFolders.find_game(process)
	BootTrace.end("worker_discover", "game_folder", trace)
	if cancelled_after(process, "game_folder", started):
		return {}
	started = Time.get_ticks_msec()
	trace = BootTrace.begin("worker_discover", "other_copies")
	var another_copy := Platform.other_copies(process) > 0
	BootTrace.end("worker_discover", "other_copies", trace)
	if cancelled_after(process, "other_copies", started):
		return {}
	started = Time.get_ticks_msec()
	trace = BootTrace.begin("worker_discover", "definitions")
	var definitions := GameDefs.load_all()
	BootTrace.end("worker_discover", "definitions", trace)
	if cancelled_after(process, "definitions", started):
		return {}
	started = Time.get_ticks_msec()
	trace = BootTrace.begin("worker_discover", "libraries")
	var libraries := SteamLibrary.libraries(SteamLibrary.roots(process))
	BootTrace.end("worker_discover", "libraries", trace)
	if cancelled_after(process, "libraries", started):
		return {}
	started = Time.get_ticks_msec()
	trace = BootTrace.begin("worker_discover", "installed")
	var installed := GameDefs.installed(definitions, libraries)
	BootTrace.end("worker_discover", "installed", trace)
	if cancelled_after(process, "installed", started):
		return {}
	return {
		"settings": settings, "game_folder": folder,
		"another_copy": another_copy,
		"definitions": installed,
		"selected": HubSettings.load_selected(),
	}

static func cancelled_after(process: RefCounted, stage: String, started: int) -> bool:
	if not process.cancelled():
		return false
	print("Mod Hub close discover_", stage, " ", Time.get_ticks_msec() - started)
	return true
