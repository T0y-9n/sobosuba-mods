extends SceneTree

const Catalog = preload("../manager/catalog.gd")
const Source = preload("../manager/release_source.gd")
var powershell := ""

func _initialize() -> void:
	run.call_deferred()

func inspect(_operation: String, request: Dictionary) -> Dictionary:
	var output: Array = []
	var script: String = ProjectSettings.globalize_path("res://../tools/inspect_catalog_package.ps1")
	var arguments := PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive"])
	if OS.get_name() == "Windows":
		arguments.append_array(["-ExecutionPolicy", "Bypass"])
	arguments.append_array(["-File", script, "-Zip", str(request.zip)])
	if OS.execute(powershell, arguments, output, true, false) != 0 or output.is_empty():
		return {"ok":false, "error":"io_error"}
	var result: Variant = JSON.parse_string(str(output[0]).strip_edges())
	return result if result is Dictionary else {"ok":false, "error":"io_error"}

func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ", false) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 4:
		quit(2)
		return
	var catalog_path: String = arguments[0]
	var output_path: String = arguments[1]
	powershell = arguments[2]
	var baseline_path: String = arguments[3]
	var checking := baseline_path != "-"
	var catalog := Catalog.new()
	root.add_child(catalog)
	if await catalog.refresh(catalog_path) != OK:
		push_error("Invalid input catalog")
		quit(1)
		return
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	var reviewed_rows: Array = document.mods.duplicate(true)
	catalog.add_source_defaults(reviewed_rows)
	var previous_rows := {}
	if checking:
		if await catalog.refresh(baseline_path) != OK:
			push_error("Invalid baseline catalog")
			quit(1)
			return
		catalog.add_source_defaults(catalog.mods)
		for previous: Dictionary in catalog.mods:
			previous_rows[previous.id] = previous
	var errors: Array = []
	if checking:
		var submitted_rows := {}
		for submitted: Dictionary in document.mods:
			submitted_rows[submitted.id] = submitted
		for previous_id: String in previous_rows:
			if not submitted_rows.has(previous_id):
				errors.append({"id":previous_id, "variant":-1, "reason":"existing_entry_removed"})
			elif submitted_rows[previous_id].get("variants", []).size() < previous_rows[previous_id].get("variants", []).size():
				errors.append({"id":previous_id, "variant":-1, "reason":"existing_variant_removed"})
		if not errors.is_empty():
			write_json(output_path.path_join("report.json"), {"changes":[], "rejected":[], "errors":errors, "repositories":0, "input_sha256":FileAccess.get_sha256(catalog_path)})
			catalog.queue_free()
			await process_frame
			quit(1)
			return
	var source := Source.new()
	var repositories := {}
	var changes: Array = []
	var rejected: Array = []
	for row_index in document.mods.size():
		var row: Dictionary = document.mods[row_index]
		var reviewed: Dictionary = reviewed_rows[row_index]
		var choices: Array = [{"entry":row, "base":reviewed, "variant":-1}]
		for variant_index in row.get("variants", []).size():
			choices.append({"entry":row.variants[variant_index], "base":reviewed.variants[variant_index], "variant":variant_index})
		for choice: Dictionary in choices:
			var base: Dictionary = choice.base.duplicate(true)
			base.id = row.id
			base.erase("variants")
			var proposed: Dictionary = base.duplicate(true)
			if checking and previous_rows.has(row.id):
				var previous: Dictionary = previous_rows[row.id]
				if choice.variant >= 0:
					previous = previous.get("variants", [])[choice.variant] if choice.variant < previous.get("variants", []).size() else {}
				previous = previous.duplicate(true)
				previous.id = row.id
				previous.erase("variants")
				if previous == proposed:
					continue
				if previous.has("source"):
					base = previous
			if not base.has("source"):
				if checking:
					errors.append({"id":base.id, "variant":choice.variant, "reason":"source"})
				continue
			if not Source.valid_source(base.source) or not Source.valid_location(base, base.source) or base.get("game_versions", []).is_empty():
				errors.append({"id":base.id, "variant":choice.variant, "reason":"source"})
				continue
			var repository: String = base.source.github
			if not repositories.has(repository):
				var response: Dictionary = await catalog.request_bytes("https://api.github.com/repos/" + repository + "/releases?per_page=100", 8 * 1024 * 1024)
				var parsed: Variant = JSON.parse_string(response.body.get_string_from_utf8()) if response.error == OK else null
				repositories[repository] = parsed if parsed is Array else null
			if not repositories[repository] is Array:
				errors.append({"id":base.id, "variant":choice.variant, "reason":"unavailable"})
				continue
			var releases: Array = repositories[repository]
			var selection: Dictionary = base.duplicate(true)
			if checking:
				releases = releases.filter(func(release): return release is Dictionary and Source.version_from_tag(str(release.get("tag_name", "")), base.source) == proposed.version)
				selection.version = "0.0.0"
			var candidate: Dictionary = Source.select_release(selection, releases)
			if candidate.is_empty():
				if checking:
					errors.append({"id":base.id, "variant":choice.variant, "reason":"metadata"})
				continue
			if checking and (candidate.zip != proposed.zip or candidate.sha256 != proposed.get("sha256", "") or proposed.get("source") != base.source):
				errors.append({"id":base.id, "variant":choice.variant, "reason":"metadata"})
				continue
			var result: Dictionary = await source.verify(catalog, base, candidate, str(base.game_versions[0]), inspect)
			if not result.has("entry"):
				rejected.append({"id":base.id, "variant":choice.variant, "version":candidate.version, "sha256":candidate.sha256, "reason":result.get("failure", "metadata")})
				continue
			if checking and (proposed.get("game_versions") != result.entry.game_versions or proposed.get("game_credit") != result.entry.game_credit):
				errors.append({"id":base.id, "variant":choice.variant, "reason":"metadata"})
				continue
			var target: Dictionary = choice.entry
			var before := {}
			var after := {}
			for field in ["version", "zip", "sha256", "game_versions", "game_credit"]:
				before[field] = target.get(field)
				after[field] = result.entry[field]
				target[field] = result.entry[field]
			changes.append({"id":base.id, "variant":choice.variant, "before":before, "after":after})
	var report := {"changes":changes, "rejected":rejected, "errors":errors, "repositories":repositories.size(), "input_sha256":FileAccess.get_sha256(catalog_path)}
	var saved := write_json(output_path.path_join("report.json"), report)
	if not changes.is_empty() and errors.is_empty():
		saved = saved and write_json(output_path.path_join("catalog.json"), document)
	catalog.queue_free()
	await process_frame
	quit(0 if saved and errors.is_empty() and (not checking or rejected.is_empty()) else 1)
