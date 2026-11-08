extends "res://game_mode/game_modes/classic/scene_classic.gd"


func spawn_from_states(states: Array[SoboState]) -> Array[Sobo]:
	var mod: Node = get_node("/root/SpecialSobo")
	var created: Array[Sobo] = []
	for state: SoboState in states:
		var original: SoboManager.SoboData = SoboManager.get_sobo_data(state.size)
		if state.get_meta("special_sobo_trait", "") == "small":
			SoboManager.sobo_datas[state.size] = mod.make_small_data(state.size)
		created.append_array(super.spawn_from_states([state]))
		SoboManager.sobo_datas[state.size] = original
	return created


func capture_game_state() -> GameState:
	var state: GameState = super.capture_game_state()
	state.set_meta("special_sobo_run", Engine.get_meta("special_sobo_run", false))
	return state
