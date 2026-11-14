extends RefCounted

# Default, minimum, maximum, whole number, page, English, Japanese.
const VALUES: Dictionary = {
	"weight_washer": [3.0, 0.0, 100.0, false, "added_weights", "Tornado frequency", "トルネードの出現比率"],
	"weight_liquid": [3.0, 0.0, 100.0, false, "added_weights", "Liquid frequency", "液体の出現比率"],
	"weight_darkmatter": [3.0, 0.0, 100.0, false, "added_weights", "Dark matter frequency", "ダークマターの出現比率"],
	"weight_shuffle": [3.0, 0.0, 100.0, false, "added_weights", "Change frequency", "チェンジの出現比率"],
	"weight_rock": [3.0, 0.0, 100.0, false, "added_weights", "Rock frequency", "岩の出現比率"],
	"weight_bigbang": [0.75, 0.0, 100.0, false, "added_weights", "Big Bang frequency", "ビッグバンの出現比率"],
	"extra_delay": [0.8, 0.0, 30.0, false, "washer", "Tornado start delay (s)", "トルネードが効き始めるまで（秒）"],
	"extra_max_targets": [8.0, 1.0, 32.0, true, "washer", "Most sobos a tornado pushes", "トルネードが押す最大個数"],
	"washer_range": [4.0, 1.0, 20.0, false, "washer", "Tornado range (radii)", "トルネードの届く範囲（半径の倍数）"],
	"washer_strength": [0.9, 0.0, 5.0, false, "washer", "Tornado force", "トルネードの強さ"],
	"washer_speed": [140.0, 1.0, 1000.0, false, "washer", "Tornado speed limit", "トルネードの速さの上限"],
	"liquid_slack": [1.65, 1.0, 3.0, false, "liquid", "Softness multiplier", "液体の柔らかさの倍率"],
	"liquid_area_hold": [0.95, 0.5, 3.0, false, "liquid", "Area multiplier", "液体の面積倍率"],
	"liquid_extra_gravity": [2.0, 0.0, 10.0, false, "liquid", "Additional gravity multiplier", "液体に追加する重力倍率"],
}

static func group_label(group: String) -> String:
	var labels: Dictionary = {
		"added_weights": ["Frequency: tornado, liquid, dark matter, change, rock, Big Bang", "出現比率: トルネード・液体・ダークマター・チェンジ・岩・ビッグバン"],
		"washer": ["Tornado", "トルネード"], "liquid": ["Liquid", "液体"],
	}
	return labels[group][1 if TranslationServer.get_locale().begins_with("ja") else 0]


static func merge_outcome(kind0: String, kind1: String) -> String:
	if kind0.is_empty() == kind1.is_empty():
		return "plain"
	return "carry"


static func can_halve(owner_size: int, target_size: int, target_trait: String) -> bool:
	if owner_size < 2 or target_trait != "":
		return false
	return target_size >= 2 and (target_size & (target_size - 1)) == 0


static func half_children(target_size: int) -> Array:
	return [target_size / 2, target_size / 2]


static func fling_pair(speed: float) -> Array:
	return [Vector2(speed, 0.0), Vector2(-speed, 0.0)]


static func shuffle_kept(kind0: String, spent0: bool, kind1: String, spent1: bool) -> bool:
	if kind0 == "shuffle" and not spent0:
		return true
	if kind1 == "shuffle" and not spent1:
		return true
	return false


static func reference_radius(size: int) -> float:
	var steps: float = log(float(size)) / log(2.0)
	return sqrt(pow(1.26, steps) * 3700.0 / PI)


static func washer_owner_radius(owner_size: int) -> float:
	return reference_radius(clampi(owner_size, 1, 64))


const WASHER_RANGE_FULL_BOARD := 4.0


static func tornado_board_diagonal() -> float:
	# Walls x=±298, floor y=322, top of the opening y=-322.
	return Vector2(298.0 * 2.0, 322.0 - (-322.0)).length()


static func washer_size_scale(owner_size: int) -> float:
	# A plain radius ratio leaves a size-1 tornado too weak. Scale from that floor
	# up to a size 64. Sizes above 64 stay at the size-64 force.
	var steps: float = log(float(clampi(owner_size, 1, 64))) / log(2.0)
	return lerpf(0.85, 1.0, steps / 6.0)


static func washer_reach(owner_radius: float, range_scale: float, baseline_radius: float) -> float:
	var baseline := baseline_radius if baseline_radius > 0.0 else owner_radius
	if baseline <= 0.0:
		return 0.0
	return tornado_board_diagonal() * (range_scale / WASHER_RANGE_FULL_BOARD) * (owner_radius / baseline)


static func washer_push(gravity: float, strength: float, speed: float, speed_limit: float, owner_size: int) -> float:
	return gravity * strength * washer_size_scale(owner_size) * clampf(1.0 - speed / speed_limit, 0.0, 1.0)


static func washer_turn_radians(gravity: float, strength: float, speed_limit: float, radius: float, seconds: float, steps: int) -> float:
	var speed := 0.0
	var angle := 0.0
	var step: float = seconds / float(maxi(steps, 1))
	for _index: int in steps:
		speed += washer_push(gravity, strength, speed, speed_limit, 64) * step
		angle += speed / radius * step
	return angle


static func liquid_acceleration_scale(size: int) -> float:
	return 1.0 + log(float(maxi(size, 1))) / log(2.0) / 6.0


static func rock_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func rock_alignment(locals: Array, currents: Array) -> Dictionary:
	var center := Vector2.ZERO
	var count := maxi(currents.size(), 1)
	for point: Variant in currents:
		center += rock_vector(point)
	center /= float(count)
	var same := 0.0
	var cross := 0.0
	for index: int in mini(locals.size(), currents.size()):
		var local := rock_vector(locals[index])
		var offset := rock_vector(currents[index]) - center
		same += local.dot(offset)
		cross += local.x * offset.y - local.y * offset.x
	return {"center": center, "angle": atan2(cross, same)}


static func rock_body_velocity(velocities: Array) -> Vector2:
	var sum := Vector2.ZERO
	for velocity: Variant in velocities:
		sum += rock_vector(velocity)
	return sum / float(maxi(velocities.size(), 1))


static func rock_spin(offsets: Array, velocities: Array, body_velocity: Vector2) -> float:
	var num := 0.0
	var den := 0.0
	for index: int in mini(offsets.size(), velocities.size()):
		var rel := rock_vector(velocities[index]) - body_velocity
		var offset := rock_vector(offsets[index])
		num += offset.x * rel.y - offset.y * rel.x
		den += offset.length_squared()
	if den == 0.0:
		return 0.0
	return num / den


static func rock_point_velocity(body_velocity: Vector2, spin: float, offset: Vector2) -> Vector2:
	return body_velocity + Vector2(-offset.y, offset.x) * spin
