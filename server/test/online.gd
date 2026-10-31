extends SceneTree
## Standalone Godot only; no sobosuba assets, autoloads, or game launch.
var failures:= 0
func check(ok: bool, what: String) -> void:
	print("ONLINE_CHECK ", "OK " if ok else "FAIL ", what)
	if not ok:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args:= OS.get_cmdline_user_args()
	var expected_rank: int = int(args[5])
	var script_path: String = args[0]
	if not FileAccess.file_exists(script_path):
		check(false, "online transport script is present")
		quit(1)
		return
	var script: Script = load(script_path)
	if script == null or not script.can_instantiate():
		check(false, "online transport compiles")
		quit(1)
		return
	var own_steam_id: String = args[6]
	var legacy: bool = args[7] == "legacy"
	var cfg:= ConfigFile.new()
	cfg.set_value("online", "enabled", false)
	cfg.set_value("online", "server_url", args[1])
	# The name in online.cfg is no longer used: the board shows the Steam name (spec §8).
	cfg.set_value("online", "name", "cfg name")
	var config_path: String = args[2].path_join("online.cfg")
	check(cfg.save(config_path) == OK, "disabled config written to real file")
	var online: Node = script.new()
	online.config_path = config_path
	online.identity_path = args[2].path_join("identity.json")
	root.add_child(online)
	# The lines are checked in Japanese (prime_text.gd), and once more in English below.
	TranslationServer.set_locale("ja")
	check(online.MOD_VERSION == "1.2.3-1.0.0", "MOD_VERSION is 1.2.3-1.0.0")
	var disabled: Dictionary = await online.submit_score(100, 20, 0.10)
	check(disabled.is_empty() and not FileAccess.file_exists(online.identity_path), "disabled is silent and creates no identity")
	cfg.set_value("online", "enabled", true)
	check(cfg.save(config_path) == OK, "enabled config written to real file")
	online.reload_config()
	# Not connected to Steam (no Steam ID from the game): nothing is sent and no key file is made.
	var no_steam: Dictionary = await online.submit_score(100, 20, 0.10)
	check(no_steam.get("ok", true) == false and online.world_text == "Steam に繋がっていない" and not online.busy and not FileAccess.file_exists(online.identity_path), "without a Steam ID nothing is sent: %s" % online.world_text)
	online.steam_id = "not a steam id"
	check((await online.submit_score(100, 20, 0.10)).get("ok", true) == false and not FileAccess.file_exists(online.identity_path), "a malformed Steam ID is not sent")
	# The game sets these from Steam (prime_sobo.gd): the player's Steam ID and Steam name.
	online.steam_id = own_steam_id
	online.player_name = "Godot player"
	# "send scores" off (the default, spec §8): enabled and on Steam, yet nothing is sent and no key is made.
	check(online.send_scores == false, "send scores is off by default")
	var not_sent: Dictionary = await online.submit_score(100, 20, 0.10)
	check(not_sent.get("ok", true) == false and not_sent.get("not_sent", false) and online.world_text == "世界ランキングに送っていない (設定の 点数を送る)" and not online.busy and not FileAccess.file_exists(online.identity_path), "send scores off sends nothing: %s %s" % [not_sent, online.world_text])
	TranslationServer.set_locale("en")
	await online.submit_score(100, 20, 0.10)
	check(online.world_text == "not sent to the world ranking (send scores in settings)", "in English the line is English: %s" % online.world_text)
	TranslationServer.set_locale("ja")
	online.send_scores = true
	var legacy_key: String = ""
	if legacy:
		# A 0.1.0 key file (random UUID + key): the key is kept, the UUID is not sent any more.
		var crypto:= Crypto.new()
		legacy_key = crypto.generate_random_bytes(32).hex_encode()
		var old_file:= FileAccess.open(online.identity_path, FileAccess.WRITE)
		old_file.store_string(JSON.stringify({"player_id": "0f8fad5b-d9cb-469f-a165-70867728950e", "player_key": legacy_key}))
		old_file.close()
	var result: Dictionary = await online.submit_score(100, 20, 0.10)
	check(result.get("ok", false) and result.get("rank", 0) == expected_rank and result.get("best", 0) == 100, "real POST produces own rank")
	check(online.world_text.contains("世界 %d 位 / " % expected_rank), "real GET appears in world board")
	check(result.get("own_found", false), "own player row retrieved from real server")
	check(online.world_text.contains("←あなた") == (expected_rank <= 3), "only actual around you row marks the displayed own rank")
	var identity_before: String = FileAccess.get_file_as_string(online.identity_path)
	var identity: Variant = JSON.parse_string(identity_before)
	if legacy:
		check(identity is Dictionary and identity.get("player_key") == legacy_key, "the 0.1.0 key is reused")
	else:
		check(identity is Dictionary and str(identity.get("player_key", "")).length() == 64 and identity.keys() == ["player_key"], "only the random key is stored (no UUID, no Steam ID): %s" % [identity])
	# Rows are checked for the Steam ID form before they are drawn (spec §8).
	var good_row:= {"rank": 1, "steam_id": own_steam_id, "name": "a", "best": 2}
	check(online.valid_entries([good_row]), "a row with a SteamID64 is accepted")
	for bad: Variant in ["76561198", 76561198000000000, null, "0f8fad5b-d9cb-469f-a165-70867728950e"]:
		var row: Dictionary = good_row.duplicate()
		row.steam_id = bad
		check(not online.valid_entries([row]), "a row with steam_id %s is refused" % [bad])
	var no_id: Dictionary = good_row.duplicate()
	no_id.erase("steam_id")
	check(not online.valid_entries([no_id]), "a row without steam_id is refused")
	# Friends only: the player's own Steam ID and friends' IDs; only listed players on the board come back.
	var stranger:= "76561190000000001"
	var friends: Dictionary = await online.fetch_friends(PackedStringArray([stranger, own_steam_id]))
	check(friends.get("ok", false) and friends.entries.size() == 1 and friends.entries[0].steam_id == own_steam_id and int(friends.entries[0].rank) == expected_rank and int(friends.entries[0].best) == 100, "friends: only the own row, with the world rank: %s" % [friends])
	# More than 100 IDs are asked in parts of 100 (the server's limit); the own row is in the second part.
	var many:= PackedStringArray()
	for i in 150:
		many.append("765611900000%05d" % (i + 10))
	many.insert(120, own_steam_id)
	var many_friends: Dictionary = await online.fetch_friends(many)
	check(many_friends.get("ok", false) and many_friends.entries.size() == 1 and many_friends.entries[0].steam_id == own_steam_id, "friends: 151 IDs are read in parts and the own row is found: %s" % [many_friends])
	check((await online.fetch_friends(PackedStringArray())).is_empty(), "friends: no IDs is refused before any request")
	check((await online.fetch_friends(PackedStringArray([own_steam_id, "nope"]))).is_empty(), "friends: a malformed ID is refused before any request")
	# Measure the same PanelContainer used by prime_scores, with real HTTP results as display data.
	# No game/Steam stand-ins: this is the presentation boundary, not a claim of live friend discovery.
	root.size = Vector2i(1280, 720)
	check(root.content_scale_size == Vector2i(512, 720) and root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT, "layout uses the game's viewport and keep-height canvas stretch")
	var canvas:= CanvasLayer.new()
	canvas.layer = 100
	root.add_child(canvas)
	var panel_script: Script = load(script_path.get_base_dir().path_join("prime_board.gd"))
	var panel: PanelContainer = panel_script.new()
	canvas.add_child(panel)
	var board_label: Label = panel.get_node("Scores") as Label
	var real_top: Dictionary = await online.exchange("/v1/leaderboard?mod=prime_sobo&limit=5", HTTPClient.METHOD_GET, "", Time.get_ticks_msec() + 5000)
	var display_friends: Dictionary = {}
	for row: Dictionary in real_top.entries:
		check(not row.has("player_id") and row.get("steam_id") is String, "public rows carry the Steam ID, not player_id")
		if row.rank != expected_rank:
			display_friends[str(row.rank)] = {"name": row.name, "best": row.best}
	board_label.text = panel.board_text(100, 1, 100, display_friends, true, online.world_text)
	panel.visible = true
	await process_frame
	await process_frame
	print("BOARD_MEASURE lines=%d drawn_lines=%d height=%.1f top=%.1f" % [board_label.text.split("\n").size(), board_label.get_line_count(), panel.size.y, panel.position.y])
	var bounds: Rect2 = panel.get_global_rect()
	var viewport: Rect2 = root.get_visible_rect()
	print("BOARD_BOUNDS left=%.1f right=%.1f viewport=%.1f..%.1f" % [bounds.position.x, bounds.end.x, viewport.position.x, viewport.end.x])
	check(bounds.position.x >= viewport.position.x and bounds.end.x <= viewport.end.x, "real CanvasLayer panel is wholly inside the viewport horizontally")
	check(absf(bounds.get_center().x - viewport.get_center().x) <= 1.0, "real CanvasLayer panel is centered in the viewport")
	check(panel.inside_viewport(), "game selftest's full-rectangle check uses the actual panel")
	check(board_label.text.split("\n").size() <= 6 and board_label.get_line_count() <= 6, "board has at most six actual lines")
	check(panel.size.y <= 160.0 and panel.get_global_rect().end.y <= 176.0, "board stays above the game's score area")
	check(panel.position.y == 16.0 and board_label.get_theme_font_size("font_size") == 15, "board uses prescribed top and font")
	check(board_label.text.get_slice("\n", 0) == "素数モード 今回 100 点 / 自己ベスト 100 点 (手元 1 位)", "score and personal best share the first line")
	if display_friends.is_empty():
		check(not board_label.text.contains("フレンド"), "no empty friend section")
	else:
		check(board_label.text.get_slice("\n", 1) == "フレンド: 1. leader4 208 / 2. leader3 206", "only the two highest friends share one line")
	check(board_label.text.contains("世界 %d 位 / " % expected_rank) and online.world_text.split("\n").size() <= 4, "world rank and at most top three rows")
	var local_only: String = panel.board_text(100, -1, 100, {}, false, online.world_text)
	check(local_only == "素数モード 今回 100 点 / 自己ベスト 100 点 (手元 圏外)", "disabled world and absent friends leave only the local line")
	TranslationServer.set_locale("en")
	var english_local: String = panel.board_text(100, -1, 100, {}, false, "")
	check(english_local == "prime mode: this run 100 / best 100 (local unranked)", "the board in English: %s" % english_local)
	var english_board: String = panel.board_text(100, 1, 100, {"1": {"name": "a", "best": 4}}, true, "")
	check(english_board == "prime mode: this run 100 / best 100 (local #1)\nfriends: 1. a 4\nworld: loading…", "friends and world in English: %s" % english_board)
	TranslationServer.set_locale("ja")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shot_path: String = args[2].path_join("board-1280x720.png")
		check(root.get_texture().get_image().save_png(shot_path) == OK, "actual panel frame saved")
		print("BOARD_IMAGE ", shot_path)
	root.size = Vector2i(640, 720)
	await process_frame
	await process_frame
	bounds = panel.get_global_rect()
	viewport = root.get_visible_rect()
	check(viewport.size == Vector2(640, 720) and viewport.encloses(bounds) and panel.inside_viewport() and absf(bounds.get_center().x - viewport.get_center().x) <= 1.0, "resized viewport keeps the real panel fully visible and centered")
	# A new instance must reuse the same installation identity rather than claim another player.
	var next: Node = script.new()
	next.config_path = config_path
	next.identity_path = online.identity_path
	next.steam_id = own_steam_id
	next.player_name = "Godot player"
	next.send_scores = true
	root.add_child(next)
	var repeat: Dictionary = await next.submit_score(102, 20, 0.10)
	check(repeat.get("ok", true) == false and next.world_text == "世界ランキングに届かなかった", "real rate rejection remains a nonblocking board message")
	check(FileAccess.get_file_as_string(next.identity_path) == identity_before, "identity reused by second instance")
	# A closed loopback port is a real connection failure, not a replacement API.
	cfg.set_value("online", "server_url", args[3])
	cfg.save(config_path)
	next.reload_config()
	var began:= Time.get_ticks_msec()
	var failed: Dictionary = await next.submit_score(104, 20, 0.10)
	check(failed.get("ok", true) == false and Time.get_ticks_msec() - began < 5500, "connection failure ends within five-second budget")
	check(next.world_text == "世界ランキングに届かなかった", "network failure is safe to show")
	# Real TCP proxy delays the real Worker's response; it never creates an API reply.
	cfg.set_value("online", "server_url", args[4])
	cfg.save(config_path)
	next.reload_config()
	began = Time.get_ticks_msec()
	var timed_out: Dictionary = await next.submit_score(106, 20, 0.10)
	var elapsed: int = Time.get_ticks_msec() - began
	check(not timed_out.get("ok", true) and elapsed >= 4500 and elapsed < 5500, "real delayed HTTP response times out at five seconds")
	check(not next.busy, "timeout releases pending request")
	cfg.set_value("online", "server_url", "http://example.com")
	cfg.save(config_path)
	next.reload_config()
	check(not (await next.submit_score(108, 20, 0.10)).get("ok", true), "non-loopback plaintext server rejected")
	quit(1 if failures else 0)
