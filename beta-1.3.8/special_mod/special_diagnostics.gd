extends RefCounted

const MOD_VERSION := "1.3.11-0.5.7"
const STALL_MSEC := 5000

class ScopeGuard extends RefCounted:
	var logger: RefCounted
	var token: int

	func _init(owner: RefCounted, identifier: int) -> void:
		logger = owner
		token = identifier

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and logger != null:
			logger.leave(token)

var _mutex := Mutex.new()
var _thread := Thread.new()
var _running := false
var _armed := false
var _entry := "idle"
var _snapshot := ""
var _last_progress_msec := 0
var _reported := false
var _prefix := ""
var _scopes: Array[Dictionary] = []
var _next_token := 0


func _init(version: String = MOD_VERSION) -> void:
	_prefix = "[Special Sobos %s] " % version
	_running = true
	_last_progress_msec = Time.get_ticks_msec()
	if _thread.start(_watch) != OK:
		_running = false
		self.log("warning diagnostic thread could not start")


static func write_line(version: String, message: String) -> void:
	print("[Special Sobos %s] " % version + message.replace("\r", "\\r").replace("\n", "\\n"))


func log(message: String) -> void:
	print(_prefix + message.replace("\r", "\\r").replace("\n", "\\n"))


func pulse(entry: String, snapshot: String, armed: bool) -> void:
	_mutex.lock()
	if _running:
		_entry = entry
		_snapshot = snapshot
		_armed = armed
		_last_progress_msec = Time.get_ticks_msec()
		_reported = false
	_mutex.unlock()


func set_armed(armed: bool) -> void:
	if not armed:
		for state: Dictionary in _scopes:
			state.armed = false
	_mutex.lock()
	if _armed != (armed and _running):
		_armed = armed and _running
		_last_progress_msec = Time.get_ticks_msec()
		_reported = false
	_mutex.unlock()


func snapshot_state() -> Dictionary:
	_mutex.lock()
	var state := {"running":_running, "armed":_armed, "entry":_entry, "snapshot":_snapshot, "last_progress_msec":_last_progress_msec, "reported":_reported}
	_mutex.unlock()
	return state


func scope(entry: String, snapshot: String, armed: bool) -> RefCounted:
	_next_token += 1
	_scopes.append({"token":_next_token, "entry":entry, "snapshot":snapshot, "armed":armed})
	pulse(entry, snapshot, armed)
	return ScopeGuard.new(self, _next_token)


func leave(token: int) -> void:
	var finished: Dictionary = {}
	for index: int in range(_scopes.size() - 1, -1, -1):
		if _scopes[index].token == token:
			finished = _scopes[index]
			_scopes.remove_at(index)
			break
	if _scopes.is_empty():
		if not finished.is_empty():
			pulse(finished.entry + ".returned", finished.snapshot, finished.armed)
	else:
		var parent: Dictionary = _scopes.back()
		pulse(parent.entry, parent.snapshot, parent.armed)


func stop() -> void:
	_mutex.lock()
	_running = false
	_armed = false
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(100)
		var line := ""
		_mutex.lock()
		var running: bool = _running
		if running and _armed and not _reported and Time.get_ticks_msec() - _last_progress_msec >= STALL_MSEC:
			_reported = true
			line = _prefix + "stalled entry=" + _entry + " snapshot=" + _snapshot
		_mutex.unlock()
		if not running:
			return
		if not line.is_empty():
			print(line.replace("\r", "\\r").replace("\n", "\\n"))
