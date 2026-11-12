extends RefCounted

# Default, minimum, maximum, whole number, page, English, Japanese.
const VALUES: Dictionary = {
	"weight_washer": [3.0, 0.0, 100.0, false, "added_weights", "Tornado frequency", "トルネードの出現比率"],
	"weight_liquid": [3.0, 0.0, 100.0, false, "added_weights", "Liquid frequency", "液体の出現比率"],
	"weight_darkmatter": [3.0, 0.0, 100.0, false, "added_weights", "Dark matter frequency", "ダークマターの出現比率"],
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
		"added_weights": ["Frequency: tornado, liquid, dark matter", "出現比率: トルネード・液体・ダークマター"],
		"washer": ["Tornado", "トルネード"], "liquid": ["Liquid", "液体"],
	}
	return labels[group][1 if TranslationServer.get_locale().begins_with("ja") else 0]

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
