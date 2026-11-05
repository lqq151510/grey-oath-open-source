class_name ItemIcon
extends Control
## Small, data-driven vector crests for relics, journey items, and potions.

var definition: Dictionary = {}
var category := "item"
var icon_id := ""
var motif_name := "rune"
var accent := Color("c7a66a")


func setup(item_definition: Dictionary, item_category: String, diameter: float = 52.0) -> void:
	definition = item_definition.duplicate(true)
	category = item_category
	icon_id = str(definition.get("id", "unknown"))
	motif_name = _motif_for(definition, category)
	accent = _accent_for(definition, category)
	custom_minimum_size = Vector2.ONE * diameter
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "%s\n%s" % [definition.get("name", icon_id), definition.get("description", "")]
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side < 2.0 or icon_id.is_empty():
		return
	var scale_factor := side / 64.0
	var origin := (size - Vector2.ONE * side) * 0.5 + Vector2.ONE * (side * 0.5)
	draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	draw_circle(Vector2.ZERO, 30.0, Color("171815"))
	draw_circle(Vector2.ZERO, 27.0, Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 0.96))
	if category == "item" and str(definition.get("kind", "")) in ["curse", "permanent"]:
		var diamond := PackedVector2Array([Vector2(0, -28), Vector2(28, 0), Vector2(0, 28), Vector2(-28, 0)])
		_draw_polygon(diamond, Color("211a1a"), accent.darkened(0.2), 2.0)
	else:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 48, accent, 2.0, true)
		draw_arc(Vector2.ZERO, 23.0, -2.45, -0.68, 12, accent.lightened(0.22), 1.0, true)
	if category == "potion":
		_draw_vial(accent)
		draw_set_transform(origin, 0.0, Vector2.ONE * (scale_factor * 0.70))
		_draw_motif(motif_name, accent)
		draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	else:
		_draw_motif(motif_name, accent)
	_draw_identity_marks(accent)
	_draw_rank_marks(accent)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _accent_for(item: Dictionary, item_category: String) -> Color:
	if item_category == "relic":
		return {
			"starter": Color("c7a66a"), "common": Color("b6b4a7"),
			"uncommon": Color("7ea78e"), "rare": Color("78a6c0"),
			"boss": Color("e0b45e"),
		}.get(str(item.get("rarity", "common")), Color("c7a66a"))
	if item_category == "potion":
		return _effect_color(_primary_op(item))
	return {
		"positive": Color("91b89b"), "temporary": Color("d39250"),
		"curse": Color("a979ac"), "sacred": Color("e0bd71"),
		"permanent": Color("bd6158"),
	}.get(str(item.get("kind", "positive")), Color("c7a66a"))


func _effect_color(op: String) -> Color:
	return {
		"damage": Color("de7a49"), "first_damage": Color("de7a49"), "strength": Color("d27c4c"), "start_strength": Color("d27c4c"),
		"block": Color("79a6bb"), "start_block": Color("79a6bb"), "turn_block": Color("79a6bb"),
		"heal": Color("84b98c"), "combat_heal": Color("84b98c"), "turn_heal": Color("84b98c"), "regen": Color("84b98c"), "max_hp": Color("b6c478"),
		"gold_bonus": Color("e0b45e"), "draw": Color("a898cf"), "turn_draw": Color("a898cf"),
		"poison": Color("8ca866"), "poison_bonus": Color("8ca866"), "weak": Color("9aa0a5"), "vulnerable": Color("cb7771"),
		"energy": Color("ddc46e"), "cleanse": Color("89c3ba"), "thorns": Color("8da46e"), "soul": Color("9480bd"), "summon": Color("9480bd"), "mark": Color("d5a15d"),
	}.get(op, Color("c7a66a"))


func _primary_op(item: Dictionary) -> String:
	var single = item.get("effect", {})
	if single is Dictionary and single.has("op"):
		return str(single.op)
	for effect in item.get("effects", []):
		if effect is Dictionary and effect.has("op"):
			return str(effect.op)
	return ""


func _motif_for(item: Dictionary, item_category: String) -> String:
	var words := (str(item.get("name", "")) + " " + str(item.get("id", ""))).to_lower()
	if _has_any(words, ["眼", "透镜", "镜", "lens", "eye"]): return "eye"
	if _has_any(words, ["书", "卷", "手记", "书签", "笔", "folio", "scroll"]): return "book"
	if _has_any(words, ["铃", "钟", "bell"]): return "bell"
	if _has_any(words, ["灯", "烛", "灯芯", "lantern", "candle"]): return "flame"
	if _has_any(words, ["剑", "刃", "枪", "箭", "刀", "sword", "blade", "arrow"]): return "sword"
	if _has_any(words, ["钱", "币", "钱袋", "账", "coin", "purse", "gold"]): return "coin"
	if _has_any(words, ["笛", "flute"]): return "flute"
	if _has_any(words, ["骨", "牙", "齿", "fang", "tooth", "bone"]): return "fang"
	if _has_any(words, ["链", "铐", "锁", "shackle", "chain"]): return "chain"
	if _has_any(words, ["针", "线", "绷带", "needle", "thread"]): return "needle"
	if _has_any(words, ["瓶", "玻瓶", "药", "vial", "potion"]): return "vial"
	if _has_any(words, ["蛇", "毒", "孢子", "蘑菇", "venom", "spore"]): return "venom"
	if _has_any(words, ["鳞", "壳", "甲", "盾", "护符", "护臂", "seal", "shield"]): return "shield"
	if _has_any(words, ["叶", "草", "苔", "种", "果", "树", "叶", "moss", "leaf", "seed"]): return "leaf"
	if _has_any(words, ["星", "晶", "琥珀", "石", "宝", "crystal", "amber", "star"]): return "crystal"
	if _has_any(words, ["羽", "笔", "羽饰", "feather", "quill"]): return "feather"
	match _primary_op(item):
		"start_block", "turn_block", "block": return "shield"
		"start_strength", "first_damage", "strength", "damage": return "sword"
		"max_hp", "turn_heal", "combat_heal", "heal", "regen": return "heart"
		"gold_bonus": return "coin"
		"turn_draw", "draw": return "book"
		"poison_bonus", "poison": return "venom"
		"weak", "vulnerable", "thorns": return "fang"
		"energy", "mark", "soul", "summon": return "star"
	return "vial" if item_category == "potion" else "rune"


func _has_any(text_value: String, tokens: Array) -> bool:
	for token in tokens:
		if text_value.contains(str(token)):
			return true
	return false


func _draw_motif(motif: String, color: Color) -> void:
	var line := Color("eee2c9")
	var fill := color.darkened(0.42)
	match motif:
		"shield":
			_draw_polygon(PackedVector2Array([Vector2(0, -17), Vector2(14, -12), Vector2(12, 5), Vector2(0, 17), Vector2(-12, 5), Vector2(-14, -12)]), fill, line, 2.0)
			draw_line(Vector2(-8, -8), Vector2(8, -8), color, 2.0, true)
			draw_line(Vector2(0, -7), Vector2(0, 11), color, 2.0, true)
		"sword":
			_draw_polygon(PackedVector2Array([Vector2(0, -19), Vector2(5, -9), Vector2(2, 8), Vector2(-2, 8), Vector2(-5, -9)]), fill, line, 2.0)
			draw_line(Vector2(-9, 3), Vector2(9, 3), color, 3.0, true)
			draw_line(Vector2(0, 7), Vector2(0, 17), line, 3.0, true)
			draw_circle(Vector2.ZERO + Vector2(0, 17), 2.5, color)
		"coin":
			draw_circle(Vector2.ZERO, 15.0, fill)
			draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 40, line, 2.0, true)
			draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 32, color, 2.0, true)
			draw_line(Vector2(-4, 0), Vector2(4, 0), line, 2.0, true)
		"heart":
			_draw_polygon(PackedVector2Array([Vector2(0, 16), Vector2(-16, 1), Vector2(-15, -8), Vector2(-9, -13), Vector2(0, -7), Vector2(9, -13), Vector2(15, -8), Vector2(16, 1)]), fill, line, 2.0)
			draw_line(Vector2(-8, -1), Vector2(-2, 5), color.lightened(0.24), 2.0, true)
			draw_line(Vector2(-2, 5), Vector2(8, -6), color.lightened(0.24), 2.0, true)
		"leaf":
			_draw_polygon(PackedVector2Array([Vector2(0, 17), Vector2(-13, 7), Vector2(-12, -7), Vector2(0, -17), Vector2(13, -7), Vector2(12, 7)]), fill, line, 2.0)
			draw_line(Vector2(-9, 8), Vector2(9, -8), color.lightened(0.25), 2.0, true)
			draw_line(Vector2(-3, 2), Vector2(-5, -7), color, 1.5, true)
		"book":
			_draw_polygon(PackedVector2Array([Vector2(-16, -12), Vector2(-3, -9), Vector2(0, -5), Vector2(3, -9), Vector2(16, -12), Vector2(16, 12), Vector2(3, 8), Vector2(0, 12), Vector2(-3, 8), Vector2(-16, 12)]), fill, line, 2.0)
			draw_line(Vector2(0, -4), Vector2(0, 10), color, 2.0, true)
			draw_line(Vector2(-11, -5), Vector2(-4, -3), color, 1.5, true)
			draw_line(Vector2(4, -3), Vector2(11, -5), color, 1.5, true)
		"eye":
			draw_arc(Vector2.ZERO, 14.0, PI * 1.08, PI * 1.92, 24, line, 2.0, true)
			draw_arc(Vector2.ZERO, 14.0, -PI * 0.92, -PI * 0.08, 24, line, 2.0, true)
			draw_circle(Vector2.ZERO, 7.0, fill)
			draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 24, color, 2.0, true)
			draw_circle(Vector2.ZERO, 2.5, line)
		"crystal":
			_draw_polygon(PackedVector2Array([Vector2(0, -18), Vector2(11, -7), Vector2(9, 10), Vector2(0, 17), Vector2(-9, 10), Vector2(-11, -7)]), fill, line, 2.0)
			draw_line(Vector2(0, -17), Vector2(0, 15), color.lightened(0.3), 2.0, true)
			draw_line(Vector2(-10, -6), Vector2(0, 0), color, 1.5, true)
			draw_line(Vector2(10, -6), Vector2(0, 0), color, 1.5, true)
		"bell":
			_draw_polygon(PackedVector2Array([Vector2(-13, 9), Vector2(-11, -2), Vector2(-7, -10), Vector2(0, -14), Vector2(7, -10), Vector2(11, -2), Vector2(13, 9)]), fill, line, 2.0)
			draw_line(Vector2(-15, 10), Vector2(15, 10), color, 3.0, true)
			draw_circle(Vector2(0, 15), 2.5, line)
		"feather":
			_draw_polygon(PackedVector2Array([Vector2(-1, 18), Vector2(-12, 5), Vector2(-13, -8), Vector2(-5, -17), Vector2(11, -8), Vector2(9, 3)]), fill, line, 2.0)
			draw_line(Vector2(-8, 13), Vector2(8, -12), color.lightened(0.25), 2.0, true)
			draw_line(Vector2(-3, 2), Vector2(-12, 0), color, 1.0, true)
		"chain":
			draw_arc(Vector2(-6, -5), 7.0, -0.45, TAU * 0.78, 32, line, 3.0, true)
			draw_arc(Vector2(6, 5), 7.0, PI * 0.55, PI * 2.3, 32, color, 3.0, true)
		"needle":
			draw_line(Vector2(-12, 13), Vector2(12, -13), line, 2.0, true)
			draw_arc(Vector2(-2, 2), 12.0, -0.3, PI * 0.95, 26, color, 2.0, true)
			draw_circle(Vector2(12, -13), 2.5, color)
		"vial":
			_draw_vial(color)
		"fang":
			_draw_polygon(PackedVector2Array([Vector2(-11, -14), Vector2(10, -14), Vector2(8, 1), Vector2(0, 17), Vector2(-8, 1)]), fill, line, 2.0)
			draw_line(Vector2(-6, -8), Vector2(6, -8), color, 1.5, true)
		"venom":
			_draw_polygon(PackedVector2Array([Vector2(0, -17), Vector2(8, -6), Vector2(11, 2), Vector2(8, 11), Vector2(0, 16), Vector2(-8, 11), Vector2(-11, 2), Vector2(-8, -6)]), fill, line, 2.0)
			draw_arc(Vector2(0, 2), 6.0, -PI * 0.12, PI * 1.35, 22, color.lightened(0.3), 2.0, true)
			draw_circle(Vector2(4, -1), 1.5, line)
		"flame":
			_draw_polygon(PackedVector2Array([Vector2(0, -19), Vector2(8, -6), Vector2(6, 0), Vector2(13, 7), Vector2(9, 16), Vector2(-9, 16), Vector2(-14, 8), Vector2(-6, 1), Vector2(-7, -8)]), fill, line, 2.0)
			draw_line(Vector2(0, 11), Vector2(0, 2), color.lightened(0.3), 2.0, true)
		"star":
			_draw_star(color, line)
		"flute":
			draw_line(Vector2(-12, 12), Vector2(12, -12), line, 5.0, true)
			for offset in [-6.0, 0.0, 6.0]:
				draw_circle(Vector2(offset, -offset), 1.5, color.darkened(0.5))
		"rune", _:
			_draw_star(color, line)
			draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, color, 1.5, true)


func _draw_vial(color: Color) -> void:
	_draw_polygon(PackedVector2Array([Vector2(-6, -16), Vector2(6, -16), Vector2(6, -9), Vector2(12, -3), Vector2(11, 13), Vector2(6, 17), Vector2(-6, 17), Vector2(-11, 13), Vector2(-12, -3), Vector2(-6, -9)]), color.darkened(0.55), Color("eee2c9"), 2.0)
	draw_line(Vector2(-6, -8), Vector2(6, -8), color, 2.0, true)
	draw_line(Vector2(-9, 6), Vector2(9, 6), color.lightened(0.18), 2.0, true)
	draw_line(Vector2(0, -4), Vector2(0, 4), Color("eee2c9"), 1.5, true)


func _draw_star(color: Color, outline: Color) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		var radius := 17.0 if index % 2 == 0 else 7.5
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_draw_polygon(points, color.darkened(0.42), outline, 2.0)
	draw_circle(Vector2.ZERO, 2.0, color.lightened(0.25))


func _draw_polygon(points: PackedVector2Array, fill: Color, outline: Color, width: float) -> void:
	draw_colored_polygon(points, fill)
	if points.size() < 2:
		return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline, width, true)


func _draw_identity_marks(color: Color) -> void:
	var seed := posmod(icon_id.hash(), 997)
	var mark_count := 1 + posmod(seed, 3)
	for index in mark_count:
		var x := -12.0 + float(posmod(seed + index * 11, 25))
		var y := -22.0 - float(posmod(seed + index * 5, 3))
		draw_circle(Vector2(x, y), 1.0 + float(posmod(seed + index, 2)) * 0.35, color.lightened(0.25))


func _draw_rank_marks(color: Color) -> void:
	var count := 2
	if category == "relic":
		count = {"starter": 1, "common": 1, "uncommon": 2, "rare": 3, "boss": 4}.get(str(definition.get("rarity", "common")), 1)
	elif category == "item":
		count = {"positive": 1, "temporary": 2, "curse": 3, "sacred": 4, "permanent": 5}.get(str(definition.get("kind", "positive")), 1)
	else:
		count = 2 + posmod(icon_id.hash(), 3)
	for index in count:
		var x := (float(index) - float(count - 1) * 0.5) * 5.0
		draw_circle(Vector2(x, 22.0), 1.1, color.lightened(0.2))
