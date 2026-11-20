extends RefCounted
## Provides the hub's Japanese text with an English fallback for missing keys.

static var _locales: Dictionary = {}

static func load_words(locale: String) -> Dictionary:
	if _locales.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string("res://hub/locales.json")) == OK and json.data is Dictionary:
			_locales = json.data
	var words: Dictionary = _locales.get("en", {}).duplicate()
	if locale == "ja":
		words.merge(_locales.get("ja", {}), true)
	return words

static func text(words: Dictionary, key: String) -> String:
	if words.get(key) is String:
		return words[key]
	return str(load_words("en").get(key, key))
