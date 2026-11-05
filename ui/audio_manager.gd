extends Node
## Audio Manager for Grey Oath. Handles background music and polyphonic SFX.

const MUSIC_TRACKS := {
	"title": "res://assets/audio/music_title.wav",
	"battle": "res://assets/audio/music_battle.wav",
	"explore": "res://assets/audio/music_explore.wav",
}

const SFX_TRACKS := {
	"click": "res://assets/audio/sfx_click.wav",
	"card": "res://assets/audio/sfx_card_play.wav",
	"slash": "res://assets/audio/sfx_slash.wav",
	"shield": "res://assets/audio/sfx_shield.wav",
	"bell": "res://assets/audio/sfx_bell.wav",
	"heal": "res://assets/audio/sfx_heal.wav",
	"victory": "res://assets/audio/sfx_victory.wav",
	"defeat": "res://assets/audio/sfx_defeat.wav",
}

var music_player: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _current_music: String = ""
var _tone := RandomNumberGenerator.new()
var _music_spare: AudioStreamPlayer
var _music_tween: Tween
var _music_gain := 0.7
var _sound_gain := 0.8

var music_enabled: bool = true:
	set(value):
		if music_enabled == value:
			return
		music_enabled = value
		if not music_enabled and music_player:
			music_player.stop()
			if _music_spare:
				_music_spare.stop()
		elif music_enabled and not _current_music.is_empty():
			play_music(_current_music)

var sound_enabled: bool = true

var _streams: Dictionary = {}


func _ready() -> void:
	_tone.seed = 17041
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.volume_db = -12.0
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)
	_music_spare = AudioStreamPlayer.new()
	_music_spare.name = "MusicCrossfade"
	add_child(_music_spare)
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.volume_db = -4.0
		add_child(p)
		sfx_pool.append(p)
		
	# Preload streams
	for k in MUSIC_TRACKS:
		if ResourceLoader.exists(MUSIC_TRACKS[k]):
			_streams[k] = load(MUSIC_TRACKS[k])
	for k in SFX_TRACKS:
		if ResourceLoader.exists(SFX_TRACKS[k]):
			_streams[k] = load(SFX_TRACKS[k])


func _ensure_stream(track_name: String, paths: Dictionary) -> void:
	if _streams.has(track_name) or not paths.has(track_name):
		return
	var path := str(paths[track_name])
	if ResourceLoader.exists(path):
		_streams[track_name] = load(path)


func play_music(track_name: String) -> void:
	_ensure_stream(track_name, MUSIC_TRACKS)
	if not _streams.has(track_name):
		return
	if _current_music == track_name and music_player.playing:
		return
	_current_music = track_name
	if not music_enabled:
		return
	var stream: AudioStream = _streams[track_name]
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_begin = 0
		(stream as AudioStreamWAV).loop_end = maxi(1, roundi(stream.get_length() * (stream as AudioStreamWAV).mix_rate))
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	var outgoing := music_player
	music_player = _music_spare
	_music_spare = outgoing
	music_player.stop()
	music_player.stream = stream
	music_player.volume_db = -60.0
	music_player.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(music_player, "volume_db", _music_db(), 0.8)
	_music_tween.tween_property(outgoing, "volume_db", -60.0, 0.8)
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	_current_music = ""
	if music_player:
		music_player.stop()
	if _music_spare:
		_music_spare.stop()


func _on_music_finished() -> void:
	if music_enabled and not _current_music.is_empty():
		music_player.play()


func play_sfx(sfx_name: String, pitch_range: float = 0.05, volume_db: float = -4.0, pitch: float = 1.0) -> void:
	_ensure_stream(sfx_name, SFX_TRACKS)
	if not sound_enabled or not _streams.has(sfx_name) or sfx_pool.is_empty():
		return
	var player := sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % sfx_pool.size()
	player.stream = _streams[sfx_name]
	player.volume_db = volume_db + linear_to_db(maxf(0.0001, _sound_gain))
	player.pitch_scale = pitch + _tone.randf_range(-pitch_range, pitch_range)
	player.play()


func _music_db() -> float:
	return -12.0 + linear_to_db(maxf(0.0001, _music_gain))


func apply_settings(settings: Dictionary) -> void:
	var gain := clampf(float(settings.get("music_volume", 0.7)), 0.0, 1.0)
	if not is_equal_approx(gain, _music_gain):
		_music_gain = gain
		if _music_tween and _music_tween.is_valid():
			_music_tween.kill()
		_music_spare.stop()
		music_player.volume_db = _music_db()
	_sound_gain = clampf(float(settings.get("sound_volume", 0.8)), 0.0, 1.0)
	music_enabled = bool(settings.get("music", true)) and gain > 0.0
	sound_enabled = bool(settings.get("sound", true)) and _sound_gain > 0.0
	if not sound_enabled:
		for player in sfx_pool:
			player.stop()
