extends RefCounted
## Permanent milestones. Reading a collection never changes its progress.

const ACHIEVEMENTS := [
	{"id": "first_oath", "name": "立下灰誓", "description": "开始第一段旅程", "metric": "runs_started", "goal": 1},
	{"id": "first_victory", "name": "余烬未熄", "description": "赢得一场战斗", "metric": "wins", "goal": 1},
	{"id": "ten_victories", "name": "长夜行者", "description": "累计赢得十场战斗", "metric": "wins", "goal": 10},
	{"id": "fifty_victories", "name": "不灭誓言", "description": "累计赢得五十场战斗", "metric": "wins", "goal": 50},
	{"id": "first_elite", "name": "直面强敌", "description": "击败一名精英", "metric": "elite_wins", "goal": 1},
	{"id": "first_boss", "name": "破晓之钟", "description": "击败一名章节首领", "metric": "boss_wins", "goal": 1},
	{"id": "first_clear", "name": "长夜退去", "description": "完成一次四章旅程", "metric": "clears", "goal": 1},
	{"id": "artisan", "name": "淬火", "description": "在营火强化一张卡牌", "metric": "cards_upgraded", "goal": 1},
	{"id": "hundred_cards", "name": "百次交锋", "description": "累计打出一百张卡牌", "metric": "cards_played", "goal": 100},
	{"id": "collector_10", "name": "灰烬拾遗", "description": "获得十种不同的卡牌", "metric": "collection", "goal": 10},
	{"id": "collector_50", "name": "誓约藏书", "description": "获得五十种不同的卡牌", "metric": "collection", "goal": 50},
]

static func metrics(profile: Dictionary) -> Dictionary:
	var result: Dictionary = profile.get("stats", {}).duplicate()
	result["wins"] = int(profile.get("total_wins", 0))
	result["collection"] = profile.get("seen_cards", []).size()
	result["sacred_collection"] = profile.get("sacred_collection", []).size()
	result["clears"] = 0
	for count in profile.get("clears", {}).values():
		result.clears += int(count)
	return result

static func entries(profile: Dictionary, sacred_goal: int, card_goal: int) -> Array:
	var values := metrics(profile)
	var result: Array = []
	var definitions := ACHIEVEMENTS.duplicate()
	if card_goal > 0:
		definitions.append({"id":"collector_all", "name":"长夜全书", "description":"收集全部 %d 种卡牌" % card_goal, "metric":"collection", "goal":card_goal})
	if sacred_goal > 0:
		definitions.append({"id":"sacred_complete", "name":"长夜圣匣", "description":"净化并永久收集全部神圣道具", "metric":"sacred_collection", "goal":sacred_goal})
	for definition in definitions:
		var entry: Dictionary = definition.duplicate()
		entry["progress"] = mini(int(values.get(entry.metric, 0)), int(entry.goal))
		entry["unlocked"] = profile.get("achievements", {}).has(entry.id)
		entry["date"] = str(profile.get("achievements", {}).get(entry.id, ""))
		result.append(entry)
	return result

static func unlock(profile: Dictionary, sacred_goal: int, card_goal: int) -> Array:
	var result: Array = []
	for entry in entries(profile, sacred_goal, card_goal):
		if not entry.unlocked and int(entry.progress) >= int(entry.goal):
			profile.achievements[entry.id] = Time.get_datetime_string_from_system()
			result.append(entry.id)
	return result
