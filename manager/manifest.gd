extends RefCounted

static func valid_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*$")
	return pattern.search(value) != null and value.to_upper() not in ["CON", "PRN", "AUX", "NUL", "COM1", "LPT1"]

static func safe_relative(value: String) -> bool:
	if value.is_empty() or value.contains("\\") or value.contains(":") or value.is_absolute_path():
		return false
	for part in value.split("/"):
		if part.is_empty() or part in [".", ".."] or part.ends_with(".") or part.ends_with(" "):
			return false
	return true

static func read_metadata(text: String, mod_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	for field in ["id", "name", "version", "autoload", "entry"]:
		if not parsed.get(field) is String or parsed[field].is_empty():
			return {}
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z_][A-Za-z0-9_]*$")
	if parsed.id != mod_id or not valid_id(mod_id) or pattern.search(parsed.autoload) == null:
		return {}
	if not safe_relative(parsed.entry) or not parsed.entry.ends_with(".gd"):
		return {}
	return parsed

static func legacy(mod_id: String) -> Dictionary:
	if mod_id != "prime_sobo":
		return {}
	return {"id": mod_id, "name": "Prime sobos", "version": "", "autoload": "PrimeSobo", "entry": "prime_sobo.gd"}
