extends Control
## The button owns input; this face moves independently inside its fixed hit area.

const CARD_ART_SCRIPT := "res://ui/card_art.gd"
const PLAYABLE_GLOW_PATH := "res://assets/art/ui/playfeel/card_playable_glow.png"
const UNPLAYABLE_VEIL_PATH := "res://assets/art/ui/playfeel/card_unplayable_veil.png"

static var _playable_glow_tex: Texture2D
static var _unplayable_veil_tex: Texture2D
static var _textures_loaded := false

const PAPER := Color("f3ead6")
const GOLD := Color("d7b879")
const MUTED := Color("c3b8a4")
const TYPE_NAMES := {"attack": "攻击", "skill": "技能", "power": "能力"}
const RARITY_NAMES := {"starter": "初始", "common": "普通", "uncommon": "罕见", "rare": "稀有"}
const TYPE_TONES := {"attack": Color("e49a7b"), "skill": Color("a4c2ad"), "power": Color("c6a9de")}
const RARITY_TONES := {"uncommon": Color("a4c2ad"), "rare": GOLD}
const CAPTIONS := {
	"hand": "点击施放 · 悬停详览",
	"browse": "查看详情",
	"reward": "选择此牌",
	"preview": "卡牌预览",
}
const INSET := 11.0
const HEADER_HEIGHT := 43.0
const FOOTER_HEIGHT := 21.0

var card: Dictionary = {}
var availability_reason := ""
var tone := GOLD
var rarity_tone := MUTED
var context := "browse"
var owner_button: Button
var heading_font: Font
var illustration: Texture2D
var art_bounds := Rect2()
var availability_label: Label
var hover_tween: Tween
var hovered := false
var focused := false
var pressed := false
var glow := 0.0:
	set(value):
		glow = value
		queue_redraw()


func configure(button: Button, definition: Dictionary, dimensions: Vector2, title_font: Font, display_context: String = "browse") -> void:
	name = "CardVisual"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _textures_loaded:
		_textures_loaded = true
		if ResourceLoader.exists(PLAYABLE_GLOW_PATH):
			_playable_glow_tex = load(PLAYABLE_GLOW_PATH) as Texture2D
		if ResourceLoader.exists(UNPLAYABLE_VEIL_PATH):
			_unplayable_veil_tex = load(UNPLAYABLE_VEIL_PATH) as Texture2D
	card = definition
	context = display_context
	owner_button = button
	heading_font = title_font
	if ResourceLoader.exists(CARD_ART_SCRIPT, "GDScript"):
		illustration = load(CARD_ART_SCRIPT).texture_for(card)
	tone = TYPE_TONES.get(str(card.get("type", "skill")), GOLD)
	rarity_tone = RARITY_TONES.get(str(card.get("rarity", "common")), MUTED)
	position = Vector2(3, 6)
	size = dimensions - Vector2(6, 10)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_build_labels()
	if context not in ["compare", "preview"]:
		button.mouse_entered.connect(func(): hovered = true; _animate())
		button.mouse_exited.connect(func(): hovered = false; pressed = false; _animate())
		button.focus_entered.connect(func(): focused = true; _animate())
		button.focus_exited.connect(func(): focused = false; _animate())
		button.button_down.connect(func(): pressed = true; _animate())
		button.button_up.connect(func(): pressed = false; _animate())
	button.resized.connect(_fit_button)
	queue_redraw()


func _fit_button() -> void:
	size = owner_button.size - Vector2(6, 10)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_layout_labels()
	queue_redraw()


func _new_label(node_name: String, value: String, font_size: int, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _build_labels() -> void:
	var zero_cost := int(card.get("cost", 0)) == 0
	var cost := _new_label("Cost", str(int(card.get("cost", 0))), 27, GOLD if zero_cost else PAPER)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_theme_font_override("font", heading_font)
	var type_label := _new_label("Type", str(TYPE_NAMES.get(str(card.get("type", "skill")), "技能")), 14, tone)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var rarity := _new_label("Rarity", str(RARITY_NAMES.get(str(card.get("rarity", "common")), "普通")), 11, rarity_tone)
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var title := _new_label("CardName", str(card.get("name", "未知卡牌")), 20)
	title.add_theme_font_override("font", heading_font)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var description := _new_label("Description", str(card.get("description", "")), 15)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_constant_override("line_spacing", 1)
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tags: Array[String] = []
	if card.get("area_kind", "") == "attack":
		tags.append("单体＋群攻" if card.get("requires_target", false) else "群攻")
	elif card.get("area_kind", "") == "effect":
		tags.append("单体＋全体" if card.get("requires_target", false) else "全体效果")
	if int(card.get("star_cost", 0)) > 0:
		tags.append("星辰 %d" % int(card.star_cost))
	if card.get("sly", false):
		tags.append("机巧")
	if card.get("ethereal", false):
		tags.append("虚无")
	if card.get("upgraded", false):
		tags.append("已升级")
	if card.get("type", "") == "power":
		tags.append("持续能力")
	elif card.get("exhaust", false):
		tags.append("消耗")
	if card.get("retain", false):
		tags.append("保留")
	if int(card.get("soul_cost", 0)) > 0:
		tags.append("灵魂 %d" % int(card.soul_cost))
	var tag_label := _new_label("Tags", " · ".join(tags), 11, tone)
	tag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_label.add_theme_constant_override("line_spacing", 0)
	tag_label.max_lines_visible = 1
	tag_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	availability_label = _new_label("Availability", _caption(), 11, MUTED)
	availability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	availability_label.clip_text = true
	availability_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_layout_labels()


func _place(node_name: String, at: Vector2, bounds: Vector2) -> void:
	var label := get_node(node_name) as Label
	label.position = at
	label.size = bounds


func _layout_labels() -> void:
	var content_width := size.x - INSET * 2.0
	var footer_top := size.y - FOOTER_HEIGHT
	var tags := get_node("Tags") as Label
	tags.max_lines_visible = 2 if size.y >= 260.0 else 1
	var tag_height := ceilf(tags.get_theme_font("font").get_height(11)) * float(tags.max_lines_visible) + 1.0
	var tags_top := footer_top - tag_height - 3.0
	var description := get_node("Description") as Label
	var line_spacing := float(description.get_theme_constant("line_spacing"))
	var line_height := ceilf(description.get_theme_font("font").get_height(15)) + line_spacing
	var preferred_lines := 3.0 if size.y >= 285.0 else 2.0
	# Text reserves two lines even on a hand card before remaining height is allocated to art.
	var max_art_height := tags_top - HEADER_HEIGHT - 37.0 - (line_height * preferred_lines - line_spacing)
	var preferred_art_height := 54.0 + (size.y - 215.0) * 0.67
	var art_height := maxf(16.0, minf(preferred_art_height, max_art_height))
	art_bounds = Rect2(Vector2(8, HEADER_HEIGHT), Vector2(maxf(1.0, size.x - 16.0), art_height))
	_place("Cost", Vector2(10, 4), Vector2(36, 35))
	_place("Type", Vector2(size.x - 64, 5), Vector2(51, 18))
	_place("Rarity", Vector2(size.x - 64, 23), Vector2(51, 15))
	_place("CardName", Vector2(INSET, art_bounds.end.y + 3.0), Vector2(content_width, 26))
	var description_top := art_bounds.end.y + 35.0
	var description_height := tags_top - description_top - 2.0
	description.max_lines_visible = maxi(1, int(floor((description_height + line_spacing) / line_height)))
	_place("Description", Vector2(INSET + 2.0, description_top), Vector2(content_width - 4.0, description_height))
	_place("Tags", Vector2(INSET + 2.0, tags_top), Vector2(content_width - 4.0, tag_height))
	_place("Availability", Vector2(9, footer_top + 1.0), Vector2(size.x - 18, FOOTER_HEIGHT - 5.0))


func _caption() -> String:
	if context == "compare":
		return "强化版" if card.get("upgraded", false) else "原版"
	return CAPTIONS.get(context, CAPTIONS.browse)


func set_availability(reason: String) -> void:
	availability_reason = reason
	availability_label.text = reason if not reason.is_empty() else _caption()
	availability_label.add_theme_color_override("font_color", Color("f4b7a1") if not reason.is_empty() else MUTED)
	queue_redraw()


func _animate() -> void:
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	var active := (hovered or focused)
	var is_hand := context == "hand"
	var lift_y := -24.0 if is_hand else -4.0
	var hover_scale := 1.07 if is_hand else 1.035
	owner_button.z_index = (10 if is_hand else 1) if active else 0
	hover_tween = create_tween().set_parallel(true)
	hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "position:y", 7.0 if pressed else (lift_y if active else 6.0), 0.14)
	hover_tween.tween_property(self, "scale", Vector2.ONE * (0.985 if pressed else (hover_scale if active else 1.0)), 0.14)
	hover_tween.tween_property(self, "glow", 1.0 if (active and availability_reason.is_empty()) else 0.0, 0.14)


const KEYWORD_TONES := {
	"易伤": Color("e0897a"), "虚弱": Color("c9a0d6"), "中毒": Color("8fbf92"),
	"力量": Color("d9a373"), "敏捷": Color("9fc9a8"), "格挡": Color("9fbfc4"),
	"抽牌": Color("c7a66a"), "消耗": Color("ae5148"), "星辰": Color("c7a66a"),
	"灵魂": Color("b08fc0"), "保留": Color("9fbfc4"), "虚无": Color("8a8b7d"),
}

var _keyword_cache_text := ""
var _keyword_cache_width := -1.0
var _keyword_cache_lines := -1
var _keyword_cache: Array[Rect2] = []


func _plate(rect: Rect2, cut: float) -> PackedVector2Array:
	var c := clampf(cut, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	return PackedVector2Array([
		Vector2(rect.position.x + c, rect.position.y), Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c), Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y), Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x, rect.position.y + c),
	])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var loop := points.duplicate()
	if not loop.is_empty():
		loop.append(loop[0])
	return loop


func _hair(from_point: Vector2, to_point: Vector2, color: Color, width: float = 1.0) -> void:
	draw_line(Vector2(snappedf(from_point.x, 0.5), snappedf(from_point.y, 0.5)),
		Vector2(snappedf(to_point.x, 0.5), snappedf(to_point.y, 0.5)), color, width, false)


func _draw_diamond(center: Vector2, radius: float, fill: Color, outline: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0),
	])
	if fill.a > 0.0:
		draw_colored_polygon(points, fill)
	if outline.a > 0.0:
		draw_polyline(_closed(points), outline, 1.0, true)


func _draw() -> void:
	if size.x < 20.0 or size.y < 20.0:
		return
	var blocked := not availability_reason.is_empty()
	var upgraded: bool = card.get("upgraded", false)
	var rare := str(card.get("rarity", "common")) == "rare"
	var edge: Color = (GOLD if (upgraded or rare) else tone.darkened(0.34))
	edge = edge.lerp(GOLD.lightened(0.24), glow)
	if blocked:
		edge = Color("6f5949")
	var cut := 10.0
	var outline_rect := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
	var frame := _plate(outline_rect, cut)
	# 投影 + 暗石底
	var shadow := PackedVector2Array()
	for point in frame:
		shadow.append(point + Vector2(0, 3))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.52))
	var base := Color("14160f").lerp(Color("221d14"), glow * 0.7)
	if blocked:
		base = Color("15130f")
	draw_colored_polygon(frame, base)
	# 上部提亮、下部压暗，做出石面厚度
	var light := PackedVector2Array([frame[0], frame[1], frame[2], Vector2(size.x, size.y * 0.42), Vector2(0, size.y * 0.42)])
	draw_colored_polygon(light, Color(1.0, 0.97, 0.88, 0.028))
	# 内阴影（收边两圈）
	var shade_a := _plate(outline_rect.grow(-3.0), cut - 2.0)
	var shade_b := _plate(outline_rect.grow(-6.0), cut - 3.0)
	draw_polyline(_closed(shade_a), Color(0, 0, 0, 0.28), 2.0, true)
	draw_polyline(_closed(shade_b), Color(0, 0, 0, 0.12), 1.0, true)
	draw_polyline(_closed(_plate(outline_rect.grow(-7.0), cut - 3.0)), Color(1.0, 0.95, 0.85, 0.035), 1.0, true)
	# 细双线旧金外框
	draw_polyline(_closed(frame), Color(edge, 0.92), 1.0, true)
	draw_polyline(_closed(_plate(outline_rect.grow(-2.0), cut - 1.5)), Color(edge, 0.26), 1.0, true)
	# 稀有 / 升级：旧金内描边
	if rare or upgraded:
		draw_polyline(_closed(_plate(outline_rect.grow(-5.0), cut - 2.5)), Color(GOLD, 0.55 if not upgraded else 0.75), 1.0, true)
	# 顶部受光条 + 四角铆钉
	_hair(frame[0] + Vector2(2, 0.5), frame[1] + Vector2(-2, 0.5), Color(1.0, 0.97, 0.90, 0.13), 1.0)
	var rivets := [frame[2] + Vector2(-3, 3), frame[3] + Vector2(3, -3), frame[6] + Vector2(3, 3)]
	for rivet in rivets:
		_draw_diamond(rivet, 2.0, Color(edge, 0.6), Color(0, 0, 0, 0.6))
	# 标题带分割线（类型 / 稀有度下沿）
	_hair(Vector2(8.0, 41.0), Vector2(size.x - 8.0, 41.0), Color(edge, 0.22), 1.0)
	_draw_diamond(Vector2(size.x - 6.0, 41.0), 2.0, Color(edge, 0.5), Color(edge, 0.7))
	_draw_cost_gem(edge)
	var art := art_bounds
	_draw_illustration_window(art, blocked, edge)
	if upgraded:
		_draw_diamond(Vector2(art.end.x - 12.0, art.end.y - 11.0), 8.0, Color("2e2216"), GOLD)
		_draw_diamond(Vector2(art.end.x - 12.0, art.end.y - 11.0), 3.0, GOLD, GOLD)
	_draw_name_ribbon(art, edge)
	_draw_description_plate(edge)
	_draw_footer(edge, blocked)
	# StS 质感：可用流光与不可用薄纱遮罩
	if blocked:
		if _unplayable_veil_tex != null:
			draw_texture_rect(_unplayable_veil_tex, Rect2(Vector2.ZERO, size), false, Color(1.0, 1.0, 1.0, 0.62))
		else:
			draw_colored_polygon(frame, Color(0.04, 0.03, 0.03, 0.42))
	elif context == "hand":
		if _playable_glow_tex != null:
			var glow_alpha := 0.22 + glow * 0.58
			var glow_bounds := Rect2(Vector2(-5.0, -5.0), size + Vector2(10.0, 10.0))
			draw_texture_rect(_playable_glow_tex, glow_bounds, false, Color(1.0, 1.0, 1.0, glow_alpha))
		elif glow > 0.05:
			draw_polyline(_closed(frame), Color(GOLD.lightened(0.3), glow * 0.65), 2.5, true)


func _draw_cost_gem(edge: Color) -> void:
	var cost := int(card.get("cost", 0))
	var center := Vector2(28.0, 21.0)
	var radius := 16.5
	draw_circle(center + Vector2(0, 2), radius + 3.0, Color(0, 0, 0, 0.45))
	draw_circle(center, radius + 2.0, Color(0.035, 0.04, 0.035, 1.0))
	for index in 16:
		var t := float(index) / 15.0
		var color := Color("2a2117").lerp(Color("7d5f34"), pow(t, 0.8))
		color = color.lerp(Color("d8bb86"), pow(t, 2.1))
		color = color.lerp(Color("f6ecc9"), pow(t, 6.0))
		draw_circle(center, radius * (1.0 - t * 0.9), color)
	draw_circle(center, radius * 0.66, Color(0.06, 0.05, 0.035, 0.34))
	draw_arc(center, radius * 0.70, 0, TAU, 36, Color(0, 0, 0, 0.35), 2.0, true)
	draw_arc(center, radius, 0, TAU, 44, Color(edge, 0.95), 1.0, true)
	draw_arc(center, radius + 2.0, 0, TAU, 44, Color(edge, 0.28), 1.0, true)
	var glint := Color(1.0, 0.98, 0.92, 0.30)
	draw_arc(center, radius * 0.86, deg_to_rad(196.0), deg_to_rad(252.0), 16, glint, 2.0, true)
	if cost == 0:
		draw_arc(center, radius - 1.0, 0, TAU, 44, Color(GOLD.lightened(0.35), 0.55), 1.0, true)


func _draw_illustration_window(art: Rect2, blocked: bool, edge: Color) -> void:
	draw_rect(art, Color("0f120e"))
	if illustration == null:
		var center := art.get_center()
		draw_arc(center, art.size.y * 0.39, 0, TAU, 40, Color(tone, 0.34), 1.0, true)
		_draw_crest(center, art.size.y * 0.31, tone)
	else:
		var image_size := illustration.get_size()
		var scale_to_cover := maxf(art.size.x / image_size.x, art.size.y / image_size.y)
		var source_size := art.size / scale_to_cover
		var source := Rect2((image_size - source_size) * 0.5, source_size)
		draw_texture_rect_region(illustration, art, source, Color("978b85") if blocked else Color.WHITE)
		# 顶部压暗 + 底部渐深，让名称绶带能压住画面
		for index in 6:
			var step := float(index) / 6.0
			draw_rect(Rect2(art.position.x, art.position.y, art.size.x, 10.0 - index * 1.4),
				Color(0.03, 0.04, 0.03, 0.10 - step * 0.012))
			draw_rect(Rect2(art.position.x, art.end.y - 30.0 + index * 5.0, art.size.x, 5.2),
				Color(0.02, 0.02, 0.02, 0.03 + step * 0.055))
	# 插画窗内框：细金线 + 内侧黑边，保留可裁切区
	draw_rect(art, Color(0, 0, 0, 0.55), false, 1.0)
	draw_rect(art.grow(-1.0), Color(edge, 0.55), false, 1.0)
	draw_rect(art.grow(-3.0), Color(1.0, 0.95, 0.86, 0.05), false, 1.0)


func _draw_name_ribbon(art: Rect2, edge: Color) -> void:
	var top := art.end.y - 12.0
	var rect := Rect2(5.0, top, size.x - 10.0, 40.0)
	var points := _plate(rect, 7.0)
	draw_colored_polygon(points, Color(0.045, 0.052, 0.043, 0.96))
	draw_colored_polygon(_plate(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 8)), 5.0), Color(0.02, 0.024, 0.02, 0.55))
	_hair(Vector2(rect.position.x + 8.0, rect.position.y + 0.5), Vector2(rect.end.x - 8.0, rect.position.y + 0.5), Color(edge, 0.66), 1.0)
	_hair(Vector2(rect.position.x + 8.0, rect.end.y - 0.5), Vector2(rect.end.x - 8.0, rect.end.y - 0.5), Color(edge, 0.34), 1.0)
	# 绶带两端的小菱形扣
	var notch_y := rect.position.y + 20.0
	_draw_diamond(Vector2(rect.position.x + 4.0, notch_y), 3.0, Color(edge, 0.28), Color(edge, 0.8))
	_draw_diamond(Vector2(rect.end.x - 4.0, notch_y), 3.0, Color(edge, 0.28), Color(edge, 0.8))


func _draw_description_plate(edge: Color) -> void:
	var description := get_node_or_null("Description") as Label
	var tags := get_node_or_null("Tags") as Label
	if description == null or tags == null:
		return
	var top := description.position.y - 4.0
	var bottom := tags.position.y - 2.0
	var height := bottom - top
	if height <= 2.0:
		return
	var rect := Rect2(7.0, top, size.x - 14.0, height)
	draw_rect(rect, Color(0.03, 0.035, 0.03, 0.42))
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0), Color(edge, 0.16))
	draw_rect(Rect2(rect.position.x, rect.position.y, 1.0, rect.size.y), Color(edge, 0.10))
	draw_rect(Rect2(rect.end.x - 1.0, rect.position.y, 1.0, rect.size.y), Color(edge, 0.10))
	for band in _keyword_bands(Rect2(description.position, description.size)):
		draw_rect(band, Color(0.86, 0.72, 0.47, 0.13))
		draw_rect(Rect2(band.position.x, band.end.y - 1.0, band.size.x, 1.0), Color(0.86, 0.72, 0.47, 0.42))


## 关键词底纹：用 TextParagraph 复算 Label 的换行，再把命中的词量成色块垫在文字下面。
func _keyword_bands(bounds: Rect2) -> Array[Rect2]:
	var description := get_node_or_null("Description") as Label
	var bands: Array[Rect2] = []
	if description == null or description.text.is_empty() or bounds.size.x <= 4.0:
		return bands
	var local := Rect2(Vector2.ZERO, bounds.size)
	if description.text == _keyword_cache_text and is_equal_approx(bounds.size.x, _keyword_cache_width) and _keyword_cache_lines == description.max_lines_visible:
		var cached: Array[Rect2] = []
		for band in _keyword_cache:
			if local.encloses(band):
				cached.append(Rect2(band.position + bounds.position, band.size))
		return cached
	var font := description.get_theme_font("font")
	if font == null:
		return bands
	var font_size := description.get_theme_font_size("font_size")
	var line_spacing := float(description.get_theme_constant("line_spacing"))
	var line_height := font.get_height(font_size) + line_spacing
	if line_height <= 1.0:
		return bands
	var paragraph := TextParagraph.new()
	paragraph.width = bounds.size.x
	paragraph.break_flags = TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(description.text, font, font_size)
	var text := description.text
	var total_lines := paragraph.get_line_count()
	var visible_lines := description.max_lines_visible
	var truncated := visible_lines > 0 and total_lines > visible_lines
	var line_top := 0.0
	for line_index in total_lines:
		# 只画完整落在描述区内的行；宁可少画一条，也绝不压到 Tags/页脚上。
		if line_top + line_height > bounds.size.y + 0.5:
			break
		var span := paragraph.get_line_range(line_index)
		var start := int(span.x)
		var end := int(span.y)
		var last_visible: bool = truncated and line_index >= visible_lines - 1
		if end > start and not last_visible:
			for keyword in KEYWORD_TONES:
				var cursor := text.find(keyword, start)
				while cursor >= 0 and cursor + keyword.length() <= end:
					var prefix := text.substr(start, cursor - start)
					var offset := font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
					var width := font.get_string_size(keyword, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
					var band := Rect2(offset - 1.0, line_top + 1.0, width + 2.0, maxf(2.0, line_height - line_spacing - 2.0))
					if local.encloses(band):
						bands.append(band)
					cursor = text.find(keyword, cursor + keyword.length())
		line_top += line_height
	_keyword_cache_text = description.text
	_keyword_cache_width = bounds.size.x
	_keyword_cache_lines = description.max_lines_visible
	_keyword_cache = bands
	var shifted: Array[Rect2] = []
	for band in bands:
		shifted.append(Rect2(band.position + bounds.position, band.size))
	return shifted


func _draw_footer(edge: Color, blocked: bool) -> void:
	var footer_top := size.y - FOOTER_HEIGHT
	var band := Rect2(6.0, footer_top, size.x - 12.0, FOOTER_HEIGHT - 5.0)
	draw_rect(band, Color(0.09, 0.07, 0.065, 0.92) if blocked else Color(0.075, 0.077, 0.064, 0.92))
	draw_rect(Rect2(band.position.x, band.position.y, band.size.x, 1.0), Color(edge, 0.50))
	draw_rect(Rect2(band.position.x, band.end.y - 1.0, band.size.x, 1.0), Color(0, 0, 0, 0.5))
	_draw_diamond(Vector2(band.position.x + 1.0, band.get_center().y), 2.5, Color(edge, 0.22), Color(edge, 0.7))
	_draw_diamond(Vector2(band.end.x - 1.0, band.get_center().y), 2.5, Color(edge, 0.22), Color(edge, 0.7))
	# 底部类型 / 稀有度细饰线：一条细线串起两枚菱形
	var line_y := footer_top - 4.5
	_hair(Vector2(size.x - 72.0, line_y), Vector2(size.x - 46.0, line_y), Color(edge, 0.34), 1.0)
	_hair(Vector2(size.x - 30.0, line_y), Vector2(size.x - 8.0, line_y), Color(edge, 0.34), 1.0)
	_draw_diamond(Vector2(size.x - 38.0, line_y), 2.2, Color(edge, 0.5), Color(edge, 0.8))


func _draw_crest(center: Vector2, radius: float, color: Color) -> void:
	match str(card.get("type", "skill")):
		"attack":
			var blade := PackedVector2Array([Vector2(0, -1), Vector2(0.2, -0.5), Vector2(0.13, 0.35), Vector2(-0.13, 0.35), Vector2(-0.2, -0.5), Vector2(0, -1)])
			for i in range(blade.size()): blade[i] = center + blade[i] * radius
			draw_polyline(blade, color, 1.2, true)
			draw_line(center + Vector2(-0.45, 0.4) * radius, center + Vector2(0.45, 0.4) * radius, color, 1.5, true)
			draw_line(center + Vector2(0, 0.4) * radius, center + Vector2(0, 0.95) * radius, color, 2, true)
		"power":
			draw_arc(center, radius * 0.8, 0, TAU, 32, Color(color, color.a * 0.5), 1, true)
			var star := PackedVector2Array()
			for i in range(9):
				star.append(center + Vector2.from_angle(i * PI / 4.0 - PI / 2.0) * radius * (1.0 if i % 2 == 0 else 0.28))
			draw_polyline(star, color, 1.3, true)
		_:
			var shield := PackedVector2Array([Vector2(-0.65, -0.7), Vector2(0.65, -0.7), Vector2(0.55, 0.25), Vector2(0, 0.95), Vector2(-0.55, 0.25), Vector2(-0.65, -0.7)])
			for i in range(shield.size()): shield[i] = center + shield[i] * radius
			draw_polyline(shield, color, 1.4, true)
			draw_line(center + Vector2(0, -0.5) * radius, center + Vector2(0, 0.55) * radius, color, 1, true)
