extends RefCounted
## Only the main thread writes game data here, already copied into strings.
const MOD_VERSION := "1.3.11-1.0.7"
const MOD_TAG := "[Prime Sobos %s]" % MOD_VERSION
const STALL_MS := 5000
const POLL_MS := 100

var _mutex := Mutex.new()
var _thread := Thread.new()
var _running := false
var _armed := false
var _mark := 0
var _last_mark_ms := 0
var _entry := ""
var _snapshot := ""
var _reported := false
var _stall_count := 0


func start() -> Error:
	if _thread.is_started():
		return ERR_ALREADY_IN_USE
	_mutex.lock()
	_running = true
	_armed = false
	_last_mark_ms = Time.get_ticks_msec()
	_mutex.unlock()
	var error := _thread.start(_watch)
	if error != OK:
		_mutex.lock()
		_running = false
		_mutex.unlock()
	return error


func pulse(entry: String, snapshot: String, armed: bool = true) -> void:
	_mutex.lock()
	if _running:
		_mark += 1
		_last_mark_ms = Time.get_ticks_msec()
		_entry = entry
		_snapshot = snapshot
		_armed = armed
		_reported = false
	_mutex.unlock()


func set_armed(value: bool) -> void:
	_mutex.lock()
	_mark += 1
	_last_mark_ms = Time.get_ticks_msec()
	_armed = value and _running
	_reported = false
	_mutex.unlock()


func snapshot_state() -> Dictionary:
	_mutex.lock()
	var state := {"mark": _mark, "entry": _entry, "snapshot": _snapshot,
		"armed": _armed, "running": _running, "reported": _reported, "stall_count": _stall_count}
	_mutex.unlock()
	return state


func stop() -> void:
	_mutex.lock()
	_running = false
	_armed = false
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()


func _watch() -> void:
	while true:
		var line := ""
		_mutex.lock()
		var running: bool = _running
		var idle_ms: int = Time.get_ticks_msec() - _last_mark_ms
		if running and _armed and not _reported and idle_ms >= STALL_MS:
			_reported = true
			_stall_count += 1
			line = "%s event=stall entry=%s mark=%d idle_ms=%d snapshot=%s" % [MOD_TAG, _entry, _mark, idle_ms, _snapshot]
		_mutex.unlock()
		if not running:
			return
		if not line.is_empty():
			print(line)
		OS.delay_msec(POLL_MS)
