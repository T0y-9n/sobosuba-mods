extends RefCounted

var reason := ""
var player: AudioStreamPlayer
var stopped_bgm: AudioStreamPlayer
var resume_bgm := false

func prepare(parent: Node) -> void:
	_ensure_bus()
	if player != null and is_instance_valid(player):
		return
	player = AudioStreamPlayer.new()
	player.name = "MusicSoboSong"
	player.bus = "MusicSobo"
	parent.add_child(player)

func load_song(path: String) -> String:
	var stream := _open(path)
	if stream == null:
		if player != null:
			player.stop()
			player.stream = null
		print("music sobo: %s" % reason)
		return reason
	if "loop" in stream:
		stream.set("loop", true)
	player.stream = stream
	reason = ""
	return ""

func set_playing(on: bool) -> void:
	if player == null:
		return
	if on:
		if player.stream == null:
			return
		var bgm := _find_bgm()
		if bgm != null and bgm.playing:
			bgm.stop()
			stopped_bgm = bgm
			resume_bgm = true
		if not player.playing:
			player.play()
		return
	player.stop()
	if resume_bgm and stopped_bgm != null and is_instance_valid(stopped_bgm):
		stopped_bgm.play()
	resume_bgm = false
	stopped_bgm = null

func is_playing() -> bool:
	return player != null and player.playing

func song_bus() -> String:
	if player == null:
		return ""
	return player.bus

func song_length() -> float:
	if player == null or player.stream == null:
		return 0.0
	return player.stream.get_length()

func _ensure_bus() -> void:
	if AudioServer.get_bus_index("MusicSobo") != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, "MusicSobo")
	AudioServer.set_bus_send(index, AudioServer.get_bus_name(0))
	AudioServer.add_bus_effect(index, AudioEffectSpectrumAnalyzer.new())

func _open(path: String) -> AudioStream:
	var lower := path.to_lower()
	if not (lower.ends_with(".wav") or lower.ends_with(".ogg") or lower.ends_with(".mp3")):
		reason = "unsupported file"
		return null
	if not FileAccess.file_exists(path):
		reason = "file not found"
		return null
	var stream: AudioStream = null
	if lower.ends_with(".wav"):
		stream = AudioStreamWAV.load_from_file(path)
	elif lower.ends_with(".ogg"):
		stream = AudioStreamOggVorbis.load_from_file(path)
	else:
		stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		reason = "could not read the file"
		return null
	return stream

func _find_bgm() -> AudioStreamPlayer:
	if player == null:
		return null
	return _search(player.get_tree().root)

func _search(node: Node) -> AudioStreamPlayer:
	if node is AudioStreamPlayer and node != player and node.playing:
		var stream: AudioStream = node.stream
		if stream != null and stream.get_length() > 15.0:
			return node
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null
