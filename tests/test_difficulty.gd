extends SceneTree

const Rules = preload("res://core/game_engine.gd")
const SEED := 729

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	_test_progression()
	_test_save()
	_test_combat()
	await _test_picker()
	print("DIFFICULTY_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _test_progression() -> void:
	var game = Rules.new("")
	for difficulty in [-3, 1, 6, 9]:
		_check(not game.new_run("warden", SEED, difficulty).ok, "fresh profile rejects difficulty %d" % difficulty)
	for difficulty in [-2, -1]:
		_check(game.new_run("warden", SEED, difficulty).ok, "fresh profile accepts difficulty %d" % difficulty)
		game._finish_run(true)
		_check(game.unlocked_difficulty("warden") == 0, "victory below standard does not unlock ascension")
		_check(int(game.profile.history[0].difficulty) == difficulty, "history records the selected preset")
	_check(int(game.profile.clears.warden) == 2, "lower difficulty clears count toward role clears")
	_check(game.new_run("warden", SEED).ok and int(game.state.difficulty) == 0, "standard remains the default")
	game._finish_run(true)
	_check(game.unlocked_difficulty("warden") == 1, "standard victory unlocks ascension 1")
	_check(game.unlocked_difficulty("ranger") == 0, "ascension unlocks are per role")
	game.profile.ascension.warden = 5
	_check(not game.new_run("warden", SEED, 6).ok, "legacy ascension 5 profile must clear 5 before 6")
	for difficulty in [5, 6, 7, 8]:
		_check(game.new_run("warden", SEED, difficulty).ok, "unlocked ascension %d is playable" % difficulty)
		game._finish_run(true)
		_check(game.unlocked_difficulty("warden") == mini(difficulty + 1, 8), "ascension advances one level, capped at 8")
	_check(not game.new_run("warden", SEED, 9).ok, "ascension above 8 remains unavailable")
	_check(game.new_run("warden", SEED, -1).ok, "earlier presets remain playable")
	game._finish_run(true)
	_check(game.unlocked_difficulty("warden") == 8, "a lower clear preserves higher unlocks")


func _test_save() -> void:
	var path := "user://difficulty-test-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	for difficulty in [-2, -1, 5, 8]:
		var game = Rules.new(path)
		game.profile.ascension.warden = maxi(0, difficulty)
		_check(game.new_run("warden", SEED, difficulty).ok and game.enter_node(1).ok, "difficulty %d starts and saves a battle" % difficulty)
		var restored = Rules.new(path)
		_check(restored.state.active and restored.state.room == "battle" and int(restored.state.difficulty) == difficulty, "saved battle retains difficulty %d" % difficulty)
		_check(restored.unlocked_difficulty("warden") == maxi(0, difficulty), "saved profile retains its ascension")
		_check(restored.state.enemies == game.state.enemies, "loading does not rescale existing enemies")
		game.abandon_run()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _encounter(difficulty: int, kind: String, chapter: int = 0):
	var game = Rules.new("")
	game.profile.ascension.warden = 8
	game.new_run("warden", SEED, difficulty)
	game.state.chapter = chapter
	game.state.map[0][1].kind = kind
	game.enter_node(1)
	return game


func _test_combat() -> void:
	for kind in ["normal", "elite", "boss"]:
		var story = _encounter(-2, kind)
		var easy = _encounter(-1, kind)
		var standard = _encounter(0, kind)
		_check(not standard.state.enemies.is_empty(), "%s fixture starts combat" % kind)
		for index in standard.state.enemies.size():
			var baseline: Dictionary = standard.state.enemies[index]
			var story_enemy: Dictionary = story.state.enemies[index]
			var easy_enemy: Dictionary = easy.state.enemies[index]
			_check(baseline.id == story_enemy.id and baseline.id == easy_enemy.id, "difficulty preserves seeded enemy selection")
			_check(int(story_enemy.max_hp) == maxi(1, floori(int(baseline.max_hp) * 0.65)), "story HP reduction for %s" % kind)
			_check(int(easy_enemy.max_hp) == maxi(1, floori(int(baseline.max_hp) * 0.80)), "easy HP reduction for %s" % kind)
	var elite_five = _encounter(5, "elite")
	var elite_six = _encounter(6, "elite")
	_check(int(elite_six.state.enemies[0].max_hp) == ceili(int(elite_five.state.enemies[0].max_hp) * 1.15), "ascension 6 raises elite HP")
	for index in [1, 2]:
		_check(elite_six.state.enemies[index].max_hp == elite_five.state.enemies[index].max_hp, "ascension 6 leaves escort HP unchanged")
	for fixture in [[-2, 7, 7], [-1, 8, 8], [0, 11, 10], [6, 13, 10], [7, 15, 12]]:
		var game = _encounter(int(fixture[0]), "elite")
		var effect := {"op": "damage", "value": 10}
		for enemy in game.state.enemies:
			enemy.pattern = [{"effects": [effect]}]
		game._update_intents()
		for index in [0, 1]:
			var expected := int(fixture[index + 1])
			game.state.hp = 80
			game.state.block = 0
			game._enemy_effect(effect, index)
			_check(game.state.enemies[index].intent == "攻击 %d" % expected and int(game.state.hp) == 80 - expected,
				"difficulty %d shows and deals %d damage for enemy %d" % [fixture[0], expected, index])
	for chapter in [0, 3]:
		var boss_seven = _encounter(7, "boss", chapter)
		var boss_eight = _encounter(8, "boss", chapter)
		var boosted_hp := ceili(int(boss_seven.state.enemies[0].max_hp) * 1.20)
		for phase in range(1, int(boss_eight.state.boss_phases) + 1):
			_check(int(boss_eight.state.boss_phase) == phase and int(boss_eight.state.enemies[0].hp) == boosted_hp,
				"ascension 8 raises chapter %d boss HP in phase %d" % [chapter + 1, phase])
			boss_eight.state.enemies[0].hp = 0
			boss_eight._check_battle_end()


func _test_picker() -> void:
	root.size = Vector2i(1280, 800)
	var ui_script := load("res://tests/ui_shell.gd") as GDScript
	if ui_script == null or not ui_script.can_instantiate():
		_check(false, "test UI and its dependencies must load")
		return
	var ui = ui_script.new()
	if not ui is Control:
		_check(false, "test UI must create a Control")
		return
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var new_journey := ui.find_child("NewJourneyButton", true, false) as Button
	if new_journey == null or ui.game == null:
		_check(false, "test UI must build the title menu and game")
		ui.queue_free()
		return
	ui.game.profile.settings.merge({"music": false, "sound": false}, true)
	ui._sync_audio()
	new_journey.pressed.emit()
	for frame in 4:
		await process_frame
	var levels := ui.find_child("DifficultySelect", true, false) as OptionButton
	_check(levels != null, "difficulty picker is present on the role screen")
	if levels == null:
		ui.queue_free()
		return
	_check(int(levels.get_item_metadata(levels.selected)) == 0, "picker initially selects standard")
	_check(levels.item_count == 11, "picker includes eight visible ascension tiers")
	var story_index := -1
	var selectable: Array[int] = []
	for index in levels.item_count:
		var difficulty := int(levels.get_item_metadata(index))
		if not levels.is_item_disabled(index):
			selectable.append(difficulty)
		if difficulty == -2:
			story_index = index
	_check(selectable == [-2, -1, 0], "fresh picker enables exactly three options")
	_check(ui.get_global_rect().encloses(levels.get_global_rect()),
		"difficulty picker %s fits in window %s" % [levels.get_global_rect(), ui.get_global_rect()])
	if story_index >= 0:
		var note := ui.find_child("DifficultyDescription", true, false) as Label
		var standard_description := note.text if note != null else ""
		levels.get_popup().index_pressed.emit(story_index)
		_check(note != null and note.text != standard_description, "choosing a different difficulty updates its explanation")
		ui.seed_input.text = str(SEED)
		ui._begin_run()
		_check(ui.game.state.active and int(ui.game.state.difficulty) == -2, "popup selection starts the signed story difficulty")
		ui.menu_open = true
		ui._refresh()
		for frame in 4:
			await process_frame
		levels = ui.find_child("DifficultySelect", true, false) as OptionButton
		_check(levels != null and ui.get_global_rect().encloses(levels.get_global_rect()), "picker remains visible during an active run")
		var active_buttons: Array[Button] = []
		if levels != null:
			for control in levels.get_parent().get_children():
				if control is Button and control.text in ["继续旅程", "结束当前旅程"]:
					active_buttons.append(control)
		_check(active_buttons.size() == 2 and active_buttons.all(func(button: Button) -> bool:
			return not button.disabled and ui.get_global_rect().encloses(button.get_global_rect())),
			"continue and abandon buttons remain usable at the target window size")
	ui.queue_free()
	await process_frame
