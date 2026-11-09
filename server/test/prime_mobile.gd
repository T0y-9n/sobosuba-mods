extends Node
## Runs inside the real game with isolated user data and score sending disabled.
var mod: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PRIME_MOBILE_CHECK ", "OK " if ok else "FAIL ", label)

func frames(count: int = 20) -> void:
	for index: int in count:
		await get_tree().process_frame

func _ready() -> void:
	run.call_deferred()

func inside(control: Control, bounds: Rect2) -> bool:
	return bounds.grow(1.0).encloses(mod.guide_screen_box(control))

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(OS.get_environment("SOBO_SHOTS").path_join(label + ".png")) == OK, "rendered " + label)

## Exercise the native mobile settings scene on PC without claiming a mobile platform run.
func mobile_settings_geometry() -> void:
	get_window().size = Vector2i(375, 667)
	await get_tree().create_timer(0.7).timeout
	var original_parent: Node = mod.prime_toggle.get_parent()
	var original_index: int = mod.prime_toggle.get_index()
	var model: SoboMenuButtonBool = Menu._0.settings_mobile_screen.show_instructions_control
	mod.prime_toggle.reparent(model.get_parent(), false)
	mod.send_toggle.reparent(model.get_parent(), false)
	mod.screenshot_toggle.reparent(model.get_parent(), false)
	model.get_parent().move_child(mod.prime_toggle, model.get_index() + 1)
	model.get_parent().move_child(mod.send_toggle, model.get_index() + 2)
	model.get_parent().move_child(mod.screenshot_toggle, model.get_index() + 3)
	mod.compact_mobile_settings()
	var preview: int = MobileManager.phone_preview_index
	MobileManager.phone_preview_index = 0
	Ui._0.fit_main_hbox_to_usable_rect()
	var panel_visibility: Array[bool] = []
	for panel: SidePanel in Ui._0.side_panels:
		panel_visibility.append(panel.visible)
		panel.visible = panel.for_mobile
	Menu._0.open_with_screen(Menu._0.settings_mobile_screen)
	await get_tree().create_timer(0.7).timeout
	check(not mod.guide_toggle.visible && not mod.level_label.visible, "run overlays hide while the native mobile settings fixture is open")
	var bounds: Rect2 = Ui._0.get_final_transform().affine_inverse() * MobileManager.get_usable_rect()
	var list: Control = mod.prime_toggle.get_parent()
	print("PRIME_MOBILE_SETTINGS rect=", mod.guide_screen_box(list), " bounds=", bounds, " minimum=", list.get_combined_minimum_size())
	check(inside(list, bounds), "native mobile settings list fits the portrait safe-area fixture on PC")
	check(list.scale == Vector2.ONE, "native mobile settings keep the original control scale")
	check(Ui._0.get_button_under_pointer(mod.guide_screen_box(mod.prime_toggle).get_center()) == mod.prime_toggle,
		"prime row is the native pointer target in the mobile settings fixture")
	check(Ui._0.get_button_under_pointer(mod.guide_screen_box(mod.send_toggle).get_center()) == mod.send_toggle,
		"send row is the native pointer target in the mobile settings fixture")
	check(Ui._0.get_button_under_pointer(mod.guide_screen_box(mod.screenshot_toggle).get_center()) == mod.screenshot_toggle,
		"screenshot row is the native pointer target in mobile settings")
	mod.screenshot_toggle.release_press.emit()
	check(mod.prime_settings.save_screenshots && mod.screenshot_toggle.bool_circles.visible, "screenshot switch turns saving on")
	mod.screenshot_toggle.release_press.emit()
	check(not mod.prime_settings.save_screenshots && not mod.screenshot_toggle.bool_circles.visible, "screenshot switch turns saving off")
	await shot("mobile-settings-fixture")
	Menu._0.try_close()
	mod.prime_toggle.reparent(original_parent, false)
	mod.send_toggle.reparent(original_parent, false)
	mod.screenshot_toggle.reparent(original_parent, false)
	original_parent.move_child(mod.prime_toggle, original_index)
	original_parent.move_child(mod.send_toggle, original_index + 1)
	original_parent.move_child(mod.screenshot_toggle, original_index + 2)
	MobileManager.phone_preview_index = preview
	Ui._0.main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for index: int in Ui._0.side_panels.size():
		Ui._0.side_panels[index].visible = panel_visibility[index]
	await frames()

func run() -> void:
	for index: int in 600:
		for child: Node in get_tree().root.get_children():
			if child.has_method("create_prime"):
				mod = child
		if mod != null && mod.enabled && mod.scores_screen != null:
			break
		await frames(1)
	print("PRIME_MOBILE_PLATFORM mobile=", OS.has_feature("mobile"), " renderer=", DisplayServer.get_name())
	check(str(ProjectSettings.get_setting("application/config/version")) == OS.get_environment("SOBO_GAME_VERSION"), "expected native game version")
	check(mod != null && mod.scores_screen != null, "prime mod loaded")
	if mod == null || mod.scores_screen == null:
		finish()
		return
	check(not mod.online.enabled && not mod.online.send_scores, "network score sending disabled")
	var desktop_settings: MenuScreen = Menu._0.get("game_settings_screen" if OS.get_environment("SOBO_GAME_VERSION") == "1.3.11" else "game_screen")
	check(mod.prime_toggle != null && (Menu._0.settings_mobile_screen if OS.has_feature("mobile") else desktop_settings).is_ancestor_of(mod.prime_toggle), "prime switch belongs to the platform settings screen")
	check(mod.send_toggle != null && (Menu._0.settings_mobile_screen if OS.has_feature("mobile") else desktop_settings).is_ancestor_of(mod.send_toggle), "send switch belongs to the platform settings screen")
	check(mod.screenshot_toggle != null && mod.screenshot_toggle.get_parent() == mod.send_toggle.get_parent() && mod.screenshot_toggle.get_index() == mod.send_toggle.get_index() + 1, "screenshot switch sits directly under send scores")
	check(not mod.prime_settings.save_screenshots, "screenshot saving starts off")
	mod.scores.save_path = mod.scores.SELFTEST_SAVE_PATH
	var handle_before: int = mod.scores.last_screenshot_handle
	await mod.scores.on_game_over()
	await get_tree().create_timer(1.0, true).timeout
	check(mod.scores.last_screenshot_handle == handle_before, "screenshots off leaves the Steam handle unchanged")
	if OS.has_feature("mobile"):
		check(not mod.scores_screen.source_btn.visible && not mod.scores_screen.friends_only_btn.visible, "mobile ranking hides the native desktop source controls")
	if mod.prime_toggle != null:
		mod.prime_toggle.release_press.emit()
		check(not mod.prime_settings.enabled, "prime switch turns the mode off")
		mod.prime_toggle.release_press.emit()
		check(mod.prime_settings.enabled, "prime switch turns the mode on")
	SettingsManager.settings.show_instructions = true
	PlayerInput.set_input_device(PlayerInput.InputDevice.TOUCH)
	if mod.has_method("start_default_run"):
		await mod.start_default_run()
	else:
		await GameModeManager.start_game_mode(GameModeManager.default_mode_path, false)
	Menu._0.try_close()
	await frames(60)
	for resolution: Vector2i in [Vector2i(375, 667), Vector2i(393, 852), Vector2i(360, 780)]:
		get_window().size = resolution
		await get_tree().create_timer(0.7).timeout
		await frames(2)
		var safe: Rect2 = get_viewport().get_visible_rect()
		if OS.has_feature("mobile"):
			safe = safe.intersection(MobileManager.get_usable_rect())
		var bounds: Rect2 = Ui._0.get_final_transform().affine_inverse() * safe
		print("PRIME_MOBILE_GEOMETRY ", resolution, " viewport=", get_viewport().get_visible_rect(), " area=", Ui._0.ui_play_area.get_global_rect())
		check(mod.level_label != null && mod.level_label.is_visible_in_tree(), "level is visible at " + str(resolution))
		if mod.level_label != null:
			print("PRIME_MOBILE_LEVEL parent=", mod.level_label.get_parent().name, " parent_size=", (mod.level_label.get_parent() as Control).size, " position=", mod.level_label.position, " parent_transform=", (mod.level_label.get_parent() as Control).get_global_transform_with_canvas(), " rect=", mod.guide_screen_box(mod.level_label), " bounds=", bounds)
			check(inside(mod.level_label, bounds), "level fits the native usable area at " + str(resolution))
		check(mod.guide_toggle != null && mod.guide_toggle.is_visible_in_tree(), "guide switch is visible at " + str(resolution))
		if mod.guide_toggle != null && mod.guide_toggle.is_visible_in_tree():
			check(inside(mod.guide_toggle, bounds) && inside(mod.guide_label, bounds), "guide and description fit the usable area at " + str(resolution))
		await shot("portrait-%dx%d" % [resolution.x, resolution.y])
	var locale: String = TranslationServer.get_locale()
	for language: String in ["de", "ja", "en"]:
		TranslationServer.set_locale(language)
		await frames(3)
		var bounds: Rect2 = Ui._0.get_final_transform().affine_inverse() * get_viewport().get_visible_rect()
		check(mod.guide_label.size.y <= mod.guide_label.get_combined_minimum_size().y + 1.0,
			"guide height shrinks to the current translation " + language)
		check(inside(mod.guide_toggle, bounds) && inside(mod.guide_label, bounds),
			"guide fits after switching language to " + language)
	TranslationServer.set_locale(locale)
	Menu._0.open_with_screen(Menu._0.settings_mobile_screen if OS.has_feature("mobile") else desktop_settings)
	await frames()
	mod.refresh_level_label()
	check(not mod.guide_toggle.visible && not mod.level_label.visible, "run overlays hide while settings pause the game")
	await shot("settings")
	await mobile_settings_geometry()
	Menu._0.open_with_screen(mod.scores_screen)
	await frames()
	check(not mod.guide_toggle.visible && not mod.level_label.visible, "run overlays stay hidden on scores")
	await shot("scores")
	Menu._0.try_close()
	if MobileManager.has_method("set_horizontal"):
		MobileManager.set_horizontal(true)
		get_window().size = Vector2i(1280, 900)
		await get_tree().create_timer(0.7).timeout
		await frames(2)
		check(mod.level_label != null && mod.level_label.get_parent() is RightSidePanel, "level follows the native landscape panel")
		if mod.level_label != null:
			check((mod.level_label.get_parent() as Control).get_global_rect().grow(1.0).encloses(mod.level_label.get_global_rect()), "landscape level stays inside its panel")
		await shot("landscape")
	finish()

func finish() -> void:
	print("PRIME_MOBILE_DONE checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
