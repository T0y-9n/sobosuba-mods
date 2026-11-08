extends "res://ui/menu/screens/game_settings_screen/game_settings_screen.gd"

var previous_title_width := 0.0
var previous_side_title_width := 0.0
var left_panel: LeftSidePanel


func _ready() -> void:
	for panel: SidePanel in Ui._0.side_panels:
		if panel is LeftSidePanel:
			left_panel = panel
	resized.connect(fit_title_width, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(fit_title_width, CONNECT_DEFERRED)


func open() -> void:
	previous_title_width = (Ui._0.mobile_top_panel as MobileTopPanel).title_label.max_width
	previous_side_title_width = left_panel.side_title.max_width
	super()
	fit_title_width()


func close() -> void:
	super()
	(Ui._0.mobile_top_panel as MobileTopPanel).title_label.max_width = previous_title_width
	left_panel.side_title.max_width = previous_side_title_width


func fit_title_width() -> void:
	if not is_visible_in_tree():
		return
	var panel := Ui._0.mobile_top_panel as MobileTopPanel
	panel.title_label.max_width = maxf(1.0, panel.size.x - 32.0) / top_title_scale if Ui._0.vertical_layout else previous_title_width
	left_panel.side_title.max_width = maxf(1.0, left_panel.size.y - 32.0) if not Ui._0.vertical_layout else previous_side_title_width


func refresh_controls() -> void:
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	if mod != null:
		mod.refresh_toggle()
	fit_title_width()
