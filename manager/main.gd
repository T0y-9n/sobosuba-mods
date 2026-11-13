extends Control

const Store = preload("mod_store.gd")
const Settings = preload("settings.gd")
const SteamFolders = preload("steam_folders.gd")
const Catalog = preload("catalog.gd")
const Words = preload("text.gd")
const Versions = preload("versions.gd")
const SelfUpdate = preload("self_update.gd")
const UiTheme = preload("manager_theme.gd")
var store := Store.new()
var settings := Settings.new()
var words := Words.new()
var catalog := Catalog.new()
var self_update := SelfUpdate.new()
var native_dialog_open := false
var update_timer: Timer
var manager_update_check: CheckBox
var update_status: Label
var restart_button: Button
var mod_update_check: CheckBox
var busy := false
var mods: Array = []
var load_order: Array = []
var target: Dictionary = {}
var bindings: Array = []
var controls: Array[BaseButton] = []
var path_label: Label
var detected_label: Label
var notice: Label
var rows: VBoxContainer
var version_picker: OptionButton
var show_older_mods_check: CheckBox
var language_picker: OptionButton
var folder_dialog: FileDialog
var zip_dialog: FileDialog
var install_dialog: ConfirmationDialog
var operation_dialog: ConfirmationDialog
var adopt_check: CheckBox
var preview_label: Label
var preview_scroll: ScrollContainer
var details: VBoxContainer
var selected_mod_key := ""
var selected_mod: Dictionary = {}
var detail_toggle_button: Button
var library_count: Label
var recovery_button: Button
var search_box: LineEdit
var status_picker: OptionButton
var detail_destination: Label
var detail_actions: HBoxContainer
var notice_scroll: ScrollContainer
const FILTERS := ["all_mods", "enabled", "disabled", "manual"]
var pending_package: Dictionary = {}
var pending_apply: Dictionary = {}
var pending_mode := "install"
var pending_zip := ""
var pending_operation := ""
var pending_mod: Dictionary = {}
var notice_key := ""
var notice_error := ""
var notice_args: Array = []
var notice_mod: Dictionary = {}

func _ready() -> void:
	get_window().min_size = Vector2i(1040, 680)
	get_tree().auto_accept_quit = false
	if "--update-probe" in OS.get_cmdline_user_args():
		add_child(catalog)
		add_child(self_update)
		build_screen()
		await get_tree().process_frame
		var probe := FileAccess.open("user://update-probe.json", FileAccess.WRITE)
		if probe == null:
			get_tree().quit(1)
			return
		probe.store_string(JSON.stringify({"ok":true, "version":SelfUpdate.current_version(), "sha256":FileAccess.get_sha256(OS.get_executable_path())}))
		probe.flush()
		var error := probe.get_error()
		probe.close()
		get_tree().quit(0 if error == OK else 1)
		return
	settings.load_file()
	if not settings.locale.is_empty():
		words.set_locale(settings.locale)
	store.game_folder = settings.game_folder
	store.game_version = settings.game_version
	store.user_data = settings.user_data
	if store.game_folder.is_empty():
		store.game_folder = SteamFolders.find_game()
	busy = true
	await detect_version()
	add_child(catalog)
	add_child(self_update)
	self_update.load_state()
	build_screen()
	get_window().files_dropped.connect(drop_zips)
	busy = false
	await refresh()
	update_timer = Timer.new()
	update_timer.wait_time = 1800.0
	update_timer.timeout.connect(check_updates)
	add_child(update_timer)
	update_timer.start()
	check_updates.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not busy:
		close_manager()

func close_manager(restart: bool = false) -> void:
	if busy or native_dialog_open or install_dialog.visible or operation_dialog.visible:
		return
	set_busy(true)
	if settings.manager_auto_update and not self_update.pending.is_empty():
		if not await self_update.handoff(restart):
			# Allow closing the manager when an update cannot be handed off.
			self_update.blocked_sha = str(self_update.pending.get("sha256", ""))
			self_update.save_state()
	get_tree().quit()

func label(text: String = "", size: int = 16) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", UiTheme.MUTED if size < 16 else UiTheme.INK)
	if size >= 20:
		item.add_theme_font_override("font", UiTheme.font(600))
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

func caption(parent: Node, key: String, size: int = 16) -> Label:
	var item := label(words.word(key), size)
	parent.add_child(item)
	bindings.append({"node": item, "key": key})
	return item

func action(parent: Node, key: String, callback: Callable, variant: String = "secondary") -> Button:
	var item := Button.new()
	item.text = words.word(key)
	item.custom_minimum_size.y = 44
	UiTheme.style_button(item, variant)
	item.pressed.connect(callback)
	item.disabled = busy
	parent.add_child(item)
	bindings.append({"node": item, "key": key})
	controls.append(item)
	return item

func card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	panel.add_child(layout)
	return layout

func build_screen() -> void:
	theme = UiTheme.create()
	get_window().theme = theme
	var background := ColorRect.new()
	background.color = UiTheme.PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SPACE_LG)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(layout)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	layout.add_child(heading)
	caption(heading, "title", 26)
	action(heading, "install_zip", choose_zip, "primary")
	language_picker = OptionButton.new()
	language_picker.custom_minimum_size = Vector2(180, 44)
	for code in Words.LANGUAGES:
		language_picker.add_item(Words.LANGUAGES[code])
		language_picker.set_item_metadata(language_picker.item_count - 1, code)
		language_picker.get_popup().set_item_as_radio_checkable(language_picker.item_count - 1, true)
		if code == words.locale:
			language_picker.select(language_picker.item_count - 1)
	language_picker.item_selected.connect(func(index): change_locale(str(language_picker.get_item_metadata(index))))
	heading.add_child(language_picker)
	controls.append(language_picker)
	caption(layout, "drop_hint", 14)
	var location := card(layout)
	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	location.add_child(path_row)
	var folder_title := caption(path_row, "game_folder", 14)
	folder_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	folder_title.custom_minimum_size.x = 120
	path_label = label(store.game_folder)
	path_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_label.clip_text = true
	path_row.add_child(path_label)
	action(path_row, "choose_location", choose_folder)
	var version_row := HFlowContainer.new()
	version_row.add_theme_constant_override("h_separation", UiTheme.SPACE_MD)
	version_row.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)
	location.add_child(version_row)
	var version_label := caption(version_row, "version", 14)
	version_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	version_label.custom_minimum_size.x = 120
	version_picker = OptionButton.new()
	version_picker.add_item("1.2.3")
	version_picker.add_item("1.3.10")
	version_picker.add_item("1.3.11")
	version_picker.select(["1.2.3", "1.3.10", "1.3.11"].find(store.game_version))
	version_picker.custom_minimum_size = Vector2(132, 44)
	version_picker.item_selected.connect(select_version)
	version_row.add_child(version_picker)
	controls.append(version_picker)
	show_older_mods_check = update_checkbox(version_row, "show_older_mods", false, func(_enabled: bool): render_rows())
	detected_label = label("", 14)
	version_row.add_child(detected_label)
	manager_update_check = update_checkbox(version_row, "manager_auto_update", settings.manager_auto_update, set_manager_updates)
	var workbench := HBoxContainer.new()
	workbench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workbench.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	layout.add_child(workbench)
	var library_panel := VBoxContainer.new()
	library_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_panel.size_flags_stretch_ratio = 1.1
	library_panel.custom_minimum_size.x = 420
	workbench.add_child(library_panel)
	var library_heading := HBoxContainer.new()
	library_heading.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	library_panel.add_child(library_heading)
	caption(library_heading, "library", 20)
	library_count = label("", 14)
	library_count.size_flags_horizontal = Control.SIZE_SHRINK_END
	library_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	library_heading.add_child(library_count)
	action(library_heading, "refresh", refresh)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	library_panel.add_child(filters)
	var search_group := VBoxContainer.new()
	search_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search_group)
	caption(search_group, "search_mods", 14)
	search_box = LineEdit.new()
	search_box.custom_minimum_size.y = 44
	search_box.clear_button_enabled = true
	search_box.text_changed.connect(func(_text): render_rows())
	search_group.add_child(search_box)
	var status_group := VBoxContainer.new()
	filters.add_child(status_group)
	caption(status_group, "status", 14)
	status_picker = OptionButton.new()
	status_picker.custom_minimum_size = Vector2(180, 44)
	status_picker.fit_to_longest_item = false
	status_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for key in FILTERS:
		status_picker.add_item(words.word(key))
	status_picker.item_selected.connect(func(_index): render_rows())
	status_group.add_child(status_picker)
	controls.append(status_picker)
	var library_scroll := ScrollContainer.new()
	library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_panel.add_child(library_scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	library_scroll.add_child(rows)
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 0.9
	detail_panel.custom_minimum_size = Vector2(360, 300)
	workbench.add_child(detail_panel)
	var detail_layout := VBoxContainer.new()
	detail_layout.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	detail_panel.add_child(detail_layout)
	caption(detail_layout, "mod_details", 14)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_layout.add_child(detail_scroll)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	detail_scroll.add_child(details)
	detail_actions = HBoxContainer.new()
	detail_actions.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	detail_layout.add_child(detail_actions)
	var footer := card(layout)
	var result_row := HBoxContainer.new()
	result_row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	footer.add_child(result_row)
	notice_scroll = ScrollContainer.new()
	notice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	notice_scroll.custom_minimum_size.y = 56
	notice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_row.add_child(notice_scroll)
	notice = label("", 14)
	notice_scroll.add_child(notice)
	var tools := VBoxContainer.new()
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result_row.add_child(tools)
	action(tools, "check_updates", reload_catalog)
	update_status = label("", 14)
	tools.add_child(update_status)
	update_status.custom_minimum_size.x = 190
	update_status.visible = false
	restart_button = action(tools, "update_restart", close_manager.bind(true))
	restart_button.visible = false
	recovery_button = action(tools, "recover", recover)
	recovery_button.visible = false
	folder_dialog = FileDialog.new()
	folder_dialog.use_native_dialog = true
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.dir_selected.connect(func(path): native_dialog_open = false; select_folder(path))
	folder_dialog.canceled.connect(func(): native_dialog_open = false)
	add_child(folder_dialog)
	zip_dialog = FileDialog.new()
	zip_dialog.use_native_dialog = true
	zip_dialog.access = FileDialog.ACCESS_FILESYSTEM
	zip_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	zip_dialog.filters = PackedStringArray(["*.zip"])
	zip_dialog.file_selected.connect(func(path): native_dialog_open = false; inspect_zip(path))
	zip_dialog.canceled.connect(func(): native_dialog_open = false)
	add_child(zip_dialog)
	install_dialog = ConfirmationDialog.new()
	install_dialog.get_label().hide()
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 16)
	install_dialog.add_child(preview_box)
	preview_label = label()
	preview_scroll = ScrollContainer.new()
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.custom_minimum_size = Vector2(660, 240)
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(preview_label)
	preview_box.add_child(preview_scroll)
	install_dialog.confirmed.connect(install_selected)
	adopt_check = CheckBox.new()
	adopt_check.custom_minimum_size.y = 52
	preview_box.add_child(adopt_check)
	install_dialog.canceled.connect(func(): pending_package = {}; pending_zip = ""; pending_apply = {})
	add_child(install_dialog)
	operation_dialog = ConfirmationDialog.new()
	operation_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operation_dialog.get_label().custom_minimum_size.x = 660
	operation_dialog.confirmed.connect(run_operation)
	add_child(operation_dialog)
	translate_dialogs()
	translate_filters()
	for dialog in [install_dialog, operation_dialog]:
		UiTheme.style_button(dialog.get_ok_button(), "primary")

func choose_folder() -> void:
	if not busy:
		native_dialog_open = true
		folder_dialog.popup_centered_ratio(0.8)

func choose_zip() -> void:
	if not busy:
		native_dialog_open = true
		zip_dialog.popup_centered_ratio(0.8)

func drop_zips(paths: PackedStringArray) -> void:
	if busy or native_dialog_open or install_dialog.visible or operation_dialog.visible or folder_dialog.visible or zip_dialog.visible:
		return
	if paths.size() != 1 or paths[0].get_extension().to_lower() != "zip":
		notice_error = ""
		notice_key = "drop_one_zip"
		render_notice()
		return
	await inspect_zip(paths[0])

func translate_filters() -> void:
	search_box.placeholder_text = words.word("search_hint")
	search_box.tooltip_text = words.word("search_mods")
	for index in FILTERS.size():
		status_picker.set_item_text(index, words.word(FILTERS[index]))
		status_picker.set_item_tooltip(index, words.word(FILTERS[index]))

func clear_filters() -> void:
	search_box.text = ""
	status_picker.select(0)
	render_rows()
	search_box.grab_focus()

func set_busy(value: bool) -> void:
	busy = value
	controls = controls.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	for item in controls:
		item.disabled = value or bool(item.get_meta("blocked", false))
	search_box.editable = not value
	if value:
		notice.text = words.word("loading")
		notice.add_theme_color_override("font_color", UiTheme.MUTED)

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
	notice_error = ""
	notice_key = ""
	notice_args = []
	notice_mod = {}
	set_busy(true)
	await read_state()
	set_busy(false)
	render_notice()

func read_state() -> void:
	var result: Dictionary = await invoke("list")
	if result.ok:
		mods = result.data.mods
		for mod: Dictionary in mods:
			if not mod.get("manual", false):
				mod.compatible = Versions.supports_game(mod.get("game_versions", []), store.game_version)
		target = result.data.target
		load_order = result.data.get("order", [])
	else:
		mods = []
		load_order = []
		target = {}
		notice_error = str(result.get("error", "invalid_request"))
		notice_args = result.get("args", [])
	render_rows()

func mod_key(mod: Dictionary) -> String:
	return str(mod.id) + "|" + str(mod.get("layout", "catalog"))

func clear_children(parent: Node) -> void:
	for item in parent.get_children():
		parent.remove_child(item)
		item.queue_free()

func status_badge(mod: Dictionary) -> PanelContainer:
	var status := "manual" if mod.get("manual", false) else ("enabled" if mod.get("enabled", false) else "disabled")
	var badge := PanelContainer.new()
	var on := status == "enabled"
	badge.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SUCCESS_SOFT if on else UiTheme.DISABLED, Color.TRANSPARENT, 0, 5, 8))
	var text := label(words.word(status), 13)
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.add_theme_color_override("font_color", UiTheme.SUCCESS if on else UiTheme.MUTED)
	badge.add_child(text)
	return badge

func ignore_pointer(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_pointer(child)

func add_library_row(mod: Dictionary, is_catalog: bool = false) -> void:
	var key := mod_key(mod)
	var layout_blocked := legacy_layout_blocked(mod)
	var button := Button.new()
	button.custom_minimum_size.y = 112
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.set_meta("mod_key", key)
	button.button_pressed = key == selected_mod_key
	button.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DISABLED if layout_blocked else UiTheme.SURFACE))
	button.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.ACCENT_SOFT, UiTheme.ACCENT))
	button.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.ACCENT_SOFT, UiTheme.ACCENT))
	button.pressed.connect(select_mod.bind(key))
	button.tooltip_text = words.word("legacy_layout_incompatible") if layout_blocked else str(mod.name)
	rows.add_child(button)
	controls.append(button)
	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 16
	content.offset_top = 12
	content.offset_right = -16
	content.offset_bottom = -12
	content.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	button.add_child(content)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(text)
	var name_label := label(str(mod.name), 18)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	if layout_blocked:
		name_label.add_theme_color_override("font_color", UiTheme.DISABLED_INK)
	text.add_child(name_label)
	var version_label := label("MOD " + str(mod.get("version", "")), 14)
	var latest := catalog.find(mod.id, store.game_version)
	if not is_catalog and catalog.has_update(mod, store.game_version) and Versions.supports_game(latest.get("game_versions", []), store.game_version):
		version_label.text += " → " + str(latest.version)
	version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	version_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	version_label.clip_text = true
	text.add_child(version_label)
	var game_versions: Array = mod.get("game_versions", [])
	var game_label := label(words.word("supported", [", ".join(game_versions) if not game_versions.is_empty() else "—"]), 14)
	game_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	game_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	game_label.clip_text = true
	text.add_child(game_label)
	if layout_blocked:
		version_label.add_theme_color_override("font_color", UiTheme.DISABLED_INK)
		game_label.add_theme_color_override("font_color", UiTheme.DISABLED_INK)
	else:
		button.tooltip_text = str(mod.name) + "\n" + version_label.text + "\n" + game_label.text
	var warning_text := compatibility_warning(mod)
	if not warning_text.is_empty():
		var warning := label(warning_text, 13)
		warning.name = "CompatibilityWarning"
		warning.add_theme_color_override("font_color", UiTheme.DANGER)
		text.add_child(warning)
	var release_note := author_release_note(mod)
	if not release_note.is_empty():
		var release_warning := label(release_note, 13)
		release_warning.name = "AuthorReleaseStatus"
		release_warning.autowrap_mode = TextServer.AUTOWRAP_OFF
		release_warning.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		release_warning.clip_text = true
		text.add_child(release_warning)
		button.tooltip_text += "\n" + release_note
	text.minimum_size_changed.connect(func(): button.custom_minimum_size.y = maxf(112.0, text.get_combined_minimum_size().y + 24.0))
	button.custom_minimum_size.y = maxf(112.0, text.get_combined_minimum_size().y + 24.0)
	if not is_catalog:
		var badge := status_badge(mod)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(badge)
	ignore_pointer(button)

func select_mod(key: String) -> void:
	if busy:
		return
	for mod in mods + catalog.for_game(store.game_version):
		if mod_key(mod) == key:
			selected_mod_key = key
			selected_mod = mod
	for row in rows.get_children():
		if row is Button:
			row.set_pressed_no_signal(row.get_meta("mod_key", "") == selected_mod_key)
	render_details()

func matches_filters(mod: Dictionary) -> bool:
	if not matches_game_version(mod):
		return false
	var query := search_box.text.strip_edges()
	var searchable := str(mod.name) + " " + str(mod.id) + " " + str(mod.get("version", ""))
	if not query.is_empty() and searchable.findn(query) < 0:
		return false
	var filter: String = FILTERS[status_picker.selected]
	if filter == "all_mods":
		return true
	if filter == "manual":
		return mod.get("manual", false)
	if not mod.has("layout") or mod.get("manual", false):
		return false
	return bool(mod.get("enabled", false)) == (filter == "enabled")

func matches_game_version(mod: Dictionary) -> bool:
	if mod.has("layout"):
		return true
	var declared: Array = mod.get("game_versions", [])
	if declared.has(store.game_version):
		return true
	return show_older_mods_check != null and show_older_mods_check.button_pressed and (legacy_layout_blocked(mod) or Versions.supports_game(declared, store.game_version))

func legacy_layout_blocked(mod: Dictionary) -> bool:
	var declared: Array = mod.get("game_versions", [])
	return store.game_version.begins_with("1.3.") and declared.has("1.2.3") and not Versions.supports_game(declared, store.game_version)

func compatibility_warning(mod: Dictionary) -> String:
	var declared: Array = mod.get("game_versions", [])
	if mod.get("manual", false) or declared.has(store.game_version) or not Versions.supports_game(declared, store.game_version):
		return ""
	return words.word("compatibility_warning", [", ".join(declared), store.game_version])

func render_rows() -> void:
	clear_children(rows)
	path_label.text = store.game_folder if not store.game_folder.is_empty() else words.word("err_target")
	path_label.tooltip_text = path_label.text
	detected_label.text = words.word("detected", [target.detected]) if not str(target.get("detected", "")).is_empty() else words.word("selected")
	library_count.text = words.word("mod_count", [mods.size()])
	var installed: Array = in_load_order(mods).filter(matches_filters)
	var installed_keys: Array = mods.map(mod_key)
	var available: Array = catalog.for_game(store.game_version).filter(func(mod: Dictionary) -> bool: return str(mod.id) + "|" + catalog.entry_layout(mod) not in installed_keys and matches_filters(mod))
	var visible_mods := installed + available
	var keys: Array = visible_mods.map(mod_key)
	if selected_mod_key not in keys:
		selected_mod_key = str(keys[0]) if not keys.is_empty() else ""
	selected_mod = {}
	for mod in installed:
		add_library_row(mod)
		if mod_key(mod) == selected_mod_key:
			selected_mod = mod
	if not available.is_empty():
		caption(rows, "available_mods", 14)
	for mod in available:
		add_library_row(mod, true)
		if mod_key(mod) == selected_mod_key:
			selected_mod = mod
	if visible_mods.is_empty():
		if search_box.text.is_empty() and status_picker.selected == 0:
			caption(rows, "empty", 20)
			caption(rows, "install_hint", 14)
			action(rows, "install_zip", choose_zip)
		else:
			caption(rows, "no_matches", 20)
			action(rows, "clear_filters", clear_filters)
	render_details()
	bindings = bindings.filter(func(item): return is_instance_valid(item.node) and not item.node.is_queued_for_deletion())

func render_details() -> void:
	clear_children(details)
	clear_children(detail_actions)
	detail_toggle_button = null
	detail_destination = null
	if selected_mod.is_empty():
		caption(details, "select_mod", 20)
		caption(details, "install_hint", 14)
		return
	var mod := selected_mod
	details.add_child(label(str(mod.name), 24))
	details.add_child(label("MOD " + str(mod.get("version", "")), 14))
	var notes := mod_notes(mod)
	if not mod.has("layout"):
		if not notes.is_empty():
			details.add_child(label(notes, 14))
		var install := action(detail_actions, "install_zip", download_mod.bind(mod), "primary")
		var blocked := not Versions.supports_game(mod.get("game_versions", []), store.game_version)
		install.set_meta("blocked", blocked)
		install.disabled = busy or blocked
		install.tooltip_text = words.word("legacy_layout_incompatible") if legacy_layout_blocked(mod) else words.word("incompatible") if blocked else ""
		return
	var badge := status_badge(mod)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	details.add_child(badge)
	details.add_child(label(words.word("supported", [", ".join(mod.get("game_versions", [])) if not mod.manual else "—"]), 14))
	if not mod.compatible and not mod.manual:
		var warning := caption(details, "incompatible", 14)
		warning.add_theme_color_override("font_color", UiTheme.DANGER)
	detail_destination = label(words.word("destination", [str(mod.get("root", "—")).replace("\\", "/")]), 14)
	detail_destination.tooltip_text = detail_destination.text
	if mod.manual:
		details.add_child(detail_destination)
		caption(details, "err_adopt", 14)
		action(detail_actions, "install_zip", choose_zip, "primary")
		return
	var latest := catalog.find(mod.id, store.game_version)
	if catalog.has_update(mod, store.game_version) and Versions.supports_game(latest.get("game_versions", []), store.game_version):
		details.add_child(label(words.word("plan_update") + " " + str(latest.version), 14))
		action(details, "plan_update", download_mod.bind(latest), "primary")
	mod_update_check = update_checkbox(details, "mod_auto_update", settings.mod_updates_enabled(mod_key(mod)), set_mod_updates.bind(mod_key(mod)))
	if not notes.is_empty():
		details.add_child(label(notes, 14))
	details.add_child(detail_destination)
	caption(details, "preserve", 14)
	if orders_on_load(mod):
		add_load_order_row(mod)
	detail_toggle_button = action(detail_actions, "disable" if mod.enabled else "enable", toggle_enabled.bind(mod), "secondary" if mod.enabled else "primary")
	var blocked: bool = not mod.enabled and not mod.compatible
	detail_toggle_button.set_meta("blocked", blocked)
	detail_toggle_button.disabled = busy or blocked
	detail_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var remove := action(detail_actions, "uninstall", confirm_operation.bind("uninstall", mod), "danger")
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# The bootstraps add their mods in the saved order; mods not in it follow in the order the game finds them.
func orders_on_load(mod: Dictionary) -> bool:
	return mod.get("layout", "") == "user-data-styles" and not mod.get("manual", false)

func in_load_order(list: Array) -> Array:
	var ranked: Array = []
	for index in list.size():
		var mod: Dictionary = list[index]
		var rank: int = load_order.find(mod.id) if orders_on_load(mod) else -1
		ranked.append([rank if rank >= 0 else load_order.size(), index, mod])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return ranked.map(func(item: Array) -> Dictionary: return item[2])

func load_order_ids() -> Array:
	return in_load_order(mods).filter(orders_on_load).map(func(mod: Dictionary) -> String: return str(mod.id))

func add_load_order_row(mod: Dictionary) -> void:
	var ids := load_order_ids()
	var place := ids.find(str(mod.id))
	details.add_child(label(words.word("load_order", [place + 1, ids.size()]), 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	details.add_child(row)
	for step: int in [-1, 1]:
		var move := action(row, "load_earlier" if step < 0 else "load_later", move_load_order.bind(mod, step))
		move.set_meta("order_step", step)
		move.set_meta("blocked", place + step < 0 or place + step >= ids.size())
		move.disabled = busy or bool(move.get_meta("blocked"))

func move_load_order(mod: Dictionary, step: int) -> void:
	if busy:
		return
	var ids := load_order_ids()
	var place := ids.find(str(mod.id))
	if place < 0 or place + step < 0 or place + step >= ids.size():
		return
	ids[place] = ids[place + step]
	ids[place + step] = str(mod.id)
	set_busy(true)
	var result := await invoke("set_order", {"order": ids})
	notice_key = ""
	notice_error = "" if result.ok else str(result.get("error", "invalid_request"))
	notice_args = [] if result.ok else result.get("args", [])
	await read_state()
	set_busy(false)
	render_notice()

func render_notice() -> void:
	notice.text = words.error_word(notice_error, notice_args) if not notice_error.is_empty() else words.word(notice_key) if not notice_key.is_empty() else words.word("ready")
	var warning := compatibility_warning(notice_mod) if notice_key == "changed" and notice_error.is_empty() else ""
	if not warning.is_empty():
		notice.text += "\n" + warning
	if notice_key in ["changed", "offline"] and notice_mod.get("credit_warning", false):
		notice.text += "\n" + words.word("credit_warning")
		warning = words.word("credit_warning")
	if notice_key in ["changed", "offline"]:
		for change in notice_mod.get("changes", []):
			if change.get("credit_warning", false) and change.get("id") != notice_mod.get("id"):
				warning = words.word("credit_warning")
				notice.text += "\n" + str(change.name) + "\n" + warning
	notice.tooltip_text = notice.text
	notice.add_theme_color_override("font_color", UiTheme.DANGER if not notice_error.is_empty() or not warning.is_empty() else UiTheme.SUCCESS if notice_key == "changed" else UiTheme.MUTED)
	recovery_button.visible = notice_error == "recovery_needed"

func translate_dialogs() -> void:
	folder_dialog.title = words.word("choose_folder")
	zip_dialog.title = words.word("choose_zip")
	for dialog in [install_dialog, operation_dialog]:
		dialog.title = words.word("confirm")
		dialog.ok_button_text = words.word("confirm")
		dialog.cancel_button_text = words.word("cancel")
	adopt_check.text = words.word("adopt")
	if not pending_package.is_empty():
		var question := words.word("enable_question", [pending_package.name]) if pending_mode == "enable" else words.word("install_question", [pending_package.name, pending_package.version])
		var changes := PackedStringArray()
		for change in pending_package.get("changes", []):
			changes.append(str(change.name) + " (" + str(change.version) + ") - " + words.word("plan_" + str(change.action)))
			if change.get("credit_warning", false):
				changes.append(words.word("credit_warning"))
		var summary := words.word("dependency_plan") + "\n" + "\n".join(changes) + "\n\n" if not changes.is_empty() else ""
		preview_label.text = question + "\n\n" + summary + words.word("supported", [", ".join(pending_package.game_versions)]) + "\n" + words.word("destination", [target.get("root", "—")]) + "\n\n" + words.word("preserve") + "\n\n" + mod_notes(pending_package)
	if not pending_mod.is_empty():
		operation_dialog.ok_button_text = words.word("uninstall" if pending_operation == "uninstall" else "disable")
		operation_dialog.dialog_text = words.word("remove_question" if pending_operation == "uninstall" else "disable_question", [pending_mod.name]) + "\n\n" + words.word("preserve")

func mod_notes(mod: Dictionary) -> String:
	var parts := PackedStringArray()
	var credit: Variant = mod.get("game_credit")
	if mod.get("credit_warning", false) or not credit is Dictionary or credit.get("text") != "sobosuba by keepee" or credit.get("store_url") != "https://store.steampowered.com/app/1946560/sobosuba":
		parts.append(words.word("credit_warning"))
	parts.append("sobosuba by keepee\nhttps://store.steampowered.com/app/1946560/sobosuba")
	var release_note := author_release_note(mod)
	if not release_note.is_empty():
		parts.append(release_note)
	if not str(mod.get("author", "")).is_empty():
		parts.append(words.word("author", [mod.author]))
	var description := description_note(mod.get("description", mod.get("summary", "")))
	if not description.is_empty():
		parts.append(description)
	var readme := str(mod.get("readme_text", ""))
	if not readme.is_empty():
		parts.append(readme)
	if mod.get("readme_unavailable", false):
		parts.append(words.word("readme_unavailable"))
	return "\n\n".join(parts)

func author_release_note(mod: Dictionary) -> String:
	if catalog.entry_layout(mod) != catalog.entry_layout({"game_versions":[store.game_version]}):
		return ""
	var status: Dictionary = catalog.release_status(mod.id, store.game_version)
	var error := str(status.get("error", ""))
	var message := ""
	if error == "author_release_unavailable":
		message = words.word(error)
	elif error == "author_release_rejected":
		message = words.word(error, [str(status.get("version", "")), author_release_reason(str(status.get("reason", "metadata")))])
	if status.get("cached", false):
		var checked_at := int(status.get("checked_at", 0))
		var checked := Time.get_datetime_string_from_unix_time(checked_at, true) + " UTC"
		var cached := words.word("author_release_cached", [str(status.get("cached_version", status.get("version", ""))), checked])
		message += (" " if not message.is_empty() else "") + cached
		if not str(status.get("cached_reason", "")).is_empty():
			message += " " + words.word("author_release_rejected", [str(status.get("cached_version", "")), author_release_reason(str(status.cached_reason))])
	if status.get("cache_error", false):
		message += (" " if not message.is_empty() else "") + words.error_word("io_error")
	var warnings: Array = status.get("warnings", mod.get("release_warnings", []))
	if "game_credit" in warnings:
		message += ("\n" if not message.is_empty() else "") + words.word("credit_warning")
	if "readme" in warnings:
		message += ("\n" if not message.is_empty() else "") + words.word("credit_readme_warning")
	return message

func author_release_reason(reason: String) -> String:
	return words.word("author_release_" + (reason if reason in ["game_credit", "readme", "metadata", "sha256", "download", "source", "cache_invalid"] else "metadata"))

func description_note(value: Variant) -> String:
	if value is String:
		return value
	if not value is Dictionary or value.is_empty():
		return ""
	var languages: Array = value.keys()
	languages.sort()
	var language := words.locale
	if not value.has(language):
		language = "en" if value.has("en") else str(languages[0])
		for candidate in languages:
			if str(candidate).get_slice("_", 0) == words.locale.get_slice("_", 0):
				language = str(candidate)
				break
	return words.word("description_language", [Words.LANGUAGES.get(language, language)]) + "\n" + str(value[language])

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
	translate_filters()
	render_rows()
	translate_dialogs()
	render_notice()
	render_update_status()

func save_target() -> void:
	settings.game_folder = store.game_folder
	settings.game_version = store.game_version
	if settings.save() != OK:
		notice_error = "io_error"

func select_folder(path: String) -> void:
	if busy:
		return
	store.game_folder = path
	set_busy(true)
	await detect_version()
	version_picker.select(["1.2.3", "1.3.10", "1.3.11"].find(store.game_version))
	set_busy(false)
	await refresh()
	save_target()
	render_notice()

func detect_version() -> void:
	var result: Dictionary = await invoke("detect")
	if result.ok and not str(result.data.get("detected", "")).is_empty():
		store.game_version = result.data.detected

func select_version(index: int) -> void:
	if busy:
		return
	store.game_version = version_picker.get_item_text(index)
	await refresh()
	save_target()
	render_notice()

func prepare_plan(request: Dictionary, allow_adopt: bool = true) -> Dictionary:
	request = request.duplicate(true)
	request.dependency_zips = request.get("dependency_zips", []).duplicate(true)
	var refreshed := false
	for attempt in 64:
		var check_request := request.duplicate(true)
		check_request.adopt = allow_adopt
		var result := await invoke("resolve", check_request)
		if result.ok:
			request.token = result.data.token
			result.request = request
			return result
		if result.error != "dependency_missing" or result.get("args", []).size() < 2:
			return result
		var id := str(result.args[0])
		var version := str(result.args[1])
		var pin := str(result.args[2]) if result.args.size() > 2 else ""
		var cache := ProjectSettings.globalize_path("user://packages")
		var found := await invoke("find_dependency", {"id":id, "version":version, "sha256":pin, "search_dirs":[settings.mod_folder, cache]})
		if not found.ok:
			return found
		if str(found.data.zip).is_empty():
			var entry := catalog.find(id, store.game_version, version)
			if (entry.is_empty() or entry.version != version) and not refreshed:
				await catalog.refresh(settings.catalog_url)
				refreshed = true
				entry = catalog.find(id, store.game_version, version)
			if entry.is_empty() or entry.version != version:
				return result
			var catalog_pin := str(entry.get("sha256", ""))
			if pin.is_empty():
				pin = catalog_pin
			elif not catalog_pin.is_empty() and pin.to_lower() != catalog_pin.to_lower():
				return download_error({"error":ERR_INVALID_DATA, "failure":"sha256_metadata"}, id, version)
			var downloaded: Dictionary = await catalog.download_verified(entry, pin)
			if downloaded.error != OK:
				return download_error(downloaded, id, version)
			found.data = {"zip":downloaded.zip, "sha256":pin}
		if request.dependency_zips.any(func(item): return item.zip == found.data.zip):
			return result
		found.data.id = id
		request.dependency_zips = request.dependency_zips.filter(func(item): return str(item.get("id", "")) != id)
		request.dependency_zips.append(found.data)
	return {"ok":false, "error":"dependency_limit", "args":[]}

func inspect_zip(path: String) -> void:
	if busy:
		return
	set_busy(true)
	pending_apply = {}
	pending_mode = "install"
	notice_mod = {}
	settings.mod_folder = path.get_base_dir()
	settings.save()
	var result := await invoke("inspect", {"zip": path})
	if result.ok:
		pending_apply = {"zip":path, "sha256":result.data.sha256}
		if not result.data.get("dependencies", []).is_empty():
			result = await prepare_plan(pending_apply)
			if result.ok:
				pending_apply = result.request
	set_busy(false)
	if result.ok:
		notice_error = ""
		notice_key = ""
		pending_package = result.data
		pending_zip = path
		adopt_check.button_pressed = false
		preview_scroll.scroll_vertical = 0
		translate_dialogs()
		install_dialog.popup_centered(Vector2i(720, 300))
	else:
		pending_apply = {}
		notice_error = result.error
		notice_args = result.get("args", [])
	render_notice()

func install_selected() -> void:
	if busy or pending_package.is_empty():
		return
	set_busy(true)
	var request := pending_apply.duplicate(true)
	request.adopt = adopt_check.button_pressed
	var result := await invoke(pending_mode, request)
	if result.ok:
		search_box.text = ""
		status_picker.select(0)
		selected_mod_key = mod_key(pending_package)
	pending_package = {}
	pending_apply = {}
	pending_zip = ""
	await finish_operation(result)

func prepare_enable(mod: Dictionary) -> void:
	set_busy(true)
	var result := await prepare_plan({"id":mod.id, "layout":mod.layout})
	set_busy(false)
	if result.ok:
		pending_mode = "enable"
		pending_package = result.data
		pending_apply = result.request
		adopt_check.button_pressed = false
		preview_scroll.scroll_vertical = 0
		translate_dialogs()
		install_dialog.popup_centered(Vector2i(720, 300))
	else:
		notice_error = result.error
		notice_args = result.get("args", [])
		render_notice()

func toggle_enabled(mod: Dictionary) -> void:
	if busy:
		return
	if mod.enabled:
		confirm_operation("disable", mod)
	elif not mod.get("dependencies", []).is_empty():
		await prepare_enable(mod)
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
	notice_mod = result.get("data", {}) if result.ok else {}
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
	await check_updates()

func check_updates() -> void:
	if busy or native_dialog_open or install_dialog.visible or operation_dialog.visible:
		# Retry a deferred check after one minute without interrupting the current operation.
		if update_timer != null:
			update_timer.start(60.0)
		return
	if update_timer != null:
		update_timer.start(1800.0)
	set_busy(true)
	notice_error = ""
	notice_key = ""
	notice_mod = {}
	var error := await catalog.refresh(settings.catalog_url)
	if error != OK:
		notice_key = "offline"
	await catalog.refresh_latest(store.game_version, invoke)
	await read_state()
	var selected := mods.duplicate(true)
	var update_changes: Array = []
	for mod in selected:
		if mod.manual or not mod.compatible or not settings.mod_updates_enabled(mod_key(mod)) or not catalog.has_update(mod, store.game_version):
			continue
		var latest := catalog.find(mod.id, store.game_version)
		if not Versions.supports_game(latest.get("game_versions", []), store.game_version):
			continue
		var result := await auto_update_mod(mod, latest)
		if not result.ok:
			notice_error = str(result.get("error", "invalid_metadata"))
			notice_args = result.get("args", [])
			if notice_error == "game_running" and update_timer != null:
				update_timer.start(60.0)
			break
		notice_key = "changed"
		notice_mod = result.get("data", {})
		update_changes.append_array(notice_mod.get("changes", []))
		await read_state()
	if not update_changes.is_empty():
		notice_mod.changes = update_changes
	if settings.manager_auto_update:
		if not store.prepare_backend() or not await self_update.check_update(catalog):
			if notice_error.is_empty():
				notice_key = "offline"
	await read_state()
	set_busy(false)
	render_rows()
	render_notice()
	render_update_status()

func auto_update_mod(mod: Dictionary, entry: Dictionary) -> Dictionary:
	if not Versions.newer(str(entry.get("version", "")), str(mod.version)):
		return {"ok":false, "error":"plan_changed"}
	var downloaded: Dictionary = await catalog.download_verified(entry, str(entry.get("sha256", "")))
	if downloaded.error != OK:
		return download_error(downloaded, mod.id, entry.version)
	var request := {"zip":downloaded.zip, "sha256":entry.sha256, "expected_version":mod.version, "expected_source_sha256":mod.get("source_sha256", ""), "adopt":false}
	var result := await invoke("inspect", request)
	if not result.ok:
		return result
	if result.data.id != mod.id or result.data.version != entry.version or result.data.layout != mod.layout:
		return {"ok":false, "error":"invalid_metadata"}
	result = await prepare_plan(request, false)
	if not result.ok:
		return result
	for change in result.data.changes:
		var previous := str(change.get("previous_version", ""))
		if not previous.is_empty() and change.version != previous and not Versions.newer(change.version, previous):
			return {"ok":false, "error":"plan_changed"}
	return await invoke("install", result.request)

func update_checkbox(parent: Node, key: String, pressed: bool, callback: Callable) -> CheckBox:
	var item := CheckBox.new()
	item.text = words.word(key)
	item.button_pressed = pressed
	item.custom_minimum_size.y = 44
	item.toggled.connect(callback)
	parent.add_child(item)
	bindings.append({"node":item, "key":key})
	controls.append(item)
	item.disabled = busy
	return item

func set_mod_updates(enabled: bool, key: String) -> void:
	var old := settings.mod_updates_enabled(key)
	settings.mod_auto_updates[key] = enabled
	if settings.save() != OK:
		settings.mod_auto_updates[key] = old
		mod_update_check.set_pressed_no_signal(old)
		notice_error = "io_error"
		render_notice()

func set_manager_updates(enabled: bool) -> void:
	var old := settings.manager_auto_update
	settings.manager_auto_update = enabled
	if settings.save() != OK:
		settings.manager_auto_update = old
		manager_update_check.set_pressed_no_signal(old)
		notice_error = "io_error"
		render_notice()
	render_update_status()

func render_update_status() -> void:
	var staged := settings.manager_auto_update and not self_update.pending.is_empty()
	update_status.visible = staged
	restart_button.visible = staged
	if staged:
		update_status.text = words.word("manager_update_ready", [self_update.pending.version])

func download_error(result: Dictionary, mod_id: String, mod_version: String) -> Dictionary:
	var details: Array = [mod_id, mod_version]
	var failure := str(result.get("failure", ""))
	match failure:
		"request", "storage":
			details.append(words.word("download_" + failure, [int(result.error)]))
		"connection":
			details.append(words.word("download_connection", [int(result.get("request_result", -1))]))
		"http":
			details.append(words.word("download_http", [int(result.get("http_status", 0))]))
		"sha256", "sha256_invalid", "sha256_metadata":
			details.append(words.word("download_" + failure))
	return {"ok":false, "error":"dependency_download", "args":details}

func download_mod(mod: Dictionary) -> void:
	if busy:
		return
	set_busy(true)
	var path := ""
	var failure: Dictionary = {}
	var pin := str(mod.get("sha256", ""))
	if not pin.is_empty():
		var verified: Dictionary = await catalog.download_verified(mod, pin)
		if verified.error != OK:
			set_busy(false)
			var error := download_error(verified, mod.id, mod.version)
			notice_error = error.error
			notice_args = error.args
			render_notice()
			return
		path = verified.zip
	else:
		var result: Dictionary = await catalog.request_bytes(mod.zip)
		failure = result
		var destination := ProjectSettings.globalize_path("user://catalog-mod.zip")
		var file := FileAccess.open(destination, FileAccess.WRITE) if result.error == OK else null
		if file != null:
			file.store_buffer(result.body)
			file.flush()
			if file.get_error() == OK:
				path = destination
			else:
				failure = {"error":file.get_error(), "failure":"storage"}
			file.close()
		elif result.error == OK:
			failure = {"error":FileAccess.get_open_error(), "failure":"storage"}
	set_busy(false)
	if not path.is_empty():
		await inspect_zip(path)
		if not pending_package.is_empty() and (pending_package.id != mod.id or pending_package.version != mod.version):
			install_dialog.hide()
			pending_package = {}
			pending_apply = {}
			notice_error = "invalid_metadata"
			render_notice()
	else:
		var error := download_error(failure, mod.id, mod.version)
		notice_error = error.error
		notice_args = error.args
		render_notice()
