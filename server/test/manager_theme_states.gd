extends SceneTree

const UiTheme = preload("../../manager/manager_theme.gd")
const ACTIVE_STATES := {
	"font_color":"normal",
	"font_hover_color":"hover",
	"font_pressed_color":"pressed",
	"font_hover_pressed_color":"hover_pressed",
	"font_focus_color":"normal"
}
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	print("MANAGER_THEME_CHECK ", "OK " if condition else "FAIL ", message)
	if not condition:
		failures += 1

func contrast(first: Color, second: Color) -> float:
	var first_luminance := first.srgb_to_linear().get_luminance()
	var second_luminance := second.srgb_to_linear().get_luminance()
	return (maxf(first_luminance, second_luminance) + 0.05) / (minf(first_luminance, second_luminance) + 0.05)

func _initialize() -> void:
	run.call_deferred()

func check_button(button: Button, expected: Color, caption: String) -> void:
	for state in ACTIVE_STATES:
		var foreground := button.get_theme_color(state)
		var background := button.get_theme_stylebox(ACTIVE_STATES[state])
		check(foreground == expected, caption + " uses its text color in " + state)
		check(background is StyleBoxFlat, caption + " uses the light theme background in " + str(ACTIVE_STATES[state]))
		if background is StyleBoxFlat:
			check(contrast(foreground, background.bg_color) >= 4.5, caption + " has readable contrast in " + state)
	check(button.get_theme_color("font_disabled_color") == UiTheme.DISABLED_INK, caption + " retains disabled text color")
	var focus := button.get_theme_stylebox("focus") as StyleBoxFlat
	check(focus != null and focus.bg_color.a == 0.0 and focus.border_color == UiTheme.FOCUS, caption + " keeps the focus outline")

func inspect_theme(theme_script: Script) -> void:
	var theme: Theme = theme_script.create()
	for button: Button in [Button.new(), CheckBox.new(), OptionButton.new()]:
		button.theme = theme
		root.add_child(button)
		button.toggle_mode = true
		button.button_pressed = false
		check_button(button, UiTheme.INK, button.get_class() + " OFF")
		button.button_pressed = true
		check_button(button, UiTheme.INK, button.get_class() + " ON")
		button.free()
	for variant in ["primary", "danger"]:
		var button := Button.new()
		button.theme = theme
		root.add_child(button)
		theme_script.style_button(button, variant)
		check_button(button, UiTheme.SURFACE if variant == "primary" else UiTheme.DANGER, variant)
		button.free()
	var popup := PopupMenu.new()
	popup.theme = theme
	root.add_child(popup)
	for state in ["font_color", "font_hover_color", "font_accelerator_color", "font_separator_color"]:
		var background := popup.get_theme_stylebox("hover" if state == "font_hover_color" else "panel") as StyleBoxFlat
		check(background != null and contrast(popup.get_theme_color(state), background.bg_color) >= 4.5, "PopupMenu readable " + state)
	check(popup.get_theme_color("font_disabled_color") == UiTheme.DISABLED_INK, "PopupMenu retains disabled text color")
	popup.free()

func move_pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame

func click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	await move_pointer(position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func save_view(path: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path) == OK, "saved viewport " + path.get_file())

func draw_states(theme_script: Script, caption: String, output: String) -> Dictionary:
	root.title = "Sobosuba Mod Manager — " + caption
	root.size = Vector2i(1040, 620)
	root.gui_embed_subwindows = true
	root.theme = theme_script.create()
	var panel := PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	var title := Label.new()
	title.text = caption + " — 操作状態の配色"
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	for variant in ["normal", "primary", "danger"]:
		var button := Button.new()
		button.text = {"normal":"通常のボタン", "primary":"ZIPからインストール", "danger":"アンインストール"}[variant]
		theme_script.style_button(button, variant)
		row.add_child(button)
	var checkbox := CheckBox.new()
	checkbox.text = "下の版向けのMODも出す"
	column.add_child(checkbox)
	var disabled := CheckBox.new()
	disabled.text = "操作できないチェックボックス"
	disabled.button_pressed = true
	disabled.disabled = true
	column.add_child(disabled)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(300, 44)
	for text in ["すべて", "有効", "無効", "手動導入"]:
		picker.add_item(text)
	picker.add_separator("区切りの見出し")
	picker.add_item("操作できません")
	picker.set_item_disabled(picker.item_count - 1, true)
	picker.get_popup().set_item_accelerator(1, KEY_MASK_CTRL | KEY_R)
	column.add_child(picker)
	await process_frame
	await process_frame
	await move_pointer(Vector2(950, 560))
	await save_view(output.path_join(caption + "-normal.png"))
	await click(checkbox)
	check(checkbox.button_pressed, caption + " checkbox is checked by input events")
	check(checkbox.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED, caption + " checkbox renders the checked hover state")
	var checkbox_mode := checkbox.get_draw_mode()
	await save_view(output.path_join(caption + "-checkbox-on-hover.png"))
	await click(picker)
	check(picker.get_popup().visible, caption + " option popup opens by input events")
	var picker_mode := picker.get_draw_mode()
	await save_view(output.path_join(caption + "-option-popup-open.png"))
	picker.get_popup().hide()
	panel.free()
	await process_frame
	return {"checkbox_draw_mode":checkbox_mode, "option_draw_mode":picker_mode}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		var before: Script = load(args[0])
		if before == null:
			check(false, "original theme loads")
			quit(1)
			return
		check(DirAccess.make_dir_recursive_absolute(args[1]) == OK, "viewport output directory exists")
		inspect_theme(before)
		var original_failures := failures
		print("MANAGER_THEME_ORIGINAL checks=", checks, " failures=", original_failures)
		failures = 0
		check(original_failures > 0, "original theme exposes the missing state colors")
		var original_states: Dictionary = await draw_states(before, "before", args[1])
		var corrected_states: Dictionary = await draw_states(UiTheme, "after", args[1])
		var report := FileAccess.open(args[1].path_join("draw-states.json"), FileAccess.WRITE)
		check(report != null, "state comparison report can be saved")
		if report != null:
			report.store_string(JSON.stringify({"before":original_states, "after":corrected_states, "original_failures":original_failures}))
			report.close()
	inspect_theme(UiTheme)
	print("MANAGER_THEME_CHECKS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
