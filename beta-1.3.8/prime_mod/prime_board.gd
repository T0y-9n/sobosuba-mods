extends PanelContainer
## Score-board presentation shared by the game and standalone Godot checks.
const FRIEND_ROWS:= 2
var label: Label


func _init() -> void:
	var box:= StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.78)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(8)
	add_theme_stylebox_override("panel", box)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(0, 16)
	custom_minimum_size = Vector2(720, 0)
	label = Label.new()
	label.name = "Scores"
	var font:= SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "MS Gothic", "Noto Sans CJK JP"])
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(label)
	visible = false


func _ready() -> void:
	get_viewport().size_changed.connect(fit_content)
	label.minimum_size_changed.connect(fit_content)
	fit_content()


func fit_content() -> void:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var width: float = minf(720.0, maxf(1.0, viewport.size.x - 32.0))
	custom_minimum_size.x = width
	size = Vector2(width, get_combined_minimum_size().y)
	# Control.position is parent-relative, not an offset from its anchor.
	position = viewport.position + Vector2((viewport.size.x - width) / 2.0, 16.0)


func inside_viewport() -> bool:
	return get_viewport().get_visible_rect().encloses(get_global_rect())


func display_name(value: String) -> String:
	var controls:= RegEx.new()
	controls.compile("[\\p{Cc}\\p{Cf}\\p{Cs}\\p{Zl}\\p{Zp}]")
	return controls.sub(value, "", true).strip_edges().substr(0, 24).strip_edges()


## One local line + at most one friend line + at most four world lines = six.
## The transport owns the world section's three-entry limit; no content is hidden vertically.
func board_text(score: int, rank: int, best: int, friends: Dictionary, world_enabled: bool, world_text: String) -> String:
	var rows: Array = []
	for k: String in friends:
		rows.append({"name": str(friends[k].name), "best": int(friends[k].best)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.best > b.best)
	var lines: PackedStringArray = []
	lines.append(word("board line") % [score, best, (word("local rank") % rank) if rank > 0 else word("unranked")])
	if not rows.is_empty():
		var top:= PackedStringArray()
		for i: int in mini(rows.size(), FRIEND_ROWS):
			top.append("%d. %s %d" % [i + 1, display_name(rows[i].name), rows[i].best])
		lines.append(word("friends") + ": " + " / ".join(top))
	if world_enabled:
		lines.append(world_text if not world_text.is_empty() else word("world loading"))
	return "\n".join(lines)


## The mod's words in the game's language (prime_text.gd next to this script).
func word(key: String) -> String:
	return load((get_script() as Script).resource_path.get_base_dir().path_join("prime_text.gd")).get_text(key)

