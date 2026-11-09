extends RefCounted
## Shared by the versioned MOD payloads. The game owns each version's default modes.

static func is_classic_run(manager: Object) -> bool:
	if "current_game_mode" in manager:
		var mode: Resource = manager.get("current_game_mode")
		if mode == null || not is_instance_valid(manager.get("current_scene")):
			return false
		if mode != manager.get("default_game_mode") && mode != manager.get("default_mobile_game_mode"):
			return false
		var run: RefCounted = manager.get("run")
		return (
			not run.get("replay")
			&& run.get("merge_radix") == mode.get("radix")
			&& run.get("sprint_target") == mode.get("sprint_target")
		)
	var legacy_mode: Node = manager.get("current_mode")
	if not is_instance_valid(legacy_mode):
		return false
	return (
		legacy_mode.scene_file_path == manager.get("default_mode_path")
		|| legacy_mode.scene_file_path == manager.get("default_mobile_mode_path")
	)


## Cached prime records remain shared in menus and classic runs, even with prime balls off.
static func can_share_prime_best(manager: Object) -> bool:
	var scene: Variant = manager.get("current_scene") if "current_scene" in manager else manager.get("current_mode")
	return not is_instance_valid(scene) || is_classic_run(manager)
