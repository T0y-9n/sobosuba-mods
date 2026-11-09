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

static func box(fill: Color, border: Color = RULE, width: int = 1, radius: int = 8, padding: int = 12) -> StyleBoxFlat:
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
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, INK)
		result.set_color("font_pressed_color", type, INK)
		result.set_color("font_hover_pressed_color", type, INK)
		result.set_color("font_focus_color", type, INK)
		result.set_color("font_disabled_color", type, DISABLED_INK)
	result.set_stylebox("normal", "Button", box(SURFACE))
	result.set_stylebox("hover", "Button", box(ACCENT_SOFT, ACCENT))
	result.set_stylebox("pressed", "Button", box(ACCENT_SOFT, ACCENT))
	result.set_stylebox("hover_pressed", "Button", box(ACCENT_SOFT, ACCENT))
	result.set_stylebox("disabled", "Button", box(DISABLED))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, FOCUS, 2))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		result.set_stylebox(state, "OptionButton", result.get_stylebox(state, "Button").duplicate())
		result.set_stylebox(state, "CheckBox", result.get_stylebox(state, "Button").duplicate())
	result.set_icon("arrow", "OptionButton", icon('<path d="m5 8 5 5 5-5" fill="none" stroke="#' + INK.to_html(false) + '" stroke-width="2"/>'))
	result.set_constant("arrow_margin", "OptionButton", 12)
	result.set_stylebox("panel", "PanelContainer", box(SURFACE))
	result.set_stylebox("panel", "PopupMenu", box(SURFACE))
	result.set_stylebox("hover", "PopupMenu", box(ACCENT_SOFT, Color.TRANSPARENT, 0, 4))
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_color("font_accelerator_color", "PopupMenu", MUTED)
	result.set_color("font_separator_color", "PopupMenu", MUTED)
	result.set_constant("v_separation", "PopupMenu", 12)
	result.set_stylebox("panel", "AcceptDialog", box(SURFACE, RULE, 1, 10, 16))
	result.set_stylebox("normal", "LineEdit", box(SURFACE))
	result.set_stylebox("read_only", "LineEdit", box(DISABLED))
	result.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, FOCUS, 2))
	result.set_color("caret_color", "LineEdit", INK)
	result.set_color("selection_color", "LineEdit", ACCENT_SOFT)
	result.set_color("font_selected_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("font_uneditable_color", "LineEdit", DISABLED_INK)
	result.set_icon("clear", "LineEdit", icon('<path d="m6 6 8 8m0-8-8 8" fill="none" stroke="#' + MUTED.to_html(false) + '" stroke-width="2"/>'))
	result.set_color("clear_button_color", "LineEdit", MUTED)
	result.set_color("clear_button_color_pressed", "LineEdit", INK)
	var window_border := box(SURFACE, RULE, 1, 8)
	window_border.expand_margin_top = 36
	window_border.expand_margin_left = 2
	window_border.expand_margin_right = 2
	window_border.expand_margin_bottom = 2
	result.set_stylebox("embedded_border", "Window", window_border)
	result.set_color("title_color", "Window", INK)
	result.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	result.set_font("title_font", "Window", font(600))
	result.set_font_size("title_font_size", "Window", 16)
	result.set_icon("close", "Window", result.get_icon("clear", "LineEdit"))
	result.set_icon("close_pressed", "Window", result.get_icon("clear", "LineEdit"))
	var separator := StyleBoxLine.new()
	separator.color = RULE
	separator.thickness = 1
	result.set_stylebox("separator", "HSeparator", separator)
	result.set_icon("unchecked", "CheckBox", icon('<rect x="2" y="2" width="16" height="16" rx="3" fill="#' + SURFACE.to_html(false) + '" stroke="#' + MUTED.to_html(false) + '" stroke-width="1.5"/>'))
	result.set_icon("checked", "CheckBox", icon('<rect x="2" y="2" width="16" height="16" rx="3" fill="#' + ACCENT.to_html(false) + '"/><path d="m5 10 3 3 7-7" fill="none" stroke="#' + SURFACE.to_html(false) + '" stroke-width="2"/>'))
	result.set_icon("checked", "PopupMenu", result.get_icon("checked", "CheckBox"))
	result.set_icon("radio_checked", "PopupMenu", icon('<circle cx="10" cy="10" r="8" fill="#' + SURFACE.to_html(false) + '" stroke="#' + ACCENT.to_html(false) + '" stroke-width="1.5"/><circle cx="10" cy="10" r="4" fill="#' + ACCENT.to_html(false) + '"/>'))
	result.set_icon("radio_unchecked", "PopupMenu", icon('<circle cx="10" cy="10" r="8" fill="#' + SURFACE.to_html(false) + '" stroke="#' + MUTED.to_html(false) + '" stroke-width="1.5"/>'))
	return result

static func style_button(button: Button, variant: String) -> void:
	if variant == "primary":
		button.add_theme_stylebox_override("normal", box(ACCENT, ACCENT))
		button.add_theme_stylebox_override("hover", box(ACCENT_HOVER, ACCENT_HOVER))
		button.add_theme_stylebox_override("pressed", box(ACCENT_HOVER, ACCENT_HOVER))
		button.add_theme_stylebox_override("hover_pressed", box(ACCENT_HOVER, ACCENT_HOVER))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, SURFACE)
	elif variant == "danger":
		button.add_theme_stylebox_override("normal", box(SURFACE, RULE))
		button.add_theme_stylebox_override("hover", box(DANGER_SOFT, DANGER))
		button.add_theme_stylebox_override("pressed", box(DANGER_SOFT, DANGER))
		button.add_theme_stylebox_override("hover_pressed", box(DANGER_SOFT, DANGER))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, DANGER)
