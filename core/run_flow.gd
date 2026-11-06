extends RefCounted
## Run flow: card rewards, shop, camp, events and relics, extracted verbatim
## from core/game_engine.gd. Every function is static and takes the engine
## instance as its first argument. Engine counterparts keep the same names.

const BuildGuides = preload("res://core/build_guides.gd")
const Items = preload("res://core/item_mechanics.gd")
const Oaths = preload("res://core/oath_mechanics.gd")


static func _eligible_cards(engine, rare_only: bool = false) -> Array:
	var cards = []
	for card in engine.data.get("cards", []):
		if card.get("role", "neutral") not in [engine.state.role, "neutral"]:
			continue
		if card.get("rarity", "common") == "starter":
			continue
		if not engine.state.unlocked_snapshot.has(str(card.id)):
			continue
		if int(engine.state.chapter) < int(card.get("min_chapter", 0)):
			continue
		if rare_only and card.get("rarity", "common") != "rare":
			continue
		cards.append(card)
	return cards


static func _make_card_rewards(engine, count: int, rare_only: bool = false) -> Array:
	var pool = _eligible_cards(engine, rare_only)
	if pool.size() < count:
		pool = _eligible_cards(engine, false)
	engine._shuffle(pool, "loot")
	var result = []
	for card in pool.slice(0, mini(count, pool.size())):
		result.append({"id": str(card.id), "upgraded": false})
	return result


static func build_plan_options(engine, role_id: String) -> Array:
	return BuildGuides.options(role_id)


static func set_build_plan(engine, plan_id: String) -> Dictionary:
	if not engine.state.active:
		return engine._fail("请先开始一段旅程。")
	var plan = BuildGuides.plan_for(str(engine.state.role), plan_id)
	if plan.is_empty():
		return engine._fail("请选择当前旅者可用的流派。")
	engine.state.build_plan = plan_id
	return engine._commit("玩法方向已调整为「%s」。" % plan.name)


static func build_recommendation(engine, instance: Dictionary) -> Dictionary:
	var deck_views: Array = []
	for card in engine.state.deck:
		deck_views.append(engine.card_view(card))
	return BuildGuides.recommend(engine.card_view(instance), str(engine.state.role), str(engine.state.get("build_plan", "")), deck_views)


static func _migrate_reward_guidance(engine) -> void:
	if BuildGuides.plan_for(str(engine.state.role), str(engine.state.get("build_plan", ""))).is_empty():
		engine.state.build_plan = ""
	if engine.state.room != "reward":
		engine.state.reward_rerolls_used = []
		engine.state.reward_seen = []
		return
	var previous: Array = engine.state.get("reward_rerolls_used", [])
	var used: Array = []
	for index in engine.state.rewards.size():
		used.append(bool(previous[index]) if index < previous.size() else false)
	engine.state.reward_rerolls_used = used
	for card in engine.state.rewards:
		var id = str(card.id)
		if not engine.state.reward_seen.has(id):
			engine.state.reward_seen.append(id)


static func _reward_reroll_candidates(engine) -> Array:
	# Apply the same boss rarity fallback as the initial three-card offer, before exclusions.
	var pool = _eligible_cards(engine, engine.state.encounter_kind == "boss")
	if pool.size() < 3:
		pool = _eligible_cards(engine, false)
	var excluded: Array = engine.state.get("reward_seen", []).duplicate()
	for card in engine.state.rewards:
		excluded.append(str(card.id))
	return pool.filter(func(card): return not excluded.has(str(card.id)))


static func reward_reroll_view(engine, index: int) -> Dictionary:
	var view = {"available": false, "used": false, "remaining": 0, "reason": ""}
	if engine.state.room != "reward" or not engine.state.active:
		view.reason = "现在没有待选择的卡牌奖励。"
	elif index < 0 or index >= engine.state.rewards.size():
		view.reason = "奖励编号无效。"
	elif engine._action_busy:
		view.reason = "当前动作尚未完成。"
	else:
		var used: Array = engine.state.get("reward_rerolls_used", [])
		view.used = bool(used[index]) if index < used.size() else false
		view.remaining = 0 if view.used else 1
		if view.used:
			view.reason = "这张候选的刷新机会已用完。"
		elif _reward_reroll_candidates(engine).is_empty():
			view.reason = "当前卡池没有其他未展示卡牌；本次机会未消耗。"
		else:
			view.available = true
	return view


static func reroll_reward(engine, index: int) -> Dictionary:
	var view = reward_reroll_view(engine, index)
	if not view.available:
		return engine._fail(str(view.reason))
	var pool = _reward_reroll_candidates(engine)
	var replacement = pool[engine._random_int("loot", 0, pool.size() - 1)]
	_migrate_reward_guidance(engine)
	engine.state.reward_rerolls_used[index] = true
	engine.state.rewards[index] = {"id": str(replacement.id), "upgraded": false}
	engine.state.reward_seen.append(str(replacement.id))
	return engine._commit("已换成「%s」，此位置的刷新机会已用完。" % replacement.name)


static func choose_reward(engine, index: int) -> Dictionary:
	if engine.state.room != "reward" or not engine.state.active:
		return engine._fail("现在没有待选择的卡牌奖励。")
	if index < -1 or index >= engine.state.rewards.size():
		return engine._fail("奖励编号无效。")
	if index >= 0:
		var card = engine.state.rewards[index].duplicate(true)
		engine.state.deck.append(card)
		engine._seen(str(card.id))
		engine._log("%s加入卡组。" % engine.card_view(card).get("name", "新卡"))
	engine.state.rewards.clear()
	engine.state.reward_rerolls_used.clear()
	engine.state.reward_seen.clear()
	if engine.state.encounter_kind == "boss":
		if int(engine.state.chapter) >= 3:
			engine._finish_run(true)
		else:
			engine.state.chapter = int(engine.state.chapter) + 1
			engine.state.row = -1
			engine.state.lane = -1
			engine.state.map = engine._make_map()
			engine.state.room = "map"
			engine.state.max_hp = int(engine.state.max_hp) + 8
			engine._heal(int(ceil(int(engine.state.max_hp) * 0.35)))
			engine._log("踏入下一章：生命上限 +8，回复35%最大生命；基础能量最多5，每回合抽牌提升至6。")
	else:
		engine.state.room = "map"
	return engine._commit("已领取奖励。" if index >= 0 else "跳过卡牌奖励。")


static func _relic_total(engine, op: String) -> int:
	var total = 0
	for id in engine.state.get("relics", []):
		var effect = engine.relic_data(str(id)).get("effect", {})
		if effect.get("op", "") == op:
			total += int(effect.get("value", 0))
	return total + Items.total(engine, op)


static func _random_relic(engine, boss: bool = false) -> String:
	var pool = []
	for relic in engine.data.get("relics", []):
		if relic.get("rarity", "") == "starter" or engine.state.relics.has(str(relic.id)):
			continue
		if relic.get("role", "neutral") not in ["neutral", engine.state.role]:
			continue
		if boss and relic.get("rarity", "") not in ["rare", "boss"]:
			continue
		pool.append(str(relic.id))
	if pool.is_empty() and boss:
		return _random_relic(engine, false)
	return "" if pool.is_empty() else pool[engine._random_int("loot", 0, pool.size() - 1)]


static func _gain_relic(engine, id: String) -> void:
	var relic = engine.relic_data(id)
	if relic.is_empty() or engine.state.relics.has(id):
		return
	engine.state.relics.append(id)
	var effect = relic.get("effect", {})
	if effect.get("op", "") == "max_hp":
		var gain = int(effect.get("value", 0))
		engine.state.max_hp = int(engine.state.max_hp) + gain
		engine.state.hp = int(engine.state.hp) + gain


static func _make_shop(engine) -> void:
	engine.state.shop = []
	for card in _make_card_rewards(engine, 4):
		var definition = engine.card_data(str(card.id))
		var price = {"common": 35, "uncommon": 55, "rare": 85}.get(str(definition.get("rarity", "common")), 35)
		engine.state.shop.append({"kind": "card", "id": card.id, "price": _shop_price(engine, price), "sold": false})
	var relic = _random_relic(engine, false)
	if not relic.is_empty():
		engine.state.shop.append({"kind": "relic", "id": relic, "price": _shop_price(engine, 100), "sold": false})
	var goods := Items.available(engine, ["positive"])
	engine._shuffle(goods, "loot")
	for good in goods.slice(0, mini(3, goods.size())):
		engine.state.shop.append({"kind":"item", "id":good.id, "price":_shop_price(engine, int(good.price)), "sold":false})
	if not engine.data.get("potions", []).is_empty():
		var potion = engine.data.potions[engine._random_int("loot", 0, engine.data.potions.size() - 1)]
		engine.state.shop.append({"kind": "potion", "id": potion.id, "price": _shop_price(engine, 28), "sold": false})
	engine.state.shop.append({"kind": "remove", "id": "", "price": _shop_price(engine, 45), "sold": false})


static func _shop_price(engine, base: int) -> int:
	var price := float(base)
	if int(engine.state.difficulty) >= 3:
		price = ceil(price * 1.15)
	var percent := Oaths.value(engine.state.modifiers, "shop_price_pct")
	if percent != 0:
		price = ceil(price * (100.0 + float(percent)) / 100.0)
	return maxi(1, int(price))


static func buy_item(engine, index: int) -> Dictionary:
	if engine.state.room != "shop" or not engine.state.active or index < 0 or index >= engine.state.shop.size():
		return engine._fail("商品不存在。")
	var item = engine.state.shop[index]
	if item.sold:
		return engine._fail("这件商品已售出。")
	if int(engine.state.gold) < int(item.price):
		return engine._fail("金币不足。")
	if item.kind == "potion" and engine.state.potions.size() >= 3:
		return engine._fail("药剂栏已满，请先在战斗中使用药剂。")
	if item.kind == "item" and (engine.item_data(str(item.id)).get("kind", "") != "positive" or not Items.can_gain(engine, str(item.id))):
		return engine._fail("该道具不可购买或已拥有。")
	if item.kind == "remove":
		if engine.state.deck.size() <= 5:
			return engine._fail("卡组至少保留五张牌。")
		engine.state.selected_shop_remove = index
		return engine._commit("请选择要删除的卡牌；选择后才扣款。")
	engine.state.gold = int(engine.state.gold) - int(item.price)
	item.sold = true
	match item.kind:
		"card":
			engine.state.deck.append({"id": str(item.id), "upgraded": false})
			engine._seen(str(item.id))
		"relic": _gain_relic(engine, str(item.id))
		"potion": engine.state.potions.append(str(item.id))
		"item": Items.gain(engine, str(item.id))
	Items.progress(engine, "shop_gold", int(item.price))
	return engine._commit("购买成功。")


static func remove_card(engine, deck_index: int) -> Dictionary:
	var item_index = int(engine.state.get("selected_shop_remove", -1))
	if engine.state.room != "shop" or item_index < 0 or item_index >= engine.state.shop.size():
		return engine._fail("请先选择商店的删牌服务。")
	var item = engine.state.shop[item_index]
	if item.sold or engine.state.deck.size() <= 5 or deck_index < 0 or deck_index >= engine.state.deck.size() or int(engine.state.gold) < int(item.price):
		return engine._fail("无法删除这张卡牌。")
	engine.state.deck.remove_at(deck_index)
	engine.state.gold = int(engine.state.gold) - int(item.price)
	item.sold = true
	engine.state.selected_shop_remove = -1
	Items.progress(engine, "shop_gold", int(item.price))
	return engine._commit("卡牌已从本局卡组移除。")


static func rest(engine, upgrade_deck_index: int = -1) -> Dictionary:
	if engine.state.room != "rest" or not engine.state.active:
		return engine._fail("只有篝火节点可以休息或升级。")
	if upgrade_deck_index < -1 or upgrade_deck_index >= engine.state.deck.size():
		return engine._fail("请选择正确的卡牌。")
	if upgrade_deck_index < 0 and Oaths.value(engine.state.modifiers, "no_rest_heal") > 0:
		return engine._fail("缄默誓禁止在篝火旁休息，只能强化卡牌。")
	if upgrade_deck_index >= 0 and engine.state.deck[upgrade_deck_index].get("upgraded", false):
		return engine._fail("这张牌已经升级。")
	if upgrade_deck_index < 0:
		engine._heal(int(engine.state.max_hp) - int(engine.state.hp))
		engine._log("篝火暖意恢复了全部生命。")
	else:
		engine.state.deck[upgrade_deck_index].upgraded = true
		engine.profile.stats.cards_upgraded = int(engine.profile.stats.cards_upgraded) + 1
		Items.progress(engine, "cards_upgraded")
		engine._log("强化了%s。" % engine.card_view(engine.state.deck[upgrade_deck_index]).get("name", "卡牌"))
	_mark_node_cleared(engine)
	engine.state.room = "map"
	return engine._commit("休整完毕。")


static func discard_negative_item(engine, id: String) -> Dictionary:
	if not engine.state.active or engine.state.room != "rest":
		return engine._fail("只有营地可以舍弃负面道具。")
	if not engine.state.items.has(id) or not Items.is_negative(engine.item_data(id)):
		return engine._fail("请选择一件随行的负面道具。")
	if int(engine.state.hp) <= Items.CAMP_COST:
		return engine._fail("需要至少 %d 点当前生命，无法支付。" % (Items.CAMP_COST + 1))
	engine.state.hp = int(engine.state.hp) - Items.CAMP_COST
	engine.state.items.erase(id)
	engine._log("在营地失去 %d 生命，舍弃「%s」。" % [Items.CAMP_COST, engine.item_data(id).name])
	_mark_node_cleared(engine)
	engine.state.room = "map"
	return engine._commit("已舍弃「%s」，失去 %d 生命。" % [engine.item_data(id).name, Items.CAMP_COST])


static func choose_event(engine, index: int) -> Dictionary:
	if engine.state.room != "event" or not engine.state.active:
		return engine._fail("当前没有可选择的事件。")
	var choices = engine.state.event.get("choices", [])
	if index < 0 or index >= choices.size():
		return engine._fail("选项不存在。")
	var choice = choices[index]
	var relic_id = str(choice.get("relic", ""))
	if not relic_id.is_empty() and engine.state.relics.has(relic_id):
		return engine._fail("已拥有此遗物，请选择其他选项。")
	var offered: Array = choice.get("items", [])
	var seen: Array = []
	for id in offered:
		if seen.has(id) or not Items.can_gain(engine, str(id)) or engine.item_data(str(id)).kind == "sacred":
			return engine._fail("道具已领取或不可领取，请选择其他选项。")
		seen.append(id)
	if int(engine.state.gold) + int(choice.get("gold", 0)) < 0:
		return engine._fail("金币不足，无法选择此项。")
	if int(engine.state.hp) + int(choice.get("hp", 0)) <= 0:
		return engine._fail("生命不足，无法支付这一代价。")
	if int(engine.state.max_hp) + int(choice.get("max_hp", 0)) <= 0:
		return engine._fail("最大生命不足。")
	engine.state.gold = int(engine.state.gold) + int(choice.get("gold", 0))
	engine.state.max_hp = int(engine.state.max_hp) + int(choice.get("max_hp", 0))
	engine.state.hp = mini(int(engine.state.max_hp), int(engine.state.hp) + int(choice.get("hp", 0)))
	engine._heal(int(choice.get("heal", 0)))
	var card_id = str(choice.get("card", ""))
	if not engine.card_data(card_id).is_empty():
		engine.state.deck.append({"id": card_id, "upgraded": false})
		engine._seen(card_id)
	_gain_relic(engine, relic_id)
	engine._log("%s：%s" % [engine.state.event.get("name", "事件"), choice.get("label", "继续")])
	_mark_node_cleared(engine)
	for id in offered:
		Items.gain(engine, str(id))
	engine.state.room = "map"
	return engine._commit("选择已生效。")


static func leave_room(engine) -> Dictionary:
	if not engine.state.active or engine.state.room not in ["shop", "treasure"]:
		return engine._fail("请先完成当前节点。")
	_mark_node_cleared(engine)
	engine.state.selected_shop_remove = -1
	engine.state.room = "map"
	return engine._commit("返回路线图。")


static func _mark_node_cleared(engine) -> void:
	if int(engine.state.row) >= 0 and int(engine.state.row) < engine.state.map.size() and int(engine.state.lane) >= 0:
		var node: Dictionary = engine.state.map[int(engine.state.row)][int(engine.state.lane)]
		if not bool(node.get("cleared", false)):
			node.cleared = true
			Items.complete_node(engine)
