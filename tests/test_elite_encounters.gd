extends SceneTree
const Rules = preload("res://core/game_engine.gd")
const Oaths = preload("res://core/oath_mechanics.gd")
var checks := 0
var failures: Array[String] = []
var capture := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func fixture(chapter: int = 0, seed_value: int = 729, difficulty: int = 0):
	var game = Rules.new("")
	game.new_run("warden", seed_value)
	game.state.chapter = chapter
	game.state.row = 0
	game.state.lane = 1
	game.state.encounter_kind = "elite"
	game.state.difficulty = difficulty
	game._start_battle("elite")
	return game

func run() -> void:
	for chapter in range(4):
		for seed_value in range(24):
			for difficulty in [0, 2]:
				var game = fixture(chapter, seed_value, difficulty)
				check(game.state.enemies.size() == 3, "elite encounter always has three enemies")
				var kinds: Array = []
				for enemy in game.state.enemies:
					var definition: Dictionary = game._indexes.enemies[enemy.id]
					kinds.append(definition.kind)
					check(int(definition.chapter) == chapter, "enemy belongs to current chapter")
					if definition.kind == "elite":
						# Elite affixes (长夜誓约) may scale the elite's HP; escorts stay untouched.
						var affix: Dictionary = Oaths.pick_affix(seed_value + chapter * 131)
						var affix_hp := Oaths.value(affix.get("modifiers", {}), "hp_pct")
						var expected_hp := ceili(float(definition.hp) * (100.0 + float(affix_hp)) / 100.0)
						check(int(enemy.max_hp) == expected_hp and enemy.get("affix", "") == affix.get("id", ""), "elite HP carries its affix scaling")
					else:
						var hp := maxi(10, int(int(definition.hp) * 0.40))
						if difficulty >= 1:
							hp = int(ceil(hp * 1.10))
						check(int(enemy.max_hp) == hp and enemy.escort, "escorts use elite three-enemy HP scaling")
				check(kinds.count("elite") == 1 and kinds.count("normal") == 2, "one elite plus two normal enemies")
	var game = fixture()
	var copy = fixture()
	check(JSON.stringify(game.state.enemies) == JSON.stringify(copy.state.enemies), "seeded lineup deterministic")
	var health: Array = []
	for enemy in game.state.enemies:
		health.append(int(enemy.hp))
	var damage := 3 + int(game.state.status.get("strength", 0))
	game._player_effect({"op": "damage", "value": 3, "target": "all"}, 0)
	for index in range(3):
		check(int(game.state.enemies[index].hp) == health[index] - damage, "area attack includes every enemy")
	var before: int = game.profile.total_wins
	game.state.enemies[0].hp = 0
	game._check_battle_end()
	check(game.state.room == "battle" and int(game.profile.total_wins) == before, "killing elite alone does not settle encounter")
	game.state.enemies[1].hp = 0
	game._check_battle_end()
	check(game.state.room == "battle", "last escort must also be defeated")
	game.state.enemies[2].hp = 0
	game._check_battle_end()
	check(game.state.room == "reward" and int(game.profile.total_wins) == before + 1, "full group rewards one victory")
	check(int(game.profile.stats.elite_wins) == 1, "one elite achievement progress")
	var gold: int = game.state.gold
	game._check_battle_end()
	game._win_battle()
	check(game.state.gold == gold and game.profile.stats.elite_wins == 1, "settlement idempotent")
	# At difficulty 2, the elite attack bonus must not leak into its two escorts.
	game = fixture(0, 729, 2)
	for enemy in game.state.enemies:
		enemy.pattern = [{"intent": "attack", "effects": [{"op": "damage", "value": 10}]}]
	game._update_intents()
	check(game.state.enemies[0].intent == "攻击 13", "elite intent includes its difficulty bonus")
	check(game.state.enemies[1].intent == "攻击 10" and game.state.enemies[2].intent == "攻击 10", "normal escorts retain normal difficulty damage")
	for index in range(3):
		game.state.hp = 90
		game.state.block = 0
		game._enemy_effect({"op": "damage", "value": 10}, index)
		check(int(game.state.hp) == (77 if index == 0 else 80), "intent and actual enemy damage agree")
	# Both dynamic attack bonuses are visible before the enemy acts.
	game = fixture()
	var foe: Dictionary = game.state.enemies[0]
	foe.pattern = [{"intent": "attack", "effects": [{"op": "damage", "value": 10}]}]
	foe.turn = 2
	foe.hp = int(foe.max_hp) / 2
	game._update_intents()
	check("攻击 14" in foe.intent and "蓄势 +1" in foe.intent and "困兽 +2" in foe.intent, "intent shows both dynamic mechanics")
	game.state.hp = 90
	game.state.block = 0
	game._enemy_effect({"op": "damage", "value": 10}, 0)
	check(int(game.state.hp) == 76, "actual attack matches both displayed bonuses")
	foe.hp = foe.max_hp
	foe.turn = 20
	game._update_intents()
	check("蓄势 +3" in foe.intent and "困兽" not in foe.intent, "pressure is capped and healing clears desperation")
	var path := "user://elite-save-%d.json" % OS.get_process_id()
	game._save_path = path
	check(game.save_game(), "elite trio saves")
	var restored = Rules.new(path)
	check(JSON.stringify(restored.state.enemies) == JSON.stringify(game.state.enemies), "elite lineup and metadata survive reload")
	game._save_path = ""
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	await ui_checks()
	var report := {"checks": checks, "failures": failures, "seeds_per_chapter": 24, "chapters": 4, "difficulties": [0, 2], "scope": "composition, current-chapter enemies, HP and damage scaling, deterministic saves, AOE, one-time settlement and UI fixtures"}
	var file := FileAccess.open("res://docs/evidence/experience-20261104/elite-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ELITE_RESULT=", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func ui_checks() -> void:
	for window in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = window
		var ui = load("res://tests/ui_shell.gd").new()
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(ui)
		ui.game = fixture()
		ui.menu_open = false
		ui._refresh()
		for frame in 4:
			await process_frame
		check(ui.combat_actors.size() == 4, "player plus elite and two escorts visible")
		for index in range(3):
			var button = ui.find_child("EnemyTarget_%d" % index, true, false)
			check(button != null and not button.disabled, "each enemy target enabled")
			button.pressed.emit()
			check(ui.selected_target == index, "each enemy can be selected")
			check(ui.overlay.find_child("EnemyDetailScroll", true, false) != null, "each enemy can be inspected")
			ui._clear(ui.overlay)
		check(ui.content.size.y <= ui.size.y - 40, "elite battle fits viewport")
		if capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/evidence/experience-20261104/elite-%dx%d.png" % [window.x, window.y]))
		ui.game.state.enemies[0].hp = 0
		ui._refresh()
		var defeated = ui.find_child("EnemyTarget_0", true, false)
		defeated.pressed.emit()
		check(ui.selected_target == 2 and ui.overlay.find_child("EnemyDetailScroll", true, false) != null, "defeated enemy can be inspected without changing target")
		ui._clear(ui.overlay)
		ui.queue_free()
		for frame in 4:
			await process_frame
