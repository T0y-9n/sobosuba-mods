extends RefCounted
## Cancels this boot reader's own process tree on Windows. Never used for modifying operations.

var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func execute(path: String, arguments: PackedStringArray, output: Array) -> int:
	if cancelled():
		return -1
	var child := OS.execute_with_pipe(path, arguments, false)
	if child.is_empty():
		return -1
	var stdout := PackedByteArray()
	var stderr := PackedByteArray()
	while OS.is_process_running(child.pid):
		stdout.append_array(child.stdio.get_buffer(65536))
		stderr.append_array(child.stderr.get_buffer(65536))
		if cancelled():
			# execute runs on the reader worker, so the blocking OS call never waits on the UI thread.
			if OS.get_name() == "Windows":
				var taskkill := OS.get_environment("SystemRoot").path_join("System32/taskkill.exe")
				var killed: Array = []
				var code := -1
				if taskkill.is_absolute_path() and FileAccess.file_exists(taskkill):
					code = OS.execute(taskkill, ["/PID", str(child.pid), "/T", "/F"], killed, true, false)
				if code != 0:
					print("Mod Hub cancel tree_failed code=", code)
			if OS.is_process_running(child.pid):
				OS.kill(child.pid)
		else:
			OS.delay_msec(10)
	for pipe in [child.stdio, child.stderr]:
		while true:
			var bytes: PackedByteArray = pipe.get_buffer(65536)
			if bytes.is_empty():
				break
			if pipe == child.stdio:
				stdout.append_array(bytes)
			else:
				stderr.append_array(bytes)
		pipe.close()
	output.append(stdout.get_string_from_utf8() + stderr.get_string_from_utf8())
	return OS.get_process_exit_code(child.pid)
