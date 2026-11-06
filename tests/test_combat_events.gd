extends SceneTree
## Isolated rules tests: no default player save, rendering, or model service.

const Rules = preload("res://core/game_engine.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func fixture(script = Rules):
	var game = script.new("")
	game.new_run("warden", 42)
	game.state.run_id = "combat-event-fixture"
	game.enter_node(1)
	game.state.enemies = [{"id": "fixture", "name": "测试敌人", "hp": 100, "max_hp": 100, "block": 0, "status": {}, "pattern": [{"intent": "等待", "effects": []}], "turn": 0, "intent": "等待", "color": "#c7a66a"}]
	game.state.hp = 50
	game.state.max_hp = 80
	game.state.block = 0
	game.state.status = {}
	game.state.relics = []
	return game


func card(game, effects: Array) -> Dictionary:
	game._indexes.cards["combat_test"] = {"id": "combat_test", "name": "反馈测试", "cost": 0, "type": "attack", "effects": effects}
	game.state.hand = [{"id": "combat_test", "upgraded": false}]
	return game.play_card(0, 0)


func matching(game, kind: String, source: String = "") -> Array:
	var result: Array = []
	for event in game.combat_events:
		if event.kind == kind and (source.is_empty() or event.source == source):
			result.append(event)
	return result


func _run() -> void:
	var game = fixture()
	game.state.enemies[0].block = 6
	check(card(game, [{"op": "damage", "value": 10}]).ok, "public card action succeeds")
	var damage = matching(game, "damage")[0]
	check(damage.amount == 4 and damage.blocked == 6, "partial block reports actual HP and absorption separately")
	check(damage.source == "player" and damage.target == "enemy:0", "player attack identifies stable target slot")
	check(game.state.enemies[0].hp == 96, "event recording does not add a second hit")
	game.state.enemies[0].block = 20
	card(game, [{"op": "damage", "value": 6}])
	damage = matching(game, "damage")[0]
	check(damage.amount == 0 and damage.blocked == 6, "fully absorbed attack still has a hit event")
	check(matching(game, "damage").size() == 1, "events reset for each action")
	var unchanged = JSON.stringify(game.state)
	check(not game.play_card(99, 0).ok and game.combat_events.is_empty(), "failed card clears previous feedback")
	check(JSON.stringify(game.state) == unchanged, "failed card has no rule side effect")

	game = fixture()
	for ignored in range(2):
		game.state.enemies.append(game.state.enemies[0].duplicate(true))
	card(game, [{"op": "damage", "value": 3, "hits": 2, "target": "all"}])
	var hits = matching(game, "damage")
	check(hits.size() == 6, "two-hit area attack records all six actual hits")
	check(hits[0].target == "enemy:0" and hits[2].target == "enemy:2" and hits[3].target == "enemy:0", "area hit order follows rules")
	check(game.state.enemies[2].hp == 94, "area damage remains exact")

	game = fixture()
	game.state.enemies[0].status.thorns = 4
	game.state.block = 1
	card(game, [{"op": "damage", "value": 5}])
	var reflected = matching(game, "damage", "thorns")
	check(reflected.size() == 1 and reflected[0].target == "player", "enemy thorns emits distinct source")
	check(reflected[0].amount == 3 and reflected[0].blocked == 1, "thorns reports actual blocked damage")
	check(game.combat_events[0].source == "player" and game.combat_events[1].source == "thorns", "attack precedes its retaliation")

	game = fixture()
	game.state.enemies[0].hp = 2
	game.state.enemies[0].status.poison = 9
	game.end_turn()
	damage = matching(game, "damage", "poison")[0]
	check(damage.amount == 2 and damage.style == "poison", "lethal poison clamps text to actual remaining HP")
	check(matching(game, "death").size() == 1 and matching(game, "death")[0].target == "enemy:0", "enemy death emitted once")
	check(game.state.room == "reward" and matching(game, "damage", "enemy:0").is_empty(), "poison-killed enemy never attacks")
	check(not game.end_turn().ok and game.combat_events.is_empty(), "invalid end-turn clears stale death events")

	game = fixture()
	game.state.summons = [{"power": 4, "turns": 3}]
	game.state.enemies[0].status.poison = 2
	game.state.enemies[0].pattern[0].effects = [{"op": "damage", "value": 5, "hits": 2}]
	game.state.enemies.append(game.state.enemies[0].duplicate(true))
	game.state.enemies[1].status = {}
	game.state.enemies[1].pattern[0].effects = [{"op": "damage", "value": 7}]
	game.state.block = 3
	game.state.status.poison = 2
	game.state.status.regen = 3
	game.end_turn()
	hits = matching(game, "damage")
	check(hits.size() == 6, "summon, poison, three enemy hits, and player poison are separate")
	check(hits[0].source == "summon:0" and hits[0].style == "projectile", "summon uses its own source and projectile style")
	check(hits[1].source == "poison" and hits[1].target == "enemy:0", "enemy poison follows summon")
	check(hits[2].source == "enemy:0" and hits[2].amount == 2 and hits[2].blocked == 3, "enemy first hit absorbs player block")
	check(hits[3].amount == 5 and hits[4].source == "enemy:1", "second hit and next enemy preserve attribution")
	check(hits[5].source == "poison" and hits[5].target == "player", "player poison follows all enemy actions")
	check(matching(game, "heal")[0].amount == 3 and game.state.hp == 37, "regen is separate from damage instead of net HP text")

	game = fixture()
	game.state.status.thorns = 3
	game.state.enemies[0].pattern[0].effects = [{"op": "damage", "value": 4}]
	game.end_turn()
	check(matching(game, "damage", "thorns")[0].target == "enemy:0", "player thorns targets attacking enemy")

	game = fixture()
	game.state.hp = 79
	game.state.enemies[0].hp = 3
	card(game, [{"op": "lifesteal", "value": 20}])
	check(matching(game, "damage")[0].amount == 3, "overkill damage uses remaining HP")
	check(matching(game, "heal")[0].amount == 1, "lifesteal text respects player healing cap")
	check(matching(game, "death").size() == 1, "overkill has one death event")

	game = fixture()
	game.state.hp = 2
	card(game, [{"op": "self_damage", "value": 5}, {"op": "heal", "value": 10}])
	check(matching(game, "damage", "self")[0].amount == 2, "self damage bypasses shields and clamps to HP")
	check(game.state.room == "defeat" and matching(game, "heal").is_empty(), "lethal self damage stops subsequent healing")
	check(matching(game, "death").size() == 1 and matching(game, "death")[0].target == "player", "player death event available after room transition")

	game = fixture()
	card(game, [{"op": "block", "value": 8}, {"op": "poison", "value": 3}])
	check(matching(game, "block")[0].amount == 8, "shield gain uses block event")
	check(matching(game, "status")[0].style == "poison" and matching(game, "status")[0].target == "enemy:0", "status application is not misrepresented as immediate damage")
	game.state.potions = ["combat_potion"]
	game._indexes.potions["combat_potion"] = {"id": "combat_potion", "name": "反馈药剂", "effects": [{"op": "damage", "value": 7}]}
	check(game.use_potion(0, 0).ok and matching(game, "damage")[0].amount == 7, "potion uses same actual damage contract")
	check(not game.use_potion(0, 0).ok and game.combat_events.is_empty(), "failed potion clears previous feedback")
	game._damage_enemy(0, 1)
	check(game.combat_events.is_empty(), "out-of-action rule helpers do not append stale feedback")
	check(not game.state.has("combat_events"), "feedback is not part of persistent state")
	_test_save()
	if OS.get_cmdline_user_args().has("--baseline"):
		_test_baseline()
	var report = {"checks": checks, "failures": failures, "scope": "isolated event ordering, actual damage, persistence, optional before-change rule comparison"}
	print("COMBAT_EVENT_RESULT=" + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _test_save() -> void:
	var game = Rules.new("")
	game.new_run("warden", 42)
	game.enter_node(1)
	var path = "user://combat-events-test-%d.json" % Time.get_ticks_usec()
	game._save_path = path
	game.play_card(0, 0)
	var saved = FileAccess.get_file_as_string(path)
	check(not saved.contains("combat_events") and not saved.contains("_combat_recording"), "save JSON excludes transient presentation data")
	var reloaded = Rules.new(path)
	check(reloaded.combat_events.is_empty(), "loading never replays previous combat effects")
	check(JSON.stringify(reloaded.state.rng_states) == JSON.stringify(game.state.rng_states), "save/reload preserves rule RNG")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _test_baseline() -> void:
	var source = "res://.state/backups/combat-effects-20261103/core/game_engine.gd"
	check(FileAccess.file_exists(source), "before-change engine backup exists for differential check")
	if not FileAccess.file_exists(source):
		return
	var original = GDScript.new()
	original.source_code = FileAccess.get_file_as_string(source)
	check(original.reload() == OK, "before-change engine compiles")
	for effects in [
		[{"op": "damage", "value": 7, "hits": 3}],
		[{"op": "damage", "value": 6, "target": "all"}],
		[{"op": "lifesteal", "value": 20}],
		[{"op": "self_damage", "value": 5}, {"op": "heal", "value": 10}],
		[{"op": "block", "value": 7}, {"op": "poison", "value": 5}],
		[{"op": "summon", "value": 4}, {"op": "thorns", "value": 3}],
	]:
		var before = fixture(original)
		var after = fixture()
		for instance in [before, after]:
			instance.state.enemies[0].pattern[0].effects = [{"op": "damage", "value": 7, "hits": 2}]
			instance.state.enemies[0].status = {"thorns": 2, "regen": 1}
			instance.state.enemies.append(instance.state.enemies[0].duplicate(true))
			card(instance, effects)
			instance.end_turn()
		check(JSON.stringify(before.state) == JSON.stringify(after.state), "events preserve complete rules and RNG: " + str(effects[0].op))
		check(JSON.stringify(before.profile) == JSON.stringify(after.profile), "events preserve profile: " + str(effects[0].op))
