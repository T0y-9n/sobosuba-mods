extends "res://main/score_manager.gd"


func _init() -> void:
	pass


func apply_run_scoring() -> void:
	super.apply_run_scoring()
	if Engine.get_meta("undo_run", false):
		disable_score_submitting = true


func submit_score(board: String, value: int):
	if Engine.get_meta("undo_run", false):
		print("score not submitted: undo mod")
		return
	super.submit_score(board, value)


func upload_steam_score(board: String, value: int) -> void:
	if Engine.get_meta("undo_run", false):
		print("score not submitted: undo mod")
		Engine.set_meta("undo_upload_refused", true)
		return
	super.upload_steam_score(board, value)


func publish_live_score() -> void:
	if Engine.get_meta("undo_run", false):
		return
	super.publish_live_score()
