extends ScoresScreen
## Prime scores screen. The game's own scores_screen.tscn is instanced a second time by
## prime_sobo.gd and given this script. The native mode row identifies the prime board;
## the game's screen node and script files are untouched.
## The game's ScoresScreen flow (source, friends only, pages, my score, hover, page count, buttons)
## runs as it is. This script only replaces where the game fetches records through ScoreManager:
## - Source.STEAM is the prime world ranking (prime_online.gd): a page of ten, the own rank (around)
##   and friends only (the player's and their Steam friends' IDs). The answers are kept here the way
##   ScoreManager keeps the Steam leaderboard, in the same row shape, and drawn with setup_steam.
## - Source.LOCAL is prime_sobo_scores.json (top 10); clear local scores clears only that board.
## Native initialization supplies the widgets; prime-server reads supply the records.

const TITLE:= "scores"
## Steam's name for a user whose name has not arrived yet.
const STEAM_UNKNOWN_NAME:= "[unknown]"

## Set by prime_sobo.gd before the screen enters the tree.
var scores: Node = null
var online: Node = null

## What ScoreManager holds for the game's screen (steam_leaderboard_high_scores, the entry count,
## steam_friends_leaderboard_high_scores, steam_friends_downloaded), from the prime server.
var world_rows: Array = []
var world_count:= 0
var friends_rows: Array = []
var friends_downloaded:= false
## Server requests in flight (the self test waits until this is 0).
var pending:= 0
## A jump within downloaded friends must keep using that same snapshot.
var using_cached_friend_rows:= false


func _ready() -> void:
	super()
	if OS.has_feature("steam"):
		ScoreManager.steam_leaderboard_updated.disconnect(_on_steam_leaderboard_updated)
		ScoreManager.steam_leaderboard_failed.disconnect(_on_steam_leaderboard_failed)
		ScoreManager.steam_user_rank_updated.disconnect(_on_steam_user_rank_updated)
	# The game's board switch cycles the author's Steam boards (ScoreManager.select_board); the prime
	# ranking is a single board. Keep the native row, with no cycling action.
	board_btn.disabled = true
	board_btn.set_value("prime")
	side_title_text = TITLE
	if OS.has_feature("steam"):
		if SteamManager.steam_ready:
			_connect_steam()
		else:
			SteamManager.steam_initialized.connect(_connect_steam, CONNECT_ONE_SHOT)


func _connect_steam() -> void:
	SteamManager.steam.connect("persona_state_change", _on_persona_state_change)


## The mod's words in the game's language (prime_text.gd next to this script).
func word(key: String) -> String:
	return load((get_script() as Script).resource_path.get_base_dir().path_join("prime_text.gd")).get_text(key)


## The game's "Steam is there" for the world: enabled in online.cfg and connected to Steam.
func world_usable() -> bool:
	return online != null and online.enabled and SteamManager.steam_ready


func unusable_text() -> String:
	return word("world disabled") if online == null or not online.enabled else word("no steam")


func source_text() -> String:
	if source == Source.LOCAL:
		return tr("local")
	return word("world")


func show_message(text: String) -> void:
	steam_failed_label.text = text
	steam_failed_label.show()


# ------------------------------------------------- the game's flow, with the prime records

func open():
	page = 0
	steam_user_rank = STEAM_USER_RANK_UNKNOWN
	_hover_self_on_next_generate = false
	source = Source.STEAM if world_usable() else Source.LOCAL
	# Same as ScoresScreen.open: the list panel is as high as one page of entries.
	(leaderboard_container.get_parent() as Control).custom_minimum_size.y = get_page_height(entries, PAGE_SIZE, leaderboard_container)
	refresh_translated_text()
	refresh_leaderboard()
	# MenuScreen.open() without ScoresScreen.open(), which picks the author's Steam board.
	SoboButton.currently_hovered = get_first_button_to_hover()
	Ui._0.mouse_hovering_disabled = false


func refresh_buttons():
	super()
	board_btn.set_value("prime")
	board_btn.disabled = true
	source_btn.set_value(source_text())
	if source == Source.STEAM:
		friends_only_btn.disabled = not world_usable()
		my_score_btn.disabled = not world_usable()


func refresh_leaderboard(request_remote: bool = true):
	if source != Source.STEAM:
		super(request_remote)
		return
	no_steam_button.hide()
	steam_failed_label.hide()
	if not world_usable():
		clear_entries()
		show_message(unusable_text())
		refresh_nav_buttons()
		return
	if friends_only:
		refresh_friends_leaderboard(request_remote and not using_cached_friend_rows)
		return
	apply_page_ranks(world_count)
	if request_remote:
		request_world_page(page)


func refresh_friends_leaderboard(request_remote: bool) -> void:
	var known_count: int = friends_rows.size() if friends_downloaded else 0
	apply_page_ranks(known_count, not friends_downloaded)
	if friends_downloaded:
		generate_friends_leaderboard()
	if request_remote:
		request_world_friends()


func _on_my_score_release_press() -> void:
	if friends_only or steam_user_rank > 0:
		super._on_my_score_release_press()
	else:
		request_world_user_rank()

## The native mode row is read-only; there is only the prime board.
func _on_board_release_press() -> void:
	pass


## The game formats a value by the selected board (a time board shows a clock); prime scores are plain.
func format_value(value: int) -> String:
	return str(value)


## Only the prime local board is cleared, never the game's own local scores.
func _on_clear_local_scores_confirm_release_press() -> void:
	scores.clear_local_scores()
	page = 0
	refresh_leaderboard()
	refresh_buttons()


func go_to_own_friends_entry() -> void:
	var own_index: int = get_own_friends_index()
	if own_index >= 0:
		using_cached_friend_rows = true
		super.go_to_steam_rank(own_index + 1)
		using_cached_friend_rows = false
	elif not friends_downloaded:
		_hover_self_on_next_generate = true
		request_world_friends()

## A Steam row drawn by the game's setup_steam; the server name stands in until Steam knows the name.
func show_steam_row(entry: LeaderboardEntry, row: Dictionary, rank: int) -> void:
	entry.setup_steam(row, rank, format_value(int(row.score)))
	if entry.name_label.text == "" or entry.name_label.text == STEAM_UNKNOWN_NAME:
		entry.name_label.text = row.name
		SteamManager.steam.requestUserInformation(row.steam_id, true)


func _on_persona_state_change(steam_id: int, _flags: int) -> void:
	var steam_name: String = SteamManager.steam.getFriendPersonaName(steam_id)
	if steam_name == "" or steam_name == STEAM_UNKNOWN_NAME:
		return
	for entry in entries:
		if entry.disabled == false and entry.steam_id == steam_id:
			entry.name_label.text = steam_name


## Called only after a prime-server read has filled this screen's records.
func on_prime_rows_updated() -> void:
	if visible and source == Source.STEAM:
		if friends_only and friends_downloaded:
			generate_friends_leaderboard()
		elif not friends_only:
			generate_steam_leaderboard()


func generate_steam_leaderboard():
	if world_rows.is_empty() or int(world_rows[0].global_rank) == page * PAGE_SIZE + 1:
		draw_prime_rows(world_rows, 0)


func generate_friends_leaderboard():
	var first: int = page * PAGE_SIZE
	draw_prime_rows(friends_rows.slice(first, first + PAGE_SIZE), first)


func generate_local_leaderboard():
	var first: int = page * PAGE_SIZE
	draw_prime_rows(scores.local_scores.slice(first, first + PAGE_SIZE), first)


## Supply only mod records to the game's existing row widgets.
func draw_prime_rows(rows: Array, first: int) -> void:
	clear_entries()
	var own_id: int = int(SteamManager.steam.getSteamID()) if source == Source.STEAM else 0
	for slot in mini(rows.size(), PAGE_SIZE):
		var row: Dictionary = rows[slot]
		var rank: int = first + slot + 1
		if source == Source.LOCAL:
			entries[slot].setup_local(rank, format_value(int(row.score)))
		else:
			if not friends_only:
				rank = int(row.global_rank)
			show_steam_row(entries[slot], row, rank)
			if int(row.steam_id) == own_id:
				steam_user_rank = int(row.global_rank)
	var focus_own_row: bool = _hover_self_on_next_generate and source == Source.STEAM
	_hover_self_on_next_generate = false
	refresh_nav_buttons()
	if focus_own_row:
		hover_own_entry()

func is_my_score_disabled() -> bool:
	if source != Source.STEAM or not world_usable():
		return true
	var own_rank: int = get_own_friends_index() + 1 if friends_only else steam_user_rank
	if own_rank > 0:
		return page == floori(float(own_rank - 1) / float(PAGE_SIZE))
	return friends_downloaded if friends_only else own_rank == STEAM_USER_RANK_NONE



func get_page_count() -> int:
	var count: int = scores.local_scores.size()
	if source == Source.STEAM:
		count = friends_rows.size() if friends_only else world_count
	return maxi(1, ceili(float(count) / float(PAGE_SIZE)))


func should_request_remote_on_page_change() -> bool:
	if friends_only:
		return friends_downloaded == false
	return true


func get_own_friends_index() -> int:
	var local_id: int = SteamManager.steam.getSteamID()
	for i in friends_rows.size():
		if friends_rows[i].steam_id == local_id:
			return i
	return -1


# ------------------------------------- the requests that replace ScoreManager's Steam downloads

## ScoreManager.request_steam_leaderboard: one page of ten from the server.
func request_world_page(for_page: int) -> void:
	pending += 1
	# Stale: a newer page read began meanwhile, so this older answer is neither drawn nor a failure.
	var result: Dictionary = await online.screen_page(for_page * PAGE_SIZE)
	pending -= 1
	if result.get("stale", false):
		return
	if result.is_empty():
		_on_world_failed()
		return
	world_rows = online.steam_rows(result.entries)
	world_count = int(result.players)
	on_prime_rows_updated()


## ScoreManager.request_steam_user_rank: the fresh own rank (around), 0 when the server has none.
func request_world_user_rank() -> void:
	pending += 1
	var own: Dictionary = await online.screen_own_rank()
	pending -= 1
	if own.get("stale", false):
		return
	if own.get("ok") == true:
		_on_steam_user_rank_updated(int(own.rank))
	elif own.get("none", false):
		_on_steam_user_rank_updated(STEAM_USER_RANK_NONE)
	else:
		_on_world_failed()


## ScoreManager.request_steam_friends_leaderboard: the player and their Steam friends on the server.
func request_world_friends() -> void:
	var steam: Object = SteamManager.steam
	var ids:= PackedStringArray([str(steam.getSteamID())])
	for i in steam.getFriendCount(SteamManager.FRIEND_FLAG_IMMEDIATE):
		ids.append(str(steam.getFriendByIndex(i, SteamManager.FRIEND_FLAG_IMMEDIATE)))
	pending += 1
	var result: Dictionary = await online.screen_friends(ids)
	pending -= 1
	if result.get("stale", false):
		return
	if result.is_empty():
		_on_world_failed()
		return
	friends_rows = online.steam_rows(result.entries)
	friends_downloaded = true
	on_prime_rows_updated()


## ScoreManager.steam_leaderboard_failed, with the prime text in the game's "steam failed" label.
func _on_world_failed() -> void:
	steam_failed_label.text = word("world failed")
	_on_steam_leaderboard_failed("prime world ranking not reached")
