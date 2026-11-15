extends RefCounted

var reason := ""
var player: AudioStreamPlayer
var stopped_bgm: AudioStreamPlayer
var resume_bgm := false
# Master reverb effects this mod turned off while a song plays.
var muted_reverbs: Array[int] = []

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
		restore_reverb()
		print("music sobo: %s" % reason)
		return reason
	if "loop" in stream:
		stream.set("loop", true)
	player.stream = stream
	if not player.playing:
		restore_reverb()
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
		_mute_reverb()
		return
	player.stop()
	restore_reverb()
	if resume_bgm and stopped_bgm != null and is_instance_valid(stopped_bgm):
		stopped_bgm.play()
	resume_bgm = false
	stopped_bgm = null

# The game's Master bus has a reverb, and every bus ends on Master.
# Turn the enabled ones off while a song plays; leave ones that were off alone.
func _mute_reverb() -> void:
	if not muted_reverbs.is_empty():
		return
	for index: int in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, index) is AudioEffectReverb and AudioServer.is_bus_effect_enabled(0, index):
			AudioServer.set_bus_effect_enabled(0, index, false)
			muted_reverbs.append(index)

func restore_reverb() -> void:
	for index: int in muted_reverbs:
		if index < AudioServer.get_bus_effect_count(0) and AudioServer.get_bus_effect(0, index) is AudioEffectReverb:
			AudioServer.set_bus_effect_enabled(0, index, true)
	muted_reverbs.clear()

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
