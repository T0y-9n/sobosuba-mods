extends SceneTree
## Standalone Godot only; no sobosuba assets, autoloads, or game launch.
## The mod's own words (prime_text.gd) in each language the game offers, through the real TranslationServer.
const LOCALES:= ["en", "ja", "de", "es", "it", "cs", "pl", "ru", "sr", "zh_CN", "zh_TW"]
const KEYS:= ["prime balls", "send scores", "prime balls description", "send scores description", "guide description",
	"board line", "local rank", "unranked", "friends", "world loading", "world rank", "you", "world failed",
	"no steam", "not sent", "scores heading", "world disabled", "world", "screenshot location", "level"]
var failures:= 0


func check(ok: bool, what: String) -> void:
	print("TEXT_CHECK ", "OK " if ok else "FAIL ", what)
	if not ok:
		failures += 1


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var words: Script = load(OS.get_cmdline_user_args()[0])
	if words == null or not words.can_instantiate():
		check(false, "prime_text.gd compiles")
		quit(1)
		return
	for key: String in KEYS:
		TranslationServer.set_locale("en")
		var english: String = words.get_text(key)
		check(english != "", "%s has English" % key)
		var seen:= {}
		for locale: String in LOCALES:
			TranslationServer.set_locale(locale)
			var text: String = words.get_text(key)
			check(text != "" and (locale == "en" or text != english), "%s in %s (%s): %s" % [key, locale, TranslationServer.get_locale(), text])
			check(text.count("%d") == english.count("%d") and text.count("%s") == english.count("%s"), "%s in %s keeps the places for numbers and words" % [key, locale])
			# Simplified and Traditional Chinese may share the same characters.
			if locale != "zh_TW":
				seen[text] = true
		check(seen.size() == LOCALES.size() - 1,"%s has its own words in each of the %d languages" % [key, LOCALES.size()])
		TranslationServer.set_locale("fr")
		check(words.get_text(key) == english, "%s is English in a language the game does not offer" % key)
	print("TEXT_DONE failures=%d" % failures)
	quit(0 if failures == 0 else 1)
