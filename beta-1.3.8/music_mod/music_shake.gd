extends RefCounted

const WEIGHTS := {"low": 1.0, "mid": 0.6, "high": 0.35}
const BEAT_GAIN := 450.0
const TONE_GAIN := 3000.0

static func step(bands: Dictionary, previous: Dictionary, average: float, since_beat: float, beat_scale: float, tone_scale: float, cap: float, beat_level: float = -1.0) -> Dictionary:
	var rise := 0.0
	for key: String in WEIGHTS:
		var delta := float(bands.get(key, 0.0)) - float(previous.get(key, 0.0))
		if delta > 0.0:
			rise += delta * float(WEIGHTS[key])
	var level := beat_level if beat_level >= 0.0 else float(bands.get("low", 0.0))
	var beat := level > average * 1.4 and since_beat >= 0.25
	var impulse := rise * tone_scale * TONE_GAIN
	if beat and average > 0.0:
		impulse += (level / average) * beat_scale * BEAT_GAIN
	impulse = clampf(impulse, 0.0, cap)
	return {"impulse": impulse, "beat": beat}
