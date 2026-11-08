extends RefCounted

const Tuning = preload("special_tuning.gd")
const GROUPS: Array[String] = ["kinds", "chances", "weights", "shape", "magnet", "throwing"]
# Default, minimum, maximum, whole number, page, English, Japanese.
const VALUES: Dictionary = {
	"chance_1": [Tuning.CHANCES[0] * 100.0, 0.0, 100.0, false, "chances", "Stage 1 chance (%)", "第1段階の出現率（%）"],
	"chance_2": [Tuning.CHANCES[1] * 100.0, 0.0, 100.0, false, "chances", "Stage 2 chance (%)", "第2段階の出現率（%）"],
	"chance_3": [Tuning.CHANCES[2] * 100.0, 0.0, 100.0, false, "chances", "Stage 3 chance (%)", "第3段階の出現率（%）"],
	"chance_4": [Tuning.CHANCES[3] * 100.0, 0.0, 100.0, false, "chances", "Stage 4 chance (%)", "第4段階の出現率（%）"],
	"chance_5": [Tuning.CHANCES[4] * 100.0, 0.0, 100.0, false, "chances", "Stage 5 chance (%)", "第5段階の出現率（%）"],
	"chance_6": [Tuning.CHANCES[5] * 100.0, 0.0, 100.0, false, "chances", "Stage 6 chance (%)", "第6段階の出現率（%）"],
	"chance_7": [Tuning.CHANCES[6] * 100.0, 0.0, 100.0, false, "chances", "Stage 7 chance (%)", "第7段階の出現率（%）"],
	"weight_small": [Tuning.WEIGHTS.small, 0.0, 100.0, false, "weights", "Small: relative frequency", "小さいソボの比率"],
	"weight_puffy": [Tuning.WEIGHTS.puffy, 0.0, 100.0, false, "weights", "Puffy: relative frequency", "ふわふわのソボの比率"],
	"weight_magnet": [Tuning.WEIGHTS.magnet, 0.0, 100.0, false, "weights", "Magnet: relative frequency", "磁石のソボの比率"],
	"weight_sticky": [Tuning.WEIGHTS.sticky, 0.0, 100.0, false, "weights", "Throwing: relative frequency", "投げ飛ばすソボの比率"],
	"small_tier_drop": [Tuning.SMALL_TIER_DROP, 1.0, 10.0, true, "shape", "Small: shape levels down", "小さいソボの形を下げる段数"],
	"puffy_gravity_ratio": [Tuning.PUFFY_GRAVITY_RATIO, 0.0, 3.0, false, "shape", "Puffy: gravity multiplier", "ふわふわの重力倍率"],
	"magnet_pull_multiplier": [2.0, 0.0, 20.0, false, "magnet", "Magnet: attraction multiplier", "磁石の引力倍率"],
	"magnet_range": [Tuning.MAGNET_RANGE, 1.1, 20.0, false, "magnet", "Magnet: range in radii", "磁石の届く範囲（半径の倍数）"],
	"magnet_strength": [Tuning.MAGNET_STRENGTH, 0.0, 20.0, false, "magnet", "Magnet: field strength", "磁石の引力と反発の強さ"],
	"hold_strength": [Tuning.STICKY_STRENGTH, 0.0, 20.0, false, "magnet", "Magnet: contact hold strength", "磁石の接触後の保持力"],
	"hold_limit": [Tuning.STICKY_LIMIT, 0.0, 20.0, true, "magnet", "Magnet: maximum held sobos", "磁石が保持する最大個数"],
	"throw_speed": [Tuning.STICKY_LAUNCH_SPEED, 0.0, 3000.0, false, "throwing", "Throwing: launch speed", "投げ飛ばす速さ"],
	"throw_cooldown": [Tuning.STICKY_COOLDOWN, 0.05, 30.0, false, "throwing", "Throwing: cooldown (seconds)", "投げ飛ばす間隔（秒）"],
}

static func defaults() -> Dictionary:
	var result: Dictionary = {}
	for key: String in VALUES:
		if key != "magnet_pull_multiplier":
			result[key] = float(VALUES[key][0])
	return result

static func valid(key: String, value: float) -> bool:
	if not VALUES.has(key) or not is_finite(value):
		return false
	var spec: Array = VALUES[key]
	return value >= spec[1] and value <= spec[2] and (not spec[3] or value == floor(value))

static func label_for(key: String) -> String:
	return VALUES[key][6 if TranslationServer.get_locale().begins_with("ja") else 5]

static func group_label(group: String) -> String:
	var labels: Dictionary = {
		"kinds": ["Kinds", "種類"], "chances": ["Spawn chance", "出現率"],
		"weights": ["Relative frequency", "種類の比率"], "shape": ["Small / Puffy", "小型・ふわふわ"],
		"magnet": ["Magnet", "磁石"], "throwing": ["Throwing", "投げ飛ばす"],
	}
	return labels[group][1 if TranslationServer.get_locale().begins_with("ja") else 0]
