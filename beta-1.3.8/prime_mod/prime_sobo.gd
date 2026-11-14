extends Node
## Prime sobos for sobosuba (Godot 4.7.2).
## Primes never merge with anything, except a pair of primes whose sum is a power of two
## (3+5=8, 3+13=16, 5+11=16, 13+19=32), which merges into the regular sobo of that value.
## A 7 merges only with another 7 into 14, and that chain doubles through 458752. It does not score.
## Loaded as an autoload through override.cfg next to sobosuba.exe.
## In a prime run, Steam leaderboard uploads, live friend scores and achievements are off.
## "prime balls" in settings -> game turns prime mode off (the game as it is) from the next run.

const MOD_VERSION:= preload("prime_diagnostics.gd").MOD_VERSION
const MOD_TAG:= preload("prime_diagnostics.gd").MOD_TAG
## SoboManager builds the data for the sizes 2^0 .. 2^19 itself: twenty powers of two.
const EXPECTED_POWER_OF_TWO_SIZES:= 20
const PRIMES: Array[int] = [3, 5, 11, 13, 19, 7]
const PRIME_WEIGHTS: Array[float] = [4.0, 6.0, 2.0, 2.0, 1.0, 4.0]
const SEVEN_CHAIN_MAX := 458752
const PRIME_COLOR:= Color(0.62, 0.62, 0.68)

var replaced: Dictionary[int, bool] = { }
var enabled:= false
var diagnostics: RefCounted = null
var diagnostics_suspended := false
var selftest:= false
## Self-test only: noguard.flag turns off the same-size guard to prove the 3+3 check can fail.
var guard_disabled_for_test:= false
var natural_replacements:= 0
var scores: Node = null
var online: Node = null
## Self-test only: a fixed chance for the prime roll. Below zero the prime level decides (spec §10).
var forced_chance:= -1.0
## The prime level of a run (prime_level.gd) and its line under the game's score.
var prime_level: Script = null
var level_label: Label = null
var level_layout: Array = []
## The prime scores screen (a second instance of the game's scores_screen.tscn) and the game's own.
## Untyped: the prime script adds members (scores, heading, select_source...) that ScoresScreen lacks.
var scores_screen = null
var original_scores_screen: ScoresScreen = null
## Prime mode on/off (prime_settings.gd, spec §7) and the "prime balls" switch on the game's
## settings -> game screen.
var prime_settings: RefCounted = null
## The mod's words in the game's language (prime_text.gd).
var prime_text: Script = null
var prime_toggle: SoboMenuButtonBool = null
## The "send scores" switch (spec §8), right under prime balls: whether a run's score goes to the world.
var send_toggle: SoboMenuButtonBool = null
var screenshot_toggle: SoboMenuButtonBool = null
## The mode of the run being played: prime balls, no Steam upload / live score / achievements.
var run_prime:= false
var game_mode_scope: Script = null

const SCORES_SCREEN_SCENE:= "res://ui/menu/screens/scores_screen/scores_screen.tscn"
const TOGGLE_TEXT:= "prime balls"
const SEND_TEXT:= "send scores"
const SCREENSHOT_TEXT:= "save screenshots"
const MENU_WAIT_FRAMES:= 600
## ScoresScreen members that the screen fills in while it runs (rows made in _ready, paging state).
## They are not copied from the game's live screen: the copy builds its own rows and starts at its
## own defaults (copying the row array would turn every row into null).
const SCORES_SCREEN_RUNTIME_MEMBERS: Array[String] = ["entries", "page", "source", "friends_only", "steam_user_rank", "_hover_self_on_next_generate"]
const LEVEL_FONT_SIZE:= 32
const LEVEL_MARGIN:= 96

signal prime_merged(p0: int, p1: int, new_sobo: Sobo)


func _ready() -> void:
	process_physics_priority = -100
	process_priority = 100
	var base: int = SoboManager.power_of_two_sizes.size()
	if base != EXPECTED_POWER_OF_TWO_SIZES:
		push_warning("%s disabled: expected %d power-of-two sobo sizes, found %d" % [MOD_TAG, EXPECTED_POWER_OF_TWO_SIZES, base])
		return
	diagnostics = load(mod_dir().path_join("prime_diagnostics.gd")).new()
	var diagnostic_error: Error = diagnostics.start()
	if diagnostic_error != OK:
		push_warning("%s diagnostic thread could not start: %s" % [MOD_TAG, error_string(diagnostic_error)])
	for p: int in PRIMES:
		# A sobo's value is its size. The game builds the data from the size alone (n = log2(size)),
		# so a prime sits between its neighbouring powers of two. Built now so the first spawn is not slow.
		SoboManager.get_sobo_data(p)
	var chain := 14
	while chain <= SEVEN_CHAIN_MAX:
		SoboManager.get_sobo_data(chain)
		chain *= 2
	game_mode_scope = load(mod_dir().path_join("game_mode_scope.gd"))
	prime_settings = load(mod_dir().path_join("prime_settings.gd")).new()
	prime_text = load(mod_dir().path_join("prime_text.gd"))
	prime_level = load(mod_dir().path_join("prime_level.gd"))
	if FileAccess.file_exists(mod_dir().path_join("selftest.flag")) or FileAccess.file_exists(mod_dir().path_join("seven.flag")):
		# The self test starts prime, in its own file; the player's switch is never touched.
		prime_settings.path = prime_settings.SELFTEST_PATH
		prime_settings.set_enabled(true)
		prime_settings.set_send_scores(false)
		prime_settings.set_save_screenshots(false)
	prime_settings.load_file()
	# Before prime_scores.gd connects its own: the run's mode is set first.
	SignalBus.on_game_mode_start.connect(on_game_mode_start)
	SignalBus.on_sobo_join_bar.connect(on_sobo_join_bar)
	SignalBus.on_sobo_merge.connect(on_native_sobo_merge)
	online = load(mod_dir().path_join("prime_online.gd")).new()
	online.send_scores = prime_settings.send_scores
	add_child(online)
	if SteamManager.steam_ready:
		apply_steam_identity()
	else:
		SteamManager.steam_initialized.connect(apply_steam_identity, CONNECT_ONE_SHOT)
	scores = load(mod_dir().path_join("prime_scores.gd")).new()
	scores.online = online
	if FileAccess.file_exists(mod_dir().path_join("selftest.flag")) or FileAccess.file_exists(mod_dir().path_join("seven.flag")):
		scores.save_path = scores.SELFTEST_SAVE_PATH
		online.identity_path = "user://prime_sobo_online_selftest.json"
		# Artificial test scores must never reach a public server or the real identity.
		if FileAccess.file_exists(mod_dir().path_join("online_selftest.flag")) == false || online.is_local_server() == false:
			online.enabled = false
	add_child(scores)
	install_scores_screen()
	enabled = true
	print("%s loaded: power-of-two sizes %d, sobo datas %d, primes %s" % [MOD_TAG, base, SoboManager.sobo_datas.size(), PRIMES])
	if FileAccess.file_exists(mod_dir().path_join("seven.flag")):
		selftest = true
		guard_disabled_for_test = false
		run_seven_selftest.call_deferred()
	elif FileAccess.file_exists(mod_dir().path_join("selftest.flag")):
		selftest = true
		guard_disabled_for_test = FileAccess.file_exists(mod_dir().path_join("noguard.flag"))
		run_selftest.call_deferred()


## The world ranking knows a player by their Steam ID and shows their Steam name, like the game's
## Steam leaderboard (ranking spec §3). Without Steam the transport sends nothing.
func apply_steam_identity() -> void:
	if SteamManager.steam_ready == false:
		return
	online.steam_id = str(SteamManager.steam.getSteamID())
	online.player_name = SteamManager.steam.getPersonaName()


func mod_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir()


## Keep every run-time side effect on the same game's default classic modes.
func is_classic_run() -> bool:
	return game_mode_scope != null && game_mode_scope.is_classic_run(GameModeManager)


func is_prime_run() -> bool:
	return run_prime && is_classic_run()


func can_share_prime_best() -> bool:
	return game_mode_scope != null && game_mode_scope.can_share_prime_best(GameModeManager)


## Autoloads are ready before the main scene, so wait for the game's Menu, then add a second
## instance of its scores screen with prime_scores_screen.gd and point Menu._0.scores_screen at it.
## Every "scores" button (main menu, game over, side panel) reads Menu._0.scores_screen.
## The game's own screen stays in the menu, hidden and unchanged.
func install_scores_screen() -> void:
	for i in MENU_WAIT_FRAMES:
		if Menu._0 != null && is_instance_valid(Menu._0) && Menu._0.is_node_ready() && Menu._0.scores_screen != null:
			break
		await get_tree().process_frame
	var menu: Menu = Menu._0
	if menu == null || is_instance_valid(menu) == false || menu.is_node_ready() == false || menu.scores_screen == null:
		push_warning("%s scores screen not installed: the game's Menu did not appear" % MOD_TAG)
		return
	var original: ScoresScreen = menu.scores_screen
	var copy = clone_scores_screen(original)
	if copy == null:
		push_warning("%s scores screen not installed: could not instance %s" % [MOD_TAG, original.scene_file_path])
		return
	copy.scores = scores
	copy.online = online
	copy.visible = false
	original.add_sibling(copy)
	original_scores_screen = original
	scores_screen = copy
	apply_scores_screen()
	# The small game-over board (CanvasLayer 100) would cover the screen's source row.
	menu.on_change_screen.connect(on_menu_screen_changed)
	menu.on_open.connect(on_menu_opened)
	menu.on_close.connect(on_menu_closed)
	print("%s scores screen installed: %s" % [MOD_TAG, copy.get_path()])
	install_prime_toggle(menu)
	install_send_toggle(menu)
	install_screenshot_toggle(menu)


## "scores" opens the prime screen while prime mode is on, the game's own while it is off.
func apply_scores_screen() -> void:
	if Menu._0 == null || scores_screen == null:
		return
	Menu._0.scores_screen = scores_screen if prime_settings.enabled && is_classic_run() else original_scores_screen


## "prime balls" on the game's settings -> game screen, right under show instructions: a copy of
## that switch with this mod's handler. The game's screen script and scene files are not changed.
func install_prime_toggle(menu: Menu) -> void:
	var game_screen: MenuScreen = menu.settings_mobile_screen if OS.has_feature("mobile") else menu.game_settings_screen
	var model: SoboMenuButtonBool = game_screen.get("show_instructions_control") if game_screen != null else null
	if model == null:
		push_warning("%s prime balls switch not installed: the game's show instructions switch was not found" % MOD_TAG)
		return
	# No DUPLICATE_SIGNALS: the copy must not run the game's show instructions handler.
	var button: SoboMenuButtonBool = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	# Stored node values (label, bool_circles, highlight_elements...) are made to point at the copy's own nodes.
	for prop: Dictionary in model.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE && prop.usage & PROPERTY_USAGE_STORAGE:
			button.set(prop.name, value_for_copy(model.get(prop.name), model, button))
	button.name = "PrimeBalls"
	button.label.text = word(TOGGLE_TEXT)
	button.release_press.connect(on_prime_toggle_pressed)
	model.add_sibling(button)
	prime_toggle = button
	refresh_prime_toggle()
	print("%s prime balls switch installed: %s" % [MOD_TAG, button.get_path()])


## The mod's words in the game's language (prime_text.gd); the English words are the keys.
func word(key: String) -> String:
	return prime_text.get_text(key) if prime_text != null else key


func _notification(what: int) -> void:
	if diagnostics != null:
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			diagnostics.stop()
		elif what == NOTIFICATION_PAUSED:
			diagnostics.set_armed(false)
		elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
			diagnostics_suspended = true
			diagnostics.set_armed(false)
		elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
			diagnostics_suspended = false
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh_texts()


## The game's language changed: write the switches and lines again in it.
func refresh_texts() -> void:
	if prime_toggle != null:
		prime_toggle.label.text = word(TOGGLE_TEXT)
		prime_toggle.tooltip_text = toggle_description()
	if send_toggle != null:
		send_toggle.label.text = word(SEND_TEXT)
		send_toggle.tooltip_text = send_description()
	if screenshot_toggle != null:
		screenshot_toggle.label.text = word(SCREENSHOT_TEXT)
		screenshot_toggle.tooltip_text = word("save screenshots description")


## The settings screen shows tr(tooltip_text) for the hovered switch at the bottom.
func toggle_description() -> String:
	return word("prime balls description")


func refresh_prime_toggle() -> void:
	if prime_toggle == null:
		return
	prime_toggle.set_value(prime_settings.enabled)
	prime_toggle.tooltip_text = toggle_description()


func on_prime_toggle_pressed() -> void:
	set_prime_enabled(prime_settings.enabled == false)


## The scores screen follows at once; the game itself from the next run (on_game_mode_start).
func set_prime_enabled(value: bool) -> void:
	prime_settings.set_enabled(value)
	refresh_prime_toggle()
	apply_scores_screen()


## "send scores" right under prime balls, made the same way as prime balls.
func install_send_toggle(_menu: Menu) -> void:
	var model: SoboMenuButtonBool = prime_toggle
	if model == null:
		push_warning("%s send scores switch not installed: prime balls is not there" % MOD_TAG)
		return
	var button: SoboMenuButtonBool = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	for prop: Dictionary in model.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE && prop.usage & PROPERTY_USAGE_STORAGE:
			button.set(prop.name, value_for_copy(model.get(prop.name), model, button))
	button.name = "SendScores"
	button.label.text = word(SEND_TEXT)
	button.release_press.connect(on_send_toggle_pressed)
	prime_toggle.add_sibling(button)
	send_toggle = button
	refresh_send_toggle()
	compact_mobile_settings()
	print("%s send scores switch installed: %s" % [MOD_TAG, button.get_path()])


## A copy with its own nodes and signal, immediately after send scores on either platform.
func install_screenshot_toggle(_menu: Menu) -> void:
	var model: SoboMenuButtonBool = send_toggle
	if model == null:
		push_warning("%s screenshot switch not installed: send scores is not there" % MOD_TAG)
		return
	var button: SoboMenuButtonBool = model.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	for prop: Dictionary in model.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE && prop.usage & PROPERTY_USAGE_STORAGE:
			button.set(prop.name, value_for_copy(model.get(prop.name), model, button))
	button.name = "SaveScreenshots"
	button.label.text = word(SCREENSHOT_TEXT)
	button.release_press.connect(on_screenshot_toggle_pressed)
	send_toggle.add_sibling(button)
	screenshot_toggle = button
	refresh_screenshot_toggle()
	compact_mobile_settings()


func refresh_screenshot_toggle() -> void:
	if screenshot_toggle == null:
		return
	screenshot_toggle.set_value(prime_settings.save_screenshots)
	screenshot_toggle.tooltip_text = word("save screenshots description")


func on_screenshot_toggle_pressed() -> void:
	set_save_screenshots(prime_settings.save_screenshots == false)


func set_save_screenshots(value: bool) -> void:
	prime_settings.set_save_screenshots(value)
	refresh_screenshot_toggle()


func send_description() -> String:
	return word("send scores description")


func refresh_send_toggle() -> void:
	if send_toggle == null:
		return
	send_toggle.set_value(prime_settings.send_scores)
	send_toggle.tooltip_text = send_description()


func on_send_toggle_pressed() -> void:
	set_send_scores(prime_settings.send_scores == false)


## From the next game over. Scores already sent stay on the ranking. A choice that could not be
## written is not taken, so the switch never shows off while a restart would send.
func set_send_scores(value: bool) -> void:
	prime_settings.set_send_scores(value)
	online.send_scores = prime_settings.send_scores
	refresh_send_toggle()


## A run starts (a new one, or one continued from the game's save). SaveLoadManager.load() keeps
## the loaded game_state until the run is applied, so it is set here only for a continued run.
func on_game_mode_start(_scene: GameScene) -> void:
	if not is_classic_run():
		apply_run(false)
		return
	var state: GameState = SaveLoadManager.game_state
	var has_save: bool = SaveLoadManager.has_save()
	var continued: bool = state != null && has_save
	# The save on disk now: for a new run the older run's (kept until this run saves), for a continued
	# run the one being loaded (the game deletes it only after applying it). A save whose MD5 cannot
	# be read is marked unreadable, never passed as no save.
	var save_id: String = prime_settings.save_id_of(has_save, FileAccess.get_md5(SaveLoadManager.SAVE_PATH) if has_save else "")
	apply_run(prime_settings.start_run(continued, continued && state_holds_primes(state), save_id))


## Whether a saved run has prime balls on the board. A run started off never rolls a prime, so a save
## holding one is a prime run even when the remembered mode says off (prime_settings.start_run).
func state_holds_primes(state: GameState) -> bool:
	for list_name: String in ["sobos_emerging", "sobos_selectable", "sobos_in_stack"]:
		var list: Variant = state.get(list_name)
		if list is Array:
			for sobo_state: Variant in list:
				if sobo_state is SoboState && is_prime_size(sobo_state.size):
					return true
	return false


func apply_run(prime: bool) -> void:
	run_prime = prime && is_classic_run()
	apply_scores_screen()
	if run_prime:
		block_online_scoring()
	else:
		unblock_online_scoring()


## Make room for the added rows without scaling the native slider controls.
func compact_mobile_settings() -> void:
	if Menu._0 == null || prime_toggle == null || not Menu._0.settings_mobile_screen.is_ancestor_of(prime_toggle):
		return
	for child: Node in prime_toggle.get_parent().get_children():
		if child is HSeparator:
			(child as HSeparator).add_theme_constant_override("separation", 4)


func on_menu_screen_changed(new_screen: MenuScreen) -> void:
	scores.set_board_suppressed(new_screen != null && new_screen == scores_screen)
	if new_screen != null && prime_toggle != null && new_screen.is_ancestor_of(prime_toggle):
		refresh_prime_toggle()


## The game pauses processing when opening a menu, so hide the run overlays on its signal.
func on_menu_opened() -> void:
	if level_label != null:
		level_label.hide()
	if diagnostics != null:
		diagnostics.set_armed(false)


func on_menu_closed() -> void:
	scores.set_board_suppressed(false)


## The game's scene instanced again. set_script() drops the values the scene gave the old script,
## so every stored (exported) value is taken from the live original first: nodes inside the
## original map to the same path in the copy, other values (parent_screen, texts) are kept as they are.
func clone_scores_screen(original: ScoresScreen) -> Node:
	var scene_path: String = original.scene_file_path if original.scene_file_path != "" else SCORES_SCREEN_SCENE
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var copy: Node = packed.instantiate()
	var values: Dictionary = {}
	for prop: Dictionary in original.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE && prop.usage & PROPERTY_USAGE_STORAGE:
			if SCORES_SCREEN_RUNTIME_MEMBERS.has(prop.name):
				continue
			values[prop.name] = value_for_copy(original.get(prop.name), original, copy)
	copy.set_script(load(mod_dir().path_join("prime_scores_screen.gd")))
	for key: String in values:
		copy.set(key, values[key])
	return copy


func value_for_copy(value: Variant, original: Node, copy: Node) -> Variant:
	if value is Node:
		if value == original:
			return copy
		if original.is_ancestor_of(value):
			return copy.get_node_or_null(original.get_path_to(value))
		return value
	if value is Array:
		var mapped: Array = value.duplicate()
		for i in mapped.size():
			mapped[i] = value_for_copy(mapped[i], original, copy)
		return mapped
	return value


## Keep modded runs off Steam: no leaderboard upload, no rich-presence live score, no achievements.
## The on-screen score keeps working; listeners after ScoreManager are reconnected in their original order.
## Safe to call again: it only changes what is not blocked yet.
func block_online_scoring() -> void:
	if SignalBus.on_game_over.is_connected(ScoreManager.on_game_over):
		SignalBus.on_game_over.disconnect(ScoreManager.on_game_over)
	swap_listener(SignalBus.on_gain_score, Callable(ScoreManager, "gain_score"), gain_score_offline)
	AchievementTracker.disable_achievements = true


## Prime mode off (spec §7): the game's own leaderboard upload (first among the game-over
## listeners, where ScoreManager connects it), live score and achievements as without this mod.
func unblock_online_scoring() -> void:
	if SignalBus.on_game_over.is_connected(ScoreManager.on_game_over) == false:
		var others: Array = SignalBus.on_game_over.get_connections()
		for c: Dictionary in others:
			SignalBus.on_game_over.disconnect(c.callable)
		SignalBus.on_game_over.connect(ScoreManager.on_game_over)
		for c: Dictionary in others:
			SignalBus.on_game_over.connect(c.callable, c.flags)
	swap_listener(SignalBus.on_gain_score, gain_score_offline, Callable(ScoreManager, "gain_score"))
	# The game decides it again for every run; ask it instead of remembering a value.
	AchievementTracker.apply_run_achievements()


## Puts `to` in the place of `from` among the signal's listeners, keeping the order of the others.
func swap_listener(sig: Signal, from: Callable, to: Callable) -> void:
	if sig.is_connected(from) == false:
		return
	var connections: Array = sig.get_connections()
	for c: Dictionary in connections:
		sig.disconnect(c.callable)
	for c: Dictionary in connections:
		sig.connect(to if c.callable == from else c.callable, c.flags)


## ScoreManager.gain_score without the live score publishing.
func gain_score_offline(amount: int) -> void:
	ScoreManager.current_score += amount


func is_prime_sobo(sobo: Sobo) -> bool:
	return is_instance_valid(sobo) && sobo.data != null && is_prime_size(sobo.data.size)


func is_power_of_two(v: int) -> bool:
	return v > 0 && (v & (v - 1)) == 0


func is_seven_chain(v: int) -> bool:
	if v < 7 or v % 7 != 0:
		return false
	return is_power_of_two(v / 7)


## The doubled sobo is created directly. SoboManager.merge emits on_sobo_merge, and the classic
## mode adds the new size to the score from that signal, so this chain never calls it.
func merge_seven(a: Sobo, b: Sobo, doubled: int, sa: Suba, sb: Suba) -> void:
	diagnostic_tick("merge_seven %d" % doubled)
	var contact_pos: Vector2 = (sa.global_position + sb.global_position) / 2.0
	var shockwave_area: float = a.data.outer_circle.area
	MergeSound.play_at_with_area(contact_pos, shockwave_area)
	Shockwave.create(contact_pos, shockwave_area / SoboManager.shockwave_life_per_sobo_area)
	var child: Sobo = create_prime(doubled, (a.center + b.center) / 2.0)
	var mode:= GameModeManager.current_scene as SceneClassic
	if mode != null:
		mode.enter_stack(child)
	a.queue_free()
	b.queue_free()


## Regular sobos have a size of 2^n; a prime sobo's size is the prime itself.
func is_prime_size(size: int) -> bool:
	return size > 1 && is_power_of_two(size) == false


func create_prime(p: int, pos: Vector2) -> Sobo:
	var sobo: Sobo = SoboManager.create(p, pos)
	sobo.allow_merges = false
	return sobo


func pick_prime() -> int:
	var total:= 0.0
	for w: float in PRIME_WEIGHTS:
		total += w
	var r:= randf() * total
	for i: int in PRIMES.size():
		r -= PRIME_WEIGHTS[i]
		if r <= 0.0:
			return PRIMES[i]
	return PRIMES[0]


## A freshly spawned sobo joins the bar inside SceneClassic.spawn_sobo_on_side, before its
## collision bits and velocity are set; swap it for a prime once that call has finished.
func on_sobo_join_bar(sobo: Sobo) -> void:
	if enabled == false || not is_prime_run() || is_prime_sobo(sobo) || sobo.merged:
		return
	var mode:= GameModeManager.current_scene as SceneClassic
	if mode == null || mode.sobos_emerging.has(sobo) == false:
		return
	var id:= sobo.get_instance_id()
	if replaced.has(id):
		return
	replaced[id] = true
	if roll_prime():
		replace_with_prime.call_deferred(sobo, pick_prime())


## The one place that decides whether a regular spawn becomes a prime.
## Never while the run was started with prime mode off.
func roll_prime() -> bool:
	return is_prime_run() && randf() < run_chance()


## The chance of a prime spawn now: the prime level's (spec §10), or the self test's fixed one.
func run_chance() -> float:
	if forced_chance >= 0.0:
		return forced_chance
	return prime_level.chance_of(current_level())


## The game's own stage (spec §10): how many spawn tiers its SpawnPool has opened in this run.
func current_level() -> int:
	var mode: GameScene = GameModeManager.current_scene
	if mode == null || mode.spawn_pool == null:
		return 1
	return prime_level.level_of(mode.spawn_pool.current_spawn_pool)


## The level line (spec §10) at the foot of the game's right panel, under the big score of a run
## (LiveScoreDisplay's SDFLabel there): a new Label of its own, never a copy of the game's (copies
## crashed in spec §9).
func install_level_label() -> void:
	var target: Control = level_label_parent()
	if target == null:
		return
	level_label = Label.new()
	level_label.name = "PrimeLevel"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(level_label)
	level_layout = []


## Use the game's visible score panel; portrait play has its score above the play area.
func level_label_parent() -> Control:
	if Ui._0 == null:
		return null
	var top: SidePanel = Ui._0.mobile_top_panel
	if is_instance_valid(top) && top.is_visible_in_tree():
		return top
	for panel: SidePanel in Ui._0.side_panels:
		if not is_instance_valid(panel):
			continue
		if panel is RightSidePanel && panel.is_visible_in_tree() && panel.size.x > 16.0 && panel.size.y > 16.0:
			return panel
	return Ui._0.ui_play_area


func refresh_level_label() -> void:
	if not is_instance_valid(level_label):
		level_label = null
		if Engine.get_process_frames() % 60 == 0:
			install_level_label()
		if level_label == null:
			return
	level_label.visible = is_prime_run() && Menu._0 != null && not Menu._0.visible
	if not level_label.visible:
		return
	var target: Control = level_label_parent()
	if target == null:
		return
	if level_label.get_parent() != target:
		level_label.reparent(target, false)
	var level: int = current_level()
	level_label.text = word("level") % [level, roundi(prime_level.chance_of(level) * 100.0)]
	var side_panel: bool = target is RightSidePanel
	level_label.add_theme_font_size_override("font_size", LEVEL_FONT_SIZE if side_panel else 20)
	var viewport: Rect2 = get_viewport().get_visible_rect()
	if OS.has_feature("mobile"):
		viewport = viewport.intersection(MobileManager.get_usable_rect())
	# Label reshaping can update its wrapped minimum size on the next frame.
	var layout: Array = [
		target.get_instance_id(), target.size, viewport,
		level_label.text, level_label.get_combined_minimum_size(),
	]
	if layout == level_layout:
		return
	var available: Rect2 = Rect2(Vector2.ZERO, target.size)
	if target == Ui._0.ui_play_area:
		var local: Rect2 = target.get_global_transform_with_canvas().affine_inverse() * viewport
		available = available.intersection(local)
	available = available.grow(-8.0)
	if not available.has_area():
		level_label.hide()
		return
	level_layout = layout
	level_label.custom_minimum_size.x = available.size.x
	level_label.size.x = available.size.x
	level_label.size.y = level_label.get_combined_minimum_size().y
	var bottom: float = target.size.y - LEVEL_MARGIN - level_label.size.y
	level_label.position = Vector2(available.position.x,
		clampf(bottom if side_panel else available.end.y - level_label.size.y, available.position.y,
			maxf(available.position.y, available.end.y - level_label.size.y)))


func replace_with_prime(sobo: Sobo, p: int) -> void:
	diagnostic_tick("replace_with_prime")
	if not is_prime_run():
		return
	var mode:= GameModeManager.current_scene as SceneClassic
	if mode == null || is_instance_valid(sobo) == false || sobo.is_queued_for_deletion():
		return
	if mode.sobos_emerging.has(sobo) == false:
		return
	var source := JSON.stringify(diagnostic_sobo(sobo))
	var prime: Sobo = create_prime(p, sobo.center)
	var src: Suba = sobo.subas[0]
	for s: Suba in prime.subas:
		s.collision_layer = src.collision_layer
		s.collision_mask = src.collision_mask
	prime.set_velocity(src.linear_velocity)
	mode.remove_from_role_lists(sobo)
	sobo.queue_free()
	mode.enter_emerging(prime)
	prime.allow_merges = false
	natural_replacements += 1
	print("%s event=prime_granted source=%s result=%s prime=%d" % [MOD_TAG, source, JSON.stringify(diagnostic_sobo(prime)), p])


func _physics_process(_dt: float) -> void:
	diagnostic_tick("_physics_process")
	if enabled == false || not is_prime_run():
		return
	var primes: Array[Sobo] = []
	for sobo: Sobo in SoboManager.all_sobos:
		if is_prime_sobo(sobo):
			primes.append(sobo)
			if guard_disabled_for_test:
				continue
			# The game merges same-size contacts only between sobos that may merge (SoboManager.sobo_can_merge,
			# for the seed and for every neighbour); keep primes out of that path entirely.
			sobo.allow_merges = false
	# TODO-138: same-size contacts are collected by the native SoboContacts (not in the decompiled sources); confirm it accepts a non-power-of-two size.
	try_prime_merge(primes)


func try_prime_merge(primes: Array[Sobo]) -> void:
	for a: Sobo in primes:
		if a.merged_this_frame || a.flashing > 0.0 || a.is_queued_for_deletion():
			continue
		for sa: Suba in a.subas:
			for sb: Suba in sa.contacting_other_subas:
				var b: Sobo = sb.sobo
				if b == a || is_instance_valid(b) == false || b.data == null || b.merged_this_frame || b.is_queued_for_deletion():
					continue
				var va: int = a.data.size
				var vb: int = b.data.size
				if is_prime_sobo(b) == false:
					# Spec §2 (2026-11-12): a seven chain from 14 up meets the plain 2^k, its seventh,
					# and both become the plain 8 * 2^k. 7 itself still pairs only with 7.
					if va >= 14 and is_seven_chain(va) and is_power_of_two(va + vb):
						merge_primes(a, b, sa, sb, va + vb)
						return
					continue
				if is_seven_chain(va) or is_seven_chain(vb):
					if va == vb and va * 2 <= SEVEN_CHAIN_MAX:
						merge_seven(a, b, va * 2, sa, sb)
						return
					continue
				var sum: int = va + vb
				if is_power_of_two(sum) == false:
					continue
				merge_primes(a, b, sa, sb, sum)
				return


## Reuse SoboManager.merge (shape blending, sound, shockwave, SignalBus.on_sobo_merge) by handing it
## the same group the game builds in detect_merges/grow_merge_group: the two sobos and the one contact.
## finish_merge gives the new sobo the sum of the old sizes, which is the power of two `sum`, so the
## primes keep their own data and nothing has to be swapped.
func merge_primes(a: Sobo, b: Sobo, sa: Suba, sb: Suba, sum: int) -> void:
	diagnostic_tick("merge_primes sum=%d" % sum)
	var p0: int = a.data.size
	var p1: int = b.data.size
	var group:= SoboManager.MergeGroup.new()
	var contact:= SoboManager.MergeContact.new()
	contact.suba0 = sa
	contact.suba1 = sb
	contact.y = (a.center.y + b.center.y) * 0.5
	group.sobos.append(a)
	group.sobos.append(b)
	group.contacts.append(contact)
	a.merged_this_frame = true
	b.merged_this_frame = true
	var before: int = SoboManager.all_sobos.size()
	SoboManager.merge(group)
	if SoboManager.all_sobos.size() > before:
		var new_sobo: Sobo = SoboManager.all_sobos[-1]
		prime_merged.emit(p0, p1, new_sobo)


func _process(_dt: float) -> void:
	diagnostic_tick("_process")
	if enabled == false:
		return
	refresh_level_label()
	if not is_prime_run():
		return
	for sobo: Sobo in SoboManager.all_sobos:
		# A shuffle in Special Sobos can hand a prime number to another body; that body keeps its color.
		if is_prime_sobo(sobo) && sobo.flashing <= 0.0 && not sobo.has_meta("special_shuffle_color"):
			sobo.color = PRIME_COLOR
			# Sobo.apply_style copies color to visual_color, which is what the game draws with.
			# TODO-138: visual_color belongs to the native SoboCore (not in the decompiled sources); confirm in game that this tints the prime.
			sobo.visual_color = PRIME_COLOR


func on_native_sobo_merge(a: Sobo, b: Sobo, result: Sobo) -> void:
	print("%s event=merge parents=%s result=%s" % [MOD_TAG,
		JSON.stringify([diagnostic_sobo(a), diagnostic_sobo(b)]), JSON.stringify(diagnostic_sobo(result))])


## Read native fields only on the main thread. The worker receives their JSON string.
func diagnostic_sobo(sobo: Sobo) -> Dictionary:
	if not is_instance_valid(sobo) or sobo.data == null:
		return {"valid": false}
	return {"id": sobo.get_instance_id(), "size": sobo.data.size, "value": sobo.data.size,
		"prime": is_prime_sobo(sobo), "radius": snappedf(sobo.data.outer_circle.radius, 0.1),
		"position": [snappedf(sobo.center.x, 0.1), snappedf(sobo.center.y, 0.1)],
		"velocity": [snappedf(sobo.avg_velocity.x, 0.1), snappedf(sobo.avg_velocity.y, 0.1)]}


func diagnostic_tick(entry: String) -> void:
	if diagnostics == null:
		return
	var rows: Array[Dictionary] = []
	for sobo: Sobo in SoboManager.all_sobos:
		rows.append(diagnostic_sobo(sobo))
	var active := enabled and is_prime_run() and not diagnostics_suspended and not get_tree().paused
	active = active and Menu._0 != null and not Menu._0.visible
	diagnostics.pulse(entry, JSON.stringify(rows), active)


func _exit_tree() -> void:
	if diagnostics != null:
		diagnostics.stop()


func run_seven_selftest() -> void:
	var lines: PackedStringArray = []
	forced_chance = 0.0
	await start_default_run()
	for i in 30:
		await get_tree().physics_frame
	var mode:= GameModeManager.current_scene as SceneClassic
	check(lines, "seven board started", mode != null, "run_prime=%s" % run_prime)
	var seven_i: int = PRIMES.find(7)
	check(lines, "7 is spawned at weight 4", seven_i >= 0 and is_equal_approx(PRIME_WEIGHTS[seven_i], 4.0), "primes=%s weights=%s" % [PRIMES, PRIME_WEIGHTS])
	if mode == null:
		await finish_seven(lines)
		return
	var merges: Array = []
	SignalBus.on_sobo_merge.connect(func(o0: Sobo, o1: Sobo, ns: Sobo) -> void: merges.append([o0.data.size, o1.data.size, ns.data.size]))
	await push_seven_pair(lines, mode, merges, "7+7", 7, 7, true, 0.0)
	await push_seven_pair(lines, mode, merges, "7+8", 7, 8, false, 140.0)
	await push_seven_pair(lines, mode, merges, "7+3", 7, 3, false, 280.0)
	await push_seven_pair(lines, mode, merges, "14+28", 14, 28, false, 420.0)
	await push_seven_pair(lines, mode, merges, "458752+458752", 458752, 458752, false, 900.0)
	await push_seven_plain(lines, mode, merges, "14+2", 14, 2, true, 140.0)
	await push_seven_plain(lines, mode, merges, "28+4", 28, 4, true, 280.0)
	await push_seven_plain(lines, mode, merges, "14+4", 14, 4, false, 420.0)
	await push_seven_plain(lines, mode, merges, "7+1", 7, 1, false, 560.0)
	await open_pre7_save(lines, mode)
	await finish_seven(lines)


func push_seven_pair(lines: PackedStringArray, mode: SceneClassic, merges: Array, pair_name: String, left: int, right: int, must_merge: bool, y: float) -> void:
	print("%s seven pair %s" % [MOD_TAG, pair_name])
	var before_14: int = count_size(left * 2)
	var score_before: int = ScoreManager.current_score
	var merges_before: int = merges.size()
	var waves_before: int = shockwave_count()
	var wave_peak: int = waves_before
	var a: Sobo = create_prime(left, Vector2(-30, -200.0 + y))
	var b: Sobo = create_prime(right, Vector2(30, -200.0 + y))
	mode.enter_stack(a)
	mode.enter_stack(b)
	var touched := false
	var became := false
	for f in 90:
		if alive(a) and alive(b):
			var d: Vector2 = a.center.direction_to(b.center)
			if d.is_finite():
				a.apply_uniform_acceleration(d * 300.0)
				b.apply_uniform_acceleration(-d * 300.0)
			for s: Suba in a.subas:
				for o: Suba in s.contacting_other_subas:
					if o.sobo == b:
						touched = true
		elif must_merge and count_size(left * 2) > before_14:
			became = true
		wave_peak = maxi(wave_peak, shockwave_count())
		await get_tree().physics_frame
	var score_after: int = ScoreManager.current_score
	if must_merge:
		if became == false:
			became = alive(a) == false and alive(b) == false and count_size(left * 2) > before_14
		check(lines, "%s doubles and the score stays" % pair_name, touched and became and score_before == score_after, "touched=%s score %d -> %d merges=%s" % [touched, score_before, score_after, merges.slice(merges_before)])
		check(lines, "%s adds one shockwave" % pair_name, wave_peak == waves_before + 1, "before=%d peak=%d" % [waves_before, wave_peak])
	else:
		var involved := false
		for recorded: Array in merges.slice(merges_before):
			if (recorded[0] == left and recorded[1] == right) or (recorded[0] == right and recorded[1] == left):
				involved = true
		check(lines, "%s does not merge" % pair_name, touched and alive(a) and alive(b) and involved == false and score_before == score_after, "touched=%s alive=%s %s score %d -> %d" % [touched, alive(a), alive(b), score_before, score_after])
	for s: Sobo in SoboManager.all_sobos.duplicate():
		if is_instance_valid(s) and s.data != null and (s.data.size == left or s.data.size == right or s.data.size == left * 2):
			s.queue_free()


## A seven-chain prime against a plain sobo (spec §2, 2026-11-12): 7 * 2^k with k >= 1 and a plain 2^k
## become the plain sobo 8 * 2^k through the game's merge. Every other pair stays apart.
func push_seven_plain(lines: PackedStringArray, mode: SceneClassic, merges: Array, pair_name: String, seven: int, plain: int, must_merge: bool, y: float) -> void:
	print("%s seven plain %s" % [MOD_TAG, pair_name])
	var total: int = seven + plain
	var before_total: int = count_size(total)
	var merges_before: int = merges.size()
	var a: Sobo = create_prime(seven, Vector2(-30, -200.0 + y))
	var b: Sobo = SoboManager.create(plain, Vector2(30, -200.0 + y))
	mode.enter_stack(a)
	mode.enter_stack(b)
	var touched := false
	for f in 90:
		if alive(a) and alive(b):
			var d: Vector2 = a.center.direction_to(b.center)
			if d.is_finite():
				a.apply_uniform_acceleration(d * 300.0)
				b.apply_uniform_acceleration(-d * 300.0)
			for s: Suba in a.subas:
				for o: Suba in s.contacting_other_subas:
					if o.sobo == b:
						touched = true
		await get_tree().physics_frame
	var involved := false
	for recorded: Array in merges.slice(merges_before):
		if (recorded[0] == seven and recorded[1] == plain) or (recorded[0] == plain and recorded[1] == seven):
			involved = true
	if must_merge:
		var result: Sobo = null
		for s: Sobo in SoboManager.all_sobos:
			if is_instance_valid(s) and s.data != null and s.data.size == total:
				result = s
		var plain_color: bool = result != null and result.color.is_equal_approx(StyleManager.current_sobo_palette.color_for_size(total))
		check(lines, "%s becomes the plain %d" % [pair_name, total], touched and involved and alive(a) == false and alive(b) == false and count_size(total) > before_total and result != null and is_prime_sobo(result) == false and plain_color, "touched=%s merges=%s alive=%s %s plain_color=%s" % [touched, merges.slice(merges_before), alive(a), alive(b), plain_color])
	else:
		check(lines, "%s does not merge" % pair_name, touched and alive(a) and alive(b) and involved == false, "touched=%s alive=%s %s merges=%s" % [touched, alive(a), alive(b), merges.slice(merges_before)])
	for s: Sobo in SoboManager.all_sobos.duplicate():
		if is_instance_valid(s) and s.data != null and (s.data.size == seven or s.data.size == plain or s.data.size == total):
			s.queue_free()


func shockwave_count() -> int:
	var n: int = 0
	if Main._0 == null:
		return 0
	for child: Node in Main._0.get_children():
		if child is Shockwave:
			n += 1
	return n


func count_size(size: int) -> int:
	var n:= 0
	if size < 0:
		return 0
	for s: Sobo in SoboManager.all_sobos:
		if is_instance_valid(s) and s.data != null and s.data.size == size:
			n += 1
	return n


func open_pre7_save(lines: PackedStringArray, mode: SceneClassic) -> void:
	if FileAccess.file_exists("user://run.sav") == false:
		lines.append("save: 開いていない")
		print("%s seven save: 開いていない" % MOD_TAG)
		return
	var state: GameState = SaveLoadManager.read_save()
	if state == null:
		check(lines, "a save from before 7 opens", false, "user://run.sav unreadable")
		return
	await mode.apply_game_state(state)
	var sizes: PackedStringArray = []
	for s: Sobo in SoboManager.all_sobos:
		if is_instance_valid(s) and s.data != null:
			sizes.append(str(s.data.size))
	check(lines, "a save from before 7 opens", true, "mode=%s sizes=%s" % [state.mode_name, " ".join(sizes)])


func finish_seven(lines: PackedStringArray) -> void:
	var fails:= 0
	for l: String in lines:
		if l.contains("FAIL"):
			fails += 1
		print("%s seven %s" % [MOD_TAG, l])
	var f:= FileAccess.open(mod_dir().path_join("seven_result.txt"), FileAccess.WRITE)
	if f:
		f.store_string(("\n".join(lines)) + ("\nfailures=%d\n" % fails))
		f.close()
	# Quitting in the same frame as the pre-7 save's bodies (one of them is size -1)
	# access-violates on the way out. Free them, let that frame finish, then quit.
	SoboManager.free_all()
	for _i in 3:
		await get_tree().physics_frame
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- self test
# Runs only when selftest.flag sits next to this script. Starts the default mode and pushes four pairs
# together: 3+5 must merge into 8; 3+11, 3+3 and 3 + a regular 4 must touch without merging.
# Writes selftest_result.txt (and selftest_shot.png when windowed), then quits.

func run_selftest() -> void:
	var lines: PackedStringArray = []
	lines.append("loaded sobo_datas=%d primes=%s" % [SoboManager.sobo_datas.size(), PRIMES])
	lines.append("leaderboard_upload_connected=%s" % SignalBus.on_game_over.is_connected(ScoreManager.on_game_over))
	lines.append("score_manager_gain_connected=%s" % SignalBus.on_gain_score.is_connected(ScoreManager.gain_score))
	lines.append("achievements_disabled=%s" % AchievementTracker.disable_achievements)
	lines.append("modes=%s default=%s" % [GameModeManager.get_mode_names(), GameModeManager.get_game_mode_name(GameModeManager.get_default_game_mode())])
	# "send scores" starts off (spec §8). The world checks below need it on: the self-test file only.
	var send_started_off: bool = prime_settings.send_scores == false && online.send_scores == false
	set_send_scores(true)
	var screenshots_started_off: bool = prime_settings.save_screenshots == false
	set_save_screenshots(true)
	# Keep natural spawns regular while the fixed pairs run, so a stray prime cannot pair with them.
	forced_chance = 0.0
	await start_default_run()
	for i in 30:
		await get_tree().physics_frame
	var mode:= GameModeManager.current_scene as SceneClassic
	lines.append("mode_started=%s" % (mode != null))
	# A new run opens only the game's smallest spawn tier: prime level 1 (spec §10).
	var level_at_start: int = current_level()
	if mode == null:
		finish_selftest(lines)
		return

	# The game can end this run by itself in the phases below (board full -> PREGAMEOVER ->
	# on_game_over), which already submits once. Watch every game over from here and keep the
	# board as it was before any of them, so the self-test never fires a second game over:
	# a second POST within 20 s is refused (429) and replaces the real submission's result.
	var board_before_over: Array = scores.local_scores.duplicate(true)
	var real_board_before: String = board_fingerprint(scores.SAVE_PATH)
	var over_scores: Array[int] = []
	var record_over:= func() -> void: over_scores.append(ScoreManager.current_score)
	SignalBus.on_game_over.connect(record_over)

	lines.append("guard_disabled_for_test=%s" % guard_disabled_for_test)
	var game_merges: Array = []
	SignalBus.on_sobo_merge.connect(func(o0: Sobo, o1: Sobo, ns: Sobo) -> void: game_merges.append([o0.data.size, o1.data.size, ns.data.size]))
	var natural_primes_before: int = count_primes()
	# [name, left sobo, right sobo, must merge]; left/right are pushed into each other for 90 frames.
	var pairs: Array = [
		["3+5", create_prime(3, Vector2(-55, -200)), create_prime(5, Vector2(55, -200)), true],
		["3+11", create_prime(3, Vector2(-60, -60)), create_prime(11, Vector2(60, -60)), false],
		["3+3", create_prime(3, Vector2(-50, 70)), create_prime(3, Vector2(50, 70)), false],
		["3+4(normal)", create_prime(3, Vector2(-50, 190)), SoboManager.create(4, Vector2(50, 190)), false],
	]
	for p: Array in pairs:
		mode.enter_stack(p[1])
		mode.enter_stack(p[2])
		# On the bar SceneClassic.enter_selectable turns allow_merges back on; reproduce that state.
		p[1].allow_merges = true
		p[2].allow_merges = true
	var touched: Dictionary[String, bool] = { }
	var score_before: int = ScoreManager.current_score
	var shot_saved:= ""
	for f in 240:
		for p: Array in pairs:
			# A merged pair is freed; a debug build refuses to put a freed instance in a typed variable.
			if alive(p[1]) == false || alive(p[2]) == false:
				continue
			var s0: Sobo = p[1]
			var s1: Sobo = p[2]
			if f < 90:
				var d: Vector2 = s0.center.direction_to(s1.center)
				s0.apply_uniform_acceleration(d * 300.0)
				s1.apply_uniform_acceleration(-d * 300.0)
			for s: Suba in s0.subas:
				for o: Suba in s.contacting_other_subas:
					if o.sobo == s1:
						touched[p[0]] = true
		if f == 120 && DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			shot_saved = mod_dir().path_join("selftest_shot.png")
			get_viewport().get_texture().get_image().save_png(shot_saved)
		await get_tree().physics_frame

	for p: Array in pairs:
		var both_alive: bool = alive(p[1]) && alive(p[2])
		var merged_now: bool = both_alive == false
		lines.append("pair %s: touched=%s merged=%s expected_merge=%s -> %s" % [p[0], touched.get(p[0], false), merged_now, p[3], "OK" if merged_now == p[3] && touched.get(p[0], false) else "FAIL"])
	lines.append("prime_merges(mod)=%s" % [game_merges.filter(func(m: Array) -> bool: return m[0] in PRIMES or m[1] in PRIMES)])
	lines.append("all_merges(game signal)=%s" % [game_merges])
	lines.append("score_before=%d score_after=%d" % [score_before, ScoreManager.current_score])
	lines.append("natural_primes_alive_before_test=%d natural_replacements=%d" % [natural_primes_before, natural_replacements])
	lines.append("all_sobo_values=%s" % [SoboManager.all_sobos.map(func(s: Sobo) -> int: return s.data.size)])
	lines.append("display=%s shot=%s" % [DisplayServer.get_name(), shot_saved])

	# Natural path: every spawn becomes a prime for a while; primes must reach the bar
	# (where enter_selectable turns allow_merges on) and still never be merged by the game.
	forced_chance = 1.0
	var replaced_before: int = natural_replacements
	var on_bar_seen: Dictionary[int, bool] = { }
	var allow_true_after_guard:= 0
	for f in 900:
		await get_tree().physics_frame
		# SceneClassic only spawns when the bar has room, so keep launching like a player would.
		if f % 30 == 0 && mode.sobos_selectable.is_empty() == false:
			mode.launch_sobo(mode.sobos_selectable[0], Vector2(randf_range(-0.3, 0.3), 0.6))
		for s: Sobo in mode.sobos_selectable:
			if is_prime_sobo(s):
				on_bar_seen[s.get_instance_id()] = true
				if s.allow_merges:
					allow_true_after_guard += 1
		if mode.state != SceneClassic.State.PLAYING:
			break
	forced_chance = -1.0
	var bad_game_merges: Array = game_merges.filter(func(m: Array) -> bool:
		var has_prime: bool = (m[0] in PRIMES) or (m[1] in PRIMES)
		return has_prime && (is_power_of_two(m[0] + m[1]) == false || m[2] != m[0] + m[1]))
	lines.append("natural: replacements=%d primes_seen_on_bar=%d allow_merges_true_seen=%d mode_state=%d" % [natural_replacements - replaced_before, on_bar_seen.size(), allow_true_after_guard, mode.state])
	lines.append("natural: bad_prime_merges=%s -> %s" % [bad_game_merges, "OK" if bad_game_merges.is_empty() && natural_replacements > replaced_before && on_bar_seen.size() > 0 else "FAIL"])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(mod_dir().path_join("selftest_shot2.png"))

	# Default mix: at the prime level's chance (11-31%) most spawns stay regular and some primes appear.
	# Runs after the forced phase so a game over here cannot spoil the other checks.
	forced_chance = -1.0
	var spawns_before: int = replaced.size()
	var mix_primes_before: int = natural_replacements
	for f in 3000:
		await get_tree().physics_frame
		if f % 30 == 0 && mode.sobos_selectable.is_empty() == false:
			mode.launch_sobo(mode.sobos_selectable[0], Vector2(randf_range(-0.3, 0.3), 0.6))
		if mode.state != SceneClassic.State.PLAYING:
			break
	var mix_spawns: int = replaced.size() - spawns_before
	var mix_primes: int = natural_replacements - mix_primes_before
	var mix_ratio: float = float(mix_primes) / float(maxi(mix_spawns, 1))
	# The in-game mix above is too small to tell one level from the next; roll the real decision
	# 20000 times (standard error at most about 0.35%), so a chance off its level is caught.
	var level_now: int = current_level()
	var chance_now: float = prime_level.chance_of(level_now)
	var rolls:= 20000
	var hits:= 0
	for i in rolls:
		if roll_prime():
			hits += 1
	var roll_ratio: float = float(hits) / float(rolls)
	check(lines, "prime decision rate follows the prime level", absf(roll_ratio - chance_now) <= 0.012 && is_equal_approx(run_chance(), chance_now), "level=%d rolls=%d hits=%d ratio=%.4f chance=%.2f" % [level_now, rolls, hits, roll_ratio, chance_now])
	check(lines, "default mix: regular sobos with some primes", mix_spawns >= 60 && mix_primes > 0 && mix_ratio >= 0.03 && mix_ratio <= 0.45, "spawns=%d primes=%d ratio=%.3f chance=%.2f mode_state=%d" % [mix_spawns, mix_primes, mix_ratio, chance_now, mode.state])
	check(lines, "prime level: a new run starts at 1 (11%) and follows the game's spawn stages", level_at_start == 1 && level_now >= level_at_start && level_now == prime_level.level_of(mode.spawn_pool.current_spawn_pool), "start=%d now=%d open_tiers=%s" % [level_at_start, level_now, mode.spawn_pool.current_spawn_pool])
	var level_shown: bool = is_instance_valid(level_label) && level_label.is_visible_in_tree() && level_label.get_parent() == level_label_parent() && level_label.text == word("level") % [level_now, roundi(chance_now * 100.0)]
	check(lines, "prime level: the line follows the visible layout and shows the level and its chance", level_shown, "text=%s" % (level_label.text if is_instance_valid(level_label) else "<none>"))

	# Game over: local board, rich presence "prime_best", Steam screenshot.
	# Exactly one game over per run. Fire it only while the run is still being played and the
	# game has not ended it; otherwise use the game's own game over (and its single POST).
	var over_path: String
	if over_scores.is_empty() && mode.state == SceneClassic.State.PLAYING:
		over_path = "selftest_emit"
		SignalBus.on_game_over.emit()
	else:
		over_path = "game_own(state=%d)" % mode.state
		# PREGAMEOVER: the game emits on_game_over itself when its own timer ends.
		var over_deadline: int = Time.get_ticks_msec() + 15000
		while over_scores.is_empty() && Time.get_ticks_msec() < over_deadline:
			await get_tree().process_frame
	await get_tree().create_timer(3.0, true).timeout
	var score_at_over: int = over_scores[0] if over_scores.size() > 0 else -1
	var count_before: int = board_before_over.size()
	# Out of the top only when the board is full and the score does not beat its last entry.
	var expect_in_top: bool = count_before < scores.LOCAL_MAX || score_at_over > int(board_before_over[-1].score)
	lines.append("gameover path=%s game_overs=%d score_at_over=%d mode_state=%d" % [over_path, over_scores.size(), score_at_over, mode.state])
	check(lines, "one game over per run", over_scores.size() == 1, "path=%s game_overs=%d" % [over_path, over_scores.size()])
	var windowed: bool = DisplayServer.get_name() != "headless"
	var recorded_ok: bool
	if expect_in_top:
		recorded_ok = scores.last_rank >= 1 && scores.local_scores.size() == mini(count_before + 1, scores.LOCAL_MAX)
	else:
		recorded_ok = scores.last_rank == -1 && scores.local_scores.size() == count_before
	check(lines, "gameover score recorded", scores.last_score == score_at_over && recorded_ok, "score=%d at_over=%d expect_in_top=%s rank=%d entries %d->%d" % [scores.last_score, score_at_over, expect_in_top, scores.last_rank, count_before, scores.local_scores.size()])
	var real_board_after: String = board_fingerprint(scores.SAVE_PATH)
	check(lines, "selftest writes only its own board", scores.save_path == scores.SELFTEST_SAVE_PATH && FileAccess.file_exists(scores.save_path) && real_board_after == real_board_before, "save_path=%s real_board %s -> %s" % [scores.save_path, real_board_before, real_board_after])
	# The first line up to the local rank, in the game's language.
	var board_header: String = word("board line").get_slice("%s", 0) % [score_at_over, scores.best_local()]
	check(lines, "board shown", scores.panel.visible && scores.label.text.begins_with(board_header) && scores.label.text.split("\n").size() <= 6 && scores.label.get_line_count() <= 6 && scores.panel.size.y <= 160.0 && scores.panel.inside_viewport(), "%s; rows=%d height=%.1f rect=%s viewport=%s" % [scores.label.text.get_slice("\n", 0), scores.label.get_line_count(), scores.panel.size.y, scores.panel.get_global_rect(), get_viewport().get_visible_rect()])
	if FileAccess.file_exists(mod_dir().path_join("online_selftest.flag")):
		# Wait for the result of that one game over's submission (it is queued with call_deferred).
		var online_deadline: int = Time.get_ticks_msec() + 6000
		while (online.busy || online.last_result.is_empty()) && Time.get_ticks_msec() < online_deadline:
			await get_tree().process_frame
		check(lines, "world online selftest uses loopback only", online.enabled && online.is_local_server(), "")
		check(lines, "world submit and own row retrieved", online.last_result.get("ok", false) && online.last_result.get("own_found", false), "path=%s result=%s" % [over_path, online.last_result])
		# The world line up to the number of players, in the game's language.
		var world_rank: String = word("world rank")
		var world_header: String = world_rank.substr(0, world_rank.rfind("%d")) % int(online.last_result.get("rank", 0))
		check(lines, "world board shown", scores.label.text.contains(world_header) && scores.label.text.split("\n").size() <= 6 && scores.label.get_line_count() <= 6 && scores.panel.size.y <= 160.0 && scores.panel.inside_viewport(), "rows=%d height=%.1f rect=%s viewport=%s" % [scores.label.get_line_count(), scores.panel.size.y, scores.panel.get_global_rect(), get_viewport().get_visible_rect()])
	check(lines, "steam leaderboard upload disconnected", SignalBus.on_game_over.is_connected(ScoreManager.on_game_over) == false, "")
	if SteamManager.steam_ready && windowed:
		check(lines, "steam screenshot written and tagged", scores.last_screenshot_handle > scores.INVALID_SCREENSHOT_HANDLE && scores.last_screenshot_tagged, "handle=%d tagged=%s" % [scores.last_screenshot_handle, scores.last_screenshot_tagged])
	else:
		lines.append("steam screenshot: not checked (steam_ready=%s display=%s)" % [SteamManager.steam_ready, DisplayServer.get_name()])
	if SteamManager.steam_ready:
		var own: String = SteamManager.steam.getFriendRichPresence(SteamManager.steam.getSteamID(), scores.PRESENCE_KEY)
		check(lines, "own prime_best published", own == str(scores.best_local()), "presence=%s best=%d friends_cached=%d" % [own, scores.best_local(), scores.friends.size()])
	SignalBus.on_game_over.disconnect(record_over)
	selftest_tie_ranks(lines)
	if windowed:
		get_viewport().get_texture().get_image().save_png(mod_dir().path_join("selftest_shot3.png"))
	await selftest_scores_screen(lines)
	selftest_send_toggle(lines, send_started_off)
	await selftest_screenshot_toggle(lines, screenshots_started_off)
	selftest_prime_toggle(lines)
	await selftest_guide_toggle(lines)
	finish_selftest(lines)


## "absent" or the file's MD5, so an overwrite of an existing board is caught, not only creation.
func board_fingerprint(path: String) -> String:
	return FileAccess.get_md5(path) if FileAccess.file_exists(path) else "absent"


func check(lines: PackedStringArray, what: String, ok: bool, detail: String) -> void:
	lines.append("check %s: %s%s" % [what, "OK" if ok else "FAIL", (" (" + detail + ")") if detail != "" else ""])


## Ranking edge cases on the real board code; the self-test board is restored afterwards.
func selftest_tie_ranks(lines: PackedStringArray) -> void:
	var backup: Array = scores.local_scores.duplicate(true)
	var full: Array = []
	for i in scores.LOCAL_MAX:
		full.append({"score": 100, "time": "t%d" % i})
	scores.local_scores = full.duplicate(true)
	var r_tie_full: int = scores.add_local_score(100)
	var size_after_tie: int = scores.local_scores.size()
	scores.local_scores = full.duplicate(true)
	var r_top: int = scores.add_local_score(150)
	scores.local_scores = [{"score": 200, "time": "a"}, {"score": 100, "time": "b"}]
	var r_tie_mid: int = scores.add_local_score(100)
	check(lines, "tie on a full board is out of the top", r_tie_full == -1 && size_after_tie == scores.LOCAL_MAX, "rank=%d size=%d" % [r_tie_full, size_after_tie])
	check(lines, "higher score on a full board is 1st", r_top == 1, "rank=%d" % r_top)
	check(lines, "tie ranks after the earlier run", r_tie_mid == 3, "rank=%d" % r_tie_mid)
	scores.local_scores = backup
	scores.save_scores()


## Waits until no request of the screen is in flight (local draws at once, a world read takes up to
## five seconds), then one more frame for what the answer drew.
func wait_screen_idle(screen) -> bool:
	await get_tree().process_frame
	var deadline: int = Time.get_ticks_msec() + 12000
	while screen.pending > 0 && Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame
	return screen.pending == 0


## The game's source button cycles local / steam; press it until `value` is shown.
func pick_source(screen, value: ScoresScreen.Source) -> void:
	if screen.source != value:
		screen._on_source_release_press()
	await wait_screen_idle(screen)


func shown_rows(screen) -> Array[LeaderboardEntry]:
	var rows: Array[LeaderboardEntry] = []
	for e: LeaderboardEntry in screen.entries:
		if e.disabled == false:
			rows.append(e)
	return rows


## Self test 9: the prime scores screen (spec §5). The game's ScoresScreen flow, with records from the
## prime local board and the prime world ranking. The local rows use the self-test board only;
## the world part runs only with online_selftest.flag against the loopback server.
func selftest_scores_base_layout(lines: PackedStringArray) -> void:
	var screen = scores_screen
	var original: ScoresScreen = original_scores_screen
	var menu: Menu = Menu._0
	menu.open_with_screen(original)
	original.source = ScoresScreen.Source.LOCAL
	original.refresh_buttons()
	original.refresh_leaderboard(false)
	for frame: int in 3:
		await get_tree().process_frame
	menu.change_screen(screen)
	await wait_screen_idle(screen)
	check(lines, "scores layout: native title", screen.side_title_text == "scores" && screen.side_title_text == original.side_title_text, "title=%s" % screen.side_title_text)
	check(lines, "scores layout: native mode row visible", screen.board_btn is SoboMenuButtonEnum && screen.board_btn.is_visible_in_tree(), "")
	check(lines, "scores layout: mode says prime", screen.board_btn.value_label.text == "prime", "value=%s" % screen.board_btn.value_label.text)
	check(lines, "scores layout: mode cannot be switched", screen.board_btn.disabled, "")
	check(lines, "scores layout: no extra heading", screen.find_child("PrimeHeading", true, false) == null, "")
	for member: String in ["board_btn", "source_btn", "friends_only_btn", "prev_btn", "my_score_btn", "next_btn", "clear_local_scores_btn"]:
		var actual: Control = screen.get(member)
		var expected: Control = original.get(member)
		check(lines, "scores layout: native position " + member, actual.get_global_rect().is_equal_approx(expected.get_global_rect()), "actual=%s native=%s" % [actual.get_global_rect(), expected.get_global_rect()])
	var selected: String = ScoreManager.selected_board
	screen.board_btn.release_press.emit()
	check(lines, "scores layout: mode signal does not select a Steam board", ScoreManager.selected_board == selected, "")


func selftest_scores_native_colours(lines: PackedStringArray) -> void:
	var members: Array[String] = ["board_btn", "source_btn", "friends_only_btn", "prev_btn", "my_score_btn", "next_btn", "clear_local_scores_btn", "clear_local_scores_confirm_btn"]
	var properties: Array[String] = ["highlight_color", "highlight_hover_color", "highlight_pressed_color", "highlight_disabled_color", "background_color", "background_hover_color", "background_pressed_color", "background_disabled_color"]
	for member: String in members:
		var same:= true
		for property: String in properties:
			var actual: Color = scores_screen.get(member).get(property)
			var expected: Color = original_scores_screen.get(member).get(property)
			same = same && actual.is_equal_approx(expected)
		check(lines, "scores colour: native " + member, same, "")
	var row_same:= true
	for property: String in properties:
		var actual: Color = scores_screen.entries[0].get(property)
		var expected: Color = original_scores_screen.entries[0].get(property)
		row_same = row_same && actual.is_equal_approx(expected)
	check(lines, "scores colour: native leaderboard row", row_same, "")


func selftest_scores_screen(lines: PackedStringArray) -> void:
	var menu: Menu = Menu._0
	var screen = scores_screen
	var original: ScoresScreen = original_scores_screen
	var screen_script: Script = load(mod_dir().path_join("prime_scores_screen.gd"))
	check(lines, "scores screen: menu scores opens the prime screen", screen != null && original != null && screen != original && menu.scores_screen == screen && screen.get_script() == screen_script && screen.get_parent() == original.get_parent(), "screen=%s original=%s" % [screen, original])
	if screen == null || original == null:
		return
	var steam_listeners:= 0
	for sig: Signal in [ScoreManager.steam_leaderboard_updated, ScoreManager.steam_leaderboard_failed, ScoreManager.steam_user_rank_updated]:
		for c: Dictionary in sig.get_connections():
			var listener: Callable = c.callable
			if listener.get_object() == screen:
				steam_listeners += 1
	check(lines, "scores screen: not connected to the author's Steam leaderboard", steam_listeners == 0, "connections=%d" % steam_listeners)
	var inside: bool = true
	for node: Variant in [screen.source_btn, screen.friends_only_btn, screen.leaderboard_container, screen.no_steam_button, screen.steam_failed_label, screen.clear_local_scores_btn, screen.clear_local_scores_confirm_btn, screen.my_score_btn, screen.prev_btn, screen.next_btn]:
		inside = inside && node is Node && screen.is_ancestor_of(node)
	check(lines, "scores screen: scene values kept on the copy", inside && screen.leaderboard_entry_ps == original.leaderboard_entry_ps && screen.parent_screen == original.parent_screen && screen.entries.size() == ScoresScreen.PAGE_SIZE, "nodes_inside=%s entries=%d parent=%s/%s" % [inside, screen.entries.size(), screen.parent_screen, original.parent_screen])
	selftest_scores_native_colours(lines)

	# Spec §5 (2026-10-30 11:46): the small game-over board must not cover the scores screen.
	var board_before: bool = scores.panel.visible
	menu.open_with_screen(menu.scores_screen)
	await wait_screen_idle(screen)
	await selftest_scores_base_layout(lines)
	check(lines, "scores screen: small board hidden while the scores screen is open", board_before && scores.panel.visible == false, "board_before=%s board_now=%s" % [board_before, scores.panel.visible])
	# Like the game's screen: it opens on the world when that can be used, otherwise on local.
	var usable: bool = online.enabled && SteamManager.steam_ready
	check(lines, "scores screen: opens on the world only when it can be used", screen.source == (ScoresScreen.Source.STEAM if usable else ScoresScreen.Source.LOCAL), "source=%d enabled=%s steam_ready=%s" % [screen.source, online.enabled, SteamManager.steam_ready])
	# Local: exactly the self-test board's ten rows (filled for this check, restored afterwards).
	var backup: Array = scores.local_scores.duplicate(true)
	var ten: Array = []
	for i in scores.LOCAL_MAX:
		ten.append({"score": 2000 - i * 2, "time": "selftest%d" % i})
	scores.local_scores = ten.duplicate(true)
	await pick_source(screen, ScoresScreen.Source.LOCAL)
	screen.refresh_leaderboard()
	var local_ok: bool = true
	for i in ScoresScreen.PAGE_SIZE:
		local_ok = local_ok && screen.entries[i].disabled == false && screen.entries[i].rank_label.text == str(i + 1) && screen.entries[i].score_label.text == str(ten[i].score)
	check(lines, "scores screen: local ten rows equal the self-test board", local_ok && screen.my_score_btn.disabled && screen.friends_only_btn.disabled, "first=%s last=%s" % [screen.entries[0].score_label.text, screen.entries[9].score_label.text])
	var real_before: String = board_fingerprint(scores.SAVE_PATH)
	screen._on_clear_local_scores_release_press()
	var asked: bool = screen.clear_local_scores_confirm_btn.visible && screen.clear_local_scores_btn.visible == false && scores.local_scores.size() == ten.size()
	screen._on_clear_local_scores_confirm_release_press()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(scores.save_path))
	check(lines, "scores screen: clear local scores asks first and clears only the prime board", asked && scores.local_scores.is_empty() && saved is Dictionary && (saved.get("local", [null]) as Array).is_empty() && screen.entries[0].disabled && board_fingerprint(scores.SAVE_PATH) == real_before, "asked=%s left=%d" % [asked, scores.local_scores.size()])
	# Coordinator's decision (2026-10-30): clearing the prime board also empties rich presence
	# "prime_best", in line with "a best of 0 is not published".
	if SteamManager.steam_ready:
		var presence_after_clear: String = SteamManager.steam.getFriendRichPresence(SteamManager.steam.getSteamID(), scores.PRESENCE_KEY)
		check(lines, "scores screen: clear local scores empties prime_best", presence_after_clear == "", "presence=%s" % presence_after_clear)
	else:
		lines.append("scores screen clear prime_best: not checked (steam_ready=false)")
	scores.local_scores = backup
	scores.save_scores()
	# Put the self-test board's best back into rich presence.
	scores.publish_best()

	var windowed: bool = DisplayServer.get_name() != "headless"
	if usable == false:
		# Like the game without Steam: the notice, and friends only and my score cannot be pressed.
		await pick_source(screen, ScoresScreen.Source.STEAM)
		var expected_text: String = word("world disabled") if online.enabled == false else word("no steam")
		check(lines, "scores screen: unusable world shows its notice", shown_rows(screen).is_empty() && screen.steam_failed_label.visible && screen.steam_failed_label.text == expected_text && screen.my_score_btn.disabled && screen.friends_only_btn.disabled, "text=%s my_score_disabled=%s friends_disabled=%s" % [screen.steam_failed_label.text, screen.my_score_btn.disabled, screen.friends_only_btn.disabled])
		lines.append("scores screen world pages: not checked (enabled=%s steam_ready=%s)" % [online.enabled, SteamManager.steam_ready])
	elif online.is_local_server():
		await selftest_scores_world(lines, screen)
	else:
		check(lines, "scores screen: world selftest uses loopback only", false, "server_url=%s" % online.server_url)
	if windowed:
		await get_tree().create_timer(0.5, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(mod_dir().path_join("selftest_scores.png"))
		lines.append("scores screen shot=%s" % mod_dir().path_join("selftest_scores.png"))
	menu.change_screen(menu.game_over_screen)
	await get_tree().process_frame
	check(lines, "scores screen: small board shown again on the game-over screen", board_before && scores.panel.visible, "board_before=%s board_now=%s" % [board_before, scores.panel.visible])
	if menu.visible:
		menu.try_close()


## Ten more real players on the loopback server, each above the player's own best, so the
## player is at rank 11 or lower. The native POST limit (10 per 60 s per IP) is waited out.
## Then the screen is opened again right away: the game's flow must show the new count and rows.
func selftest_scores_world(lines: PackedStringArray, screen) -> void:
	var own_before: Dictionary = await online.fetch_own_rank()
	var base_score: int = int(own_before.get("best", 0)) if own_before.get("ok") == true else 0
	var sent:= 0
	var refused: Array = []
	var deadline: int = Time.get_ticks_msec() + 100000
	while sent < 10 && Time.get_ticks_msec() < deadline:
		# A Steam ID no real account has (7656119 0000 + six digits) and a random key, per filler.
		var filler_id: String = "76561190000%06d" % (randi() % 1000000)
		var body:= {"mod": "prime_sobo", "mod_version": online.MOD_VERSION, "player_id": filler_id,
			"player_key": Crypto.new().generate_random_bytes(32).hex_encode(), "name": "selftest filler %d" % sent, "score": base_score + 2 + sent * 2,
			"duration_s": 86400, "prime_chance": prime_level.chance_of(1)}
		var answer: Dictionary = await online.request_json("/v1/scores", HTTPClient.METHOD_POST, JSON.stringify(body), Time.get_ticks_msec() + online.TIMEOUT_MS)
		var status: int = int(answer.get("status", 0))
		if status == 200:
			sent += 1
		elif status == 429:
			await get_tree().create_timer(5.0, true).timeout
		else:
			refused.append(status)
			break
	var own: Dictionary = await online.fetch_own_rank()
	check(lines, "scores screen: eleven or more world players", sent == 10 && own.get("ok") == true && int(own.get("players", 0)) >= 11 && int(own.get("rank", 0)) >= 11, "sent=%d refused=%s own=%s" % [sent, refused, own])
	if own.get("ok") != true:
		return
	var own_id: int = SteamManager.steam.getSteamID()
	# Opened right after the POSTs: the page count comes from the new number of players (spec §7).
	Menu._0.change_screen(screen)
	await wait_screen_idle(screen)
	var pages: int = ceili(float(int(own.players)) / float(ScoresScreen.PAGE_SIZE))
	check(lines, "scores screen: opened right after sending shows the new players and page 1", screen.source == ScoresScreen.Source.STEAM && screen.get_page_count() == pages && screen.next_btn.disabled == false && screen.entries[0].rank_label.text == "1" && screen.steam_failed_label.visible == false, "pages=%d expected=%d first=%s" % [screen.get_page_count(), pages, screen.entries[0].rank_label.text])
	screen._on_next_release_press()
	await wait_screen_idle(screen)
	var page2: Dictionary = await online.fetch_page(ScoresScreen.PAGE_SIZE)
	var page2_rows: Array = online.steam_rows(page2.get("entries", []))
	var same_rows: bool = page2_rows.size() > 0 && shown_rows(screen).size() == page2_rows.size()
	if same_rows:
		for i in page2_rows.size():
			same_rows = same_rows && screen.entries[i].steam_id == page2_rows[i].steam_id && screen.entries[i].rank_label.text == str(page2_rows[i].global_rank) && screen.entries[i].score_label.text == str(page2_rows[i].score) && screen.entries[i].name_label.text != ""
	check(lines, "scores screen: world page 2 starts at rank 11 with the server's rows (Steam ID, name, score)", screen.page == 1 && screen.entries[0].rank_label.text == "11" && same_rows, "page=%d first=%s rows=%d/%d" % [screen.page, screen.entries[0].rank_label.text, shown_rows(screen).size(), page2_rows.size()])
	screen._on_prev_release_press()
	await wait_screen_idle(screen)
	# The game's hover mark is for the gamepad: with the mouse, Ui.p_mouse sets currently_hovered to
	# the button under the mouse every frame (null without window focus), so it would replace the
	# mark at once, as on the game's own screen. Press my score the gamepad way (hovering it), then
	# give the input device back. Only a click switches the game back to the mouse, a move does not.
	var device_before: PlayerInput.InputDevice = PlayerInput.input_device
	PlayerInput.set_input_device(PlayerInput.InputDevice.GAMEPAD)
	SoboButton.currently_hovered = screen.my_score_btn
	screen._on_my_score_release_press()
	await wait_screen_idle(screen)
	var own_page: int = floori(float(int(own.rank) - 1) / float(ScoresScreen.PAGE_SIZE))
	var hovered: LeaderboardEntry = SoboButton.currently_hovered as LeaderboardEntry
	var marked: bool = hovered != null && screen.entries.has(hovered) && hovered.steam_id == own_id && hovered.score_label.text == str(int(own.best))
	check(lines, "scores screen: my score jumps to the own page and hovers the own row (Steam ID)", screen.page == own_page && screen.steam_user_rank == int(own.rank) && marked, "page=%d expected=%d rank=%d hovered=%s device=%d" % [screen.page, own_page, screen.steam_user_rank, SoboButton.currently_hovered, PlayerInput.input_device])
	var windowed: bool = DisplayServer.get_name() != "headless"
	if windowed:
		await get_tree().create_timer(0.5, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(mod_dir().path_join("selftest_scores_world.png"))
	PlayerInput.set_input_device(device_before)
	# Friends only: the loopback fillers are not the player's Steam friends, so only the player is listed.
	screen._on_friends_only_release_press()
	await wait_screen_idle(screen)
	var friends: Array[LeaderboardEntry] = shown_rows(screen)
	check(lines, "scores screen: friends only lists only the player", screen.friends_only && friends.size() == 1 && friends[0].steam_id == own_id && friends[0].rank_label.text == "1" && friends[0].score_label.text == str(int(own.best)), "rows=%d" % friends.size())
	screen._on_friends_only_release_press()
	await wait_screen_idle(screen)


## Self test 10: prime mode on/off (spec §7), in prime_sobo_settings_selftest.json only.
## Exercise the screenshot choice only in the self-test's settings and local board.
func selftest_screenshot_toggle(lines: PackedStringArray, started_off: bool) -> void:
	var real_settings_before: String = board_fingerprint(prime_settings.PATH)
	check(lines, "screenshot toggle: starts off in the self-test file", started_off && prime_settings.path == prime_settings.SELFTEST_PATH, "")
	var placed: bool = screenshot_toggle != null && send_toggle != null && screenshot_toggle.get_parent() == send_toggle.get_parent() && screenshot_toggle.get_index() == send_toggle.get_index() + 1 && screenshot_toggle.label != send_toggle.label && screenshot_toggle.bool_circles != send_toggle.bool_circles && screenshot_toggle.is_ancestor_of(screenshot_toggle.bool_circles) && screenshot_toggle.label.text == word(SCREENSHOT_TEXT) && screenshot_toggle.tooltip_text == word("save screenshots description")
	check(lines, "screenshot toggle: under send scores with its own nodes", placed, "")
	if screenshot_toggle == null:
		return
	screenshot_toggle.release_press.emit()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(prime_settings.SELFTEST_PATH))
	check(lines, "screenshot toggle: off is saved", not prime_settings.save_screenshots && not screenshot_toggle.bool_circles.visible && saved is Dictionary && saved.get("save_screenshots") == false, "")
	var handle_before: int = scores.last_screenshot_handle
	var sending_before: bool = prime_settings.send_scores
	set_send_scores(false)
	await scores.on_game_over()
	check(lines, "screenshot toggle: off leaves the Steam handle unchanged", scores.last_screenshot_handle == handle_before, "")
	set_send_scores(sending_before)
	screenshot_toggle.release_press.emit()
	check(lines, "screenshot toggle: on is saved", prime_settings.save_screenshots && screenshot_toggle.bool_circles.visible && JSON.parse_string(FileAccess.get_file_as_string(prime_settings.SELFTEST_PATH)).get("save_screenshots") == true, "")
	check(lines, "screenshot toggle: real settings untouched", board_fingerprint(prime_settings.PATH) == real_settings_before, "")


## The off part runs without a single frame in between (no await): with the switch off the game's
## Steam upload, live score and achievements are connected again, so no play may happen meanwhile.
## The next run is started the way the game starts one (its on_game_mode_start), without play.
func selftest_send_toggle(lines: PackedStringArray, started_off: bool) -> void:
	var real_settings_before: String = board_fingerprint(prime_settings.PATH)
	check(lines, "send toggle: off at the start", started_off, "")
	var placed: bool = send_toggle != null && prime_toggle != null && send_toggle.get_parent() == prime_toggle.get_parent() && send_toggle.get_index() == prime_toggle.get_index() + 1 && send_toggle.label != prime_toggle.label && send_toggle.label.text == word(SEND_TEXT) && prime_toggle.label.text == word(TOGGLE_TEXT) && send_toggle.bool_circles != prime_toggle.bool_circles && send_toggle.is_ancestor_of(send_toggle.bool_circles) && send_toggle.tooltip_text == send_description()
	check(lines, "send toggle: send scores right under prime balls, own nodes", placed, "toggle=%s" % [send_toggle])
	if send_toggle == null:
		return
	send_toggle.release_press.emit()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(prime_settings.SELFTEST_PATH))
	check(lines, "send toggle: off is written to the self-test file and stops sending", prime_settings.send_scores == false && online.send_scores == false && send_toggle.bool_circles.visible == false && saved is Dictionary && saved.get("send_scores") == false, "saved=%s" % [saved])
	send_toggle.release_press.emit()
	check(lines, "send toggle: on again sends", prime_settings.send_scores && online.send_scores && send_toggle.bool_circles.visible, "")
	check(lines, "send toggle: the real settings file is untouched", board_fingerprint(prime_settings.PATH) == real_settings_before, "")


func selftest_prime_toggle(lines: PackedStringArray) -> void:
	var menu: Menu = Menu._0
	var real_settings_before: String = board_fingerprint(prime_settings.PATH)
	check(lines, "prime toggle: self-test settings file", prime_settings.path == prime_settings.SELFTEST_PATH, "path=%s" % prime_settings.path)
	var game_screen: MenuScreen = menu.settings_mobile_screen if OS.has_feature("mobile") else menu.game_settings_screen
	var model: SoboMenuButtonBool = game_screen.get("show_instructions_control")
	var toggle_ok: bool = prime_toggle != null && prime_toggle.get_parent() == model.get_parent() && prime_toggle.get_index() == model.get_index() + 1 && prime_toggle.label != model.label && prime_toggle.label.text == word(TOGGLE_TEXT) && model.label.text != word(TOGGLE_TEXT) && prime_toggle.bool_circles != model.bool_circles && prime_toggle.is_ancestor_of(prime_toggle.bool_circles)
	var copied_game_handler:= false
	if prime_toggle != null:
		for c: Dictionary in prime_toggle.release_press.get_connections():
			copied_game_handler = copied_game_handler || (c.callable as Callable).get_object() == game_screen
	check(lines, "prime toggle: prime balls under show instructions on the game settings screen, own nodes, not the game's handler", toggle_ok && copied_game_handler == false && prime_toggle.tooltip_text == toggle_description(), "toggle=%s copied_handler=%s" % [prime_toggle, copied_game_handler])
	check(lines, "prime toggle: on at the start", prime_settings.enabled && run_prime && prime_toggle.bool_circles.visible && menu.scores_screen == scores_screen, "enabled=%s run_prime=%s" % [prime_settings.enabled, run_prime])

	# Off while a run is in progress: the scores screen at once, this run stays prime.
	prime_toggle.release_press.emit()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(prime_settings.SELFTEST_PATH))
	check(lines, "prime toggle: off is written to the self-test file", prime_settings.enabled == false && prime_toggle.bool_circles.visible == false && saved is Dictionary && saved.get("enabled") == false, "saved=%s" % [saved])
	check(lines, "prime toggle: off switches scores to the game's screen at once", menu.scores_screen == original_scores_screen, "")
	check(lines, "prime toggle: off mid-run keeps this run prime", run_prime && SignalBus.on_game_over.is_connected(ScoreManager.on_game_over) == false && AchievementTracker.disable_achievements, "")
	# The next run: the game's own.
	on_game_mode_start(GameModeManager.current_scene)
	var hits:= 0
	for i in 20000:
		if roll_prime():
			hits += 1
	var upload_back: bool = SignalBus.on_game_over.is_connected(ScoreManager.on_game_over)
	var live_back: bool = SignalBus.on_gain_score.is_connected(ScoreManager.gain_score) && SignalBus.on_gain_score.is_connected(gain_score_offline) == false
	var achievements_back: bool = AchievementTracker.disable_achievements == (GameModeManager.run_is_ranked() == false)
	var local_before: Array = scores.local_scores.duplicate(true)
	var panel_before: bool = scores.panel.visible
	scores.panel.visible = false
	# Only this mod's handler, not the signal (the signal would now upload to the author's board).
	scores.on_game_over()
	var no_prime_record: bool = scores.panel.visible == false && scores.local_scores == local_before && online.busy == false
	# Back on before any frame passes.
	prime_toggle.release_press.emit()
	on_game_mode_start(GameModeManager.current_scene)
	scores.panel.visible = panel_before
	check(lines, "prime toggle: off, the next run never rolls a prime", hits == 0, "hits=%d of 20000" % hits)
	check(lines, "prime toggle: off, the next run sends to Steam and keeps achievements as without the mod", upload_back && live_back && achievements_back, "upload=%s live=%s achievements=%s (the game decides %s)" % [upload_back, live_back, achievements_back, GameModeManager.run_is_ranked() == false])
	check(lines, "prime toggle: off, no small board, no prime record, no world send", no_prime_record, "")
	# On again: everything back on the prime side.
	hits = 0
	for i in 20000:
		if roll_prime():
			hits += 1
	check(lines, "prime toggle: on again, the next run is prime", run_prime && prime_settings.enabled && absf(float(hits) / 20000.0 - run_chance()) <= 0.012 && SignalBus.on_game_over.is_connected(ScoreManager.on_game_over) == false && SignalBus.on_gain_score.is_connected(gain_score_offline) && SignalBus.on_gain_score.is_connected(ScoreManager.gain_score) == false && AchievementTracker.disable_achievements && menu.scores_screen == scores_screen, "hits=%d" % hits)
	# A continued save holding prime balls is a prime run (the game saves only when it closes). The
	# game's own save classes with one regular and then one prime sobo; only the reading is checked.
	var saved_state:= GameStateClassic.new()
	var regular_state:= SoboState.new()
	regular_state.size = 4
	saved_state.sobos_in_stack.append(regular_state)
	var regular_only: bool = state_holds_primes(saved_state)
	var prime_state:= SoboState.new()
	prime_state.size = PRIMES[0]
	saved_state.sobos_selectable.append(prime_state)
	check(lines, "prime toggle: a continued save holding prime balls is read as prime", regular_only == false && state_holds_primes(saved_state), "regular_only=%s" % regular_only)
	# The save that was there when the latest run began is not that run's (the run was lost before
	# it saved): it resumes as prime even with no prime ball left and off remembered. Only the
	# decision, on the self-test file; no run is started and the hooks above are not touched.
	prime_settings.set_enabled(false)
	var off_run: bool = prime_settings.start_run(false, false, "selftest-older-save")
	var older_resumed: bool = prime_settings.start_run(true, false, "selftest-older-save")
	prime_settings.set_enabled(true)
	prime_settings.start_run(false, false, prime_settings.save_id_of(false, ""))
	check(lines, "prime toggle: the save that was there before the latest run resumes as prime", off_run == false && older_resumed && prime_settings.enabled && prime_settings.run_prime, "off_run=%s resumed=%s" % [off_run, older_resumed])
	# A run begun over a save whose MD5 could not be read is remembered as unreadable, not as no save:
	# a save resumed after it (read normally then) is prime.
	prime_settings.set_enabled(false)
	var unread_run: bool = prime_settings.start_run(false, false, prime_settings.save_id_of(true, ""))
	var unread_remembered: Variant = prime_settings.older_save
	var unread_resumed: bool = prime_settings.start_run(true, false, "selftest-readable-save")
	prime_settings.set_enabled(true)
	prime_settings.start_run(false, false, prime_settings.save_id_of(false, ""))
	check(lines, "prime toggle: a save resumed after a run begun over an unreadable save is prime", unread_run == false && unread_remembered == prime_settings.UNREADABLE_SAVE && unread_resumed && prime_settings.run_prime, "run=%s remembered=%s resumed=%s" % [unread_run, unread_remembered, unread_resumed])
	check(lines, "prime toggle: the real settings file is untouched", board_fingerprint(prime_settings.PATH) == real_settings_before, "%s -> %s" % [real_settings_before, board_fingerprint(prime_settings.PATH)])


## Self test: the how-to-play guide shows only the game's own words. Prime balls is switched in the
## game's settings, not on the guide (commander 2026-11-12 21:54).
func selftest_guide_toggle(lines: PackedStringArray) -> void:
	await start_default_run()
	for i in 10:
		await get_tree().process_frame
	var mode: GameScene = GameModeManager.current_scene if is_instance_valid(GameModeManager.current_scene) else null
	var guide: Instructions = mode.instructions if mode != null && is_instance_valid(mode.instructions) else null
	if SettingsManager.settings.show_instructions == false || guide == null || is_instance_valid(guide.current_control) == false:
		lines.append("guide toggle: not checked (show_instructions=%s guide=%s)" % [SettingsManager.settings.show_instructions, guide])
		return
	var found: Array[String] = []
	for label: Node in Ui._0.find_children("*", "Label", true, false):
		var shown_label: Label = label as Label
		if shown_label.is_visible_in_tree() && shown_label.text == word(TOGGLE_TEXT):
			found.append(str(shown_label.get_path()))
	check(lines, "guide toggle: no prime balls switch on the game's guide", guide.current_control.is_visible_in_tree() && found.is_empty(), "found=%s" % [found])


## Starts the default mode the way the game does (GameModeManager.start_default_game_mode), but
## awaitable and without the start juice.
func start_default_run() -> void:
	var game_mode: GameMode = GameModeManager.get_default_game_mode()
	GameModeManager.begin_run_for_mode(game_mode)
	await GameModeManager.start_game_mode(game_mode, false)


## Waits until a different run is the game's current mode (start_game_mode waits a frame first).
func wait_new_run(before: Node) -> bool:
	for i in 120:
		if is_instance_valid(GameModeManager.current_scene) && GameModeManager.current_scene != before:
			return true
		await get_tree().process_frame
	return false


## Untyped on purpose: the self test keeps sobos across frames, and they may be freed by then.
func alive(s: Variant) -> bool:
	return is_instance_valid(s) && (s as Object).is_queued_for_deletion() == false


func count_primes() -> int:
	var n:= 0
	for s: Sobo in SoboManager.all_sobos:
		if is_prime_sobo(s):
			n += 1
	return n


func finish_selftest(lines: PackedStringArray) -> void:
	var f:= FileAccess.open(mod_dir().path_join("selftest_result.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	for l: String in lines:
		print("%s selftest %s" % [MOD_TAG, l])
	GameModeManager.end_game_mode()
	get_tree().quit()
