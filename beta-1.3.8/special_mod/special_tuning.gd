extends RefCounted

const CHANCES: Array[float] = [0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08]
const WEIGHTS: Dictionary = {"small": 3.0, "puffy": 3.0, "magnet": 2.0, "sticky": 1.0}
const PUFFY_GRAVITY_RATIO:= 0.5
const MAGNET_RANGE:= 3.0
const MAGNET_STRENGTH:= 0.25
const STICKY_STRENGTH:= 2.0
const STICKY_LAUNCH_SPEED:= 500.0
const STICKY_LIMIT:= 3
const STICKY_COOLDOWN:= 2.0
const SMALL_TIER_DROP:= 3
const MARKER_OFFSET:= 0.45
const MARKER_SIZE:= 0.30
const MARKER_NUMBER_MIX:= 0.5
