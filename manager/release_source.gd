extends RefCounted

const Versions = preload("versions.gd")
const CREDIT_TEXT := "sobosuba by keepee"
const CREDIT_URL := "https://store.steampowered.com/app/1946560/sobosuba"
const CACHE_ROOT := "user://release-cache"
var statuses: Dictionary = {}

static func valid_source(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field in ["github", "asset"]:
		if not value.get(field) is String:
			return false
	var repository := RegEx.new()
	repository.compile("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+\\z")
	if repository.search(value.github) == null or value.github.get_slice("/", 1) in [".", ".."]:
		return false
	var prefix: Variant = value.get("tag_prefix", "")
	var allowed := RegEx.new()
	allowed.compile("^[A-Za-z0-9_.-]*\\z")
	if not prefix is String or allowed.search(prefix) == null:
		return false
	var asset: String = value.asset
	if asset.count("{version}") != 1 or not asset.ends_with(".zip") or allowed.search(asset.replace("{version}", "")) == null:
		return false
	return not value.has("prerelease") or value.prerelease is bool

static func source_identity(source: Dictionary) -> Dictionary:
	return {"github":source.github, "tag_prefix":source.get("tag_prefix", ""), "asset":source.asset, "prerelease":source.get("prerelease", false)}

static func version_from_tag(tag: String, source: Dictionary) -> String:
	var prefix: String = source.get("tag_prefix", "")
	if not tag.begins_with(prefix):
		return ""
	var version := tag.trim_prefix("v")
	if Versions.parse(version).is_empty():
		var leading := RegEx.new()
		leading.compile("^[^0-9]+")
		var found := leading.search(prefix)
		if found == null:
			return ""
		version = tag.trim_prefix(found.get_string())
	return version if not Versions.parse(version).is_empty() and version.length() <= 80 else ""

static func valid_location(entry: Dictionary, source: Dictionary) -> bool:
	if not entry.get("zip") is String or not entry.get("version") is String:
		return false
	var base := "https://github.com/" + str(source.github) + "/releases/download/"
	if not entry.zip.begins_with(base):
		return false
	var parts: PackedStringArray = entry.zip.trim_prefix(base).split("/")
	return parts.size() == 2 and version_from_tag(parts[0], source) == entry.version and parts[1] == str(source.asset).replace("{version}", entry.version)

static func key(entry: Dictionary) -> String:
	return str(entry.id) + "|" + JSON.stringify(source_identity(entry.source))

static func select_release(entry: Dictionary, releases: Array) -> Dictionary:
	var source: Dictionary = entry.source
	var best: Dictionary = {}
	for release in releases:
		if not release is Dictionary or not release.get("draft") is bool or release.draft or not release.get("prerelease") is bool or not release.get("tag_name") is String:
			continue
		if release.prerelease and not source.get("prerelease", false):
			continue
		var version := version_from_tag(release.tag_name, source)
		if version.is_empty() or not Versions.newer(version, entry.version) or (not best.is_empty() and not Versions.newer(version, best.version)):
			continue
		var name: String = str(source.asset).replace("{version}", version)
		var url := "https://github.com/" + str(source.github) + "/releases/download/" + str(release.tag_name) + "/" + name
		best = {"version":version, "tag":release.tag_name, "zip":url, "sha256":"", "failure":"metadata"}
		if not release.get("assets") is Array:
			continue
		for asset in release.assets:
			if not asset is Dictionary or asset.get("name") != name or asset.get("browser_download_url") != url:
				continue
			if not asset.get("size") is float and not asset.get("size") is int:
				continue
			if asset.size <= 0 or asset.size > 32 * 1024 * 1024:
				continue
			var digest: Variant = asset.get("digest")
			var hash_pattern := RegEx.new()
			hash_pattern.compile("^sha256:[a-fA-F0-9]{64}\\z")
			if not digest is String or hash_pattern.search(digest) == null:
				best.failure = "sha256"
				continue
			best.sha256 = digest.trim_prefix("sha256:").to_lower()
			best.failure = ""
	return best

static func package_credit(path: String, mod_id: String) -> bool:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return false
	var metadata_path := "mod-package.json" if archive.file_exists("mod-package.json") else "mods/" + mod_id + "/mod.json"
	var metadata: Variant = JSON.parse_string(archive.read_file(metadata_path).get_string_from_utf8())
	archive.close()
	if not metadata is Dictionary or not metadata.get("game_credit") is Dictionary:
		return false
	return metadata.game_credit.get("text") == CREDIT_TEXT and metadata.game_credit.get("store_url") == CREDIT_URL

func readme_credit(catalog: Node, source: Dictionary, tag: String) -> bool:
	var response: Dictionary = await catalog.request_bytes("https://api.github.com/repos/" + str(source.github) + "/readme?ref=" + tag.uri_encode(), 1024 * 1024)
	if response.error != OK:
		return false
	var data: Variant = JSON.parse_string(response.body.get_string_from_utf8())
	if not data is Dictionary or data.get("encoding") != "base64" or not data.get("content") is String:
		return false
	var text := Marshalls.base64_to_utf8(data.content)
	return text.to_lower().contains("sobosuba") and text.to_lower().contains("keepee") and text.contains(CREDIT_URL)

func verify(catalog: Node, base: Dictionary, candidate: Dictionary, game: String, inspect: Callable) -> Dictionary:
	if not str(candidate.get("failure", "")).is_empty():
		return {"failure":candidate.failure}
	if not catalog.valid_hash(str(candidate.get("sha256", ""))) or not valid_location(candidate, base.source):
		return {"failure":"metadata"}
	var downloaded: Dictionary = await catalog.download_verified(candidate, candidate.sha256)
	if downloaded.error != OK:
		return {"failure":"sha256" if str(downloaded.get("failure", "")).begins_with("sha256") else "download"}
	var path: String = downloaded.zip
	var result: Dictionary = await inspect.call("inspect", {"zip":path, "sha256":candidate.sha256})
	if not result.get("ok", false):
		return {"failure":"game_credit" if result.get("error") == "credit_required" else "metadata"}
	var metadata: Variant = result.get("data")
	if not metadata is Dictionary or metadata.get("id") != base.id or metadata.get("version") != candidate.version or not metadata.get("game_versions") is Array:
		return {"failure":"metadata"}
	if not Versions.supports_game(metadata.game_versions, game) or catalog.entry_layout(metadata) != catalog.entry_layout(base):
		return {"failure":"metadata"}
	if not package_credit(path, base.id):
		return {"failure":"game_credit"}
	if not await readme_credit(catalog, base.source, candidate.tag):
		return {"failure":"readme"}
	var entry := base.duplicate(true)
	for field in ["version", "zip", "sha256"]:
		entry[field] = candidate[field]
	entry.game_versions = metadata.game_versions.duplicate()
	entry.game_credit = {"text":CREDIT_TEXT, "store_url":CREDIT_URL}
	return {"entry":entry}

func cache_path(base: Dictionary) -> String:
	return ProjectSettings.globalize_path(CACHE_ROOT.path_join(key(base).sha256_text() + ".json"))

func save_cache(base: Dictionary, candidate: Dictionary, checked_at: int, reason: String) -> bool:
	var path := cache_path(base)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var record := {"schema":1, "id":base.id, "source":source_identity(base.source), "candidate":candidate, "checked_at":checked_at, "reason":reason, "readme_verified":reason.is_empty()}
	record.integrity = JSON.stringify(record).sha256_text()
	file.store_string(JSON.stringify(record))
	file.flush()
	var error := file.get_error()
	file.close()
	var saved := error == OK and DirAccess.rename_absolute(temporary, path) == OK
	if not saved:
		DirAccess.remove_absolute(temporary)
	return saved

func load_cache(catalog: Node, base: Dictionary) -> Dictionary:
	var file := FileAccess.open(cache_path(base), FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > 65536:
		file.close()
		return {"failure":"cache_invalid"}
	var record: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not record is Dictionary or record.get("schema") != 1 or record.get("id") != base.id or record.get("source") != source_identity(base.source) or not record.get("candidate") is Dictionary:
		return {"failure":"cache_invalid"}
	if (not record.get("checked_at") is float and not record.get("checked_at") is int) or float(record.checked_at) != floorf(float(record.checked_at)):
		return {"failure":"cache_invalid"}
	# JSON numbers become floats on read; keep the hashed representation stable.
	record.schema = 1
	record.checked_at = int(record.checked_at)
	var integrity: Variant = record.get("integrity")
	record.erase("integrity")
	if not integrity is String or integrity != JSON.stringify(record).sha256_text() or record.get("reason") not in ["", "game_credit", "metadata", "sha256", "download", "readme"]:
		return {"failure":"cache_invalid"}
	if not record.get("readme_verified") is bool or (record.reason == "" and not record.readme_verified):
		return {"failure":"cache_invalid"}
	if record.checked_at <= 0 or record.checked_at > Time.get_unix_time_from_system() + 300:
		return {"failure":"cache_invalid"}
	var candidate: Dictionary = record.candidate
	if not candidate.get("version") is String or Versions.parse(candidate.version).is_empty() or not valid_location(candidate, base.source) or candidate.get("tag") != str(candidate.get("zip", "")).trim_prefix("https://github.com/" + str(base.source.github) + "/releases/download/").get_slice("/", 0):
		return {"failure":"cache_invalid"}
	if not catalog.valid_hash(str(candidate.get("sha256", ""))) and not (str(candidate.get("sha256", "")).is_empty() and record.reason in ["sha256", "metadata"]):
		return {"failure":"cache_invalid"}
	return {"candidate":candidate, "checked_at":int(record.checked_at), "reason":record.reason}

func status(base: Dictionary, candidate: Dictionary, reason: String, cached: Dictionary = {}) -> Dictionary:
	var cached_reason: String = cached.get("reason", "")
	return {"error":"author_release_unavailable" if reason in ["unavailable", "cache_invalid"] else "author_release_rejected", "version":candidate.get("version", base.version), "reason":cached_reason if reason == "unavailable" and not cached_reason.is_empty() else reason, "checked_at":cached.get("checked_at", int(Time.get_unix_time_from_system())), "cached":cached.has("candidate"), "cached_version":cached.get("candidate", {}).get("version", ""), "cached_reason":cached_reason}

func refresh(catalog: Node, entries: Array, game: String, inspect: Callable, trusted: bool) -> Dictionary:
	statuses = {}
	var output := entries.duplicate(true)
	var repositories := {}
	var updated := 0
	for index in entries.size():
		var row: Dictionary = entries[index]
		var choices: Array = [{"entry":row, "variant":-1}]
		for variant_index in row.get("variants", []).size():
			var variant: Dictionary = row.variants[variant_index].duplicate(true)
			variant.id = row.id
			choices.append({"entry":variant, "variant":variant_index})
		for choice: Dictionary in choices:
			var base: Dictionary = choice.entry.duplicate(true)
			base.erase("variants")
			if not base.has("source") or not Versions.supports_game(base.get("game_versions", []), game):
				continue
			var status_key: String = str(base.id) + "|" + str(catalog.entry_layout(base))
			if not trusted or not valid_source(base.source) or not valid_location(base, base.source) or not inspect.is_valid():
				statuses[status_key] = status(base, {}, "source")
				continue
			var repository: String = base.source.github
			if not repositories.has(repository):
				var response: Dictionary = await catalog.request_bytes("https://api.github.com/repos/" + repository + "/releases?per_page=100", 8 * 1024 * 1024)
				var parsed: Variant = JSON.parse_string(response.body.get_string_from_utf8()) if response.error == OK else null
				repositories[repository] = parsed if parsed is Array else null
			var releases: Variant = repositories[repository]
			var candidate: Dictionary = select_release(base, releases) if releases is Array else {}
			var checked_at := int(Time.get_unix_time_from_system())
			var result := await verify(catalog, base, candidate, game, inspect) if not candidate.is_empty() else {}
			var reason := "unavailable" if not releases is Array else str(result.get("failure", ""))
			var cache_error: bool = not candidate.is_empty() and not save_cache(base, candidate, checked_at, reason)
			if not reason.is_empty():
				var previous := load_cache(catalog, base) if not releases is Array or reason == "cache_invalid" else {}
				statuses[status_key] = status(base, candidate, "cache_invalid" if previous.get("failure") == "cache_invalid" else reason, previous)
			elif result.has("entry"):
				statuses[status_key] = {"error":"", "version":candidate.version, "reason":"", "checked_at":checked_at, "cached":false, "cached_version":""}
			if cache_error:
				statuses[status_key].cache_error = true
			if result.has("entry"):
				var accepted: Dictionary = result.entry
				if choice.variant == -1:
					accepted["variants"] = output[index].get("variants", []).duplicate(true)
					if accepted.variants.is_empty():
						accepted.erase("variants")
					output[index] = accepted
				else:
					accepted.erase("id")
					output[index].variants[choice.variant] = accepted
				updated += 1
	return {"mods":output, "updated":updated, "repositories":repositories.size()}
