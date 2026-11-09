extends "res://game_elements/sobo/sobo_manager.gd"


func create(size: int, pos_: Vector2 = Vector2.ZERO, replay_id: int = 0) -> Sobo:
	var sobo: Sobo = super.create(size, pos_, replay_id)
	var mod: Node = get_node("/root/SpecialSobo")
	if not mod.is_classic_run():
		return sobo
	mod.patch_script(sobo, mod.mod_dir().path_join("special_body.gd"))
	return sobo
