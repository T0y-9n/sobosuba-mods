extends Node

const Parameters = preload("special_effect_parameters.gd")

const WORDS: Dictionary = {
	"trait liquid": {"en":"liquid sobos", "ja":"液体のソボ"},
	"trait bigbang": {"en":"bigbang sobos", "ja":"ビッグバンのソボ"},
	"description bigbang": {"en":"A negative number. Touching the same positive number sets off a chain from itself: every sobo it reaches splits, one step at a time, down to 1. A larger number reaches farther, and 64 reaches the whole board. No sobo merges until about a second after the last split. Two of the same negative number become an ordinary double.", "ja":"負の数。同じ正の数に触れると、自分を中心に連鎖が広がり、届いたソボは 1 段ずつ 1 まで割れる。数が大きいほど遠くまで届き、64 では盤の全部。最後に割れてから約 1 秒は合体しない。同じ負の数どうしは普通の倍になる"},
	"description liquid": {"en":"Soft, heavy sobos that spread and settle in the stack.", "ja":"盤面で柔らかく重くなり、広がって沈むソボ"},
	"trait washer": {"en":"tornado sobos", "ja":"トルネードソボ"},
	"trait shuffle": {"en":"change sobos", "ja":"チェンジソボ"},
	"description washer": {"en":"Stirs the sobos around it. A larger number reaches farther and pushes harder. At 64 it covers the whole board, and a larger number stays at that reach.", "ja":"周りのソボをかき混ぜる。数が大きいほど遠く、強く押す。64 で盤面の全体に届き、それより大きくても同じ届き。"},
	"description shuffle": {"en":"Swaps numbers with the first sobo it touches, once, as soon as they touch. Only the number moves, with the merge rule that goes with it. Shapes, colors and the other sobo's own effect stay.", "ja":"最初に触れたソボと、触れた時に 1 回だけ数字を入れ替える。入れ替わるのは数字（と、その数字の合体の決まり）だけで、形・色・相手の効果はそのまま。"},
	"trait rock": {"en":"rock sobos", "ja":"岩のソボ"},
	"description rock": {"en":"Keeps the shape it had when thrown, or when it was merged. It can still roll as a whole. Its weight stays the same.", "ja":"投げた瞬間、または合体した瞬間の形を保つ。体ごと転がる。重さは変えない"},
	"trait darkmatter": {"en":"dark matter sobos", "ja":"ダークマターソボ"},
	"description darkmatter": {"en":"Black, with no number and no mark. Its size is random, from the smallest sobo this match can spawn up to the largest one on the board. It keeps its real number, and merges only with that number. Merging with an ordinary sobo stays dark matter and draws a new size. Two of the same number become an ordinary sobo.", "ja":"真っ黒で、数字も印も出ない。大きさはランダムで、その試合に出る一番小さいソボから盤面の一番大きいソボまで。本当の数字を内側に持ち、その数字とだけ合体する。普通のソボと合体するとダークマターのまま大きさを引き直す。同じ数字どうしは普通のソボに戻る。"},
	"extra sobos": {"en":"extra sobos", "ja":"追加ソボ"},
}

const KINDS: Array[String] = ["washer", "liquid", "darkmatter", "shuffle", "rock", "bigbang"]
const STATE_META := "special_extra_state"
const SHAPE_META := "special_extra_shape_size"
const KEEP_COLOR_META := "special_shuffle_color"

const LIQUID_META := "special_sobo_liquid_slack"

var liquid_data: Dictionary = {}
var bang_clock := 0.0
## The Big Bang wave reaches the edge of its range in this many seconds.
const BANG_WAVE_SECONDS := 1.0
## Each split of a chain waits this long before the next halving.
const BANG_STEP_SECONDS := 0.3
## Merges stay off on the whole board until the chain has calmed down,
## and for this long after the last split.
const BANG_QUIET_SECONDS := 1.0
const BANG_HOLD_META := "special_bigbang_hold"
var bang_quiet_until := -1.0
## A half needs this much room (centre distance over summed radii) from every other
## sobo. Halves born on top of each other blow the soft bodies apart.
const BANG_ROOM_RATIO := 0.5
## While a crack waits, the room it asks for falls to this by the end of the wait: a half
## on the floor or under the pile then fits, still outside every body and the wall.
const BANG_ROOM_FLOOR := 0.15
## A crack with no room pushes the sobos in the way aside and waits a frame at a time,
## up to this many frames. In a full bucket the halves need more room than the pile has.
const BANG_WAIT_FRAMES := 240
## The push on a sobo in the way of a waiting crack, in gravities. A push that keeps
## growing presses the pile into both side bumpers and ends the run.
const BANG_PUSH_GRAVITIES := 3.0
## The bang first throws the sobos in its range away from where it went off (speed at
## the centre, falling to 0 at the edge of the range), so the pile opens up for the halves.
const BANG_KICK_SPEED := 300.0
## A side bumper pressed in this far (0 out, 1 fully in) stops the cracks for a while.
const BANG_BUMPER_LIMIT := 0.5
const BANG_WAIT_META := "special_bigbang_waited"
const BANG_AXES := 8
## The two halves sit this many radii of the cracked sobo apart.
const BANG_SPACING := 1.05
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
		sobo.set_meta(STATE_META, {"elapsed":0.0, "spent":false})
	return sobo.get_meta(STATE_META)


func capture(sobo: Sobo) -> Dictionary:
	var result: Dictionary = {}
	var data: Variant = sobo.get_meta(STATE_META) if sobo.has_meta(STATE_META) else null
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
		sobo.set_meta(STATE_META, {
			"elapsed":finite_number(data.get("elapsed"), 90.0),
			"spent":data.get("spent") == true,
		})
	var shape: Variant = saved.get("shape_size")
	if shape is int and shape in SoboManager.power_of_two_sizes:
		sobo.set_meta(SHAPE_META, shape)


func eligible(sobo: Variant, mode: SceneClassic) -> bool:
	return (is_instance_valid(sobo) and not sobo.is_queued_for_deletion()
		and mode.sobos_in_stack.has(sobo) and not sobo.frozen
		and not sobo.merged_this_frame and mod.at_rest(sobo))


func action_allowed(owner: Sobo, mode: SceneClassic, kind: String) -> bool:
	return (mod.run_special and GameModeManager.current_scene == mode
		and eligible(owner, mode) and mod.trait_of(owner) == kind
		and not state(owner).spent)


func tick(mode: SceneClassic, delta: float, gravity: float) -> void:
	if not mod.run_special or GameModeManager.current_scene != mode or not is_finite(delta) or delta <= 0.0:
		return
	settle_liquids(mode)
	bigbang_touch(mode, delta, gravity)
	hold_rocks(mode)
	var stack: Array[Sobo] = mod.live_stack(mode)
	for sobo: Sobo in stack:
		if mod.trait_of(sobo) == "liquid":
			sobo.apply_uniform_acceleration(liquid_acceleration(mode, sobo, down_direction(), gravity))
	hold_bang_merges()
	for owner: Sobo in stack:
		var kind: String = mod.trait_of(owner)
		if kind == "liquid" or kind == "bigbang" or kind == "rock" or kind not in KINDS or not eligible(owner, mode):
			continue
		var data := state(owner)
		if data.spent:
			continue
		data.elapsed += delta
		if kind == "shuffle":
			# The change acts on the first sobo it touches, so it looks every frame from the start.
			var partner: Sobo = shuffle_partner(owner, mode)
			if partner != null:
				swap_with(owner, partner, mode)
			continue
		if kind == "washer" and data.elapsed >= number("extra_delay"):
			wash(owner, mode, gravity)


func hold_rocks(mode: SceneClassic) -> void:
	for owner: Sobo in mod.live_stack(mode):
		if mod.trait_of(owner) != "rock" or owner.subas.is_empty() or owner.is_queued_for_deletion():
			continue
		var locals: Array = state(owner).get("rock_local", [])
		if locals.size() != owner.subas.size():
			capture_rock(owner)
			continue
		var currents: Array = []
		var velocities: Array = []
		for suba: Suba in owner.subas:
			currents.append(suba.global_position)
			velocities.append(suba.linear_velocity)
		var body_velocity: Vector2 = Parameters.rock_body_velocity(velocities)
		var pose: Dictionary = Parameters.rock_alignment(locals, currents)
		var angle: float = pose.angle
		var center: Vector2 = pose.center
		var offsets: Array = []
		for local: Variant in locals:
			offsets.append(Parameters.rock_vector(local).rotated(angle))
		var spin: float = Parameters.rock_spin(offsets, velocities, body_velocity)
		for index: int in owner.subas.size():
			var offset: Vector2 = offsets[index]
			owner.subas[index].global_position = center + offset
			owner.subas[index].linear_velocity = Parameters.rock_point_velocity(body_velocity, spin, offset)
			owner.subas[index].angular_velocity = spin
		owner.extra_mass_ball.global_position = center
		owner.extra_mass_ball.linear_velocity = body_velocity
		owner.read_body_states()
		owner.update_polygon_points()


# from_server: read the positions the physics server holds. The base fix_shape
# writes the repaired shape there; the nodes keep the broken shape until the next step.
func capture_rock(owner: Sobo, from_server: bool = false) -> void:
	if owner.subas.is_empty():
		return
	var points: Array[Vector2] = []
	for suba: Suba in owner.subas:
		if from_server:
			var placed: Transform2D = PhysicsServer2D.body_get_state(suba.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
			points.append(placed.origin)
		else:
			points.append(suba.global_position)
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(points.size())
	var locals: Array = []
	for point: Vector2 in points:
		locals.append(point - center)
	state(owner)["rock_local"] = locals


# After the base fix_shape: put the rock back on the shape it holds, at rest,
# where the base found it. The base repair draws a small ring; a rock keeps its own shape.
func restore_rock(owner: Sobo) -> void:
	var locals: Array = state(owner).get("rock_local", [])
	if owner.subas.is_empty() or locals.size() != owner.subas.size():
		capture_rock(owner, true)
		return
	var currents: Array = []
	for suba: Suba in owner.subas:
		currents.append(suba.global_position)
	var pose: Dictionary = Parameters.rock_alignment(locals, currents)
	var center: Vector2 = pose.center
	for index: int in owner.subas.size():
		var suba: Suba = owner.subas[index]
		suba.global_position = center + Parameters.rock_vector(locals[index]).rotated(pose.angle)
		suba.linear_velocity = Vector2.ZERO
		suba.angular_velocity = 0.0
	owner.extra_mass_ball.global_position = center
	owner.extra_mass_ball.linear_velocity = Vector2.ZERO
	owner.read_body_states()
	owner.update_polygon_points()
	owner.snap_interpolation()


func nearby(owner: Sobo, mode: SceneClassic, reach: float = -1.0) -> Array[Sobo]:
	var targets: Array[Sobo] = []
	for target: Sobo in mod.live_stack(mode):
		if target != owner and eligible(target, mode):
			targets.append(target)
	var radius: float = reach if reach > 0.0 else owner.data.outer_circle.radius * number(mod.trait_of(owner) + "_range")
	return SoboManager.get_closest_sobos_center(owner.center, int(number("extra_max_targets")), radius, targets)


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


func spawn_half(target: Sobo, mode: SceneClassic, spots: Array[Vector2], axis: Vector2) -> Array[Sobo]:
	if not Parameters.can_halve(2, target.data.size, ""):
		return []
	var sizes: Array = Parameters.half_children(target.data.size)
	var flung: Array = Parameters.fling_pair(18.0)
	var velocity: Vector2 = target.get_avg_velocity()
	var children: Array[Sobo] = []
	for index: int in 2:
		var child: Sobo = SoboManager.create(int(sizes[index]), spots[index])
		mode.enter_stack(child)
		child.set_velocity(velocity + (flung[index] as Vector2).rotated(axis.angle()))
		child.read_body_states()
		children.append(child)
	target.set_meta(mod.REPLACED_META, true)
	mod.forget_sticky(target)
	mode.remove_from_role_lists(target)
	target.disable_collisions()
	SoboManager.all_sobos.erase(target)
	target.queue_free()
	ScoreManager.set_score(mode.calculate_score())
	return children


func keep_shuffle(result: Sobo, saved: Dictionary) -> void:
	mod.apply_trait(result, "shuffle")
	var data := state(result)
	data["elapsed"] = finite_number(saved.get("elapsed", 0.0), 90.0)
	data["spent"] = false
	data.erase("skipped")


## The first sobo the shuffle touches. Plain sobos, primes (plain sobos with a prime number)
## and dark matter can swap. Other special sobos keep their own rules and are passed over.
func shuffle_partner(owner: Sobo, mode: SceneClassic) -> Sobo:
	for other: Sobo in mod.live_stack(mode):
		if other == owner or not eligible(other, mode):
			continue
		var kind: String = mod.trait_of(other)
		if kind != "" and kind != "darkmatter":
			continue
		if bigbang_touches(owner, other):
			return other
	return null


## The change sobo (internal id "shuffle"): one swap with the first sobo touched, then the effect ends.
## Only the number moves, with the merge rule that goes with it (2026-11-13).
## Each body keeps its own shape, color and effect: dark matter stays dark matter.
func swap_with(owner: Sobo, partner: Sobo, mode: SceneClassic) -> bool:
	if not action_allowed(owner, mode, "shuffle") or not eligible(partner, mode):
		return false
	if mod.diagnostics != null:
		mod.diagnostics.log("shuffle owner=" + mod.diagnostic_sobo(owner) + " partner=" + mod.diagnostic_sobo(partner))
	var partner_kind: String = mod.trait_of(partner)
	var owner_value: int = owner.data.size
	var owner_allow: bool = owner.allow_merges
	var owner_color: Color = owner.color
	var partner_color: Color = partner.color
	set_number_only(owner, partner.data.size)
	set_number_only(partner, owner_value)
	owner.allow_merges = partner.allow_merges
	partner.allow_merges = owner_allow
	state(owner).spent = true
	var marker: Node = owner.get_node_or_null("SpecialMarker")
	if marker != null:
		marker.queue_free()
	owner.remove_meta(mod.TRAIT_META)
	owner.set_meta(KEEP_COLOR_META, owner_color)
	if partner_kind != "darkmatter":
		partner.set_meta(KEEP_COLOR_META, partner_color)
	var body_path: String = (get_script() as Script).resource_path.get_base_dir().path_join("special_body.gd")
	if partner.get_script().resource_path != body_path:
		mod.patch_script(partner, body_path)
	owner.apply_style()
	partner.apply_style()
	var animation: Node2D = load((get_script() as Script).resource_path.get_base_dir().path_join("shuffle_pulse.gd")).new()
	animation.first = weakref(owner)
	animation.second = weakref(partner)
	get_tree().current_scene.add_child(animation)
	return true


func set_number_only(sobo: Sobo, value: int) -> void:
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
	forget_contacts(sobo)
	sobo.read_body_states()
	sobo.sobo_label.text = str(value)


# setup_core empties the native part's record of the contacts it last wrote, but
# not the lists themselves, and the next update rewrites a list only when it
# differs from that record. Empty the lists too, or a neighbor that goes away
# before the next update stays listed after it is freed.
func forget_contacts(sobo: Sobo) -> void:
	for suba: Suba in sobo.subas:
		suba.contacting_other_subas.clear()
	sobo.contacting_same_size_sobos.clear()


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
	forget_contacts(sobo)
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


func draw_marker(marker: Node2D, sobo: Sobo, kind: String, offset: Vector2, size: float, color: Color) -> void:
	if sobo.get_meta(STATE_META, {}).get("spent", false):
		color.a *= 0.35
	if kind == "liquid":
		marker.draw_colored_polygon(PackedVector2Array([offset + Vector2(0.0, -size * 0.45), offset + Vector2(-size * 0.24, size * 0.02), offset + Vector2(size * 0.24, size * 0.02)]), color)
		marker.draw_circle(offset + Vector2(0.0, size * 0.1), size * 0.26, color)
	elif kind == "rock":
		marker.draw_rect(Rect2(offset + Vector2(-size, -size) * 0.28, Vector2.ONE * size * 0.56), color, false, size * 0.12)
	elif kind == "washer":
		marker.draw_arc(offset, size * 0.4, 0.2, TAU - 0.4, 20, color, size * 0.14, true)
		marker.draw_line(offset + Vector2(size * 0.4, -size * 0.15), offset + Vector2(size * 0.1, -size * 0.25), color, size * 0.14, true)
	elif kind == "bigbang":
		# A burst: eight rays that start away from the center (sticky draws six from the center).
		for ray: int in 8:
			var direction := Vector2.UP.rotated(TAU * float(ray) / 8.0)
			marker.draw_line(offset + direction * size * 0.18, offset + direction * size * 0.48, color, size * 0.12, true)
	elif kind == "shuffle":
		for side: float in [-1.0, 1.0]:
			var start := offset + Vector2(-size * 0.4 * side, size * 0.25 * side)
			var end := offset + Vector2(size * 0.4 * side, size * 0.25 * side)
			marker.draw_line(start, end, color, size * 0.14, true)
			marker.draw_line(end, end + Vector2(-side, -side) * size * 0.2, color, size * 0.14, true)


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


func bigbang_reach(magnitude: int) -> float:
	var steps: float = log(float(maxi(magnitude, 1))) / log(2.0)
	return Parameters.tornado_board_diagonal() * steps / 6.0


func bang_stages(magnitude: int) -> int:
	var stages := 0
	var n := magnitude
	while n > 1:
		n = int(n / 2)
		stages += 1
	return stages


func bigbang_touch(mode: SceneClassic, delta: float, gravity: float) -> void:
	bang_clock += delta
	for sobo: Sobo in SoboManager.all_sobos.duplicate():
		if not is_instance_valid(sobo) or sobo.is_queued_for_deletion() or not sobo.has_meta("special_bigbang_crack_at"):
			continue
		if bang_clock < float(sobo.get_meta("special_bigbang_crack_at")):
			continue
		var left: int = int(sobo.get_meta("special_bigbang_left", 0))
		sobo.remove_meta("special_bigbang_crack_at")
		sobo.remove_meta("special_bigbang_left")
		crack_sobo(mode, sobo, left, gravity)
	for owner: Sobo in mod.live_stack(mode).duplicate():
		if not is_instance_valid(owner) or owner.is_queued_for_deletion() or mod.trait_of(owner) != "bigbang" or owner.data.size >= 0:
			continue
		var magnitude: int = -owner.data.size
		var partner: Sobo = null
		var same: Sobo = null
		for other: Sobo in mod.live_stack(mode):
			if other == owner or not is_instance_valid(other) or other.is_queued_for_deletion():
				continue
			if not bigbang_touches(owner, other):
				continue
			if mod.trait_of(other) == "bigbang" and other.data.size == owner.data.size:
				same = other
				break
			if partner == null and other.data.size == magnitude:
				partner = other
		if same != null:
			var born: int = magnitude * 2
			var at: Vector2 = owner.center
			remove_sobo(mode, owner)
			remove_sobo(mode, same)
			var ordinary: Sobo = SoboManager.create(born, at)
			mode.enter_stack(ordinary)
			continue
		if partner == null:
			continue
		# −n and +n cancel out. The bang spreads from the bigbang sobo, reaching the
		# farther sobos later, and each sobo halves one step at a time down to 1.
		var center: Vector2 = owner.center
		var reach: float = bigbang_reach(magnitude)
		var speed: float = maxf(reach, 1.0) / BANG_WAVE_SECONDS
		remove_sobo(mode, owner)
		remove_sobo(mode, partner)
		bang_quiet_until = maxf(bang_quiet_until, bang_clock + BANG_QUIET_SECONDS)
		for other: Sobo in mod.live_stack(mode):
			if not is_instance_valid(other) or other.is_queued_for_deletion():
				continue
			var distance: float = center.distance_to(other.center)
			if distance <= reach and distance > 0.001:
				other.add_velocity((other.center - center) / distance * BANG_KICK_SPEED * (1.0 - distance / reach))
			if other.data.size <= 1 or mod.trait_of(other) == "bigbang":
				continue
			if distance <= reach:
				other.set_meta("special_bigbang_left", bang_stages(other.data.size))
				other.set_meta("special_bigbang_crack_at", bang_clock + distance / speed)


func bigbang_touches(left: Sobo, right: Sobo) -> bool:
	for suba: Suba in left.subas:
		for other: Suba in suba.contacting_other_subas:
			if is_instance_valid(other) and other.sobo == right:
				return true
	return false


func crack_sobo(mode: SceneClassic, sobo: Sobo, stages: int, gravity: float) -> void:
	if not is_instance_valid(sobo) or sobo.is_queued_for_deletion() or sobo.data.size <= 1 or stages <= 0:
		return
	# In a full bucket, neighbours crack in the same frame. Halves laid side by side
	# land on the neighbour's halves, so pick the roomiest direction, or wait for room.
	# A sobo resting in the pile has no room on both sides of it, so one half may also
	# stay where the sobo was while the other goes the free way.
	var axis: Vector2 = Vector2.RIGHT
	var spots: Array[Vector2] = half_spots(sobo, axis, 0.0)
	var room: float = -1.0
	for step: int in BANG_AXES * 2:
		var candidate: Vector2 = Vector2.RIGHT.rotated(PI * step / BANG_AXES)
		for shift: float in [0.0, 1.0]:
			# Pairs around the centre repeat after half a turn.
			if shift == 0.0 and step >= BANG_AXES:
				continue
			var at: Array[Vector2] = half_spots(sobo, candidate, shift)
			var free: float = half_room(mode, sobo, at)
			if free > room:
				room = free
				axis = candidate
				spots = at
	var waited: int = int(sobo.get_meta(BANG_WAIT_META, 0))
	if bumpers_pressed(mode) or room < lerpf(BANG_ROOM_RATIO, BANG_ROOM_FLOOR, minf(float(waited) / float(BANG_WAIT_FRAMES / 2), 1.0)):
		if waited >= BANG_WAIT_FRAMES:
			# Giving up ends this sobo's part of the chain: the board stays quiet a step
			# longer, as after a split, before merges come back.
			sobo.remove_meta(BANG_WAIT_META)
			bang_quiet_until = maxf(bang_quiet_until, bang_clock + BANG_QUIET_SECONDS)
			return
		if not bumpers_pressed(mode):
			push_aside(sobo, spots, gravity * BANG_PUSH_GRAVITIES)
		sobo.set_meta(BANG_WAIT_META, waited + 1)
		sobo.set_meta("special_bigbang_left", stages)
		sobo.set_meta("special_bigbang_crack_at", bang_clock)
		return
	var children: Array[Sobo] = spawn_half(sobo, mode, spots, axis)
	bang_quiet_until = maxf(bang_quiet_until, bang_clock + BANG_QUIET_SECONDS)
	var left: int = stages - 1
	if left <= 0:
		return
	for child: Sobo in children:
		if not is_instance_valid(child) or child.data.size <= 1:
			continue
		child.set_meta("special_bigbang_left", left)
		child.set_meta("special_bigbang_crack_at", bang_clock + BANG_STEP_SECONDS)


## True while the pile presses either side bumper of the base game in. The base ends
## the run when both stay pressed, so a crack then neither splits nor pushes: more
## or bigger sobos would only press the pile in further.
func bumpers_pressed(mode: SceneClassic) -> bool:
	if not is_instance_valid(mode):
		return false
	for side: ClassicSide in [mode.left, mode.right]:
		if side == null or side.bumper == null:
			continue
		if side.bumper.holding or side.bumper.dist_nrm >= BANG_BUMPER_LIMIT:
			return true
	return false


## Pushes every sobo whose body sits where a half of the waiting crack would be born
## away from that spot, so the pile makes room as a bang would.
func push_aside(target: Sobo, spots: Array[Vector2], push: float) -> void:
	var radius: float = SoboManager.get_sobo_data(int(target.data.size / 2)).outer_circle.radius
	for at: Vector2 in spots:
		for other: Sobo in SoboManager.all_sobos:
			if other == target or not is_instance_valid(other) or other.is_queued_for_deletion():
				continue
			var away: Vector2 = other.center - at
			if away.length() - other.data.outer_circle.radius >= radius * BANG_ROOM_RATIO:
				continue
			var direction: Vector2 = away.normalized() if away.length() > 0.001 else (at - target.center).normalized()
			other.apply_uniform_acceleration(direction * push)


## Where the two halves of a crack are born along the axis: around the cracked sobo's
## centre (shift 0), or one half where the sobo was and the other further along (shift 1).
func half_spots(target: Sobo, axis: Vector2, shift: float) -> Array[Vector2]:
	var gap: float = target.data.outer_circle.radius * BANG_SPACING
	return [target.center + axis * (shift - 1.0) * gap, target.center + axis * (shift + 1.0) * gap]


## The tightest fit of the two halves at the given spots, in half radii: how far each half's
## centre sits outside the other half, every neighbour's body and the bucket wall
## (0 when outside the bucket, negative when inside a body).
func half_room(mode: SceneClassic, target: Sobo, spots: Array[Vector2]) -> float:
	var radius: float = SoboManager.get_sobo_data(int(target.data.size / 2)).outer_circle.radius
	if radius <= 0.0:
		return INF
	var bucket: PackedVector2Array = bucket_polygon(mode)
	var tightest: float = (spots[0].distance_to(spots[1]) - radius) / radius
	for at: Vector2 in spots:
		if bucket.size() >= 3:
			tightest = minf(tightest, wall_room(bucket, at) / radius)
		for other: Sobo in SoboManager.all_sobos:
			if other == target or not is_instance_valid(other) or other.is_queued_for_deletion():
				continue
			tightest = minf(tightest, (at.distance_to(other.center) - other.data.outer_circle.radius) / radius)
	return tightest


## The bucket outline in global coordinates, empty when the scene has none.
func bucket_polygon(mode: SceneClassic) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if not is_instance_valid(mode):
		return outline
	var structure: Node2D = mode.get_node_or_null("StructureInvertedPoly") as Node2D
	if structure == null or not "polygon" in structure:
		return outline
	for point: Vector2 in structure.polygon:
		outline.append(structure.global_transform * point)
	return outline


## Distance from a point to the nearest bucket edge, 0 when the point is outside.
func wall_room(bucket: PackedVector2Array, at: Vector2) -> float:
	if not Geometry2D.is_point_in_polygon(at, bucket):
		return 0.0
	var nearest: float = INF
	for i: int in bucket.size():
		var hit: Vector2 = Geometry2D.get_closest_point_to_segment(at, bucket[i], bucket[(i + 1) % bucket.size()])
		nearest = minf(nearest, at.distance_to(hit))
	return nearest


## While a chain is splitting, no sobo on the board merges. Each sobo keeps what it
## would have had (a lock may end meanwhile) and gets it back once the chain is quiet.
func hold_bang_merges() -> void:
	var active: bool = bang_clock < bang_quiet_until
	if not active:
		for sobo: Sobo in SoboManager.all_sobos:
			if is_instance_valid(sobo) and sobo.has_meta("special_bigbang_crack_at"):
				active = true
				break
	for sobo: Sobo in SoboManager.all_sobos:
		if not is_instance_valid(sobo):
			continue
		if active:
			if not sobo.has_meta(BANG_HOLD_META) or sobo.allow_merges:
				sobo.set_meta(BANG_HOLD_META, sobo.allow_merges)
			sobo.allow_merges = false
		elif sobo.has_meta(BANG_HOLD_META):
			sobo.allow_merges = bool(sobo.get_meta(BANG_HOLD_META))
			sobo.remove_meta(BANG_HOLD_META)
			mod.block_negative_merge(sobo)


func remove_sobo(mode: SceneClassic, sobo: Sobo) -> void:
	if not is_instance_valid(sobo) or sobo.is_queued_for_deletion():
		return
	mode.remove_from_role_lists(sobo)
	sobo.disable_collisions()
	SoboManager.all_sobos.erase(sobo)
	sobo.queue_free()


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
