extends Control
## Displays the real reader rows grouped by their read-only mod locations.

const GameDefs = preload("game_defs.gd")
const Readers = preload("readers.gd")
const HubText = preload("hub_text.gd")
const UiTheme = preload("../manager_theme.gd")
const WorkshopTitles = preload("workshop_titles.gd")
const BootTrace = preload("boot_trace.gd")
const COLUMNS := ["col_name", "col_version", "col_origin", "col_enabled", "col_installed", "col_update"]

var rows: Array[Dictionary] = []
var problems: Array[String] = []
var title_source := WorkshopTitles.new()
var _definition: Dictionary = {}
var _words: Dictionary = {}
var _titles: Dictionary = {}
var _content: VBoxContainer
var _groups: Array[Dictionary] = []
var _requested_ids := PackedStringArray()
var _titles_missing := false
var skip_next_show := false
var reading := false
var _reader: Thread
var _closing := false

func setup(definition: Dictionary, words: Dictionary) -> void:
	_definition = definition
	_words = words

func _ready() -> void:
	add_child(title_source)
	title_source.titles_ready.connect(_receive_titles)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTheme.SPACE_LG)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	scroll.add_child(_content)
	if is_visible_in_tree():
		refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		if skip_next_show:
			skip_next_show = false
		else:
			refresh()
	elif what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		for tree: Tree in find_children("Items_*", "Tree", true, false):
			var item := tree.get_root().get_first_child()
			while item != null:
				if item.get_metadata(5) == "update":
					_paint_update(item)
				item = item.get_next()

func refresh() -> void:
	if _content == null or _closing:
		return
	if reading:
		while reading:
			await get_tree().process_frame
		return
	reading = true
	var trace_stage := str(_definition.id) + "/refresh/launch"
	var trace := BootTrace.begin("main", trace_stage)
	_reader = Thread.new()
	if _reader.start(read_definition.bind(_definition.duplicate(true))) != OK:
		reading = false
		push_error("Mod Hub could not start a game reader")
		return
	BootTrace.end("main", trace_stage, trace)
	while _reader.is_alive():
		await get_tree().process_frame
	trace_stage = str(_definition.id) + "/refresh/collect"
	trace = BootTrace.begin("main", trace_stage)
	var groups: Array[Dictionary] = _reader.wait_to_finish()
	_reader = null
	if _closing:
		reading = false
		BootTrace.end("main", trace_stage, trace)
		return
	rows.clear()
	problems.clear()
	_groups = groups
	for group in groups:
		rows.append_array(group.items)
		if not group.problem.is_empty():
			problems.append(group.problem)
	BootTrace.end("main", trace_stage, trace)
	await _render()
	if _closing:
		reading = false
		return
	trace_stage = str(_definition.id) + "/refresh/titles"
	trace = BootTrace.begin("main", trace_stage)
	set_titles(_titles)
	reading = false
	if not _closing:
		_request_titles()
	BootTrace.end("main", trace_stage, trace)

static func read_definition(definition: Dictionary) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var prefix := str(definition.id) + "/read/"
	var trace := BootTrace.begin("worker_library", prefix + "context")
	var context := GameDefs.context(definition)
	BootTrace.end("worker_library", prefix + "context", trace)
	for original in definition.get("places", []):
		var trace_stage := prefix + str(original.id) + "/" + str(original.reader)
		trace = BootTrace.begin("worker_library", trace_stage)
		var place: Dictionary = original.duplicate(true)
		for field in ["path", "user"]:
			if place.has(field):
				place[field] = GameDefs.resolve(str(place[field]), context)
		var result := Readers.read(place, context)
		var items: Array[Dictionary] = []
		for entry in result.items:
			items.append(entry)
		var problem := str(result.get("unreadable", ""))
		groups.append({"place": place, "items": items, "problem": problem})
		BootTrace.end("worker_library", trace_stage, trace)
	return groups

func _exit_tree() -> void:
	var started := Time.get_ticks_msec()
	if _reader != null and _reader.is_started():
		_reader.wait_to_finish()
	if _closing:
		print("Mod Hub close reader_", _definition.id, " ", Time.get_ticks_msec() - started)

func set_titles(titles: Dictionary) -> void:
	var trace_stage := str(_definition.id) + "/set_titles"
	var trace := BootTrace.begin("main", trace_stage)
	_titles = titles
	for entry in rows:
		if titles.has(entry.origin_id):
			entry.name = str(titles[entry.origin_id])
	for group in _groups:
		var tree := find_child("Items_" + str(group.place.id), true, false) as Tree
		if tree == null:
			continue
		var item := tree.get_root().get_first_child()
		for entry in group.items:
			item.set_text(0, str(entry.name))
			item.set_tooltip_text(0, str(entry.name))
			item = item.get_next()
	BootTrace.end("main", trace_stage, trace)

func _request_titles() -> void:
	var trace_stage := str(_definition.id) + "/request_titles/ids"
	var trace := BootTrace.begin("main", trace_stage)
	var ids := PackedStringArray()
	for entry in rows:
		if entry.origin == "workshop" and not entry.origin_id.is_empty() and not entry.origin_id in ids:
			ids.append(entry.origin_id)
	BootTrace.end("main", trace_stage, trace)
	if ids.is_empty() or ids == _requested_ids:
		return
	_requested_ids = ids
	title_source.request(int(_definition.steam_appid), ids)

func _receive_titles(appid: int, titles: Dictionary, complete: bool) -> void:
	if _closing:
		return
	if appid != int(_definition.steam_appid):
		return
	_titles.merge(titles, true)
	_titles_missing = not complete and not _titles.has_all(Array(_requested_ids))
	if reading:
		return
	set_titles(_titles)
	var problem := _content.get_node_or_null("TitlesProblem")
	if _titles_missing and problem == null:
		_add_titles_problem()
	elif not _titles_missing and problem != null:
		problem.free()

func _add_titles_problem() -> void:
	var problem := _label(HubText.text(_words, "titles_missing"))
	problem.name = "TitlesProblem"
	_content.add_child(problem)

func _render() -> void:
	var trace_stage := str(_definition.id) + "/render/header"
	var trace := BootTrace.begin("main", trace_stage)
	for child in _content.get_children():
		child.free()
	var heading := _label(str(_definition.get("name", "")))
	heading.add_theme_font_override("font", UiTheme.font(600))
	heading.add_theme_font_size_override("font_size", 24)
	_content.add_child(heading)
	var folder := _label(str(_definition.get("app", {}).get("folder", "")))
	folder.theme_type_variation = "MutedLabel"
	_content.add_child(folder)
	BootTrace.end("main", trace_stage, trace)
	for group in _groups:
		if _closing:
			return
		await _render_place(group)
		if _closing:
			return
	if _titles_missing:
		_add_titles_problem()

func _render_place(group: Dictionary) -> void:
	var trace_stage := str(_definition.id) + "/render/" + str(group.place.id) + "/header"
	var trace := BootTrace.begin("main", trace_stage)
	var section := VBoxContainer.new()
	section.name = "Place_" + str(group.place.id)
	section.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	_content.add_child(section)
	var enabled := 0
	var known := false
	for entry in group.items:
		if entry.enabled is bool:
			known = true
			if entry.enabled:
				enabled += 1
	var count := HubText.text(_words, "count") % group.items.size()
	if known:
		count = HubText.text(_words, "count_on") % [group.items.size(), enabled]
	var title := _label(HubText.text(_words, "place_" + str(group.place.reader)) + "  " + count)
	title.add_theme_font_override("font", UiTheme.font(600))
	section.add_child(title)
	if not group.problem.is_empty():
		section.add_child(_label(HubText.text(_words, "unreadable") % group.problem))
	elif group.items.is_empty():
		section.add_child(_label(HubText.text(_words, "empty_place")))
	else:
		section.size_flags_vertical = Control.SIZE_EXPAND_FILL
		BootTrace.end("main", trace_stage, trace)
		await _tree(group, section)
		return
	BootTrace.end("main", trace_stage, trace)

func _tree(group: Dictionary, section: Control) -> void:
	var trace_prefix := str(_definition.id) + "/tree/" + str(group.place.id)
	var trace := BootTrace.begin("main", trace_prefix + "/setup")
	var tree := Tree.new()
	tree.name = "Items_" + str(group.place.id)
	tree.set_meta("place", group.place.id)
	tree.columns = COLUMNS.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 40 + mini(group.items.size(), 3) * 30
	section.add_child(tree)
	for column in range(COLUMNS.size()):
		tree.set_column_title(column, HubText.text(_words, COLUMNS[column]))
		tree.set_column_custom_minimum_width(column, 220 if column == 0 else 100)
		tree.set_column_expand(column, column == 0)
	var root := tree.create_item()
	var count := 0
	var update_font := UiTheme.font(600)
	BootTrace.end("main", trace_prefix + "/setup", trace)
	var chunk := 0
	trace = BootTrace.begin("main", trace_prefix + "/items/" + str(chunk))
	for entry in group.items:
		var item := tree.create_item(root)
		item.set_metadata(0, entry.key)
		var values := [str(entry.name), _value(entry.version), _value(entry.origin, "origin_"),
			_state(entry.enabled), _date(entry.installed_at), _update(entry.update)]
		for column in range(values.size()):
			item.set_text(column, values[column])
			item.set_tooltip_text(column, values[column])
		if entry.update == true:
			item.set_metadata(5, "update")
			_paint_update(item)
			item.set_custom_font(5, update_font)
		count += 1
		if count % 32 == 0:
			BootTrace.end("main", trace_prefix + "/items/" + str(chunk), trace)
			await get_tree().process_frame
			if _closing:
				return
			chunk += 1
			trace = BootTrace.begin("main", trace_prefix + "/items/" + str(chunk))
	BootTrace.end("main", trace_prefix + "/items/" + str(chunk), trace)

func _paint_update(item: TreeItem) -> void:
	item.set_custom_color(5, UiTheme.tone("on_accent"))
	item.set_custom_bg_color(5, UiTheme.tone("accent"))

func _value(value: Variant, prefix: String = "") -> String:
	if value == null:
		return HubText.text(_words, "unknown")
	return str(value) if prefix.is_empty() else HubText.text(_words, prefix + str(value))

func _state(value: Variant) -> String:
	if not value is bool:
		return HubText.text(_words, "unknown")
	return HubText.text(_words, "enabled_on" if value else "enabled_off")

func _update(value: Variant) -> String:
	if not value is bool:
		return HubText.text(_words, "unknown")
	return HubText.text(_words, "update_available" if value else "update_none")

func _date(value: Variant) -> String:
	if value == null:
		return HubText.text(_words, "unknown")
	var local_time := int(value) + int(Time.get_time_zone_from_system().bias) * 60
	return Time.get_date_string_from_unix_time(local_time)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
