extends SceneTree

const EngineScript = preload("res://core/game_engine.gd")
var checks = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _json_equal(left: Variant, right: Variant) -> bool:
	# JSON numbers reload as floats; normalize both sides without dropping any fields.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func game(role: String = "warden", seed_value: int = 42):
	var instance = EngineScript.new("")
	instance.profile.total_wins = 999
	for definition in instance.data.get("roles", []):
		instance.profile.role_wins[definition.id] = 999
		instance.profile.ascension[definition.id] = 5
	instance.new_run(role, seed_value)
	return instance


func battle(role: String = "warden"):
	var instance = game(role)
	instance.enter_node(1)
	return instance


func _run() -> void:
	var base = EngineScript.new("")
	check(base.data.get("cards", []).size() == 290, "catalog has 290 independently defined cards")
	check(base.data.get("roles", []).size() == 7, "catalog has 7 roles")
	check(base.data.get("enemies", []).size() == 56, "catalog has 56 enemies")
	check(base.data.get("relics", []).size() == 62, "catalog has 62 relics")
	check(base.data.get("potions", []).size() == 15, "catalog has 15 potions")
	check(base.data.get("events", []).size() == 40, "catalog has 40 events")
	check(base.data.get("chapters", []).size() == 4, "catalog has 4 chapters")
	if base.data.get("cards", []).is_empty():
		_finish()
		return
	_test_content(base)
	_test_unlocks()
	_test_cards()
	_test_rules()
	_test_rooms()
	_test_random_and_save()
	_test_full_routes()
	_finish()


func _test_content(base) -> void:
	var ids = {}
	var counts = {}
	for card in base.data.cards:
		check(not ids.has(card.id), "unique card ID: " + str(card.id))
		ids[card.id] = true
		counts[card.role] = int(counts.get(card.role, 0)) + 1
		check(not str(card.get("name", "")).is_empty() and not str(card.get("description", "")).is_empty(), "card has complete text: " + str(card.id))
		check(not card.get("effects", []).is_empty(), "card has effects: " + str(card.id))
		check(not card.get("upgrade_effects", []).is_empty(), "card has upgrade effects: " + str(card.id))
		for effect in card.get("effects", []) + card.get("upgrade_effects", []):
			check(EngineScript.EFFECT_OPS.has(str(effect.op)), "supported effect: " + str(card.id) + "/" + str(effect.op))
	for role in base.data.roles:
		var pool_size := 20 if role.id in ["bellscribe", "ashlamper"] else 44
		check(int(counts.get(role.id, 0)) == pool_size, "%d unique cards for %s" % [pool_size, role.id])
		check(role.starter_cards.size() == 10, "10 starter instances for " + str(role.id))
		for id in role.starter_cards:
			check(not base.card_data(str(id)).is_empty(), "starter reference exists")
	check(int(counts.get("neutral", 0)) == 30, "30 neutral cards")
	for event in base.data.events:
		for choice in event.choices:
			if choice.has("card"):
				check(not base.card_data(str(choice.card)).is_empty(), "event card reference exists")
			if choice.has("relic"):
				check(not base.relic_data(str(choice.relic)).is_empty(), "event relic reference exists")


func _test_unlocks() -> void:
	var instance = EngineScript.new("")
	check(instance.is_role_unlocked("warden"), "warden unlocked at first launch")
	for role in instance.data.roles:
		check(instance.is_role_unlocked(str(role.id)), "all roles available for playtesting")
	check(not instance.new_run("missing", 1).ok, "unknown role cannot start")
	check(instance.new_run("warden", 1).ok, "starter role starts")
	var before = JSON.stringify(instance.state)
	check(not instance.new_run("warden", 2).ok, "active run cannot be overwritten")
	check(JSON.stringify(instance.state) == before, "reject new run without mutation")
	check(not instance.enter_node(8).ok, "invalid lane rejected")
	check(JSON.stringify(instance.state) == before, "invalid lane causes no state mutation")
	instance.enter_node(0)
	var unlocked_at_start = instance.state.unlocked_snapshot.duplicate()
	for ignored in range(3):
		instance.state.room = "battle"
		instance.state.active = true
		instance.state.battle_rewarded = false
		instance.state.row = ignored
		for enemy in instance.state.enemies:
			enemy.hp = 0
		instance._check_battle_end()
		var wins = int(instance.profile.total_wins)
		instance._check_battle_end()
		check(int(instance.profile.total_wins) == wins, "win settlement idempotent")
	check(instance.is_role_unlocked("ranger"), "three wins unlock ranger")
	check(instance.state.unlocked_snapshot == unlocked_at_start, "new card unlock eligibility applies next run")
	instance.abandon_run()
	check(int(instance.profile.total_wins) == 3, "abandon keeps permanent wins")
	check(instance.new_run("ranger", 44).ok, "unlocked ranger can start")
	check(not instance.new_run("arcanist", 45).ok, "active journey still cannot be overwritten by another role")


func _test_cards() -> void:
	var template = game()
	var tested = 0
	for definition in template.data.cards:
		for upgraded in [false, true]:
			var role = str(definition.role) if definition.role != "neutral" else "warden"
			var instance = battle(role)
			instance.state.max_hp = 1000
			instance.state.hp = 900
			instance.state.energy = 100
			instance.state.souls = 100
			instance.state.stars = 100
			instance.state.osty_hp = 100
			instance.state.block = 20
			instance.state.hand = [{"id": str(definition.id), "upgraded": upgraded}]
			instance.state.enemies[0].hp = 100000
			instance.state.enemies[0].max_hp = 100000
			var result = instance.play_card(0, 0)
			check(result.ok, "card executes: %s%s" % [definition.id, "+" if upgraded else ""])
			check(int(instance.state.hp) >= 0 and int(instance.state.energy) >= 0, "card maintains nonnegative resources")
			tested += 1
	print("CARD_EXECUTIONS=" + str(tested))


func _test_rules() -> void:
	var instance = battle()
	var before = JSON.stringify(instance.state)
	check(not instance.play_card(-1).ok, "negative hand index rejected")
	check(not instance.play_card(100).ok, "out of range hand index rejected")
	check(before == JSON.stringify(instance.state), "invalid card indices leave all state untouched")
	instance.state.energy = 0
	var expensive = -1
	for i in range(instance.state.hand.size()):
		if int(instance.card_view(instance.state.hand[i]).cost) > 0:
			expensive = i
			break
	if expensive >= 0:
		before = JSON.stringify(instance.state)
		check(not instance.play_card(expensive).ok, "insufficient energy rejected")
		check(before == JSON.stringify(instance.state), "insufficient energy does not consume card")
	check(instance.calculate_damage(10, {"strength": 2, "weak": 1}, {"vulnerable": 1}) == 13, "strength weak vulnerable round once at end")
	instance.state.enemies[0].hp = 20
	instance.state.enemies[0].block = 8
	check(instance._damage_enemy(0, 10, false) == 2, "block absorbs damage before HP")
	check(int(instance.state.enemies[0].hp) == 18, "HP damage exact")
	instance.state.enemies[0].block = 100
	instance.state.hp = 40
	instance._player_effect({"op": "lifesteal", "value": 6}, 0)
	check(int(instance.state.hp) == 40, "lifesteal does not heal absorbed damage")
	instance.state.block = 12
	instance.state.hp = 40
	instance._player_effect({"op": "self_damage", "value": 4}, 0)
	check(int(instance.state.hp) == 36 and int(instance.state.block) == 12, "self damage bypasses block")
	instance.state.status = {"weak": 2, "vulnerable": 2, "poison": 3, "strength": 4}
	instance._player_effect({"op": "cleanse", "value": 0}, 0)
	check(int(instance.state.status.poison) == 0 and int(instance.state.status.strength) == 4, "cleanse removes debuffs and preserves strength")
	instance.state.hand = []
	instance._draw_cards(30)
	check(instance.state.hand.size() <= 10, "hand hard cap ten")
	instance.state.summons = []
	for value in [3, 4, 5, 6]:
		instance._player_effect({"op": "summon", "value": value}, 0)
	check(instance.state.summons.size() == 3, "summon cap three")
	instance.state.marks = []
	instance.state.block = 0
	for mark in [1, 3, 2]:
		instance._player_effect({"op": "mark", "value": mark}, 0)
	check(instance.state.marks.is_empty() and int(instance.state.block) == 12, "third moon mark resolves twelve block and clears sequence")
	var sister = battle("sister")
	sister.state.hp = 1
	sister._player_effect({"op": "self_damage", "value": 1}, 0)
	check(sister.state.room == "defeat" and not sister.state.active, "lethal blood cost resolves death before passive healing")
	var medium = battle("medium")
	check(int(medium.state.osty_hp) == 1 and int(medium.state.souls) == 0, "necrobinder summons Osty; Souls are cards rather than a passive currency")
	var poison = battle()
	poison.state.enemies = [poison.state.enemies[0]]
	poison.state.enemies[0].hp = 2
	poison.state.enemies[0].block = 100
	poison.state.enemies[0].status.poison = 3
	poison.end_turn()
	check(poison.state.room == "reward", "poison bypasses block and ends combat before dead enemy acts")
	var retained = battle()
	retained.state.enemies[0].hp = 10000
	retained.state.enemies[0].pattern = [{"intent": "等待", "effects": []}]
	retained.state.status.next_energy = 2
	retained.end_turn()
	check(int(retained.state.energy) == 5 and int(retained.state.status.next_energy) == 0, "next turn energy consumed exactly once")


func _test_rooms() -> void:
	var instance = game()
	for row in instance.state.map:
		check(row.size() == 3, "all map rows have 3 connected candidates")
	instance.state.map[0][1].kind = "shop"
	instance.enter_node(1)
	instance.state.gold = 1000
	var initial_deck = instance.state.deck.size()
	check(instance.buy_item(0).ok, "shop purchase succeeds")
	check(instance.state.deck.size() == initial_deck + 1, "shop card added once")
	var after = JSON.stringify(instance.state)
	check(not instance.buy_item(0).ok and after == JSON.stringify(instance.state), "sold item cannot duplicate")
	var removal = instance.state.shop.size() - 1
	var gold = int(instance.state.gold)
	instance.buy_item(removal)
	check(int(instance.state.gold) == gold, "selecting removal service does not charge yet")
	check(instance.remove_card(0).ok, "remove chosen card")
	check(instance.state.deck.size() == initial_deck, "removal removes exactly one copy")
	instance.leave_room()
	instance.state.map[1][1].kind = "rest"
	instance.enter_node(1)
	check(instance.rest(0).ok and instance.state.deck[0].upgraded, "rest upgrades selected card")
	check(not instance.rest(1).ok, "rest cannot be used twice")
	instance.state.map[2][1].kind = "event"
	instance.enter_node(1)
	instance.state.event = {"id": "test", "name": "test", "choices": [{"label": "pay", "gold": -9999}, {"label": "gift", "gold": 8}]}
	after = JSON.stringify(instance.state)
	check(not instance.choose_event(0).ok and after == JSON.stringify(instance.state), "unaffordable event has no side effects")
	instance.state.event.choices.append({"label": "duplicate relic", "gold": -40, "hp": -3, "max_hp": -2, "heal": 4, "card": instance.state.deck[0].id, "relic": instance.state.relics[0]})
	after = JSON.stringify(instance.state)
	var profile_before = JSON.stringify(instance.profile)
	var duplicate_result = instance.choose_event(2)
	check(not duplicate_result.ok and duplicate_result.message.contains("已拥有"), "event refuses already owned relic with a clear reason")
	check(after == JSON.stringify(instance.state) and profile_before == JSON.stringify(instance.profile), "duplicate relic event changes no resources, cards, progress, or room")
	check(instance.choose_event(1).ok and instance.state.room == "map", "event choice resolves and leaves room")
	check(not instance.choose_event(1).ok, "event cannot settle twice")


func _test_random_and_save() -> void:
	var left = game("warden", 12087)
	var right = game("warden", 12087)
	check(left.state.map == right.state.map, "same seed gives same map")
	left.enter_node(1)
	right.enter_node(1)
	check(left.state.hand == right.state.hand and left.state.enemies == right.state.enemies, "same seed gives same enemies and shuffled hand")
	var save_path = "res://tests/output/test-save.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	left._save_path = save_path
	check(left.save_game(), "atomic save succeeds")
	var envelope = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(left._valid_save(envelope), "serialized numeric content version remains compatible")
	var incompatible = envelope.duplicate(true)
	incompatible.content_version = "incompatible-version"
	check(not left._valid_save(incompatible), "different content version is still rejected")
	incompatible.content_version = int(left.data.version) + 1
	check(not left._valid_save(incompatible), "different numeric content version is still rejected")
	var loaded = EngineScript.new(save_path)
	check(_json_equal(loaded.state, left.state) and _json_equal(loaded.profile, left.profile), "all game and profile state survives serialization")
	check(loaded.state.rng_states == left.state.rng_states, "saved RNG states survive serialization exactly")
	left.end_turn()
	loaded.end_turn()
	check(_json_equal(left.state, loaded.state), "next turn after reload has identical game state")
	check(left.state.rng_states == loaded.state.rng_states, "next turn after reload has identical exact RNG states")
	check(loaded.save_game(), "second save produces backup")
	check(FileAccess.file_exists(save_path + ".bak"), "previous save backup exists")
	var corrupt = FileAccess.open(save_path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var recovered = EngineScript.new(save_path)
	check(not recovered.state.deck.is_empty() and recovered.last_error.contains("备份"), "corrupt main save restores last valid backup")
	for suffix in ["", ".bak", ".tmp"]:
		var absolute = ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _test_full_routes() -> void:
	# Fixture-powered flow traversal verifies transitions, NOT difficulty or balance.
	var base = EngineScript.new("")
	for definition in base.data.roles:
		var role := str(definition.id)
		var instance = game(role, 777)
		var rooms = 0
		while instance.state.active and rooms < 300:
			rooms += 1
			match instance.state.room:
				"map":
					var available = instance.available_nodes()
					check(not available.is_empty(), "route has a reachable next node")
					if available.is_empty(): break
					instance.enter_node(int(available[0]))
				"battle":
					for enemy in instance.state.enemies:
						enemy.hp = 0
					instance._check_battle_end()
				"reward": instance.choose_reward(0)
				"rest": instance.rest()
				"shop", "treasure": instance.leave_room()
				"event":
					var chosen = false
					for i in range(instance.state.event.choices.size()):
						if instance.choose_event(i).ok:
							chosen = true
							break
					check(chosen, "event has at least one affordable exit")
				_: break
		check(instance.state.room == "victory", "four-chapter state-machine fixture completes for " + role)
		check(int(instance.profile.ascension.get(role, 0)) >= 1, "victory preserves progression for " + role)
		check(instance.profile.history.size() == 1, "exactly one history record")
		var wins = int(instance.profile.total_wins)
		instance._finish_run(true)
		check(int(instance.profile.total_wins) == wins and instance.profile.history.size() == 1, "repeated end state is idempotent")


func _finish() -> void:
	var result = {"checks": checks, "failures": failures, "scope": "rules/content/save/state transitions; fixture routes are not balance or manual play evidence"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file = FileAccess.open("res://tests/output/engine-results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
	print("ENGINE_TEST_RESULT=" + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
