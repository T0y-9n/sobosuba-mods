extends "res://main/score_manager.gd"


func _init() -> void:
	pass


func upload_steam_score(board: String, value: int) -> void:
	if Engine.get_meta("special_sobo_run", false):
		return
	super.upload_steam_score(board, value)


func publish_live_score() -> void:
	if Engine.get_meta("special_sobo_run", false):
		return
	super.publish_live_score()
