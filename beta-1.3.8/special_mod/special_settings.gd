extends RefCounted

const Parameters = preload("special_parameters.gd")

const PATH:= "user://special_sobo_settings.json"
const SELFTEST_PATH:= "user://special_sobo_settings_selftest.json"
const TRAITS: Array[String] = ["small", "puffy", "magnet", "sticky"]
const DEFAULT_MAGNET_PULL:= 2.0
const MIN_MAGNET_PULL:= 0.0
const MAX_MAGNET_PULL:= 20.0

var path:= PATH
var enabled:= true
var base_traits: Array[String] = TRAITS.duplicate()
var extra_traits: Array[String] = []
var traits: Dictionary = default_traits()
var magnet_pull_multiplier:= DEFAULT_MAGNET_PULL
var numbers: Dictionary = Parameters.defaults()
var parameter_values: Dictionary = Parameters.VALUES.duplicate(true)


func register_parameters(values: Dictionary) -> void:
	parameter_values.merge(values)


func number_defaults() -> Dictionary:
	var result: Dictionary = {}
	for key: String in parameter_values:
		if key != "magnet_pull_multiplier":
			result[key] = float(parameter_values[key][0])
	return result


func valid_number(key: String, value: float) -> bool:
	if not parameter_values.has(key) or not is_finite(value):
		return false
	var spec: Array = parameter_values[key]
	return value >= spec[1] and value <= spec[2] and (not spec[3] or value == floor(value))


static func default_traits(kinds: Array[String] = TRAITS) -> Dictionary:
	var result: Dictionary = {}
	for kind: String in kinds:
		result[kind] = true
	return result


func trait_kinds() -> Array[String]:
	var result: Array[String] = base_traits.duplicate()
	result.append_array(extra_traits)
	return result


func load_file() -> void:
	enabled = true
	traits = default_traits(trait_kinds())
	magnet_pull_multiplier = DEFAULT_MAGNET_PULL
	numbers = number_defaults()
	if not FileAccess.file_exists(path):
		return
	var json:= JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
		if json.data.get("enabled") is bool:
			enabled = json.data.enabled
		var pull: Variant = json.data.get("magnet_pull_multiplier")
		if (pull is float or pull is int) and valid_magnet_pull(float(pull)):
			magnet_pull_multiplier = float(pull)
		var saved: Variant = json.data.get("traits")
		var saved_numbers: Variant = json.data.get("parameters")
		if saved_numbers is Dictionary:
			for key: String in numbers:
				var value: Variant = saved_numbers.get(key)
				if (value is float or value is int) and valid_number(key, float(value)):
					numbers[key] = float(value)
			# Keep settings owned by an independently installed companion package.
			for key: String in saved_numbers:
				if not parameter_values.has(key):
					numbers[key] = saved_numbers[key]
		if saved is Dictionary:
			for kind: Variant in saved:
				if saved.get(kind) is bool:
					traits[kind] = saved[kind]


func trait_enabled(kind: String) -> bool:
	return bool(traits.get(kind, true))


func set_enabled(value: bool) -> void:
	if write(value, traits, magnet_pull_multiplier):
		enabled = value


func set_trait(kind: String, value: bool) -> void:
	if not trait_kinds().has(kind):
		return
	var next: Dictionary = traits.duplicate()
	next[kind] = value
	if write(enabled, next, magnet_pull_multiplier):
		traits = next


func valid_magnet_pull(value: float) -> bool:
	return is_finite(value) and value >= MIN_MAGNET_PULL and value <= MAX_MAGNET_PULL


func set_magnet_pull_multiplier(value: float) -> bool:
	if not valid_magnet_pull(value):
		return false
	if value == magnet_pull_multiplier:
		return true
	if not write(enabled, traits, value):
		return false
	magnet_pull_multiplier = value
	return true


func number(key: String) -> float:
	if key == "magnet_pull_multiplier":
		return magnet_pull_multiplier
	return float(numbers.get(key, 0.0))


func set_number(key: String, value: float) -> bool:
	if not valid_number(key, value):
		return false
	if key == "magnet_pull_multiplier":
		return set_magnet_pull_multiplier(value)
	var next: Dictionary = numbers.duplicate()
	next[key] = value
	if not write(enabled, traits, magnet_pull_multiplier, next):
		return false
	numbers = next
	return true


func reset_numbers(keys: Array = []) -> bool:
	var defaults: Dictionary = numbers.duplicate()
	for key: String in parameter_values:
		if key != "magnet_pull_multiplier" and (keys.is_empty() or key in keys):
			defaults[key] = float(parameter_values[key][0])
	var pull: float = DEFAULT_MAGNET_PULL if keys.is_empty() or "magnet_pull_multiplier" in keys else magnet_pull_multiplier
	if not write(enabled, traits, pull, defaults):
		return false
	numbers = defaults
	magnet_pull_multiplier = pull
	return true


func write(enabled_value: bool, traits_value: Dictionary, pull_value: float, values: Dictionary = {}) -> bool:
	var file:= FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[special_sobo] could not write settings")
		return false
	file.store_string(JSON.stringify({"enabled": enabled_value, "traits": traits_value, "magnet_pull_multiplier": pull_value, "parameters": numbers if values.is_empty() else values}))
	file.flush()
	return file.get_error() == OK
