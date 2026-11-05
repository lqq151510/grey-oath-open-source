extends RefCounted
## Item state belongs to a journey; purified IDs also enter the permanent collection.
const CAMP_COST := 5
const KIND_NAMES := {"positive":"正面", "temporary":"限时负面", "curse":"诅咒", "sacred":"神圣", "permanent":"永久负面"}
const PERMANENT_OFFER_DESCRIPTION := "获得正面道具和 120 金币。附带的负面道具会持续生效，可以在营地舍弃。"

static func is_negative(item: Dictionary) -> bool:
	return item.get("kind", "") in ["temporary", "curse", "permanent"]

static func available(g, kinds: Array) -> Array:
	return g.data.get("items", []).filter(func(item): return item.kind in kinds and can_gain(g, str(item.id)))

static func can_gain(g, id: String) -> bool:
	return not g.item_data(id).is_empty() and not g.state.item_claimed.has(id) and not g.state.items.has(id)

static func gain(g, id: String) -> bool:
	if not can_gain(g, id):
		return false
	var item: Dictionary = g.item_data(id)
	g.state.item_claimed.append(id)
	g.state.items[id] = {"remaining":int(item.get("duration", 0)), "progress":0}
	if item.kind == "sacred" and not g.profile.sacred_collection.has(id):
		g.profile.sacred_collection.append(id)
	g._log("获得道具「%s」。" % item.name)
	return true

static func total(g, op: String) -> int:
	var amount := 0
	for id in g.state.items:
		for effect in g.item_data(str(id)).get("effects", []):
			if effect.op == op:
				amount += int(effect.value)
	return amount

static func note(g, message: String) -> void:
	g._log(message)
	g._item_notices.append(message)

static func replace(g, id: String) -> void:
	var definition: Dictionary = g.item_data(id)
	var next_id := str(definition.get("transforms_to", ""))
	g.state.items.erase(id)
	if not next_id.is_empty() and gain(g, next_id):
		var next_item: Dictionary = g.item_data(next_id)
		note(g, "「%s」已转化为「%s」。%s" % [definition.name, next_item.name, next_item.description])
	else:
		note(g, "「%s」已消失。" % definition.name)

static func complete_node(g) -> void:
	for id in g.state.items.keys():
		if g.item_data(str(id)).get("kind", "") != "temporary":
			continue
		var entry: Dictionary = g.state.items[id]
		entry.remaining = maxi(0, int(entry.remaining) - 1)
		if entry.remaining == 0:
			replace(g, str(id))

static func progress(g, metric: String, amount: int = 1) -> void:
	for id in g.state.items.keys():
		var task: Dictionary = g.item_data(str(id)).get("task", {})
		if task.get("metric", "") != metric:
			continue
		var entry: Dictionary = g.state.items[id]
		entry.progress = mini(int(task.goal), int(entry.progress) + amount)
		if entry.progress >= int(task.goal):
			replace(g, str(id))

static func offer(g) -> Dictionary:
	var goods := available(g, ["positive"])
	if goods.is_empty():
		return {}
	var good: Dictionary = goods[g._random_int("event", 0, goods.size() - 1)]
	var choices := [{"label":"收下馈赠", "description":"取走正面道具，结束探索。", "items":[good.id]}]
	var roll: int = g._random_int("event", 0, 99)
	var burdens := available(g, ["permanent"] if roll < 12 else ["curse"] if roll < 24 else ["temporary"] if roll < 42 else [])
	if not burdens.is_empty():
		# Uncollected sacred items are prioritized when a curse offer appears.
		var uncollected := burdens.filter(func(item): return item.get("kind", "") == "curse" and not g.profile.sacred_collection.has(item.get("transforms_to", "")))
		var pool := uncollected if not uncollected.is_empty() else burdens
		var negative: Dictionary = pool[g._random_int("event", 0, pool.size() - 1)]
		var permanent: bool = negative.kind == "permanent"
		choices.append({"label":"接受永誓" if permanent else "接受试炼", "description":PERMANENT_OFFER_DESCRIPTION if permanent else "收下馈赠与额外金币，同时携带所列负面道具。", "items":[good.id, negative.id], "gold":120 if permanent else 30})
	choices.append({"label":"直接离开", "description":"不触碰祭台上的物件。"})
	return {"id":"expedition_offer", "name":"灰烬祭台", "description":"问号尽头是一座未熄的祭台。祭品旁写明了恩惠与代价。", "choices":choices}
