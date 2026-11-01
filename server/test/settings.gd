extends SceneTree
## Standalone Godot only; no sobosuba assets, autoloads, or game launch.
## Prime mode on/off (spec §7) on real files: the switch, and the mode a run keeps.
var failures:= 0
func check(ok: bool, what: String) -> void:
	print("SETTINGS_CHECK ", "OK " if ok else "FAIL ", what)
	if not ok:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func written(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func fresh(script: Script, path: String) -> RefCounted:
	var settings: RefCounted = script.new()
	settings.path = path
	settings.load_file()
	return settings

func run() -> void:
	var args:= OS.get_cmdline_user_args()
	var script: Script = load(args[0])
	if script == null or not script.can_instantiate():
		check(false, "prime_settings.gd compiles")
		quit(1)
		return
	var dir: String = args[1]
	var defaults: RefCounted = script.new()
	check(defaults.PATH == "user://prime_sobo_settings.json" and defaults.SELFTEST_PATH == "user://prime_sobo_settings_selftest.json" and defaults.path == defaults.PATH, "real and self-test files are the spec's, the real one by default")

	# No file: prime mode is on (the MOD is installed).
	var path: String = dir.path_join("settings.json")
	var settings: RefCounted = fresh(script, path)
	check(settings.enabled and settings.run_prime and not FileAccess.file_exists(path), "no file: on, and reading writes nothing")
	# Broken or foreign files are read as on.
	for text: String in ["{", "[]", "{\"enabled\": \"no\"}", "{\"enabled\": 0}"]:
		var broken_path: String = dir.path_join("broken.json")
		var f:= FileAccess.open(broken_path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		check(fresh(script, broken_path).enabled, "unreadable value %s is read as on" % text)

	# A new run takes the switch; the switch is kept in the file.
	check(settings.start_run(false) == true, "a new run with the switch on is prime")
	check(settings.set_enabled(false), "switching off is written")
	check(written(path) is Dictionary and written(path).get("enabled") == false, "the file says off: %s" % [written(path)])
	check(fresh(script, path).enabled == false, "off is read back by the next start of the game")
	# The run in progress keeps the mode it started with.
	check(settings.run_prime == true, "switching off mid-run leaves this run prime")
	check(settings.start_run(false) == false and settings.run_prime == false, "the next new run is the game's own")
	check(written(path).get("run_prime") == false, "the new run's mode is written with it")

	# A run continued from the game's save. The game writes its save only when it closes, and a new
	# run neither deletes nor rewrites the older save, so start_run is told which save it is (save_id,
	# the save file's MD5 from prime_sobo.gd): at a new run the save that was there when it began
	# ("" for none), when continuing the save being loaded.
	var takes_save_id:= false
	for method: Dictionary in script.get_script_method_list():
		if method.name == "start_run":
			takes_save_id = method.args.size() == 3
	check(takes_save_id, "start_run is told whether the save holds prime balls and which save it is")
	if not takes_save_id:
		print("SETTINGS_DONE failures=%d" % failures)
		quit(1)
		return

	# The latest run (the game's own, begun with no save on disk) saved when the game closed.
	settings.set_enabled(true)
	check(settings.run_prime == false, "switching on mid-run leaves this run the game's own")
	var restarted: RefCounted = fresh(script, path)
	check(restarted.enabled and restarted.start_run(true, false, "save-of-B") == false, "a continued run keeps the game's own mode although the switch is on")
	check(restarted.start_run(false, false, "") == true, "then a new run is prime again")
	restarted.set_enabled(false)
	check(fresh(script, path).start_run(true, false, "save-of-C") == true, "a continued prime run stays prime although the switch is off")

	# Prime run A saved ("save-of-A"), the switch turned off, run B (the game's own) begun while A's
	# save was still there and lost before any save of its own (a crash): the save is still A's.
	var lost: RefCounted = fresh(script, path)
	lost.set_enabled(true)
	lost.start_run(false, false, "")
	lost.set_enabled(false)
	check(lost.start_run(false, false, "save-of-A") == false, "run B, begun over A's save, is the game's own")
	check(written(path).get("older_save") == "save-of-A", "the save that was there when B began is remembered: %s" % [written(path)])
	# B's own save (written when the game closed) is a different file: B's mode.
	check(fresh(script, path).start_run(true, false, "save-of-B") == false, "B's own save continues as the game's own")
	# A's save resumed: not B's, so prime, even with no prime ball left on A's board.
	var resumed: RefCounted = fresh(script, path)
	check(resumed.start_run(true, false, "save-of-A") == true and resumed.run_prime, "the save that was there before the latest run is prime although off was remembered")
	check(written(path).get("run_prime") == true, "that prime mode is written for the run: %s" % [written(path)])
	# Prime balls on the board make a continued save prime whatever else was remembered.
	var again: RefCounted = fresh(script, path)
	check(again.start_run(false, false, "") == false, "another run of the game's own")
	check(fresh(script, path).start_run(true, true, "save-of-D") == true, "a continued save holding prime balls is prime although off was remembered")
	# A save that cannot be told apart (no MD5) is prime.
	check(fresh(script, path).start_run(false, false, "save-of-F") == false, "a run of the game's own begun over another save")
	check(fresh(script, path).start_run(true, false, "") == true, "a continued save without an MD5 is prime")

	# "No save" and "a save whose MD5 could not be read" are different things: prime_sobo.gd asks
	# save_id_of(has_save, md5) for the id it passes, so a save that is there is never taken for none.
	var tells_unreadable: bool = script.get_script_constant_map().has("UNREADABLE_SAVE") and settings.has_method("save_id_of")
	check(tells_unreadable, "the settings tell a save whose MD5 could not be read from no save")
	if tells_unreadable:
		var unreadable: String = settings.save_id_of(true, "")
		check(settings.save_id_of(false, "") == "" and unreadable == script.get_script_constant_map().UNREADABLE_SAVE and unreadable != "" and settings.save_id_of(true, "save-of-G") == "save-of-G", "ids: none '', unreadable '%s', readable its MD5" % unreadable)
		# Prime run G saved; the switch turned off; run H (the game's own) begun while G's save was
		# there but its MD5 could not be read, then lost before it saved. G's save is read normally
		# later: H cannot have been told apart from it, so it resumes as prime.
		var unread: RefCounted = fresh(script, path)
		unread.set_enabled(false)
		check(unread.start_run(false, false, settings.save_id_of(true, "")) == false, "run H, begun over a save it could not read, is the game's own")
		check(written(path).get("older_save") == unreadable, "the unreadable save is remembered as unreadable, not as none: %s" % [written(path)])
		check(fresh(script, path).start_run(true, false, "save-of-G") == true, "a save resumed after a run begun over an unreadable save is prime")
		# A run of the game's own begun with no save: its own save, when it cannot be read, is prime.
		check(fresh(script, path).start_run(false, false, settings.save_id_of(false, "")) == false, "a run of the game's own begun with no save")
		check(fresh(script, path).start_run(true, false, settings.save_id_of(true, "")) == true, "a continued save whose MD5 could not be read is prime")
		check(fresh(script, path).start_run(false, false, settings.save_id_of(false, "")) == false and fresh(script, path).start_run(true, false, "save-of-H") == false, "a run begun with no save still continues its own readable save as the game's own")

	# A file without the run's mode or without the save it began over (written by an older MOD):
	# a continued run counts as prime, so a run that may hold prime balls never reaches the
	# author's Steam leaderboard.
	for text: String in ["{\"enabled\": false}", "{\"enabled\": false, \"run_prime\": false}"]:
		var plain_path: String = dir.path_join("plain.json")
		var plain_file:= FileAccess.open(plain_path, FileAccess.WRITE)
		plain_file.store_string(text)
		plain_file.close()
		var plain: RefCounted = fresh(script, plain_path)
		check(plain.enabled == false and plain.start_run(true, false, "save-of-E") == true, "unknown run of a continued save is prime: %s" % text)

	# "send scores" (spec §8): off unless the player turns it on, and kept in the same file.
	var send_path: String = dir.path_join("send.json")
	var send: RefCounted = fresh(script, send_path)
	check(send.send_scores == false, "send scores is off with no file")
	for text: String in ["{", "{\"send_scores\": \"yes\"}", "{\"send_scores\": 1}"]:
		var bad_send_file:= FileAccess.open(send_path, FileAccess.WRITE)
		bad_send_file.store_string(text)
		bad_send_file.close()
		check(fresh(script, send_path).send_scores == false, "unreadable send scores %s is read as off" % text)
	send = fresh(script, send_path)
	send.set_enabled(false)
	check(send.set_send_scores(true) and written(send_path).get("send_scores") == true, "turning send scores on is written: %s" % [written(send_path)])
	var send_again: RefCounted = fresh(script, send_path)
	check(send_again.send_scores == true and send_again.enabled == false, "send scores is read back and the prime switch is kept")
	send_again.set_send_scores(false)
	check(fresh(script, send_path).send_scores == false, "turning send scores off is read back")
	# A choice that could not be written is not taken: after a restart the file would say otherwise.
	var unwritable: RefCounted = script.new()
	unwritable.path = dir.path_join("no such folder").path_join("send.json")
	check(unwritable.set_send_scores(true) == false and unwritable.send_scores == false, "send scores that could not be written stays as it was")

	# The self-test writes only its own file.
	var real_path: String = dir.path_join("real.json")
	var real_file:= FileAccess.open(real_path, FileAccess.WRITE)
	real_file.store_string("{\"enabled\": true, \"run_prime\": true}")
	real_file.close()
	var real_before: String = FileAccess.get_md5(real_path)
	var selftest: RefCounted = fresh(script, dir.path_join("selftest.json"))
	selftest.set_enabled(false)
	selftest.start_run(false)
	check(FileAccess.get_md5(real_path) == real_before and written(dir.path_join("selftest.json")).get("enabled") == false, "another path leaves the real file as it was")

	# The prime marker (save_run_state): a prime run that cannot save its mode and cannot remove the
	# stale file leaves a marker, so a restart stays prime. The marker holds the settings file's MD5,
	# so a later save that rewrites the file retires it even when it was not removed, and a successful
	# save removes it.
	var marker_path: String = dir.path_join("marker.json")
	var base: RefCounted = fresh(script, marker_path)
	base.enabled = false
	base.run_prime = false
	check(base.save_file(), "a file with run_prime false is written")
	var count_at_marker: int = base.save_count
	check(base.write_prime_marker() and fresh(script, marker_path).run_prime == true, "a marker matching the file's save_count keeps a restart on the prime side")
	# A normal run saves the same run_prime = false: the contents match, but the save_count rises.
	var normal: RefCounted = fresh(script, marker_path)
	normal.run_prime = false
	check(normal.save_file() and normal.save_count > count_at_marker, "saving the same mode again still raises the save_count")
	# A marker left from before that save (its removal failed) holds the old count and is ignored.
	var leftover:= FileAccess.open(marker_path + ".prime", FileAccess.WRITE)
	leftover.store_string(str(count_at_marker))
	leftover.close()
	check(fresh(script, marker_path).run_prime == false, "a marker left from before a same-contents save is ignored, not read as prime")
	# A successful save_run_state removes a matching marker.
	var recovered: RefCounted = fresh(script, marker_path)
	check(recovered.write_prime_marker() and FileAccess.file_exists(marker_path + ".prime"), "a marker is written again")
	recovered.run_prime = false
	check(recovered.save_run_state() and not FileAccess.file_exists(marker_path + ".prime"), "a successful save removes the marker")
	# A marker from an older mod (not a save_count: the literal "prime") is honoured once, so updating
	# from a version that wrote that format does not lose a prime recovery.
	var old_path: String = dir.path_join("old-marker.json")
	var old_base: RefCounted = fresh(script, old_path)
	old_base.enabled = false
	old_base.run_prime = false
	check(old_base.save_file(), "a file with run_prime false is written for the old-marker case")
	var old_marker:= FileAccess.open(old_path + ".prime", FileAccess.WRITE)
	old_marker.store_string("prime")
	old_marker.close()
	check(fresh(script, old_path).run_prime == true, "the old 'prime' marker is honoured once as a prime recovery")
	check(FileAccess.get_file_as_string(old_path + ".prime").is_valid_int(), "reading it migrated the marker to a save_count form")
	var migrated: RefCounted = fresh(script, old_path)
	migrated.run_prime = false
	check(migrated.save_run_state() and not FileAccess.file_exists(old_path + ".prime"), "a later normal save then removes the migrated marker")
	var empty_marker:= FileAccess.open(old_path + ".prime", FileAccess.WRITE)
	empty_marker.store_string("")
	empty_marker.close()
	check(fresh(script, old_path).run_prime == false, "an empty marker is not 'prime' and is ignored")

	print("SETTINGS_DONE failures=%d" % failures)
	quit(1 if failures else 0)
