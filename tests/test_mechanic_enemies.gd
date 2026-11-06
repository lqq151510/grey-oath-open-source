extends SceneTree

const Rules = preload("res://core/game_engine.gd")
const MECHANIC_IDS = ["ch1_bellsmith", "ch2_armor_priest", "ch3_star_arbiter", "ch4_oath_mender"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func encounter(chapter: int):
	var game = Rules.new("")
	for seed_value in range(64):
		game.state.active = false
		game.new_run("warden", seed_value)
		game.state.chapter = chapter
		game.enter_node(0)
		for enemy in game.state.enemies:
			if enemy.id == MECHANIC_IDS[chapter]:
				check(game.state.room == "battle" and game.state.encounter_kind == "normal", "%s enters through a normal map node" % enemy.id)
				game.state.enemies = [enemy]
				game._update_intents()
				return game
	check(false, "chapter %d specialist appears in the normal pool" % (chapter + 1))
	return null


func run() -> void:
	for chapter in range(MECHANIC_IDS.size()):
		var game = encounter(chapter)
		if game == null:
			continue
		match chapter:
			0: test_bellsmith(game)
			1: test_priest(game)
			2: test_arbiter(game)
			3: test_mender(game)
	test_legacy_battle()
	print("MECHANIC_ENEMIES_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func test_bellsmith(game) -> void:
	var enemy: Dictionary = game.state.enemies[0]
	game.end_turn()
	check("攻击 13" in enemy.intent and "可打断" in enemy.intent, "bellsmith announces its next interruptible attack")
	game._damage_enemy(0, int(enemy.block))
	game._update_intents()
	check("可打断" in enemy.intent, "fully blocked damage does not interrupt the bellsmith")
	game.state.hand = [{"id": "warden_01", "upgraded": false}]
	game.play_card(0, 0)
	check("已打断" in enemy.intent and "攻击" not in enemy.intent, "an actual attack refreshes the interrupted intent")
	var restored = round_trip(game)
	if restored != null:
		var hp := int(restored.state.hp)
		restored.end_turn()
		check(int(restored.state.hp) == hp, "an interrupted attack stays canceled after load")
		check(not restored.state.enemies[0].has("hurt_this_turn"), "new player turn clears the interrupt marker")
	enemy.erase("hurt_this_turn")
	enemy.hp = enemy.max_hp
	enemy.status.poison = 1
	enemy.status.regen = 2
	game._update_intents()
	check("中毒将打断" in enemy.intent, "intent anticipates poison that resolves before the bell strike")
	var hp := int(game.state.hp)
	game.end_turn()
	check(int(game.state.hp) == hp and int(enemy.hp) == int(enemy.max_hp), "poison interrupts even if regeneration restores the damage")
	enemy.turn = 1
	game._update_intents()
	check("攻击 13" in enemy.intent, "the next charge can attack once the previous interrupt has cleared")
	game.end_turn()
	check(int(game.state.hp) == hp - 13, "an unbroken charge attacks for its previewed damage")


func test_priest(game) -> void:
	var enemy: Dictionary = game.state.enemies[0]
	game.state.block = 6
	game.state.status.vulnerable = 1
	game._update_intents()
	check("破甲 4" in enemy.intent and "攻击 8" in enemy.intent, "priest announces the shield strip and chapter-scaled attack after expiring vulnerability")
	var hp := int(game.state.hp)
	var result: Dictionary = game.end_turn()
	check(int(game.state.hp) == hp - 6, "priest removes four block before the chapter-scaled attack consumes the remaining two")
	check(result.ok and game.combat_events.any(func(event): return event.get("style") == "sunder" and int(event.amount) == 4), "actual shield loss is emitted for the presentation layer")


func test_arbiter(game) -> void:
	var enemy: Dictionary = game.state.enemies[0]
	game.state.hand = []
	game.state.energy = 8
	for ignored in range(7):
		game.state.hand.append({"id": "warden_02", "upgraded": false})
	for played in range(1, 8):
		game.play_card(0)
		var extra := 2 * clampi(played - 3, 0, 3)
		var chapter_scaled_base := 9 + int(game.state.chapter)
		check(("攻击 %d" % (chapter_scaled_base + extra)) in enemy.intent, "arbiter updates after %d skill plays with chapter scaling" % played)
	var restored = round_trip(game)
	if restored != null:
		restored._update_intents()
		var expected_attack := 9 + int(restored.state.chapter) + 6
		check(("攻击 %d" % expected_attack) in restored.state.enemies[0].intent, "arbiter preserves this turn's card count on reload")
		restored.state.block = 0
		var hp := int(restored.state.hp)
		restored.end_turn()
		check(int(restored.state.hp) == hp - expected_attack and int(restored.state.cards_played_this_turn) == 0, "arbiter uses the same capped bonus as intent, then the counter resets")


func test_mender(game) -> void:
	var mender: Dictionary = game.state.enemies[0]
	var ally: Dictionary = mender.duplicate(true)
	var wounded: Dictionary = mender.duplicate(true)
	ally.hp = int(ally.max_hp) - 4
	wounded.hp = int(wounded.max_hp) - 14
	ally.pattern = []
	wounded.pattern = []
	game.state.enemies = [mender, ally, wounded]
	game._update_intents()
	check("治疗同伴 11" in mender.intent, "mender announces healing when a companion is wounded")
	game.end_turn()
	check(int(wounded.max_hp) - int(wounded.hp) == 3 and int(ally.max_hp) - int(ally.hp) == 4, "mender heals the largest missing health pool")
	mender.turn = 0
	ally.hp = ally.max_hp
	wounded.hp = 0
	game._update_intents()
	check("格挡 7" in mender.intent and "治疗" not in mender.intent, "mender forecasts fallback block when there is no eligible ally")
	game.end_turn()
	check(int(mender.block) == 7 and int(wounded.hp) == 0, "fallback gives seven block and never revives a defeated companion")


func test_legacy_battle() -> void:
	var game = Rules.new("")
	game.new_run("warden", 42)
	game.enter_node(0)
	game.state.enemies = game.state.enemies.filter(func(enemy): return enemy.id not in MECHANIC_IDS)
	check(not game.state.enemies.is_empty(), "legacy fixture contains a conventional enemy")
	game.state.erase("cards_played_this_turn")
	for enemy in game.state.enemies:
		enemy.erase("hurt_this_turn")
	var expected := JSON.stringify(game.state.enemies)
	var restored = round_trip(game)
	if restored != null:
		check(JSON.stringify(restored.state.enemies) == expected, "older battle roster and action patterns load unchanged")
		check(restored.end_turn().ok, "legacy encounter resolves without new turn fields")


func round_trip(game):
	var path := "user://test-mechanic-enemies-%d.json" % OS.get_process_id()
	game._save_path = path
	var saved: bool = game.save_game()
	game._save_path = ""
	check(saved, "new battle state saves")
	var restored = Rules.new(path)
	restored._save_path = ""
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	check(restored.state.room == "battle", "new battle state reloads")
	return restored if restored.state.room == "battle" else null
