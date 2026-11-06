extends SceneTree

const AudioScript = preload("res://ui/audio_manager.gd")
var checks := 0
var failures: Array[String] = []

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		printerr("FAIL: ", msg)

func _initialize() -> void:
	print("Starting Audio System Verification...")
	var audio = AudioScript.new()
	get_root().add_child(audio)
	await process_frame
	
	# 1. Verify all tracks exist and loaded
	for track in ["title", "battle"]:
		check(ResourceLoader.exists(AudioScript.MUSIC_TRACKS[track]), "Music file exists: " + track)
		var stream = load(AudioScript.MUSIC_TRACKS[track])
		check(stream is AudioStreamWAV, "Music is AudioStreamWAV: " + track)
		check(stream.get_length() > 0.0, "Music has positive length: " + track)
		
	for sfx in ["click", "card", "slash", "shield", "bell", "heal", "victory", "defeat"]:
		check(ResourceLoader.exists(AudioScript.SFX_TRACKS[sfx]), "SFX file exists: " + sfx)
		var stream = load(AudioScript.SFX_TRACKS[sfx])
		check(stream is AudioStreamWAV, "SFX is AudioStreamWAV: " + sfx)
		check(stream.get_length() > 0.0, "SFX has positive length: " + sfx)
		
	# 2. Test music player
	audio.play_music("title")
	check(audio.music_player != null, "Music player instantiated")
	check(audio._current_music == "title", "Current music track is title")
	
	audio.play_music("battle")
	check(audio._current_music == "battle", "Current music track switched to battle")
	
	# 3. Test SFX polyphony
	for sfx in ["click", "card", "slash", "shield", "bell", "heal"]:
		audio.play_sfx(sfx)
	check(audio.sfx_pool.size() == 8, "SFX pool has 8 players")
	
	# 4. Test mute toggles
	audio.music_enabled = false
	check(not audio.music_player.playing, "Muting music stops player")
	audio.sound_enabled = false
	
	audio.music_player.stop()
	for p in audio.sfx_pool:
		p.stop()
	audio.queue_free()
	await process_frame
	
	var result = {
		"checks": checks,
		"failures": failures,
		"scope": "offline procedural dark fantasy music and polyphonic SFX"
	}
	print("AUDIO_TEST_RESULT=", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
