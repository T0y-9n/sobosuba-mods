extends Control

const Store = preload("mod_store.gd")
const Settings = preload("settings.gd")
const SteamFolders = preload("steam_folders.gd")
const Catalog = preload("catalog.gd")
const Words = preload("text.gd")
var store := Store.new()
var settings := Settings.new()
var words := Words.new()
var catalog := Catalog.new()
var busy := false
var mods: Array = []
var target: Dictionary = {}
var bindings: Array = []
var controls: Array[BaseButton] = []
var path_label: Label
var detected_label: Label
var destination_label: Label
var notice: Label
var rows: VBoxContainer
var version_picker: OptionButton
var language_picker: OptionButton
var folder_dialog: FileDialog
var zip_dialog: FileDialog
var install_dialog: ConfirmationDialog
var operation_dialog: ConfirmationDialog
var adopt_check: CheckBox
var preview_label: Label
var pending_package: Dictionary = {}
var pending_zip := ""
var pending_operation := ""
var pending_mod: Dictionary = {}
var notice_key := ""
var notice_error := ""
var notice_args: Array = []

func _ready() -> void:
	get_window().min_size = Vector2i(1000, 620)
	get_tree().auto_accept_quit = false
	settings.load_file()
	if not settings.locale.is_empty():
		words.set_locale(settings.locale)
	store.game_folder = settings.game_folder
	store.game_version = settings.game_version
	store.user_data = settings.user_data
	if store.game_folder.is_empty():
		store.game_folder = SteamFolders.find_game()
	add_child(catalog)
	build_screen()
	await refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not busy:
		get_tree().quit()

func label(text: String = "", size: int = 16) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

func caption(parent: Node, key: String, size: int = 16) -> Label:
	var item := label(words.word(key), size)
	parent.add_child(item)
	bindings.append({"node": item, "key": key})
	return item

func action(parent: Node, key: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = words.word(key)
	item.custom_minimum_size.y = 40
	item.pressed.connect(callback)
	item.disabled = busy
	parent.add_child(item)
	bindings.append({"node": item, "key": key})
	controls.append(item)
	return item

func card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var inset := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(inset)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	inset.add_child(layout)
	return layout

func build_screen() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 16
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Yu Gothic UI", "Microsoft YaHei UI", "Microsoft JhengHei UI", "Malgun Gothic"])
	ui_theme.default_font = font
	theme = ui_theme
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 16)
	scroll.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	caption(heading, "title", 27)
	language_picker = OptionButton.new()
	language_picker.custom_minimum_size = Vector2(185, 40)
	for code in Words.LANGUAGES:
		language_picker.add_item(Words.LANGUAGES[code])
		language_picker.set_item_metadata(language_picker.item_count - 1, code)
		if code == words.locale:
			language_picker.select(language_picker.item_count - 1)
	language_picker.item_selected.connect(func(index): change_locale(str(language_picker.get_item_metadata(index))))
	heading.add_child(language_picker)
	controls.append(language_picker)
	caption(layout, "subtitle", 15)
	var location := card(layout)
	caption(location, "game_folder", 14)
	var path_row := HBoxContainer.new()
	location.add_child(path_row)
	path_label = label(store.game_folder)
	path_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_label.clip_text = true
	path_row.add_child(path_label)
	action(path_row, "change", func(): folder_dialog.popup_centered_ratio(0.8))
	var version_row := HBoxContainer.new()
	version_row.add_theme_constant_override("separation", 16)
	location.add_child(version_row)
	var version_label := caption(version_row, "version")
	version_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	version_label.custom_minimum_size.x = 140
	version_picker = OptionButton.new()
	version_picker.add_item("1.2.3")
	version_picker.add_item("1.3.10")
	version_picker.select(0 if store.game_version == "1.2.3" else 1)
	version_picker.custom_minimum_size = Vector2(130, 40)
	version_picker.item_selected.connect(select_version)
	version_row.add_child(version_picker)
	controls.append(version_picker)
	detected_label = label()
	version_row.add_child(detected_label)
	destination_label = label("", 14)
	location.add_child(destination_label)
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 10)
	layout.add_child(toolbar)
	action(toolbar, "install_zip", func(): zip_dialog.popup_centered_ratio(0.8))
	action(toolbar, "refresh", refresh)
	action(toolbar, "catalog", reload_catalog)
	action(toolbar, "recover", recover)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	layout.add_child(rows)
	caption(layout, "preserve", 14)
	notice = label()
	notice.custom_minimum_size.y = 58
	layout.add_child(notice)
	folder_dialog = FileDialog.new()
	folder_dialog.use_native_dialog = true
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.dir_selected.connect(select_folder)
	add_child(folder_dialog)
	zip_dialog = FileDialog.new()
	zip_dialog.use_native_dialog = true
	zip_dialog.access = FileDialog.ACCESS_FILESYSTEM
	zip_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	zip_dialog.filters = PackedStringArray(["*.zip"])
	zip_dialog.file_selected.connect(inspect_zip)
	add_child(zip_dialog)
	install_dialog = ConfirmationDialog.new()
	install_dialog.get_label().hide()
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 16)
	install_dialog.add_child(preview_box)
	preview_label = label()
	preview_label.custom_minimum_size.x = 660
	preview_box.add_child(preview_label)
	install_dialog.confirmed.connect(install_selected)
	adopt_check = CheckBox.new()
	adopt_check.custom_minimum_size.y = 52
	preview_box.add_child(adopt_check)
	install_dialog.canceled.connect(func(): pending_package = {}; pending_zip = "")
	add_child(install_dialog)
	operation_dialog = ConfirmationDialog.new()
	operation_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operation_dialog.get_label().custom_minimum_size.x = 660
	operation_dialog.confirmed.connect(run_operation)
	add_child(operation_dialog)
	translate_dialogs()

func set_busy(value: bool) -> void:
	busy = value
	controls = controls.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	for item in controls:
		item.disabled = value
	if value:
		notice.text = words.word("loading")

func invoke(operation: String, extra: Dictionary = {}) -> Dictionary:
	var thread := Thread.new()
	var error := thread.start(store.request.bind(operation, extra))
	if error != OK:
		return {"ok": false, "error": "io_error"}
	while thread.is_alive():
		await get_tree().create_timer(0.03).timeout
	return thread.wait_to_finish()

func refresh() -> void:
	if busy:
		return
	set_busy(true)
	await read_state()
	set_busy(false)
	render_notice()

func read_state() -> void:
	var result: Dictionary = await invoke("list")
	if result.ok:
		mods = result.data.mods
		target = result.data.target
	else:
		mods = []
		target = {}
		notice_error = str(result.get("error", "invalid_request"))
		notice_args = result.get("args", [])
	render_rows()

func render_rows() -> void:
	for item in rows.get_children():
		rows.remove_child(item)
		item.queue_free()
	path_label.text = store.game_folder if not store.game_folder.is_empty() else words.word("err_target")
	path_label.tooltip_text = path_label.text
	detected_label.text = words.word("detected", [target.detected]) if not str(target.get("detected", "")).is_empty() else words.word("selected")
	destination_label.text = words.word("destination", [target.get("root", "—")])
	for mod in mods:
		var row := card(rows)
		var title_row := HBoxContainer.new()
		row.add_child(title_row)
		title_row.add_child(label(str(mod.name) + ("  " + str(mod.version) if not str(mod.version).is_empty() else ""), 20))
		var status := "manual" if mod.manual else ("enabled" if mod.enabled else "disabled")
		var state := label(words.word(status), 15)
		state.autowrap_mode = TextServer.AUTOWRAP_OFF
		state.size_flags_horizontal = Control.SIZE_SHRINK_END
		title_row.add_child(state)
		row.add_child(label(words.word("supported", [", ".join(mod.get("game_versions", [])) if not mod.manual else "—"]), 14))
		if not mod.compatible:
			caption(row, "incompatible", 14)
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 10)
		row.add_child(actions)
		if not mod.manual:
			var toggle := action(actions, "disable" if mod.enabled else "enable", toggle_enabled.bind(mod))
			toggle.disabled = busy or (not mod.enabled and not mod.compatible)
			action(actions, "uninstall", confirm_operation.bind("uninstall", mod))
		else:
			caption(row, "err_adopt", 14)
	for mod in catalog.mods:
		var row := card(rows)
		row.add_child(label(mod.name + "  " + mod.version))
		action(row, "install_zip", download_mod.bind(mod))
	if mods.is_empty() and catalog.mods.is_empty():
		caption(rows, "empty")
	bindings = bindings.filter(func(item): return is_instance_valid(item.node) and not item.node.is_queued_for_deletion())

func render_notice() -> void:
	notice.text = words.error_word(notice_error, notice_args) if not notice_error.is_empty() else words.word(notice_key) if not notice_key.is_empty() else ""
	notice.modulate = Color(1.0, 0.7, 0.55) if not notice_error.is_empty() else Color(0.82, 0.88, 0.92)

func translate_dialogs() -> void:
	folder_dialog.title = words.word("choose_folder")
	zip_dialog.title = words.word("choose_zip")
	for dialog in [install_dialog, operation_dialog]:
		dialog.title = words.word("confirm")
		dialog.ok_button_text = words.word("confirm")
		dialog.cancel_button_text = words.word("cancel")
	adopt_check.text = words.word("adopt")
	if not pending_package.is_empty():
		preview_label.text = words.word("install_question", [pending_package.name, pending_package.version]) + "\n\n" + words.word("supported", [", ".join(pending_package.game_versions)]) + "\n" + words.word("destination", [target.get("root", "—")]) + "\n\n" + words.word("preserve")
	if not pending_mod.is_empty():
		operation_dialog.dialog_text = words.word("remove_question" if pending_operation == "uninstall" else "disable_question", [pending_mod.name]) + "\n\n" + words.word("preserve")

func change_locale(locale: String) -> void:
	if busy:
		return
	words.set_locale(locale)
	settings.locale = words.locale
	settings.save()
	for item in bindings:
		if is_instance_valid(item.node) and not item.node.is_queued_for_deletion():
			item.node.text = words.word(item.key)
	for index in language_picker.item_count:
		if language_picker.get_item_metadata(index) == words.locale:
			language_picker.select(index)
	render_rows()
	translate_dialogs()
	render_notice()

func save_target() -> void:
	settings.game_folder = store.game_folder
	settings.game_version = store.game_version
	if settings.save() != OK:
		notice_error = "io_error"

func select_folder(path: String) -> void:
	if busy:
		return
	store.game_folder = path
	notice_error = ""
	save_target()
	await refresh()

func select_version(index: int) -> void:
	if busy:
		return
	store.game_version = version_picker.get_item_text(index)
	notice_error = ""
	save_target()
	await refresh()

func inspect_zip(path: String) -> void:
	if busy:
		return
	set_busy(true)
	var result := await invoke("inspect", {"zip": path})
	set_busy(false)
	if result.ok:
		pending_package = result.data
		pending_zip = path
		adopt_check.button_pressed = false
		translate_dialogs()
		install_dialog.popup_centered(Vector2i(720, 300))
	else:
		notice_error = result.error
		notice_args = result.get("args", [])
	render_notice()

func install_selected() -> void:
	if busy or pending_package.is_empty():
		return
	set_busy(true)
	var result := await invoke("install", {"zip": pending_zip, "sha256": pending_package.sha256, "adopt": adopt_check.button_pressed})
	pending_package = {}
	pending_zip = ""
	await finish_operation(result)

func toggle_enabled(mod: Dictionary) -> void:
	if busy:
		return
	if mod.enabled:
		confirm_operation("disable", mod)
	else:
		pending_operation = "enable"
		pending_mod = mod
		await run_operation()

func confirm_operation(operation: String, mod: Dictionary) -> void:
	if busy:
		return
	pending_operation = operation
	pending_mod = mod
	translate_dialogs()
	operation_dialog.popup_centered(Vector2i(720, 250))

func run_operation() -> void:
	if busy or pending_mod.is_empty():
		return
	set_busy(true)
	var result := await invoke(pending_operation, {"id": pending_mod.id, "layout": pending_mod.layout})
	pending_mod = {}
	await finish_operation(result)

func finish_operation(result: Dictionary) -> void:
	notice_error = "" if result.ok else str(result.error)
	notice_args = [] if result.ok else result.get("args", [])
	notice_key = "changed" if result.ok else ""
	await read_state()
	set_busy(false)
	render_rows()
	render_notice()

func recover() -> void:
	if busy:
		return
	set_busy(true)
	await finish_operation(await invoke("recover"))

func reload_catalog() -> void:
	if busy:
		return
	set_busy(true)
	var error := await catalog.refresh(settings.catalog_url)
	notice_error = ""
	notice_key = "offline" if error != OK else ""
	set_busy(false)
	render_rows()
	render_notice()

func download_mod(mod: Dictionary) -> void:
	if busy:
		return
	set_busy(true)
	var result: Dictionary = await catalog.request_bytes(mod.zip)
	var path := ProjectSettings.globalize_path("user://catalog-mod.zip")
	var file := FileAccess.open(path, FileAccess.WRITE) if result.error == OK else null
	if file != null:
		file.store_buffer(result.body)
		file.close()
	set_busy(false)
	if file != null:
		await inspect_zip(path)
		if not pending_package.is_empty() and (pending_package.id != mod.id or pending_package.version != mod.version):
			install_dialog.hide()
			pending_package = {}
			notice_error = "invalid_metadata"
			render_notice()
	else:
		notice_key = "offline"
		render_notice()
