extends RefCounted
## Opt-in diagnostic spans. Only stable stage identifiers and monotonic times are logged.

static func begin(lane: String, stage: String) -> int:
	if OS.get_environment("HUB_BOOT_TRACE") != "1":
		return 0
	var started := Time.get_ticks_usec()
	print("Mod Hub trace lane=", lane, " stage=", stage, " event=begin us=", started)
	return started

static func end(lane: String, stage: String, started: int) -> void:
	if started == 0:
		return
	print("Mod Hub trace lane=", lane, " stage=", stage, " event=end us=", Time.get_ticks_usec())
