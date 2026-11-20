extends RefCounted
## Reads Valve's text KeyValues files (libraryfolders.vdf, appmanifest_*.acf, appworkshop_*.acf).
## Blocks become Dictionaries and values stay Strings. A missing or broken file gives an empty Dictionary.

static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path))

static func parse(text: String) -> Dictionary:
	var state := {"at": 0, "ok": true}
	var tokens := _tokens(text, state)
	if not state.ok:
		return {}
	var result := _block(tokens, state, true)
	return result if state.ok else {}

## Quoted strings become one-element Arrays so that a quoted brace is not taken for a block.
static func _tokens(text: String, state: Dictionary) -> Array:
	var tokens: Array = []
	var at := 0
	var length := text.length()
	while at < length:
		var character := text[at]
		if character == "\"":
			var value := PackedStringArray()
			var start := at + 1
			at = start
			while at < length and text[at] != "\"":
				if text[at] == "\\" and at + 1 < length:
					value.append(text.substr(start, at - start))
					at += 1
					value.append("\n" if text[at] == "n" else "\t" if text[at] == "t" else text[at])
					start = at + 1
				at += 1
			if at >= length:
				state.ok = false
				return tokens
			value.append(text.substr(start, at - start))
			tokens.append(["".join(value)])
			at += 1
		elif character == "{" or character == "}":
			tokens.append(character)
			at += 1
		elif character == "/" and at + 1 < length and text[at + 1] == "/":
			while at < length and text[at] != "\n":
				at += 1
		else:
			at += 1
	return tokens

static func _block(tokens: Array, state: Dictionary, top: bool) -> Dictionary:
	var node := {}
	while state.at < tokens.size():
		var key = tokens[state.at]
		state.at += 1
		if key is String:
			state.ok = key == "}" and not top
			return node
		if state.at >= tokens.size():
			state.ok = false
			return node
		var value = tokens[state.at]
		state.at += 1
		if value is String:
			if value != "{":
				state.ok = false
				return node
			node[key[0]] = _block(tokens, state, false)
			if not state.ok:
				return node
		else:
			node[key[0]] = value[0]
	state.ok = top
	return node
