extends SceneTree
## Standalone Godot only; no sobosuba assets, autoloads, or game launch.
## Prime levels (spec §10) on the real prime_level.gd: the game's open spawn tiers -> level -> chance.
var failures:= 0


func check(ok: bool, what: String) -> void:
	print("LEVEL_CHECK ", "OK " if ok else "FAIL ", what)
	if not ok:
		failures += 1


func _initialize() -> void:
	run.call_deferred()


func is_prime(n: int) -> bool:
	if n < 2:
		return false
	var d:= 2
	while d * d <= n:
		if n % d == 0:
			return false
		d += 1
	return true


func run() -> void:
	var level: Script = load(OS.get_cmdline_user_args()[0])
	if level == null or not level.can_instantiate():
		check(false, "prime_level.gd compiles")
		quit(1)
		return
	var percents: Array[int] = []
	for l: int in range(1, 8):
		percents.append(roundi(level.chance_of(l) * 100.0))
	check(percents == [11, 13, 17, 19, 23, 29, 31], "levels 1-7 are 11, 13, 17, 19, 23, 29 and 31 percent: %s" % [percents])
	var primes: Array[int] = []
	for n: int in range(11, 32):
		if is_prime(n):
			primes.append(n)
	check(percents == primes, "the percents are the primes from 11 in order, none skipped: %s" % [primes])
	check(level.level_of([0]) == 1, "only the smallest tier open is level 1")
	check(level.level_of([0, 1, 2]) == 3, "three tiers open is level 3")
	check(level.level_of([0, 1, 2, 3, 4, 5, 6]) == 7, "all seven tiers open is level 7")
	check(level.level_of([0, 1, 2, 3, 4, 5, 6, 7, 8]) == 7, "more than seven tiers stays at level 7")
	check(level.level_of([]) == 1, "an empty pool counts as level 1")
	check(is_equal_approx(level.chance_of(0), 0.11) and is_equal_approx(level.chance_of(99), 0.31), "levels out of range use the nearest one")
	print("LEVEL_DONE failures=%d" % failures)
	quit(0 if failures == 0 else 1)
