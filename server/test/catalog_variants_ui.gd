extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PRIME_UI ", "OK " if value else "FAIL ", description)
func idle(app: Node) -> void:
	await process_frame
	while app.busy:
		await create_timer(0.03).timeout
func run() -> void:
	var qa := OS.get_environment("PRIME_QA")
	var actual_user := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	if not qa.is_absolute_path() or not actual_user.begins_with(qa.replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"):
		push_error("PRIME_QA and the application data directory must be isolated together")
		quit(2)
		return
	var settings = load("res://settings.gd").new()
	settings.game_folder = qa.path_join("game")
	settings.user_data = qa.path_join("user-data")
	settings.game_version = "1.3.11"
	settings.locale = "en"
	settings.manager_auto_update = false
	settings.catalog_url = qa.path_join("empty-catalog.json")
	check(settings.save() == OK, "isolated settings")
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await idle(app)
	await idle(app)
	app.update_timer.stop()
	check(await app.catalog.refresh(qa.path_join("catalog.json")) == OK, "variant catalog loads")
	check(app.mods.size() == 2, "real backend lists both independently installed families")
	var legacy: Dictionary = {}
	var modern: Dictionary = {}
	for mod: Dictionary in app.mods:
		if mod.layout == "game-autoload": legacy = mod
		else: modern = mod
	check(legacy.get("version") == "1.2.3-1.0.2" and modern.get("version") == "1.3.11-1.0.0", "both release versions retained")
	var removed: Dictionary = await app.invoke("uninstall", {"id":"prime_sobo", "layout":"user-data-styles"})
	check(removed.ok, "dedicated modern fixture is removed before testing first installation")
	await app.read_state()
	check(app.mods.size() == 1 and not FileAccess.file_exists(qa.path_join("user-data/prime_mod/prime_sobo.gd")), "only the legacy family actually exists before catalog installation")
	app.render_rows()
	app.select_mod("prime_sobo|catalog")
	check(app.selected_mod.get("version") == "1.3.11-1.0.0", "legacy installation does not hide the modern catalog release")
	check(app.detail_actions.get_child_count() == 1 and not app.detail_actions.get_child(0).disabled, "modern release remains installable alongside legacy")
	if app.selected_mod.get("version") == "1.3.11-1.0.0":
		await app.download_mod(app.selected_mod)
		check(app.pending_package.get("version") == "1.3.11-1.0.0" and app.pending_package.get("layout") == "user-data-styles", "catalog download opens the actual modern package installation plan")
		if not app.pending_package.is_empty():
			app.install_dialog.hide()
			await app.install_selected()
			check(app.notice_error.is_empty(), "normal installation path accepts the catalog release")
			check(FileAccess.file_exists(qa.path_join("game/mods/prime_sobo/prime_sobo.gd")) and FileAccess.file_exists(qa.path_join("user-data/prime_mod/prime_sobo.gd")), "catalog installation preserves both independent payloads")
	app.mods = [modern]
	app.store.game_version = "1.2.3"
	app.render_rows()
	app.select_mod("prime_sobo|catalog")
	check(app.selected_mod.get("version") == "1.2.3-1.0.2", "modern installation does not hide the legacy release")
	app.mods = [legacy,modern]
	app.store.game_version = "1.3.11"
	app.render_rows()
	var prime_rows: Array = app.rows.get_children().filter(func(row): return row is Button and str(row.get_meta("mod_key", "")).begins_with("prime_sobo|"))
	check(prime_rows.size() == 2, "both installed families remain separate without a duplicate catalog row")
	app.select_mod("prime_sobo|game-autoload")
	check(app.selected_mod.get("version") == "1.2.3-1.0.2", "legacy selection retains its own installed release")
	check(not app.catalog.has_update(legacy), "modern release is never an automatic legacy update")
	app.queue_free()
	await process_frame
	print("PRIME_UI_DONE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
