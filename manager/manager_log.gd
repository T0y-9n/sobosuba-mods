extends RefCounted

const LIMIT := 1024 * 1024

static func file_path() -> String:
	return ProjectSettings.globalize_path("user://manager.log")

static func timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	var zone: Dictionary = Time.get_time_zone_from_system()
	var minutes := int(zone.get("bias", 0))
	var sign := "+" if minutes >= 0 else "-"
	var absolute := absi(minutes)
	return "%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second, sign, int(absolute / 60.0), absolute % 60]

static func redact(text: String) -> String:
	var out := text
	for key in ["USERPROFILE", "HOME"]:
		var home := OS.get_environment(key)
		if home.is_empty():
			continue
		out = out.replace(home, "~")
		out = out.replace(home.replace("\\", "/"), "~")
		out = out.replace(home.replace("/", "\\"), "~")
	var pattern := RegEx.new()
	pattern.compile("(?i)[A-Za-z]:[\\\\/]+Users[\\\\/]+[^\\\\/]+")
	out = pattern.sub(out, "~", true)
	pattern.compile("(?i)/Users/[^/]+")
	out = pattern.sub(out, "~", true)
	pattern.compile("(?i)/home/[^/]+")
	out = pattern.sub(out, "~", true)
	return out

static func record(operation: String, mod_id: String, before: String, after: String, ok: bool, reason: String, details: Array, game_version: String) -> bool:
	var fields: PackedStringArray = PackedStringArray([timestamp(), operation])
	if not mod_id.is_empty():
		fields.append(mod_id)
	if not before.is_empty() and not after.is_empty():
		fields.append(before + " -> " + after)
	elif not after.is_empty():
		fields.append("-> " + after)
	elif not before.is_empty():
		fields.append(before + " ->")
	fields.append("済み" if ok else "止めた")
	if not ok and not reason.is_empty():
		fields.append(reason)
	for detail in details:
		var shown := redact(str(detail))
		if not shown.is_empty():
			fields.append(shown)
	fields.append("game=" + game_version)
	return append(" ".join(fields))

static func append(line: String) -> bool:
	var current := file_path()
	var previous := current + ".1"
	var size := byte_length(current)
	if size < 0:
		return false
	if size > LIMIT:
		if FileAccess.file_exists(previous) and DirAccess.remove_absolute(previous) != OK:
			return false
		if DirAccess.rename_absolute(current, previous) != OK:
			return false
	# WRITE_READ creates a missing file. READ_WRITE keeps the bytes already there.
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(current) else FileAccess.WRITE_READ
	var file := FileAccess.open(current, mode)
	if file == null:
		return false
	file.seek_end()
	file.store_line(redact(line))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

static func byte_length(current: String) -> int:
	if not FileAccess.file_exists(current):
		return 0
	var file := FileAccess.open(current, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

static func tail(count: int) -> PackedStringArray:
	var current := file_path()
	if not FileAccess.file_exists(current):
		return PackedStringArray()
	var file := FileAccess.open(current, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var lines := file.get_as_text().split("\n", false)
	file.close()
	if lines.size() > count:
		lines = lines.slice(lines.size() - count)
	var shown := PackedStringArray()
	for line in lines:
		shown.append(redact(line))
	return shown

static func diagnostics(manager_version: String, game_version: String, game_folder: String, mods: Array, order: Array) -> String:
	var lines: PackedStringArray = PackedStringArray([
		"manager " + manager_version,
		"game " + game_version,
		"folder " + redact(game_folder),
	])
	for mod in mods:
		if not mod is Dictionary:
			continue
		var id := str(mod.get("id", ""))
		var place := order.find(id)
		var state := "on" if mod.get("enabled", false) else "off"
		lines.append(id + " " + str(mod.get("version", "")) + " " + state + " order=" + str(place))
	lines.append_array(tail(50))
	return "\n".join(lines)
