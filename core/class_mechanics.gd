extends RefCounted
## Character-specific combat rules. Static helpers avoid owning the rules engine.

const RESONANCE_MAX := 6
const RESONANCE_COST := 3
const CINDER_MAX := 8

static func start_combat(g) -> void:
	g.state.stars = 3 if g.state.role == "arcanist" else 0
	g.state.blade = 0
	g.state.blade_created = false
	g.state.orbs = []
	g.state.orb_slots = 3
	g.state.osty_hp = 0
	g.state.pending_discard = 0
	if g.state.role == "sister":
		channel(g, "lightning")
	# 铁甲战士的开场誓约：先有1点力量，力量牌与多段攻击从第一回合就有落点。
	if g.state.role == "warden":
		g._add_status(g.state.status, "strength", 1)
	if g.state.role == "bellscribe":
		g.state.status.resonance = 2


static func start_turn(g) -> void:
	var strength = int(g.state.status.get("strength_each_turn", 0))
	if strength > 0:
		g._add_status(g.state.status, "strength", strength)
		g._combat_event("status", "player", "player", strength, 0, "strength")
	if g.state.role == "medium":
		g.state.osty_hp = int(g.state.get("osty_hp", 0)) + 1
	if g.state.role == "sister":
		for orb in g.state.get("orbs", []):
			if orb.kind == "plasma":
				g.state.energy = int(g.state.energy) + 1


static func turn_draw(g) -> int:
	# 寂静猎手：第一回合额外抽2张，作为主动弃牌与机巧的启动资源。
	return 2 if g.state.role == "ranger" and int(g.state.turn) == 1 else 0


static func apply(g, op: String, value: int, effect: Dictionary, target_index: int) -> bool:
	match op:
		"stars": g.state.stars = int(g.state.get("stars", 0)) + value
		"forge":
			g.state.blade = int(g.state.get("blade", 0)) + value
			if not g.state.get("blade_created", false):
				g.state.blade_created = true
				add_token(g, "token_blade")
		"fetch_blade":
			for zone in ["draw", "discard", "exhaust"]:
				for index in range(g.state[zone].size() - 1, -1, -1):
					if g.state[zone][index].id == "token_blade" and g.state.hand.size() < 10:
						g.state.hand.append(g.state[zone].pop_at(index))
						if g._combat_recording:
							g._combat_event("draw", zone, "player", 1)
							g.combat_events.back()["card"] = g.state.hand.back().duplicate(true)
							g.combat_events.back()["hand_index"] = g.state.hand.size() - 1
		"minion":
			for index in g.state.hand.size():
				if g.state.hand[index].id != "token_blade":
					g.state.hand[index] = {"id": "token_minion", "upgraded": false}
		"osty_summon":
			g.state.osty_hp = int(g.state.get("osty_hp", 0)) + value
			g._combat_event("status", "player", "player", value, 0, "osty")
		"osty_attack":
			if int(g.state.get("osty_hp", 0)) > 0:
				var targets = []
				if effect.get("target", "") == "all":
					for index in g.state.enemies.size():
						if g._valid_target(index): targets.append(index)
				elif g._valid_target(target_index): targets.append(target_index)
				for hit in clampi(int(effect.get("hits", 1)), 1, 30):
					for index in targets:
						if g.state.room == "battle" and g._valid_target(index):
							g._damage_enemy(index, g.calculate_damage(value, {}, g.state.enemies[index].status), false, "osty")
							g._check_battle_end()
		"osty_sacrifice": g.state.osty_hp = 0
		"doom":
			if effect.get("target", "") == "self":
				g._add_status(g.state.status, "doom", value)
			else:
				for index in g.state.enemies.size():
					if g._valid_target(index) and (effect.get("target", "") == "all" or index == target_index):
						g._add_status(g.state.enemies[index].status, "doom", value)
						g._combat_event("status", "player", "enemy:%d" % index, value, 0, "doom")
		"soul_card":
			for ignored in mini(value, 10): add_token(g, "token_soul")
		"shiv":
			for ignored in mini(value, 10): add_token(g, "token_shiv")
		"discard":
			g.state.pending_discard = mini(g.state.hand.size(), int(g.state.get("pending_discard", 0)) + value)
		"poison_multiply":
			for index in g.state.enemies.size():
				if g._valid_target(index) and (effect.get("target", "") == "all" or index == target_index):
					var extra = int(g.state.enemies[index].status.get("poison", 0)) * maxi(0, value - 1)
					g._add_status(g.state.enemies[index].status, "poison", extra)
					g._combat_event("status", "player", "enemy:%d" % index, extra, 0, "poison")
		"channel":
			for ignored in mini(value, 10):
				if g.state.room == "battle": channel(g, str(effect.get("orb", "lightning")))
		"evoke":
			for ignored in mini(value, 10):
				if not g.state.get("orbs", []).is_empty() and g.state.room == "battle":
					evoke(g, g.state.orbs.pop_front())
		"dualcast":
			if not g.state.get("orbs", []).is_empty():
				var orb = g.state.orbs.pop_front()
				for ignored in mini(value, 10):
					if g.state.room == "battle": evoke(g, orb)
		"orb_slots": g.state.orb_slots = mini(10, int(g.state.get("orb_slots", 3)) + value)
		"resonance":
			var previous := int(g.state.status.get("resonance", 0))
			var total := mini(RESONANCE_MAX, previous + value)
			g.state.status.resonance = total
			if total > previous:
				g._combat_event("status", "player", "player", total - previous, 0, "resonance")
		"resonant_damage", "resonant_block":
			var recipient := str(effect.get("target", ""))
			if op == "resonant_damage":
				var has_target: bool = g._first_living_enemy() >= 0 if recipient == "all" else g._valid_target(target_index)
				if not has_target:
					return true
			var charge := int(g.state.status.get("resonance", 0))
			if charge >= RESONANCE_COST:
				g.state.status.resonance = charge - RESONANCE_COST
				g._log("共鸣消耗%d回响。" % RESONANCE_COST)
				var base_op := "damage" if op == "resonant_damage" else "block"
				g._player_effect({"op": base_op, "value": value, "target": recipient}, target_index)
		"cinder", "ignite":
			for index in g.state.enemies.size():
				if not g._valid_target(index) or (effect.get("target", "") != "all" and index != target_index):
					continue
				var enemy: Dictionary = g.state.enemies[index]
				var stacks := int(enemy.status.get("cinder", 0))
				if op == "cinder":
					var total := mini(CINDER_MAX, stacks + value)
					enemy.status.cinder = total
					if total > stacks:
						g._combat_event("status", "player", "enemy:%d" % index, total - stacks, 0, "cinder")
				elif stacks > 0:
					enemy.status.erase("cinder")
					g._log("引燃%s的%d层余烬。" % [enemy.name, stacks])
					g._damage_enemy(index, stacks * value, false, "cinder")
		"focus", "dexterity", "intangible", "frail", "exhaust_block", "exhaust_draw", "strength_each_turn", "retain_block", "shiv_damage", "discard_draw", "discard_energy", "soul_summon":
			g._add_status(g.state.status, op, value)
			g._combat_event("status", "player", "player", value, 0, op)
		_: return false
	return true


static func on_play(g, card: Dictionary) -> void:
	if card.id == "token_soul":
		var amount = int(g.state.status.get("soul_summon", 0))
		if amount > 0:
			g.state.osty_hp = int(g.state.get("osty_hp", 0)) + amount
			g._combat_event("status", "player", "player", amount, 0, "osty")


static func on_discard(g) -> void:
	# Only explicit player discards reach this hook; end-turn cleanup does not.
	if g.state.room != "battle":
		return
	g.state.energy = int(g.state.energy) + int(g.state.status.get("discard_energy", 0))
	g._draw_cards(int(g.state.status.get("discard_draw", 0)))


static func add_token(g, id: String) -> void:
	var instance = {"id": id, "upgraded": false}
	if g.state.hand.size() >= 10:
		g.state.discard.append(instance)
		return
	g.state.hand.append(instance)
	if g._combat_recording:
		g._combat_event("draw", "created", "player", 1)
		g.combat_events.back()["card"] = instance.duplicate(true)
		g.combat_events.back()["hand_index"] = g.state.hand.size() - 1


static func channel(g, kind: String) -> void:
	if g.state.orbs.size() >= int(g.state.get("orb_slots", 3)):
		evoke(g, g.state.orbs.pop_front())
	if g.state.room == "battle":
		g.state.orbs.append({"kind": kind, "value": 6 if kind == "dark" else 4})
		g._combat_event("status", "player", "player", 1, 0, kind)


static func orb_damage(g, amount: int, all: bool = false, lowest: bool = false) -> void:
	var targets = []
	for index in g.state.enemies.size():
		if g._valid_target(index): targets.append(index)
	if targets.is_empty(): return
	if not all:
		var target = targets[0]
		if lowest:
			for index in targets:
				if int(g.state.enemies[index].hp) < int(g.state.enemies[target].hp): target = index
		else:
			target = targets[g._random_int("battle", 0, targets.size() - 1)]
		targets = [target]
	for index in targets:
		g._damage_enemy(index, maxi(0, amount), false, "orb")
		g._check_battle_end()


static func evoke(g, orb: Dictionary) -> void:
	var focus = int(g.state.status.get("focus", 0))
	match str(orb.kind):
		"lightning": orb_damage(g, 8 + focus)
		"frost":
			var amount = maxi(0, 5 + focus)
			g.state.block = int(g.state.block) + amount
			g._combat_event("block", "player", "player", amount)
		"dark": orb_damage(g, int(orb.value), false, true)
		"plasma": g.state.energy = int(g.state.energy) + 2
		"glass": orb_damage(g, maxi(0, int(orb.value) + focus) * 2, true)


static func end_turn(g) -> void:
	for orb in g.state.get("orbs", []).duplicate():
		if g.state.room != "battle": return
		var focus = int(g.state.status.get("focus", 0))
		match str(orb.kind):
			"lightning": orb_damage(g, 3 + focus)
			"frost":
				var amount = maxi(0, 2 + focus)
				g.state.block = int(g.state.block) + amount
				g._combat_event("block", "player", "player", amount)
			"dark": orb.value = int(orb.value) + maxi(0, 6 + focus)
			"glass":
				orb_damage(g, int(orb.value) + focus, true)
				orb.value = maxi(0, int(orb.value) - 1)


static func check_doom(g, index: int) -> void:
	if g._valid_target(index):
		var enemy = g.state.enemies[index]
		if int(enemy.status.get("doom", 0)) >= int(enemy.hp):
			var before = int(enemy.hp)
			enemy.hp = 0
			g._combat_damage("doom", "enemy:%d" % index, before, 0, 0)
			g._log("%s在其回合结束时被灾厄收割。" % enemy.name)
			g._check_battle_end()
