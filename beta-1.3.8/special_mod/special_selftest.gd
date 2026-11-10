extends Node

var mod: Node
var lines: PackedStringArray = []
var failures:= 0
var checks:= 0


func _ready() -> void:
	run.call_deferred()


func check(condition: bool, name: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	lines.append(("OK " if condition else "FAIL ") + name)


func frames(count: int = 3) -> void:
	for frame: int in count:
		await get_tree().process_frame


func start_run() -> void:
	var mode: GameMode = GameModeManager.get_default_game_mode()
	GameModeManager.begin_run_for_mode(mode)
	await GameModeManager.start_game_mode(mode, false)


func run() -> void:
	for frame: int in 600:
		if mod.toggle != null:
			break
		await get_tree().process_frame
	check(mod.toggle != null, "settings toggle installed")
	if mod.toggle == null:
		finish()
		return
	var order: String = FileAccess.get_file_as_string(mod.mod_dir().path_join("selftest_order.txt"))
	var other: Node = mod.get_prime()
	check((other == null and order == "alone") or (other != null and ((other.get_index() < mod.get_index()) == (order == "prime-first"))), "bootstrap order: " + order)
	mod.settings.set_enabled(true)
	mod.forced_chance = 0.0
	var prime: Node = mod.get_prime()
	if prime != null:
		prime.set_prime_enabled(true)
		prime.forced_chance = 0.0
	await start_run()
	await frames()
	var mode:= GameModeManager.current_scene as SceneClassic
	check(mode != null, "real classic mode started")
	if mode == null:
		finish()
		return
	var direction: Vector2 = PhysicsServer2D.area_get_param(get_viewport().world_2d.space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR)
	check(not direction.is_zero_approx() and direction.y > 0.0, "puffy reads a nonzero downward gravity vector in classic mode")
	mode.set_physics_process(false)
	Dev.merging_enabled = false
	check(Engine.get_meta("special_sobo_run", false), "run metadata is set before any special spawn")
	check(AchievementTracker.disable_achievements, "special run disables achievements")
	check(ScoreManager.get_script().resource_path.ends_with("special_score_manager.gd"), "Steam entry points patched without replacing score logic")
	var hits:= 0
	for sample: int in 1000:
		if mod.roll_special():
			hits += 1
	check(hits == 0, "chance zero never assigns")
	mod.forced_chance = 1.0
	hits = 0
	for sample: int in 1000:
		if mod.roll_special():
			hits += 1
	check(hits == 1000, "chance one always assigns")
	mod.apply_run(false)
	check(not mod.roll_special(), "disabled run never assigns even at chance one")
	mod.apply_run(true)
	mod.forced_chance = -1.0
	check(is_equal_approx(mod.run_chance(), mod.tuning.CHANCES[mode.spawn_pool.current_spawn_pool.size() - 1]), "chance reads the real spawn pool")
	check(mod.tuning.CHANCES == [0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08], "seven specified spawn chances")
	var small_count:= 0
	var puffy_count:= 0
	var magnet_count:= 0
	var tier_zero_small:= 0
	for sample: int in 800:
		var roll: float = float(sample) / 800.0
		var kind: String = mod.pick_trait(4, roll)
		if kind == "small":
			small_count += 1
		elif kind == "puffy":
			puffy_count += 1
		elif kind == "magnet":
			magnet_count += 1
		if mod.pick_trait(1, roll) == "small":
			tier_zero_small += 1
	check(small_count == 300 and puffy_count == 300 and magnet_count == 200, "small puffy magnet use three-to-three-to-two weights")
	check(tier_zero_small == 0 and mod.pick_trait(1, 0.0) == "puffy", "tier zero excludes small and renormalizes weights")
	mod.forced_chance = 0.0
	await check_small(mode)
	await check_magnet(mode)
	mode = await check_saved_traits(mode)
	await check_merges(mode)
	await check_spawns(mode, prime)
	await check_scoring(prime)
	await check_settings(prime)
	check_settings_export()
	await check_missing_run_marker()
	lines.append("natural_specials=%d" % mod.natural_specials)
	finish()


func check_small(mode: SceneClassic) -> void:
	var original: SoboManager.SoboData = SoboManager.sobo_datas[32]
	var shape: SoboManager.SoboData = SoboManager.sobo_datas[4]
	var sobo: Sobo = SoboManager.create(32, Vector2(0, -100))
	mode.enter_emerging(sobo)
	sobo.freeze(true)
	sobo.set_velocity(Vector2(12, -34))
	sobo.merged = true
	var collision_layer: int = sobo.subas[0].collision_layer
	var collision_mask: int = sobo.subas[0].collision_mask
	var position: Vector2 = sobo.center
	var replacement: Sobo = mod.apply_trait(sobo, "small")
	check(replacement != sobo and sobo.is_queued_for_deletion(), "small replaces the original through SoboManager.create")
	check(replacement.data.size == original.size, "small preserves tier number and score")
	check(replacement.data.inner_circle == shape.inner_circle and replacement.data.outer_circle == shape.outer_circle and replacement.data.circular_positions == shape.circular_positions and replacement.data.suba_count == shape.suba_count and replacement.data.total_mass == shape.total_mass and replacement.data.extra_mass_ball_mass == shape.extra_mass_ball_mass, "small borrows the exact shape and mass three tiers down")
	check(SoboManager.sobo_datas[32] == original, "small leaves the game's tier table unchanged")
	check(replacement.center.is_equal_approx(position) and replacement.get_avg_velocity().is_equal_approx(Vector2(12, -34)) and replacement.subas[0].collision_layer == collision_layer and replacement.subas[0].collision_mask == collision_mask, "small transfers position velocity and collision filters")
	check(mode.sobos_emerging.has(replacement) and not mode.sobos_emerging.has(sobo) and replacement.merged and replacement.frozen, "small transfers role and merged and frozen state")
	check(mod.make_small_data(2).outer_circle == SoboManager.sobo_datas[1].outer_circle and mod.make_small_data(4).outer_circle == SoboManager.sobo_datas[1].outer_circle, "tiers one and two borrow tier zero")
	var marker: Node = replacement.get_node("SpecialMarker")
	check(marker.kind == "small" and marker.marker_color() == StyleManager.current_sobo_palette.color_for_size(32).lerp(StyleManager.current_style.background_color, mod.tuning.MARKER_COLOR_MIX), "small marker follows the game's palette and background")
	replacement.flashing = 1.0
	check(marker.marker_color() == Color.WHITE, "marker follows the merge flash")
	await frames()


func check_magnet(mode: SceneClassic) -> void:
	SoboManager.free_all()
	await frames()
	var magnet: Sobo = SoboManager.create(16, Vector2.ZERO)
	var target: Sobo = SoboManager.create(16, Vector2.ZERO)
	mode.enter_stack(magnet)
	mode.enter_stack(target)
	mod.apply_trait(magnet, "magnet")
	check(magnet.has_node("SpecialMarker") and magnet.get_node("SpecialMarker").kind == "magnet", "magnet has its marker")
	var marker: Node = magnet.get_node("SpecialMarker")
	check(marker.get_script().source_code.contains('elif kind == "magnet":') and marker.get_script().source_code.contains("draw_arc("), "magnet marker draws a curved U")
	var available: bool = mod.has_method("magnet_acceleration")
	check(available, "magnet acceleration is implemented")
	if available:
		var radius: float = magnet.data.outer_circle.radius
		magnet.circularize(Vector2.ZERO)
		target.circularize(Vector2(radius, 0))
		check(mod.magnet_acceleration(mode, magnet, target, 100.0).is_equal_approx(Vector2(-25, 0)), "magnet acceleration is maximum at the edge")
		target.circularize(Vector2(radius * 0.5, 0))
		check(mod.magnet_acceleration(mode, magnet, target, 100.0).is_equal_approx(Vector2(-25, 0)), "magnet acceleration is capped inside the edge")
		target.circularize(Vector2(radius * 2.0, 0))
		check(mod.magnet_acceleration(mode, magnet, target, 100.0).is_equal_approx(Vector2(-12.5, 0)), "magnet acceleration fades linearly")
		target.circularize(Vector2(radius * 3.0, 0))
		check(mod.magnet_acceleration(mode, magnet, target, 100.0).is_zero_approx(), "magnet acceleration is zero at range")
		target.circularize(Vector2(radius * 4.0, 0))
		check(mod.magnet_acceleration(mode, magnet, target, 100.0).is_zero_approx(), "magnet acceleration is zero outside range")
		target.circularize(Vector2(radius, 0))
		mod.apply_trait(target, "magnet")
		check(mod.magnet_acceleration(mode, magnet, target, 100.0).is_zero_approx(), "magnet does not pull magnets")
		var bar: Sobo = SoboManager.create(16, Vector2(radius, 0))
		mode.enter_emerging(bar)
		check(mod.magnet_acceleration(mode, magnet, bar, 100.0).is_zero_approx(), "magnet does not pull a bar sobo")
		var disappearing: Sobo = SoboManager.create(16, Vector2(radius, 0))
		mode.enter_stack(disappearing)
		disappearing.queue_free()
		check(mod.magnet_acceleration(mode, magnet, disappearing, 100.0).is_zero_approx(), "magnet does not pull a queued sobo")
	SoboManager.free_all()
	await frames()


func check_saved_traits(mode: SceneClassic) -> SceneClassic:
	for kind: String in ["small", "puffy", "magnet", ""]:
		var sobo: Sobo = SoboManager.create(32, Vector2(0, -150))
		mode.enter_stack(sobo)
		if kind != "":
			sobo = mod.apply_trait(sobo, kind)
		sobo.freeze(true)
		var state: SoboState = sobo.capture_sobo_state()
		var marked: bool = state.get_meta(mod.TRAIT_META, "missing") == kind and state.get_meta("special_sobo_run", false)
		check(marked, "saved state carries the mod trait and special run: " + kind)
		if not marked:
			continue
		var path: String = mod.mod_dir().path_join("selftest_state.tres")
		check(ResourceSaver.save(state, path) == OK, "trait state written through the real ResourceSaver: " + kind)
		var saved: SoboState = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var states: Array[SoboState] = [saved]
		var restored: Sobo = mode.spawn_from_states(states)[0]
		check(mod.trait_of(restored) == kind and restored.data.size == sobo.data.size and restored.data.outer_circle == sobo.data.outer_circle and restored.subas.size() == sobo.subas.size(), "real saved state restores the mod shape and trait: " + kind)
		if kind != "":
			check(restored.has_node("SpecialMarker"), "restored trait receives its marker: " + kind)
		await frames()
	SaveLoadManager.save()
	check(SaveLoadManager.game_state.get_meta("special_sobo_run", false), "the real game save records the special run even without a trait")
	mod.settings.set_enabled(false)
	await SaveLoadManager.load()
	await frames()
	var resumed:= GameModeManager.current_scene as SceneClassic
	resumed.set_physics_process(false)
	check(mod.run_special and Engine.get_meta("special_sobo_run", false), "resumed special run stays special when the next-run toggle is off")
	var kinds: Array[String] = []
	for sobo: Sobo in resumed.sobos_in_stack:
		kinds.append(mod.trait_of(sobo))
	check(kinds.has("small") and kinds.has("puffy") and kinds.has("magnet"), "the real SaveLoadManager restores all special traits")
	mod.settings.set_enabled(true)
	return resumed


func check_merges(mode: SceneClassic) -> void:
	for pair: Array in [["small", "", "small"], ["", "puffy", "puffy"], ["magnet", "", "magnet"], ["magnet", "puffy", ""], ["magnet", "magnet", ""], ["small", "small", ""], ["small", "puffy", ""], ["puffy", "puffy", ""], ["", "", ""]]:
		SoboManager.free_all()
		await frames()
		var left: Sobo = SoboManager.create(16, Vector2(-40, -100))
		var right: Sobo = SoboManager.create(16, Vector2(40, -100))
		mode.enter_stack(left)
		mode.enter_stack(right)
		if pair[0] != "":
			left = mod.apply_trait(left, pair[0])
		if pair[1] != "":
			right = mod.apply_trait(right, pair[1])
		left.freeze(true)
		right.freeze(true)
		await frames()
		var group:= SoboManager.MergeGroup.new()
		var contact:= SoboManager.MergeContact.new()
		contact.suba0 = left.subas[0]
		contact.suba1 = right.subas[0]
		group.sobos.assign([left, right])
		group.contacts.append(contact)
		SoboManager.merge(group)
		await frames()
		var results: Array[Sobo] = mode.sobos_in_stack
		var valid: bool = results.size() == 1 and mod.trait_of(results[0]) == pair[2]
		check(valid, "merge trait routing %s + %s -> %s" % [pair[0], pair[1], pair[2]])
		if valid and pair[2] == "small":
			check(results[0].data.outer_circle == SoboManager.sobo_datas[4].outer_circle and results[0].data.size == 32, "inherited small is reshaped after the real merge")
		if valid and pair[2] == "puffy":
			check(results[0].get_node("SpecialMarker").kind == "puffy", "inherited puffy receives its marker")


func check_spawns(mode: SceneClassic, prime: Node) -> void:
	SoboManager.free_all()
	await frames()
	mod.forced_chance = 1.0
	var safety: Sobo = mode.safety_spawn()
	check(safety != null, "real safety spawn created")
	await frames()
	if is_instance_valid(safety):
		check(mod.trait_of(safety) == "", "safety spawn is never assigned a fresh trait")
	var before: int = mod.natural_specials
	var fresh: Sobo = SoboManager.create(16, Vector2(0, -200))
	mode.enter_emerging(fresh)
	await frames()
	check(mod.natural_specials == before + 1, "a real new bar spawn gets one trait at chance one")
	if prime != null:
		SoboManager.free_all()
		await frames()
		prime.forced_chance = 1.0
		before = mod.natural_specials
		var ordinary: Sobo = SoboManager.create(16, Vector2(0, -200))
		var reference: WeakRef = weakref(ordinary)
		mode.enter_emerging(ordinary)
		await frames()
		check(reference.get_ref() == null and mod.natural_specials == before, "queued originals replaced by prime are ignored after one frame")
		var primes: Array = mode.sobos_emerging.filter(func(sobo: Sobo) -> bool: return prime.is_prime_sobo(sobo))
		check(primes.size() == 1 and mod.trait_of(primes[0]) == "", "real prime sobos never receive a trait")
		if primes.size() == 1:
			check(mod.apply_trait(primes[0], "puffy") == primes[0] and mod.trait_of(primes[0]) == "", "explicit trait assignment also excludes prime sobos")
		prime.forced_chance = 0.0
	lines.append("selftest_special_spawns=%d" % mod.natural_specials)
	mod.forced_chance = 0.0


func check_scoring(prime: Node) -> void:
	mod.apply_run(true)
	var pending: Array = ScoreManager._pending_uploads.duplicate(true)
	ScoreManager.upload_steam_score("highscore", 123)
	check(ScoreManager._pending_uploads == pending, "special run stops the Steam upload entry point")
	var published: int = ScoreManager._published_live_score
	ScoreManager.publish_live_score()
	check(ScoreManager._published_live_score == published, "special run stops the live friend score entry point")
	var count: int = ScoreManager.get_local_scores("highscore").size()
	ScoreManager.on_game_over()
	check(ScoreManager.get_local_scores("highscore").size() == count + 1, "game over still records the game's local score")
	if prime != null:
		prime.online.enabled = true
		prime.scores.on_game_over()
		mod.apply_run(false)
		await frames()
		check(prime.online.last_result.is_empty() and not prime.online.busy, "special run is not queued for the world ranking even if the next run is ordinary")
		var ordinary: Dictionary = await prime.online.submit_score(123, 60, 0.11)
		check(ordinary.get("no_steam", false) or ordinary.get("not_sent", false), "ordinary run retains the existing prime transport path")
		mod.apply_run(true)
		prime.online.enabled = false


func check_settings(prime: Node) -> void:
	var locale: String = TranslationServer.get_locale()
	var translated:= true
	for language: String in ["en", "ja", "de", "es", "it", "cs", "pl", "ru", "sr", "zh_CN", "zh_TW"]:
		TranslationServer.set_locale(language)
		mod.refresh_toggle()
		translated = translated and mod.toggle.label.text == mod.text.WORDS["special sobos"][language] and mod.toggle.tooltip_text == mod.text.WORDS["special sobos description"][language]
	TranslationServer.set_locale(locale)
	check(translated, "toggle and description follow all eleven real locales")
	mod.toggle.release_press.emit()
	check(not mod.settings.enabled and mod.run_special and Engine.get_meta("special_sobo_run", false), "mid-run toggle keeps the current run special")
	var settings_copy: RefCounted = load(mod.mod_dir().path_join("special_settings.gd")).new()
	settings_copy.path = mod.settings.path
	settings_copy.load_file()
	check(not settings_copy.enabled and mod.settings.path == mod.settings.SELFTEST_PATH, "toggle saves only to the self-test settings file")
	if prime != null:
		prime.set_prime_enabled(false)
	await start_run()
	await frames()
	check(not mod.run_special and Engine.has_meta("special_sobo_run") and not Engine.get_meta("special_sobo_run"), "next ordinary run resets the Engine metadata")
	check(not AchievementTracker.disable_achievements, "ordinary run restores achievements in either autoload order")
	SaveLoadManager.save()
	SaveLoadManager.game_state = SaveLoadManager.read_save()
	check(SaveLoadManager.has_save() and SaveLoadManager.game_state != null, "an older real ordinary save remains on disk and in the resource cache")
	mod.toggle.release_press.emit()
	check(mod.settings.enabled and not mod.run_special, "enabling the toggle also waits until the next run")
	await start_run()
	await frames()
	check(mod.run_special and AchievementTracker.disable_achievements, "next special run blocks achievements even with prime disabled")
	check(mod.run_special, "new special run ignores an older ordinary save unless load was called")
	SaveLoadManager.save()
	SaveLoadManager.game_state = SaveLoadManager.read_save()
	mod.toggle.release_press.emit()
	await start_run()
	await frames()
	check(not mod.run_special, "new ordinary run ignores an older special save unless load was called")


func check_settings_export() -> void:
	var available: bool = mod.settings.has_method("export_settings")
	check(available, "settings export is available")
	if not available:
		return
	var directory: String = mod.mod_dir().path_join("selftest_exports")
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "settings export self-test directory is created")
	var expected: Dictionary = {
		"enabled": mod.settings.enabled,
		"traits": mod.settings.traits.duplicate(true),
		"magnet_pull_multiplier": mod.settings.magnet_pull_multiplier,
		"parameters": mod.settings.numbers.duplicate(true),
	}
	var written: PackedStringArray = []
	var first: Dictionary = {}
	var second: Dictionary = {}
	for attempt: int in 20:
		var result: Dictionary = mod.settings.export_settings(mod.MOD_VERSION, directory)
		if not result.get("ok", false):
			first = result
			break
		var path: String = result.get("path", "")
		written.append(path)
		if not first.is_empty() and path == str(first.path).trim_suffix(".json") + "_2.json":
			second = result
			break
		first = result
	var parsed: Dictionary = {}
	if first.get("ok", false):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(first.path)) == OK and json.data is Dictionary:
			parsed = json.data
	var values_match: bool = (
		parsed.get("enabled") == expected.enabled
		and parsed.get("traits") == expected.traits
		and parsed.get("magnet_pull_multiplier") == expected.magnet_pull_multiplier
		and JSON.stringify(parsed.get("parameters")) == JSON.stringify(expected.parameters)
		and parsed.get("mod_version") == mod.MOD_VERSION
		and parsed.get("exported_at") is String
		and not str(parsed.get("exported_at")).is_empty()
	)
	check(values_match, "settings export reads back the current values and export metadata")
	check(first.get("ok", false) and second.get("ok", false) and first.path != second.path and FileAccess.file_exists(first.path) and FileAccess.file_exists(second.path), "two settings exports in the same second keep the earlier file")
	for path: String in written:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func check_missing_run_marker() -> void:
	for missing: String in ["file", "special"]:
		mod.settings.set_enabled(true)
		await start_run()
		await frames()
		SaveLoadManager.save()
		var removed: bool
		if missing == "file":
			removed = DirAccess.remove_absolute(SaveLoadManager.SPECIAL_SAVE_PATH) == OK
		else:
			var extra: Dictionary = SecureSave.load_var(SaveLoadManager.SPECIAL_SAVE_PATH)
			removed = extra.erase("special") and SecureSave.save_var(SaveLoadManager.SPECIAL_SAVE_PATH, extra) == OK
		mod.settings.set_enabled(false)
		await SaveLoadManager.load()
		await frames()
		check(removed and mod.run_special and Engine.get_meta("special_sobo_run", false) and AchievementTracker.disable_achievements, "missing " + missing + " marker keeps the resumed special run and achievements blocked with the toggle off")
		var pending: Array = ScoreManager._pending_uploads.duplicate(true)
		if mod.run_special:
			ScoreManager.upload_steam_score("highscore", 123)
		check(mod.run_special and ScoreManager._pending_uploads == pending, "missing " + missing + " marker keeps the resumed run out of the Steam upload queue")


func finish() -> void:
	lines.append("user_data_dir=%s" % OS.get_user_data_dir())
	lines.append("SPECIAL_DONE failures=%d checks=%d" % [failures, checks])
	var result:= FileAccess.open(mod.mod_dir().path_join("selftest_result.txt"), FileAccess.WRITE)
	result.store_string("\n".join(lines) + "\n")
	for line: String in lines:
		if not line.begins_with("user_data_dir="):
			mod.diagnostics.log(line)
	get_tree().quit(0 if failures == 0 else 1)
