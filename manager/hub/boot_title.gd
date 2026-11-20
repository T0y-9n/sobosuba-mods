extends PanelContainer
## A title with a replaceable, aspect-preserving picture and a count of completed stages.

const UiTheme = preload("../manager_theme.gd")
const HubText = preload("hub_text.gd")
var status: Label
var progress: ProgressBar
var _heading: Label
var _words: Dictionary

func _init() -> void:
	name = "BootTitle"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SPACE_LG)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(column)
	var image := TextureRect.new()
	image.name = "BootImage"
	image.texture = load("res://assets/hub_title.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(image)
	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 28)
	column.add_child(_heading)
	status = Label.new()
	status.name = "BootStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	progress = ProgressBar.new()
	progress.name = "BootProgress"
	progress.show_percentage = false
	progress.custom_minimum_size.y = 8
	column.add_child(progress)
	# Read only the two presentation choices; discovery still owns full loading/migration.
	var diagnostic := OS.get_environment("HUB_BOOT_TRACE") == "1"
	var locale_done := 0
	var exists_done := 0
	var open_done := 0
	var read_done := 0
	var parse_done := 0
	var close_done := 0
	var started := Time.get_ticks_usec()
	var appearance := "system"
	var locale := OS.get_locale_language()
	if diagnostic:
		locale_done = Time.get_ticks_usec()
		FileAccess.file_exists("user://manager.json")
		exists_done = Time.get_ticks_usec()
	var file := FileAccess.open("user://manager.json", FileAccess.READ)
	if diagnostic:
		open_done = Time.get_ticks_usec()
		read_done = open_done
		parse_done = open_done
	if file != null:
		var contents := file.get_as_text()
		if diagnostic:
			read_done = Time.get_ticks_usec()
		var json := JSON.new()
		var parse_error := json.parse(contents)
		if diagnostic:
			parse_done = Time.get_ticks_usec()
		if parse_error == OK and json.data is Dictionary:
			var saved: Dictionary = json.data
			var choice := str(saved.get("appearance", ""))
			if choice in ["system", "light", "dark"]:
				appearance = choice
			if saved.get("locale") is String and not saved.locale.is_empty():
				locale = saved.locale
		file.close()
	if diagnostic:
		close_done = Time.get_ticks_usec()
	var ended := Time.get_ticks_usec()
	var elapsed_ms := ceili((ended - started) / 1000.0)
	print("Mod Hub boot first_look ", elapsed_ms)
	if diagnostic:
		print("Mod Hub trace lane=main stage=first_look/marks us=",
			JSON.stringify([started, locale_done, exists_done, open_done, read_done, parse_done, close_done, ended]))
	configure(HubText.load_words(locale), appearance)

func configure(words: Dictionary, appearance: String) -> void:
	_words = words
	UiTheme.apply(appearance, DisplayServer.is_dark_mode())
	theme = UiTheme.create()
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.tone("paper"), Color.TRANSPARENT, 0, 0, 0))
	_heading.text = HubText.text(words, "boot_name") + " " + str(ProjectSettings.get_setting("application/config/version"))
	_heading.add_theme_color_override("font_color", UiTheme.tone("ink"))
	status.add_theme_color_override("font_color", UiTheme.tone("muted"))
	progress.add_theme_stylebox_override("background", UiTheme.box(UiTheme.tone("paper"), Color.TRANSPARENT, 0, 0, 0))
	progress.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.tone("accent"), Color.TRANSPARENT, 0, 0, 0))
	stage("boot_discover", 0, 1)

func stage(key: String, done: int, total: int, game: String = "") -> void:
	var description := HubText.text(_words, key)
	if not game.is_empty():
		description = description % game
	status.text = HubText.text(_words, "boot_loading") % description
	progress.max_value = total
	progress.value = done
