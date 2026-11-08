extends Node
## Optional MOD-only world ranking. No Steam APIs or game globals in this transport:
## prime_sobo.gd reads the player's Steam ID and Steam name from Steam and sets them here.
## One five-second budget covers POST, top-five GET, and fresh own-row lookup.
## The prime scores screen reads one page of ten (offset), the fresh own rank (around span=0)
## and the friends' rows, each within its own five seconds.
signal updated(text: String)

const MOD_VERSION:= "1.3.11-1.0.1"
const TIMEOUT_MS:= 5000
const BOARD_ROWS:= 5
const PAGE_ROWS:= 10
const MAX_OFFSET:= 10000
## The server takes at most this many Steam IDs per friends read.
const FRIENDS_PER_READ:= 100
var config_path:= ""
var identity_path:= "user://prime_sobo_online.json"
var enabled:= false
## The "send scores" switch (spec §8), set by prime_sobo.gd. Off: a run's score is not sent.
var send_scores:= false
var server_url:= ""
## The player's SteamID64 in decimal, "" while Steam is not connected. Set by prime_sobo.gd.
var steam_id:= ""
## The player's Steam name. Set by prime_sobo.gd.
var player_name:= "anon"
var world_text:= ""
var last_result: Dictionary = {}
var busy:= false
var _generation:= 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config_path.is_empty():
		config_path = (get_script() as Script).resource_path.get_base_dir().path_join("online.cfg")
	reload_config()

func reload_config() -> void:
	var cfg:= ConfigFile.new()
	enabled = false
	server_url = ""
	if cfg.load(config_path) != OK:
		return
	enabled = cfg.get_value("online", "enabled", false) == true
	server_url = str(cfg.get_value("online", "server_url", "")).strip_edges().trim_suffix("/")

func start_run() -> void:
	_generation += 1
	world_text = ""
	last_result = {}

func valid_server_url() -> bool:
	var pattern:= RegEx.new()
	# Keys may leave the machine only over TLS. Plain HTTP is limited to loopback QA.
	pattern.compile("^(https://[A-Za-z0-9.-]+|http://(127\\.0\\.0\\.1|localhost|\\[::1\\]))(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$")
	return pattern.search(server_url) != null

func is_local_server() -> bool:
	return valid_server_url() and (server_url.begins_with("http://127.0.0.1:") or server_url.begins_with("http://localhost:") or server_url.begins_with("http://[::1]:"))

## SteamID64 of an individual account in decimal, the server's player_id (ranking spec §3).
func valid_steam_id(value: Variant) -> bool:
	if not value is String:
		return false
	var pattern:= RegEx.new()
	pattern.compile("^7656119[0-9]{10}$")
	return pattern.search(value) != null

## The key file holds the random key only. A 0.1.0 file also holds a UUID; its key is kept.
func valid_identity(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var key_pattern:= RegEx.new()
	key_pattern.compile("^[0-9a-f]{64}$")
	return value.get("player_key") is String and key_pattern.search(value.player_key) != null

## The stored key, or {} when there is none or it is broken. Never creates one.
func saved_identity() -> Dictionary:
	if not FileAccess.file_exists(identity_path):
		return {}
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(identity_path))
	return {"player_key": saved.player_key} if valid_identity(saved) else {}

func identity() -> Dictionary:
	if FileAccess.file_exists(identity_path):
		# Never silently replace a broken key: the server would refuse this Steam ID (KEY_MISMATCH).
		return saved_identity()
	var key: PackedByteArray = Crypto.new().generate_random_bytes(32)
	if key.size() != 32:
		return {}
	var value:= {"player_key": key.hex_encode()}
	var file:= FileAccess.open(identity_path, FileAccess.WRITE)
	if file == null:
		return {}
	file.store_string(JSON.stringify(value))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return value if write_error == OK else {}

## {"status": code, "body": Dictionary} for any HTTP answer within the deadline, {} otherwise.
func request_json(path: String, method: HTTPClient.Method, body: String, deadline: int) -> Dictionary:
	var remaining: int = deadline - Time.get_ticks_msec()
	if remaining <= 0:
		return {}
	var http:= HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	http.timeout = float(remaining) / 1000.0
	http.body_size_limit = 65536
	http.max_redirects = 0
	add_child(http)
	var error: Error = http.request(server_url + path, PackedStringArray(["Content-Type: application/json"]), method, body)
	if error != OK:
		http.queue_free()
		return {}
	var response: Array = await http.request_completed
	http.queue_free()
	if Time.get_ticks_msec() > deadline or response[0] != HTTPRequest.RESULT_SUCCESS:
		return {}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	return {"status": int(response[1]), "body": parsed if parsed is Dictionary else {}}

## The body of a 200 {"ok": true} answer, {} for anything else.
func exchange(path: String, method: HTTPClient.Method, body: String, deadline: int) -> Dictionary:
	var answer: Dictionary = await request_json(path, method, body, deadline)
	if answer.is_empty() or answer.status != 200 or answer.body.get("ok") != true:
		return {}
	return answer.body

func positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 1.0 and float(value) == floor(float(value))

func non_negative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) == floor(float(value))

func valid_entries(value: Variant, around:= false, max_rows:= BOARD_ROWS) -> bool:
	if not value is Array or value.size() > max_rows:
		return false
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("name") is String or entry.has("player_id") or not valid_steam_id(entry.get("steam_id")):
			return false
		if around and not entry.get("you") is bool:
			return false
		if not positive_integer(entry.get("rank")) or not (entry.get("best") is int or entry.get("best") is float):
			return false
		var best: float = float(entry.best)
		if not is_finite(best) or best < 0.0 or best != floor(best) or best > 10000000.0 or int(best) % 2 != 0:
			return false
	return true

func fail(generation: int) -> Dictionary:
	busy = false
	if generation == _generation:
		last_result = {"ok": false}
		world_text = word("world failed")
		updated.emit(world_text)
	return {"ok": false}


## The server accepted the score (it cannot be taken back) but a later read of the ranking failed.
## Not a failed send: the rank and player count of the accepted answer are shown, with a line saying
## the list could not be read. ok stays false (the ranking was not fully read); sent says what happened.
func sent_but_unread(generation: int, posted: Dictionary) -> Dictionary:
	busy = false
	var result:= {"ok": false, "sent": true, "rank": int(posted.rank), "best": posted.best, "own_found": false}
	if generation == _generation:
		last_result = result
		world_text = word("world rank") % [int(posted.rank), int(posted.players)] + "\n" + word("sent, ranking not read")
		updated.emit(world_text)
	return result


## The mod's words in the game's language (prime_text.gd next to this script).
func word(key: String) -> String:
	return load((get_script() as Script).resource_path.get_base_dir().path_join("prime_text.gd")).get_text(key)


func submit_score(score: int, duration_s: int, prime_chance: float) -> Dictionary:
	if not enabled or busy:
		return {}
	busy = true
	var generation: int = _generation
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	if not valid_steam_id(steam_id):
		# Not connected to Steam: nothing is sent and no key file is made.
		busy = false
		last_result = {"ok": false, "no_steam": true}
		world_text = word("no steam")
		updated.emit(world_text)
		return last_result
	if not send_scores:
		# "send scores" is off: nothing is sent and no key file is made.
		busy = false
		last_result = {"ok": false, "not_sent": true}
		world_text = word("not sent") % word("send scores")
		updated.emit(world_text)
		return last_result
	if not valid_server_url():
		return fail(generation)
	var who:= identity()
	if who.is_empty():
		return fail(generation)
	world_text = word("world loading")
	updated.emit(world_text)
	var payload:= {"mod": "prime_sobo", "mod_version": MOD_VERSION, "player_id": steam_id,
		"player_key": who.player_key, "name": player_name, "score": score,
		"duration_s": duration_s, "prime_chance": prime_chance}
	var posted: Dictionary = await exchange("/v1/scores", HTTPClient.METHOD_POST, JSON.stringify(payload), deadline)
	if generation != _generation:
		busy = false
		return {}
	if not positive_integer(posted.get("rank")) or not positive_integer(posted.get("players")) or not (posted.get("best") is int or posted.get("best") is float):
		return fail(generation)
	var best: float = float(posted.best)
	if not is_finite(best) or best < 0.0 or best != floor(best) or best > 10000000.0 or int(best) % 2 != 0:
		return fail(generation)
	var board: Dictionary = await exchange("/v1/leaderboard?mod=prime_sobo&limit=5", HTTPClient.METHOD_GET, "", deadline)
	if generation != _generation:
		busy = false
		return {}
	if not valid_entries(board.get("entries")):
		return sent_but_unread(generation, posted)
	# Always retrieve the fresh own row; its you flag marks the player.
	var around: Dictionary = await exchange("/v1/leaderboard/around?mod=prime_sobo&player_id=%s&span=2" % steam_id, HTTPClient.METHOD_GET, "", deadline)
	if generation != _generation:
		busy = false
		return {}
	if not valid_entries(around.get("entries"), true) or not positive_integer(around.get("rank")) or not positive_integer(around.get("players")):
		return sent_but_unread(generation, posted)
	var own: Dictionary = {}
	var own_count:= 0
	for entry: Dictionary in around.entries:
		if entry.you:
			own = entry
			own_count += 1
	if own_count != 1 or own.rank != around.rank:
		return sent_but_unread(generation, posted)
	var entries: Array = board.entries
	# When the player is displayed in the top three, span=2 includes that entire
	# top section. Use its fresh you flags rather than guessing from public ranks.
	if own.rank <= 3:
		entries = around.entries.filter(func(entry: Dictionary) -> bool: return entry.rank <= 3)
	var lines:= PackedStringArray([word("world rank") % [around.rank, around.players]])
	for entry: Dictionary in entries.slice(0, 3):
		lines.append("%d. %s  %d%s" % [entry.rank, clean_name(entry.name), entry.best, ("  ←" + word("you")) if entry.get("you", false) else ""])
	world_text = "\n".join(lines)
	last_result = {"ok": true, "rank": around.rank, "best": posted.best, "own_found": true}
	busy = false
	updated.emit(world_text)
	return last_result

## Labels are plain text. Strip line separators from remote names before drawing rows.
func clean_name(value: Variant) -> String:
	return str(value).replace("\n", "").replace("\r", "").replace("\t", " ").replace("\u2028", "").replace("\u2029", "").substr(0, 24)

## One scores-screen page: GET /v1/leaderboard?limit=10&offset=<offset>, five seconds.
## {"ok": true, "entries": [...], "players": n}, or {} on any failure (disabled, refused, late, malformed).
func fetch_page(offset: int) -> Dictionary:
	if not enabled or not valid_server_url() or offset < 0 or offset > MAX_OFFSET:
		return {}
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	var page: Dictionary = await exchange("/v1/leaderboard?mod=prime_sobo&limit=%d&offset=%d" % [PAGE_ROWS, offset], HTTPClient.METHOD_GET, "", deadline)
	if not valid_entries(page.get("entries"), false, PAGE_ROWS) or not non_negative_integer(page.get("players")):
		return {}
	# Rows keep their global rank, so a page starts at offset + 1 and runs without gaps.
	for i: int in page.entries.size():
		if int(page.entries[i].rank) != offset + 1 + i:
			return {}
	return {"ok": true, "entries": page.entries, "players": int(page.players)}

## The fresh own row: GET /v1/leaderboard/around?span=0 for the Steam ID, five seconds.
## {"ok": true, "rank", "best", "name", "players"}; {"ok": false, "none": true} when the server
## does not know this Steam ID (never sent); {} on failure or without a Steam ID.
func fetch_own_rank() -> Dictionary:
	if not enabled or not valid_server_url() or not valid_steam_id(steam_id):
		return {}
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	var answer: Dictionary = await request_json("/v1/leaderboard/around?mod=prime_sobo&player_id=%s&span=0" % steam_id, HTTPClient.METHOD_GET, "", deadline)
	if answer.is_empty():
		return {}
	if answer.status == 404 and answer.body.get("error") == "PLAYER_NOT_FOUND":
		return {"ok": false, "none": true}
	var around: Dictionary = answer.body
	if answer.status != 200 or around.get("ok") != true:
		return {}
	if not valid_entries(around.get("entries"), true, 1) or around.entries.size() != 1 or not positive_integer(around.get("rank")) or not positive_integer(around.get("players")):
		return {}
	var own: Dictionary = around.entries[0]
	if own.you != true or int(own.rank) != int(around.rank):
		return {}
	return {"ok": true, "rank": int(own.rank), "best": int(own.best), "name": clean_name(own.name), "players": int(around.players)}

## Friends only: GET /v1/leaderboard/friends for the given Steam IDs (the player's and their Steam
## friends'), FRIENDS_PER_READ at a time within one five-second budget. Only players on the board come
## back, best first, each with the world rank. {"ok": true, "entries": [...]}, or {} on any failure.
func fetch_friends(ids: PackedStringArray) -> Dictionary:
	if not enabled or not valid_server_url() or ids.is_empty():
		return {}
	for id: String in ids:
		if not valid_steam_id(id):
			return {}
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	var rows: Array = []
	for start in range(0, ids.size(), FRIENDS_PER_READ):
		var part: PackedStringArray = ids.slice(start, start + FRIENDS_PER_READ)
		var answer: Dictionary = await exchange("/v1/leaderboard/friends?mod=prime_sobo&ids=%s" % ",".join(part), HTTPClient.METHOD_GET, "", deadline)
		if not valid_entries(answer.get("entries"), false, part.size()):
			return {}
		rows.append_array(answer.entries)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) < int(b.rank))
	return {"ok": true, "entries": rows}

## The scores screen's reads. Like the game's Steam downloads, only the latest read of a kind counts:
## an answer that comes back after a newer read of its kind began is {"stale": true}, success or
## failure, so it never replaces newer rows or shows a failure. Otherwise the plain answer of
## fetch_page / fetch_own_rank / fetch_friends.
var _screen_reads: Dictionary = {}

func _begin_screen_read(kind: String) -> int:
	_screen_reads[kind] = int(_screen_reads.get(kind, 0)) + 1
	return _screen_reads[kind]

func _screen_answer(kind: String, ticket: int, answer: Dictionary) -> Dictionary:
	return answer if _screen_reads.get(kind) == ticket else {"stale": true}

func screen_page(offset: int) -> Dictionary:
	var ticket: int = _begin_screen_read("page")
	var answer: Dictionary = await fetch_page(offset)
	return _screen_answer("page", ticket, answer)

func screen_own_rank() -> Dictionary:
	var ticket: int = _begin_screen_read("own_rank")
	var answer: Dictionary = await fetch_own_rank()
	return _screen_answer("own_rank", ticket, answer)

func screen_friends(ids: PackedStringArray) -> Dictionary:
	var ticket: int = _begin_screen_read("friends")
	var answer: Dictionary = await fetch_friends(ids)
	return _screen_answer("friends", ticket, answer)

## Server rows in the shape of the game's Steam leaderboard rows, {steam_id, score, global_rank},
## so the scores screen draws them with the game's LeaderboardEntry.setup_steam. The server name
## stays for players whose Steam name is not known yet.
func steam_rows(entries: Array) -> Array:
	var rows: Array = []
	for entry: Dictionary in entries:
		rows.append({"steam_id": int(entry.steam_id), "score": int(entry.best), "global_rank": int(entry.rank), "name": clean_name(entry.name)})
	return rows

## Index of the own row on a page, or -1. The page and the own rank are separate reads, so the row is
## only marked when its rank and best both equal the fresh around row.
func own_index_in_page(entries: Array, own: Dictionary) -> int:
	if own.get("ok") != true:
		return -1
	for i: int in entries.size():
		if int(entries[i].rank) == int(own.rank) and int(entries[i].best) == int(own.best):
			return i
	return -1
