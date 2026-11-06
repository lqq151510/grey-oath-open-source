extends SceneTree
## Tactical behavior fixtures use isolated saves and never open the player's save.

const Rules = preload("res://core/game_engine.gd")
const Tactics = preload("res://core/battle_tactics.gd")
var checks := 0
var failures: Array[String] = []
var save_path := ""


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func token(id: String) -> Dictionary:
	return {"id": id, "upgraded": false}


func fixture(role: String = "warden"):
	var g = Rules.new("")
	g.new_run(role, 729)
	g.enter_node(1)
	g.state.relics = []
	g.state.status = {}
	g.state.hp = 500
	g.state.max_hp = 500
	g.state.energy = 100
	g.state.hand = []
	g.state.draw = []
	g.state.discard = []
	g.state.exhaust = []
	g.state.orbs = []
	g.state.enemies = [{"id": "fixture", "name": "战术靶", "hp": 10000, "max_hp": 10000, "block": 0, "status": {}, "pattern": [{"intent": "等待", "effects": []}], "turn": 0, "intent": "等待", "color": "#aaaaaa"}]
	return g


func play(g, id: String) -> Dictionary:
	g.state.hand.append(token(id))
	return g.play_card(g.state.hand.size() - 1)


func snapshot(g) -> String:
	# RNG 现在由 core/random_streams.gd 持有；snapshot() 是它的实时状态视图。
	return JSON.stringify({"state": g.state, "profile": g.profile, "rng": g._random.snapshot()})


func rejected(g, id: String, label: String, target: int = 0) -> void:
	var before := snapshot(g)
	var result: Dictionary = g.use_tactic(id, target)
	check(not result.ok and not str(result.message).is_empty(), label + " is rejected with a reason")
	check(snapshot(g) == before, label + " leaves state, profile and RNG unchanged")
	check(g.combat_events.is_empty(), label + " does not produce presentation events")


func option(g, id: String, target: int = 0) -> Dictionary:
	for entry in g.tactics_view(target).options:
		if entry.id == id:
			return entry
	return {}


func test_chain() -> void:
	var g = fixture()
	check(g.state.tactical_points == 0 and g.state.tactical_last_type == "" and g.state.tactical_gained == 0 and not g.state.tactical_used, "new battle initializes all tactical state")
	check(play(g, "warden_01").ok and g.state.tactical_points == 0, "first attack starts the chain without points")
	check(play(g, "warden_01").ok and g.state.tactical_points == 0, "same-type cards do not award points")
	check(play(g, "warden_04").ok and g.state.tactical_last_type == "attack", "power does not participate or interrupt the chain")
	check(play(g, "warden_02").ok and g.state.tactical_points == 1 and g.state.tactical_gained == 1, "skill following attack across a power awards one point")
	check(g.combat_events.filter(func(event): return event.kind == "status" and event.style == "tactical_points").size() == 1, "one successful alternation emits exactly one point event")
	check(play(g, "warden_01").ok and g.state.tactical_points == 2, "attack after skill earns the second point")
	check(play(g, "warden_02").ok and g.state.tactical_points == 2 and g.state.tactical_gained == 2, "per-turn gain cap prevents further gains")
	check(g.use_tactic("guard").ok and g.state.tactical_points == 0, "two earned points pay for a tactic")
	check(play(g, "warden_01").ok and g.state.tactical_points == 0, "spending points does not reset the per-turn earning cap")
	check(g.end_turn().ok and g.state.tactical_last_type == "" and g.state.tactical_gained == 0 and not g.state.tactical_used, "new turn resets chain, gain count and use flag")
	g.state.energy = 100
	check(play(g, "warden_02").ok and g.state.tactical_points == 0, "new turn's first card cannot chain from the previous turn")
	check(play(g, "warden_01").ok and play(g, "warden_02").ok and g.state.tactical_points == 2, "new turn can earn two more points")
	check(g.end_turn().ok and g.state.tactical_points == 2, "unspent points carry across turns")
	g.state.energy = 100
	play(g, "warden_01")
	play(g, "warden_02")
	check(g.state.tactical_points == 3 and g.state.tactical_gained == 1, "stored points cap at three")
	play(g, "warden_01")
	check(g.state.tactical_points == 3 and g.state.tactical_gained == 1 and g.state.tactical_last_type == "attack", "full meter preserves actual gain count and current chain type")
	g._start_battle("normal")
	check(g.state.tactical_points == 0 and g.state.tactical_gained == 0 and g.state.tactical_last_type == "" and not g.state.tactical_used, "a new encounter clears all tactical state")

	for role in g.data.roles:
		var traveler = fixture(str(role.id))
		check(play(traveler, "warden_01").ok and play(traveler, "warden_02").ok and traveler.state.tactical_points == 1, "%s can earn tactical points through normal card resolution" % str(role.id))
		traveler.state.tactical_points = 2
		check(traveler.use_tactic("guard").ok, "%s can use a tactic without a class resource" % str(role.id))


func test_rejections_and_views() -> void:
	var g = fixture()
	var before := snapshot(g)
	var view: Dictionary = g.tactics_view()
	check(view.points == 0 and view.max_points == 3 and view.cost == 2 and view.gain_limit == 2 and view.options.size() == 3, "view exposes complete tactical contract")
	check(not str(view.hint).contains("发动") and str(view.hint).contains("交替"), "empty meter explains how to earn points")
	g.state.tactical_points = 2
	check(str(g.tactics_view().hint).contains("发动一次战术"), "two points tell the player a tactic is ready now")
	g.state.tactical_points = 3
	check(str(g.tactics_view().hint).contains("已满"), "full meter reports the cap")
	g.state.tactical_points = 0
	view.options[0].description = "mutated view"
	check(snapshot(g) == before and not str(option(g, "strike").description).contains("mutated view"), "view and option dictionaries are detached and side-effect free")
	rejected(g, "guard", "insufficient points")
	g.state.tactical_points = 2
	rejected(g, "unknown", "unknown tactic")
	rejected(g, "strike", "invalid target", -1)
	g.state.enemies.append(g.state.enemies[0].duplicate(true))
	g.state.enemies[1].hp = 0
	rejected(g, "strike", "defeated target", 1)
	check(not option(g, "strike", 1).available and option(g, "guard", 1).available, "target validity only disables targeted tactic")
	g.state.pending_discard = 1
	rejected(g, "guard", "pending discard")
	g.state.pending_discard = 0
	g._action_busy = true
	rejected(g, "guard", "busy action")
	g._action_busy = false
	g.state.tactical_used = true
	rejected(g, "guard", "per-turn use limit")
	g.state.tactical_used = false
	g.state.hp = 0
	rejected(g, "guard", "dead player")
	g.state.hp = 500
	g.state.room = "map"
	rejected(g, "guard", "outside battle")
	g.state.room = "battle"
	g.state.active = false
	rejected(g, "guard", "inactive run")
	g.state.active = true
	g.state.enemies[0].hp = 0
	rejected(g, "guard", "no living enemies")

	g = fixture()
	play(g, "warden_01")
	g.state.hand = [token("warden_02")]
	g.state.energy = 0
	before = snapshot(g)
	check(not g.play_card(0).ok and snapshot(g) == before, "failed card does not advance or award a chain")
	g.state.energy = 100
	g.state.hand = [token("warden_01")]
	before = snapshot(g)
	check(not g.play_card(0, 90).ok and snapshot(g) == before, "failed targeted card leaves tactical state unchanged")


func test_strike_and_guard() -> void:
	var g = fixture()
	g.state.tactical_points = 3
	g.state.tactical_last_type = "skill"
	g.state.status = {"strength": 50, "weak": 3}
	g.state.enemies[0].status = {"vulnerable": 3, "thorns": 90}
	g.state.enemies[0].block = 2
	var hp: int = g.state.hp
	var energy: int = g.state.energy
	var cards_played: int = g.profile.stats.cards_played
	var combo: int = g.state.combo
	check(str(option(g, "strike").description).contains("预计损失 4 生命"), "strike preview includes current target block")
	check(g.use_tactic("strike").ok and g.state.enemies[0].hp == 9996 and g.state.enemies[0].block == 0, "fixed strike respects block but ignores strength, weak and vulnerable")
	check(g.state.hp == hp and not g.state.first_damage_used, "strike triggers neither thorns nor first-damage relic use")
	check(g.state.energy == energy and g.profile.stats.cards_played == cards_played and g.state.combo == combo, "tactic spends neither energy nor card-trigger counters")
	check(g.state.tactical_points == 1 and g.state.tactical_used and g.state.tactical_last_type == "skill" and g.state.tactical_gained == 0, "tactic consumes points once and preserves the chain")
	check(g.combat_events.size() == 1 and g.combat_events[0].kind == "damage" and g.combat_events[0].amount == 4 and g.combat_events[0].blocked == 2, "strike emits one accurate damage event")
	rejected(g, "strike", "repeated strike")
	check(g.end_turn().ok and g.state.tactical_points == 1 and not g.state.tactical_used, "strike availability resets next turn without refunding spent points")

	g = fixture()
	g.state.tactical_points = 2
	g.state.enemies[0].status.intangible = 1
	check(str(option(g, "strike").description).contains("预计损失 1 生命"), "strike preview respects intangible defense")
	check(g.use_tactic("strike").ok and g.state.enemies[0].hp == 9999, "fixed strike follows existing intangible mitigation")
	g = fixture()
	g.state.tactical_points = 2
	g.state.enemies[0].block = 10
	check(g.use_tactic("strike").ok and g.state.enemies[0].hp == 10000 and g.state.enemies[0].block == 4, "fully blocked strike still spends points and removes shield")
	g = fixture()
	g.state.tactical_points = 2
	g.state.block = 4
	g.state.status = {"dexterity": 50, "frail": 3}
	check(g.use_tactic("guard", -1).ok and g.state.block == 11, "guard grants fixed block and needs no target")
	check(g.combat_events.size() == 1 and g.combat_events[0].kind == "block" and g.combat_events[0].amount == 7, "guard emits one seven-block event")
	check(play(g, "warden_01").ok and play(g, "warden_02").ok and g.state.tactical_points == 1, "using a tactic does not stop subsequent manual card chaining")


func test_chapter_scaling() -> void:
	var g = fixture()
	g.state.chapter = 3
	g.state.tactical_points = 2
	check(str(option(g, "strike").title) == "追击 · 12伤害", "strike title scales with chapter")
	check(str(option(g, "guard").title) == "固守 · 13格挡", "guard title scales with chapter")
	check(str(option(g, "strike").description).contains("造成 12 点固定伤害"), "strike description scales with chapter")
	check(str(option(g, "guard").description).contains("13 点固定格挡"), "guard description scales with chapter")
	var hp: int = g.state.enemies[0].hp
	check(g.use_tactic("strike", 0).ok and g.state.enemies[0].hp == hp - 12, "chapter 3 strike deals scaled fixed damage")
	g.state.tactical_used = false
	g.state.tactical_points = 2
	g.state.block = 0
	check(g.use_tactic("guard", -1).ok and g.state.block == 13, "chapter 3 guard grants scaled block")
	check(g.combat_events.size() == 1 and g.combat_events[0].kind == "block" and g.combat_events[0].amount == 13, "chapter 3 guard emits a scaled block event")


func test_cycle() -> void:
	var g = fixture("ranger")
	g.state.tactical_points = 2
	g.state.tactical_last_type = "skill"
	g.state.draw = [token("ranger_08"), token("warden_02")]
	g.state.status.discard_energy = 1
	check(g.use_tactic("cycle", -1).ok and g.state.hand.size() == 2 and g.state.pending_discard == 1, "cycle draws before opening its discard choice")
	check(g.combat_events.size() == 2 and g.combat_events.all(func(event): return event.kind == "draw"), "cycle emits exactly two draw events")
	var before := snapshot(g)
	check(not g.end_turn().ok and snapshot(g) == before, "end turn is blocked until cycle discard completes")
	check(not g.play_card(0).ok and snapshot(g) == before, "manual card play is blocked until cycle discard completes")
	rejected(g, "guard", "tactic during cycle discard")
	var energy: int = g.state.energy
	check(g.choose_discard(1).ok and g.state.enemies[0].hp == 9990, "cycle can discard a newly drawn Sly attack and resolve it")
	check(g.state.tactical_points == 0 and g.state.tactical_last_type == "skill" and g.state.tactical_gained == 0, "automatic Sly attack does not earn points or change chain history")
	check(g.state.pending_discard == 0 and g.state.energy == energy + 1 and g.state.hand.size() == 1, "cycle preserves class discard triggers and closes its choice")

	g = fixture()
	g.state.tactical_points = 2
	for ignored in 9:
		g.state.hand.append(token("warden_01"))
	g.state.draw = [token("warden_01"), token("warden_02")]
	check(not option(g, "cycle").available and str(option(g, "cycle").reason).contains("空位"), "cycle view explains insufficient hand space")
	rejected(g, "cycle", "nine-card hand")
	g.state.hand.append(token("warden_01"))
	rejected(g, "cycle", "full hand")
	g.state.hand.clear()
	g.state.draw = [token("warden_01")]
	check(not option(g, "cycle").available and str(option(g, "cycle").reason).contains("可抽牌"), "cycle view explains insufficient draw supply")
	rejected(g, "cycle", "one available card")
	g.state.draw.clear()
	rejected(g, "cycle", "empty draw and discard piles")
	g.state.discard = [token("warden_01"), token("warden_02")]
	for ignored in 8:
		g.state.hand.append(token("warden_01"))
	check(g.use_tactic("cycle").ok and g.state.hand.size() == 10 and g.state.discard.is_empty() and g.state.pending_discard == 1, "cycle accepts exactly two slots and reshuffles discard as needed")
	check(g.choose_discard(0).ok and g.state.hand.size() == 9 and g.state.discard.size() == 1, "ordinary cycle discard has the expected net one-card gain")


func test_encounter_completion() -> void:
	var g = fixture()
	g.state.tactical_points = 2
	g.state.enemies[0].hp = 6
	var wins: int = g.profile.total_wins
	check(g.use_tactic("strike").ok and g.state.room == "reward" and g.state.battle_rewarded, "strike can finish an encounter and enter reward selection")
	check(g.profile.total_wins == wins + 1 and g.state.processed_encounters.size() == 1, "strike awards a victory exactly once")
	rejected(g, "strike", "strike after victory")
	var before := snapshot(g)
	g._check_battle_end()
	check(snapshot(g) == before, "rechecking a completed tactical victory does not repeat rewards")

	g = fixture()
	g.state.encounter_kind = "boss"
	g.state.boss_phase = 1
	g.state.boss_phases = 2
	g.state.enemies[0].hp = 6
	g.state.enemies[0].max_hp = 30
	g.state.tactical_points = 3
	check(g.use_tactic("strike").ok and g.state.room == "battle" and g.state.boss_phase == 2 and g.state.enemies[0].hp == 30, "strike advances a non-final boss phase")
	check(g.state.tactical_points == 1 and g.state.tactical_used and not g.state.battle_rewarded, "boss phase transition does not reset tactical spending or award victory")
	check(g.combat_events.any(func(event): return event.kind == "phase") and not g.combat_events.any(func(event): return event.kind == "death"), "non-final boss strike records phase rather than death")
	check(g.end_turn().ok, "boss phase encounter can continue")
	g.state.tactical_points = 2
	g.state.enemies[0].hp = 6
	check(g.use_tactic("strike").ok and g.state.room == "reward" and g.state.battle_rewarded, "strike can finish the final boss phase")


func test_saves() -> void:
	save_path = "user://tests/tactics-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var g = fixture()
	g._save_path = save_path
	play(g, "warden_01")
	play(g, "warden_02")
	check(g.save_game(), "tactical chain saves successfully to isolated path")
	var restored = Rules.new(save_path)
	check(restored.state.tactical_points == 1 and restored.state.tactical_gained == 1 and restored.state.tactical_last_type == "skill" and not restored.state.tactical_used, "mid-chain save reload restores all tactical state")
	check(play(restored, "warden_01").ok and restored.state.tactical_points == 2, "restored chain continues from the last manual card")
	check(restored.use_tactic("guard").ok, "restored points can fund a tactic")
	var spent = Rules.new(save_path)
	check(spent.state.tactical_points == 0 and spent.state.tactical_used and spent.state.tactical_gained == 2, "reload cannot refund a consumed tactic or earning limit")
	rejected(spent, "guard", "tactic repeated after reload")
	check(spent.end_turn().ok and not spent.state.tactical_used and spent.state.tactical_gained == 0, "persisted use lock clears only on the next turn")
	spent.state.hand = []
	spent.state.draw = [token("warden_01"), token("warden_02")]
	spent.state.discard = []
	spent.state.tactical_points = 2
	check(spent.use_tactic("cycle").ok, "cycle persists an unfinished discard choice")
	var pending = Rules.new(save_path)
	check(pending.state.pending_discard == 1 and pending.state.hand.size() == 2 and pending.state.tactical_used and pending.state.tactical_points == 0, "reloading during cycle retains cards, cost and pending choice")
	rejected(pending, "cycle", "reloaded unfinished cycle")
	check(pending.choose_discard(0).ok and pending.state.pending_discard == 0 and pending.state.hand.size() == 1, "reloaded cycle completes its original discard exactly once")

	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	for key in ["tactical_points", "tactical_last_type", "tactical_gained", "tactical_used"]:
		parsed.state.erase(key)
	var old_state = JSON.parse_string(JSON.stringify(parsed.state))
	var old_profile = JSON.parse_string(JSON.stringify(parsed.profile))
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	var legacy = Rules.new(save_path)
	check(legacy.last_error.is_empty() and legacy.state.active, "legacy battle save loads normally without tactical keys")
	check(legacy.state.tactical_points == 0 and legacy.state.tactical_last_type == "" and legacy.state.tactical_gained == 0 and not legacy.state.tactical_used, "legacy save receives neutral tactical defaults")
	var stripped: Dictionary = legacy.state.duplicate(true)
	for key in ["tactical_points", "tactical_last_type", "tactical_gained", "tactical_used"]:
		stripped.erase(key)
	check(JSON.parse_string(JSON.stringify(stripped)) == old_state and JSON.parse_string(JSON.stringify(legacy.profile)) == old_profile, "legacy migration preserves unrelated state and progression")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix)) == OK, "isolated tactical save cleaned up: " + suffix)


func run() -> void:
	test_chain()
	test_rejections_and_views()
	test_strike_and_guard()
	test_chapter_scaling()
	test_cycle()
	test_encounter_completion()
	test_saves()
	var report := {"checks": checks, "failures": failures, "mode": "script-driven rules and isolated save fixtures", "player_save_used": false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var output := FileAccess.open("res://tests/output/tactics-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("TACTICS_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
