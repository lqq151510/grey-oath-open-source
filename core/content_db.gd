extends RefCounted
## Content catalog indexing and card presentation, extracted verbatim from
## core/game_engine.gd. Engine counterparts: the _init() catalog load,
## role_data/card_data/relic_data/potion_data/item_data/enemy_data,
## sacred_ids(), _normalize_numbers(), _requires_enemy() and card_view().
## The workshop ("encounter_kind") special case intentionally stays in the engine.

const DEFAULT_PATH = "res://data/catalog.json"
const GROUPS = ["roles", "cards", "enemies", "relics", "potions", "events", "items"]
const ATTACK_AREA_OPS = ["damage", "lifesteal", "block_damage", "osty_attack", "resonant_damage", "ignite"]
const ENEMY_TARGET_OPS = ["damage", "lifesteal", "block_damage", "poison", "weak", "vulnerable", "doom", "osty_attack", "poison_multiply", "resonant_damage", "cinder", "ignite"]
const TOKEN_SHIV_ID = "token_shiv"

var data: Dictionary = {}
var indexes: Dictionary = {}
var last_error: String = ""


func load_from(path: String = DEFAULT_PATH) -> bool:
	data = {}
	indexes = {}
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "内容目录无法读取。"
		return false
	var raw = FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		last_error = "内容目录无法读取。"
		return false
	data = normalize_numbers(parsed)
	for group in GROUPS:
		indexes[group] = {}
		for item in data.get(group, []):
			indexes[group][str(item.id)] = item
	for token in data.get("tokens", []):
		indexes.cards[str(token.id)] = token
	return true


func role_data(id: String) -> Dictionary:
	return indexes.get("roles", {}).get(id, {})


func card_data(id: String) -> Dictionary:
	return indexes.get("cards", {}).get(id, {})


func relic_data(id: String) -> Dictionary:
	return indexes.get("relics", {}).get(id, {})


func potion_data(id: String) -> Dictionary:
	return indexes.get("potions", {}).get(id, {})


func item_data(id: String) -> Dictionary:
	return indexes.get("items", {}).get(id, {})


func enemy_data(id: String) -> Dictionary:
	return indexes.get("enemies", {}).get(id, {})


func sacred_ids() -> Array:
	return data.get("items", []).filter(func(item): return item.kind == "sacred").map(func(item): return str(item.id))


static func normalize_numbers(val):
	if val is float:
		if is_equal_approx(val, round(val)):
			return int(round(val))
		return val
	elif val is Dictionary:
		var normalized = {}
		for key in val:
			normalized[str(key)] = normalize_numbers(val[key])
		return normalized
	elif val is Array:
		var normalized = []
		for item in val:
			normalized.append(normalize_numbers(item))
		return normalized
	return val


static func requires_enemy(effects: Array) -> bool:
	for effect in effects:
		if str(effect.get("target", "")) == "self":
			continue
		if effect.op in ENEMY_TARGET_OPS and effect.get("target", "enemy") != "all":
			return true
	return false


func view(instance: Dictionary, card_def: Dictionary, shiv_bonus: int = 0) -> Dictionary:
	var result = card_def.duplicate(true)
	if result.is_empty():
		return result
	if bool(instance.get("upgraded", false)):
		result["name"] = str(result.get("name", "")) + "+"
		result["effects"] = result.get("upgrade_effects", result.get("effects", [])).duplicate(true)
		result["description"] = result.get("upgrade_description", result.get("description", ""))
		result["cost"] = int(result.get("upgrade_cost", result.get("cost", 0)))
	result["upgraded"] = bool(instance.get("upgraded", false))
	result["area_kind"] = ""
	for effect in result.get("effects", []):
		if effect.get("target", "") == "all":
			if effect.op in ATTACK_AREA_OPS:
				result.area_kind = "attack"
				break
			result.area_kind = "effect"
	result["requires_target"] = requires_enemy(result.get("effects", []))
	if str(result.get("id", "")) == TOKEN_SHIV_ID:
		var bonus = shiv_bonus
		if bonus > 0:
			var base = int(result.effects[0].value)
			result.effects[0].value = base + bonus
			# The catalog is normalised without spaces between numbers and units,
			# but old localisations and tests may still use "6 点伤害".
			var description = str(result.description)
			description = description.replace("%d 点伤害" % base, "%d 点伤害" % (base + bonus))
			description = description.replace("%d点伤害" % base, "%d点伤害" % (base + bonus))
			result.description = description
	return result
