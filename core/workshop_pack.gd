extends RefCounted
## The same data-only pack can be shared locally or carried by a workshop item.

const VERSION := 1
const MAX_BYTES := 16 * 1024
const CARD_ID := "workshop_card"
const _SECTIONS := {
	"role": {"name": 24, "base": 32, "hp": [1, 200]},
	"enemy": {"name": 24, "hp": [1, 200], "attack": [1, 40], "block": [0, 40]},
	"item": {"name": 24, "kind": ["heal", "block", "energy"], "amount": [1, 40]},
	"card": {"name": 24, "kind": ["attack", "skill"], "cost": [0, 3], "amount": [1, 40]},
	"talent": {"name": 24, "kind": ["strength", "block"], "amount": [1, 20]},
	"build": {"name": 24, "description": 240},
}


static func default_deck(game, role_id: String) -> Array:
	var deck: Array = game.role_data(role_id).get("starter_cards", []).duplicate()
	if not deck.is_empty():
		deck[deck.size() - 1] = CARD_ID
	return deck


static func default_pack(game) -> Dictionary:
	return {
		"version": VERSION,
		"title": "暮钟试炼",
		"role": {"name": "旅途拾钟人", "base": "warden", "hp": 45},
		"enemy": {"name": "空钟守卫", "hp": 50, "attack": 8, "block": 6},
		"item": {"name": "余火药剂", "kind": "heal", "amount": 9},
		"card": {"name": "裂钟击", "kind": "attack", "cost": 1, "amount": 12},
		"talent": {"name": "旧誓之盾", "kind": "block", "amount": 5},
		"build": {"name": "暮钟攻守", "description": "靠格挡稳住第一回合，用裂钟击反击。", "starter_cards": default_deck(game, "warden")},
	}


static func parse_text(source: String, game) -> Dictionary:
	if source.length() > MAX_BYTES or source.to_utf8_buffer().size() > MAX_BYTES:
		return _fail("作品包不能超过 16 KB。")
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _fail("作品包不是有效的 JSON（第 %d 行）。" % parser.get_error_line())
	if not parser.data is Dictionary:
		return _fail("作品包顶层必须是一个对象。")
	return validate(parser.data, game)


static func validate(source: Dictionary, game) -> Dictionary:
	if not _whole_number(source.get("version"), VERSION, VERSION):
		return _fail("作品包版本不受支持。")
	var title: Variant = _clean_text(source.get("title"), 32)
	if title == null:
		return _fail("作品名需要 1 到 32 个字符。")
	if source.size() != _SECTIONS.size() + 2:
		return _fail("作品包必须包含角色、怪物、道具、卡牌、天赋和流派。")
	var pack := {"version": VERSION, "title": title}
	for section in _SECTIONS:
		var raw = source.get(section)
		var fields: Dictionary = _SECTIONS[section]
		var field_count := fields.size() + (1 if section == "build" else 0)
		if not raw is Dictionary or raw.size() != field_count:
			return _fail("作品包的 %s 区块缺少字段或含有未知字段。" % section)
		var normalized := {}
		for field in fields:
			var rule = fields[field]
			var value = raw.get(field)
			var label := "%s.%s" % [section, field]
			if rule is int:
				var cleaned: Variant = _clean_text(value, rule)
				if cleaned == null:
					return _fail("%s 需要 1 到 %d 个字符。" % [label, rule])
				normalized[field] = cleaned
			elif rule[0] is int:
				if not _whole_number(value, rule[0], rule[1]):
					return _fail("%s 需要是 %d 到 %d 的整数。" % [label, rule[0], rule[1]])
				normalized[field] = int(value)
			else:
				if not value is String or not rule.has(value):
					return _fail("%s 的类型不受支持。" % label)
				normalized[field] = value
		pack[section] = normalized
	var role: Dictionary = game.role_data(pack.role.base)
	if role.is_empty():
		return _fail("角色引用了不存在的基础职业。")
	if pack.item.kind == "energy" and pack.item.amount > 3:
		return _fail("补充能量的道具最多提供 3 点能量。")
	var starter_cards = source.build.get("starter_cards")
	if not starter_cards is Array or starter_cards.size() < 5 or starter_cards.size() > 12:
		return _fail("流派的起始牌组需要 5 到 12 张牌。")
	for id in starter_cards:
		if not id is String or (id != CARD_ID and (not role.starter_cards.has(id) or game.card_data(id).is_empty())):
			return _fail("起始牌组只能使用基础职业的起始牌和自制卡。")
	if not starter_cards.has(CARD_ID):
		return _fail("起始牌组至少需要一张自制卡。")
	pack.build.starter_cards = starter_cards.duplicate()
	return {"ok": true, "message": "作品包校验通过。", "pack": pack}


static func _clean_text(value: Variant, limit: int) -> Variant:
	if not value is String:
		return null
	var cleaned: String = value.strip_edges()
	if cleaned.is_empty() or cleaned.length() > limit:
		return null
	for index in range(cleaned.length()):
		var character := cleaned.unicode_at(index)
		if character < 32 or character == 127:
			return null
	return cleaned


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum and value == floorf(float(value))


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
