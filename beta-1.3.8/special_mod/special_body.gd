extends "res://game_elements/sobo/sobo.gd"


func fix_shape() -> void:
	set_meta("special_sobo_shape_repairs", int(get_meta("special_sobo_shape_repairs", 0)) + 1)
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	if mod != null:
		mod.shape_repairs += 1
	super.fix_shape()


func capture_sobo_state() -> SoboState:
	var state: SoboState = super.capture_sobo_state()
	state.set_meta("special_sobo_trait", get_meta("special_sobo_trait", ""))
	state.set_meta("special_sobo_run", Engine.get_meta("special_sobo_run", false))
	state.set_meta("special_extra", get_node("/root/SpecialSobo").capture_extra_state(self))
	return state


func apply_sobo_state(state: SoboState) -> void:
	var mod: Node = get_node("/root/SpecialSobo")
	var kind: String = str(state.get_meta("special_sobo_trait", ""))
	super.apply_sobo_state(state)
	mod.restore_extra_state(self, state.get_meta("special_extra", {}))
	if kind == "small":
		set_meta("special_sobo_trait", kind)
		mod.finish_small_merge.call_deferred(weakref(self), mod.run_serial)
	elif kind != "":
		mod.add_marker(self, kind)
