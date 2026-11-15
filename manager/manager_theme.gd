# Hallmark · macrostructure: Split Studio · tone: utilitarian · theme: Cobalt
# Native Godot tokens. Pre-emit critique: P4 H5 E4 S5 R5 V4.
extends RefCounted

const PAPER := Color("f2f5fa")
const SURFACE := Color("ffffff")
const INK := Color("172c46")
const MUTED := Color("52647b")
const RULE := Color("cbd5e2")
const ACCENT := Color("2458ba")
const ACCENT_HOVER := Color("1b4698")
const ACCENT_SOFT := Color("eaf0fc")
const FOCUS := Color("275ed0")
const DISABLED := Color("e9edf3")
const DISABLED_INK := Color("69788c")
const SUCCESS := Color("176047")
const SUCCESS_SOFT := Color("e5f3ec")
const DANGER := Color("a42f43")
const DANGER_SOFT := Color("fbedf0")
const BODY_FONTS := ["Segoe UI", "Yu Gothic UI", "Microsoft YaHei UI", "Microsoft JhengHei UI", "Malgun Gothic"]
const SPACE_SM := 8
const SPACE_MD := 16
const SPACE_LG := 24


static var shown := "light"

static func resolve_appearance(choice: String, os_dark: bool) -> String:
	if choice == "dark":
		return "dark"
	if choice == "light":
		return "light"
	if choice == "system":
		return "dark" if os_dark else "light"
	return "light"

static func colors(name: String) -> Dictionary:
	if name == "dark":
		return {
			"paper": Color("0e1726"),
			"surface": Color("17263a"),
			"ink": Color("e7eef8"),
			"muted": Color("a9b8cc"),
			"rule": Color("314864"),
			"accent": Color("2458ba"),
			"accent_hover": Color("1b4698"),
			"accent_soft": Color("1a3054"),
			"focus": Color("8eb6ff"),
			"disabled": Color("121c2e"),
			"disabled_ink": Color("93a6be"),
			"success": Color("8fd0aa"),
			"success_soft": Color("163528"),
			"danger": Color("ffb3c0"),
			"danger_soft": Color("3f2430"),
			"on_accent": Color("e7eef8"),
		}
	return {
		"paper": PAPER,
		"surface": SURFACE,
		"ink": INK,
		"muted": MUTED,
		"rule": RULE,
		"accent": ACCENT,
		"accent_hover": ACCENT_HOVER,
		"accent_soft": ACCENT_SOFT,
		"focus": FOCUS,
		"disabled": DISABLED,
		"disabled_ink": DISABLED_INK,
		"success": SUCCESS,
		"success_soft": SUCCESS_SOFT,
		"danger": DANGER,
		"danger_soft": DANGER_SOFT,
		"on_accent": SURFACE,
	}

static func apply(choice: String, os_dark: bool) -> void:
	shown = resolve_appearance(choice, os_dark)

static func tone(key: String) -> Color:
	return colors(shown)[key]


static func box(fill: Color, border: Color = RULE, width: int = 1, radius: int = 8, padding: int = 12) -> StyleBoxFlat:
	if border == RULE:
		border = tone("rule")
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func icon(body: String) -> ImageTexture:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">' + body + '</svg>')
	return ImageTexture.create_from_image(image)

static func font(weight: int = 400) -> SystemFont:
	var face := SystemFont.new()
	face.font_names = PackedStringArray(BODY_FONTS)
	face.font_weight = weight
	return face

static func create() -> Theme:
	var result := Theme.new()
	result.default_font = font()
	result.default_font_size = 16
	for type in ["Label", "Button", "OptionButton", "CheckBox", "PopupMenu", "LineEdit"]:
		result.set_color("font_color", type, tone("ink"))
		result.set_color("font_hover_color", type, tone("ink"))
		result.set_color("font_pressed_color", type, tone("ink"))
		result.set_color("font_hover_pressed_color", type, tone("ink"))
		result.set_color("font_focus_color", type, tone("ink"))
		result.set_color("font_disabled_color", type, tone("disabled_ink"))
	result.set_stylebox("normal", "Button", box(tone("surface")))
	result.set_stylebox("hover", "Button", box(tone("accent_soft"), tone("accent")))
	result.set_stylebox("pressed", "Button", box(tone("accent_soft"), tone("accent")))
	result.set_stylebox("hover_pressed", "Button", box(tone("accent_soft"), tone("accent")))
	result.set_stylebox("disabled", "Button", box(tone("disabled")))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, tone("focus"), 2))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		result.set_stylebox(state, "OptionButton", result.get_stylebox(state, "Button").duplicate())
		result.set_stylebox(state, "CheckBox", result.get_stylebox(state, "Button").duplicate())
	result.set_icon("arrow", "OptionButton", icon('<path d="m5 8 5 5 5-5" fill="none" stroke="#' + tone("ink").to_html(false) + '" stroke-width="2"/>'))
	result.set_constant("arrow_margin", "OptionButton", 12)
	result.set_stylebox("panel", "PanelContainer", box(tone("surface")))
	result.set_stylebox("panel", "PopupMenu", box(tone("surface")))
	result.set_stylebox("hover", "PopupMenu", box(tone("accent_soft"), Color.TRANSPARENT, 0, 4))
	result.set_color("font_hover_color", "PopupMenu", tone("ink"))
	result.set_color("font_accelerator_color", "PopupMenu", tone("muted"))
	result.set_color("font_separator_color", "PopupMenu", tone("muted"))
	result.set_constant("v_separation", "PopupMenu", 12)
	result.set_stylebox("panel", "AcceptDialog", box(tone("surface"), tone("rule"), 1, 10, 16))
	result.set_stylebox("normal", "LineEdit", box(tone("surface")))
	result.set_stylebox("read_only", "LineEdit", box(tone("disabled")))
	result.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, tone("focus"), 2))
	result.set_color("caret_color", "LineEdit", tone("ink"))
	result.set_color("selection_color", "LineEdit", tone("accent_soft"))
	result.set_color("font_selected_color", "LineEdit", tone("ink"))
	result.set_color("font_placeholder_color", "LineEdit", tone("muted"))
	result.set_color("font_uneditable_color", "LineEdit", tone("disabled_ink"))
	result.set_icon("clear", "LineEdit", icon('<path d="m6 6 8 8m0-8-8 8" fill="none" stroke="#' + tone("muted").to_html(false) + '" stroke-width="2"/>'))
	result.set_color("clear_button_color", "LineEdit", tone("muted"))
	result.set_color("clear_button_color_pressed", "LineEdit", tone("ink"))
	var window_border := box(tone("surface"), tone("rule"), 1, 8)
	window_border.expand_margin_top = 36
	window_border.expand_margin_left = 2
	window_border.expand_margin_right = 2
	window_border.expand_margin_bottom = 2
	result.set_stylebox("embedded_border", "Window", window_border)
	result.set_color("title_color", "Window", tone("ink"))
	result.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	result.set_font("title_font", "Window", font(600))
	result.set_font_size("title_font_size", "Window", 16)
	result.set_icon("close", "Window", result.get_icon("clear", "LineEdit"))
	result.set_icon("close_pressed", "Window", result.get_icon("clear", "LineEdit"))
	var separator := StyleBoxLine.new()
	separator.color = tone("rule")
	separator.thickness = 1
	result.set_stylebox("separator", "HSeparator", separator)
	result.set_icon("unchecked", "CheckBox", icon('<rect x="2" y="2" width="16" height="16" rx="3" fill="#' + tone("surface").to_html(false) + '" stroke="#' + tone("muted").to_html(false) + '" stroke-width="1.5"/>'))
	result.set_icon("checked", "CheckBox", icon('<rect x="2" y="2" width="16" height="16" rx="3" fill="#' + tone("accent").to_html(false) + '"/><path d="m5 10 3 3 7-7" fill="none" stroke="#' + tone("on_accent").to_html(false) + '" stroke-width="2"/>'))
	result.set_icon("checked", "PopupMenu", result.get_icon("checked", "CheckBox"))
	result.set_icon("radio_checked", "PopupMenu", icon('<circle cx="10" cy="10" r="8" fill="#' + tone("surface").to_html(false) + '" stroke="#' + tone("accent").to_html(false) + '" stroke-width="1.5"/><circle cx="10" cy="10" r="4" fill="#' + tone("accent").to_html(false) + '"/>'))
	result.set_icon("radio_unchecked", "PopupMenu", icon('<circle cx="10" cy="10" r="8" fill="#' + tone("surface").to_html(false) + '" stroke="#' + tone("muted").to_html(false) + '" stroke-width="1.5"/>'))
	return result

static func style_button(button: Button, variant: String) -> void:
	button.set_meta("variant", variant)
	if variant == "primary":
		button.add_theme_stylebox_override("normal", box(tone("accent"), tone("accent")))
		button.add_theme_stylebox_override("hover", box(tone("accent_hover"), tone("accent_hover")))
		button.add_theme_stylebox_override("pressed", box(tone("accent_hover"), tone("accent_hover")))
		button.add_theme_stylebox_override("hover_pressed", box(tone("accent_hover"), tone("accent_hover")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, tone("on_accent"))
	elif variant == "danger":
		button.add_theme_stylebox_override("normal", box(tone("surface"), tone("rule")))
		button.add_theme_stylebox_override("hover", box(tone("danger_soft"), tone("danger")))
		button.add_theme_stylebox_override("pressed", box(tone("danger_soft"), tone("danger")))
		button.add_theme_stylebox_override("hover_pressed", box(tone("danger_soft"), tone("danger")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, tone("danger"))
