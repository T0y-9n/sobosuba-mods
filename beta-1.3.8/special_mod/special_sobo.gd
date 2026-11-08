extends Node

const TRAIT_META:= "special_sobo_trait"
const REPLACED_META:= "special_sobo_replaced"
const SAFETY_META:= "special_sobo_safety"
const MENU_WAIT_FRAMES:= 600

var tuning: Script
var settings: RefCounted
var text: Script
var extra_effects: Node
var include_base_traits:= true
var trait_weights: Dictionary = {}
var traits_grid: GridContainer
var toggle: SoboMenuButtonBool
var settings_screen: GameSettingsScreen
var settings_entry: SoboMenuButtonBool
var trait_toggles: Dictionary = {}
var run_special:= false
var forced_chance:= -1.0
var magnet_pull_multiplier:= 1.0
var magnet_pull_label: Label
var magnet_pull_input: LineEdit
var natural_specials:= 0
var small_data: Dictionary = {}
var resting_collision:= Vector2i(-1, -1)
var run_serial:= 0
var small_waiting: Dictionary = {}
var sticky_links: Dictionary = {}
var sticky_cooldowns: Dictionary = {}
var shape_repairs:= 0
var parameter_rows: Dictionary = {}
var number_inputs: Dictionary = {}
var page_picker: SoboMenuButtonEnum
var reset_button: SoboMenuButtonBool
var settings_page := 0


func _init() -> void:
	name = "SpecialSobo"


func get_prime() -> Node:
	for child: Node in get_tree().root.get_children():
		if child.get_script() is Script and child.get_script().resource_path == "user://prime_mod/prime_sobo.gd":
			return child
	return null


func mod_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir()


func _ready() -> void:
	tuning = load(mod_dir().path_join("special_tuning.gd"))
	settings = load(mod_dir().path_join("special_settings.gd")).new()
	text = load(mod_dir().path_join("special_text.gd"))
	Engine.set_meta("special_sobo_runtime", weakref(self))
	if include_base_traits:
		trait_weights = tuning.WEIGHTS.duplicate()
	else:
		settings.base_traits.clear()
	if FileAccess.file_exists(mod_dir().path_join("selftest.flag")):
		settings.path = settings.SELFTEST_PATH
	settings.load_file()
	magnet_pull_multiplier = settings.magnet_pull_multiplier
	install_score_guard()
	patch_script(SoboManager, mod_dir().path_join("special_sobo_manager.gd"))
	patch_script(SaveLoadManager, mod_dir().path_join("special_save_load.gd"))
	apply_run(settings.enabled)
	SignalBus.on_sobo_join_bar.connect(on_sobo_join_bar)
	SignalBus.on_safety_spawn.connect(on_safety_spawn)
	SignalBus.on_sobo_merge.connect(on_sobo_merge)
	finish_setup.call_deferred()


func register_base_traits() -> void:
	if include_base_traits:
		return
	include_base_traits = true
	trait_weights.merge(tuning.WEIGHTS)
	settings.base_traits.assign(settings.TRAITS)
	settings.load_file()
	install_trait_toggles()
	if page_picker != null:
		install_parameter_rows(toggle.get_parent(), Menu._0.game_settings_screen.show_instructions_control)
	refresh_toggle()


func register_extra_effects(controller: Node) -> void:
	extra_effects = controller
	settings.extra_traits.assign(controller.KINDS)
	settings.register_parameters(controller.Parameters.VALUES)
	for kind: String in controller.KINDS:
		trait_weights[kind] = 1.0
	settings.load_file()
	for sobo: Sobo in SoboManager.all_sobos:
		restore_extra_state(sobo, sobo.get_meta("special_extra", {}))
	install_trait_toggles()
	if page_picker != null:
		install_parameter_rows(toggle.get_parent(), Menu._0.game_settings_screen.show_instructions_control)
	refresh_toggle()


func capture_extra_state(sobo: Sobo) -> Dictionary:
	if is_instance_valid(extra_effects):
		return extra_effects.capture(sobo)
	return sobo.get_meta("special_extra", {}).duplicate(true)


func restore_extra_state(sobo: Sobo, saved: Variant) -> void:
	var data: Dictionary = saved.duplicate(true) if saved is Dictionary else {}
	if is_instance_valid(extra_effects):
		extra_effects.restore(sobo, data)
	elif data.get("lock") is Dictionary:
		var lock: Dictionary = data.lock
		if lock.get("previous") is bool:
			sobo.allow_merges = lock.previous
		data.erase("lock")
	sobo.set_meta("special_extra", data)


func finish_setup() -> void:
	SignalBus.on_game_mode_start.connect(on_game_mode_start)
	apply_run(settings.enabled)
	install_toggle()
	if FileAccess.file_exists(mod_dir().path_join("selftest.flag")):
		var suite: Node = load(mod_dir().path_join("special_selftest.gd")).new()
		suite.mod = self
		add_child(suite)


func install_score_guard() -> void:
	patch_script(ScoreManager, mod_dir().path_join("special_score_manager.gd"))


func patch_script(target: Node, path: String) -> void:
	var values: Dictionary = {}
	for prop: Dictionary in target.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[prop.name] = target.get(prop.name)
	target.set_script(load(path))
	for key: String in values:
		target.set(key, values[key])


func on_game_mode_start(mode: GameScene) -> void:
	run_serial += 1
	small_waiting.clear()
	sticky_links.clear()
	sticky_cooldowns.clear()
	natural_specials = 0
	var saved: GameState = SaveLoadManager.game_state
	var continued: bool = saved != null and SaveLoadManager.get("special_load_session") == GameModeManager.start_session
	apply_run(false if GameModeManager.run.replay else (bool(saved.get_meta("special_sobo_run", true)) if continued else settings.enabled))
	if mode is SceneClassic:
		mode.ready.connect(patch_mode.bind(weakref(mode)), CONNECT_ONE_SHOT)


func patch_mode(reference: WeakRef) -> void:
	var mode: SceneClassic = reference.get_ref()
	if mode != null and not mode.is_queued_for_deletion():
		patch_script(mode, mod_dir().path_join("special_classic.gd"))


func apply_run(value: bool) -> void:
	run_special = value
	Engine.set_meta("special_sobo_run", run_special)
	var prime: Node = get_prime()
	var prime_run: bool = prime != null and prime.run_prime
	AchievementTracker.disable_achievements = run_special or prime_run or not GameModeManager.run_is_ranked()


func run_chance() -> float:
	if forced_chance >= 0.0:
		return forced_chance
	var mode: GameScene = GameModeManager.current_scene
	var level: int = mode.spawn_pool.current_spawn_pool.size() if mode != null and mode.spawn_pool != null else 1
	return settings.number("chance_" + str(clampi(level, 1, 7))) / 100.0


func roll_special() -> bool:
	return run_special and randf() < run_chance()


func pick_trait(size: int, roll: float = randf()) -> String:
	var total:= 0.0
	for kind: String in trait_weights:
		if not settings.trait_enabled(kind):
			continue
		if kind != "small" or size > 1:
			total += weight_of(kind)
	var remaining: float = roll * total
	for kind: String in trait_weights:
		if not settings.trait_enabled(kind):
			continue
		if kind == "small" and size == 1:
			continue
		remaining -= weight_of(kind)
		if remaining < 0.0:
			return kind
	return ""


func weight_of(kind: String) -> float:
	return settings.number("weight_" + kind)


func trait_of(sobo: Sobo) -> String:
	return str(sobo.get_meta(TRAIT_META, ""))


func on_safety_spawn(sobo: Sobo) -> void:
	sobo.set_meta(SAFETY_META, true)


func on_sobo_join_bar(sobo: Sobo) -> void:
	if not run_special or sobo.merged or not SoboManager.power_of_two_sizes.has(sobo.data.size) or trait_of(sobo) != "":
		return
	var mode:= GameModeManager.current_scene as SceneClassic
	if mode == null or not mode.sobos_emerging.has(sobo):
		return
	consider_spawn(weakref(sobo), mode, run_serial)


func consider_spawn(reference: WeakRef, mode: SceneClassic, serial: int) -> void:
	await get_tree().process_frame
	var sobo: Sobo = reference.get_ref()
	if serial != run_serial or not is_instance_valid(mode) or GameModeManager.current_scene != mode:
		return
	if sobo == null or sobo.is_queued_for_deletion() or sobo.get_meta(REPLACED_META, false) or sobo.get_meta(SAFETY_META, false):
		return
	if not SoboManager.power_of_two_sizes.has(sobo.data.size) or sobo.merged or trait_of(sobo) != "" or not mode.is_on_bar(sobo):
		return
	if roll_special():
		var kind: String = pick_trait(sobo.data.size)
		if kind != "":
			apply_trait(sobo, kind)
			natural_specials += 1


func apply_trait(sobo: Sobo, kind: String) -> Sobo:
	if kind == "" or not SoboManager.power_of_two_sizes.has(sobo.data.size) or (kind == "small" and sobo.data.size == 1):
		return sobo
	if kind == "small":
		sobo = replace_small(sobo)
	elif sobo.get_script().resource_path != mod_dir().path_join("special_body.gd"):
		patch_script(sobo, mod_dir().path_join("special_body.gd"))
	add_marker(sobo, kind)
	return sobo


func add_marker(sobo: Sobo, kind: String) -> void:
	sobo.set_meta(TRAIT_META, kind)
	var marker: Node2D = load(mod_dir().path_join("special_marker.gd")).new()
	marker.name = "SpecialMarker"
	marker.sobo = sobo
	marker.kind = kind
	marker.tuning = tuning
	sobo.add_child(marker)


func make_small_data(size: int) -> SoboManager.SoboData:
	if small_data.has(size):
		return small_data[size]
	var shape: SoboManager.SoboData = SoboManager.get_sobo_data(maxi(1, size >> int(settings.number("small_tier_drop"))))
	var data:= SoboManager.SoboData.new()
	for prop: Dictionary in shape.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data.set(prop.name, shape.get(prop.name))
	data.size = size
	small_data[size] = data
	return data


func replace_small(sobo: Sobo) -> Sobo:
	return replace_shape(sobo, make_small_data(sobo.data.size), "small")


func replace_shape(sobo: Sobo, data: SoboManager.SoboData, kind: String) -> Sobo:
	sobo.read_body_states()
	var size: int = sobo.data.size
	var original: SoboManager.SoboData = SoboManager.sobo_datas[size]
	SoboManager.sobo_datas[size] = data
	var replacement: Sobo = SoboManager.create(size, sobo.center, sobo.replay_id)
	SoboManager.sobo_datas[size] = original
	replacement.set_meta(TRAIT_META, kind)
	for suba: Suba in replacement.subas:
		suba.collision_layer = sobo.subas[0].collision_layer
		suba.collision_mask = sobo.subas[0].collision_mask
	replacement.extra_mass_ball.collision_layer = sobo.extra_mass_ball.collision_layer
	replacement.extra_mass_ball.collision_mask = sobo.extra_mass_ball.collision_mask
	replacement.freeze(sobo.frozen)
	replacement.set_velocity(sobo.get_avg_velocity())
	replacement.extra_mass_ball.linear_velocity = sobo.extra_mass_ball.linear_velocity
	replacement.merged = sobo.merged
	replacement.merged_this_frame = sobo.merged_this_frame
	replacement.flashing = sobo.flashing
	replacement.flash_elapsed = sobo.flash_elapsed
	replacement.sobo_label.ang_vel = sobo.sobo_label.ang_vel
	replacement.read_body_states()
	var mode:= GameModeManager.current_scene as SceneClassic
	if mode != null:
		var emerging: bool = mode.sobos_emerging.has(sobo)
		var selectable: bool = mode.sobos_selectable.has(sobo)
		var stacked: bool = mode.sobos_in_stack.has(sobo)
		mode.remove_from_role_lists(sobo)
		if emerging:
			mode.enter_emerging(replacement)
		elif selectable:
			mode.enter_selectable(replacement)
		elif stacked:
			mode.enter_stack(replacement)
		for key: String in ["hovered_sobo", "previously_hovered_sobo", "launching_sobo"]:
			if mode.get(key) == sobo:
				mode.set(key, replacement)
	replacement.allow_merges = sobo.allow_merges
	sobo.set_meta(REPLACED_META, true)
	forget_sticky(sobo)
	sobo.disable_collisions()
	SoboManager.all_sobos.erase(sobo)
	sobo.queue_free()
	return replacement


func on_sobo_merge(old0: Sobo, old1: Sobo, result: Sobo) -> void:
	forget_sticky(old0)
	forget_sticky(old1)
	var trait0: String = trait_of(old0)
	var trait1: String = trait_of(old1)
	if trait0.is_empty() == trait1.is_empty():
		return
	var kind: String = trait0 if not trait0.is_empty() else trait1
	if kind == "small":
		result.set_meta(TRAIT_META, kind)
		finish_small_merge.call_deferred(weakref(result), run_serial)
	else:
		apply_trait(result, kind)
		restore_extra_state(result, capture_extra_state(old0 if trait0 != "" else old1))


func finish_small_merge(reference: WeakRef, serial: int) -> void:
	var result: Sobo = reference.get_ref()
	if serial != run_serial or result == null or result.is_queued_for_deletion() or result.get_meta(REPLACED_META, false):
		return
	var mode:= GameModeManager.current_scene as SceneClassic
	if (mode != null and mode.is_on_bar(result)) or at_rest(result):
		apply_trait(result, "small")
	else:
		small_waiting[result.get_instance_id()] = reference


func settle_smalls(mode: SceneClassic) -> void:
	for id: int in small_waiting.keys():
		var sobo: Sobo = small_waiting[id].get_ref()
		if sobo == null or sobo.is_queued_for_deletion() or sobo.get_meta(REPLACED_META, false) or trait_of(sobo) != "small":
			small_waiting.erase(id)
			continue
		if mode.is_on_bar(sobo) or (mode.sobos_in_stack.has(sobo) and at_rest(sobo)):
			small_waiting.erase(id)
			apply_trait(sobo, "small")


func _physics_process(delta: float) -> void:
	if not run_special or SpaceGravity._0 == null:
		return
	var mode:= GameModeManager.current_scene as SceneClassic
	if mode == null:
		return
	var gravity: SpaceGravity = SpaceGravity._0
	settle_smalls(mode)
	update_sticky(mode, delta, gravity.gravity)
	if is_instance_valid(extra_effects):
		extra_effects.tick(mode, delta, gravity.gravity)
	var stack: Array[Sobo] = live_stack(mode)
	var direction: Vector2 = PhysicsServer2D.area_get_param(get_viewport().world_2d.space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR)
	for sobo: Sobo in stack:
		if trait_of(sobo) == "puffy":
			sobo.apply_uniform_acceleration(-direction * gravity.gravity * (1.0 - settings.number("puffy_gravity_ratio")))
		elif trait_of(sobo) == "magnet":
			for target: Sobo in stack:
				var acceleration: Vector2 = magnet_acceleration(mode, sobo, target, gravity.gravity)
				if acceleration != Vector2.ZERO:
					target.apply_uniform_acceleration(acceleration)



func at_rest(sobo: Sobo) -> bool:
	if resting_collision.x < 0:
		var probe: Node = sobo.suba_ps.instantiate()
		resting_collision = Vector2i(probe.collision_layer, probe.collision_mask)
		probe.free()
	for suba: Suba in sobo.subas:
		if suba.collision_layer != resting_collision.x or suba.collision_mask != resting_collision.y:
			return false
	return true


func live_stack(mode: SceneClassic) -> Array[Sobo]:
	var live: Array[Sobo] = []
	for entry: Variant in mode.sobos_in_stack:
		if is_instance_valid(entry) and not entry.is_queued_for_deletion():
			live.append(entry)
	return live


func forget_sticky(sobo: Sobo) -> void:
	for records: Dictionary in [sticky_links, sticky_cooldowns]:
		records.erase(sobo)
		for owner: Variant in records.keys():
			records[owner].erase(sobo)


func update_sticky(mode: SceneClassic, delta: float, gravity: float) -> void:
	for records: Dictionary in [sticky_links, sticky_cooldowns]:
		for owner: Variant in records.keys():
			if not is_instance_valid(owner) or owner.is_queued_for_deletion() or not mode.sobos_in_stack.has(owner):
				records.erase(owner)
				continue
			for target: Variant in records[owner].keys():
				if not is_instance_valid(target) or target.is_queued_for_deletion() or not mode.sobos_in_stack.has(target):
					records[owner].erase(target)
	for owner: Sobo in sticky_cooldowns:
		for target: Sobo in sticky_cooldowns[owner].keys():
			sticky_cooldowns[owner][target] -= delta
			if sticky_cooldowns[owner][target] <= 0.0:
				sticky_cooldowns[owner].erase(target)
	for owner: Sobo in live_stack(mode):
		var kind: String = trait_of(owner)
		if kind != "sticky" and kind != "magnet":
			continue
		if not sticky_links.has(owner):
			sticky_links[owner] = {}
		if not sticky_cooldowns.has(owner):
			sticky_cooldowns[owner] = {}
		var links: Dictionary = sticky_links[owner]
		var cooldowns: Dictionary = sticky_cooldowns[owner]
		while links.size() > int(settings.number("hold_limit")):
			links.erase(links.keys().back())
		for suba: Variant in owner.subas:
			if not is_instance_valid(suba):
				continue
			for other: Variant in suba.contacting_other_subas:
				if not is_instance_valid(other):
					continue
				var target: Variant = other.sobo
				if not is_instance_valid(target) or target == owner or target.is_queued_for_deletion() or not mode.sobos_in_stack.has(target) or trait_of(target) == kind or links.has(target) or cooldowns.has(target):
					continue
				if kind == "sticky":
					target.add_velocity((target.center - owner.center).normalized() * settings.number("throw_speed"))
					cooldowns[target] = settings.number("throw_cooldown")
				elif links.size() < int(settings.number("hold_limit")):
					links[target] = true
		for target: Sobo in links.keys():
			var direction: Vector2 = (owner.center - target.center).normalized()
			target.apply_uniform_acceleration(direction * gravity * settings.number("hold_strength"))


func magnet_acceleration(mode: SceneClassic, magnet: Sobo, target: Sobo, gravity: float) -> Vector2:
	if not is_instance_valid(target) or target == magnet or target.is_queued_for_deletion() or not mode.sobos_in_stack.has(target):
		return Vector2.ZERO
	var offset: Vector2 = magnet.center - target.center
	var radius: float = magnet.data.outer_circle.radius
	var distance: float = offset.length()
	var reach: float = settings.number("magnet_range")
	var strength: float = clampf((reach * radius - distance) / ((reach - 1.0) * radius), 0.0, 1.0)
	var multiplier: float = -1.0 if trait_of(target) == "magnet" else magnet_pull_multiplier
	return offset.normalized() * gravity * settings.number("magnet_strength") * strength * multiplier


func install_toggle() -> void:
	for frame: int in MENU_WAIT_FRAMES:
		if Menu._0 != null and Menu._0.is_node_ready() and Menu._0.game_settings_screen != null:
			break
		await get_tree().process_frame
	if Menu._0 == null or Menu._0.game_settings_screen == null:
		push_warning("[special_sobo] game settings screen not found")
		return
	var model: SoboMenuButtonBool = Menu._0.game_settings_screen.show_instructions_control
	var original: GameSettingsScreen = Menu._0.game_settings_screen
	settings_screen = original.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	for prop: Dictionary in original.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			settings_screen.set(prop.name, value_for_copy(original.get(prop.name), original, settings_screen))
	var list: Node = settings_screen.show_instructions_control.get_parent()
	for control: Node in list.get_children():
		if control == settings_screen.description_label or control.is_ancestor_of(settings_screen.description_label):
			continue
		list.remove_child(control)
		control.queue_free()
	patch_script(settings_screen, mod_dir().path_join("special_settings_screen.gd"))
	settings_screen.name = "SpecialSobosSettings"
	var parent: MenuScreen = Menu._0.settings_mobile_screen if OS.has_feature("mobile") else original
	settings_screen.parent_screen = parent
	settings_screen.description_label.text = ""
	settings_screen.hide()
	Menu._0.add_child(settings_screen)
	Menu._0.register_screen("special_sobos", settings_screen)
	settings_entry = copy_toggle(model)
	settings_entry.name = "SpecialSobosSettingsEntry"
	settings_entry.bool_circles.hide()
	settings_entry.release_press.connect(open_settings)
	var entry_model: SoboMenuButtonBool = parent.get("show_instructions_control")
	entry_model.add_sibling(settings_entry)
	if parent == Menu._0.settings_mobile_screen:
		for child: Node in entry_model.get_parent().get_children():
			if child is HSeparator:
				(child as HSeparator).add_theme_constant_override("separation", 4)
	var button: SoboMenuButtonBool = copy_toggle(model)
	button.name = "SpecialSobos"
	button.release_press.connect(on_toggle_pressed)
	list.add_child(button)
	toggle = button
	settings_screen.first_button_hovered = toggle
	traits_grid = GridContainer.new()
	traits_grid.name = "SpecialSoboTraits"
	traits_grid.columns = 2
	traits_grid.add_theme_constant_override("h_separation", 8)
	traits_grid.add_theme_constant_override("v_separation", 0)
	button.add_sibling(traits_grid)
	install_trait_toggles()
	install_parameter_pages(list, original.jumpscare_control, model)
	original.resized.connect(reserve_description_space, CONNECT_DEFERRED)
	settings_screen.resized.connect(reserve_description_space, CONNECT_DEFERRED)
	refresh_toggle()


func open_settings() -> void:
	Menu._0.change_screen(settings_screen)


func reserve_description_space() -> void:
	# Hovering must not resize the centered list and move the next hit target.
	for screen: GameSettingsScreen in [Menu._0.game_settings_screen, settings_screen]:
		var label: Label = screen.description_label
		if label.size.x <= 0.0:
			continue
		var measure: Label = label.duplicate(Node.DUPLICATE_SCRIPTS)
		measure.hide()
		label.add_child(measure)
		measure.size = Vector2(label.size.x, 0.0)
		var height: float = label.custom_minimum_size.y
		for button: SoboButton in SoboButton.list:
			if screen.is_ancestor_of(button):
				measure.text = tr(button.tooltip_text)
				height = maxf(height, measure.get_minimum_size().y)
		label.custom_minimum_size.y = height
		measure.free()


func install_trait_toggles() -> void:
	if traits_grid == null:
		return
	var model: SoboMenuButtonBool = Menu._0.game_settings_screen.show_instructions_control
	for kind: String in settings.trait_kinds():
		if trait_toggles.has(kind):
			continue
		var trait_button: SoboMenuButtonBool = copy_toggle(model)
		trait_button.name = "SpecialSobos" + kind.capitalize()
		trait_button.custom_minimum_size.x = 0.0
		trait_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trait_button.release_press.connect(on_trait_toggle_pressed.bind(kind))
		traits_grid.add_child(trait_button)
		trait_toggles[kind] = trait_button


func install_magnet_pull_input(previous: Node, model: SoboMenuButtonBool) -> void:
	var row: SoboMenuButtonBool = copy_toggle(model)
	row.name = "MagnetPullRow"
	row.bool_circles.hide()
	row.pointer_hoverable = false
	row.gamepad_hoverable = false
	magnet_pull_label = row.label
	magnet_pull_input = LineEdit.new()
	magnet_pull_input.name = "MagnetPullInput"
	magnet_pull_input.custom_minimum_size = Vector2(128, 48)
	magnet_pull_input.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	magnet_pull_input.offset_left = -144.0
	magnet_pull_input.offset_right = -16.0
	magnet_pull_input.offset_top = 0.0
	magnet_pull_input.offset_bottom = 48.0
	magnet_pull_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	magnet_pull_input.select_all_on_focus = true
	magnet_pull_input.add_theme_color_override("font_color", model.label.get_theme_color("font_color"))
	magnet_pull_input.add_theme_font_size_override("font_size", model.label.get_theme_font_size("font_size"))
	var transparent:= StyleBoxEmpty.new()
	for part: String in ["normal", "focus", "read_only"]:
		magnet_pull_input.add_theme_stylebox_override(part, transparent)
	magnet_pull_input.text_submitted.connect(on_magnet_pull_submitted)
	magnet_pull_input.focus_exited.connect(on_magnet_pull_focus_exited)
	magnet_pull_input.focus_entered.connect(on_magnet_pull_focus_entered)
	row.add_child(magnet_pull_input)
	row.highlight_elements.append(magnet_pull_input)
	previous.add_sibling(row)


func install_parameter_pages(list: Node, enum_model: SoboMenuButtonEnum, model: SoboMenuButtonBool) -> void:
	page_picker = copy_menu_button(enum_model) as SoboMenuButtonEnum
	page_picker.name = "SpecialSettingsPage"
	page_picker.release_press.connect(cycle_settings_page)
	list.add_child(page_picker)
	list.move_child(page_picker, toggle.get_index())
	settings_screen.first_button_hovered = page_picker
	install_parameter_rows(list, model)
	reset_button = copy_toggle(model)
	reset_button.name = "ResetSpecialTuning"
	reset_button.bool_circles.hide()
	reset_button.release_press.connect(reset_tuning)
	list.add_child(reset_button)


func install_parameter_rows(list: Node, model: SoboMenuButtonBool) -> void:
	for key: String in settings.parameter_values:
		if parameter_rows.has(key) or not parameter_active(key):
			continue
		var row: SoboMenuButtonBool = copy_toggle(model)
		row.name = "Parameter_" + key
		row.bool_circles.hide()
		row.pointer_hoverable = false
		row.gamepad_hoverable = false
		var input := LineEdit.new()
		input.name = "NumberInput"
		input.custom_minimum_size = Vector2(128, 48)
		input.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		input.offset_left = -144.0
		input.offset_right = -16.0
		input.offset_top = 0.0
		input.offset_bottom = 48.0
		input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		input.select_all_on_focus = true
		input.add_theme_color_override("font_color", model.label.get_theme_color("font_color"))
		input.add_theme_font_size_override("font_size", model.label.get_theme_font_size("font_size"))
		var transparent := StyleBoxEmpty.new()
		for part: String in ["normal", "focus", "read_only"]:
			input.add_theme_stylebox_override(part, transparent)
		input.text_submitted.connect(on_number_submitted.bind(key))
		input.focus_exited.connect(on_number_focus_exited.bind(key))
		input.focus_entered.connect(on_number_focus_entered.bind(key))
		row.add_child(input)
		row.highlight_elements.append(input)
		row.label.add_theme_font_size_override("font_size", 20)
		list.add_child(row)
		parameter_rows[key] = row
		number_inputs[key] = input
		if key == "magnet_pull_multiplier":
			magnet_pull_input = input
			magnet_pull_label = row.label
	if reset_button != null:
		list.move_child(reset_button, list.get_child_count() - 1)


func parameter_active(key: String) -> bool:
	return key.begins_with("chance_") or include_base_traits and settings.Parameters.VALUES.has(key) or extra_effects != null and extra_effects.Parameters.VALUES.has(key)


func parameter_groups() -> Array[String]:
	var groups: Array[String] = ["kinds"]
	for key: String in settings.parameter_values:
		var group: String = settings.parameter_values[key][4]
		if parameter_active(key) and group not in groups:
			groups.append(group)
	return groups


func cycle_settings_page() -> void:
	settings_page = (settings_page + 1) % parameter_groups().size()
	refresh_toggle()


func on_number_focus_entered(key: String) -> void:
	SoboButton.currently_hovered = null
	settings_screen.description_label.text = number_inputs[key].tooltip_text


func on_number_focus_exited(key: String) -> void:
	on_number_submitted(number_inputs[key].text, key)


func on_number_submitted(value: String, key: String) -> void:
	if key == "magnet_pull_multiplier":
		on_magnet_pull_submitted(value)
		return
	var number: String = value.strip_edges()
	var input: LineEdit = number_inputs[key]
	var previous: float = settings.number(key)
	if not number.is_valid_float() or not settings.valid_number(key, number.to_float()):
		input.text = str(previous)
		settings_screen.description_label.text = input.tooltip_text
		return
	if not settings.set_number(key, number.to_float()):
		input.text = str(previous)
		settings_screen.description_label.text = text.get_text("magnet pull save failed")
		return
	apply_tuning(key)
	input.text = str(settings.number(key))


func apply_tuning(key: String = "") -> void:
	magnet_pull_multiplier = settings.magnet_pull_multiplier
	if is_instance_valid(extra_effects):
		extra_effects.apply_tuning(key)
	if key == "small_tier_drop" or key.is_empty():
		small_data.clear()
		for sobo: Sobo in SoboManager.all_sobos.duplicate():
			if is_instance_valid(sobo) and not sobo.is_queued_for_deletion() and trait_of(sobo) == "small":
				apply_trait(sobo, "small")
	if key == "throw_cooldown" or key.is_empty():
		for owner: Sobo in sticky_cooldowns:
			for target: Sobo in sticky_cooldowns[owner]:
				sticky_cooldowns[owner][target] = minf(sticky_cooldowns[owner][target], settings.number("throw_cooldown"))


func reset_tuning() -> void:
	if not settings.reset_numbers(number_inputs.keys()):
		settings_screen.description_label.text = text.get_text("magnet pull save failed")
		return
	apply_tuning()
	refresh_toggle()


func refresh_parameters() -> void:
	if page_picker == null:
		return
	var groups: Array[String] = parameter_groups()
	settings_page = clampi(settings_page, 0, groups.size() - 1)
	page_picker.show()
	reset_button.show()
	var japanese: bool = TranslationServer.get_locale().begins_with("ja")
	var group: String = groups[settings_page]
	page_picker.label.text = "設定ページ" if japanese else "Settings page"
	page_picker.set_value(settings.Parameters.group_label(group) if group in settings.Parameters.GROUPS else extra_effects.Parameters.group_label(group))
	page_picker.tooltip_text = "押すと次の設定ページへ" if japanese else "Press to open the next settings page."
	toggle.visible = group == "kinds"
	traits_grid.visible = group == "kinds"
	reset_button.label.text = "数値を初期値に戻す" if japanese else "Reset tuning to defaults"
	reset_button.tooltip_text = "数値を保存して今の盤面に反映。種類の切替は維持します。" if japanese else "Save and apply the default numbers now. Kind switches are kept."
	for key: String in parameter_rows:
		var row: SoboMenuButtonBool = parameter_rows[key]
		var spec: Array = settings.parameter_values[key]
		row.visible = spec[4] == group and parameter_active(key)
		row.label.text = spec[6 if japanese else 5]
		var input: LineEdit = number_inputs[key]
		input.tooltip_text = ("範囲 %s〜%s。%s入力後Enterか欄を離れる操作で保存・即時反映。" if japanese else "Range %s to %s. %sPress Enter or leave the field to save and apply now.") % [str(spec[1]), str(spec[2]), ("整数のみ。" if japanese else "Whole numbers only. ") if spec[3] else ""]
		if not input.has_focus():
			input.text = str(settings.number(key))


func on_magnet_pull_focus_entered() -> void:
	SoboButton.currently_hovered = null


func on_magnet_pull_focus_exited() -> void:
	on_magnet_pull_submitted(magnet_pull_input.text)


func on_magnet_pull_submitted(value: String) -> void:
	var number: String = value.strip_edges()
	if not number.is_valid_float() or not settings.valid_magnet_pull(number.to_float()):
		magnet_pull_input.text = str(magnet_pull_multiplier)
		magnet_pull_input.tooltip_text = text.get_text("magnet pull invalid")
		return
	if not settings.set_magnet_pull_multiplier(number.to_float()):
		magnet_pull_input.text = str(magnet_pull_multiplier)
		magnet_pull_input.tooltip_text = text.get_text("magnet pull save failed")
		return
	magnet_pull_multiplier = settings.magnet_pull_multiplier
	magnet_pull_input.text = str(magnet_pull_multiplier)
	magnet_pull_input.tooltip_text = text.get_text("magnet pull description")


func copy_toggle(model: SoboMenuButtonBool) -> SoboMenuButtonBool:
	return copy_menu_button(model) as SoboMenuButtonBool


func copy_menu_button(model: SoboMenuButton) -> SoboMenuButton:
	var button: SoboMenuButton = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	for prop: Dictionary in model.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			button.set(prop.name, value_for_copy(model.get(prop.name), model, button))
	return button


func value_for_copy(value: Variant, original: Node, copy: Node) -> Variant:
	if value is Node:
		if value == original:
			return copy
		if original.is_ancestor_of(value):
			return copy.get_node_or_null(original.get_path_to(value))
	if value is Array:
		var mapped: Array = value.duplicate()
		for index: int in mapped.size():
			mapped[index] = value_for_copy(mapped[index], original, copy)
		return mapped
	return value


func on_toggle_pressed() -> void:
	settings.set_enabled(not settings.enabled)
	refresh_toggle()


func on_trait_toggle_pressed(kind: String) -> void:
	settings.set_trait(kind, not settings.trait_enabled(kind))
	refresh_toggle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh_toggle()


func refresh_toggle() -> void:
	if toggle == null:
		return
	toggle.label.text = text.get_text("special sobos") if include_base_traits else extra_effects.get_text("extra sobos")
	if settings_entry != null:
		settings_entry.label.text = toggle.label.text
		settings_entry.tooltip_text = text.get_text("special sobos description")
		settings_screen.side_title_text = toggle.label.text
	toggle.tooltip_text = text.get_text("special sobos description") if extra_effects == null else extra_effects.get_text("special sobos description")
	toggle.bool_circles.visible = settings.enabled
	for kind: String in trait_toggles:
		var button: SoboMenuButtonBool = trait_toggles[kind]
		if not is_instance_valid(button):
			continue
		var extra: bool = extra_effects != null and kind in extra_effects.KINDS
		button.label.text = extra_effects.get_text("trait " + kind) if extra else text.get_text("trait " + kind)
		button.tooltip_text = extra_effects.get_text("description " + kind) if extra else text.get_text("trait description")
		button.bool_circles.visible = settings.trait_enabled(kind)
	if is_instance_valid(magnet_pull_input):
		if not magnet_pull_input.has_focus():
			magnet_pull_input.text = str(magnet_pull_multiplier)
	refresh_parameters()
	reserve_description_space.call_deferred()
