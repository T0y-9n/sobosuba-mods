extends "res://game_mode/game_modes/classic/scene_classic.gd"


func _physics_process(dt: float) -> void:
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_classic.physics") if mod != null else null
	super._physics_process(dt)


func enter_selectable(sobo: Sobo):
	super.enter_selectable(sobo)
	# The game allows merges again when the bar hands a sobo back to the player.
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	if mod != null:
		mod.block_negative_merge(sobo)


func spawn_from_states(states: Array[SoboState]) -> Array[Sobo]:
	var mod: Node = get_node("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_classic.restore")
	if not mod.is_classic_run():
		return super.spawn_from_states(states)
	var created: Array[Sobo] = []
	for state: SoboState in states:
		var original: SoboManager.SoboData = SoboManager.get_sobo_data(state.size)
		if state.get_meta("special_sobo_trait", "") == "small":
			SoboManager.sobo_datas[state.size] = mod.make_small_data(state.size)
		created.append_array(super.spawn_from_states([state]))
		SoboManager.sobo_datas[state.size] = original
	return created


func capture_game_state() -> GameState:
	var _diagnostic: RefCounted = get_node("/root/SpecialSobo").diagnostic_scope("special_classic.capture")
	var state: GameState = super.capture_game_state()
	if not get_node("/root/SpecialSobo").is_classic_run():
		return state
	state.set_meta("special_sobo_run", Engine.get_meta("special_sobo_run", false))
	return state
