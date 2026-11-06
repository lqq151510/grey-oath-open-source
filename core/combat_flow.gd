extends RefCounted
## Combat pipeline, extracted verbatim from core/game_engine.gd.
## Engine counterparts: _start_battle() ... _win_battle() and use_potion().
## Every function is static, takes the engine as first argument and only
## touches it through engine.state / engine.profile / engine.xxx() so the
## engine can keep thin wrappers for its existing call sites.

const Classes = preload("res://core/class_mechanics.gd")
const Items = preload("res://core/item_mechanics.gd")
const BattleTactics = preload("res://core/battle_tactics.gd")
const Oaths = preload("res://core/oath_mechanics.gd")


static func _start_battle(engine, kind: String) -> void:
	engine.state.room = "battle"
	engine.state.tactical_points = 0
	engine.state.tactical_last_type = ""
	engine.state.tactical_gained = 0
	engine.state.tactical_used = false
	engine.state.turn = 0
	engine.state.block = 0
	engine.state.energy = 0
	engine.state.status = {}
	engine.state.souls = 0
	engine.state.marks = []
	engine.state.summons = []
	engine.state.combo = 0
	engine.state.first_damage_used = false
	engine.state.battle_rewarded = false
	engine.state.hand = []
	engine.state.draw = engine.state.deck.duplicate(true)
	engine.state.discard = []
	engine.state.exhaust = []
	engine.state.enemies = []
	engine.state.rewards = []
	engine.state.boss_reward = ""
	engine._shuffle(engine.state.draw, "battle")
	var pool = []
	for enemy in engine.data.get("enemies", []):
		if int(enemy.get("chapter", 0)) == int(engine.state.chapter) and enemy.get("kind", "normal") == kind:
			pool.append(enemy)
	if pool.is_empty():
		engine.last_error = "关卡没有可用敌人。"
		engine.state.room = "map"
		engine.state.row = int(engine.state.row) - 1
		return
	var escorts = []
	if kind == "elite":
		for enemy in engine.data.get("enemies", []):
			if int(enemy.get("chapter", 0)) == int(engine.state.chapter) and enemy.get("kind", "normal") == "normal":
				escorts.append(enemy)
		if escorts.is_empty():
			engine.last_error = "精英关卡没有可用的本章小怪。"
			engine.state.room = "map"
			engine.state.row = int(engine.state.row) - 1
			return
	var count = 3 if kind == "elite" else 1
	if kind == "normal":
		count = engine._random_int("battle", 1, 3)
	var difficulty := int(engine.state.difficulty)
	for index in range(count):
		var candidates = escorts if kind == "elite" and index > 0 else pool
		var definition = candidates[engine._random_int("battle", 0, candidates.size() - 1)]
		var enemy_kind = str(definition.get("kind", kind))
		var hp = int(definition.get("hp", 30))
		if count > 1 and enemy_kind == "normal":
			hp = maxi(10, int(hp * (0.55 if count == 2 else 0.40) if kind == "elite" else hp * (0.85 if count == 2 else 0.70)))
		if difficulty >= 1 and enemy_kind == "normal":
			hp = int(ceil(hp * 1.10))
		if kind == "boss":
			if difficulty >= 4:
				hp = int(ceil(hp * 1.15))
			hp = maxi(1, int(ceil(hp * (0.92 if int(engine.state.chapter) == 0 else 0.82))))
			if difficulty >= 8:
				hp = ceili(hp * 120.0 / 100.0)
		elif difficulty >= 6 and enemy_kind == "elite":
			hp = ceili(hp * 115.0 / 100.0)
		match difficulty:
			-2: hp = maxi(1, floori(hp * 65.0 / 100.0))
			-1: hp = maxi(1, floori(hp * 80.0 / 100.0))
		engine.state.enemies.append({"id": str(definition.id), "kind": enemy_kind, "escort": kind == "elite" and index > 0, "name": str(definition.name), "hp": hp, "max_hp": hp, "block": 0, "status": {}, "pattern": definition.pattern.duplicate(true), "turn": 0, "intent": "", "color": definition.get("color", "#c7a279")})
	engine.state.boss_phase = 1
	engine.state.boss_phases = (2 if int(engine.state.chapter) == 0 else 3) if kind == "boss" else 1
	if kind == "boss":
		for enemy in engine.state.enemies:
			enemy["base_pattern"] = enemy.pattern.duplicate(true)
	engine._apply_battle_modifiers(kind)
	engine.state.status.strength = engine._relic_total("start_strength") + int(engine.state.chapter) + mini(3, int(engine.state.get("growth_level", 0)) / 3) + Oaths.value(engine.state.modifiers, "start_strength")
	engine._log("遭遇%s。" % "、".join(engine._enemy_names()))
	Classes.start_combat(engine)
	engine._begin_player_turn()
	engine.state.block = int(engine.state.block) + engine._relic_total("start_block") + Oaths.value(engine.state.modifiers, "start_block")
	engine._update_intents()

static func _apply_battle_modifiers(engine, kind: String) -> void:
	## Twists are resolved once per battle so reloading mid-combat cannot reroll them.
	engine.state.elite_affix = ""
	var enemy_hp_pct := Oaths.value(engine.state.modifiers, "enemy_hp_pct")
	if enemy_hp_pct != 0:
		for enemy in engine.state.enemies:
			var scaled := maxi(1, ceili(float(enemy.hp) * (100.0 + float(enemy_hp_pct)) / 100.0))
			enemy.hp = scaled
			enemy.max_hp = scaled
	if kind != "elite":
		return
	var affix: Dictionary = Oaths.pick_affix(int(engine.state.seed) + int(engine.state.chapter) * 131 + int(engine.state.row) * 17)
	engine.state.elite_affix = str(affix.get("id", ""))
	var mods: Dictionary = affix.get("modifiers", {})
	var elite_hp_pct := Oaths.value(mods, "hp_pct") + Oaths.value(engine.state.modifiers, "elite_hp_pct")
	var start_block := Oaths.value(mods, "start_block")
	var thorns := Oaths.value(mods, "start_thorns")
	for enemy in engine.state.enemies:
		if bool(enemy.get("escort", false)):
			continue
		enemy["affix"] = engine.state.elite_affix
		if elite_hp_pct != 0:
			var scaled := maxi(1, ceili(float(enemy.hp) * (100.0 + float(elite_hp_pct)) / 100.0))
			enemy.hp = scaled
			enemy.max_hp = scaled
		if start_block > 0:
			enemy.block = int(enemy.block) + start_block
		if thorns > 0:
			enemy.status["thorns"] = int(enemy.status.get("thorns", 0)) + thorns
	if not engine.state.elite_affix.is_empty():
		engine._log("精英词缀「%s」：%s" % [str(affix.get("name", "")), str(affix.get("description", ""))])

static func _enemy_names(engine) -> Array[String]:
	var result: Array[String] = []
	for enemy in engine.state.enemies:
		result.append(str(enemy.name))
	return result

static func _begin_player_turn(engine) -> void:
	engine.state.turn = int(engine.state.turn) + 1
	engine.state.tactical_last_type = ""
	engine.state.tactical_gained = 0
	engine.state.tactical_used = false
	engine.state.elapsed_turns = int(engine.state.elapsed_turns) + 1
	if int(engine.state.status.get("retain_block", 0)) <= 0:
		engine.state.block = 0
	engine.state.energy = 3 + mini(1, int(engine.state.chapter)) + int(engine.state.status.get("next_energy", 0))
	if int(engine.state.turn) == 1:
		engine.state.energy += Oaths.value(engine.state.modifiers, "first_turn_energy")
	engine.state.status.next_energy = 0
	if str(engine.state.get("elite_affix", "")) == "hunger" and int(engine.state.turn) > 1:
		for enemy in engine.state.enemies:
			if not bool(enemy.get("escort", false)):
				enemy.status["strength"] = int(enemy.status.get("strength", 0)) + 1
	engine.state.combo = 0
	engine.state.cards_played_this_turn = 0
	for enemy in engine.state.enemies:
		enemy.erase("hurt_this_turn")
	engine.state.sister_used = false
	var poison = int(engine.state.status.get("poison", 0))
	if poison > 0:
		var hp_before = int(engine.state.hp)
		engine.state.hp = maxi(0, int(engine.state.hp) - poison)
		engine._combat_damage("poison", "player", hp_before, int(engine.state.hp), 0)
		engine.state.status.poison = poison - 1
		engine._log("中毒损失%d生命。" % poison)
		if int(engine.state.hp) <= 0:
			engine._finish_run(false)
			return
	var regen = int(engine.state.status.get("regen", 0))
	if regen > 0:
		engine._heal(regen)
		engine.state.status.regen = regen - 1
	var turn_block = engine._relic_total("turn_block") + mini(4, int(engine.state.get("growth_level", 0)) / 2)
	engine.state.block = int(engine.state.block) + turn_block
	if turn_block > 0:
		engine._combat_event("block", "player", "player", turn_block)
	engine._heal(engine._relic_total("turn_heal"))
	Classes.start_turn(engine)
	engine._combat_event("turn_start", "player", "player", int(engine.state.turn))
	engine._draw_cards(5 + mini(1, int(engine.state.chapter)) + engine._relic_total("turn_draw") + (2 if engine.state.role == "ranger" and int(engine.state.turn) == 1 else 0) + (Oaths.value(engine.state.modifiers, "first_turn_draw") if int(engine.state.turn) == 1 else 0))

static func _draw_cards(engine, amount: int) -> void:
	for ignored in range(clampi(amount, 0, 100)):
		if engine.state.hand.size() >= 10:
			break
		if engine.state.draw.is_empty():
			if engine.state.discard.is_empty():
				break
			engine.state.draw = engine.state.discard.duplicate(true)
			engine.state.discard.clear()
			engine._shuffle(engine.state.draw, "battle")
		engine.state.hand.append(engine.state.draw.pop_back())
		if engine._combat_recording:
			engine._combat_event("draw", "draw", "player", 1)
			engine.combat_events.back()["card"] = engine.state.hand.back().duplicate(true)
			engine.combat_events.back()["hand_index"] = engine.state.hand.size() - 1

static func _valid_target(engine, index: int) -> bool:
	return index >= 0 and index < engine.state.enemies.size() and int(engine.state.enemies[index].hp) > 0

static func play_card(engine, hand_index: int, target_index: int = 0) -> Dictionary:
	engine._reset_combat_events()
	if not engine.state.active or engine.state.room != "battle" or engine._action_busy:
		return engine._fail("现在不能出牌。")
	if int(engine.state.get("pending_discard", 0)) > 0:
		return engine._fail("请先完成弃牌选择。")
	if hand_index < 0 or hand_index >= engine.state.hand.size():
		return engine._fail("这张牌已经不在手中。")
	var instance = engine.state.hand[hand_index]
	var card = engine.card_view(instance)
	if card.is_empty():
		return engine._fail("卡牌内容不可用。")
	if int(card.cost) > int(engine.state.energy):
		return engine._fail("能量不足。")
	if int(card.get("star_cost", 0)) > int(engine.state.get("stars", 0)):
		return engine._fail("星辰不足。")
	if int(card.get("soul_cost", 0)) > int(engine.state.souls):
		return engine._fail("灵魂不足。")
	if engine._requires_enemy(card.effects) and not engine._valid_target(target_index):
		return engine._fail("请选择仍然存活的敌人。")
	engine._action_busy = true
	engine._combat_recording = true
	engine.state.energy = int(engine.state.energy) - int(card.cost)
	engine.state.stars = int(engine.state.get("stars", 0)) - int(card.get("star_cost", 0))
	engine.state.souls = int(engine.state.souls) - int(card.get("soul_cost", 0))
	engine.state.hand.remove_at(hand_index)
	engine.profile.stats.cards_played = int(engine.profile.stats.cards_played) + 1
	engine.state.cards_played_this_turn = int(engine.state.get("cards_played_this_turn", 0)) + 1
	if card.get("type", "skill") == "attack":
		engine.state.combo = int(engine.state.combo) + 1
		Items.progress(engine, "attacks_played")
	engine._log("打出%s。" % card.name)
	engine._record_tactical_play(str(card.get("type", "")))
	Classes.on_play(engine, card)
	for effect in card.effects:
		if engine.state.room != "battle":
			break
		engine._player_effect(effect, target_index)
		engine._check_battle_end()
	if card.get("exhaust", false):
		engine._exhaust_instance(instance)
	elif card.get("type", "") == "power":
		engine.state.exhaust.append(instance)
	else:
		engine.state.discard.append(instance)
	engine._action_busy = false
	engine._update_intents()
	return engine._commit("已打出%s。" % card.name)

static func _record_tactical_play(engine, card_type: String) -> void:
	var chain := BattleTactics.next_chain(int(engine.state.get("tactical_points", 0)), int(engine.state.get("tactical_gained", 0)), str(engine.state.get("tactical_last_type", "")), card_type)
	engine.state.tactical_points = chain.points
	engine.state.tactical_gained = chain.gained
	engine.state.tactical_last_type = chain.last_type
	if int(chain.added) > 0:
		engine._log("连携：应变 +1（%d / %d）。" % [int(chain.points), BattleTactics.MAX_POINTS])
		engine._combat_event("status", "player", "player", 1, 0, "tactical_points")

static func tactics_view(engine, target_index: int = 0) -> Dictionary:
	var points := int(engine.state.get("tactical_points", 0))
	var gained := int(engine.state.get("tactical_gained", 0))
	var used := bool(engine.state.get("tactical_used", false))
	var last_type := str(engine.state.get("tactical_last_type", ""))
	var common_reason := ""
	if not engine.state.active or engine.state.room != "battle" or int(engine.state.hp) <= 0 or engine._first_living_enemy() < 0:
		common_reason = "现在不能发动战术。"
	elif engine._action_busy:
		common_reason = "当前动作尚未结算完成。"
	elif int(engine.state.get("pending_discard", 0)) > 0:
		common_reason = "请先完成弃牌选择。"
	elif used:
		common_reason = "本回合已发动战术，下回合恢复。"
	elif points < BattleTactics.COST:
		common_reason = "应变不足，需要 2 点。"
	var options: Array = []
	for definition in BattleTactics.OPTIONS:
		var option: Dictionary = definition.duplicate(true)
		option["title"] = BattleTactics.option_title(str(option.id), int(engine.state.chapter))
		option["description"] = BattleTactics.option_description(str(option.id), int(engine.state.chapter))
		var reason := common_reason
		if str(option.id) == "strike":
			if reason.is_empty() and not engine._valid_target(target_index):
				reason = "请选择仍然存活的敌人。"
			if engine._valid_target(target_index):
				var enemy: Dictionary = engine.state.enemies[target_index]
				var damage := 1 if int(enemy.status.get("intangible", 0)) > 0 else BattleTactics.strike_damage(int(engine.state.chapter))
				var loss := mini(int(enemy.hp), maxi(0, damage - int(enemy.block)))
				option.description += "\n当前目标：%s，预计损失 %d 生命。" % [str(enemy.name), loss]
		elif str(option.id) == "cycle" and reason.is_empty():
			if engine.state.hand.size() > 10 - BattleTactics.CYCLE_DRAW:
				reason = "手牌空位不足，需要至少 2 个空位。"
			elif engine.state.draw.size() + engine.state.discard.size() < BattleTactics.CYCLE_DRAW:
				reason = "可抽牌不足，抽牌堆与弃牌堆合计需至少 2 张。"
		option["available"] = reason.is_empty()
		option["reason"] = reason
		options.append(option)
	return {"points": points, "max_points": BattleTactics.MAX_POINTS, "cost": BattleTactics.COST, "gained": gained, "gain_limit": BattleTactics.GAIN_LIMIT, "used": used, "last_type": last_type, "hint": BattleTactics.chain_hint(points, gained, last_type), "options": options}

static func use_tactic(engine, id: String, target_index: int = 0) -> Dictionary:
	engine._reset_combat_events()
	var selected: Dictionary = {}
	for option in engine.tactics_view(target_index).options:
		if str(option.id) == id:
			selected = option
			break
	if selected.is_empty():
		return engine._fail("未知的战术。")
	if not bool(selected.available):
		return engine._fail(str(selected.reason))
	engine._action_busy = true
	engine._combat_recording = true
	engine.state.tactical_points = int(engine.state.tactical_points) - BattleTactics.COST
	engine.state.tactical_used = true
	engine._log("发动%s，消耗 %d 点应变。" % [str(selected.name), BattleTactics.COST])
	match id:
		"strike":
			engine._damage_enemy(target_index, BattleTactics.strike_damage(int(engine.state.chapter)), false)
		"guard":
			var guard_block := BattleTactics.guard_block(int(engine.state.chapter))
			engine.state.block = int(engine.state.block) + guard_block
			engine._combat_event("block", "player", "player", guard_block)
		"cycle":
			engine._draw_cards(BattleTactics.CYCLE_DRAW)
			engine._player_effect({"op": "discard", "value": 1}, target_index)
	engine._check_battle_end()
	engine._action_busy = false
	engine._update_intents()
	return engine._commit("已发动%s。" % str(selected.name))

static func _effect_value(engine, effect: Dictionary, target_index: int = 0) -> int:
	var base = int(effect.get("value", 0))
	var scale = 0
	match effect.get("scale", ""):
		"block": scale = int(engine.state.block)
		"combo": scale = int(engine.state.combo)
		"souls": scale = int(engine.state.souls)
		"stars": scale = int(engine.state.get("stars", 0))
		"blade": scale = int(engine.state.get("blade", 0))
		"missing_hp": scale = int(engine.state.max_hp) - int(engine.state.hp)
		"poison":
			if engine._valid_target(target_index):
				scale = int(engine.state.enemies[target_index].status.get("poison", 0))
	return maxi(0, base + int(floor(scale * float(effect.get("factor", 1.0)))))

static func _player_effect(engine, effect: Dictionary, target_index: int) -> void:
	var value = engine._effect_value(effect, target_index)
	var op = str(effect.get("op", ""))
	var target = str(effect.get("target", ""))
	if Classes.apply(engine, op, value, effect, target_index):
		return
	var indexes = []
	if target == "all":
		for i in range(engine.state.enemies.size()):
			if engine._valid_target(i):
				indexes.append(i)
	elif engine._valid_target(target_index):
		indexes.append(target_index)
	match op:
		"damage", "lifesteal", "block_damage":
			if op == "block_damage":
				value += int(engine.state.block)
			var first_bonus = 0
			if not bool(engine.state.first_damage_used):
				first_bonus = engine._relic_total("first_damage")
				engine.state.first_damage_used = true
			for hit in range(clampi(int(effect.get("hits", 1)), 1, 30)):
				for index in indexes:
					if not engine._valid_target(index) or int(engine.state.hp) <= 0:
						continue
					var damage = engine.calculate_damage(value + first_bonus, engine.state.status, engine.state.enemies[index].status)
					first_bonus = 0
					var dealt = engine._damage_enemy(index, damage, true)
					if op == "lifesteal" and int(engine.state.hp) > 0:
						engine._heal(dealt)
		"block":
			value = maxi(0, value + int(engine.state.status.get("dexterity", 0)))
			if int(engine.state.status.get("frail", 0)) > 0:
				value = int(floor(value * 0.75))
			engine.state.block = int(engine.state.block) + value
			engine._combat_event("block", "player", "player", value)
		"draw": engine._draw_cards(value)
		"energy": engine.state.energy = int(engine.state.energy) + value
		"heal": engine._heal(value)
		"self_damage":
			var hp_before = int(engine.state.hp)
			if int(engine.state.status.get("intangible", 0)) > 0:
				value = mini(1, value)
			engine.state.hp = maxi(0, int(engine.state.hp) - value)
			engine._combat_damage("self", "player", hp_before, int(engine.state.hp), 0)
			engine._log("献血：失去%d生命。" % value)
			if int(engine.state.hp) <= 0:
				engine._finish_run(false)
		"poison", "weak", "vulnerable":
			if target == "self":
				engine._add_status(engine.state.status, op, value)
				engine._combat_event("status", "player", "player", value, 0, op)
			else:
				if op == "poison":
					value += engine._relic_total("poison_bonus")
				for index in indexes:
					engine._add_status(engine.state.enemies[index].status, op, value)
					engine._combat_event("status", "player", "enemy:%d" % index, value, 0, op)
		"strength", "thorns", "regen", "next_energy":
			engine._add_status(engine.state.status, op, value)
			engine._combat_event("status", "player", "player", value, 0, op)
		"soul": engine.state.souls = int(engine.state.souls) + value
		"summon":
			if engine.state.summons.size() >= 3:
				var replace = 0
				for i in range(1, engine.state.summons.size()):
					if int(engine.state.summons[i].turns) < int(engine.state.summons[replace].turns):
						replace = i
				engine.state.summons.remove_at(replace)
			engine.state.summons.append({"power": value, "turns": 3})
		"mark":
			engine.state.marks.append(clampi(value, 1, 3))
			if engine.state.marks.size() >= 3:
				var last = int(engine.state.marks.back())
				engine.state.marks.clear()
				match last:
					1:
						for i in range(engine.state.enemies.size()):
							if engine._valid_target(i):
								engine._damage_enemy(i, engine.calculate_damage(8, engine.state.status, engine.state.enemies[i].status), false)
						engine._log("日印共鸣：日火扫过敌阵。")
					2:
						engine.state.block = int(engine.state.block) + 12
						engine._combat_event("block", "player", "player", 12)
						engine._log("月印共鸣：获得12格挡。")
					3:
						engine._draw_cards(2)
						engine._log("星印共鸣：抽取2张牌。")
		"cleanse":
			for status in ["poison", "weak", "vulnerable"]:
				engine.state.status[status] = 0
		"exhaust_hand":
			var removed = engine.state.hand.duplicate()
			engine.state.hand = []
			for instance in removed:
				engine._exhaust_instance(instance)
			engine._draw_cards(value)

static func _exhaust_instance(engine, instance: Dictionary) -> void:
	engine.state.exhaust.append(instance)
	if engine.state.room != "battle":
		return
	var block = int(engine.state.status.get("exhaust_block", 0))
	engine.state.block = int(engine.state.block) + block
	if block > 0:
		engine._combat_event("block", "player", "player", block)
	engine._draw_cards(int(engine.state.status.get("exhaust_draw", 0)))

static func choose_discard(engine, index: int, target_index: int = 0) -> Dictionary:
	engine._reset_combat_events()
	if engine.state.room != "battle" or not engine.state.active or engine._action_busy or int(engine.state.get("pending_discard", 0)) <= 0:
		return engine._fail("现在不需要选择弃牌。")
	if index < 0 or index >= engine.state.hand.size():
		return engine._fail("请选择手牌中的卡牌。")
	engine._action_busy = true
	engine._combat_recording = true
	engine.state.pending_discard = int(engine.state.pending_discard) - 1
	var instance = engine.state.hand.pop_at(index)
	var card = engine.card_view(instance)
	if card.get("sly", false):
		engine._log("机巧：%s被主动弃置，免费打出。" % card.name)
		engine.profile.stats.cards_played = int(engine.profile.stats.cards_played) + 1
		engine.state.cards_played_this_turn = int(engine.state.get("cards_played_this_turn", 0)) + 1
		if card.get("type", "") == "attack":
			engine.state.combo = int(engine.state.combo) + 1
			Items.progress(engine, "attacks_played")
		Classes.on_play(engine, card)
		for effect in card.effects:
			if engine.state.room != "battle": break
			engine._player_effect(effect, target_index if engine._valid_target(target_index) else engine._first_living_enemy())
			engine._check_battle_end()
		if card.get("type", "") == "power":
			engine.state.exhaust.append(instance)
		elif card.get("exhaust", false):
			engine._exhaust_instance(instance)
		else:
			engine.state.discard.append(instance)
	else:
		engine.state.discard.append(instance)
	Classes.on_discard(engine)
	engine.state.pending_discard = mini(int(engine.state.pending_discard), engine.state.hand.size())
	engine._action_busy = false
	engine._update_intents()
	return engine._commit("已完成一次弃牌选择。")

static func calculate_damage(engine, base: int, source_status: Dictionary, target_status: Dictionary) -> int:
	var amount = float(maxi(0, base + int(source_status.get("strength", 0))))
	if int(source_status.get("weak", 0)) > 0:
		amount *= 0.75
	if int(target_status.get("vulnerable", 0)) > 0:
		amount *= 1.5
	return maxi(0, int(floor(amount)))

static func preview_card(engine, hand_index: int, target_index: int = 0) -> Dictionary:
	if hand_index < 0 or hand_index >= engine.state.hand.size():
		return {}
	var card = engine.card_view(engine.state.hand[hand_index])
	var result = {"damage": 0, "block": 0, "cost": card.get("cost", 0)}
	var has_target: bool = engine._valid_target(target_index)
	var resonance := int(engine.state.status.get("resonance", 0))
	var cinder := int(engine.state.enemies[target_index].status.get("cinder", 0)) if has_target else 0
	for effect in card.get("effects", []):
		var value = engine._effect_value(effect, target_index)
		if effect.op == "block":
			result.block += value
		if effect.op in ["damage", "lifesteal", "block_damage"] and has_target:
			if effect.op == "block_damage":
				value += int(engine.state.block)
			result.damage += engine.calculate_damage(value, engine.state.status, engine.state.enemies[target_index].status) * int(effect.get("hits", 1))
		# As with ordinary hits, previews report raw damage before enemy block.
		match effect.op:
			"resonance": resonance = mini(Classes.RESONANCE_MAX, resonance + value)
			"resonant_damage":
				if has_target and resonance >= Classes.RESONANCE_COST:
					resonance -= Classes.RESONANCE_COST
					result.damage += engine.calculate_damage(value, engine.state.status, engine.state.enemies[target_index].status)
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

static func _add_status(engine, target: Dictionary, key: String, amount: int) -> void:
	var total = int(target.get(key, 0)) + amount
	target[key] = total if key == "strength" else maxi(0, total)

static func _damage_enemy(engine, index: int, amount: int, retaliate: bool = true, source: String = "player") -> int:
	if not engine._valid_target(index):
		return 0
	var enemy = engine.state.enemies[index]
	if int(enemy.status.get("intangible", 0)) > 0:
		amount = mini(1, amount)
	var absorbed = mini(int(enemy.block), amount)
	enemy.block = int(enemy.block) - absorbed
	var dealt = mini(int(enemy.hp), maxi(0, amount - absorbed))
	var hp_before = int(enemy.hp)
	enemy.hp = maxi(0, int(enemy.hp) - dealt)
	engine._combat_damage(source, "enemy:%d" % index, hp_before, int(enemy.hp), absorbed)
	if dealt > 0:
		enemy.hurt_this_turn = true
		engine._log("%s受到%d伤害。" % [enemy.name, dealt])
	var thorns = int(enemy.status.get("thorns", 0))
	if retaliate and amount > 0 and thorns > 0:
		engine._damage_player(thorns, -1, false, "thorns")
	return dealt

static func _damage_player(engine, amount: int, source_index: int = -1, retaliate: bool = true, source: String = "") -> int:
	if int(engine.state.status.get("intangible", 0)) > 0:
		amount = mini(1, amount)
	var absorbed = mini(int(engine.state.block), amount)
	engine.state.block = int(engine.state.block) - absorbed
	var remainder = maxi(0, amount - absorbed)
	if source_index >= 0 and engine.state.role == "medium" and int(engine.state.get("osty_hp", 0)) > 0:
		var protected = mini(int(engine.state.osty_hp), remainder)
		engine.state.osty_hp = int(engine.state.osty_hp) - protected
		remainder -= protected
		if protected > 0:
			engine._combat_event("osty_guard", "osty", "player", protected)
	var dealt = mini(int(engine.state.hp), remainder)
	var hp_before = int(engine.state.hp)
	engine.state.hp = maxi(0, int(engine.state.hp) - dealt)
	var actor = source if not source.is_empty() else ("enemy:%d" % source_index if source_index >= 0 else "self")
	engine._combat_damage(actor, "player", hp_before, int(engine.state.hp), absorbed)
	if dealt > 0:
		engine._log("受到%d伤害。" % dealt)
	if int(engine.state.hp) <= 0:
		engine._finish_run(false)
		return dealt
	var thorns = int(engine.state.status.get("thorns", 0))
	if retaliate and amount > 0 and thorns > 0 and engine._valid_target(source_index):
		engine._damage_enemy(source_index, thorns, false, "thorns")
	return dealt

static func _heal(engine, amount: int) -> void:
	if amount > 0 and int(engine.state.hp) > 0:
		var hp_before = int(engine.state.hp)
		engine.state.hp = mini(int(engine.state.max_hp), int(engine.state.hp) + amount)
		if int(engine.state.hp) > hp_before:
			engine._combat_event("heal", "player", "player", int(engine.state.hp) - hp_before)

static func _decay_turn_status(engine, status: Dictionary) -> void:
	for key in ["weak", "vulnerable", "frail"]:
		status[key] = maxi(0, int(status.get(key, 0)) - 1)

static func end_turn(engine) -> Dictionary:
	engine._reset_combat_events()
	if not engine.state.active or engine.state.room != "battle" or engine._action_busy:
		return engine._fail("现在不能结束回合。")
	engine._action_busy = true
	engine._combat_recording = true
	if int(engine.state.get("pending_discard", 0)) > 0:
		engine._action_busy = false
		engine._combat_recording = false
		return engine._fail("请先完成弃牌选择。")
	engine._combat_event("turn_end", "player", "player", int(engine.state.turn))
	var retained = []
	var old_hand = engine.state.hand.duplicate()
	engine.state.hand = retained
	for card in old_hand:
		if engine.card_view(card).get("ethereal", false):
			engine._exhaust_instance(card)
		elif engine.card_view(card).get("retain", false):
			retained.append(card)
		else:
			engine.state.discard.append(card)
	Classes.end_turn(engine)
	if int(engine.state.status.get("doom", 0)) >= int(engine.state.hp):
		engine.state.hp = 0
		engine._finish_run(false)
	for summon_index in range(engine.state.summons.size()):
		var summon = engine.state.summons[summon_index]
		if engine.state.room != "battle":
			break
		var target = engine._first_living_enemy()
		if target >= 0:
			engine._damage_enemy(target, int(summon.power), false, "summon:%d" % summon_index)
			summon.turns = int(summon.turns) - 1
			engine._check_battle_end()
	var kept_summons = []
	for summon in engine.state.summons:
		if int(summon.turns) > 0:
			kept_summons.append(summon)
	engine.state.summons = kept_summons
	engine._decay_turn_status(engine.state.status)
	for index in range(engine.state.enemies.size()):
		if engine.state.room != "battle":
			break
		if not engine._valid_target(index):
			continue
		var enemy = engine.state.enemies[index]
		enemy.block = 0
		var poison = int(enemy.status.get("poison", 0))
		if poison > 0:
			var hp_before = int(enemy.hp)
			enemy.hp = maxi(0, int(enemy.hp) - poison)
			enemy.hurt_this_turn = true
			engine._combat_damage("poison", "enemy:%d" % index, hp_before, int(enemy.hp), 0)
			enemy.status.poison = poison - 1
			engine._log("%s受到%d中毒伤害。" % [enemy.name, poison])
			engine._check_battle_end()
			if engine.state.room != "battle" or not engine._valid_target(index):
				continue
		var regen = int(enemy.status.get("regen", 0))
		if regen > 0:
			var hp_before = int(enemy.hp)
			enemy.hp = mini(int(enemy.max_hp), int(enemy.hp) + regen)
			if int(enemy.hp) > hp_before:
				engine._combat_event("heal", "enemy:%d" % index, "enemy:%d" % index, int(enemy.hp) - hp_before)
			enemy.status.regen = regen - 1
		var pattern = enemy.pattern
		if not pattern.is_empty():
			var action = pattern[int(enemy.turn) % pattern.size()]
			for effect in action.get("effects", []):
				if engine.state.room != "battle" or not engine._valid_target(index):
					break
				engine._enemy_effect(effect, index)
				engine._check_battle_end()
		if engine.state.room == "battle":
			Classes.check_doom(engine, index)
		enemy.turn = int(enemy.turn) + 1
		engine._decay_turn_status(enemy.status)
	engine.state.status.intangible = maxi(0, int(engine.state.status.get("intangible", 0)) - 1)
	if engine.state.room == "battle":
		engine._begin_player_turn()
		engine._update_intents()
	engine._action_busy = false
	return engine._commit("回合结束。")

static func _enemy_pressure(engine, enemy: Dictionary) -> int:
	# Prolonged fights become more dangerous; existing turn counters keep saves compatible.
	return mini(3, int(enemy.get("turn", 0)) / 2)

static func _enemy_desperation(engine, enemy: Dictionary) -> int:
	# Wounded enemies threaten a final counterattack; no extra persistent state.
	return 2 if int(enemy.get("hp", 0)) > 0 and int(enemy.hp) * 2 <= int(enemy.get("max_hp", 1)) else 0

static func _enemy_attack_value(engine, value: int, op: String, enemy: Dictionary) -> int:
	if op == "block_damage":
		value += int(enemy.block)
	elif op == "echo_strike":
		value += engine._enemy_echo_bonus()
	value += engine._enemy_pressure(enemy) + engine._enemy_desperation(enemy)
	var difficulty := int(engine.state.difficulty)
	if difficulty >= 0:
		# 标准及以上难度：敌方攻击随章节推进，精英额外凶险。
		value += int(engine.state.chapter)
		if str(enemy.get("kind", engine.state.encounter_kind)) == "elite":
			value += 1
	if difficulty >= 2 and str(enemy.get("kind", engine.state.encounter_kind)) == "elite":
		value = int(ceil(value * 1.10))
	if difficulty >= 7:
		return ceili(value * 115.0 / 100.0)
	match difficulty:
		-2: return maxi(0, floori(value * 70.0 / 100.0))
		-1: return maxi(0, floori(value * 85.0 / 100.0))
	return value

static func _enemy_echo_bonus(engine) -> int:
	return 2 * clampi(int(engine.state.get("cards_played_this_turn", 0)) - 3, 0, 3)

static func _enemy_heal_target(engine, index: int) -> int:
	var target := -1
	var biggest_wound := 0
	for candidate in range(engine.state.enemies.size()):
		if candidate == index or not engine._valid_target(candidate):
			continue
		var ally: Dictionary = engine.state.enemies[candidate]
		var missing := int(ally.max_hp) - int(ally.hp)
		if missing > biggest_wound:
			biggest_wound = missing
			target = candidate
	return target

static func _enemy_effect(engine, effect: Dictionary, index: int) -> void:
	var enemy = engine.state.enemies[index]
	var value = maxi(0, int(effect.get("value", 0)))
	var op = str(effect.get("op", ""))
	match op:
		"damage", "lifesteal", "block_damage", "summon", "charge_strike", "echo_strike":
			if op == "charge_strike" and bool(enemy.get("hurt_this_turn", false)):
				engine._log("%s的钟槌蓄力被打断。" % enemy.name)
				return
			value = engine._enemy_attack_value(value, op, enemy)
			for hit in range(clampi(int(effect.get("hits", 1)), 1, 30)):
				if engine.state.room != "battle" or not engine._valid_target(index):
					break
				var dealt = engine._damage_player(engine.calculate_damage(value, enemy.status, engine.state.status), index)
				if op == "lifesteal" and engine._valid_target(index):
					var hp_before = int(enemy.hp)
					enemy.hp = mini(int(enemy.max_hp), int(enemy.hp) + dealt)
					if int(enemy.hp) > hp_before:
						engine._combat_event("heal", "enemy:%d" % index, "enemy:%d" % index, int(enemy.hp) - hp_before)
		"block":
			enemy.block = int(enemy.block) + value
			engine._combat_event("block", "enemy:%d" % index, "enemy:%d" % index, value)
		"sunder":
			var removed := mini(int(engine.state.block), value)
			if removed > 0:
				engine.state.block = int(engine.state.block) - removed
				engine._log("%s剥离了%d点格挡。" % [enemy.name, removed])
				engine._combat_event("status", "enemy:%d" % index, "player", removed, 0, "sunder")
		"heal_ally":
			var target: int = engine._enemy_heal_target(index)
			if target < 0:
				engine._enemy_effect({"op": "block", "value": int(effect.get("fallback_block", 0))}, index)
				return
			var ally: Dictionary = engine.state.enemies[target]
			var restored := mini(value, int(ally.max_hp) - int(ally.hp))
			ally.hp = int(ally.hp) + restored
			engine._log("%s为%s回复%d点生命。" % [enemy.name, ally.name, restored])
			engine._combat_event("heal", "enemy:%d" % index, "enemy:%d" % target, restored)
		"heal":
			var hp_before = int(enemy.hp)
			enemy.hp = mini(int(enemy.max_hp), int(enemy.hp) + value)
			if int(enemy.hp) > hp_before:
				engine._combat_event("heal", "enemy:%d" % index, "enemy:%d" % index, int(enemy.hp) - hp_before)
		"self_damage":
			var hp_before = int(enemy.hp)
			enemy.hp = maxi(0, int(enemy.hp) - value)
			engine._combat_damage("self", "enemy:%d" % index, hp_before, int(enemy.hp), 0)
		"poison", "weak", "vulnerable":
			engine._add_status(enemy.status if effect.get("target", "enemy") == "self" else engine.state.status, op, value)
			engine._combat_event("status", "enemy:%d" % index, "enemy:%d" % index if effect.get("target", "enemy") == "self" else "player", value, 0, op)
		"strength", "thorns", "regen":
			engine._add_status(enemy.status, op, value)
			engine._combat_event("status", "enemy:%d" % index, "enemy:%d" % index, value, 0, op)
		"cleanse":
			for key in ["poison", "weak", "vulnerable"]:
				enemy.status[key] = 0

static func _first_living_enemy(engine) -> int:
	for i in range(engine.state.enemies.size()):
		if engine._valid_target(i):
			return i
	return -1

static func _update_intents(engine) -> void:
	var player_status: Dictionary = engine.state.status.duplicate()
	engine._decay_turn_status(player_status)
	for index in range(engine.state.enemies.size()):
		var enemy: Dictionary = engine.state.enemies[index]
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
					value = engine._enemy_attack_value(value, str(effect.op), enemy)
					var damage = engine.calculate_damage(value, enemy.status, player_status)
					var hits = int(effect.get("hits", 1))
					pieces.append("攻击 %d%s" % [damage, ("×%d" % hits) if hits > 1 else ""])
					if effect.op == "charge_strike":
						pieces.append("可打断")
					elif effect.op == "echo_strike":
						pieces.append("出牌反击 +%d" % engine._enemy_echo_bonus())
				"block": pieces.append("格挡 %d" % value)
				"sunder": pieces.append("破甲 %d" % value)
				"heal_ally":
					var target: int = engine._enemy_heal_target(index)
					if target < 0:
						pieces.append("格挡 %d" % int(effect.get("fallback_block", 0)))
					else:
						var ally: Dictionary = engine.state.enemies[target]
						pieces.append("治疗同伴 %d" % mini(value, int(ally.max_hp) - int(ally.hp)))
				"poison": pieces.append("施毒 %d" % value)
				"weak": pieces.append("虚弱 %d" % value)
				"vulnerable": pieces.append("易伤 %d" % value)
				"strength": pieces.append("力量 +%d" % value)
				"heal": pieces.append("回复 %d" % value)
				"thorns": pieces.append("荆棘 +%d" % value)
				_: pieces.append(str(action.get("intent", "蓄势")))
		if engine._enemy_pressure(enemy) > 0:
			pieces.append("蓄势 +%d" % engine._enemy_pressure(enemy))
		if engine._enemy_desperation(enemy) > 0:
			pieces.append("困兽 +%d" % engine._enemy_desperation(enemy))
		enemy.intent = " · ".join(pieces)

static func _check_battle_end(engine) -> void:
	if engine.state.room != "battle":
		return
	if int(engine.state.hp) <= 0:
		engine._finish_run(false)
	elif engine._first_living_enemy() < 0:
		if not engine._advance_boss_phase():
			engine._win_battle()

static func _advance_boss_phase(engine) -> bool:
	if engine.state.encounter_kind != "boss" or int(engine.state.get("boss_phase", 1)) >= int(engine.state.get("boss_phases", 1)):
		return false
	engine.state.boss_phase = int(engine.state.boss_phase) + 1
	var phase = int(engine.state.boss_phase)
	for index in engine.state.enemies.size():
		var enemy = engine.state.enemies[index]
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
		engine._combat_event("phase", "enemy:%d" % index, "enemy:%d" % index, phase)
	engine._update_intents()
	engine._log("首领进入第 %d / %d 阶段：生命恢复，清除自身状态，行动改变。" % [phase, int(engine.state.boss_phases)])
	return true

static func _battle_growth(engine) -> void:
	engine.state.growth_wins = int(engine.state.get("growth_wins", 0)) + 1
	var next_level = int(engine.state.growth_wins) / 4
	engine._heal(4 if engine.state.encounter_kind == "normal" else 6)
	if next_level > int(engine.state.get("growth_level", 0)):
		engine.state.growth_level = next_level
		engine.state.max_hp = int(engine.state.max_hp) + 3
		engine._heal(5)
		engine._log("历练升至 %d：生命上限 +3、回复 5；每两历练基础格挡 +1，每三历练初始力量 +1。" % next_level)

static func _win_battle(engine) -> void:
	if engine.state.encounter_kind in ["tutorial", "workshop"]:
		engine._finish_run(true)
		return
	if bool(engine.state.battle_rewarded):
		return
	var key = "%s:%d:%d" % [engine.state.run_id, engine.state.chapter, engine.state.row]
	if engine.state.processed_encounters.has(key):
		return
	engine.state.processed_encounters.append(key)
	engine.state.battle_rewarded = true
	engine._battle_growth()
	engine.state.room = "reward"
	if engine.state.encounter_kind in ["elite", "boss"]:
		var counter = "elite_wins" if engine.state.encounter_kind == "elite" else "boss_wins"
		engine.profile.stats[counter] = int(engine.profile.stats.get(counter, 0)) + 1
	engine.profile.total_wins = int(engine.profile.total_wins) + 1
	engine.profile.role_wins[engine.state.role] = int(engine.profile.role_wins.get(engine.state.role, 0)) + 1
	if engine.state.encounter_kind == "elite":
		engine.state.run_elites = int(engine.state.run_elites) + 1
	elif engine.state.encounter_kind == "boss":
		engine.state.run_bosses = int(engine.state.run_bosses) + 1
	var gold = engine._random_int("loot", 15, 22)
	if engine.state.encounter_kind == "elite":
		gold = engine._random_int("loot", 30, 40)
	elif engine.state.encounter_kind == "boss":
		gold = 70
	gold = maxi(0, gold + engine._relic_total("gold_bonus") + Oaths.value(engine.state.modifiers, "combat_gold_flat"))
	engine.state.gold = int(engine.state.gold) + gold
	engine._heal(engine._relic_total("combat_heal"))
	var blood_price := Oaths.value(engine.state.modifiers, "combat_heal")
	if blood_price < 0:
		engine.state.hp = maxi(1, int(engine.state.hp) + blood_price)
	elif blood_price > 0:
		engine._heal(blood_price)
	if engine.state.encounter_kind in ["elite", "boss"]:
		var relic = engine._random_relic(engine.state.encounter_kind == "boss")
		engine.state.boss_reward = relic
		engine._gain_relic(relic)
	if engine.state.potions.size() < 3 and engine._random_int("loot", 0, 99) < 32 and not engine.data.get("potions", []).is_empty():
		var potion = engine.data.potions[engine._random_int("loot", 0, engine.data.potions.size() - 1)]
		engine.state.potions.append(str(potion.id))
	engine.state.rewards = engine._make_card_rewards(3, engine.state.encounter_kind == "boss")
	if engine.state.encounter_kind == "elite" and Oaths.value(engine.state.modifiers, "elite_reward_rare") > 0:
		for extra in engine._make_card_rewards(1, true):
			var repeated := false
			for owned in engine.state.rewards:
				if str(owned.id) == str(extra.id):
					repeated = true
			if not repeated:
				engine.state.rewards.append(extra)
	engine.state.reward_rerolls_used = []
	engine.state.reward_seen = []
	engine._migrate_reward_guidance()
	engine._log("战斗胜利！获得%d金币，累计胜场%d。" % [gold, engine.profile.total_wins])
	if engine.state.encounter_kind == "elite":
		Items.progress(engine, "elite_wins")
	engine._mark_node_cleared()

static func use_potion(engine, slot: int, target_index: int = 0) -> Dictionary:
	engine._reset_combat_events()
	if engine.state.room != "battle" or not engine.state.active or slot < 0 or slot >= engine.state.potions.size() or engine._action_busy:
		return engine._fail("现在无法使用这瓶药剂。")
	var potion = engine.potion_data(str(engine.state.potions[slot]))
	if potion.is_empty():
		return engine._fail("药剂内容不可用。")
	if engine._requires_enemy(potion.get("effects", [])) and not engine._valid_target(target_index):
		return engine._fail("请选择仍然存活的敌人。")
	engine._action_busy = true
	engine.state.potions.remove_at(slot)
	engine._combat_recording = true
	for effect in potion.get("effects", []):
		if engine.state.room != "battle":
			break
		engine._player_effect(effect, target_index)
		engine._check_battle_end()
	engine._action_busy = false
	engine._log("使用%s。" % potion.get("name", "药剂"))
	engine._update_intents()
	return engine._commit("药剂已使用。")
