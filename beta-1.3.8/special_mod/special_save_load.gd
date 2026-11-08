extends "res://save_load_manager.gd"

const SPECIAL_SAVE_PATH:= "user://special_sobo_run.sav"

var special_load_session:= 0


func save() -> void:
	if not can_save():
		super.save()
		return
	super.save()
	var traits: Dictionary = {}
	var effects: Dictionary = {}
	if game_state is GameStateClassic:
		for state: SoboState in game_state.get_sobo_states():
			traits[state.replay_id] = state.get_meta("special_sobo_trait", "")
			effects[state.replay_id] = state.get_meta("special_extra", {})
	SecureSave.save_var(SPECIAL_SAVE_PATH, {
		"run_id": game_state.run_id,
		"save_hash": FileAccess.get_md5(SAVE_PATH),
		"special": game_state.get_meta("special_sobo_run", false),
		"traits": traits,
		"effects": effects,
	})


func read_save() -> GameState:
	var state: GameState = super.read_save()
	var extra: Variant = SecureSave.load_var(SPECIAL_SAVE_PATH)
	if state == null or extra is not Dictionary:
		return state
	if extra.get("run_id") != state.run_id or extra.get("save_hash") != FileAccess.get_md5(SAVE_PATH):
		return state
	state.set_meta("special_sobo_run", extra.get("special", true))
	if state is GameStateClassic:
		for sobo: SoboState in state.get_sobo_states():
			sobo.set_meta("special_sobo_trait", extra.traits.get(sobo.replay_id, ""))
			sobo.set_meta("special_extra", extra.get("effects", {}).get(sobo.replay_id, {}))
	return state


func load() -> void:
	var session: int = GameModeManager.start_session + 1
	special_load_session = session
	await super.load()
	if special_load_session == session:
		special_load_session = 0
