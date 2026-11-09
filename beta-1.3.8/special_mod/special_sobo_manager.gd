extends "res://game_elements/sobo/sobo_manager.gd"


func _physics_process(dt: float) -> void:
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_sobo_manager.physics") if mod != null else null
	super._physics_process(dt)


func merge(group: MergeGroup) -> void:
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_sobo_manager.merge") if mod != null else null
	super.merge(group)


func create(size: int, pos_: Vector2 = Vector2.ZERO, replay_id: int = 0) -> Sobo:
	var _diagnostic: RefCounted = get_node("/root/SpecialSobo").diagnostic_scope("special_sobo_manager.create")
	var sobo: Sobo = super.create(size, pos_, replay_id)
	var mod: Node = get_node("/root/SpecialSobo")
	if not mod.is_classic_run():
		return sobo
	mod.patch_script(sobo, mod.mod_dir().path_join("special_body.gd"))
	return sobo
