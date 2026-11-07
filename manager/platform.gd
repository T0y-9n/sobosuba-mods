extends RefCounted

static func asset_platform() -> String:
	return "Linux-x86_64" if OS.get_name() == "Linux" else "Windows"

static func executable_name() -> String:
	return "SobosubaModManager.x86_64" if OS.get_name() == "Linux" else "SobosubaModManager.exe"

static func path_key(path: String) -> String:
	var normalized := path.replace("\\", "/")
	return normalized.to_lower() if OS.get_name() == "Windows" else normalized

static func powershell() -> String:
	if OS.get_name() == "Windows":
		return OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if OS.get_name() != "Linux":
		return ""
	var pin: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/linux.json"))
	if not pin is Dictionary or not pin.get("sha256") is String:
		return ""
	var folder := ProjectSettings.globalize_path("user://runtime/" + str(pin.sha256))
	var executable := folder.path_join("pwsh")
	if FileAccess.file_exists(executable) and FileAccess.file_exists(folder.path_join(".ready")):
		return executable
	var archive := "res://runtime/powershell-linux-x64.tar.gz"
	if not FileAccess.file_exists(archive) or FileAccess.get_sha256(archive) != pin.sha256:
		return ""
	var staging := folder + "." + Crypto.new().generate_random_bytes(8).hex_encode()
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return ""
	var temporary_archive := staging.path_join("runtime.tar.gz")
	if DirAccess.copy_absolute(archive, temporary_archive) != OK:
		return ""
	var output: Array = []
	if OS.execute("/usr/bin/tar", ["-xzf", temporary_archive, "-C", staging], output, true) != 0:
		return ""
	DirAccess.remove_absolute(temporary_archive)
	if FileAccess.set_unix_permissions(staging.path_join("pwsh"), 493) != OK:
		return ""
	var marker := FileAccess.open(staging.path_join(".ready"), FileAccess.WRITE)
	if marker == null:
		return ""
	marker.store_string(str(pin.sha256))
	marker.close()
	if DirAccess.rename_absolute(staging, folder) != OK:
		return ""
	return executable

static func shell_arguments(script: String, arguments: Array, hidden: bool = false) -> PackedStringArray:
	var result := PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive"])
	if OS.get_name() == "Windows":
		if hidden:
			result.append_array(["-WindowStyle", "Hidden"])
		result.append_array(["-ExecutionPolicy", "Bypass"])
	result.append_array(["-File", script])
	for argument in arguments:
		result.append(str(argument))
	return result
