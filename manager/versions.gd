extends RefCounted

# Do not guess version ordering for unknown formats or different prerelease families.
static func parse(value: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$")
	var found := pattern.search(value)
	if found == null:
		return {}
	var core: Array = []
	for i in [1, 2, 3]:
		var part := found.get_string(i)
		if part.length() > 9:
			return {}
		core.append(int(part))
	var pre := found.get_string(4).replace("-", ".").split(".") if not found.get_string(4).is_empty() else PackedStringArray()
	for part in pre:
		if part.is_empty() or (part.is_valid_int() and (part.length() > 9 or (part.length() > 1 and part.begins_with("0")))):
			return {}
	return {"core":core, "pre":pre}

# Return -2 when incomparable, otherwise -1, 0 or 1.
static func compare(candidate: String, current: String) -> int:
	var a := parse(candidate)
	var b := parse(current)
	if a.is_empty() or b.is_empty():
		return -2
	for i in 3:
		if a.core[i] != b.core[i]:
			return 1 if a.core[i] > b.core[i] else -1
	if a.pre.is_empty() or b.pre.is_empty():
		return 0 if a.pre.is_empty() and b.pre.is_empty() else 1 if a.pre.is_empty() else -1
	for i in mini(a.pre.size(), b.pre.size()):
		var left: String = a.pre[i]
		var right: String = b.pre[i]
		if left == right:
			continue
		if left.is_valid_int() and right.is_valid_int():
			return 1 if int(left) > int(right) else -1
		return -2
	return 0 if a.pre.size() == b.pre.size() else 1 if a.pre.size() > b.pre.size() else -1

static func newer(candidate: String, current: String) -> bool:
	return compare(candidate, current) == 1

static func supports_game(game_versions: Array, selected: String) -> bool:
	if game_versions.has(selected):
		return true
	var target := parse(selected)
	if target.is_empty() or target.core[0] != 1 or target.core[1] != 3 or selected != "1.3." + str(target.core[2]):
		return false
	for value: Variant in game_versions:
		if not value is String:
			continue
		var declared := parse(value)
		if declared.is_empty() or declared.core[0] != 1 or declared.core[1] != 3 or value != "1.3." + str(declared.core[2]):
			continue
		if declared.core[2] <= target.core[2]:
			return true
	return false
