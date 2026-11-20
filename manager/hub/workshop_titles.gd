extends Node
## Retrieves Workshop titles in one request and retains real cached titles on failure.

signal titles_ready(appid: int, titles: Dictionary, complete: bool)

const MAX_AGE := 24 * 60 * 60
const BootTrace = preload("boot_trace.gd")
static var _store_mutex := Mutex.new()
var endpoint := "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
var _workers: Array[Thread] = []

static func request_body(ids: PackedStringArray) -> String:
	var fields := PackedStringArray(["itemcount=%d" % ids.size()])
	for index in range(ids.size()):
		fields.append("publishedfileids[%d]=%s" % [index, ids[index].uri_encode()])
	return "&".join(fields)

static func cached(appid: int) -> Dictionary:
	var stage := "cache/" + str(appid)
	var lane := "main" if OS.get_thread_caller_id() == OS.get_main_thread_id() else "worker_titles"
	var trace := BootTrace.begin(lane, stage)
	var result := _read_cache(appid)
	BootTrace.end(lane, stage, trace)
	return result

static func _read_cache(appid: int) -> Dictionary:
	var file := FileAccess.open(_path(appid), FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return {}
	var record: Dictionary = json.data
	if record.get("format_version") != 1 or not record.get("titles") is Dictionary:
		return {}
	var fetched: Variant = record.get("fetched_at")
	if not (fetched is int or fetched is float) or fetched <= 0 or fetched > Time.get_unix_time_from_system():
		return {}
	var titles: Dictionary = {}
	for id in record.titles:
		if id is String and id.is_valid_int() and record.titles[id] is String and not record.titles[id].is_empty():
			titles[id] = record.titles[id]
	var unavailable: Dictionary = {}
	var unavailable_ids: Variant = record.get("unavailable_ids", [])
	if unavailable_ids is Array:
		for id in unavailable_ids:
			if id is String and id.is_valid_int():
				unavailable[id] = true
	var unresolved: Dictionary = {}
	var unresolved_ids: Variant = record.get("unresolved_ids", [])
	if unresolved_ids is Array:
		for id in unresolved_ids:
			if id is String and id.is_valid_int() and not unavailable.has(id):
				unresolved[id] = true
	return {"titles": titles, "unavailable": unavailable, "unresolved": unresolved, "fetched_at": int(fetched)}

func request(appid: int, ids: PackedStringArray) -> void:
	var stored: Dictionary = await _io(cached.bind(appid))
	var titles: Dictionary = _selected(stored.get("titles", {}), ids)
	var unavailable := _selected(stored.get("unavailable", {}), ids)
	var unresolved := _selected(stored.get("unresolved", {}), ids)
	var resolved := titles.merged(unavailable).size() == ids.size()
	var recorded := titles.merged(unavailable).merged(unresolved).size() == ids.size()
	if ids.is_empty() or (recorded and Time.get_unix_time_from_system() - int(stored.get("fetched_at", 0)) < MAX_AGE):
		titles_ready.emit(appid, titles, resolved)
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var complete := false
	var error := http.request(endpoint, ["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, request_body(ids))
	if error == OK:
		var response: Array = await http.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200:
			var received := _response_details(response[3], ids)
			if received.valid:
				var saved: Dictionary = await _io(_store_response.bind(appid, received, ids))
				var delivered := _stored_response(saved, received, ids, titles)
				titles = delivered.titles
				complete = delivered.complete
	http.queue_free()
	titles_ready.emit(appid, titles, complete)

func _stored_response(saved: Dictionary, received: Dictionary, ids: PackedStringArray, previous: Dictionary) -> Dictionary:
	var titles := _selected(saved.get("titles", {}), ids)
	if saved.has("thread_start_error"):
		titles = _selected(previous.merged(received.titles, true), ids)
		print("Mod Hub titles store_start_failed code=", saved.thread_start_error)
	return {"titles": titles, "complete": titles.merged(received.unavailable).size() == ids.size()}

func _io(job: Callable) -> Dictionary:
	var worker := Thread.new()
	var error := worker.start(job)
	if error != OK:
		return {"thread_start_error": error}
	_workers.append(worker)
	# An owned signal is cancelled with this node; SceneTree.process_frame outlives it.
	var poll := Timer.new()
	poll.wait_time = 0.01
	add_child(poll)
	poll.start()
	while worker.is_alive():
		await poll.timeout
	var result: Dictionary = worker.wait_to_finish()
	_workers.erase(worker)
	poll.queue_free()
	return result

func _exit_tree() -> void:
	var started := Time.get_ticks_msec()
	for worker in _workers:
		worker.wait_to_finish()
	_workers.clear()
	if get_parent() != null and get_parent().get("_closing") == true:
		print("Mod Hub close titles_", get_parent().name, " ", Time.get_ticks_msec() - started)

static func _store_response(appid: int, received: Dictionary, ids: PackedStringArray) -> Dictionary:
	# One transaction owns read/merge/rename, including the shared temporary path.
	_store_mutex.lock()
	var latest := cached(appid)
	var titles: Dictionary = latest.get("titles", {}).duplicate()
	var unavailable: Dictionary = latest.get("unavailable", {}).duplicate()
	var unresolved: Dictionary = latest.get("unresolved", {}).duplicate()
	for id in ids:
		unavailable.erase(id)
		unresolved.erase(id)
	titles.merge(received.titles, true)
	unavailable.merge(received.unavailable, true)
	unresolved.merge(received.unresolved, true)
	_save(appid, titles, unavailable, unresolved)
	_store_mutex.unlock()
	return {"titles": titles}

func _response_details(body: PackedByteArray, ids: PackedStringArray) -> Dictionary:
	var titles: Dictionary = {}
	var unavailable: Dictionary = {}
	var unresolved: Dictionary = {}
	var details := {"valid": false, "titles": titles, "unavailable": unavailable, "unresolved": unresolved}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return details
	var response: Variant = json.data.get("response")
	if not response is Dictionary or response.get("result") != 1 or not response.get("publishedfiledetails") is Array:
		return details
	details.valid = true
	for detail in response.publishedfiledetails:
		if not detail is Dictionary:
			continue
		var id := str(detail.get("publishedfileid", ""))
		if not id in ids:
			continue
		var title: Variant = detail.get("title")
		if detail.get("result") == 1 and title is String and not title.is_empty():
			titles[id] = title
			unavailable.erase(id)
		elif detail.get("result") == 9:
			unavailable[id] = true
			titles.erase(id)
	for id in ids:
		if not titles.has(id) and not unavailable.has(id):
			unresolved[id] = true
	return details

func _selected(titles: Dictionary, ids: PackedStringArray) -> Dictionary:
	var selected: Dictionary = {}
	for id in ids:
		if titles.has(id):
			selected[id] = titles[id]
	return selected

static func _path(appid: int) -> String:
	return "user://hub-cache/workshop-%d.json" % appid

static func _save(appid: int, titles: Dictionary, unavailable: Dictionary, unresolved: Dictionary) -> void:
	if DirAccess.make_dir_recursive_absolute("user://hub-cache") != OK:
		return
	var temporary := _path(appid) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"format_version": 1, "fetched_at": int(Time.get_unix_time_from_system()),
		"titles": titles, "unavailable_ids": unavailable.keys(), "unresolved_ids": unresolved.keys()}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, _path(appid)) != OK:
		# This invocation opened this temporary file; a failed save must not leave it behind.
		DirAccess.remove_absolute(temporary)
