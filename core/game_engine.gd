extends RefCounted
## Grey Oath deterministic rules. No scene tree or animation dependencies.

const Progression = preload("res://core/progression.gd")
const SAVE_VERSION = 1
const MIN_DIFFICULTY = -2
const MAX_DIFFICULTY = 8
const CHAPTER_NODES = 15
const Classes = preload("res://core/class_mechanics.gd")
const TutorialLessons = preload("res://core/tutorial_lessons.gd")
const Items = preload("res://core/item_mechanics.gd")
const BattleTactics = preload("res://core/battle_tactics.gd")
const BuildGuides = preload("res://core/build_guides.gd")
const WorkshopPack = preload("res://core/workshop_pack.gd")
const WORKSHOP_CARD_ID = WorkshopPack.CARD_ID
const WORKSHOP_ENEMY_ID = "workshop_enemy"
const WORKSHOP_POTION_ID = "workshop_potion"
const STREAMS = ["map", "battle", "loot", "event"]
const EFFECT_OPS = ["damage", "block", "draw", "energy", "heal", "self_damage", "poison", "weak", "vulnerable", "strength", "thorns", "regen", "soul", "summon", "mark", "lifesteal", "block_damage", "cleanse", "exhaust_hand", "next_energy", "stars", "forge", "fetch_blade", "minion", "osty_summon", "osty_attack", "osty_sacrifice", "doom", "soul_card", "shiv", "discard", "channel", "evoke", "dualcast", "orb_slots", "focus", "dexterity", "intangible", "frail", "exhaust_block", "exhaust_draw", "strength_each_turn", "retain_block", "shiv_damage", "poison_multiply", "discard_draw", "discard_energy", "soul_summon", "resonance", "resonant_damage", "resonant_block", "cinder", "ignite"]

var data: Dictionary = {}
var state: Dictionary = {}
var profile: Dictionary = {}
var last_error: String = ""
var _save_path: String = ""
var _indexes: Dictionary = {}
var _rng: Dictionary = {}
var _workshop_definitions: Dictionary = {}
var _action_busy = false
## Transient presentation results: never saved and never used to determine rules.
var combat_events: Array = []
var _combat_recording := false
var _item_notices: Array[String] = []


func _init(save_path: String = "user://save.json") -> void:
	_save_path = save_path
	var raw = FileAccess.get_file_as_string("res://data/catalog.json")
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		data = _normalize_numbers(parsed)
	else:
		last_error = "内容目录无法读取。"
	for group in ["roles", "cards", "enemies", "relics", "potions", "events", "items"]:
		_indexes[group] = {}
		for item in data.get(group, []):
			_indexes[group][str(item.id)] = item
	for token in data.get("tokens", []):
		_indexes.cards[str(token.id)] = token
	profile = _new_profile()
	state = _blank_state()
	if not _save_path.is_empty() and (FileAccess.file_exists(_save_path) or FileAccess.file_exists(_save_path + ".bak")):
		load_game()


func _new_profile() -> Dictionary:
	return {"total_wins": 0, "role_wins": {}, "clears": {}, "ascension": {}, "seen_cards": [], "sacred_collection": [], "history": [], "settings": {"music": true, "sound": true, "music_volume": 0.7, "sound_volume": 0.8, "combat_speed": 1.0, "reduced_motion": false}, "stats": {"runs_started": 0, "cards_played": 0, "cards_upgraded": 0, "elite_wins": 0, "boss_wins": 0}, "achievements": {}}


func _blank_state() -> Dictionary:
	return {"active": false, "run_id": "", "seed": 0, "role": "warden", "difficulty": 0, "chapter": 0, "row": -1, "lane": -1, "room": "map", "hp": 0, "max_hp": 0, "gold": 0, "deck": [], "relics": [], "items": {}, "item_claimed": [], "potions": [], "map": [], "hand": [], "draw": [], "discard": [], "exhaust": [], "enemies": [], "energy": 0, "block": 0, "status": {}, "souls": 0, "marks": [], "summons": [], "combo": 0, "turn": 0, "rewards": [], "build_plan": "", "reward_rerolls_used": [], "reward_seen": [], "shop": [], "event": {}, "log": [], "unlocked_snapshot": [], "processed_encounters": [], "rng_states": {}, "encounter_kind": "normal", "first_damage_used": false, "sister_used": false, "selected_shop_remove": -1, "battle_rewarded": false, "history_recorded": false, "boss_reward": "", "elapsed_turns": 0, "growth_wins": 0, "growth_level": 0, "boss_phase": 1, "boss_phases": 1, "stars": 0, "blade": 0, "blade_created": false, "orbs": [], "orb_slots": 3, "osty_hp": 0, "pending_discard": 0, "tactical_points": 0, "tactical_last_type": "", "tactical_gained": 0, "tactical_used": false}


func role_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == state.role:
		return _workshop_definitions.role
	return _indexes.get("roles", {}).get(id, {})


func card_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == WORKSHOP_CARD_ID:
		return _workshop_definitions.card
	return _indexes.get("cards", {}).get(id, {})


func relic_data(id: String) -> Dictionary:
	return _indexes.get("relics", {}).get(id, {})


func potion_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == WORKSHOP_POTION_ID:
		return _workshop_definitions.potion
	return _indexes.get("potions", {}).get(id, {})


func item_data(id: String) -> Dictionary:
	return _indexes.get("items", {}).get(id, {})


func enemy_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == WORKSHOP_ENEMY_ID:
		return _workshop_definitions.enemy
	return _indexes.get("enemies", {}).get(id, {})


func sacred_ids() -> Array:
	return data.get("items", []).filter(func(item): return item.kind == "sacred").map(func(item): return str(item.id))


func card_view(instance: Dictionary) -> Dictionary:
	var result = card_data(str(instance.get("id", ""))).duplicate(true)
	if result.is_empty():
		return result
	if bool(instance.get("upgraded", false)):
		result["name"] = str(result.name) + "+"
		result["effects"] = result.get("upgrade_effects", result.get("effects", [])).duplicate(true)
		result["description"] = result.get("upgrade_description", result.get("description", ""))
		result["cost"] = int(result.get("upgrade_cost", result.get("cost", 0)))
	result["upgraded"] = bool(instance.get("upgraded", false))
	result["area_kind"] = ""
	for effect in result.effects:
		if effect.get("target", "") == "all":
			if effect.op in ["damage", "lifesteal", "block_damage", "osty_attack", "resonant_damage", "ignite"]:
				result.area_kind = "attack"
				break
			result.area_kind = "effect"
	result["requires_target"] = _requires_enemy(result.effects)
	if str(result.id) == "token_shiv":
		var bonus = int(state.get("status", {}).get("shiv_damage", 0))
		if bonus > 0:
			var base = int(result.effects[0].value)
			result.effects[0].value = base + bonus
			result.description = str(result.description).replace("%d 点伤害" % base, "%d 点伤害" % (base + bonus))
	return result


func is_role_unlocked(role_id: String) -> bool:
	var role = role_data(role_id)
	# Every playable traveler is available from the first launch.
	return not role.is_empty()


func is_card_unlocked(card: Dictionary) -> bool:
	var progress = int(profile.total_wins) if card.get("role", "neutral") == "neutral" else int(profile.role_wins.get(str(card.role), 0))
	return progress >= int(card.get("unlock_wins", 0))


func unlocked_difficulty(role_id: String) -> int:
	return clampi(int(profile.ascension.get(role_id, 0)), 0, MAX_DIFFICULTY)


func start_tutorial(role_id: String = "warden") -> Dictionary:
	if not _save_path.is_empty() or state.active:
		return _fail("教学需要单独的练习场。")
	var lesson: Dictionary = TutorialLessons.LESSONS.get(role_id, {})
	if lesson.is_empty() or role_data(role_id).is_empty():
		return _fail("没有这个旅者的教学关卡。")
	var opponent: Dictionary = _indexes.enemies.get(lesson.enemy, {})
	if opponent.is_empty():
		return _fail("练习对手尚未就绪。")
	var deck: Array = []
	for id in lesson.deck:
		if card_data(id).is_empty():
			return _fail("练习卡牌尚未就绪。")
		deck.append({"id": id, "upgraded": false})

	state = _blank_state()
	state.active = true
	state.run_id = "tutorial"
	state.role = role_id
	state.room = "battle"
	state.encounter_kind = "tutorial"
	state.hp = 24
	state.max_hp = state.hp
	state.deck = deck
	state.draw = deck.duplicate(true)
	state.draw.reverse()
	state.enemies.append({
		"id": opponent.id, "name": opponent.name, "kind": "normal",
		"hp": lesson.hp, "max_hp": lesson.hp, "block": 0, "status": {}, "turn": 0,
		"pattern": opponent.pattern.duplicate(true), "intent": "", "color": opponent.color,
	})
	_seed_streams(int(state.seed))
	_log("练习开始。先观察敌人头顶的行动意图。")
	Classes.start_combat(self)
	_begin_player_turn()
	_update_intents()
	return _commit("练习开始。")


func start_workshop(pack: Dictionary) -> Dictionary:
	if not _save_path.is_empty() or state.active:
		return _fail("工坊试玩需要独立的试玩场。")
	var checked: Dictionary = WorkshopPack.validate(pack, self)
	if not checked.get("ok", false):
		return _fail(str(checked.get("message", "工坊作品无效。")))
	var design: Dictionary = checked.pack
	var base_role: Dictionary = _indexes.roles[design.role.base].duplicate(true)
	base_role.name = design.role.name
	base_role.max_hp = design.role.hp
	var card_op := "damage" if design.card.kind == "attack" else "block"
	var opponent := {
		"id": WORKSHOP_ENEMY_ID, "name": design.enemy.name, "kind": "normal", "chapter": 0,
		"hp": design.enemy.hp, "color": "#c7a279", "pattern": [
			{"intent": "攻击", "effects": [{"op": "damage", "value": design.enemy.attack}]},
			{"intent": "防御", "effects": [{"op": "block", "value": design.enemy.block}]},
		],
	}
	_workshop_definitions = {
		"role": base_role,
		"card": {
			"id": WORKSHOP_CARD_ID, "name": design.card.name, "role": design.role.base,
			"type": design.card.kind, "rarity": "starter", "cost": design.card.cost,
			"description": _workshop_effect_text(card_op, design.card.amount),
			"effects": [{"op": card_op, "value": design.card.amount}],
		},
		"potion": {
			"id": WORKSHOP_POTION_ID, "name": design.item.name,
			"description": _workshop_effect_text(design.item.kind, design.item.amount),
			"effects": [{"op": design.item.kind, "value": design.item.amount}],
		},
		"enemy": opponent,
	}

	state = _blank_state()
	state.workshop_pack = design.duplicate(true)
	state.active = true
	state.run_id = "workshop"
	state.role = design.role.base
	state.room = "battle"
	state.encounter_kind = "workshop"
	state.max_hp = design.role.hp
	state.hp = state.max_hp
	state.potions = [WORKSHOP_POTION_ID]
	for id in design.build.starter_cards:
		state.deck.append({"id": id, "upgraded": false})
	state.draw = state.deck.duplicate(true)
	_seed_streams(int(state.seed))
	_shuffle(state.draw, "battle")
	var signature_index: int = state.draw.find_custom(func(card): return card.id == WORKSHOP_CARD_ID)
	state.draw.append(state.draw.pop_at(signature_index))
	state.enemies.append({
		"id": opponent.id, "name": opponent.name, "kind": opponent.kind,
		"hp": opponent.hp, "max_hp": opponent.hp, "block": 0, "status": {}, "turn": 0,
		"pattern": opponent.pattern.duplicate(true), "intent": "", "color": opponent.color,
	})
	Classes.start_combat(self)
	_begin_player_turn()
	_player_effect({"op": design.talent.kind, "value": design.talent.amount}, 0)
	_log("%s使用流派「%s」迎战%s。" % [base_role.name, design.build.name, opponent.name])
	_log("天赋「%s」：%s" % [design.talent.name, _workshop_effect_text(design.talent.kind, design.talent.amount)])
	_update_intents()
	return _commit("工坊试玩开始。")


func _workshop_effect_text(op: String, amount: int) -> String:
	match op:
		"damage": return "造成 %d 点伤害。" % amount
		"block": return "获得 %d 点格挡。" % amount
		"heal": return "回复 %d 点生命。" % amount
		"energy": return "获得 %d 点能量。" % amount
		"strength": return "获得 %d 点力量。" % amount
	return ""


func new_run(role_id: String, seed_value: int = -1, difficulty: int = 0, build_plan: String = "") -> Dictionary:
	if not is_role_unlocked(role_id):
		return _fail("这个职业尚未解锁。")
	if difficulty < MIN_DIFFICULTY or difficulty > unlocked_difficulty(role_id):
		return _fail("该职业尚未开放此进阶难度。")
	if bool(state.get("active", false)):
		return _fail("已有未完成旅程，请继续或先结束当前旅程。")
	if BuildGuides.plan_for(role_id, build_plan).is_empty():
		return _fail("请选择当前旅者可用的流派。")
	state = _blank_state()
	var role = role_data(role_id)
	state.build_plan = build_plan
	state.active = true
	profile.stats.runs_started = int(profile.stats.runs_started) + 1
	state.seed = (int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())) & 0x7fffffff if seed_value < 0 else seed_value & 0x7fffffff
	state.run_id = "%s-%s-%s" % [state.seed, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	state.role = role_id
	state.difficulty = difficulty
	state.hp = int(role.get("max_hp", 80))
	state.max_hp = state.hp
	state.gold = 65
	for id in role.get("starter_cards", []):
		if card_data(str(id)).is_empty():
			return _fail("初始卡组引用了不存在的卡牌。")
		state.deck.append({"id": str(id), "upgraded": false})
		_seen(str(id))
	for card in data.get("cards", []):
		if is_card_unlocked(card):
			state.unlocked_snapshot.append(str(card.id))
	_seed_streams(int(state.seed))
	_gain_relic(str(role.get("starter_relic", "")))
	state.map = _make_map()
	_log("%s踏入长夜。种子 %d" % [role.name, state.seed])
	return _commit("新的旅程已开始。")


func _seed_streams(seed_value: int) -> void:
	_rng.clear()
	for i in range(STREAMS.size()):
		var generator = RandomNumberGenerator.new()
		generator.seed = seed_value + (i + 1) * 104729
		_rng[STREAMS[i]] = generator
	_sync_rng()


func _sync_rng() -> void:
	var values = {}
	for key in _rng:
		values[key] = {"seed": str(_rng[key].seed), "state": str(_rng[key].state)}
	state.rng_states = values


func _restore_rng() -> void:
	_rng.clear()
	for key in STREAMS:
		var generator = RandomNumberGenerator.new()
		var snapshot = state.get("rng_states", {}).get(key, {})
		generator.seed = int(snapshot.get("seed", str(int(state.seed) + (STREAMS.find(key) + 1) * 104729)))
		if snapshot.has("state"):
			generator.state = int(snapshot.state)
		_rng[key] = generator


func _random_int(stream: String, low: int, high: int) -> int:
	if not _rng.has(stream):
		_restore_rng()
	return _rng[stream].randi_range(low, high)


func _shuffle(items: Array, stream: String) -> void:
	for i in range(items.size() - 1, 0, -1):
		var other = _random_int(stream, 0, i)
		var temporary = items[i]
		items[i] = items[other]
		items[other] = temporary


func _make_map() -> Array:
	var result = []
	var pool = ["normal", "normal", "normal", "normal", "unknown", "unknown", "elite", "shop", "treasure", "fate"]
	for row in range(CHAPTER_NODES):
		var nodes = []
		for lane in range(3):
			var kind = pool[_random_int("map", 0, pool.size() - 1)]
			if row == 0:
				kind = "normal"
			elif row == CHAPTER_NODES - 2:
				var final_pool = ["normal", "elite", "unknown", "shop", "fate", "treasure"]
				kind = final_pool[_random_int("map", 0, final_pool.size() - 1)]
			elif row == CHAPTER_NODES - 1:
				kind = "boss"
			elif row == 1 and kind == "elite":
				kind = "normal"
			nodes.append({"kind": kind, "cleared": false, "next": [lane] if row < CHAPTER_NODES - 1 else []})
		result.append(nodes)
	# Guaranteed chapter landmarks, with seed-dependent lanes. Random weights alone
	# could otherwise omit an entire node type from a chapter.
	for landmark in [[1, "unknown"], [3, "shop"], [4, "elite"], [5, "treasure"], [6, "fate"], [7, "rest"]]:
		result[landmark[0]][_random_int("map", 0, 2)].kind = landmark[1]
	# Randomly choose the varied room; the other two are camps.
	var varied_lane = _random_int("map", 0, 2)
	for lane in range(3):
		if lane != varied_lane:
			result[CHAPTER_NODES - 2][lane].kind = "rest"
	for row in range(CHAPTER_NODES - 1):
		var diagonal_count = 0
		for left_lane in range(2):
			var direction = _random_int("map", 0, 2)
			# Only one diagonal orientation per adjacent lane pair: the two
			# opposing diagonals would cross without sharing a node.
			if direction == 1:
				result[row][left_lane].next.append(left_lane + 1)
				diagonal_count += 1
			elif direction == 2:
				result[row][left_lane + 1].next.append(left_lane)
				diagonal_count += 1
		if diagonal_count == 0:
			var left_lane = _random_int("map", 0, 1)
			if _random_int("map", 0, 1) == 0:
				result[row][left_lane].next.append(left_lane + 1)
			else:
				result[row][left_lane + 1].next.append(left_lane)
		for node in result[row]:
			node.next.sort()
	return result


func route_exits(row: int, lane: int) -> Array:
	var result = []
	var route = state.get("map", [])
	if not route is Array or row < 0 or row >= route.size() - 1:
		return result
	if not route[row] is Array or not route[row + 1] is Array or lane < 0 or lane >= route[row].size():
		return result
	var node = route[row][lane]
	if not node is Dictionary:
		return result
	# Old saves have no explicit edges. Keep their original adjacency rule
	# without rebuilding maps or consuming random numbers during reads.
	var exits = node.get("next", [lane - 1, lane, lane + 1])
	if not exits is Array:
		return result
	for destination in exits:
		if not destination is int and not destination is float:
			continue
		var next_lane = int(destination)
		if float(destination) != float(next_lane) or next_lane < 0 or next_lane >= mini(3, route[row + 1].size()) or absi(next_lane - lane) > 1:
			continue
		if route[row + 1][next_lane] is Dictionary and not result.has(next_lane):
			result.append(next_lane)
	result.sort()
	return result


func available_nodes() -> Array:
	var result = []
	if not state.active or state.room != "map":
		return result
	if int(state.row) < 0:
		if not state.map.is_empty() and state.map[0] is Array:
			for lane in range(mini(3, state.map[0].size())):
				if state.map[0][lane] is Dictionary:
					result.append(lane)
		return result
	return route_exits(int(state.row), int(state.lane))


func _resolve_node_kind(node: Dictionary) -> String:
	var kind = str(node.get("kind", "normal"))
	if kind == "fate":
		return "event"
	if kind != "unknown":
		return kind
	if node.has("resolved_kind"):
		var resolved = str(node.resolved_kind)
		return resolved if resolved in ["normal", "elite", "event", "treasure", "shop", "rest"] else "normal"
	var possibilities = ["normal", "elite", "event", "treasure", "shop", "rest"]
	var resolved = possibilities[_random_int("event", 0, possibilities.size() - 1)]
	node.resolved_kind = resolved
	return resolved


func enter_node(lane: int) -> Dictionary:
	if not available_nodes().has(lane):
		return _fail("无法前往这个节点。请选择连线上的下一层。")
	state.row = int(state.row) + 1
	state.lane = lane
	var node: Dictionary = state.map[int(state.row)][lane]
	var kind = _resolve_node_kind(node)
	state.encounter_kind = kind
	state.selected_shop_remove = -1
	match kind:
		"normal", "elite", "boss":
			_start_battle(kind)
		"shop":
			state.room = "shop"
			_make_shop()
		"rest":
			state.room = "rest"
		"event":
			state.room = "event"
			state.event = Items.offer(self) if node.kind == "unknown" or (node.kind == "fate" and _random_int("event", 0, 2) == 0) else {}
			if state.event.is_empty():
				var options = []
				for event in data.get("events", []):
					if int(event.get("chapter", 0)) == int(state.chapter):
						options.append(event)
				if options.is_empty():
					state.room = "rest"
				else:
					state.event = options[_random_int("event", 0, options.size() - 1)].duplicate(true)
		"treasure":
			state.room = "treasure"
			var relic = _random_relic(false)
			state.boss_reward = relic
			_gain_relic(relic)
			state.gold = int(state.gold) + 25
			_log("开启遗留箱：获得25金币与%s。" % relic_data(relic).get("name", "一份祝福"))
	return _commit("抵达新的节点。")


func _start_battle(kind: String) -> void:
	state.room = "battle"
	state.tactical_points = 0
	state.tactical_last_type = ""
	state.tactical_gained = 0
	state.tactical_used = false
	state.turn = 0
	state.block = 0
	state.energy = 0
	state.status = {}
	state.souls = 0
	state.marks = []
	state.summons = []
	state.combo = 0
	state.first_damage_used = false
	state.battle_rewarded = false
	state.hand = []
	state.draw = state.deck.duplicate(true)
	state.discard = []
	state.exhaust = []
	state.enemies = []
	state.rewards = []
	state.boss_reward = ""
	_shuffle(state.draw, "battle")
	var pool = []
	for enemy in data.get("enemies", []):
		if int(enemy.get("chapter", 0)) == int(state.chapter) and enemy.get("kind", "normal") == kind:
			pool.append(enemy)
	if pool.is_empty():
		last_error = "关卡没有可用敌人。"
		state.room = "map"
		state.row = int(state.row) - 1
		return
	var escorts = []
	if kind == "elite":
		for enemy in data.get("enemies", []):
			if int(enemy.get("chapter", 0)) == int(state.chapter) and enemy.get("kind", "normal") == "normal":
				escorts.append(enemy)
		if escorts.is_empty():
			last_error = "精英关卡没有可用的本章小怪。"
			state.room = "map"
			state.row = int(state.row) - 1
			return
	var count = 3 if kind == "elite" else 1
	if kind == "normal":
		count = _random_int("battle", 1, 3)
	var difficulty := int(state.difficulty)
	for index in range(count):
		var candidates = escorts if kind == "elite" and index > 0 else pool
		var definition = candidates[_random_int("battle", 0, candidates.size() - 1)]
		var enemy_kind = str(definition.get("kind", kind))
		var hp = int(definition.get("hp", 30))
		if count > 1 and enemy_kind == "normal":
			hp = maxi(10, int(hp * (0.55 if count == 2 else 0.40) if kind == "elite" else hp * (0.85 if count == 2 else 0.70)))
		if difficulty >= 1 and enemy_kind == "normal":
			hp = int(ceil(hp * 1.10))
		if kind == "boss":
			if difficulty >= 4:
				hp = int(ceil(hp * 1.15))
			hp = maxi(1, int(ceil(hp * (0.92 if int(state.chapter) == 0 else 0.82))))
			if difficulty >= 8:
				hp = ceili(hp * 120.0 / 100.0)
		elif difficulty >= 6 and enemy_kind == "elite":
			hp = ceili(hp * 115.0 / 100.0)
		match difficulty:
			-2: hp = maxi(1, floori(hp * 65.0 / 100.0))
			-1: hp = maxi(1, floori(hp * 80.0 / 100.0))
		state.enemies.append({"id": str(definition.id), "kind": enemy_kind, "escort": kind == "elite" and index > 0, "name": str(definition.name), "hp": hp, "max_hp": hp, "block": 0, "status": {}, "pattern": definition.pattern.duplicate(true), "turn": 0, "intent": "", "color": definition.get("color", "#c7a279")})
	state.boss_phase = 1
	state.boss_phases = (2 if int(state.chapter) == 0 else 3) if kind == "boss" else 1
	if kind == "boss":
		for enemy in state.enemies:
			enemy["base_pattern"] = enemy.pattern.duplicate(true)
	state.status.strength = _relic_total("start_strength") + int(state.chapter) + mini(3, int(state.get("growth_level", 0)) / 3)
	_log("遭遇%s。" % "、".join(_enemy_names()))
	Classes.start_combat(self)
	_begin_player_turn()
	state.block = int(state.block) + _relic_total("start_block")
	_update_intents()


func _enemy_names() -> Array[String]:
	var result: Array[String] = []
	for enemy in state.enemies:
		result.append(str(enemy.name))
	return result


func _begin_player_turn() -> void:
	state.turn = int(state.turn) + 1
	state.tactical_last_type = ""
	state.tactical_gained = 0
	state.tactical_used = false
	state.elapsed_turns = int(state.elapsed_turns) + 1
	if int(state.status.get("retain_block", 0)) <= 0:
		state.block = 0
	state.energy = 3 + mini(1, int(state.chapter)) + int(state.status.get("next_energy", 0))
	state.status.next_energy = 0
	state.combo = 0
	state.cards_played_this_turn = 0
	for enemy in state.enemies:
		enemy.erase("hurt_this_turn")
	state.sister_used = false
	var poison = int(state.status.get("poison", 0))
	if poison > 0:
		var hp_before = int(state.hp)
		state.hp = maxi(0, int(state.hp) - poison)
		_combat_damage("poison", "player", hp_before, int(state.hp), 0)
		state.status.poison = poison - 1
		_log("中毒损失%d生命。" % poison)
		if int(state.hp) <= 0:
			_finish_run(false)
			return
	var regen = int(state.status.get("regen", 0))
	if regen > 0:
		_heal(regen)
		state.status.regen = regen - 1
	var turn_block = _relic_total("turn_block") + mini(4, int(state.get("growth_level", 0)) / 2)
	state.block = int(state.block) + turn_block
	if turn_block > 0:
		_combat_event("block", "player", "player", turn_block)
	_heal(_relic_total("turn_heal"))
	Classes.start_turn(self)
	_combat_event("turn_start", "player", "player", int(state.turn))
	_draw_cards(5 + mini(1, int(state.chapter)) + _relic_total("turn_draw") + (2 if state.role == "ranger" and int(state.turn) == 1 else 0))


func _draw_cards(amount: int) -> void:
	for ignored in range(clampi(amount, 0, 100)):
		if state.hand.size() >= 10:
			break
		if state.draw.is_empty():
			if state.discard.is_empty():
				break
			state.draw = state.discard.duplicate(true)
			state.discard.clear()
			_shuffle(state.draw, "battle")
		state.hand.append(state.draw.pop_back())
		if _combat_recording:
			_combat_event("draw", "draw", "player", 1)
			combat_events.back()["card"] = state.hand.back().duplicate(true)
			combat_events.back()["hand_index"] = state.hand.size() - 1


func _requires_enemy(effects: Array) -> bool:
	for effect in effects:
		if str(effect.get("target", "")) == "self":
			continue
		if effect.op in ["damage", "lifesteal", "block_damage", "poison", "weak", "vulnerable", "doom", "osty_attack", "poison_multiply", "resonant_damage", "cinder", "ignite"] and effect.get("target", "enemy") != "all":
			return true
	return false


func _valid_target(index: int) -> bool:
	return index >= 0 and index < state.enemies.size() and int(state.enemies[index].hp) > 0


func play_card(hand_index: int, target_index: int = 0) -> Dictionary:
	_reset_combat_events()
	if not state.active or state.room != "battle" or _action_busy:
		return _fail("现在不能出牌。")
	if int(state.get("pending_discard", 0)) > 0:
		return _fail("请先完成弃牌选择。")
	if hand_index < 0 or hand_index >= state.hand.size():
		return _fail("这张牌已经不在手中。")
	var instance = state.hand[hand_index]
	var card = card_view(instance)
	if card.is_empty():
		return _fail("卡牌内容不可用。")
	if int(card.cost) > int(state.energy):
		return _fail("能量不足。")
	if int(card.get("star_cost", 0)) > int(state.get("stars", 0)):
		return _fail("星辰不足。")
	if int(card.get("soul_cost", 0)) > int(state.souls):
		return _fail("灵魂不足。")
	if _requires_enemy(card.effects) and not _valid_target(target_index):
		return _fail("请选择仍然存活的敌人。")
	_action_busy = true
	_combat_recording = true
	state.energy = int(state.energy) - int(card.cost)
	state.stars = int(state.get("stars", 0)) - int(card.get("star_cost", 0))
	state.souls = int(state.souls) - int(card.get("soul_cost", 0))
	state.hand.remove_at(hand_index)
	profile.stats.cards_played = int(profile.stats.cards_played) + 1
	state.cards_played_this_turn = int(state.get("cards_played_this_turn", 0)) + 1
	if card.get("type", "skill") == "attack":
		state.combo = int(state.combo) + 1
		Items.progress(self, "attacks_played")
	_log("打出%s。" % card.name)
	_record_tactical_play(str(card.get("type", "")))
	Classes.on_play(self, card)
	for effect in card.effects:
		if state.room != "battle":
			break
		_player_effect(effect, target_index)
		_check_battle_end()
	if card.get("exhaust", false):
		_exhaust_instance(instance)
	elif card.get("type", "") == "power":
		state.exhaust.append(instance)
	else:
		state.discard.append(instance)
	_action_busy = false
	_update_intents()
	return _commit("已打出%s。" % card.name)


func _record_tactical_play(card_type: String) -> void:
	var chain := BattleTactics.next_chain(int(state.get("tactical_points", 0)), int(state.get("tactical_gained", 0)), str(state.get("tactical_last_type", "")), card_type)
	state.tactical_points = chain.points
	state.tactical_gained = chain.gained
	state.tactical_last_type = chain.last_type
	if int(chain.added) > 0:
		_log("连携：应变 +1（%d / %d）。" % [int(chain.points), BattleTactics.MAX_POINTS])
		_combat_event("status", "player", "player", 1, 0, "tactical_points")


func tactics_view(target_index: int = 0) -> Dictionary:
	var points := int(state.get("tactical_points", 0))
	var gained := int(state.get("tactical_gained", 0))
	var used := bool(state.get("tactical_used", false))
	var last_type := str(state.get("tactical_last_type", ""))
	var common_reason := ""
	if not state.active or state.room != "battle" or int(state.hp) <= 0 or _first_living_enemy() < 0:
		common_reason = "现在不能发动战术。"
	elif _action_busy:
		common_reason = "当前动作尚未结算完成。"
	elif int(state.get("pending_discard", 0)) > 0:
		common_reason = "请先完成弃牌选择。"
	elif used:
		common_reason = "本回合已发动战术，下回合恢复。"
	elif points < BattleTactics.COST:
		common_reason = "应变不足，需要 2 点。"
	var options: Array = []
	for definition in BattleTactics.OPTIONS:
		var option: Dictionary = definition.duplicate(true)
		option["title"] = BattleTactics.option_title(str(option.id), int(state.chapter))
		option["description"] = BattleTactics.option_description(str(option.id), int(state.chapter))
		var reason := common_reason
		if str(option.id) == "strike":
			if reason.is_empty() and not _valid_target(target_index):
				reason = "请选择仍然存活的敌人。"
			if _valid_target(target_index):
				var enemy: Dictionary = state.enemies[target_index]
				var damage := 1 if int(enemy.status.get("intangible", 0)) > 0 else BattleTactics.strike_damage(int(state.chapter))
				var loss := mini(int(enemy.hp), maxi(0, damage - int(enemy.block)))
				option.description += "\n当前目标：%s，预计损失 %d 生命。" % [str(enemy.name), loss]
		elif str(option.id) == "cycle" and reason.is_empty():
			if state.hand.size() > 10 - BattleTactics.CYCLE_DRAW:
				reason = "手牌空位不足，需要至少 2 个空位。"
			elif state.draw.size() + state.discard.size() < BattleTactics.CYCLE_DRAW:
				reason = "可抽牌不足，抽牌堆与弃牌堆合计需至少 2 张。"
		option["available"] = reason.is_empty()
		option["reason"] = reason
		options.append(option)
	return {"points": points, "max_points": BattleTactics.MAX_POINTS, "cost": BattleTactics.COST, "gained": gained, "gain_limit": BattleTactics.GAIN_LIMIT, "used": used, "last_type": last_type, "hint": BattleTactics.chain_hint(points, gained, last_type), "options": options}


func use_tactic(id: String, target_index: int = 0) -> Dictionary:
	_reset_combat_events()
	var selected: Dictionary = {}
	for option in tactics_view(target_index).options:
		if str(option.id) == id:
			selected = option
			break
	if selected.is_empty():
		return _fail("未知的战术。")
	if not bool(selected.available):
		return _fail(str(selected.reason))
	_action_busy = true
	_combat_recording = true
	state.tactical_points = int(state.tactical_points) - BattleTactics.COST
	state.tactical_used = true
	_log("发动%s，消耗 %d 点应变。" % [str(selected.name), BattleTactics.COST])
	match id:
		"strike":
			_damage_enemy(target_index, BattleTactics.strike_damage(int(state.chapter)), false)
		"guard":
			var guard_block := BattleTactics.guard_block(int(state.chapter))
			state.block = int(state.block) + guard_block
			_combat_event("block", "player", "player", guard_block)
		"cycle":
			_draw_cards(BattleTactics.CYCLE_DRAW)
			_player_effect({"op": "discard", "value": 1}, target_index)
	_check_battle_end()
	_action_busy = false
	_update_intents()
	return _commit("已发动%s。" % str(selected.name))


func _effect_value(effect: Dictionary, target_index: int = 0) -> int:
	var base = int(effect.get("value", 0))
	var scale = 0
	match effect.get("scale", ""):
		"block": scale = int(state.block)
		"combo": scale = int(state.combo)
		"souls": scale = int(state.souls)
		"stars": scale = int(state.get("stars", 0))
		"blade": scale = int(state.get("blade", 0))
		"missing_hp": scale = int(state.max_hp) - int(state.hp)
		"poison":
			if _valid_target(target_index):
				scale = int(state.enemies[target_index].status.get("poison", 0))
	return maxi(0, base + int(floor(scale * float(effect.get("factor", 1.0)))))


func _player_effect(effect: Dictionary, target_index: int) -> void:
	var value = _effect_value(effect, target_index)
	var op = str(effect.get("op", ""))
	var target = str(effect.get("target", ""))
	if Classes.apply(self, op, value, effect, target_index):
		return
	var indexes = []
	if target == "all":
		for i in range(state.enemies.size()):
			if _valid_target(i):
				indexes.append(i)
	elif _valid_target(target_index):
		indexes.append(target_index)
	match op:
		"damage", "lifesteal", "block_damage":
			if op == "block_damage":
				value += int(state.block)
			var first_bonus = 0
			if not bool(state.first_damage_used):
				first_bonus = _relic_total("first_damage")
				state.first_damage_used = true
			for hit in range(clampi(int(effect.get("hits", 1)), 1, 30)):
				for index in indexes:
					if not _valid_target(index) or int(state.hp) <= 0:
						continue
					var damage = calculate_damage(value + first_bonus, state.status, state.enemies[index].status)
					first_bonus = 0
					var dealt = _damage_enemy(index, damage, true)
					if op == "lifesteal" and int(state.hp) > 0:
						_heal(dealt)
		"block":
			value = maxi(0, value + int(state.status.get("dexterity", 0)))
			if int(state.status.get("frail", 0)) > 0:
				value = int(floor(value * 0.75))
			state.block = int(state.block) + value
			_combat_event("block", "player", "player", value)
		"draw": _draw_cards(value)
		"energy": state.energy = int(state.energy) + value
		"heal": _heal(value)
		"self_damage":
			var hp_before = int(state.hp)
			if int(state.status.get("intangible", 0)) > 0:
				value = mini(1, value)
			state.hp = maxi(0, int(state.hp) - value)
			_combat_damage("self", "player", hp_before, int(state.hp), 0)
			_log("献血：失去%d生命。" % value)
			if int(state.hp) <= 0:
				_finish_run(false)
		"poison", "weak", "vulnerable":
			if target == "self":
				_add_status(state.status, op, value)
				_combat_event("status", "player", "player", value, 0, op)
			else:
				if op == "poison":
					value += _relic_total("poison_bonus")
				for index in indexes:
					_add_status(state.enemies[index].status, op, value)
					_combat_event("status", "player", "enemy:%d" % index, value, 0, op)
		"strength", "thorns", "regen", "next_energy":
			_add_status(state.status, op, value)
			_combat_event("status", "player", "player", value, 0, op)
		"soul": state.souls = int(state.souls) + value
		"summon":
			if state.summons.size() >= 3:
				var replace = 0
				for i in range(1, state.summons.size()):
					if int(state.summons[i].turns) < int(state.summons[replace].turns):
						replace = i
				state.summons.remove_at(replace)
			state.summons.append({"power": value, "turns": 3})
		"mark":
			state.marks.append(clampi(value, 1, 3))
			if state.marks.size() >= 3:
				var last = int(state.marks.back())
				state.marks.clear()
				match last:
					1:
						for i in range(state.enemies.size()):
							if _valid_target(i):
								_damage_enemy(i, calculate_damage(8, state.status, state.enemies[i].status), false)
						_log("日印共鸣：日火扫过敌阵。")
					2:
						state.block = int(state.block) + 12
						_combat_event("block", "player", "player", 12)
						_log("月印共鸣：获得12格挡。")
					3:
						_draw_cards(2)
						_log("星印共鸣：抽取2张牌。")
		"cleanse":
			for status in ["poison", "weak", "vulnerable"]:
				state.status[status] = 0
		"exhaust_hand":
			var removed = state.hand.duplicate()
			state.hand = []
			for instance in removed:
				_exhaust_instance(instance)
			_draw_cards(value)


func _exhaust_instance(instance: Dictionary) -> void:
	state.exhaust.append(instance)
	if state.room != "battle":
		return
	var block = int(state.status.get("exhaust_block", 0))
	state.block = int(state.block) + block
	if block > 0:
		_combat_event("block", "player", "player", block)
	_draw_cards(int(state.status.get("exhaust_draw", 0)))


func choose_discard(index: int, target_index: int = 0) -> Dictionary:
	_reset_combat_events()
	if state.room != "battle" or not state.active or _action_busy or int(state.get("pending_discard", 0)) <= 0:
		return _fail("现在不需要选择弃牌。")
	if index < 0 or index >= state.hand.size():
		return _fail("请选择手牌中的卡牌。")
	_action_busy = true
	_combat_recording = true
	state.pending_discard = int(state.pending_discard) - 1
	var instance = state.hand.pop_at(index)
	var card = card_view(instance)
	if card.get("sly", false):
		_log("机巧：%s被主动弃置，免费打出。" % card.name)
		profile.stats.cards_played = int(profile.stats.cards_played) + 1
		state.cards_played_this_turn = int(state.get("cards_played_this_turn", 0)) + 1
		if card.get("type", "") == "attack":
			state.combo = int(state.combo) + 1
			Items.progress(self, "attacks_played")
		Classes.on_play(self, card)
		for effect in card.effects:
			if state.room != "battle": break
			_player_effect(effect, target_index if _valid_target(target_index) else _first_living_enemy())
			_check_battle_end()
		if card.get("type", "") == "power":
			state.exhaust.append(instance)
		elif card.get("exhaust", false):
			_exhaust_instance(instance)
		else:
			state.discard.append(instance)
	else:
		state.discard.append(instance)
	Classes.on_discard(self)
	state.pending_discard = mini(int(state.pending_discard), state.hand.size())
	_action_busy = false
	_update_intents()
	return _commit("已完成一次弃牌选择。")


func calculate_damage(base: int, source_status: Dictionary, target_status: Dictionary) -> int:
	var amount = float(maxi(0, base + int(source_status.get("strength", 0))))
	if int(source_status.get("weak", 0)) > 0:
		amount *= 0.75
	if int(target_status.get("vulnerable", 0)) > 0:
		amount *= 1.5
	return maxi(0, int(floor(amount)))


func preview_card(hand_index: int, target_index: int = 0) -> Dictionary:
	if hand_index < 0 or hand_index >= state.hand.size():
		return {}
	var card = card_view(state.hand[hand_index])
	var result = {"damage": 0, "block": 0, "cost": card.get("cost", 0)}
	var has_target := _valid_target(target_index)
	var resonance := int(state.status.get("resonance", 0))
	var cinder := int(state.enemies[target_index].status.get("cinder", 0)) if has_target else 0
	for effect in card.get("effects", []):
		var value = _effect_value(effect, target_index)
		if effect.op == "block":
			result.block += value
		if effect.op in ["damage", "lifesteal", "block_damage"] and has_target:
			if effect.op == "block_damage":
				value += int(state.block)
			result.damage += calculate_damage(value, state.status, state.enemies[target_index].status) * int(effect.get("hits", 1))
		# As with ordinary hits, previews report raw damage before enemy block.
		match effect.op:
			"resonance": resonance = mini(Classes.RESONANCE_MAX, resonance + value)
			"resonant_damage":
				if has_target and resonance >= Classes.RESONANCE_COST:
					resonance -= Classes.RESONANCE_COST
					result.damage += calculate_damage(value, state.status, state.enemies[target_index].status)
			"resonant_block":
				if resonance >= Classes.RESONANCE_COST:
					resonance -= Classes.RESONANCE_COST
					result.block += value
			"cinder": cinder = mini(Classes.CINDER_MAX, cinder + value)
			"ignite":
				if has_target:
					result.damage += cinder * value
					cinder = 0
	return result


func _add_status(target: Dictionary, key: String, amount: int) -> void:
	var total = int(target.get(key, 0)) + amount
	target[key] = total if key == "strength" else maxi(0, total)


func _damage_enemy(index: int, amount: int, retaliate: bool = true, source: String = "player") -> int:
	if not _valid_target(index):
		return 0
	var enemy = state.enemies[index]
	if int(enemy.status.get("intangible", 0)) > 0:
		amount = mini(1, amount)
	var absorbed = mini(int(enemy.block), amount)
	enemy.block = int(enemy.block) - absorbed
	var dealt = mini(int(enemy.hp), maxi(0, amount - absorbed))
	var hp_before = int(enemy.hp)
	enemy.hp = maxi(0, int(enemy.hp) - dealt)
	_combat_damage(source, "enemy:%d" % index, hp_before, int(enemy.hp), absorbed)
	if dealt > 0:
		enemy.hurt_this_turn = true
		_log("%s受到%d伤害。" % [enemy.name, dealt])
	var thorns = int(enemy.status.get("thorns", 0))
	if retaliate and amount > 0 and thorns > 0:
		_damage_player(thorns, -1, false, "thorns")
	return dealt


func _damage_player(amount: int, source_index: int = -1, retaliate: bool = true, source: String = "") -> int:
	if int(state.status.get("intangible", 0)) > 0:
		amount = mini(1, amount)
	var absorbed = mini(int(state.block), amount)
	state.block = int(state.block) - absorbed
	var remainder = maxi(0, amount - absorbed)
	if source_index >= 0 and state.role == "medium" and int(state.get("osty_hp", 0)) > 0:
		var protected = mini(int(state.osty_hp), remainder)
		state.osty_hp = int(state.osty_hp) - protected
		remainder -= protected
		if protected > 0:
			_combat_event("osty_guard", "osty", "player", protected)
	var dealt = mini(int(state.hp), remainder)
	var hp_before = int(state.hp)
	state.hp = maxi(0, int(state.hp) - dealt)
	var actor = source if not source.is_empty() else ("enemy:%d" % source_index if source_index >= 0 else "self")
	_combat_damage(actor, "player", hp_before, int(state.hp), absorbed)
	if dealt > 0:
		_log("受到%d伤害。" % dealt)
	if int(state.hp) <= 0:
		_finish_run(false)
		return dealt
	var thorns = int(state.status.get("thorns", 0))
	if retaliate and amount > 0 and thorns > 0 and _valid_target(source_index):
		_damage_enemy(source_index, thorns, false, "thorns")
	return dealt


func _heal(amount: int) -> void:
	if amount > 0 and int(state.hp) > 0:
		var hp_before = int(state.hp)
		state.hp = mini(int(state.max_hp), int(state.hp) + amount)
		if int(state.hp) > hp_before:
			_combat_event("heal", "player", "player", int(state.hp) - hp_before)


func _decay_turn_status(status: Dictionary) -> void:
	for key in ["weak", "vulnerable", "frail"]:
		status[key] = maxi(0, int(status.get(key, 0)) - 1)


func end_turn() -> Dictionary:
	_reset_combat_events()
	if not state.active or state.room != "battle" or _action_busy:
		return _fail("现在不能结束回合。")
	_action_busy = true
	_combat_recording = true
	if int(state.get("pending_discard", 0)) > 0:
		_action_busy = false
		_combat_recording = false
		return _fail("请先完成弃牌选择。")
	_combat_event("turn_end", "player", "player", int(state.turn))
	var retained = []
	var old_hand = state.hand.duplicate()
	state.hand = retained
	for card in old_hand:
		if card_view(card).get("ethereal", false):
			_exhaust_instance(card)
		elif card_view(card).get("retain", false):
			retained.append(card)
		else:
			state.discard.append(card)
	Classes.end_turn(self)
	if int(state.status.get("doom", 0)) >= int(state.hp):
		state.hp = 0
		_finish_run(false)
	for summon_index in range(state.summons.size()):
		var summon = state.summons[summon_index]
		if state.room != "battle":
			break
		var target = _first_living_enemy()
		if target >= 0:
			_damage_enemy(target, int(summon.power), false, "summon:%d" % summon_index)
			summon.turns = int(summon.turns) - 1
			_check_battle_end()
	var kept_summons = []
	for summon in state.summons:
		if int(summon.turns) > 0:
			kept_summons.append(summon)
	state.summons = kept_summons
	_decay_turn_status(state.status)
	for index in range(state.enemies.size()):
		if state.room != "battle":
			break
		if not _valid_target(index):
			continue
		var enemy = state.enemies[index]
		enemy.block = 0
		var poison = int(enemy.status.get("poison", 0))
		if poison > 0:
			var hp_before = int(enemy.hp)
			enemy.hp = maxi(0, int(enemy.hp) - poison)
			enemy.hurt_this_turn = true
			_combat_damage("poison", "enemy:%d" % index, hp_before, int(enemy.hp), 0)
			enemy.status.poison = poison - 1
			_log("%s受到%d中毒伤害。" % [enemy.name, poison])
			_check_battle_end()
			if state.room != "battle" or not _valid_target(index):
				continue
		var regen = int(enemy.status.get("regen", 0))
		if regen > 0:
			var hp_before = int(enemy.hp)
			enemy.hp = mini(int(enemy.max_hp), int(enemy.hp) + regen)
			if int(enemy.hp) > hp_before:
				_combat_event("heal", "enemy:%d" % index, "enemy:%d" % index, int(enemy.hp) - hp_before)
			enemy.status.regen = regen - 1
		var pattern = enemy.pattern
		if not pattern.is_empty():
			var action = pattern[int(enemy.turn) % pattern.size()]
			for effect in action.get("effects", []):
				if state.room != "battle" or not _valid_target(index):
					break
				_enemy_effect(effect, index)
				_check_battle_end()
		if state.room == "battle":
			Classes.check_doom(self, index)
		enemy.turn = int(enemy.turn) + 1
		_decay_turn_status(enemy.status)
	state.status.intangible = maxi(0, int(state.status.get("intangible", 0)) - 1)
	if state.room == "battle":
		_begin_player_turn()
		_update_intents()
	_action_busy = false
	return _commit("回合结束。")


func _enemy_pressure(enemy: Dictionary) -> int:
	# Prolonged fights become more dangerous; existing turn counters keep saves compatible.
	return mini(3, int(enemy.get("turn", 0)) / 2)


func _enemy_desperation(enemy: Dictionary) -> int:
	# Wounded enemies threaten a final counterattack; no extra persistent state.
	return 2 if int(enemy.get("hp", 0)) > 0 and int(enemy.hp) * 2 <= int(enemy.get("max_hp", 1)) else 0


func _enemy_attack_value(value: int, op: String, enemy: Dictionary) -> int:
	if op == "block_damage":
		value += int(enemy.block)
	elif op == "echo_strike":
		value += _enemy_echo_bonus()
	value += _enemy_pressure(enemy) + _enemy_desperation(enemy)
	var difficulty := int(state.difficulty)
	if difficulty >= 0:
		# 标准及以上难度：敌方攻击随章节推进，精英额外凶险。
		value += int(state.chapter)
		if str(enemy.get("kind", state.encounter_kind)) == "elite":
			value += 1
	if difficulty >= 2 and str(enemy.get("kind", state.encounter_kind)) == "elite":
		value = int(ceil(value * 1.10))
	if difficulty >= 7:
		return ceili(value * 115.0 / 100.0)
	match difficulty:
		-2: return maxi(0, floori(value * 70.0 / 100.0))
		-1: return maxi(0, floori(value * 85.0 / 100.0))
	return value


func _enemy_echo_bonus() -> int:
	return 2 * clampi(int(state.get("cards_played_this_turn", 0)) - 3, 0, 3)


func _enemy_heal_target(index: int) -> int:
	var target := -1
	var biggest_wound := 0
	for candidate in range(state.enemies.size()):
		if candidate == index or not _valid_target(candidate):
			continue
		var ally: Dictionary = state.enemies[candidate]
		var missing := int(ally.max_hp) - int(ally.hp)
		if missing > biggest_wound:
			biggest_wound = missing
			target = candidate
	return target


func _enemy_effect(effect: Dictionary, index: int) -> void:
	var enemy = state.enemies[index]
	var value = maxi(0, int(effect.get("value", 0)))
	var op = str(effect.get("op", ""))
	match op:
		"damage", "lifesteal", "block_damage", "summon", "charge_strike", "echo_strike":
			if op == "charge_strike" and bool(enemy.get("hurt_this_turn", false)):
				_log("%s的钟槌蓄力被打断。" % enemy.name)
				return
			value = _enemy_attack_value(value, op, enemy)
			for hit in range(clampi(int(effect.get("hits", 1)), 1, 30)):
				if state.room != "battle" or not _valid_target(index):
					break
				var dealt = _damage_player(calculate_damage(value, enemy.status, state.status), index)
				if op == "lifesteal" and _valid_target(index):
					var hp_before = int(enemy.hp)
					enemy.hp = mini(int(enemy.max_hp), int(enemy.hp) + dealt)
					if int(enemy.hp) > hp_before:
						_combat_event("heal", "enemy:%d" % index, "enemy:%d" % index, int(enemy.hp) - hp_before)
		"block":
			enemy.block = int(enemy.block) + value
			_combat_event("block", "enemy:%d" % index, "enemy:%d" % index, value)
		"sunder":
			var removed := mini(int(state.block), value)
			if removed > 0:
				state.block = int(state.block) - removed
				_log("%s剥离了%d点格挡。" % [enemy.name, removed])
				_combat_event("status", "enemy:%d" % index, "player", removed, 0, "sunder")
		"heal_ally":
			var target := _enemy_heal_target(index)
			if target < 0:
				_enemy_effect({"op": "block", "value": int(effect.get("fallback_block", 0))}, index)
				return
			var ally: Dictionary = state.enemies[target]
			var restored := mini(value, int(ally.max_hp) - int(ally.hp))
			ally.hp = int(ally.hp) + restored
			_log("%s为%s回复%d点生命。" % [enemy.name, ally.name, restored])
			_combat_event("heal", "enemy:%d" % index, "enemy:%d" % target, restored)
		"heal":
			var hp_before = int(enemy.hp)
			enemy.hp = mini(int(enemy.max_hp), int(enemy.hp) + value)
			if int(enemy.hp) > hp_before:
				_combat_event("heal", "enemy:%d" % index, "enemy:%d" % index, int(enemy.hp) - hp_before)
		"self_damage":
			var hp_before = int(enemy.hp)
			enemy.hp = maxi(0, int(enemy.hp) - value)
			_combat_damage("self", "enemy:%d" % index, hp_before, int(enemy.hp), 0)
		"poison", "weak", "vulnerable":
			_add_status(enemy.status if effect.get("target", "enemy") == "self" else state.status, op, value)
			_combat_event("status", "enemy:%d" % index, "enemy:%d" % index if effect.get("target", "enemy") == "self" else "player", value, 0, op)
		"strength", "thorns", "regen":
			_add_status(enemy.status, op, value)
			_combat_event("status", "enemy:%d" % index, "enemy:%d" % index, value, 0, op)
		"cleanse":
			for key in ["poison", "weak", "vulnerable"]:
				enemy.status[key] = 0


func _first_living_enemy() -> int:
	for i in range(state.enemies.size()):
		if _valid_target(i):
			return i
	return -1


func _update_intents() -> void:
	var player_status: Dictionary = state.status.duplicate()
	_decay_turn_status(player_status)
	for index in range(state.enemies.size()):
		var enemy: Dictionary = state.enemies[index]
		if int(enemy.hp) <= 0:
			enemy.intent = "已击败"
			continue
		var pattern = enemy.get("pattern", [])
		if pattern.is_empty():
			enemy.intent = "等待"
			continue
		var action = pattern[int(enemy.turn) % pattern.size()]
		var pieces: Array[String] = []
		for effect in action.get("effects", []):
			var value = int(effect.get("value", 0))
			match effect.get("op", ""):
				"damage", "lifesteal", "block_damage", "summon", "charge_strike", "echo_strike":
					if effect.op == "charge_strike" and bool(enemy.get("hurt_this_turn", false)):
						pieces.append("蓄力已打断")
						continue
					if effect.op == "charge_strike" and int(enemy.status.get("poison", 0)) > 0:
						pieces.append("中毒将打断")
						continue
					value = _enemy_attack_value(value, str(effect.op), enemy)
					var damage = calculate_damage(value, enemy.status, player_status)
					var hits = int(effect.get("hits", 1))
					pieces.append("攻击 %d%s" % [damage, ("×%d" % hits) if hits > 1 else ""])
					if effect.op == "charge_strike":
						pieces.append("可打断")
					elif effect.op == "echo_strike":
						pieces.append("出牌反击 +%d" % _enemy_echo_bonus())
				"block": pieces.append("格挡 %d" % value)
				"sunder": pieces.append("破甲 %d" % value)
				"heal_ally":
					var target := _enemy_heal_target(index)
					if target < 0:
						pieces.append("格挡 %d" % int(effect.get("fallback_block", 0)))
					else:
						var ally: Dictionary = state.enemies[target]
						pieces.append("治疗同伴 %d" % mini(value, int(ally.max_hp) - int(ally.hp)))
				"poison": pieces.append("施毒 %d" % value)
				"weak": pieces.append("虚弱 %d" % value)
				"vulnerable": pieces.append("易伤 %d" % value)
				"strength": pieces.append("力量 +%d" % value)
				"heal": pieces.append("回复 %d" % value)
				"thorns": pieces.append("荆棘 +%d" % value)
				_: pieces.append(str(action.get("intent", "蓄势")))
		if _enemy_pressure(enemy) > 0:
			pieces.append("蓄势 +%d" % _enemy_pressure(enemy))
		if _enemy_desperation(enemy) > 0:
			pieces.append("困兽 +%d" % _enemy_desperation(enemy))
		enemy.intent = " · ".join(pieces)


func _check_battle_end() -> void:
	if state.room != "battle":
		return
	if int(state.hp) <= 0:
		_finish_run(false)
	elif _first_living_enemy() < 0:
		if not _advance_boss_phase():
			_win_battle()


func _advance_boss_phase() -> bool:
	if state.encounter_kind != "boss" or int(state.get("boss_phase", 1)) >= int(state.get("boss_phases", 1)):
		return false
	state.boss_phase = int(state.boss_phase) + 1
	var phase = int(state.boss_phase)
	for index in state.enemies.size():
		var enemy = state.enemies[index]
		enemy.hp = int(enemy.max_hp)
		enemy.block = 0
		enemy.status = {}
		enemy.turn = 0
		enemy.pattern = enemy.get("base_pattern", enemy.pattern).duplicate(true)
		if not enemy.pattern.is_empty():
			for ignored in range(phase - 1):
				enemy.pattern.append(enemy.pattern.pop_front())
			for action in enemy.pattern:
				for effect in action.effects:
					if effect.op in ["damage", "lifesteal", "block_damage"]:
						effect.value = int(effect.value) + (phase - 1) * 2
					elif effect.op == "block":
						effect.value = int(effect.value) + (phase - 1) * 3
		_combat_event("phase", "enemy:%d" % index, "enemy:%d" % index, phase)
	_update_intents()
	_log("首领进入第 %d / %d 阶段：生命恢复，清除自身状态，行动改变。" % [phase, int(state.boss_phases)])
	return true


func _battle_growth() -> void:
	state.growth_wins = int(state.get("growth_wins", 0)) + 1
	var next_level = int(state.growth_wins) / 4
	_heal(4 if state.encounter_kind == "normal" else 6)
	if next_level > int(state.get("growth_level", 0)):
		state.growth_level = next_level
		state.max_hp = int(state.max_hp) + 3
		_heal(5)
		_log("历练升至 %d：生命上限 +3、回复 5；每两历练基础格挡 +1，每三历练初始力量 +1。" % next_level)


func _win_battle() -> void:
	if state.encounter_kind in ["tutorial", "workshop"]:
		_finish_run(true)
		return
	if bool(state.battle_rewarded):
		return
	var key = "%s:%d:%d" % [state.run_id, state.chapter, state.row]
	if state.processed_encounters.has(key):
		return
	state.processed_encounters.append(key)
	state.battle_rewarded = true
	_battle_growth()
	state.room = "reward"
	if state.encounter_kind in ["elite", "boss"]:
		var counter = "elite_wins" if state.encounter_kind == "elite" else "boss_wins"
		profile.stats[counter] = int(profile.stats.get(counter, 0)) + 1
	profile.total_wins = int(profile.total_wins) + 1
	profile.role_wins[state.role] = int(profile.role_wins.get(state.role, 0)) + 1
	var gold = _random_int("loot", 15, 22)
	if state.encounter_kind == "elite":
		gold = _random_int("loot", 30, 40)
	elif state.encounter_kind == "boss":
		gold = 70
	gold = maxi(0, gold + _relic_total("gold_bonus"))
	state.gold = int(state.gold) + gold
	_heal(_relic_total("combat_heal"))
	if state.encounter_kind in ["elite", "boss"]:
		var relic = _random_relic(state.encounter_kind == "boss")
		state.boss_reward = relic
		_gain_relic(relic)
	if state.potions.size() < 3 and _random_int("loot", 0, 99) < 32 and not data.get("potions", []).is_empty():
		var potion = data.potions[_random_int("loot", 0, data.potions.size() - 1)]
		state.potions.append(str(potion.id))
	state.rewards = _make_card_rewards(3, state.encounter_kind == "boss")
	state.reward_rerolls_used = []
	state.reward_seen = []
	_migrate_reward_guidance()
	_log("战斗胜利！获得%d金币，累计胜场%d。" % [gold, profile.total_wins])
	if state.encounter_kind == "elite":
		Items.progress(self, "elite_wins")
	_mark_node_cleared()


func _eligible_cards(rare_only: bool = false) -> Array:
	var cards = []
	for card in data.get("cards", []):
		if card.get("role", "neutral") not in [state.role, "neutral"]:
			continue
		if card.get("rarity", "common") == "starter":
			continue
		if not state.unlocked_snapshot.has(str(card.id)):
			continue
		if int(state.chapter) < int(card.get("min_chapter", 0)):
			continue
		if rare_only and card.get("rarity", "common") != "rare":
			continue
		cards.append(card)
	return cards


func _make_card_rewards(count: int, rare_only: bool = false) -> Array:
	var pool = _eligible_cards(rare_only)
	if pool.size() < count:
		pool = _eligible_cards(false)
	_shuffle(pool, "loot")
	var result = []
	for card in pool.slice(0, mini(count, pool.size())):
		result.append({"id": str(card.id), "upgraded": false})
	return result


func build_plan_options(role_id: String) -> Array:
	return BuildGuides.options(role_id)


func set_build_plan(plan_id: String) -> Dictionary:
	if not state.active:
		return _fail("请先开始一段旅程。")
	var plan = BuildGuides.plan_for(str(state.role), plan_id)
	if plan.is_empty():
		return _fail("请选择当前旅者可用的流派。")
	state.build_plan = plan_id
	return _commit("玩法方向已调整为「%s」。" % plan.name)


func build_recommendation(instance: Dictionary) -> Dictionary:
	var deck_views: Array = []
	for card in state.deck:
		deck_views.append(card_view(card))
	return BuildGuides.recommend(card_view(instance), str(state.role), str(state.get("build_plan", "")), deck_views)


func _migrate_reward_guidance() -> void:
	if BuildGuides.plan_for(str(state.role), str(state.get("build_plan", ""))).is_empty():
		state.build_plan = ""
	if state.room != "reward":
		state.reward_rerolls_used = []
		state.reward_seen = []
		return
	var previous: Array = state.get("reward_rerolls_used", [])
	var used: Array = []
	for index in state.rewards.size():
		used.append(bool(previous[index]) if index < previous.size() else false)
	state.reward_rerolls_used = used
	for card in state.rewards:
		var id = str(card.id)
		if not state.reward_seen.has(id):
			state.reward_seen.append(id)


func _reward_reroll_candidates() -> Array:
	# Apply the same boss rarity fallback as the initial three-card offer, before exclusions.
	var pool = _eligible_cards(state.encounter_kind == "boss")
	if pool.size() < 3:
		pool = _eligible_cards(false)
	var excluded: Array = state.get("reward_seen", []).duplicate()
	for card in state.rewards:
		excluded.append(str(card.id))
	return pool.filter(func(card): return not excluded.has(str(card.id)))


func reward_reroll_view(index: int) -> Dictionary:
	var view = {"available": false, "used": false, "remaining": 0, "reason": ""}
	if state.room != "reward" or not state.active:
		view.reason = "现在没有待选择的卡牌奖励。"
	elif index < 0 or index >= state.rewards.size():
		view.reason = "奖励编号无效。"
	elif _action_busy:
		view.reason = "当前动作尚未完成。"
	else:
		var used: Array = state.get("reward_rerolls_used", [])
		view.used = bool(used[index]) if index < used.size() else false
		view.remaining = 0 if view.used else 1
		if view.used:
			view.reason = "这张候选的刷新机会已用完。"
		elif _reward_reroll_candidates().is_empty():
			view.reason = "当前卡池没有其他未展示卡牌；本次机会未消耗。"
		else:
			view.available = true
	return view


func reroll_reward(index: int) -> Dictionary:
	var view = reward_reroll_view(index)
	if not view.available:
		return _fail(str(view.reason))
	var pool = _reward_reroll_candidates()
	var replacement = pool[_random_int("loot", 0, pool.size() - 1)]
	_migrate_reward_guidance()
	state.reward_rerolls_used[index] = true
	state.rewards[index] = {"id": str(replacement.id), "upgraded": false}
	state.reward_seen.append(str(replacement.id))
	return _commit("已换成「%s」，此位置的刷新机会已用完。" % replacement.name)


func choose_reward(index: int) -> Dictionary:
	if state.room != "reward" or not state.active:
		return _fail("现在没有待选择的卡牌奖励。")
	if index < -1 or index >= state.rewards.size():
		return _fail("奖励编号无效。")
	if index >= 0:
		var card = state.rewards[index].duplicate(true)
		state.deck.append(card)
		_seen(str(card.id))
		_log("%s加入卡组。" % card_view(card).get("name", "新卡"))
	state.rewards.clear()
	state.reward_rerolls_used.clear()
	state.reward_seen.clear()
	if state.encounter_kind == "boss":
		if int(state.chapter) >= 3:
			_finish_run(true)
		else:
			state.chapter = int(state.chapter) + 1
			state.row = -1
			state.lane = -1
			state.map = _make_map()
			state.room = "map"
			state.max_hp = int(state.max_hp) + 8
			_heal(int(ceil(int(state.max_hp) * 0.35)))
			_log("踏入下一章：生命上限 +8，回复35%最大生命；基础能量最多5，每回合抽牌提升至6。")
	else:
		state.room = "map"
	return _commit("已领取奖励。" if index >= 0 else "跳过卡牌奖励。")


func _relic_total(op: String) -> int:
	var total = 0
	for id in state.get("relics", []):
		var effect = relic_data(str(id)).get("effect", {})
		if effect.get("op", "") == op:
			total += int(effect.get("value", 0))
	return total + Items.total(self, op)


func _random_relic(boss: bool = false) -> String:
	var pool = []
	for relic in data.get("relics", []):
		if relic.get("rarity", "") == "starter" or state.relics.has(str(relic.id)):
			continue
		if relic.get("role", "neutral") not in ["neutral", state.role]:
			continue
		if boss and relic.get("rarity", "") not in ["rare", "boss"]:
			continue
		pool.append(str(relic.id))
	if pool.is_empty() and boss:
		return _random_relic(false)
	return "" if pool.is_empty() else pool[_random_int("loot", 0, pool.size() - 1)]


func _gain_relic(id: String) -> void:
	var relic = relic_data(id)
	if relic.is_empty() or state.relics.has(id):
		return
	state.relics.append(id)
	var effect = relic.get("effect", {})
	if effect.get("op", "") == "max_hp":
		var gain = int(effect.get("value", 0))
		state.max_hp = int(state.max_hp) + gain
		state.hp = int(state.hp) + gain


func _make_shop() -> void:
	state.shop = []
	for card in _make_card_rewards(4):
		var definition = card_data(str(card.id))
		var price = {"common": 35, "uncommon": 55, "rare": 85}.get(str(definition.get("rarity", "common")), 35)
		state.shop.append({"kind": "card", "id": card.id, "price": _shop_price(price), "sold": false})
	var relic = _random_relic(false)
	if not relic.is_empty():
		state.shop.append({"kind": "relic", "id": relic, "price": _shop_price(100), "sold": false})
	var goods := Items.available(self, ["positive"])
	_shuffle(goods, "loot")
	for good in goods.slice(0, mini(3, goods.size())):
		state.shop.append({"kind":"item", "id":good.id, "price":_shop_price(int(good.price)), "sold":false})
	if not data.get("potions", []).is_empty():
		var potion = data.potions[_random_int("loot", 0, data.potions.size() - 1)]
		state.shop.append({"kind": "potion", "id": potion.id, "price": _shop_price(28), "sold": false})
	state.shop.append({"kind": "remove", "id": "", "price": _shop_price(45), "sold": false})


func _shop_price(base: int) -> int:
	return int(ceil(base * 1.15)) if int(state.difficulty) >= 3 else base


func buy_item(index: int) -> Dictionary:
	if state.room != "shop" or not state.active or index < 0 or index >= state.shop.size():
		return _fail("商品不存在。")
	var item = state.shop[index]
	if item.sold:
		return _fail("这件商品已售出。")
	if int(state.gold) < int(item.price):
		return _fail("金币不足。")
	if item.kind == "potion" and state.potions.size() >= 3:
		return _fail("药剂栏已满，请先在战斗中使用药剂。")
	if item.kind == "item" and (item_data(str(item.id)).get("kind", "") != "positive" or not Items.can_gain(self, str(item.id))):
		return _fail("该道具不可购买或已拥有。")
	if item.kind == "remove":
		if state.deck.size() <= 5:
			return _fail("卡组至少保留五张牌。")
		state.selected_shop_remove = index
		return _commit("请选择要删除的卡牌；选择后才扣款。")
	state.gold = int(state.gold) - int(item.price)
	item.sold = true
	match item.kind:
		"card":
			state.deck.append({"id": str(item.id), "upgraded": false})
			_seen(str(item.id))
		"relic": _gain_relic(str(item.id))
		"potion": state.potions.append(str(item.id))
		"item": Items.gain(self, str(item.id))
	Items.progress(self, "shop_gold", int(item.price))
	return _commit("购买成功。")


func remove_card(deck_index: int) -> Dictionary:
	var item_index = int(state.get("selected_shop_remove", -1))
	if state.room != "shop" or item_index < 0 or item_index >= state.shop.size():
		return _fail("请先选择商店的删牌服务。")
	var item = state.shop[item_index]
	if item.sold or state.deck.size() <= 5 or deck_index < 0 or deck_index >= state.deck.size() or int(state.gold) < int(item.price):
		return _fail("无法删除这张卡牌。")
	state.deck.remove_at(deck_index)
	state.gold = int(state.gold) - int(item.price)
	item.sold = true
	state.selected_shop_remove = -1
	Items.progress(self, "shop_gold", int(item.price))
	return _commit("卡牌已从本局卡组移除。")


func rest(upgrade_deck_index: int = -1) -> Dictionary:
	if state.room != "rest" or not state.active:
		return _fail("只有篝火节点可以休息或升级。")
	if upgrade_deck_index < -1 or upgrade_deck_index >= state.deck.size():
		return _fail("请选择正确的卡牌。")
	if upgrade_deck_index >= 0 and state.deck[upgrade_deck_index].get("upgraded", false):
		return _fail("这张牌已经升级。")
	if upgrade_deck_index < 0:
		_heal(int(state.max_hp) - int(state.hp))
		_log("篝火暖意恢复了全部生命。")
	else:
		state.deck[upgrade_deck_index].upgraded = true
		profile.stats.cards_upgraded = int(profile.stats.cards_upgraded) + 1
		Items.progress(self, "cards_upgraded")
		_log("强化了%s。" % card_view(state.deck[upgrade_deck_index]).get("name", "卡牌"))
	_mark_node_cleared()
	state.room = "map"
	return _commit("休整完毕。")


func discard_negative_item(id: String) -> Dictionary:
	if not state.active or state.room != "rest":
		return _fail("只有营地可以舍弃负面道具。")
	if not state.items.has(id) or not Items.is_negative(item_data(id)):
		return _fail("请选择一件随行的负面道具。")
	if int(state.hp) <= Items.CAMP_COST:
		return _fail("需要至少 %d 点当前生命，无法支付。" % (Items.CAMP_COST + 1))
	state.hp = int(state.hp) - Items.CAMP_COST
	state.items.erase(id)
	_log("在营地失去 %d 生命，舍弃「%s」。" % [Items.CAMP_COST, item_data(id).name])
	_mark_node_cleared()
	state.room = "map"
	return _commit("已舍弃「%s」，失去 %d 生命。" % [item_data(id).name, Items.CAMP_COST])


func choose_event(index: int) -> Dictionary:
	if state.room != "event" or not state.active:
		return _fail("当前没有可选择的事件。")
	var choices = state.event.get("choices", [])
	if index < 0 or index >= choices.size():
		return _fail("选项不存在。")
	var choice = choices[index]
	var relic_id = str(choice.get("relic", ""))
	if not relic_id.is_empty() and state.relics.has(relic_id):
		return _fail("已拥有此遗物，请选择其他选项。")
	var offered: Array = choice.get("items", [])
	var seen: Array = []
	for id in offered:
		if seen.has(id) or not Items.can_gain(self, str(id)) or item_data(str(id)).kind == "sacred":
			return _fail("道具已领取或不可领取，请选择其他选项。")
		seen.append(id)
	if int(state.gold) + int(choice.get("gold", 0)) < 0:
		return _fail("金币不足，无法选择此项。")
	if int(state.hp) + int(choice.get("hp", 0)) <= 0:
		return _fail("生命不足，无法支付这一代价。")
	if int(state.max_hp) + int(choice.get("max_hp", 0)) <= 0:
		return _fail("最大生命不足。")
	state.gold = int(state.gold) + int(choice.get("gold", 0))
	state.max_hp = int(state.max_hp) + int(choice.get("max_hp", 0))
	state.hp = mini(int(state.max_hp), int(state.hp) + int(choice.get("hp", 0)))
	_heal(int(choice.get("heal", 0)))
	var card_id = str(choice.get("card", ""))
	if not card_data(card_id).is_empty():
		state.deck.append({"id": card_id, "upgraded": false})
		_seen(card_id)
	_gain_relic(relic_id)
	_log("%s：%s" % [state.event.get("name", "事件"), choice.get("label", "继续")])
	_mark_node_cleared()
	for id in offered:
		Items.gain(self, str(id))
	state.room = "map"
	return _commit("选择已生效。")


func use_potion(slot: int, target_index: int = 0) -> Dictionary:
	_reset_combat_events()
	if state.room != "battle" or not state.active or slot < 0 or slot >= state.potions.size() or _action_busy:
		return _fail("现在无法使用这瓶药剂。")
	var potion = potion_data(str(state.potions[slot]))
	if potion.is_empty():
		return _fail("药剂内容不可用。")
	if _requires_enemy(potion.get("effects", [])) and not _valid_target(target_index):
		return _fail("请选择仍然存活的敌人。")
	_action_busy = true
	state.potions.remove_at(slot)
	_combat_recording = true
	for effect in potion.get("effects", []):
		if state.room != "battle":
			break
		_player_effect(effect, target_index)
		_check_battle_end()
	_action_busy = false
	_log("使用%s。" % potion.get("name", "药剂"))
	_update_intents()
	return _commit("药剂已使用。")


func leave_room() -> Dictionary:
	if not state.active or state.room not in ["shop", "treasure"]:
		return _fail("请先完成当前节点。")
	_mark_node_cleared()
	state.selected_shop_remove = -1
	state.room = "map"
	return _commit("返回路线图。")


func _mark_node_cleared() -> void:
	if int(state.row) >= 0 and int(state.row) < state.map.size() and int(state.lane) >= 0:
		var node: Dictionary = state.map[int(state.row)][int(state.lane)]
		if not bool(node.get("cleared", false)):
			node.cleared = true
			Items.complete_node(self)


func _finish_run(victory: bool) -> void:
	state.room = "victory" if victory else "defeat"
	state.active = false
	if state.encounter_kind in ["tutorial", "workshop"]:
		return
	if state.get("history_recorded", false):
		return
	state.history_recorded = true
	if victory:
		profile.clears[state.role] = int(profile.clears.get(state.role, 0)) + 1
		if int(state.difficulty) >= 0:
			profile.ascension[state.role] = mini(MAX_DIFFICULTY, maxi(unlocked_difficulty(str(state.role)), int(state.difficulty) + 1))
		_log("长夜退去。四章旅程完成！")
	else:
		_log("旅程结束。已经获得的解锁进度将永久保留。")
	profile.history.push_front({"run_id": state.run_id, "role": state.role, "seed": state.seed, "chapter": state.chapter, "row": state.row, "victory": victory, "difficulty": state.difficulty, "turns": state.elapsed_turns, "date": Time.get_datetime_string_from_system()})
	while profile.history.size() > 30:
		profile.history.pop_back()


func abandon_run() -> Dictionary:
	if state.active:
		_finish_run(false)
	state = _blank_state()
	_rng.clear()
	return _commit("已结束本局，永久解锁已保留。")


func _seen(id: String) -> void:
	if not profile.seen_cards.has(id):
		profile.seen_cards.append(id)


func _log(message: String) -> void:
	state.log.append(message)
	while state.log.size() > 12:
		state.log.pop_front()


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


func _commit(message: String) -> Dictionary:
	_combat_recording = false
	_sync_rng()
	if not _item_notices.is_empty():
		message += " " + " ".join(_item_notices)
		_item_notices.clear()
	if state.encounter_kind in ["tutorial", "workshop"]:
		return {"ok": true, "message": message}
	var unlocked = Progression.unlock(profile, sacred_ids().size(), data.get("cards", []).size())
	if not save_game():
		return {"ok": true, "message": message + "（自动保存失败，请勿关闭游戏。）", "save_error": last_error, "achievements": unlocked}
	return {"ok": true, "message": message, "achievements": unlocked}


func _reset_combat_events() -> void:
	combat_events.clear()
	_combat_recording = false


func _combat_event(kind: String, source: String, target: String, amount: int = 0, blocked: int = 0, style: String = "slash") -> void:
	if not _combat_recording:
		return
	combat_events.append({"kind": kind, "source": source, "target": target, "amount": amount, "blocked": blocked, "style": style})


func _combat_damage(source: String, target: String, hp_before: int, hp_after: int, blocked: int) -> void:
	var style = "poison" if source == "poison" else ("projectile" if source.begins_with("summon:") else "slash")
	_combat_event("damage", source, target, hp_before - hp_after, blocked, style)
	if hp_before > 0 and hp_after <= 0:
		if target.begins_with("enemy:") and state.encounter_kind == "boss" and int(state.get("boss_phase", 1)) < int(state.get("boss_phases", 1)):
			return
		_combat_event("death", source, target)


func save_game() -> bool:
	if _save_path.is_empty():
		return true
	_sync_rng()
	var envelope = {"save_version": SAVE_VERSION, "content_version": data.get("version", "1"), "profile": profile, "state": state}
	var absolute = ProjectSettings.globalize_path(_save_path)
	var directory = absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var error = DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			last_error = "无法建立存档目录：%s" % error_string(error)
			return false
	var temporary = absolute + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入临时存档：%s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		last_error = "存档写入失败：%s" % error_string(write_error)
		return false
	if FileAccess.file_exists(absolute):
		var previous = FileAccess.get_file_as_bytes(absolute)
		var backup = FileAccess.open(absolute + ".bak", FileAccess.WRITE)
		if backup == null:
			last_error = "无法保留上一份存档。"
			return false
		backup.store_buffer(previous)
		backup.flush()
		backup.close()
	var rename_error = DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		last_error = "无法提交存档：%s" % error_string(rename_error)
		return false
	last_error = ""
	return true


func load_game() -> bool:
	if _save_path.is_empty():
		return false
	for path in [_save_path, _save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not _valid_save(parsed):
			continue
		profile = _new_profile()
		profile.merge(_normalize_numbers(parsed.profile), true)
		_migrate_progression()
		state = _blank_state()
		state.merge(_normalize_numbers(parsed.state), true)
		_migrate_reward_guidance()
		_restore_rng()
		last_error = "已从上一份备份恢复存档。" if path.ends_with(".bak") else ""
		return true
	last_error = "存档损坏或版本不兼容，原文件已保留；未自动覆盖。"
	return false


func _normalize_numbers(val):
	if val is float:
		if is_equal_approx(val, round(val)):
			return int(round(val))
		return val
	elif val is Dictionary:
		var normalized = {}
		for key in val:
			normalized[str(key)] = _normalize_numbers(val[key])
		return normalized
	elif val is Array:
		var normalized = []
		for item in val:
			normalized.append(_normalize_numbers(item))
		return normalized
	return val


func _valid_save(value) -> bool:
	if not value is Dictionary or int(value.get("save_version", -1)) != SAVE_VERSION:
		return false
	if str(_normalize_numbers(value.get("content_version", ""))) != str(data.get("version", "1")):
		return false
	if not value.get("profile") is Dictionary or not value.get("state") is Dictionary:
		return false
	var saved = value.state
	if saved.get("encounter_kind") == "workshop":
		return false
	if not saved.get("build_plan", "") is String or not saved.get("reward_rerolls_used", []) is Array or not saved.get("reward_seen", []) is Array:
		return false
	for used in saved.get("reward_rerolls_used", []):
		if not used is bool:
			return false
	for id in saved.get("reward_seen", []):
		if not id is String:
			return false
	if not saved.get("items", {}) is Dictionary or not saved.get("item_claimed", []) is Array:
		return false
	for id in saved.get("items", {}):
		var record = saved.items[id]
		if item_data(str(id)).is_empty() or not record is Dictionary or not record.has("remaining") or not record.has("progress"):
			return false
	for key in ["active", "role", "room", "hp", "max_hp", "deck", "map", "hand", "draw", "discard", "exhaust", "enemies", "rng_states"]:
		if not saved.has(key):
			return false
	if saved.room not in ["map", "battle", "reward", "shop", "rest", "event", "treasure", "victory", "defeat"]:
		return false
	if saved.active and (role_data(str(saved.role)).is_empty() or not saved.deck is Array or int(saved.get("max_hp", 0)) <= 0):
		return false
	for zone in ["deck", "hand", "draw", "discard", "exhaust"]:
		if not saved[zone] is Array:
			return false
		for card in saved[zone]:
			if not card is Dictionary or card_data(str(card.get("id", ""))).is_empty():
				return false
	return true


func _migrate_progression() -> void:
	var defaults = _new_profile()
	for section in ["settings", "stats"]:
		var merged: Dictionary = defaults[section].duplicate(true)
		if profile.get(section) is Dictionary:
			merged.merge(profile[section], true)
		profile[section] = merged
	for key in ["music_volume", "sound_volume", "combat_speed"]:
		profile.settings[key] = float(profile.settings[key])
	if not profile.get("achievements") is Dictionary:
		profile.achievements = {}
	var collected: Array = []
	for id in profile.get("seen_cards", []):
		if not card_data(str(id)).is_empty() and not collected.has(str(id)):
			collected.append(str(id))
	profile.seen_cards = collected
	var sacred: Array = []
	var valid_sacred := sacred_ids()
	if profile.get("sacred_collection") is Array:
		for id in profile.sacred_collection:
			if valid_sacred.has(id) and not sacred.has(id):
				sacred.append(id)
	profile.sacred_collection = sacred
	# Legacy saves have no detailed counters: keep them at zero rather than invent history.
	Progression.unlock(profile, valid_sacred.size(), data.get("cards", []).size())


func achievement_entries() -> Array:
	return Progression.entries(profile, sacred_ids().size(), data.get("cards", []).size())


func update_setting(key: String, value: Variant) -> Dictionary:
	match key:
		"music", "sound", "reduced_motion":
			if not value is bool:
				return _fail("设置值无效。")
		"music_volume", "sound_volume":
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
				return _fail("音量需要在 0 到 1 之间。")
		"combat_speed":
			if not (value is float or value is int) or value not in [1.0, 1.5, 2.0]:
				return _fail("动画速度无效。")
		_:
			return _fail("未知设置。")
	profile.settings[key] = value
	return _commit("设置已保存。")
