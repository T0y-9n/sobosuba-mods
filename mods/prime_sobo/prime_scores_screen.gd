extends ScoresScreen
## Prime scores screen. The game's own scores_screen.tscn is instanced a second time by
## prime_sobo.gd and given this script, so the layout is the game's; only the title, a heading
## and the colours mark it as the mod's board. The game's screen node and script files are untouched.
## The game's ScoresScreen flow (source, friends only, pages, my score, hover, page count, buttons)
## runs as it is. This script only replaces where the game fetches records through ScoreManager:
## - Source.STEAM is the prime world ranking (prime_online.gd): a page of ten, the own rank (around)
##   and friends only (the player's and their Steam friends' IDs). The answers are kept here the way
##   ScoreManager keeps the Steam leaderboard, in the same row shape, and drawn with setup_steam.
## - Source.LOCAL is prime_sobo_scores.json (top 10); clear local scores clears only that board.
## Never connects to ScoreManager.steam_leaderboard_* (the author's Steam leaderboard).

const TITLE:= "prime scores"
## Hue of prime_sobo.PRIME_COLOR (0.62, 0.62, 0.68). The game's menu is neutral grey, so the
## prime board keeps each colour's brightness and alpha and turns it slate grey.
const PRIME_HUE:= 0.667
const PRIME_SATURATION:= 0.25
## Steam's name for a user whose name has not arrived yet.
const STEAM_UNKNOWN_NAME:= "[unknown]"

## Set by prime_sobo.gd before the screen enters the tree.
var scores: Node = null
var online: Node = null

var heading: Label
## What ScoreManager holds for the game's screen (steam_leaderboard_high_scores, the entry count,
## steam_friends_leaderboard_high_scores, steam_friends_downloaded), from the prime server.
var world_rows: Array = []
var world_count:= 0
var friends_rows: Array = []
var friends_downloaded:= false
## Server requests in flight (the self test waits until this is 0).
var pending:= 0


func _ready() -> void:
	# Not super(): ScoresScreen._ready connects the author's Steam leaderboard signals.
	for i in PAGE_SIZE:
		var entry: LeaderboardEntry = leaderboard_entry_ps.instantiate()
		leaderboard_container.add_child(entry)
		entries.append(entry)
		entry.clear()
	side_title_text = TITLE
	build_heading()
	# Buttons connected their own apply_style first, so this runs after it on every style change.
	recolor()
	StyleManager.style_changed.connect(recolor)
	if OS.has_feature("steam"):
		if SteamManager.steam_ready:
			_connect_steam()
		else:
			SteamManager.steam_initialized.connect(_connect_steam, CONNECT_ONE_SHOT)


func _connect_steam() -> void:
	_connect_steam_avatar()
	SteamManager.steam.connect("persona_state_change", _on_persona_state_change)


## The mod's words in the game's language (prime_text.gd next to this script).
func word(key: String) -> String:
	return load((get_script() as Script).resource_path.get_base_dir().path_join("prime_text.gd")).get_text(key)


## One plain-text line above the list, in the game's font for the language (the game swaps the
## theme's font when the language changes). The side title is an SDF label (ASCII glyphs only).
func build_heading() -> void:
	heading = Label.new()
	heading.name = "PrimeHeading"
	heading.text = word("scores heading")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var slot: Node = get_node_or_null("MainVBox/ListSlot")
	if slot == null:
		push_warning("[prime_sobo] scores screen: MainVBox/ListSlot not found; heading placed at the top")
		add_child(heading)
		return
	slot.get_parent().add_child(heading)
	slot.get_parent().move_child(heading, slot.get_index())


static func prime_tint(c: Color) -> Color:
	return Color.from_hsv(PRIME_HUE, PRIME_SATURATION, c.v, c.a)


func prime_buttons(node: Node, found: Array[SoboButton]) -> Array[SoboButton]:
	for child: Node in node.get_children():
		if child is SoboButton:
			found.append(child)
		prime_buttons(child, found)
	return found


func recolor() -> void:
	for b: SoboButton in prime_buttons(self, []):
		b.highlight_color = prime_tint(b.highlight_color)
		b.highlight_hover_color = prime_tint(b.highlight_hover_color)
		b.highlight_pressed_color = prime_tint(b.highlight_pressed_color)
		b.highlight_disabled_color = prime_tint(b.highlight_disabled_color)
		b.background_color = prime_tint(b.background_color)
		b.background_hover_color = prime_tint(b.background_hover_color)
		b.background_pressed_color = prime_tint(b.background_pressed_color)
		b.background_disabled_color = prime_tint(b.background_disabled_color)
	if heading != null and StyleManager.current_style != null:
		heading.add_theme_color_override("font_color", prime_tint(StyleManager.current_style.ui_highlight_color))


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
	# The language may have changed since the heading was made.
	heading.text = word("scores heading")
	page = 0
	steam_user_rank = STEAM_USER_RANK_UNKNOWN
	_hover_self_on_next_generate = false
	source = Source.STEAM if world_usable() else Source.LOCAL
	refresh_buttons()
	refresh_leaderboard()
	# MenuScreen.open() without ScoresScreen.open(), which picks the author's Steam board.
	SoboButton.currently_hovered = get_first_button_to_hover()
	Ui._0.mouse_hovering_disabled = false


func refresh_buttons():
	super()
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
		refresh_friends_leaderboard(request_remote)
		return
	apply_page_ranks(world_count)
	if request_remote:
		request_world_page(page)


func refresh_friends_leaderboard(request_remote: bool) -> void:
	if friends_downloaded:
		apply_page_ranks(friends_rows.size(), false)
		generate_friends_leaderboard()
	else:
		apply_page_ranks(0)
	if request_remote:
		request_world_friends()


func _on_my_score_release_press() -> void:
	if friends_only:
		go_to_own_friends_entry()
		return
	if steam_user_rank > 0:
		go_to_steam_rank(steam_user_rank)
		return
	request_world_user_rank()


## Only the prime local board is cleared, never the game's own local scores.
func _on_clear_local_scores_confirm_release_press() -> void:
	scores.clear_local_scores()
	page = 0
	refresh_leaderboard()
	clear_local_scores_confirm_btn.hide()
	clear_local_scores_btn.show()


func go_to_own_friends_entry() -> void:
	var own_index: int = get_own_friends_index()
	if own_index < 0:
		if friends_downloaded:
			return
		_hover_self_on_next_generate = true
		request_world_friends()
		return
	var my_page: int = floori(float(own_index) / float(PAGE_SIZE))
	if page == my_page:
		hover_own_entry()
		refresh_nav_buttons()
		return
	_hover_self_on_next_generate = true
	page = my_page
	refresh_leaderboard(false)


## A Steam row drawn by the game's setup_steam; the server name stands in until Steam knows the name.
func show_steam_row(entry: LeaderboardEntry, row: Dictionary, rank: int) -> void:
	entry.setup_steam(row, rank)
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


## ScoresScreen._on_steam_leaderboard_updated, with the prime friends rows instead of
## ScoreManager.steam_friends_downloaded (the author's Steam flag, never set here).
func _on_steam_leaderboard_updated() -> void:
	if visible == false || source != Source.STEAM:
		return
	if friends_only:
		if friends_downloaded:
			generate_friends_leaderboard()
		return
	generate_steam_leaderboard()


func generate_steam_leaderboard():
	var local_id: int = SteamManager.steam.getSteamID()
	if world_rows.size() > 0 && world_rows[0].global_rank != page * PAGE_SIZE + 1:
		return
	for i in PAGE_SIZE:
		if i < world_rows.size():
			show_steam_row(entries[i], world_rows[i], world_rows[i].global_rank)
			if world_rows[i].steam_id == local_id:
				steam_user_rank = world_rows[i].global_rank
		else:
			entries[i].clear()
	refresh_nav_buttons()
	if _hover_self_on_next_generate:
		_hover_self_on_next_generate = false
		hover_own_entry()


func generate_friends_leaderboard():
	var local_id: int = SteamManager.steam.getSteamID()
	var start: int = page * PAGE_SIZE
	for i in PAGE_SIZE:
		var index: int = start + i
		if index < friends_rows.size():
			show_steam_row(entries[i], friends_rows[index], index + 1)
			if friends_rows[index].steam_id == local_id:
				steam_user_rank = friends_rows[index].global_rank
		else:
			entries[i].clear()
	refresh_nav_buttons()
	if _hover_self_on_next_generate:
		_hover_self_on_next_generate = false
		hover_own_entry()


func generate_local_leaderboard():
	var rows: Array = scores.local_scores
	var start: int = page * PAGE_SIZE
	for i in PAGE_SIZE:
		var index: int = start + i
		if index < rows.size():
			entries[i].setup_local(index + 1, int(rows[index].score))
		else:
			entries[i].clear()
	refresh_nav_buttons()


func is_my_score_disabled() -> bool:
	if source != Source.STEAM or not world_usable():
		return true
	if friends_only:
		var own_index: int = get_own_friends_index()
		if own_index < 0:
			return friends_downloaded
		return page == floori(float(own_index) / float(PAGE_SIZE))
	if steam_user_rank == STEAM_USER_RANK_NONE:
		return true
	if steam_user_rank > 0:
		return page == floori(float(steam_user_rank - 1) / float(PAGE_SIZE))
	return false


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
	_on_steam_leaderboard_updated()


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
	_on_steam_leaderboard_updated()


## ScoreManager.steam_leaderboard_failed, with the prime text in the game's "steam failed" label.
func _on_world_failed() -> void:
	steam_failed_label.text = word("world failed")
	_on_steam_leaderboard_failed("prime world ranking not reached")
