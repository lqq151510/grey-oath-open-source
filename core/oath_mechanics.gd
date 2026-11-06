extends RefCounted
## v0.2.3 "长夜誓约": oaths, daily vows and elite affixes.
## Pure data plus deterministic helpers. Reading this module never mutates game state.

const OATHS := [
	{
		"id": "blood", "name": "血誓", "kicker": "以血为薪",
		"boon": "每场战斗的第一回合额外获得 1 点能量。",
		"price": "最大生命降低 12%。",
		"modifiers": {"max_hp_pct": -12, "first_turn_energy": 1},
	},
	{
		"id": "scavenger", "name": "拾荒誓", "kicker": "翻找每一具残骸",
		"boon": "每场战斗胜利额外获得 12 金币。",
		"price": "起始金币减少 30。",
		"modifiers": {"gold_flat": -30, "combat_gold_flat": 12},
	},
	{
		"id": "hunter", "name": "猎誓", "kicker": "只向最强的猎物举刀",
		"boon": "精英战额外提供一张稀有牌。",
		"price": "精英敌人生命提高 20%。",
		"modifiers": {"elite_hp_pct": 20, "elite_reward_rare": 1},
	},
	{
		"id": "silence", "name": "缄默誓", "kicker": "不在篝火旁开口",
		"boon": "每场战斗的第一回合多抽 1 张牌。",
		"price": "营火不能休息回血，只能强化卡牌。",
		"modifiers": {"no_rest_heal": 1, "first_turn_draw": 1},
	},
	{
		"id": "iron", "name": "铁誓", "kicker": "把骨头锻进盾里",
		"boon": "每场战斗开始时获得 8 点格挡。",
		"price": "每场战斗结束后失去 3 点生命。",
		"modifiers": {"start_block": 8, "combat_heal": -3},
	},
	{
		"id": "ember", "name": "余烬誓", "kicker": "用未熄的炭火起誓",
		"boon": "每场战斗开始时获得 1 点力量。",
		"price": "商店价格提高 20%。",
		"modifiers": {"start_strength": 1, "shop_price_pct": 20},
	},
]

const AFFIXES := [
	{"id": "vigil", "name": "守夜", "description": "精英开场获得 12 点格挡。", "modifiers": {"start_block": 12}},
	{"id": "hunger", "name": "饥饿", "description": "精英每回合获得 1 点力量。", "modifiers": {"turn_strength": 1}},
	{"id": "thorns", "name": "荆棘", "description": "精英拥有 4 点荆棘。", "modifiers": {"start_thorns": 4}},
	{"id": "shroud", "name": "灰幕", "description": "精英最大生命提高 25%。", "modifiers": {"hp_pct": 25}},
]

const DAILY_MODIFIERS := [
	{"id": "long_night", "name": "长夜", "description": "所有敌人生命提高 15%。", "modifiers": {"enemy_hp_pct": 15}},
	{"id": "full_purse", "name": "满囊", "description": "起始金币增加 50。", "modifiers": {"gold_flat": 50}},
	{"id": "sharpened", "name": "磨刃", "description": "每场战斗开始时获得 2 点力量。", "modifiers": {"start_strength": 2}},
	{"id": "thin_blood", "name": "薄暮", "description": "最大生命降低 15%。", "modifiers": {"max_hp_pct": -15}},
	{"id": "bargain", "name": "贱卖", "description": "商店价格降低 25%。", "modifiers": {"shop_price_pct": -25}},
	{"id": "swift", "name": "疾行", "description": "每场战斗的第一回合多抽 1 张牌。", "modifiers": {"first_turn_draw": 1}},
]

const DAILY_BASE := "2026-01-01"


static func oath(id: String) -> Dictionary:
	for entry in OATHS:
		if str(entry.id) == id:
			return entry.duplicate(true)
	return {}


static func oath_entries() -> Array:
	return OATHS.duplicate(true)


static func offers(seed_value: int, count: int = 3) -> Array:
	## Deterministic three-way oath draft. The same seed always offers the same
	## oaths, so reopening the selection screen cannot reroll the choices.
	var pool := oath_entries()
	var generator := RandomNumberGenerator.new()
	generator.seed = abs(seed_value) + 7919
	for index in range(pool.size() - 1, 0, -1):
		var other := generator.randi_range(0, index)
		var temporary = pool[index]
		pool[index] = pool[other]
		pool[other] = temporary
	return pool.slice(0, mini(count, pool.size()))


static func modifiers_for(oath_id: String) -> Dictionary:
	var entry := oath(oath_id)
	if entry.is_empty():
		return {}
	return entry.get("modifiers", {}).duplicate(true)


static func value(modifiers: Dictionary, key: String, fallback: int = 0) -> int:
	return int(modifiers.get(key, fallback))


static func apply_max_hp(base_hp: int, modifiers: Dictionary) -> int:
	var percent := value(modifiers, "max_hp_pct")
	var flat := value(modifiers, "max_hp_flat")
	var result := int(floor(float(base_hp) * (100.0 + float(percent)) / 100.0)) + flat
	return maxi(1, result)


static func affix(id: String) -> Dictionary:
	for entry in AFFIXES:
		if str(entry.id) == id:
			return entry.duplicate(true)
	return {}


static func affix_entries() -> Array:
	return AFFIXES.duplicate(true)


static func pick_affix(seed_value: int) -> Dictionary:
	var generator := RandomNumberGenerator.new()
	generator.seed = abs(seed_value) * 31 + 17
	return AFFIXES[generator.randi_range(0, AFFIXES.size() - 1)].duplicate(true)


static func daily_key() -> String:
	return Time.get_date_string_from_system()


static func daily_seed(key: String) -> int:
	return abs(key.hash()) & 0x7fffffff


static func daily_day_index(key: String) -> int:
	var stamp := Time.get_unix_time_from_datetime_string(key + "T00:00:00")
	var base := Time.get_unix_time_from_datetime_string(DAILY_BASE + "T00:00:00")
	if stamp <= 0 or base <= 0:
		return 0
	return int(floor(float(stamp - base) / 86400.0))


static func daily_setup(key: String, role_ids: Array) -> Dictionary:
	## Fixed daily configuration. Rotating role, oath and one run-wide twist,
	## all derived from the date key so every install sees the same challenge.
	var roles: Array = []
	for id in role_ids:
		if not str(id).is_empty():
			roles.append(str(id))
	var seed_value := daily_seed(key)
	var oath_entry: Dictionary = OATHS[seed_value % OATHS.size()]
	var modifier: Dictionary = DAILY_MODIFIERS[(seed_value / 7) % DAILY_MODIFIERS.size()]
	var combined := modifiers_for(str(oath_entry.id))
	for stat in modifier.get("modifiers", {}):
		combined[stat] = int(combined.get(stat, 0)) + int(modifier.modifiers[stat])
	return {
		"key": key,
		"seed": seed_value,
		"role": "" if roles.is_empty() else str(roles[daily_day_index(key) % roles.size()]),
		"oath": str(oath_entry.id),
		"oath_view": oath_entry.duplicate(true),
		"modifier": modifier.duplicate(true),
		"modifiers": combined,
	}


static func previous_day(key: String) -> String:
	var stamp := Time.get_unix_time_from_datetime_string(key + "T00:00:00")
	if stamp <= 0:
		return ""
	return Time.get_date_string_from_unix_time(stamp - 86400)


static func score(state: Dictionary, victory: bool) -> int:
	## Slay-the-Spire style run score: depth, elites, bosses, purse and health.
	var floors := int(state.get("chapter", 0)) * 15 + int(state.get("row", 0)) + 1
	var value := floors * 10
	value += int(state.get("run_elites", 0)) * 30
	value += int(state.get("run_bosses", 0)) * 120
	value += int(state.get("gold", 0))
	value += int(state.get("hp", 0)) * 2
	value += maxi(0, int(state.get("difficulty", 0))) * 100
	if victory:
		value += 500
	return maxi(0, value)
