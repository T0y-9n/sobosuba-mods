extends RefCounted
## Prime mode on/off (spec §7), kept in this mod's own file, never in the game's settings.tres.
## {"enabled": bool, "run_prime": bool, "older_save": String, "send_scores": bool}
## - enabled: the "prime balls" switch in settings -> game. No file or an unreadable value: on.
## - run_prime: the mode the latest run started with. The game saves only the run in progress
##   (user://game_state.tres, at quit), so a run continued from that save keeps this mode.
## - older_save: the MD5 of the save that was on disk when the latest run began ("" for none,
##   UNREADABLE_SAVE for a save that was there but whose MD5 could not be read).
##   A new run neither deletes nor rewrites that save, so if the run is lost before it saves (a
##   crash), the save left is the older run's, not the one run_prime was remembered for.
## Unknown: prime, so a run that may hold prime balls never reaches the author's Steam leaderboard.
## - send_scores: the "send scores" switch (spec §8). No file or an unreadable value: off.
## No game classes (tested alone in server/test/settings.test.mjs). Used by prime_sobo.gd.

const PATH:= "user://prime_sobo_settings.json"
const SELFTEST_PATH:= "user://prime_sobo_settings_selftest.json"
## The id of a save that is on disk but whose MD5 could not be read. Never an MD5 (not hex), and not
## "" (no save): a run begun over it cannot be told apart from that save later.
const UNREADABLE_SAVE:= "unreadable"

var path:= PATH
var enabled:= true
var run_prime:= true
## null while unknown (no file, or a file from before this was kept).
var older_save: Variant = null
var send_scores:= false
## Rises on every successful save. The marker records it, so a later save retires the marker even when
## the file's contents are otherwise unchanged (a normal run writing the same run_prime = false).
var save_count:= 0


func load_file() -> void:
	enabled = true
	run_prime = true
	older_save = null
	send_scores = false
	if not FileAccess.file_exists(path):
		return
	# JSON.new().parse reports a broken file by its return value, without an engine error.
	var json:= JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return
	var data: Dictionary = json.data
	if data.get("enabled") is bool:
		enabled = data.enabled
	if data.get("run_prime") is bool:
		run_prime = data.run_prime
	if data.get("older_save") is String:
		older_save = data.older_save
	if data.get("send_scores") is bool:
		send_scores = data.send_scores
	if data.get("save_count") is float:
		save_count = int(data.save_count)
	# The marker (see save_run_state) outranks a stale run_prime = false, but only while its save_count
	# still matches the file. Every successful save raises the count, so a later save retires the
	# marker even when it could not be deleted and the rest of the file is unchanged.
	if not run_prime and marker_matches_file():
		run_prime = true
	# An older mod (before save_count) wrote the marker as the exact text "prime". Honour that one
	# known form once as a prime recovery and rewrite it in this file's save_count form, so from then
	# on the save_count rule governs it. An empty or garbled marker is not "prime", so it is ignored.
	elif not run_prime and FileAccess.file_exists(prime_marker_path()) and FileAccess.get_file_as_string(prime_marker_path()) == "prime":
		run_prime = true
		write_prime_marker()


func save_file() -> bool:
	var file:= FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[prime_sobo] settings not saved: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var next_count:= save_count + 1
	var data:= {"enabled": enabled, "run_prime": run_prime, "send_scores": send_scores, "save_count": next_count}
	if older_save is String:
		data.older_save = older_save
	file.store_string(JSON.stringify(data))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error == OK:
		save_count = next_count
	return error == OK


## The switch. The run in progress keeps its mode.
func set_enabled(value: bool) -> bool:
	enabled = value
	return save_file()


## Whether a run's score goes to the world ranking, from the next game over. Sent scores stay.
## A choice that could not be written is not taken (a restart would read the old one back).
func set_send_scores(value: bool) -> bool:
	var before:= send_scores
	send_scores = value
	if save_file():
		return true
	send_scores = before
	return false


## The save id start_run is given: "" when there is no save, UNREADABLE_SAVE when there is one but
## its MD5 (FileAccess.get_md5, "" on failure) could not be read, otherwise the MD5.
func save_id_of(has_save: bool, md5: String) -> String:
	if not has_save:
		return ""
	return md5 if md5 != "" else UNREADABLE_SAVE


## When a run starts: a new run takes the switch, a run continued from the game's save keeps the
## mode it started with. Returns whether this run is prime.
## save_id is from save_id_of: at a new run the save on disk when it begins, when continuing the
## save being loaded. A continued save is prime whatever was remembered when it holds prime balls (a
## run started off never rolls one), when it is the save that was there before the latest run began
## (that run was lost before it saved), or when it cannot be told apart: its MD5 or the one
## remembered could not be read.
func start_run(continued: bool, save_holds_primes:= false, save_id:= "") -> bool:
	if not continued:
		run_prime = enabled
		older_save = save_id
		save_run_state()
	elif not run_prime and (save_holds_primes or save_id == "" or save_id == UNREADABLE_SAVE or not older_save is String or older_save == UNREADABLE_SAVE or save_id == older_save):
		run_prime = true
		save_run_state()
	return run_prime


## Writes the run's mode. A write that fails is reported. If it fails while this run is prime and the
## file on disk still says the latest run was not (it would read back as the game's own run, with the
## game's Steam upload and achievements), the file is removed: no file reads back as prime.
## Returns whether the file was written.
func save_run_state() -> bool:
	if save_file():
		# The file now holds the current mode. The marker was written against an older file, so its
		# MD5 no longer matches and load_file ignores it; removing it is tidy-up, and a failure here
		# no longer makes a normal run read back as prime.
		if FileAccess.file_exists(prime_marker_path()):
			DirAccess.remove_absolute(prime_marker_path())
		return true
	push_warning("[prime_sobo] run mode not saved (run_prime=%s); a restart may not know it" % run_prime)
	if run_prime and file_says_not_prime():
		var error: Error = DirAccess.remove_absolute(path)
		if error != OK:
			push_warning("[prime_sobo] stale run mode could not be removed: %s (%s)" % [path, error_string(error)])
			# The stale file stays and would read back as the game's own run. A second file, which
			# load_file reads as "the latest run was prime", keeps the restart on the prime side.
			if not write_prime_marker():
				# TODO-138: nothing could be written. This run stays prime in memory (start_run returns
				# run_prime), but a restart reads the stale file; start_run's save_holds_primes check
				# is then the only thing left that treats a continued save as prime.
				push_warning("[prime_sobo] prime run could not be remembered on disk: a restart may read the older mode")
	return false


## A second file next to the settings file, holding the settings file's save_count as it was when the
## marker was written. load_file reads it as run_prime = true only while that count still matches the
## file. Every successful save raises the count, so a later save retires the marker even when the
## file's contents are otherwise unchanged and the marker could not be removed.
func prime_marker_path() -> String:
	return path + ".prime"


## Whether a marker is there and still matches the file's save_count. A save raises the count, so the
## marker no longer matches and is ignored, even when the rest of the file is unchanged.
func marker_matches_file() -> bool:
	if not FileAccess.file_exists(prime_marker_path()):
		return false
	return FileAccess.get_file_as_string(prime_marker_path()) == str(save_count)


func write_prime_marker() -> bool:
	var file:= FileAccess.open(prime_marker_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(str(save_count))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK


## Whether the file on disk holds run_prime = false. A missing or broken file reads back as prime.
func file_says_not_prime() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var json:= JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return false
	var value: Variant = json.data.get("run_prime")
	return value is bool and value == false
