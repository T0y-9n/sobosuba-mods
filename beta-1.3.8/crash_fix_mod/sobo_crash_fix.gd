extends Node

## Sobo Crash Fix: keeps the game from handing a freed sobo to its native part.

const MOD_VERSION := "1.3.11-1.0.0"


func _ready() -> void:
	SignalBus.on_sobo_exit_tree.connect(forget_recoveries)
	print("[Sobo Crash Fix %s] loaded" % MOD_VERSION)


# At the start of a physics frame the game hands both sobos of every overlap
# recovery to the native part without checking that they are alive, and drops a
# dead sobo's record only later in that frame. A merge frees both parents while
# their record is still listed, and so does the end of a run. Drop the records
# as the sobo leaves, so a freed one is never handed over. Sobos leave through
# queue_free, never in the middle of the game's own pass over the records.
func forget_recoveries(sobo: Sobo) -> void:
	var records: Array = SoboManager.active_overlap_recoveries
	for index: int in range(records.size() - 1, -1, -1):
		if records[index].sobo_0 == sobo or records[index].sobo_1 == sobo:
			records.remove_at(index)
