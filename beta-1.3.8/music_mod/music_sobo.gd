extends Node

const MOD_VERSION := "1.3.11-1.2.0"
const IMPULSE_CAP := 3400.0

var settings: RefCounted
var play: RefCounted
var shake: Script
var play_button: SoboMenuButtonBool
var file_button: SoboMenuButtonBool
var beat_button: SoboMenuButtonFloat
var tone_button: SoboMenuButtonFloat
var range_button: SoboMenuButtonFloat
var dialog: FileDialog
var installing := false
var controls_ready := false
var previous := {"low": 0.0, "mid": 0.0, "high": 0.0}
var since_beat := 1.0
var samples: Array[Dictionary] = []

func _ready() -> void:
	var dir := (get_script() as Script).resource_path.get_base_dir()
	var settings_script: Script = load(dir.path_join("music_settings.gd"))
	var play_script: Script = load(dir.path_join("music_play.gd"))
	shake = load(dir.path_join("music_shake.gd"))
	settings = settings_script.new()
	settings.path = "user://music_sobo_settings.json"
	settings.load_file()
	play = play_script.new()
	play.prepare(self)
	if str(settings.song) != "":
		play.load_song(str(settings.song))
	if settings.playing and str(play.reason) == "":
		play.set_playing(true)
	install_controls()
	print("[Music Sobos %s] loaded" % MOD_VERSION)

func _exit_tree() -> void:
	if play != null:
		play.restore_reverb()

func _process(delta: float) -> void:
	since_beat += delta
	if shake == null or play == null or not play.is_playing():
		return
	var bus := AudioServer.get_bus_index("MusicSobo")
	if bus < 0:
		return
	var instance: AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(bus, 0)
	if instance == null:
		return
	var beat_level := _level(instance, 40.0, 160.0)
	var bands := {
		"low": _level(instance, 40.0, 250.0),
		"mid": _level(instance, 250.0, 2000.0),
		"high": _level(instance, 2000.0, 8000.0),
	}
	var average := _average(beat_level)
	var heard := beat_level if average >= 0.001 else 0.0
	var result: Dictionary = shake.step(bands, previous, average, since_beat, float(settings.beat), float(settings.tone), IMPULSE_CAP, heard, float(settings.shake_range))
	previous = bands
	if result.get("beat") == true:
		since_beat = 0.0
	var impulse := float(result.get("impulse", 0.0))
	if impulse <= 0.0:
		return
	for sobo: Sobo in SoboManager.all_sobos:
		if not is_instance_valid(sobo) or not is_instance_valid(sobo.extra_mass_ball):
			continue
		var direction := Vector2.UP.rotated(deg_to_rad(randf_range(-25.0, 25.0)))
		_push(sobo, direction, impulse)

func _push(sobo: Sobo, direction: Vector2, impulse: float) -> void:
	var total := sobo.extra_mass_ball.mass
	for suba: Suba in sobo.subas:
		total += suba.mass
	if total <= 0.0:
		return
	sobo.extra_mass_ball.apply_central_impulse(direction * impulse * sobo.extra_mass_ball.mass / total)
	for suba: Suba in sobo.subas:
		if is_instance_valid(suba):
			suba.apply_central_impulse(direction * impulse * suba.mass / total)

func install_controls() -> void:
	if controls_ready:
		return
	if installing:
		while not controls_ready:
			await get_tree().process_frame
		return
	installing = true
	for _frame: int in 120:
		if Menu._0 != null and Menu._0.game_settings_screen != null and Menu._0.settings_screen != null:
			break
		await get_tree().process_frame
	if Menu._0 == null or Menu._0.game_settings_screen == null:
		print("music sobo: game settings screen was not found")
		controls_ready = true
		return
	var game_screen: MenuScreen = Menu._0.settings_mobile_screen if OS.has_feature("mobile") else Menu._0.game_settings_screen
	var model: SoboMenuButtonBool = game_screen.get("show_instructions_control")
	if model == null:
		print("music sobo: show instructions was not found")
		controls_ready = true
		return
	play_button = _copy_button(model, "MusicPlay")
	play_button.release_press.connect(_on_play)
	file_button = _copy_button(model, "MusicFile")
	file_button.release_press.connect(_on_file)
	var volume: SoboMenuButtonFloat = Menu._0.settings_screen.get("volume_control")
	if volume != null:
		beat_button = _copy_float(volume, "MusicBeat")
		beat_button.min_value = 0.0
		beat_button.max_value = 2.0
		beat_button.on_value_changed.connect(_on_beat)
		tone_button = _copy_float(volume, "MusicTone")
		tone_button.min_value = 0.0
		tone_button.max_value = 2.0
		tone_button.on_value_changed.connect(_on_tone)
		range_button = _copy_float(volume, "MusicRange")
		range_button.min_value = 0.0
		range_button.max_value = 3.0
		range_button.on_value_changed.connect(_on_range)
	dialog = FileDialog.new()
	dialog.name = "MusicFileDialog"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = false
	dialog.filters = PackedStringArray(["*.wav ; WAV", "*.ogg ; Ogg", "*.mp3 ; MP3"])
	dialog.file_selected.connect(_on_chosen)
	get_tree().root.add_child(dialog)
	_refresh()
	controls_ready = true

func _copy_button(model: SoboMenuButtonBool, node_name: String) -> SoboMenuButtonBool:
	var button: SoboMenuButtonBool = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	_copy_values(model, button)
	button.name = node_name
	model.add_sibling(button)
	return button

func _copy_float(model: SoboMenuButtonFloat, node_name: String) -> SoboMenuButtonFloat:
	var button: SoboMenuButtonFloat = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	_copy_values(model, button)
	button.name = node_name
	model.add_sibling(button)
	return button

func _copy_values(model: Node, button: Node) -> void:
	for prop: Dictionary in model.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			button.set(prop.name, _value_for_copy(model.get(prop.name), model, button))

func _value_for_copy(value: Variant, original: Node, copy: Node) -> Variant:
	if value is Node:
		if value == original:
			return copy
		if original.is_ancestor_of(value):
			return copy.get_node_or_null(original.get_path_to(value))
		return value
	if value is Array:
		var mapped: Array = value.duplicate()
		for index: int in mapped.size():
			mapped[index] = _value_for_copy(mapped[index], original, copy)
		return mapped
	return value

func _on_play() -> void:
	settings.playing = settings.playing == false
	settings.save_file()
	if settings.playing and str(play.reason) == "" and str(settings.song) != "":
		play.set_playing(true)
	else:
		play.set_playing(false)
		if settings.playing and str(settings.song) == "":
			play.reason = "file not found"
			print("music sobo: file not found")
	_refresh()

func _on_file() -> void:
	if dialog != null:
		dialog.popup_centered()

func _on_chosen(path: String) -> void:
	settings.song = path
	settings.save_file()
	var notice: String = play.load_song(path)
	if notice != "":
		settings.playing = false
		play.set_playing(false)
		settings.save_file()
	_refresh()

func _on_beat(value: float) -> void:
	settings.beat = clampf(value, 0.0, 2.0)
	settings.save_file()

func _on_tone(value: float) -> void:
	settings.tone = clampf(value, 0.0, 2.0)
	settings.save_file()

func _on_range(value: float) -> void:
	settings.shake_range = clampf(value, 0.0, 3.0)
	settings.save_file()

func _refresh() -> void:
	if play_button != null:
		play_button.set_value(settings.playing)
		play_button.label.text = _play_label()
	if file_button != null:
		file_button.label.text = _file_label()
	if beat_button != null:
		beat_button.set_value(float(settings.beat))
		beat_button.label.text = _beat_label()
	if tone_button != null:
		tone_button.set_value(float(settings.tone))
		tone_button.label.text = _tone_label()
	if range_button != null:
		range_button.set_value(float(settings.shake_range))
		range_button.label.text = _range_label()

func _file_label() -> String:
	if str(play.reason) != "":
		return _reason_text(str(play.reason))
	if str(settings.song) == "":
		if TranslationServer.get_locale().begins_with("ja"):
			return "曲を選ぶ"
		return "Choose a song"
	return str(settings.song).get_file()

func _reason_text(code: String) -> String:
	var japanese := TranslationServer.get_locale().begins_with("ja")
	if code == "file not found":
		if japanese:
			return "ファイルが無い"
		return "file not found"
	if code == "unsupported file":
		if japanese:
			return "対応していない形式"
		return "unsupported file"
	if code == "could not read the file":
		if japanese:
			return "曲を読めなかった"
		return "could not read the file"
	return code

func _play_label() -> String:
	if TranslationServer.get_locale().begins_with("ja"):
		return "曲を流す"
	return "Play song"

func _beat_label() -> String:
	if TranslationServer.get_locale().begins_with("ja"):
		return "拍の強さ"
	return "Beat"

func _tone_label() -> String:
	if TranslationServer.get_locale().begins_with("ja"):
		return "音の高さの揺れ"
	return "Pitch shake"

func _range_label() -> String:
	if TranslationServer.get_locale().begins_with("ja"):
		return "揺れの幅"
	return "Shake range"

func _level(instance: AudioEffectSpectrumAnalyzerInstance, from_hz: float, to_hz: float) -> float:
	return instance.get_magnitude_for_frequency_range(from_hz, to_hz).y

func _average(level: float) -> float:
	var now := Time.get_ticks_msec() / 1000.0
	samples.append({"t": now, "v": level})
	var kept: Array[Dictionary] = []
	var sum := 0.0
	for item: Dictionary in samples:
		if now - float(item.t) <= 1.0:
			kept.append(item)
			sum += float(item.v)
	samples = kept
	if kept.is_empty():
		return 0.0
	return sum / kept.size()
