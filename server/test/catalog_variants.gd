extends SceneTree

var checks := 0
var failures := 0
var catalog: Variant
var fixture_path := ""

func check(condition: bool, message: String) -> void:
	checks += 1
	print("CATALOG_VARIANT_CHECK ", "OK " if condition else "FAIL ", message)
	if not condition:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func load_fixture(entries: Array) -> int:
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify({"mods":entries}))
	file.close()
	return await catalog.refresh(fixture_path)

func base_entry() -> Dictionary:
	return {"id":"prime_sobo", "name":"Prime sobos", "summary":"Legacy prime release", "version":"1.2.3-1.0.2", "game_versions":["1.2.3"], "zip":"https://example.invalid/prime-123.zip", "sha256":"a".repeat(64)}

func modern_variant() -> Dictionary:
	return {"version":"1.3.11-0.5.0", "game_versions":["1.3.11"], "zip":"https://example.invalid/prime-1311.zip", "sha256":"b".repeat(64)}

func variant_catalog() -> Dictionary:
	var entry := base_entry()
	entry.variants = [modern_variant()]
	return entry

func one_prime(entries: Array) -> Dictionary:
	var found: Array = entries.filter(func(entry): return entry.get("id") == "prime_sobo")
	return found[0] if found.size() == 1 else {}

func finish() -> void:
	catalog.free()
	print("CATALOG_VARIANT_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		check(false, "supply the manager source and isolated fixture folder")
		quit(1)
		return
	fixture_path = args[1].path_join("catalog-variant-fixture.json")
	var script: Script = load(args[0].path_join("catalog.gd"))
	if script == null:
		check(false, "catalog script loads")
		quit(1)
		return
	catalog = script.new()
	root.add_child(catalog)
	var legacy := base_entry()
	legacy.erase("sha256")
	legacy.erase("game_versions")
	check(await load_fixture([legacy]) == OK, "the earlier catalog without optional SHA or game versions remains readable")
	check(catalog.find("prime_sobo") == legacy, "find without game selection preserves the earlier top-level entry")
	check(await load_fixture([variant_catalog()]) == OK, "a catalog with an optional variant remains readable")
	check(catalog.mods.size() == 1 and catalog.mods[0].version == "1.2.3-1.0.2", "the public top-level list retains the legacy release")
	check(catalog.has_method("for_game") and catalog.has_method("entry_layout"), "catalog resolves game variants and exposes their install family")
	if not catalog.has_method("for_game") or not catalog.has_method("entry_layout"):
		finish()
		return
	check(await load_fixture([legacy]) == OK, "the original undeclared catalog row loads for dependency lookup")
	check(catalog.find("prime_sobo", "1.2.3", legacy.version).get("version") == legacy.version, "exact dependency lookup preserves an undeclared original row for package inspection")
	check(catalog.find("prime_sobo", "1.3.11").is_empty(), "undeclared original rows are not offered as known-compatible manual releases")
	check(await load_fixture([variant_catalog()]) == OK, "restore variant group after the original dependency case")
	var old: Dictionary = catalog.find("prime_sobo", "1.2.3")
	var modern: Dictionary = catalog.find("prime_sobo", "1.3.11")
	check(old.get("version") == "1.2.3-1.0.2" and old.get("sha256") == "a".repeat(64), "game 1.2.3 resolves its own release and SHA")
	check(modern.get("version") == "1.3.11-0.5.0" and modern.get("sha256") == "b".repeat(64), "game 1.3.11 resolves its own release and SHA")
	check(modern.get("id") == "prime_sobo" and modern.get("name") == "Prime sobos" and modern.get("summary") == "Legacy prime release", "variants inherit the fixed ID and unchanged descriptive fields")
	check(modern.get("game_versions") == ["1.3.11"] and not modern.has("variants"), "a resolved release keeps only its own declared game versions")
	check(catalog.find("prime_sobo").version == "1.2.3-1.0.2", "the original find call still returns the original release")
	check(one_prime(catalog.for_game("1.2.3")).get("version") == old.version, "the old game displays one old-game candidate")
	check(one_prime(catalog.for_game("1.3.11")).get("version") == modern.version, "the new game displays one new-game candidate")
	check(catalog.find("prime_sobo", "1.3.10").is_empty(), "an unsupported newer release is unavailable to an older game")
	check(one_prime(catalog.for_game("1.3.10")).get("version") == old.version, "display fallback preserves the original locked legacy row")
	check(catalog.find("prime_sobo", "1.3.12").get("version") == modern.version, "the existing forward compatibility within game 1.3 remains available")
	check(catalog.find("prime_sobo", "1.3.11", modern.version).get("sha256") == modern.sha256, "dependency selection resolves an exact mod version in the selected game")
	check(catalog.find("prime_sobo", "1.3.11", old.version).is_empty(), "an exact dependency version cannot select another game family")
	check(catalog.find("missing", "1.3.11").is_empty(), "an absent mod remains unavailable")
	check(catalog.entry_layout(old) == "game-autoload" and catalog.entry_layout(modern) == "user-data-styles", "resolved releases map to the existing backend layout families")
	check(catalog.entry_layout({}) == "" and catalog.entry_layout({"game_versions":["2.0.0"]}) == "", "unknown game families have no inferred install layout")
	check(catalog.entry_layout({"game_versions":["1.2.3", "1.3.11"]}) == "", "mixed game families have no inferred install layout")
	var old_installed := {"id":"prime_sobo", "version":"1.2.3-1.0.1", "layout":"game-autoload", "game_versions":["1.2.3"]}
	var modern_installed := {"id":"prime_sobo", "version":"1.3.11-0.4.0", "layout":"user-data-styles", "game_versions":["1.3.11"]}
	check(catalog.has_update(old_installed, "1.2.3"), "the old-game installed release can update within its own family")
	check(catalog.has_update(modern_installed, "1.3.11"), "the new-game installed release can update within its own family")
	check(not catalog.has_update(old_installed, "1.3.11") and not catalog.has_update(modern_installed, "1.2.3"), "update lookup cannot cross installation families")
	check(catalog.has_update(old_installed), "the earlier update call remains usable for the original release")
	check(not catalog.has_update({"id":"prime_sobo", "version":modern.version, "layout":"user-data-styles", "game_versions":["1.3.11"]}, "1.3.11"), "the installed current release has no update")
	# Existing standalone rows continue to resolve alongside a variant group.
	var standalone := {"id":"sobosandbox", "name":"SoboSandbox", "summary":"Sandbox", "version":"1.3.0", "game_versions":["1.3.11", "1.3.10", "1.3.9"], "zip":"https://example.invalid/sandbox.zip", "sha256":"c".repeat(64)}
	check(await load_fixture([variant_catalog(), standalone]) == OK and catalog.for_game("1.3.11").size() == 2, "ordinary catalog rows remain alongside the resolved variant")
	# Each variant supplies its own indivisible download identity.
	for field in ["version", "game_versions", "zip", "sha256"]:
		var invalid := variant_catalog()
		invalid.variants[0].erase(field)
		check(await load_fixture([invalid]) == ERR_INVALID_DATA and catalog.mods.is_empty(), "reject a variant missing " + field + " without retaining stale rows")
	var invalid := variant_catalog()
	invalid.variants = "not-an-array"
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject a malformed variant container")
	invalid = variant_catalog()
	invalid.variants[0].id = "other_mod"
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject a variant that changes the parent ID")
	invalid = variant_catalog()
	invalid.variants[0].game_versions = []
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject a variant with no supported game versions")
	invalid = variant_catalog()
	invalid.variants[0].game_versions = ["1.2.3", "1.3.11"]
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject a variant mixing incompatible installation families")
	invalid = variant_catalog()
	invalid.variants[0].zip = "http://example.invalid/prime.zip"
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject a variant with an insecure download URL")
	invalid = variant_catalog()
	invalid.variants[0].sha256 = "b".repeat(63)
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject a variant with an invalid SHA")
	invalid = variant_catalog()
	invalid.variants[0].variants = [modern_variant()]
	check(await load_fixture([invalid]) == ERR_INVALID_DATA, "reject nested variant groups")
	check(await load_fixture([base_entry(), base_entry()]) == ERR_INVALID_DATA, "top-level duplicate IDs remain invalid for earlier readers")
	# Equal-priority choices are rejected instead of using array order.
	var overlapping := variant_catalog()
	var other := modern_variant()
	other.version = "1.3.11-0.6.0"
	overlapping.variants.append(other)
	var overlap_status: int = await load_fixture([overlapping])
	check(overlap_status == ERR_INVALID_DATA or catalog.find("prime_sobo", "1.3.11").is_empty(), "ambiguous explicit game variants never select the first row")
	if overlap_status == OK:
		check(one_prime(catalog.for_game("1.3.11")).is_empty(), "ambiguous variants are excluded from selectable display candidates")
	var fallback_overlap := variant_catalog()
	other = modern_variant()
	other.version = "1.3.10-0.4.0"
	other.game_versions = ["1.3.10"]
	fallback_overlap.variants.append(other)
	var fallback_status: int = await load_fixture([fallback_overlap])
	check(fallback_status == ERR_INVALID_DATA or catalog.find("prime_sobo", "1.3.12").is_empty(), "ambiguous compatibility fallback never selects the first row")
	if fallback_status == OK:
		check(catalog.find("prime_sobo", "1.3.11").get("version") == modern.version, "an explicit declared game match takes precedence over compatible fallback")
		check(catalog.find("prime_sobo", "1.3.11", other.version).get("version") == other.version, "an exact dependency version is filtered before game-match preference")
		check(one_prime(catalog.for_game("1.3.12")).is_empty(), "ambiguous fallback is excluded from selectable display candidates")
	finish()
