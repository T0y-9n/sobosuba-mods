extends SceneTree
## Standalone Godot only; no sobosuba assets, autoloads, or game launch.
## Scores-screen transport: one page of ten (offset) and the fresh own rank (around span=0).
var failures:= 0
func check(ok: bool, what: String) -> void:
	print("PAGES_CHECK ", "OK " if ok else "FAIL ", what)
	if not ok:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func ranks_and_bests(page: Dictionary) -> Array:
	var out: Array = []
	for row: Dictionary in page.get("entries", []):
		out.append([int(row.rank), int(row.best)])
	return out

## Points the transport at another real server through its real config file.
func use_server(cfg: ConfigFile, config_path: String, online: Node, url: String) -> void:
	cfg.set_value("online", "server_url", url)
	cfg.save(config_path)
	online.reload_config()

## Waits until a read begun without await has filled `into`, or `limit_ms` passes.
func wait_filled(into: Dictionary, limit_ms: int) -> void:
	var began:= Time.get_ticks_msec()
	while into.is_empty() and Time.get_ticks_msec() - began < limit_ms:
		await process_frame

func run() -> void:
	var args:= OS.get_cmdline_user_args()
	var script_path: String = args[0]
	var script: Script = load(script_path)
	if script == null or not script.can_instantiate():
		check(false, "online transport compiles")
		quit(1)
		return
	var cfg:= ConfigFile.new()
	cfg.set_value("online", "enabled", false)
	cfg.set_value("online", "server_url", args[1])
	cfg.set_value("online", "name", "Godot pages")
	var config_path: String = args[2].path_join("online.cfg")
	check(cfg.save(config_path) == OK, "disabled config written to real file")
	var online: Node = script.new()
	online.config_path = config_path
	online.identity_path = args[2].path_join("pages_identity.json")
	root.add_child(online)
	check(online.MOD_VERSION == "1.2.3-1.0.0", "MOD_VERSION is the first public version")

	# Disabled: no reads, no identity file.
	check((await online.fetch_page(0)).is_empty(), "disabled config reads no page")
	check((await online.fetch_own_rank()).is_empty(), "disabled config reads no own rank")
	check(not FileAccess.file_exists(online.identity_path), "disabled reads create no identity")

	cfg.set_value("online", "enabled", true)
	cfg.save(config_path)
	online.reload_config()
	var own_steam_id: String = args[6]
	# Not connected to Steam: no own rank can be asked (the screen shows the no-Steam text instead).
	check((await online.fetch_own_rank()).is_empty(), "without a Steam ID the own rank is not asked")
	# A Steam ID the server has never seen: the real 404 PLAYER_NOT_FOUND is 'no rank'.
	online.steam_id = own_steam_id
	var unknown: Dictionary = await online.fetch_own_rank()
	check(unknown.get("ok", true) == false and unknown.get("none", false) == true, "server 404 for a Steam ID it does not know is 'no rank'")
	check(not FileAccess.file_exists(online.identity_path), "own-rank reads create no key file")

	var first: Dictionary = await online.fetch_page(0)
	var expected_first: Array = []
	for i in 10:
		expected_first.append([i + 1, 1040 - i * 4])
	check(first.get("ok", false) and ranks_and_bests(first) == expected_first and int(first.get("players", 0)) == 11, "page 1 has ranks 1-10 of 11 players: %s" % [ranks_and_bests(first)])
	for row: Dictionary in first.get("entries", []):
		check(not row.has("player_id") and not row.has("you") and online.valid_steam_id(row.get("steam_id")), "page rows carry the Steam ID only")
		break

	# Page 2 read before Godot's submission: the older real answer (rank 11 is the 1000 player).
	var before_post: Dictionary = await online.fetch_page(10)
	check(before_post.get("ok", false) and ranks_and_bests(before_post) == [[11, 1000]] and int(before_post.get("players", 0)) == 11, "page 2 before the POST: %s" % [ranks_and_bests(before_post)])

	# Godot's own real submission: 1002 lands at rank 11, above the 1000 player.
	online.send_scores = true
	var posted: Dictionary = await online.submit_score(1002, 100, 0.10)
	check(posted.get("ok", false) and posted.get("rank", 0) == 11, "real POST places Godot at rank 11: %s" % [posted])
	var own: Dictionary = await online.fetch_own_rank()
	check(own.get("ok", false) and own.get("rank", 0) == 11 and own.get("best", 0) == 1002 and own.get("players", 0) == 12, "fresh own rank from around span=0: %s" % [own])
	# Friends only: the own Steam ID and two of the eleven players (the 1000 and the 1040 one),
	# plus one the server does not know. Best first, each with the world rank.
	var friend_low: String = args[7]
	var friend_top: String = args[8]
	var friends: Dictionary = await online.fetch_friends(PackedStringArray([friend_low, "76561190000000002", own_steam_id, friend_top]))
	var friend_rows: Array = []
	for row: Dictionary in friends.get("entries", []):
		friend_rows.append([int(row.rank), str(row.steam_id), int(row.best)])
	check(friends.get("ok", false) and friend_rows == [[1, friend_top, 1040], [11, own_steam_id, 1002], [12, friend_low, 1000]], "friends: listed players only, best first, world ranks: %s" % [friend_rows])
	# The scores screen draws server rows with the game's LeaderboardEntry.setup_steam, so they take
	# the shape of the game's Steam leaderboard rows: {steam_id (int), score, global_rank} (+ the server name).
	var shaped: Array = online.steam_rows(friends.get("entries", []))
	var shaped_ok: bool = shaped.size() == 3
	for row: Dictionary in shaped:
		shaped_ok = shaped_ok and row.keys().size() == 4 and typeof(row.steam_id) == TYPE_INT and typeof(row.score) == TYPE_INT and typeof(row.global_rank) == TYPE_INT and row.name is String
	check(shaped_ok and shaped[1] == {"steam_id": int(own_steam_id), "score": 1002, "global_rank": 11, "name": "anon"} and shaped[0].steam_id == int(friend_top) and shaped[2].global_rank == 12, "server rows take the game's Steam row shape: %s" % [shaped])

	# Read again right after the POST: never the earlier answer (no cache), players counts Godot.
	var second: Dictionary = await online.fetch_page(10)
	check(second.get("ok", false) and ranks_and_bests(second) == [[11, 1002], [12, 1000]] and int(second.get("players", 0)) == 12, "page 2 right after the POST is new: %s players=%s" % [ranks_and_bests(second), second.get("players")])
	var second_rows: Array = online.steam_rows(second.get("entries", []))
	check(second_rows.size() == 2 and second_rows[0].global_rank == 11 and second_rows[0].steam_id == int(own_steam_id) and second_rows[1].score == 1000, "page 2 rows in the game's shape: the own Steam ID first: %s" % [second_rows])
	check(online.own_index_in_page(second.get("entries", []), own) == 0, "new page: own row is the first row")
	# The page and the own rank are separate reads: an older page answer is never marked.
	check(online.own_index_in_page(before_post.get("entries", []), own) == -1, "older page answer: own row is not marked")
	check(online.own_index_in_page(first.get("entries", []), own) == -1, "own row is not on page 1")
	check(online.own_index_in_page(second.get("entries", []), {"ok": false, "none": true}) == -1, "no rank marks nothing")

	# The scores screen reads through screen_page / screen_own_rank / screen_friends: like the game's
	# Steam downloads only the latest read of a kind counts. An older read that a real proxy holds
	# comes back {"stale": true}, success or failure, so it never replaces the newer page or puts a
	# failure on the screen. Each older read begins on the slow proxy (the URL is taken before the
	# first wait), then the newer one goes straight to the Worker.
	var has_screen_reads: bool = online.has_method("screen_page") and online.has_method("screen_own_rank") and online.has_method("screen_friends")
	check(has_screen_reads, "the transport has the scores screen's latest-only reads")
	if has_screen_reads:
		var slow: Dictionary = {}
		use_server(cfg, config_path, online, args[9])
		(func() -> void: slow.merge(await online.screen_page(0), true)).call()
		use_server(cfg, config_path, online, args[1])
		var newer_page: Dictionary = await online.screen_page(10)
		check(newer_page.get("ok", false) and ranks_and_bests(newer_page) == [[11, 1002], [12, 1000]] and not newer_page.has("stale"), "screen: the newer page answers: %s" % [ranks_and_bests(newer_page)])
		await wait_filled(slow, 6000)
		check(slow == {"stale": true}, "screen: an older page read (held two seconds) that succeeds later comes back stale: %s" % [slow.keys()])

		slow = {}
		use_server(cfg, config_path, online, args[4])
		(func() -> void: slow.merge(await online.screen_own_rank(), true)).call()
		use_server(cfg, config_path, online, args[1])
		var newer_own: Dictionary = await online.screen_own_rank()
		check(newer_own.get("ok", false) and newer_own.get("rank", 0) == 11 and not newer_own.has("stale"), "screen: the newer own rank answers: %s" % [newer_own])
		await wait_filled(slow, 7000)
		check(slow == {"stale": true}, "screen: an older own-rank read that fails later (held six seconds) comes back stale, not a failure: %s" % [slow])

		slow = {}
		use_server(cfg, config_path, online, args[9])
		(func() -> void: slow.merge(await online.screen_friends(PackedStringArray([own_steam_id])), true)).call()
		use_server(cfg, config_path, online, args[1])
		var newer_friends: Dictionary = await online.screen_friends(PackedStringArray([own_steam_id, friend_top]))
		check(newer_friends.get("ok", false) and newer_friends.entries.size() == 2 and not newer_friends.has("stale"), "screen: the newer friends read answers: %s" % [newer_friends.get("entries", []).size()])
		await wait_filled(slow, 6000)
		check(slow == {"stale": true}, "screen: an older friends read that succeeds later comes back stale: %s" % [slow.keys()])

		# Alone, a screen read is the plain answer: a failure is {} (the screen shows it), never stale.
		use_server(cfg, config_path, online, args[3])
		check((await online.screen_page(0)) == {}, "screen: a failed latest page read is a failure, not stale")
		use_server(cfg, config_path, online, args[1])
		var latest: Dictionary = await online.screen_page(0)
		check(latest.get("ok", false) and ranks_and_bests(latest).size() == 10, "screen: a latest page read alone is the page")

	for bad: int in [-1, 10001]:
		check((await online.fetch_page(bad)).is_empty(), "offset %d is refused before any request" % bad)

	# A closed loopback port is a real connection failure.
	cfg.set_value("online", "server_url", args[3])
	cfg.save(config_path)
	online.reload_config()
	var began:= Time.get_ticks_msec()
	check((await online.fetch_page(0)).is_empty() and Time.get_ticks_msec() - began < 5500, "closed port: page read fails within five seconds")
	check((await online.fetch_own_rank()).is_empty(), "closed port: own rank is a failure, not 'no rank'")
	check((await online.fetch_friends(PackedStringArray([own_steam_id]))).is_empty(), "closed port: friends read is a failure")
	# The real Worker's answer held for six seconds by the proxy times out at five.
	cfg.set_value("online", "server_url", args[4])
	cfg.save(config_path)
	online.reload_config()
	began = Time.get_ticks_msec()
	var late_page: Dictionary = await online.fetch_page(0)
	var elapsed: int = Time.get_ticks_msec() - began
	check(late_page.is_empty() and elapsed >= 4500 and elapsed < 5500, "delayed page read times out at five seconds (%d ms)" % elapsed)
	began = Time.get_ticks_msec()
	var late_own: Dictionary = await online.fetch_own_rank()
	elapsed = Time.get_ticks_msec() - began
	check(late_own.is_empty() and elapsed >= 4500 and elapsed < 5500, "delayed own-rank read times out at five seconds (%d ms)" % elapsed)
	cfg.set_value("online", "server_url", "http://example.com")
	cfg.save(config_path)
	online.reload_config()
	check((await online.fetch_page(0)).is_empty(), "non-loopback plaintext server refused for page reads")
	print("PAGES_DONE failures=%d" % failures)
	quit(1 if failures else 0)
