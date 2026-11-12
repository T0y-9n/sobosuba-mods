extends "res://game_elements/sobo/sobo.gd"


func apply_style() -> void:
	super.apply_style()
	var kind: String = str(get_meta("special_sobo_trait", ""))
	if kind == "darkmatter":
		var bg: Color = StyleManager.current_style.background_color
		color = Color(bg.r, bg.g, bg.b, 1.0)
		visual_color = color
		sobo_label.visible = false
		for suba: Suba in subas:
			suba.queue_redraw()


func _physics_process(dt: float) -> void:
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_body.physics") if mod != null else null
	super._physics_process(dt)


func fix_shape() -> void:
	var mod: Node = get_node_or_null("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_body.fix_shape") if mod != null else null
	if mod == null or not mod.is_classic_run():
		super.fix_shape()
		return
	set_meta("special_sobo_shape_repairs", int(get_meta("special_sobo_shape_repairs", 0)) + 1)
	mod.shape_repairs += 1
	super.fix_shape()


func capture_sobo_state() -> SoboState:
	var _diagnostic: RefCounted = get_node("/root/SpecialSobo").diagnostic_scope("special_body.capture")
	var state: SoboState = super.capture_sobo_state()
	if not get_node("/root/SpecialSobo").is_classic_run():
		return state
	state.set_meta("special_sobo_trait", get_meta("special_sobo_trait", ""))
	state.set_meta("special_sobo_run", Engine.get_meta("special_sobo_run", false))
	state.set_meta("special_extra", get_node("/root/SpecialSobo").capture_extra_state(self))
	return state


func apply_sobo_state(state: SoboState) -> void:
	var mod: Node = get_node("/root/SpecialSobo")
	var _diagnostic: RefCounted = mod.diagnostic_scope("special_body.restore")
	if not mod.is_classic_run():
		super.apply_sobo_state(state)
		return
	var kind: String = str(state.get_meta("special_sobo_trait", ""))
	mod.restore_extra_shape(self, state)
	super.apply_sobo_state(state)
	mod.restore_extra_state(self, state.get_meta("special_extra", {}))
	if kind == "small":
		set_meta("special_sobo_trait", kind)
		mod.finish_small_merge.call_deferred(weakref(self), mod.run_serial)
	elif kind != "":
		mod.add_marker(self, kind)
