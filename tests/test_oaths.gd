extends SceneTree

const Rules = preload("res://core/game_engine.gd")
const Oaths = preload("res://core/oath_mechanics.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func fresh(role: String = "warden", seed_value: int = 47190, oath_id: String = "") -> Variant:
	var game = Rules.new("")
	game.profile.total_wins = 100
	game.profile.role_wins[role] = 100
	var started: Dictionary = game.new_run(role, seed_value, 0, "", oath_id)
	check(started.ok, "fixture starts " + role + " " + oath_id)
	return game


func enter(game, kind: String = "normal") -> void:
	game.state.chapter = 0
	game.state.row = 0
	game.state.lane = 0
	game.state.encounter_kind = kind
	game._start_battle(kind)


func run() -> void:
	_test_offers()
	_test_oath_effects()
	_test_battle_modifiers()
	_test_affixes()
	_test_shop_and_rest()
	_test_score()
	_test_daily()
	_test_save_roundtrip()
	print("OATHS_CHECKS=", checks, " FAILURES=", failures.size())
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _test_offers() -> void:
	var first: Array = Oaths.offers(729)
	var again: Array = Oaths.offers(729)
	check(first.size() == 3, "draft always offers three oaths")
	var ids: Array = []
	for entry in first:
		ids.append(entry.id)
	check(ids.size() == 3 and ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "draft has no duplicate oath")
	var repeated: Array = []
	for entry in again:
		repeated.append(entry.id)
	check(ids == repeated, "same seed drafts the same oaths")
	var other: Array = Oaths.offers(730)
	var different := false
	for entry in other:
		if not ids.has(entry.id):
			different = true
	check(different, "another seed can draft a different oath")
	var game = fresh()
	check(game.oath_view("blood").get("name", "") == "血誓", "oath view exposes name")
	check(game.oath_view("missing").is_empty(), "unknown oath view is empty")
	check(game.current_oath().is_empty(), "no oath by default")
	check(game.elite_affix_view().is_empty(), "no affix outside elite battle")


func _test_oath_effects() -> void:
	var base = fresh("warden", 11)
	var blood = fresh("warden", 11, "blood")
	check(int(blood.state.max_hp) == int(floor(float(base.state.max_hp) * 0.88)), "blood scales max hp by 12 percent")
	check(int(blood.state.hp) == int(blood.state.max_hp), "blood starts at the reduced maximum")
	check(blood.current_oath().get("id", "") == "blood", "current oath is stored")
	var scavenger = fresh("warden", 11, "scavenger")
	check(int(scavenger.state.gold) == 35, "scavenger starts with 35 gold")
	var no_oath = fresh("warden", 11)
	check(int(no_oath.state.gold) == 65, "plain run keeps 65 gold")
	check(not no_oath.new_run("warden", 11, 0, "", "missing").ok, "unknown oath cannot start a run")


func _test_battle_modifiers() -> void:
	var plain = fresh("warden", 21)
	enter(plain, "normal")
	var plain_energy := int(plain.state.energy)
	var plain_hand: int = plain.state.hand.size()
	var blood = fresh("warden", 21, "blood")
	enter(blood, "normal")
	check(int(blood.state.energy) == plain_energy + 1, "first turn oath grants one energy")
	var silence = fresh("warden", 21, "silence")
	enter(silence, "normal")
	check(silence.state.hand.size() == plain_hand + 1, "first turn oath draws one extra card")
	var iron = fresh("warden", 21, "iron")
	enter(iron, "normal")
	check(int(iron.state.block) >= 8, "iron oath starts with eight block")
	var ember = fresh("warden", 21, "ember")
	enter(ember, "normal")
	check(int(ember.state.status.get("strength", 0)) >= 1, "ember oath grants opening strength")
	check(int(ember._shop_price(100)) == 120, "ember oath taxes the shop twenty percent")


func _test_affixes() -> void:
	var first = fresh("warden", 909, "hunter")
	enter(first, "elite")
	check(not first.state.elite_affix.is_empty(), "elite battles roll an affix")
	check(first.elite_affix_view().get("id", "") == first.state.elite_affix, "affix view matches state")
	var second = fresh("warden", 909, "hunter")
	enter(second, "elite")
	check(first.state.elite_affix == second.state.elite_affix, "affix is deterministic for a seed and floor")
	var found := {}
	for seed_value in range(200):
		var game = fresh("warden", seed_value, "hunter")
		enter(game, "elite")
		found[game.state.elite_affix] = true
	check(found.size() >= 3, "affix pool rotates across seeds")
	var vigil_seed := -1
	var shroud_seed := -1
	var thorns_seed := -1
	for candidate in range(400):
		match str(Oaths.pick_affix(candidate).id):
			"vigil": vigil_seed = candidate if vigil_seed < 0 else vigil_seed
			"shroud": shroud_seed = candidate if shroud_seed < 0 else shroud_seed
			"thorns": thorns_seed = candidate if thorns_seed < 0 else thorns_seed
	var vigil = fresh("warden", vigil_seed, "hunter")
	enter(vigil, "elite")
	var main_block := 0
	var vigil_hp := 0
	var vigil_id := ""
	for enemy in vigil.state.enemies:
		if not bool(enemy.escort):
			main_block = int(enemy.block)
			vigil_hp = int(enemy.max_hp)
			vigil_id = str(enemy.id)
	check(main_block == 12, "vigil affix gives the elite twelve opening block")
	var hunter_scale := ceili(float(vigil.enemy_data(vigil_id).get("hp", 1)) * 1.20)
	check(vigil_hp == hunter_scale, "hunter oath raises elite max hp by twenty percent")
	var thorns = fresh("warden", thorns_seed, "hunter")
	enter(thorns, "elite")
	var main_thorns := 0
	for enemy in thorns.state.enemies:
		if not bool(enemy.escort):
			main_thorns = int(enemy.status.get("thorns", 0))
	check(main_thorns == 4, "thorns affix gives the elite four thorns")
	var shrouded = fresh("warden", shroud_seed, "hunter")
	enter(shrouded, "elite")
	var shroud_hp := 0
	var shroud_id := ""
	for enemy in shrouded.state.enemies:
		if not bool(enemy.escort):
			shroud_hp = int(enemy.max_hp)
			shroud_id = str(enemy.id)
	check(shroud_hp == ceili(float(shrouded.enemy_data(shroud_id).get("hp", 1)) * 1.45), "shroud stacks with the hunter oath on elite max hp")


func _test_shop_and_rest() -> void:
	var silence = fresh("warden", 31, "silence")
	silence.state.room = "rest"
	var blocked: Dictionary = silence.rest(-1)
	check(not blocked.ok, "silence oath refuses healing rest")
	var plain = fresh("warden", 31)
	plain.state.room = "rest"
	plain.state.hp = 10
	check(plain.rest(-1).ok, "plain run can rest")
	var iron = fresh("warden", 31, "iron")
	enter(iron, "normal")
	iron.state.hp = iron.state.max_hp
	iron.state.encounter_kind = "normal"
	iron._win_battle()
	check(int(iron.state.hp) == int(iron.state.max_hp) - 3, "iron oath costs three life after a win")
	check(int(iron.state.run_elites) == 0, "normal win does not count an elite")
	var hunter = fresh("warden", 31, "hunter")
	enter(hunter, "elite")
	hunter.state.hp = hunter.state.max_hp
	hunter.state.run_elites = 0
	hunter._win_battle()
	check(hunter.state.rewards.size() == 4, "hunter oath adds one extra elite reward")
	var last: Dictionary = hunter.state.rewards[hunter.state.rewards.size() - 1]
	check(hunter.card_data(str(last.id)).get("rarity", "") == "rare", "the extra hunter reward is rare")


func _test_score() -> void:
	var state := {"chapter": 1, "row": 5, "run_elites": 2, "run_bosses": 1, "gold": 50, "hp": 30, "difficulty": 3}
	check(Oaths.score(state, true) == 1300, "score formula counts depth, elites, boss, purse, life, difficulty and victory")
	check(Oaths.score(state, false) == 800, "defeat omits the victory bonus")
	var game = fresh("warden", 41)
	enter(game, "normal")
	game.state.hp = game.state.max_hp
	game._win_battle()
	check(int(game.state.score) == 0, "score stays zero until the run ends")
	game._finish_run(false)
	check(int(game.state.score) > 0, "finishing writes the score")


func _test_daily() -> void:
	var key := "2026-11-05"
	var view = Rules.new("").daily_view()
	check(str(view.get("key", "")).length() == 10, "daily view exposes a date key")
	check(not str(view.get("role", "")).is_empty(), "daily view picks a role")
	check(view.get("oath") is Dictionary and not view.get("oath").is_empty(), "daily view fixes an oath")
	check(view.get("modifier") is Dictionary and not view.get("modifier").is_empty(), "daily view fixes a twist")
	var one = Rules.new("")
	check(one.start_daily_run(key).ok, "daily journey starts")
	check(bool(one.state.daily) and one.state.daily_key == key, "daily state is stamped")
	# daily_view() 读取“今天”的日期键；这里用注入的 key 复算，避免跨日期运行测试时
	# 把注入日期的局和当天的变体相互比较。变体仅由日期键派生，与角色表无关。
	var expected_twist := str(Oaths.daily_setup(key, []).modifier.id)
	check(one.state.daily_modifier == expected_twist, "daily twist is stored")
	check(not str(one.state.daily_modifier).is_empty(), "daily twist is never empty")
	check(one.start_daily_run(key).ok, "same day daily can be continued")
	one._finish_run(false)
	var entry: Dictionary = one.profile.daily
	check(int(entry.attempts) == 1, "finishing records one daily attempt")
	check(int(entry.best) == int(one.state.score), "best score is recorded")
	check(int(entry.streak) == 1, "first daily starts a streak")
	check(one.profile.history[0].get("daily", false), "history marks the daily run")
	check(one.start_daily_run(key).ok, "daily can be retried")
	one._finish_run(false)
	check(int(one.profile.daily.attempts) == 2, "retry counts another attempt")
	check(int(one.profile.daily.streak) == 1, "same day retry keeps the streak")
	one.profile.daily.last_key = Oaths.previous_day(key)
	one.start_daily_run(key)
	one._finish_run(false)
	check(int(one.profile.daily.streak) == 2, "consecutive days extend the streak")
	var busy = fresh("warden", 51)
	check(not busy.start_daily_run(key).ok, "daily refuses to replace an active journey")
	check(not Rules.new("").start_daily_run("11-05").ok, "malformed daily key is rejected")
	var purse_key := ""
	for offset in range(20):
		var probe_key := Oaths.daily_key() if offset == 0 else "2026-11-%02d" % (offset + 1)
		var setup: Dictionary = Oaths.daily_setup(probe_key, ["warden", "ranger"])
		if str(setup.modifier.id) == "full_purse":
			purse_key = probe_key
			break
	if not purse_key.is_empty():
		var purse = Rules.new("")
		var setup: Dictionary = Oaths.daily_setup(purse_key, ["warden", "ranger"])
		purse.start_daily_run(purse_key)
		check(int(purse.state.gold) == 65 + int(setup.modifiers.get("gold_flat", 0)), "daily twist adds its starting gold")


func _test_save_roundtrip() -> void:
	var path := "user://oath_test_%d.json" % Time.get_ticks_usec()
	var writer = Rules.new(path)
	writer.new_run("warden", 61, 0, "", "ember")
	writer.save_game()
	var reader = Rules.new(path)
	check(reader.state.oath == "ember", "save keeps the oath id")
	check(int(reader.state.modifiers.get("shop_price_pct", 0)) == 20, "save keeps oath modifiers")
	check(reader.current_oath().get("name", "") == "余烬誓", "reloaded oath view resolves")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A v0.2.2 save has none of the oath fields; loading it must fill safe defaults.
	var legacy_path := "user://oath_legacy_%d.json" % Time.get_ticks_usec()
	var legacy_state: Dictionary = writer.state.duplicate(true)
	for key in ["oath", "modifiers", "daily", "daily_key", "daily_modifier", "elite_affix", "run_elites", "run_bosses", "score"]:
		legacy_state.erase(key)
	var legacy_profile: Dictionary = writer.profile.duplicate(true)
	legacy_profile.erase("daily")
	var envelope := {"save_version": 1, "content_version": str(writer.data.get("version", "")), "profile": legacy_profile, "state": legacy_state}
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	var migrated = Rules.new(legacy_path)
	check(migrated.state.get("oath", "x") == "", "legacy save gains an empty oath")
	check(migrated.state.get("modifiers") is Dictionary, "legacy save gains modifier defaults")
	check(migrated.profile.get("daily") is Dictionary, "legacy save gains a daily record")
	check(int(migrated.profile.daily.get("best", -1)) == 0, "legacy daily best starts at zero")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
