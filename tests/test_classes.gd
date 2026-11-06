extends SceneTree
## Explicit fixtures exercise class rules without the player's save or balance claims.
const Rules = preload("res://core/game_engine.gd")
const Classes = preload("res://core/class_mechanics.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func fixture(role: String = "warden"):
	var g = Rules.new("")
	g.profile.total_wins = 999
	g.profile.role_wins[role] = 999
	g.new_run(role, 729)
	g.enter_node(1)
	g.state.relics = []
	g.state.status = {}
	g.state.hp = 500
	g.state.max_hp = 500
	g.state.energy = 100
	g.state.stars = 100
	g.state.hand = []
	g.state.draw = []
	g.state.discard = []
	g.state.exhaust = []
	g.state.orbs = []
	g.state.enemies = [{"id":"fixture", "name":"规则靶", "hp":10000, "max_hp":10000, "block":0, "status":{}, "pattern":[{"intent":"等待", "effects":[]}], "turn":0, "intent":"等待", "color":"#aaaaaa"}]
	return g

func token(id: String) -> Dictionary:
	return {"id":id, "upgraded":false}

func play(g, name_value: String) -> Dictionary:
	for card in g.data.cards:
		if card.name == name_value:
			g.state.hand.append(token(str(card.id)))
			return g.play_card(g.state.hand.size() - 1)
	return {"ok":false}

func check_original_roles() -> void:
	var fresh = Rules.new("")
	check(fresh.new_run("bellscribe", 729).ok and fresh.enter_node(1).ok, "bellscribe starts a natural run and opens first battle")
	check(fresh.state.status.get("resonance", 0) == 2, "bellscribe starts each battle with 2 resonance")
	var g = fixture("bellscribe")
	g.state.status.resonance = 2
	g.state.hand = [token("bellscribe_03")]
	check(g.preview_card(0).damage == 6 and g.play_card(0).ok, "unprimed resonance attack still deals its base damage")
	check(g.state.enemies[0].hp == 9994 and g.state.status.resonance == 2, "unprimed attack neither doubles damage nor spends resonance")
	check(play(g, "拓音").ok and g.state.status.resonance == 3, "base attack primes resonance threshold")
	g.state.hand = [token("bellscribe_03")]
	check(g.preview_card(0).damage == 14 and g.play_card(0).ok, "primed resonance attack previews and resolves its second hit")
	check(g.state.enemies[0].hp == 9973 and g.state.status.resonance == 0, "resonant hit consumes exactly three resonance")
	g.state.status.resonance = 5
	check(play(g, "试钟").ok and g.state.status.resonance == 6, "resonance caps at 6")
	g.end_turn()
	check(g.state.status.resonance == 6, "unused resonance carries across turns")
	g.state.hand = [token("bellscribe_04")]
	check(g.preview_card(0).block == 13 and g.play_card(0).ok, "resonant block previews and resolves its second layer")
	check(g.state.block == 13 and g.state.status.resonance == 3, "resonant block spends the same resource as damage")
	g.state.enemies[0].hp = 5
	g.state.enemies.append(g.state.enemies[0].duplicate(true))
	check(play(g, "敲碑").ok and g.state.status.resonance == 3, "no resonance is spent when the base hit already defeated the target")

	fresh = Rules.new("")
	check(fresh.new_run("ashlamper", 729).ok and fresh.enter_node(1).ok, "ashlamper starts a natural run and opens first battle")
	g = fixture("ashlamper")
	g.state.enemies.append(g.state.enemies[0].duplicate(true))
	g.state.hand = [token("ashlamper_04")]
	check(not g.play_card(0, 5).ok and g.state.hand.size() == 1 and g.state.energy == 100, "single-target cinder rejects invalid targets without spending")
	check(g.play_card(0, 1).ok and g.state.enemies[0].status.get("cinder", 0) == 0 and g.state.enemies[1].status.cinder == 3, "cinder stacks only on the chosen target")
	g.end_turn()
	check(g.state.enemies[1].status.cinder == 3 and g.state.enemies[1].hp == 10000, "cinder persists without passive damage")
	g.state.hand = [token("ashlamper_16")]
	g.state.enemies[1].block = 4
	g.state.enemies[1].status.vulnerable = 1
	g.state.enemies[1].status.thorns = 4
	g.state.status.strength = 20
	check(g.preview_card(0, 1).damage == 15 and g.play_card(0, 1).ok, "same-card cinder increase is included in ignition preview")
	check(g.state.enemies[1].hp == 9989 and g.state.enemies[1].status.get("cinder", 0) == 0 and g.state.hp == 500, "ignition clears stacks and bypasses modifiers and thorns while respecting block")
	g.state.energy = 100
	check(play(g, "贴烛").ok and play(g, "贴烛").ok and g.state.enemies[0].status.cinder == 8, "each target caps at 8 cinder")
	check(play(g, "走灯").ok and g.state.enemies[1].status.cinder == 1, "area cinder applies to every living target")
	g.state.hand = [token("ashlamper_17")]
	check(g.play_card(0, -1).ok and g.state.enemies.all(func(enemy): return not enemy.status.has("cinder")), "area ignition needs no target and clears each living target")

func run() -> void:
	var g = fixture()
	play(g, "恶魔之力")
	check(int(g.state.status.get("strength", 0)) == 0, "turn strength does not fire on power application")
	g.end_turn()
	check(int(g.state.status.strength) == 2, "turn strength fires on subsequent turn")
	g.state.energy = 100
	play(g, "不动堡垒")
	g.state.block = 17
	g.end_turn()
	check(g.state.block == 17, "barricade preserves block across turns")
	g = fixture()
	g.state.status = {"exhaust_block":4, "exhaust_draw":1}
	g.state.draw = [token("warden_01")]
	g.state.block = 0
	play(g, "铁甲·战意")
	check(g.state.block == 0 and g.state.hand.is_empty(), "power removal does not trigger exhaust benefits")
	play(g, "余烬斩")
	check(g.state.block == 4 and g.state.hand.size() == 1, "true exhaust triggers block and draw once")
	g = fixture("ranger")
	play(g, "精准刀锋")
	g.state.hand = [token("token_shiv")]
	var card: Dictionary = g.card_view(g.state.hand[0])
	check(card.effects[0].value == 10 and str(card.description).replace(" ", "").contains("10点伤害"), "Shiv tooltip agrees with augmented damage")
	check(g.card_data("token_shiv").effects[0].value == 6, "dynamic Shiv view never mutates catalog")
	g.state.status.strength = 2
	g.play_card(0)
	check(g.state.enemies[0].hp == 9988, "Shiv bonus stacks with strength")
	play(g, "淬毒")
	play(g, "催化毒素")
	check(g.state.enemies[0].status.poison == 14, "poison doubles current stacks")
	g.state.status.discard_draw = 1
	g.state.status.discard_energy = 1
	g.state.pending_discard = 1
	g.state.hand = [token("ranger_08")]
	g.state.draw = [token("ranger_01")]
	g.state.energy = 0
	var before: int = g.state.enemies[0].hp
	var played: int = g.profile.stats.cards_played
	check(g.choose_discard(0).ok, "Sly discard resolves at zero energy")
	check(g.state.enemies[0].hp == before - 12, "Sly attacks apply strength")
	check(g.state.energy == 1 and g.state.hand.size() == 1, "explicit discard triggers energy and draw")
	check(g.profile.stats.cards_played == played + 1, "Sly play contributes to played-card stats")
	check(g.state.pending_discard == 0, "discard request completes")
	g.state.hand = [token("ranger_08")]
	g.state.draw = []
	g.state.discard = []
	g.state.enemies[0].status.erase("poison")
	before = g.state.enemies[0].hp
	g.end_turn()
	check(g.state.enemies[0].hp == before and g.state.energy == 3, "end-turn discard triggers neither Sly nor discard energy")
	g = fixture("ranger")
	play(g, "猎手·断筋")
	play(g, "烟幕")
	check(g.state.enemies[0].status.weak == 3, "two different cards add Weak duration")
	check(g.calculate_damage(10, g.state.enemies[0].status, {}) == 7, "stacked Weak applies its multiplier only once")
	play(g, "铁甲·破甲")
	play(g, "破阵")
	check(g.state.enemies[0].status.vulnerable == 3, "two different cards add Vulnerable duration")
	check(g.calculate_damage(10, {}, g.state.enemies[0].status) == 15, "stacked Vulnerable applies its multiplier only once")
	check(g.calculate_damage(10, {"weak":3}, {"vulnerable":3}) == 11, "Weak and Vulnerable combine before a single rounding")
	g.end_turn()
	check(g.state.enemies[0].status.weak == 2 and g.state.enemies[0].status.vulnerable == 2, "both durations tick once at owner's turn end")
	g.state.status.strength = -2
	g._player_effect({"op":"strength","value":1}, 0)
	check(g.state.status.strength == -1, "strength gain offsets signed curse penalty exactly")
	g = fixture()
	var armored: Dictionary = g.state.enemies[0].duplicate(true)
	armored.hp = 20
	armored.block = 4
	var vulnerable: Dictionary = armored.duplicate(true)
	vulnerable.block = 0
	vulnerable.status = {"vulnerable":1}
	var fallen: Dictionary = armored.duplicate(true)
	fallen.hp = 0
	g.state.enemies = [armored, vulnerable, fallen]
	g.state.hand = [token("warden_06")]
	check(g.card_view(g.state.hand[0]).area_kind == "attack" and not g.card_view(g.state.hand[0]).requires_target, "group attack card exposes no-target scope")
	check(g.play_card(0, -1).ok and armored.hp == 17 and vulnerable.hp == 10 and fallen.hp == 0, "group attack works without a target, applies each enemy's Block and Vulnerable, skips the fallen")
	armored.hp = 2
	vulnerable.hp = 20
	g.state.hand = [token("ranger_14")]
	check(g.play_card(0, -1).ok and armored.hp == 0 and vulnerable.hp == 12, "two-hit group attack reevaluates living enemies each hit")
	check(g.card_view(token("ranger_09")).area_kind == "effect", "all-enemy Poison is labeled as a group effect instead of attack")
	g = fixture("arcanist")
	g.state.stars = 1
	g.state.hand = [token("arcanist_03")]
	var snapshot := JSON.stringify(g.state)
	check(not g.play_card(0).ok and JSON.stringify(g.state) == snapshot, "insufficient Stars rejects without side effects")
	g.state.stars = 3
	g.play_card(0)
	check(g.state.stars == 1, "Stars are paid separately from energy")
	g._player_effect({"op":"forge", "value":6}, 0)
	g._player_effect({"op":"forge", "value":8}, 0)
	check(g.state.blade == 14 and g.state.hand.size() == 1, "repeated Forge grows one blade")
	check(g.card_view(g.state.hand[0]).effects[0].scale == "blade", "blade uses saved Forge scaling")
	g.end_turn()
	check(g.state.stars == 1 and g.state.blade == 14 and g.state.hand.any(func(c): return c.id == "token_blade"), "Stars, Forge and retained blade survive turn")
	g = fixture("medium")
	g.state.osty_hp = 5
	g.state.block = 3
	g._damage_player(12, 0)
	check(g.state.hp == 496 and g.state.osty_hp == 0 and g.state.block == 0, "incoming attack uses block, Osty, then player HP")
	g._player_effect({"op":"osty_summon", "value":6}, 0)
	g._player_effect({"op":"osty_attack", "value":12, "hits":2}, 0)
	check(g.state.enemies[0].hp == 9976, "Osty multi-hit executes both hits")
	g.state.status.soul_summon = 3
	g.state.hand = [token("token_soul")]
	g.state.draw = [token("medium_01"), token("medium_02")]
	g.play_card(0)
	check(g.state.osty_hp == 9 and g.state.hand.size() == 2, "Soul triggers summon and draws two cards")
	g.state.enemies[0].hp = 8
	g.state.enemies[0].status.doom = 8
	g.state.enemies[0].pattern = [{"effects":[{"op":"damage", "value":2}]}]
	g.state.osty_hp = 0
	g.end_turn()
	var enemy_acted: bool = g.combat_events.any(func(event): return event.source == "enemy:0" and event.target == "player" and int(event.amount) == 4)
	check(enemy_acted and g.state.room == "reward", "Doom allows enemy action before end-turn execution")
	g = fixture("sister")
	g.state.status = {"strength":50, "weak":1, "focus":2, "dexterity":50, "frail":1}
	g._player_effect({"op":"channel", "value":1, "orb":"frost"}, 0)
	g.state.block = 0
	Classes.end_turn(g)
	check(g.state.block == 4, "frost uses Focus, ignoring Dexterity and Frail")
	g.state.orbs = [{"kind":"dark", "value":6}]
	Classes.end_turn(g)
	check(g.state.orbs[0].value == 14, "dark charges once using Focus")
	g.state.enemies[0].status.vulnerable = 3
	before = g.state.enemies[0].hp
	g._player_effect({"op":"dualcast", "value":2}, 0)
	check(g.state.enemies[0].hp == before - 28 and g.state.orbs.is_empty(), "double dark evoke ignores strength, weakness and vulnerable")
	g.state.orbs = [{"kind":"glass", "value":4}]
	Classes.end_turn(g)
	check(g.state.orbs[0].value == 3, "glass damage decays after passive activation")
	g.state.orbs = [{"kind":"plasma", "value":0}]
	g.state.energy = 0
	Classes.start_turn(g)
	check(g.state.energy == 1, "plasma energy ignores Focus")
	g = fixture("sister")
	g.state.orbs = [{"kind":"frost", "value":0}, {"kind":"dark", "value":6}, {"kind":"plasma", "value":0}]
	g.state.block = 0
	g._player_effect({"op":"channel", "value":1, "orb":"lightning"}, 0)
	check(g.state.block == 5 and g.state.orbs.size() == 3 and g.state.orbs[0].kind == "dark", "full slots evoke oldest orb before adding new orb")
	check_original_roles()
	# Every base/upgraded recipe must execute through the public API.
	var executions := 0
	for role in g.data.roles:
		g = fixture(str(role.id))
		var chapter_counts := [6,11,14,16] if role.id in ["bellscribe", "ashlamper"] else [14,24,32,40]
		for chapter in range(4):
			g.state.chapter = chapter
			var pool: Array = g._eligible_cards()
			var own := pool.filter(func(c): return c.role == role.id)
			check(own.size() == chapter_counts[chapter], "%s chapter %d cumulative class pool" % [role.id,chapter])
			if chapter == 0:
				check(own.any(func(c): return g.card_view(token(str(c.id))).area_kind == "attack"), "%s offers group attacks in chapter one" % role.id)
			check(pool.all(func(c): return int(c.get("min_chapter", 0)) <= chapter), "chapter gate applies before reward/shop generation")
	for definition in g.data.cards + g.data.tokens:
		for upgraded in [false,true]:
			g = fixture(str(definition.role) if definition.role != "neutral" else "warden")
			g.state.osty_hp = 100
			g.state.hand = [{"id":definition.id, "upgraded":upgraded}]
			check(g.play_card(0).ok, "base/upgraded executes: " + str(definition.id))
			executions += 1
	# Reload a generated-card battle with ongoing resources and passive powers.
	g = fixture("arcanist")
	g.state.hand = [token("token_blade"),token("token_soul")]
	g.state.blade = 23
	g.state.stars = 7
	g.state.osty_hp = 11
	g.state.status = {"soul_summon":3,"retain_block":1,"discard_energy":1}
	var path := "user://class-test-%d.json" % OS.get_process_id()
	g._save_path = path
	check(g.save_game(), "generated cards and class resources save")
	var reloaded = Rules.new(path)
	check(reloaded.state == g.state, "class resources, token cards and ongoing powers survive reload")
	g.end_turn()
	reloaded.end_turn()
	check(reloaded.state == g.state, "reloaded class battle produces identical next turn")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var report := {"checks":checks,"failures":failures,"card_executions":executions,"scope":"class-combination fixtures, chapter pools, generated cards and save reload; not natural-run balance"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/spire-classes-20261104"))
	var file := FileAccess.open("res://docs/evidence/spire-classes-20261104/classes.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("CLASSES_RESULT=",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
