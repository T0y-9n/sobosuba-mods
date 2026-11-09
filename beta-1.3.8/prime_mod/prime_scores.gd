extends CanvasLayer
## Prime-mode scores, kept apart from the game's own (Steam) leaderboard.
## - Local top 10 in user://prime_sobo_scores.json.
## - Shared only between Steam friends who run this mod: each player's best is published as the
##   rich presence key "prime_best"; friends' bests are read the same way ScoreManager reads live
##   scores and remembered locally, so the board keeps them after they go offline.
## - At game over: shows the board and saves a Steam screenshot (local library) tagged with the score.
## Created by prime_sobo.gd.

const SAVE_PATH:= "user://prime_sobo_scores.json"
const SELFTEST_SAVE_PATH:= "user://prime_sobo_scores_selftest.json"
const PRESENCE_KEY:= "prime_best"
const LOCAL_MAX:= 10
const FRIEND_POLL_INTERVAL:= 15.0
const SCREENSHOT_DELAY:= 0.8
## Steamworks k_ScreenshotInvalidHandle.
const INVALID_SCREENSHOT_HANDLE:= 0

var local_scores: Array = []
var friends: Dictionary = { }
## prime_sobo.gd points this at SELFTEST_SAVE_PATH before _ready when the self test runs.
var save_path:= SAVE_PATH
var last_rank:= -1
var last_score:= -1
var last_screenshot_handle:= -1
var last_screenshot_tagged:= false
var _poll_t:= FRIEND_POLL_INTERVAL

var panel: PanelContainer
var label: Label
var online: Node = null
var _round_started_ms:= 0
var _round_finished:= false
## Counts game overs, so the screenshot after the wait can tell whether it is still the same one.
var _over_serial:= 0
## The board belongs on screen after a game over, until the next game starts.
var _board_wanted:= false
## Hidden while the prime scores screen is open (it would cover the source row). Set by prime_sobo.gd.
var _board_suppressed:= false


func _ready() -> void:
	layer = 100
	load_scores()
	build_panel()
	_round_started_ms = Time.get_ticks_msec()
	SignalBus.on_game_over.connect(on_game_over)
	SignalBus.on_game_mode_start.connect(on_game_mode_start)
	if online != null:
		online.updated.connect(on_world_updated)
	if SteamManager.steam_ready:
		connect_steam_signals()
	else:
		SteamManager.steam_initialized.connect(connect_steam_signals, CONNECT_ONE_SHOT)


## requestFriendRichPresence answers asynchronously; values are read when Steam says they arrived.
func connect_steam_signals() -> void:
	var steam: Object = SteamManager.steam
	if steam && steam.has_signal("friend_rich_presence_update") && steam.is_connected("friend_rich_presence_update", on_friend_presence) == false:
		steam.connect("friend_rich_presence_update", on_friend_presence)


func on_friend_presence(steam_id: int, app_id: int) -> void:
	if app_id != SteamManager.APP_ID || steam_id == SteamManager.steam.getSteamID():
		return
	if remember_friend(steam_id):
		save_scores()


func build_panel() -> void:
	panel = load((get_script() as Script).resource_path.get_base_dir().path_join("prime_board.gd")).new()
	add_child(panel)
	label = panel.get_node("Scores") as Label


func load_scores() -> void:
	if FileAccess.file_exists(save_path) == false:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if parsed is Dictionary:
		local_scores = parsed.get("local", [])
		friends = parsed.get("friends", { })


func save_scores() -> void:
	var f:= FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"local": local_scores, "friends": friends}, "\t"))


func best_local() -> int:
	return int(local_scores[0].score) if local_scores.size() > 0 else 0


## "clear local scores" on the prime scores screen: only this mod's local top 10 in save_path.
## Remembered friends stay; the game's own local scores are never touched.
## The best is now 0, which is never published, so rich presence "prime_best" is emptied too
## (an empty value deletes the key).
func clear_local_scores() -> void:
	local_scores = []
	save_scores()
	if SteamManager.steam_ready:
		SteamManager.steam.setRichPresence(PRESENCE_KEY, "")


## Inserted after older entries with the same score, so a tie never outranks an earlier run.
## Returns the new entry's rank, or -1 when it falls outside the top LOCAL_MAX.
func add_local_score(score: int) -> int:
	var i:= 0
	while i < local_scores.size() && int(local_scores[i].score) >= score:
		i += 1
	if i >= LOCAL_MAX:
		return -1
	local_scores.insert(i, {"score": score, "time": Time.get_datetime_string_from_system()})
	if local_scores.size() > LOCAL_MAX:
		local_scores.resize(LOCAL_MAX)
	save_scores()
	return i + 1


func _process(dt: float) -> void:
	if SteamManager.steam_ready == false:
		return
	_poll_t += dt
	if _poll_t < FRIEND_POLL_INTERVAL:
		return
	_poll_t = 0.0
	publish_best()
	refresh_friends()


## Re-published on every poll: the game's own settings toggle calls clearRichPresence().
func publish_best() -> void:
	if SteamManager.steam_ready && best_local() > 0:
		SteamManager.steam.setRichPresence(PRESENCE_KEY, str(best_local()))


func refresh_friends() -> void:
	if SteamManager.steam_ready == false:
		return
	var steam: Object = SteamManager.steam
	var changed:= false
	for i in steam.getFriendCount(SteamManager.FRIEND_FLAG_IMMEDIATE):
		var steam_id: int = steam.getFriendByIndex(i, SteamManager.FRIEND_FLAG_IMMEDIATE)
		var game_info: Dictionary = steam.getFriendGamePlayed(steam_id)
		if game_info.is_empty() || int(game_info.id) != SteamManager.APP_ID:
			continue
		# The answer arrives later through friend_rich_presence_update; whatever Steam already
		# holds for this friend is read now as well.
		steam.requestFriendRichPresence(steam_id)
		if remember_friend(steam_id):
			changed = true
	if changed:
		save_scores()


## Returns true when the stored best for this friend changed.
func remember_friend(steam_id: int) -> bool:
	var steam: Object = SteamManager.steam
	var text: String = steam.getFriendRichPresence(steam_id, PRESENCE_KEY)
	if text.is_valid_int() == false:
		return false
	var key:= str(steam_id)
	var best:= int(text)
	if friends.has(key) && int(friends[key].best) == best:
		return false
	friends[key] = {"name": steam.getFriendPersonaName(steam_id), "best": best, "seen": Time.get_datetime_string_from_system()}
	return true


func board_text(score: int, rank: int) -> String:
	return panel.board_text(score, rank, best_local(), friends, online != null && online.enabled, online.world_text if online != null else "")


## While the prime scores screen is open the board hides; it comes back when that screen closes.
func set_board_suppressed(value: bool) -> void:
	_board_suppressed = value
	refresh_board_visibility()


func refresh_board_visibility() -> void:
	panel.visible = _board_wanted && not _board_suppressed


func on_game_mode_start(_scene: GameScene) -> void:
	_board_wanted = false
	refresh_board_visibility()
	_round_finished = false
	_round_started_ms = Time.get_ticks_msec()
	if online != null:
		online.start_run()


func on_world_updated(_text: String) -> void:
	if _round_finished && _board_wanted:
		label.text = board_text(last_score, last_rank)


func on_game_over() -> void:
	# A run started with prime mode off (spec §7) is the game's own: no board, record, screenshot or send.
	if get_parent().run_prime == false:
		return
	var score: int = ScoreManager.current_score
	_round_finished = true
	_over_serial += 1
	var serial: int = _over_serial
	last_score = score
	last_rank = add_local_score(score)
	publish_best()
	refresh_friends()
	label.text = board_text(score, last_rank)
	_board_wanted = true
	refresh_board_visibility()
	if online != null && online.enabled && not Engine.get_meta("special_sobo_run", false):
		var duration_s: int = int((Time.get_ticks_msec() - _round_started_ms) / 1000)
		online.submit_score.call_deferred(score, duration_s, get_parent().run_chance())
	print("[prime_sobo] game over: score=%d local_rank=%d best=%d friends=%d" % [score, last_rank, best_local(), friends.size()])
	if not get_parent().prime_settings.save_screenshots:
		return
	await get_tree().create_timer(SCREENSHOT_DELAY, true).timeout
	await RenderingServer.frame_post_draw
	# A next run (or another game over) in the meantime: the screen is no longer this score's.
	if serial != _over_serial or _round_finished == false:
		print("[prime_sobo] screenshot skipped: the game over it was for is over")
		return
	if get_parent().prime_settings.save_screenshots:
		save_steam_screenshot(score)


## Writes into the player's local Steam screenshot library; uploading stays the player's choice.
func save_steam_screenshot(score: int) -> void:
	if SteamManager.steam_ready == false:
		print("[prime_sobo] screenshot skipped: steam not ready")
		return
	var img: Image = get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	last_screenshot_tagged = false
	var handle: int = SteamManager.steam.writeScreenshot(img.get_data(), img.get_width(), img.get_height())
	last_screenshot_handle = handle
	if handle == INVALID_SCREENSHOT_HANDLE:
		push_warning("[prime_sobo] steam screenshot failed: writeScreenshot returned an invalid handle")
		return
	var tagged: bool = SteamManager.steam.setLocation(handle, panel.word("screenshot location") % score)
	last_screenshot_tagged = tagged
	print("[prime_sobo] steam screenshot handle=%d tagged=%s size=%dx%d" % [handle, tagged, img.get_width(), img.get_height()])
