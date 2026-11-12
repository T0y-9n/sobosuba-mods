extends Node2D

var sobo: Sobo
var kind:= ""
var tuning: Script


func _process(_delta: float) -> void:
	global_rotation = Cam._0.rotation if Cam._0 != null else 0.0
	if is_instance_valid(sobo):
		position = sobo.get_label_position()
	queue_redraw()


func marker_color() -> Color:
	return marker_color_for(StyleManager.current_sobo_palette.color_for_size(sobo.data.size)).lerp(Color.WHITE, sobo.flashing)


func number_color_for(fill: Color) -> Color:
	var text:= Color(0.0, 0.0, 0.0, 0.4)
	var label: Variant = sobo.get("sobo_label") if is_instance_valid(sobo) else null
	if label is Label and is_instance_valid(label):
		text = label.get_theme_color("font_color") * label.modulate * label.self_modulate
	return fill.lerp(Color(text.r, text.g, text.b, fill.a), clampf(text.a, 0.0, 1.0))


func marker_color_for(fill: Color) -> Color:
	var number: Color = number_color_for(fill)
	if absf(fill.get_luminance() - number.get_luminance()) < 0.02:
		return fill.lerp(Color(1.0, 1.0, 1.0, fill.a), tuning.MARKER_NUMBER_MIX * 0.5)
	return fill.lerp(number, tuning.MARKER_NUMBER_MIX)


func _draw() -> void:
	var radius: float = sobo.data.outer_circle.radius
	var offset: Vector2 = Vector2.UP * radius * tuning.MARKER_OFFSET
	var size: float = radius * tuning.MARKER_SIZE
	var color: Color = marker_color()
	if kind == "small":
		draw_circle(offset, size * 0.5, color)
	elif kind == "puffy":
		draw_circle(offset + Vector2(-size * 0.25, size * 0.12), size * 0.25, color)
		draw_circle(offset + Vector2(size * 0.25, size * 0.12), size * 0.25, color)
		draw_circle(offset + Vector2(0.0, -size * 0.15), size * 0.3, color)
	elif kind == "magnet":
		var width: float = size * 0.16
		var curve: float = size * 0.3
		draw_line(offset + Vector2(-curve, -curve), offset + Vector2(-curve, 0.0), color, width, true)
		draw_line(offset + Vector2(curve, -curve), offset + Vector2(curve, 0.0), color, width, true)
		draw_arc(offset, curve, 0.0, PI, 12, color, width, true)
		draw_circle(offset + Vector2(-curve, -curve), width * 0.5, color)
		draw_circle(offset + Vector2(curve, -curve), width * 0.5, color)
	elif kind == "sticky":
		for ray: int in 6:
			var direction:= Vector2.RIGHT.rotated(TAU * float(ray) / 6.0)
			draw_line(offset, offset + direction * size * 0.5, color, size * 0.16, true)

	else:
		var mod: Node = get_node_or_null("/root/SpecialSobo")
		if mod != null and is_instance_valid(mod.extra_effects):
			mod.extra_effects.draw_marker(self, sobo, kind, offset, size, color)
