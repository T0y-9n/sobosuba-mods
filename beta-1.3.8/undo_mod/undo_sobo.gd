extends Node

const MOD_VERSION := "1.3.11-1.0.0"
const DEPTH := 5
const MENU_WAIT_FRAMES := 600

var history: Array = []
var run_undo := false
var settings: RefCounted
var toggle: SoboMenuButtonBool


func _init() -> void:
	name = "UndoSobo"


func mod_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir()


func _ready() -> void:
	print("[Undo %s] loaded" % MOD_VERSION)
	var settings_script: GDScript = load_user(mod_dir().path_join("undo_settings.gd"))
	if settings_script == null:
		print("undo settings did not compile")
		return
	settings = settings_script.new()
	settings.path = "user://undo_settings.json"
	settings.load_file()
	install_score_guard()
	SignalBus.on_game_mode_start.connect(on_game_mode_start)
	install_toggle.call_deferred()
	if FileAccess.file_exists(mod_dir().path_join("undo.flag")):
		var script: GDScript = load_user(mod_dir().path_join("undo_selftest.gd"))
		if script == null:
			print("undo selftest did not compile")
			return
		var test: Node = script.new()
		test.mod = self
		add_child(test)


func load_user(path: String) -> GDScript:
	var gd := GDScript.new()
	gd.source_code = FileAccess.get_file_as_string(path)
	gd.take_over_path(path)
	if gd.reload() != OK:
		return null
	return gd


func install_score_guard() -> void:
	var script: GDScript = load_user(mod_dir().path_join("undo_score.gd"))
	if script == null:
		print("undo score guard did not compile")
		return
	patch_node(ScoreManager, script)


func on_game_mode_start(mode: GameScene) -> void:
	history.clear()
	var block: bool = settings.enabled
	run_undo = block and mode is SceneClassic
	Engine.set_meta("undo_run", block)
	if block:
		ScoreManager.disable_score_submitting = true
	else:
		ScoreManager.apply_run_scoring()
	if run_undo:
		mode.ready.connect(install_hook.bind(mode), CONNECT_ONE_SHOT)


func install_hook(mode: Node) -> void:
	if not is_instance_valid(mode) or not run_undo:
		return
	install_hook_deferred.call_deferred(mode)


func install_hook_deferred(mode: Node) -> void:
	if not is_instance_valid(mode) or not run_undo:
		return
	var current: Script = mode.get_script() as Script
	if current == null or current.resource_path.is_empty():
		print("undo hook skipped: scene script has no path")
		return
	if current.resource_path.ends_with("undo_launch.gd"):
		return
	var path: String = mod_dir().path_join("undo_launch.gd")
	var source: String = "extends \"%s\"\n\nfunc launch_sobo(sobo: Sobo, nrm_vel: Vector2):\n\tvar undo: Node = get_node_or_null(\"/root/UndoSobo\")\n\tif undo != null and undo.run_undo:\n\t\tundo.remember_board()\n\tsuper.launch_sobo(sobo, nrm_vel)\n" % current.resource_path
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("undo hook skipped: could not write the script")
		return
	f.store_string(source)
	f.close()
	var script: GDScript = load_user(path)
	if script == null:
		print("undo hook skipped: script did not compile")
		return
	patch_node(mode, script)


func patch_node(target: Node, script: Script) -> void:
	var values: Dictionary = {}
	for prop: Dictionary in target.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[prop.name] = target.get(prop.name)
	target.set_script(script)
	for key: String in values:
		target.set(key, values[key])


func remember_board() -> void:
	if not run_undo:
		print("undo remember skipped: run is not latched (0)")
		return
	var scene: SceneClassic = GameModeManager.current_scene as SceneClassic
	if scene == null:
		print("undo remember skipped: no scene (0)")
		return
	var state: GameState = scene.capture_state(false)
	var shot: Dictionary = {
		"state": state,
		"time": ScoreManager.current_time,
		"largest": int(scene.get("largest_merged_size")),
	}
	history.append(shot)
	while history.size() > DEPTH:
		history.pop_front()


func undo() -> bool:
	if history.is_empty():
		print("undo skipped: no snapshot (0)")
		return false
	var scene: SceneClassic = GameModeManager.current_scene as SceneClassic
	if scene == null:
		print("undo skipped: no scene (0)")
		return false
	var shot: Dictionary = history.pop_back()
	scene.apply_game_state(shot.state)
	ScoreManager.current_time = float(shot.time)
	scene.set("largest_merged_size", int(shot.largest))
	print("undo restored: %d left" % history.size())
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not run_undo or event.is_echo():
		return
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.keycode != KEY_U:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	var scene: SceneClassic = GameModeManager.current_scene as SceneClassic
	if scene == null or scene.state != SceneClassic.State.PLAYING:
		return
	undo()
	get_viewport().set_input_as_handled()


func install_toggle() -> void:
	for _frame in MENU_WAIT_FRAMES:
		if Menu._0 != null and Menu._0.is_node_ready() and Menu._0.game_settings_screen != null:
			break
		await get_tree().process_frame
	if Menu._0 == null or Menu._0.game_settings_screen == null:
		print("undo switch skipped: game settings screen was not found")
		return
	var game_screen: MenuScreen = Menu._0.settings_mobile_screen if OS.has_feature("mobile") else Menu._0.game_settings_screen
	var model: SoboMenuButtonBool = game_screen.get("show_instructions_control") if game_screen != null else null
	if model == null:
		print("undo switch skipped: show instructions was not found")
		return
	var button: SoboMenuButtonBool = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	for prop: Dictionary in model.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			button.set(prop.name, value_for_copy(model.get(prop.name), model, button))
	button.name = "Undo"
	button.label.text = label_text()
	button.tooltip_text = tip_text()
	button.release_press.connect(on_toggle_pressed)
	model.add_sibling(button)
	toggle = button
	refresh_toggle()
	print("undo switch installed")


func value_for_copy(value: Variant, original: Node, copy: Node) -> Variant:
	if value is Node:
		if value == original:
			return copy
		if original.is_ancestor_of(value):
			return copy.get_node_or_null(original.get_path_to(value))
		return value
	if value is Array:
		var mapped: Array = value.duplicate()
		for i in mapped.size():
			mapped[i] = value_for_copy(mapped[i], original, copy)
		return mapped
	return value


func label_text() -> String:
	if TranslationServer.get_locale().begins_with("ja"):
		return "一手戻す"
	return "undo"


func tip_text() -> String:
	if TranslationServer.get_locale().begins_with("ja"):
		return "ソボを放つ直前の盤面へ、5回まで戻します。入のあいだ、どの一局も順位表へ送りません。"
	return "Restores the board from before a launch, up to 5 times. While on, no run is sent to a leaderboard."


func refresh_toggle() -> void:
	if toggle == null:
		return
	toggle.set_value(settings.enabled)
	toggle.label.text = label_text()
	toggle.tooltip_text = tip_text()


func on_toggle_pressed() -> void:
	settings.set_enabled(settings.enabled == false)
	refresh_toggle()
	if settings.enabled:
		Engine.set_meta("undo_run", true)
		ScoreManager.disable_score_submitting = true
		print("undo switch: on, this run will not send")
		return
	print("undo switch: off, next run can send")
