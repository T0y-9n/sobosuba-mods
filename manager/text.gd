extends RefCounted

const LANGUAGES := {"en": "English", "ja": "日本語", "de": "Deutsch", "es": "Español", "es_MX": "Español (México)", "fr": "Français", "it": "Italiano", "pt_BR": "Português (Brasil)", "cs": "Čeština", "pl": "Polski", "ru": "Русский", "sr": "Српски", "zh_CN": "简体中文", "zh_TW": "繁體中文", "tr": "Türkçe", "uk": "Українська", "ko": "한국어", "id": "Bahasa Indonesia", "vi": "Tiếng Việt", "nl": "Nederlands", "hu": "Magyar", "ro": "Română"}
var translations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locales.json"))
var locale := "en"

func _init() -> void:
	set_locale(OS.get_locale())

func set_locale(value: String) -> void:
	var normalized := value.replace("-", "_")
	if LANGUAGES.has(normalized):
		locale = normalized
	elif normalized.begins_with("zh"):
		locale = "zh_TW" if normalized.contains("TW") or normalized.contains("HK") or normalized.contains("Hant") else "zh_CN"
	elif normalized.begins_with("pt"):
		locale = "pt_BR"
	else:
		var language := normalized.get_slice("_", 0)
		locale = language if LANGUAGES.has(language) else "en"
	TranslationServer.set_locale(locale)

func word(key: String, args: Array = []) -> String:
	var text: String = translations[locale].get(key, "[" + key + "]")
	for i in range(args.size()):
		text = text.replace("{" + str(i) + "}", str(args[i]))
	return text

func error_word(key: String, args: Array = []) -> String:
	var mapping := {"version_mismatch": "err_version", "unknown_version": "err_target", "game_missing": "err_target", "invalid_metadata": "err_zip", "unsafe_zip": "err_zip", "zip_read": "err_zip", "zip_changed": "err_changed", "unsafe_path": "err_conflict", "file_conflict": "err_conflict", "recovery_needed": "err_recovery", "game_running": "err_running", "busy": "loading", "io_error": "err_io", "invalid_request": "error", "adopt_required": "err_adopt", "other_version_active": "err_other"}
	var message := word(mapping.get(key, "error"))
	# 保存層が返す構造化した道・版・MOD名だけを表示する。OSの英語エラーは混ぜない。
	if key in ["file_conflict", "unsafe_path", "recovery_needed", "game_missing", "zip_read", "version_mismatch", "other_version_active"]:
		for detail in args:
			message += "\n" + str(detail)
	return message
