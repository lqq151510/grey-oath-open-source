extends SceneTree

const Rules = preload("res://core/game_engine.gd")
const Guides = preload("res://core/build_guides.gd")
const OUTPUT = "res://docs/evidence/build-guides-20261104"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func card(id: String) -> Dictionary:
	return {"id": id, "upgraded": false}


func fixture(role: String = "ranger", kind: String = "normal", chapter: int = 0, unlocked: bool = true):
	var g = Rules.new("")
	if unlocked:
		g.profile.total_wins = 100
		g.profile.role_wins[role] = 100
	check(g.new_run(role, 47190).ok, "fixture starts " + role)
	g.state.chapter = chapter
	check(g.enter_node(1).ok, "fixture enters battle")
	g.state.encounter_kind = kind
	g._win_battle()
	g._commit("fixture")
	return g


func snapshot(g) -> Dictionary:
	# RNG 现在由 core/random_streams.gd 持有；snapshot() 是它的实时状态视图。
	return {"state": g.state.duplicate(true), "profile": g.profile.duplicate(true), "rng": g._random.snapshot()}


func reject_refresh(g, index: int, label: String) -> void:
	var before := snapshot(g)
	check(not g.reroll_reward(index).ok, label + " rejected")
	check(before == snapshot(g), label + " leaves state, profile and RNG intact")


func test_plans() -> void:
	var g = Rules.new("")
	var plan_count := 0
	for role in g.data.roles:
		var options: Array = g.build_plan_options(str(role.id))
		check(options[0].id == "", "free choice is the default: " + str(role.id))
		check(options.size() >= 3, "each traveler has at least two build paths: " + str(role.id))
		var ids: Array = []
		for plan in options:
			check(not ids.has(plan.id), "unique build id within role")
			ids.append(plan.id)
			if str(plan.id).is_empty():
				continue
			plan_count += 1
			var early_core := 0
			for definition in g.data.cards:
				if definition.role != role.id or definition.rarity == "starter" or int(definition.get("min_chapter", 0)) > 0 or int(definition.get("unlock_wins", 0)) > 0:
					continue
				if Guides.recommend(definition, str(role.id), str(plan.id)).tier == "core":
					early_core += 1
			check(early_core > 0, "build has obtainable first-chapter core cards: %s/%s" % [role.id, plan.id])
	check(plan_count == 18, "all 18 build paths are present")
	check(Guides.affinity_score(1, 0) > Guides.affinity_score(0, 100), "generic support never outranks a core match")
	check(Guides.affinity_score(-1, -1) == 0, "affinity cannot become negative")
	var examples := [
		["warden", "strength", "warden_13"], ["warden", "exhaust", "warden_08"], ["warden", "bastion", "warden_12"],
		["ranger", "poison", "ranger_06"], ["ranger", "shiv", "ranger_05"], ["ranger", "discard", "ranger_08"],
		["sister", "lightning", "sister_12"], ["sister", "frost", "sister_11"], ["sister", "dark", "sister_08"],
		["arcanist", "stars", "arcanist_12"], ["arcanist", "blade", "arcanist_06"],
		["medium", "osty", "medium_07"], ["medium", "doom", "medium_09"], ["medium", "souls", "medium_05"],
		["bellscribe", "echo_strike", "bellscribe_09"], ["bellscribe", "echo_guard", "bellscribe_11"],
		["ashlamper", "ignite", "ashlamper_08"], ["ashlamper", "wildfire", "ashlamper_10"],
	]
	for example in examples:
		var recommendation := Guides.recommend(g.card_data(example[2]), example[0], example[1])
		check(recommendation.tier == "core" and not str(recommendation.reason).is_empty(), "mechanics justify recommendation: " + example[2])
	check(Guides.recommend(g.card_data("ashlamper_10"), "ashlamper", "ignite").tier != "core", "group ignition is distinct from focused ignition")
	check(Guides.recommend(g.card_data("ranger_05"), "ranger", "poison").tier != "core", "small knives are not falsely labeled poison core")
	var automatic := Guides.recommend(g.card_data("ranger_06"), "ranger", "")
	check(automatic.source == "automatic" and automatic.plan_id == "poison" and automatic.tier == "core", "free build still shows an explainable automatic recommendation")
	var inferred := Guides.inferred_plan("ranger", [g.card_view(card("ranger_05"))])
	check(inferred.plan.id == "shiv", "automatic direction follows the current deck's strongest core tag")


func test_optional_selection() -> void:
	var g = Rules.new("")
	var before := snapshot(g)
	check(not g.new_run("warden", 55, 0, "poison").ok, "other-role build rejected before a run starts")
	check(before == snapshot(g), "invalid preset does not start or consume RNG")
	check(g.new_run("ranger", 55, 0, "poison").ok and g.state.build_plan == "poison", "build can be chosen before play")
	var free = Rules.new("")
	check(free.new_run("ranger", 55).ok and free.state.build_plan == "", "legacy three-argument API retains free choice")
	check(g.state.deck == free.state.deck and g.state.map == free.state.map and g.state.rng_states == free.state.rng_states, "preset does not change starter deck, map or RNG")
	g = fixture()
	before = snapshot(g)
	check(g.set_build_plan("poison").ok, "reward-page plan change succeeds")
	var changed := snapshot(g)
	changed.state.build_plan = before.state.build_plan
	check(changed == before, "changing plans does not reroll offers, reset allowance or alter RNG")
	before = snapshot(g)
	for instance in g.state.rewards:
		g.build_recommendation(instance)
	check(before == snapshot(g), "recommendations are read-only")
	check(not g.set_build_plan("forge").ok and before == snapshot(g), "invalid plan change is inert")
	g.state.rewards = [card("ranger_05"), card("ranger_06"), card("ranger_07")]
	var size: int = g.state.deck.size()
	check(g.choose_reward(0).ok and g.state.deck.size() == size + 1 and g.state.deck.back().id == "ranger_05", "player can freely take a nonrecommended card")
	g = fixture()
	g.set_build_plan("poison")
	size = g.state.deck.size()
	check(g.choose_reward(-1).ok and g.state.deck.size() == size, "preset never prevents skipping rewards")


func test_rerolls() -> void:
	var g = fixture()
	var offers: Array = g.state.rewards.duplicate(true)
	var seen: Array = offers.map(func(c): return str(c.id))
	var gold: int = g.state.gold
	var deck: Array = g.state.deck.duplicate(true)
	var profile: Dictionary = g.profile.duplicate(true)
	var streams: Dictionary = g.state.rng_states.duplicate(true)
	for slot in 3:
		var before := snapshot(g)
		check(g.reward_reroll_view(slot).available and before == snapshot(g), "refresh availability query is pure")
		check(g.reroll_reward(slot).ok, "each of the three slots refreshes independently")
		var id := str(g.state.rewards[slot].id)
		check(not seen.has(id), "refreshed card was not previously shown in this reward")
		seen.append(id)
		for other in 3:
			if other != slot:
				check(g.state.rewards[other] == offers[other], "refresh preserves other offers")
		offers = g.state.rewards.duplicate(true)
		check(g.state.reward_rerolls_used[slot] and not g.reward_reroll_view(slot).available, "consumed slot is locked")
		reject_refresh(g, slot, "second refresh of slot %d" % slot)
		before = snapshot(g)
		g._win_battle()
		check(snapshot(g) == before, "duplicate victory cannot renew refreshes")
	check(g.state.gold == gold and g.state.deck == deck and g.profile == profile, "free rerolls do not grant cards, gold, progress or collection entries")
	for stream in ["map", "battle", "event"]:
		check(g.state.rng_states[stream] == streams[stream], "refresh only consumes loot RNG: " + stream)
	reject_refresh(g, -1, "negative slot")
	reject_refresh(g, 3, "out-of-range slot")
	check(g.choose_reward(1).ok, "a refreshed card can be selected")
	check(g.state.reward_seen.is_empty() and g.state.reward_rerolls_used.is_empty(), "completed reward clears temporary refresh state")
	reject_refresh(g, 0, "refresh outside reward room")
	g.state.row += 1
	g._start_battle("normal")
	g._win_battle()
	check(g.state.reward_rerolls_used == [false, false, false], "next victory grants three fresh independent allowances")


func test_pool_boundaries() -> void:
	var catalog = Rules.new("")
	for role in catalog.data.roles:
		for kind in ["normal", "elite", "boss"]:
			for chapter in [0, 2, 3]:
				var g = fixture(str(role.id), kind, chapter, false)
				var pool: Array = g._eligible_cards(kind == "boss")
				if pool.size() < 3:
					pool = g._eligible_cards(false)
				var allowed: Array = pool.map(func(c): return str(c.id))
				for slot in 3:
					if g.reward_reroll_view(slot).available:
						check(g.reroll_reward(slot).ok and allowed.has(str(g.state.rewards[slot].id)), "reroll respects role, chapter, unlock snapshot and boss rarity")
					else:
						reject_refresh(g, slot, "exhausted legal pool")
	var narrow = fixture()
	narrow.state.unlocked_snapshot = narrow.state.rewards.map(func(c): return str(c.id))
	check(not narrow.reward_reroll_view(0).available and narrow.reward_reroll_view(0).remaining == 1, "exhausted pool retains unused opportunity")
	reject_refresh(narrow, 0, "three-card-only pool")
	narrow = fixture()
	narrow._action_busy = true
	reject_refresh(narrow, 0, "busy action")


func test_saves() -> void:
	var path := "user://tests/build-guides-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var g = fixture()
	g._save_path = path
	check(g.set_build_plan("poison").ok and g.reroll_reward(0).ok, "build and refresh persisted to isolated save")
	var restored = Rules.new(path)
	check(restored.last_error.is_empty() and restored.state.build_plan == "poison" and restored.state.reward_rerolls_used == [true, false, false], "reload restores preset and each slot's allowance")
	check(restored.state.rewards == g.state.rewards and restored.state.reward_seen == g.state.reward_seen, "reload preserves offers and excluded cards")
	reject_refresh(restored, 0, "used slot after reload")
	var checkpoint: Dictionary = restored.state.duplicate(true)
	check(g.reroll_reward(1).ok and restored.reroll_reward(1).ok, "unspent slot can refresh after reload")
	check(g.state.rewards == restored.state.rewards and g.state.rng_states == restored.state.rng_states, "reload preserves deterministic next refresh")
	check(restored.set_build_plan("shiv").ok and restored.state.reward_rerolls_used == [true, true, false], "plan change never refunds refreshes")
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	parsed.state = checkpoint
	for key in ["build_plan", "reward_rerolls_used", "reward_seen"]:
		parsed.state.erase(key)
	var old_state: Dictionary = JSON.parse_string(JSON.stringify(parsed.state))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	var legacy = Rules.new(path)
	check(legacy.last_error.is_empty() and legacy.state.build_plan == "" and legacy.state.reward_rerolls_used == [false, false, false], "old pending reward gains optional guidance and fresh slots")
	var stripped: Dictionary = legacy.state.duplicate(true)
	for key in ["build_plan", "reward_rerolls_used", "reward_seen"]:
		stripped.erase(key)
	check(JSON.parse_string(JSON.stringify(stripped)) == old_state, "legacy migration preserves unrelated state")
	legacy._save_path = ""
	check(legacy.reroll_reward(2).ok, "old reward can use its new allowance")
	g._save_path = "user://tests/build-guides-missing-%d/save.json" % Time.get_ticks_usec()
	# Force a save failure using a file as the parent, without touching the player's save.
	var blocker := FileAccess.open(path + ".blocker", FileAccess.WRITE)
	blocker.store_string("test")
	blocker.close()
	g._save_path = path + ".blocker/save.json"
	var result: Dictionary = g.reroll_reward(2)
	check(result.ok and result.has("save_error") and g.state.reward_rerolls_used[2], "save failure is reported without silently refunding a successful reroll")
	for suffix in ["", ".bak", ".tmp", ".blocker"]:
		if FileAccess.file_exists(path + suffix):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix)) == OK, "isolated test save cleaned up")


func run() -> void:
	test_plans()
	test_optional_selection()
	test_rerolls()
	test_pool_boundaries()
	test_saves()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := {"checks": checks, "failures": failures, "mode": "deterministic rules and isolated save fixtures", "player_save_used": false}
	var file := FileAccess.open(OUTPUT + "/rules-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BUILD_GUIDES_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
