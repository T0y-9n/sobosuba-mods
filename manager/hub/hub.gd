extends Control
## The hub shell: a rail of games on the left and the selected game's screen on the right.
## It is the main scene only in builds exported with the "hub" feature.

const HubMode = preload("hub_mode.gd")
const LibraryView = preload("library_view.gd")
const HubText = preload("hub_text.gd")
const HubSettings = preload("hub_settings.gd")
const BootData = preload("boot_data.gd")
const BootTitle = preload("boot_title.gd")
const BootProcess = preload("boot_process.gd")
const BootTrace = preload("boot_trace.gd")
const MANAGER_MIN := Vector2i(1040, 680)
const MANAGER_WIDTH := 1180
const RAIL_WIDTH := 220
const TITLE := "Mod Hub"

var row: HBoxContainer
var rail: VBoxContainer
var screens: Dictionary = {}
var buttons: Dictionary = {}
var selected := ""
var booting := true
var _worker: Thread
var _title: PanelContainer
var _closing := false
var _boot_running := true
var _boot_process := BootProcess.new()
var _close_started := 0

func _init() -> void:
	HubMode.active = true

func _ready() -> void:
	await boot()
	_boot_running = false

func boot() -> void:
	get_tree().auto_accept_quit = false
	get_window().title = TITLE + " " + str(ProjectSettings.get_setting("application/config/version"))
	_title = BootTitle.new()
	add_child(_title)
	# Two process-frame boundaries guarantee a full draw opportunity before discovery I/O.
	await get_tree().process_frame
	if _closing:
		return
	await get_tree().process_frame
	if _closing:
		return
	var started := Time.get_ticks_msec()
	_worker = Thread.new()
	if _worker.start(BootData.discover.bind(_boot_process)) != OK:
		push_error("Mod Hub could not start its boot reader")
		get_tree().quit(1)
		return
	while _worker.is_alive():
		await get_tree().process_frame
		if _closing:
			return
	var data: Dictionary = _worker.wait_to_finish()
	_worker = null
	if _closing:
		return
	print("Mod Hub boot discover ", Time.get_ticks_msec() - started)
	var trace := BootTrace.begin("main", "hub/title/configure")
	var settings: RefCounted = data.settings
	var words := HubText.load_words(settings.locale if not settings.locale.is_empty() else OS.get_locale_language())
	_title.configure(words, settings.appearance)
	var definitions: Array[Dictionary] = data.definitions
	var total := definitions.filter(func(definition: Dictionary) -> bool: return definition.get("screen") == "library").size() + 2
	var done := 1
	_title.stage("boot_game", done, total, "sobosuba")
	BootTrace.end("main", "hub/title/configure", trace)
	await get_tree().process_frame
	if _closing:
		return
	started = Time.get_ticks_msec()
	# Script/resource loading also occurs after the title has been drawn.
	var request_error := ResourceLoader.load_threaded_request("res://main.tscn")
	if request_error != OK:
		boot_failed("scene request code=%d" % request_error)
		return
	var scene_status := ResourceLoader.load_threaded_get_status("res://main.tscn")
	while scene_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		scene_status = ResourceLoader.load_threaded_get_status("res://main.tscn")
	# Consume the completed request on failure too, releasing the loader's task.
	var scene := ResourceLoader.load_threaded_get("res://main.tscn") as PackedScene
	if scene_status != ResourceLoader.THREAD_LOAD_LOADED:
		if not _closing:
			boot_failed("scene load status=%d" % scene_status)
		return
	if _closing:
		return
	if scene == null:
		boot_failed("scene is not a PackedScene")
		return
	trace = BootTrace.begin("main", "sobosuba/instantiate")
	row = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.visible = false
	add_child(row)
	var panel := PanelContainer.new()
	panel.name = "HubRail"
	panel.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	row.add_child(panel)
	rail = VBoxContainer.new()
	panel.add_child(rail)
	var manager := scene.instantiate()
	BootTrace.end("main", "sobosuba/instantiate", trace)
	print("Mod Hub boot sobosuba_resources ", Time.get_ticks_msec() - started)
	manager.hub_startup = data
	manager.store.boot_process = BootProcess.new()
	await get_tree().process_frame
	if _closing:
		# These helpers have not entered the tree, so _exit_tree cannot release them.
		manager.catalog.free()
		manager.self_update.free()
		manager.free()
		return
	add_screen("sobosuba", "sobosuba", manager)
	while manager.hub_starting or manager.busy:
		await get_tree().process_frame
		if _closing:
			return
	print("Mod Hub boot sobosuba ", Time.get_ticks_msec() - started)
	done += 1
	await get_tree().process_frame
	if _closing:
		return
	for definition in definitions:
		if _closing:
			return
		if definition.get("screen") == "library":
			_title.stage("boot_game", done, total, definition.name)
			await get_tree().process_frame
			if _closing:
				return
			started = Time.get_ticks_msec()
			trace = BootTrace.begin("main", str(definition.id) + "/instantiate")
			var view := LibraryView.new()
			view.setup(definition, words)
			BootTrace.end("main", str(definition.id) + "/instantiate", trace)
			await get_tree().process_frame
			if _closing:
				view.title_source.free()
				view.free()
				return
			add_screen(definition.id, definition.name, view)
			await view.refresh()
			if _closing:
				return
			print("Mod Hub boot ", definition.id, " ", Time.get_ticks_msec() - started)
			done += 1
			await get_tree().process_frame
			if _closing:
				return
	_title.progress.value = total
	var saved: String = data.selected
	var restored := saved if screens.has(saved) else "sobosuba"
	if restored != "sobosuba":
		screens[restored].skip_next_show = true
	select(restored, false)
	print("Mod Hub games ", screens.size())
	if "--update-probe" in OS.get_cmdline_user_args():
		manager.finish_update_probe()
		return
	var extra: int = RAIL_WIDTH + row.get_theme_constant("separation")
	var window := get_window()
	window.min_size = Vector2i(MANAGER_MIN.x + extra, MANAGER_MIN.y)
	window.size = Vector2i(maxi(window.size.x, MANAGER_WIDTH + extra), window.size.y)
	window.title = TITLE + " " + str(ProjectSettings.get_setting("application/config/version"))
	_title.free()
	_title = null
	row.show()
	booting = false
	# As in the standalone app, update checks begin after the usable screen is shown.
	manager.check_updates.call_deferred()

func boot_failed(reason: String) -> void:
	print("Mod Hub boot failed ", reason)
	get_tree().quit(1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and booting and not _closing:
		_close_started = Time.get_ticks_msec()
		_closing = true
		# This mode is transient: never persist it in manager or hub settings.
		get_window().mode = Window.MODE_MINIMIZED
		print("Mod Hub close minimize_request ", Time.get_ticks_msec() - _close_started)
		_boot_process.cancel()
		for id in screens:
			if id != "sobosuba":
				screens[id]._closing = true
		if screens.has("sobosuba"):
			screens.sobosuba.hub_closing = true
			if screens.sobosuba.store.boot_process != null:
				screens.sobosuba.store.boot_process.cancel()
		close_boot.call_deferred()
		print("Mod Hub close cancel ", Time.get_ticks_msec() - _close_started)

func close_boot() -> void:
	print("Mod Hub close dispatch ", Time.get_ticks_msec() - _close_started)
	var started := Time.get_ticks_msec()
	if screens.has("sobosuba"):
		var manager: Control = screens.sobosuba
		manager.hub_closing = true
		while manager.hub_starting or not manager._hub_workers.is_empty():
			await get_tree().process_frame
	print("Mod Hub close manager ", Time.get_ticks_msec() - started)
	started = Time.get_ticks_msec()
	if _worker != null:
		while _worker.is_alive():
			await get_tree().process_frame
		_worker.wait_to_finish()
		_worker = null
	print("Mod Hub close discover ", Time.get_ticks_msec() - started)
	for id in screens:
		if id != "sobosuba":
			started = Time.get_ticks_msec()
			while screens[id].reading:
				await get_tree().process_frame
			print("Mod Hub close library_", id, " ", Time.get_ticks_msec() - started)
	started = Time.get_ticks_msec()
	while _boot_running:
		await get_tree().process_frame
	print("Mod Hub close boot_coroutine ", Time.get_ticks_msec() - started)
	started = Time.get_ticks_msec()
	# Let the startup coroutines return before SceneTree tears down their resources.
	await get_tree().process_frame
	await get_tree().process_frame
	print("Mod Hub close frames ", Time.get_ticks_msec() - started)
	print("Mod Hub close ready ", Time.get_ticks_msec() - _close_started)
	get_tree().quit()

func _exit_tree() -> void:
	var started := Time.get_ticks_msec()
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
	if _closing:
		print("Mod Hub close exit_tree ", Time.get_ticks_msec() - started)
		print("Mod Hub close exit_tree_total ", Time.get_ticks_msec() - _close_started)

func add_screen(id: String, label: String, screen: Control) -> void:
	var trace := BootTrace.begin("main", id + "/add_screen")
	screen.name = "Screen_" + id
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.visible = false
	row.add_child(screen)
	screens[id] = screen
	var button := Button.new()
	button.name = "Game_" + id
	button.text = label
	button.tooltip_text = label
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(select.bind(id))
	rail.add_child(button)
	buttons[id] = button
	BootTrace.end("main", id + "/add_screen", trace)

func select(id: String, remember: bool = true) -> void:
	if not screens.has(id):
		return
	selected = id
	for key in screens:
		screens[key].visible = key == id
		buttons[key].set_pressed_no_signal(key == id)
	if remember:
		HubSettings.save_selected(id)
