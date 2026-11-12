extends Node

const Parameters = preload("special_effect_parameters.gd")

const WORDS: Dictionary = {
	"trait liquid": {"en":"liquid sobos", "ja":"液体のソボ"},
	"description liquid": {"en":"Soft, heavy sobos that spread and settle in the stack.", "ja":"盤面で柔らかく重くなり、広がって沈むソボ"},
	"trait washer": {"en":"tornado sobos", "ja":"トルネードソボ"},
	"description washer": {"en":"Stirs the sobos around it. A larger number reaches farther and pushes harder. At 64 it covers the whole board, and a larger number stays at that reach.", "ja":"周りのソボをかき混ぜる。数が大きいほど遠く、強く押す。64 で盤面の全体に届き、それより大きくても同じ届き。"},
	"trait darkmatter": {"en":"dark matter sobos", "ja":"ダークマターソボ"},
	"description darkmatter": {"en":"Black, with no number and no mark. Its size is random, from the smallest sobo this match can spawn up to the largest one on the board. It keeps its real number, and merges only with that number. Merging with an ordinary sobo stays dark matter and draws a new size. Two of the same number become an ordinary sobo.", "ja":"真っ黒で、数字も印も出ない。大きさはランダムで、その試合に出る一番小さいソボから盤面の一番大きいソボまで。本当の数字を内側に持ち、その数字とだけ合体する。普通のソボと合体するとダークマターのまま大きさを引き直す。同じ数字どうしは普通のソボに戻る。"},
	"extra sobos": {"en":"extra sobos", "ja":"追加ソボ"},
}

const KINDS: Array[String] = ["washer", "liquid", "darkmatter"]
const STATE_META := "special_extra_state"
const SHAPE_META := "special_extra_shape_size"

const LIQUID_META := "special_sobo_liquid_slack"

var liquid_data: Dictionary = {}
var mod: Node


func _init() -> void:
	name = "ExtraSobos"


func _ready() -> void:
	mod = get_parent()
	if mod == null or not mod.has_method("register_extra_effects"):
		return
	if not mod.is_node_ready():
		await mod.ready
	mod.register_extra_effects(self)


func number(key: String) -> float:
	return mod.settings.number(key)


func apply_tuning(key: String = "") -> void:
	if key.is_empty() or key in ["liquid_slack", "liquid_area_hold"]:
		liquid_data.clear()
		for sobo: Sobo in SoboManager.all_sobos.duplicate():
			if is_instance_valid(sobo) and not sobo.is_queued_for_deletion() and mod.trait_of(sobo) == "liquid" and sobo.has_meta(LIQUID_META):
				reshape_liquid(sobo)


func state(sobo: Sobo) -> Dictionary:
	if not sobo.has_meta(STATE_META):
		sobo.set_meta(STATE_META, {"elapsed":0.0})
	return sobo.get_meta(STATE_META)


func capture(sobo: Sobo) -> Dictionary:
	var result: Dictionary = {}
	var data: Variant = sobo.get_meta(STATE_META, null)
	if data is Dictionary:
		result["state"] = data.duplicate(true)
	if sobo.has_meta(SHAPE_META):
		result["shape_size"] = sobo.get_meta(SHAPE_META)
	return result


func finite_number(value: Variant, maximum: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), 0.0, maximum)
	return 0.0


func restore(sobo: Sobo, saved: Variant) -> void:
	if not saved is Dictionary:
		return
	var data: Variant = saved.get("state")
	if data is Dictionary:
		sobo.set_meta(STATE_META, {"elapsed":finite_number(data.get("elapsed"), 90.0)})
	var shape: Variant = saved.get("shape_size")
	if shape is int and shape in SoboManager.power_of_two_sizes:
		sobo.set_meta(SHAPE_META, shape)


func eligible(sobo: Variant, mode: SceneClassic) -> bool:
	return (is_instance_valid(sobo) and not sobo.is_queued_for_deletion()
		and mode.sobos_in_stack.has(sobo) and not sobo.frozen
		and not sobo.merged_this_frame and mod.at_rest(sobo))


func tick(mode: SceneClassic, delta: float, gravity: float) -> void:
	if not mod.run_special or GameModeManager.current_scene != mode or not is_finite(delta) or delta <= 0.0:
		return
	settle_liquids(mode)
	var stack: Array[Sobo] = mod.live_stack(mode)
	for sobo: Sobo in stack:
		if mod.trait_of(sobo) == "liquid":
			sobo.apply_uniform_acceleration(liquid_acceleration(mode, sobo, down_direction(), gravity))
	for owner: Sobo in stack:
		if mod.trait_of(owner) != "washer" or not eligible(owner, mode):
			continue
		var data := state(owner)
		data.elapsed += delta
		if data.elapsed >= number("extra_delay"):
			wash(owner, mode, gravity)


func nearby(owner: Sobo, mode: SceneClassic, reach: float) -> Array[Sobo]:
	var targets: Array[Sobo] = []
	for target: Sobo in mod.live_stack(mode):
		if target != owner and eligible(target, mode):
			targets.append(target)
	return SoboManager.get_closest_sobos_center(owner.center, int(number("extra_max_targets")), reach, targets)


func down_direction() -> Vector2:
	var direction: Vector2 = PhysicsServer2D.area_get_param(get_viewport().world_2d.space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR)
	return direction.normalized()


func wash(owner: Sobo, mode: SceneClassic, gravity: float) -> void:
	var direction := 1.0 if owner.replay_id % 2 == 0 else -1.0
	var owner_radius: float = Parameters.washer_owner_radius(owner.data.size)
	var reach: float = Parameters.washer_reach(owner_radius, number("washer_range"), Parameters.reference_radius(64))
	for target: Sobo in nearby(owner, mode, reach):
		var radial: Vector2 = (target.center - owner.center).normalized()
		var tangent: Vector2 = radial.orthogonal() * direction
		var speed: float = target.get_avg_velocity().dot(tangent)
		var scale: float = Parameters.washer_push(gravity, number("washer_strength"), speed, number("washer_speed"), owner.data.size)
		target.apply_uniform_acceleration(tangent * scale)
		target.apply_uniform_acceleration(-radial * gravity * number("washer_strength") * Parameters.washer_size_scale(owner.data.size) * 0.15)


func set_value(sobo: Sobo, value: int) -> void:
	if not sobo.has_meta(SHAPE_META):
		sobo.set_meta(SHAPE_META, physical_size(sobo))
	var data := SoboManager.SoboData.new()
	for prop: Dictionary in sobo.data.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data.set(prop.name, sobo.data.get(prop.name))
	data.size = value
	sobo.data = data
	var slack: float = float(sobo.get_meta(LIQUID_META, 1.0))
	sobo.setup_core(sobo.subas, sobo.extra_mass_ball, data.inner_circle.area, data.inner_circle.radius, SoboManager.dist_between_subas * slack, value)
	sobo.read_body_states()
	sobo.update_polygon_points()
	sobo.sobo_label.text = str(value)
	sobo.apply_style()


func physical_size(sobo: Sobo) -> int:
	for size: int in SoboManager.power_of_two_sizes:
		var original: SoboManager.SoboData = SoboManager.get_sobo_data(size)
		if sobo.subas.size() == original.suba_count and is_equal_approx(sobo.data.outer_circle.radius, original.outer_circle.radius):
			return size
	return sobo.data.size


func prepare_saved_shape(sobo: Sobo, saved: SoboState) -> void:
	var extra: Variant = saved.get_meta("special_extra", {})
	if extra is not Dictionary:
		return
	var size: Variant = extra.get("shape_size")
	if size is not int or size not in SoboManager.power_of_two_sizes:
		return
	var kind: String = str(saved.get_meta("special_sobo_trait", ""))
	var shape: SoboManager.SoboData = make_liquid_data(size) if kind == "liquid" else SoboManager.get_sobo_data(size)
	var original: SoboManager.SoboData = SoboManager.get_sobo_data(saved.size)
	SoboManager.sobo_datas[saved.size] = shape
	for suba: Suba in sobo.subas:
		suba.free()
	sobo.subas.clear()
	var spacing: float = SoboManager.dist_between_subas
	if kind == "liquid":
		SoboManager.dist_between_subas *= number("liquid_slack")
		sobo.set_meta(LIQUID_META, number("liquid_slack"))
	sobo.initialize(saved.size)
	SoboManager.dist_between_subas = spacing
	SoboManager.sobo_datas[saved.size] = original
	sobo.set_meta(SHAPE_META, size)
	set_value(sobo, saved.size)


static func get_text(key: String) -> String:
	var words: Dictionary = WORDS.get(key, {})
	var language: String = "ja" if TranslationServer.get_locale().begins_with("ja") else "en"
	return words.get(language, words.get("en", key))


func draw_marker(marker: Node2D, _sobo: Sobo, kind: String, offset: Vector2, size: float, color: Color) -> void:
	if kind == "liquid":
		marker.draw_colored_polygon(PackedVector2Array([offset + Vector2(0.0, -size * 0.45), offset + Vector2(-size * 0.24, size * 0.02), offset + Vector2(size * 0.24, size * 0.02)]), color)
		marker.draw_circle(offset + Vector2(0.0, size * 0.1), size * 0.26, color)
	elif kind == "washer":
		marker.draw_arc(offset, size * 0.4, 0.2, TAU - 0.4, 20, color, size * 0.14, true)
		marker.draw_line(offset + Vector2(size * 0.4, -size * 0.15), offset + Vector2(size * 0.1, -size * 0.25), color, size * 0.14, true)


func make_liquid_data(size: int) -> SoboManager.SoboData:
	if liquid_data.has(size):
		return liquid_data[size]
	var source: SoboManager.SoboData = SoboManager.get_sobo_data(size)
	var data:= SoboManager.SoboData.new()
	for prop: Dictionary in source.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data.set(prop.name, source.get(prop.name))
	data.inner_circle = copied_circle(source.inner_circle)
	data.inner_circle.area = source.inner_circle.area * number("liquid_area_hold")
	liquid_data[size] = data
	return data


func copied_circle(circle: Variant) -> Variant:
	if circle is Resource or circle is Dictionary:
		return circle.duplicate()
	var copy: Object = circle.get_script().new() if circle.get_script() != null else ClassDB.instantiate(circle.get_class())
	for prop: Dictionary in circle.get_property_list():
		if prop.name != "script" and prop.usage & (PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE):
			copy.set(prop.name, circle.get(prop.name))
	return copy


func settle_liquids(mode: SceneClassic) -> void:
	for sobo: Sobo in mod.live_stack(mode):
		if mod.trait_of(sobo) == "liquid" and not sobo.has_meta(LIQUID_META) and SoboManager.power_of_two_sizes.has(sobo.data.size) and mod.at_rest(sobo):
			reshape_liquid(sobo)


func reshape_liquid(sobo: Sobo) -> Sobo:
	var spacing: float = SoboManager.dist_between_subas
	SoboManager.dist_between_subas = spacing * number("liquid_slack")
	var size: int = int(sobo.get_meta(SHAPE_META, sobo.data.size))
	var liquid: Sobo = mod.replace_shape(sobo, make_liquid_data(size), "liquid")
	SoboManager.dist_between_subas = spacing
	liquid.set_meta(LIQUID_META, number("liquid_slack"))
	copy_body_places(sobo, liquid)
	set_value(liquid, sobo.data.size)
	liquid.set_meta(SHAPE_META, size)
	mod.add_marker(liquid, "liquid")
	return liquid


func copy_body_places(source: Sobo, target: Sobo) -> void:
	if source.subas.size() != target.subas.size():
		return
	for index: int in source.subas.size():
		target.subas[index].global_position = source.subas[index].global_position
		target.subas[index].linear_velocity = source.subas[index].linear_velocity
	target.extra_mass_ball.global_position = source.extra_mass_ball.global_position
	target.read_body_states()


func liquid_acceleration(mode: SceneClassic, sobo: Sobo, direction: Vector2, gravity: float) -> Vector2:
	if not is_instance_valid(sobo) or sobo.is_queued_for_deletion() or not mode.sobos_in_stack.has(sobo) or mod.trait_of(sobo) != "liquid":
		return Vector2.ZERO
	return direction * gravity * number("liquid_extra_gravity") * Parameters.liquid_acceleration_scale(sobo.data.size)
