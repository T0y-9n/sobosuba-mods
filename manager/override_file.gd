extends RefCounted

func section_name(line: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^\\s*\\[([^\\]]+)\\]\\s*(?:[;#].*)?$")
	var found := pattern.search(line)
	return found.get_string(1) if found != null else ""

func entry(line: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.parse("[autoload]\n" + line) != OK or not config.has_section("autoload"):
		return {}
	var keys := config.get_section_keys("autoload")
	if keys.size() != 1:
		return {}
	var value: Variant = config.get_value("autoload", keys[0])
	if not value is String:
		return {}
	return {"key": keys[0], "value": value}

func points_to(value: String, folder: String) -> bool:
	if not value.begins_with("*"):
		return false
	var path := value.substr(1).replace("\\", "/").simplify_path()
	var target := folder.replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	if OS.get_name() == "Windows":
		path = path.to_lower()
		target = target.to_lower()
	return path.begins_with(target)

func enabled(text: String, game: String, metadata: Dictionary) -> bool:
	var in_autoload := false
	var expected: String = game.path_join("mods").path_join(metadata.id).path_join(metadata.entry)
	for line in text.split("\n"):
		var section := section_name(line)
		if not section.is_empty():
			in_autoload = section == "autoload"
		elif in_autoload:
			var item := entry(line)
			if item.get("key") == metadata.autoload:
				var value: String = item.get("value", "")
				if value.replace("\\", "/").to_lower() == ("*" + expected).replace("\\", "/").to_lower():
					return true
	return false

func changed(text: String, game: String, metadata: Dictionary, turn_on: bool) -> String:
	var newline := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.split("\n")
	var output := PackedStringArray()
	var in_autoload := false
	var insertion := -1
	var mod_folder: String = game.path_join("mods").path_join(metadata.id)
	for index in range(lines.size()):
		var line := lines[index]
		var section := section_name(line)
		if not section.is_empty():
			if in_autoload and insertion < 0:
				insertion = output.size()
			in_autoload = section == "autoload"
		elif in_autoload:
			var item := entry(line)
			if not item.is_empty():
				if points_to(item.value, mod_folder):
					continue
		if in_autoload and index == lines.size() - 1 and insertion < 0:
			insertion = output.size() if line.is_empty() else output.size() + 1
		output.append(line)
	if not turn_on:
		return "\n".join(output)
	var path: String = mod_folder.path_join(metadata.entry).replace("\\", "/")
	var autoload_line: String = metadata.autoload + "=" + var_to_str("*" + path)
	if insertion < 0:
		var content := "\n".join(output)
		if not content.is_empty() and not content.ends_with("\n"):
			content += newline
		return content + "[autoload]" + newline + autoload_line + newline
	if insertion > 0 and not output[insertion - 1].ends_with("\r") and newline == "\r\n":
		output[insertion - 1] += "\r"
	output.insert(insertion, autoload_line + ("\r" if newline == "\r\n" else ""))
	return "\n".join(output)
