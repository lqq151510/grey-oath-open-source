extends RefCounted
## 灰誓 · 《杀戮尖塔》式控件库。纯静态工厂 + 自绘控件，不依赖任何外部贴图。
##
## 约定：
## - 所有控件都能 StsUI.xxx() 直接 new 出来，可任意设置 size / custom_minimum_size。
## - 视觉一律在 _draw() 里画（切角、细双线、内阴影、纸纹噪点），1x 下用半像素对齐保证不糊。
## - 字体只复用项目已有的系统字体回退（与 ui/main.gd 的 _build_theme 保持一致）。
## - panel() / button_style() 返回 StyleBoxFlat（给 Theme / 容器用）；
##   cut_panel() 返回真正的自绘切角面板（双线旧金框 + 内阴影 + 石纹）。
##
## 色板来自 docs/DESIGN.md：夜底 / 面板 / 骨白 / 旧金 / 危险 / 盟友 / 冷光。

const FONT_STEPS: Array[int] = [11, 13, 15, 17, 20, 26, 34]
const BODY_FONTS := ["PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", "Heiti SC", "sans-serif"]
const SERIF_FONTS := ["Songti SC", "Noto Serif CJK SC", "Songti TC", "STSong", "serif"]

const NIGHT := Color("0e1311")
const PANEL := Color("1a201c")
const BONE := Color("e8dfcc")
const GOLD := Color("c7a66a")
const DANGER := Color("ae5148")
const ALLY := Color("7fa98c")
const COLD := Color("9fbfc4")
const MUTED := Color("8a8b7d")

static var _body_font: Font
static var _serif_font: Font


# ---------------------------------------------------------------- 色板 / 字体

static func palette() -> Dictionary:
	return {
		"night": NIGHT,
		"panel": Color(PANEL, 0.92),
		"bone": BONE,
		"gold": GOLD,
		"danger": DANGER,
		"ally": ALLY,
		"cold": COLD,
	}


static func label_font() -> Font:
	if _body_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(BODY_FONTS)
		_body_font = font
	return _body_font


static func serif_font() -> Font:
	if _serif_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(SERIF_FONTS)
		_serif_font = font
	return _serif_font


## 字号阶梯 11 / 13 / 15 / 17 / 20 / 26 / 34。
static func font_step(index: int) -> int:
	return int(FONT_STEPS[clampi(index, 0, FONT_STEPS.size() - 1)])


static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


# ---------------------------------------------------------------- StyleBox

## 切角石质面板（container 版）。真正的切角由 cut_panel() 自绘；
## 这里给出切角对应的内容边距、1px 旧金边和外投影，用作 Theme 默认面板。
static func panel(fill: Color = PANEL, edge: Color = GOLD, cut: float = 10.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill, 0.92)
	box.border_color = Color(edge, 0.62)
	box.set_border_width_all(1)
	box.corner_radius_top_left = 1
	box.corner_radius_top_right = 1
	box.corner_radius_bottom_left = 1
	box.corner_radius_bottom_right = 1
	box.corner_detail = 1
	box.anti_aliasing = true
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	var pad := maxf(cut * 0.9, 6.0)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad * 0.8
	box.content_margin_bottom = pad * 0.8
	box.set_meta("cut", cut)
	return box


## 宽底座按钮：四态 + focus。顶部 1px 高光条（上边框）、底部 2px 暗边（硬投影）。
## hover 边线更亮，并带 meta("lift") = 1.0 供调用方整体上浮 1px。
static func button_style(state: String = "normal") -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.anti_aliasing = true
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	box.corner_detail = 1
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 9
	box.content_margin_bottom = 11
	var lift := 0.0
	match state:
		"hover":
			box.bg_color = Color("2e352c")
			box.border_color = Color(GOLD.lightened(0.28), 0.95)
			box.border_width_top = 1
			box.border_width_left = 1
			box.border_width_right = 1
			box.border_width_bottom = 0
			box.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
			box.shadow_size = 0
			box.shadow_offset = Vector2(0, 2)
			lift = 1.0
		"pressed":
			box.bg_color = Color("171c16")
			box.border_color = Color(GOLD, 0.72)
			box.border_width_top = 1
			box.border_width_left = 1
			box.border_width_right = 1
			box.border_width_bottom = 0
			box.shadow_color = Color(0.0, 0.0, 0.0, 0.0)
			box.shadow_size = 0
			box.content_margin_top = 10
			box.content_margin_bottom = 10
		"disabled":
			box.bg_color = Color("141814")
			box.border_color = Color("3b4238")
			box.border_width_top = 1
			box.border_width_left = 1
			box.border_width_right = 1
			box.border_width_bottom = 0
			box.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
			box.shadow_size = 0
			box.shadow_offset = Vector2(0, 2)
		"focus":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = Color(GOLD, 0.85)
			box.set_border_width_all(1)
			box.shadow_color = Color(0, 0, 0, 0)
			box.shadow_size = 0
		_:
			box.bg_color = Color("222823")
			box.border_color = Color(GOLD, 0.55)
			box.border_width_top = 1
			box.border_width_left = 1
			box.border_width_right = 1
			box.border_width_bottom = 0
			box.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
			box.shadow_size = 0
			box.shadow_offset = Vector2(0, 2)
	box.set_meta("state", state)
	box.set_meta("lift", lift)
	return box


## 现成的宽底座按钮（用于总览页与后续接入）。
static func pedestal_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", serif_font())
	button.add_theme_font_size_override("font_size", font_step(3))
	button.add_theme_color_override("font_color", BONE)
	button.add_theme_color_override("font_hover_color", Color("f6ecd6"))
	button.add_theme_color_override("font_pressed_color", Color("d9cbb0"))
	button.add_theme_color_override("font_disabled_color", Color("6d7166"))
	button.add_theme_constant_override("outline_size", 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, button_style(state))
	button.custom_minimum_size = Vector2(176, 46)
	return button


# ---------------------------------------------------------------- 控件工厂

## 细长血条（8~10px），旧金 1px 边，数字叠在中间；blocked > 0 时左侧叠蓝白格挡段。
static func hp_bar(current: int, max_hp: int, tone: Color = DANGER, blocked: int = 0) -> Control:
	var bar := HpBar.new()
	bar.ui_font = label_font()
	bar.num_font = serif_font()
	bar.tone = tone
	bar.set_values(current, max_hp, blocked)
	bar.custom_minimum_size = Vector2(150, 10)
	return bar


## 圆形能量球：径向渐变 + 外环 + 衬线大数字，下方小字「能量」。
static func energy_orb(value: int, maximum: int = 3) -> Control:
	var orb := EnergyOrb.new()
	orb.ui_font = label_font()
	orb.num_font = serif_font()
	orb.set_value(value, maximum)
	orb.custom_minimum_size = Vector2(76, 94)
	return orb


## 抽牌 / 弃牌 / 消耗小牌堆：叠牌轮廓 + 右下角数字。
static func pile_counter(title: String, count: int, icon_kind: String = "draw") -> Control:
	var pile := PileCounter.new()
	pile.ui_font = label_font()
	pile.num_font = serif_font()
	pile.setup(title, count, icon_kind)
	pile.custom_minimum_size = Vector2(78, 92)
	return pile


## 敌方意图徽记：攻击=剑 + 红数字、防御=盾 + 冷蓝、增益=向上箭头 + 旧金。
static func intent_badge(kind: String = "attack", value: int = 0, vulnerable: bool = false) -> Control:
	var badge := IntentBadge.new()
	badge.ui_font = label_font()
	badge.num_font = serif_font()
	badge.vulnerable = vulnerable
	badge.set_kind(kind, false)
	badge.set_value(value, false)
	badge.custom_minimum_size = Vector2(66, 66)
	return badge


## 状态小签：圆角 2px、半透明底、细边。
static func chip(text: String, tone: Color = ALLY) -> Control:
	var tag := Chip.new()
	tag.ui_font = label_font()
	tag.num_font = serif_font()
	tag.setup(text, tone)
	return tag


## 中间带菱形的分隔线。
static func rule_line(width: float = 320.0) -> Control:
	var rule := RuleLine.new()
	rule.line_width = width
	rule.custom_minimum_size = Vector2(width, 14)
	return rule


## 真正的自绘切角石质面板：细双线旧金框 + 内阴影 + 石纹噪点。
static func cut_panel(fill: Color = PANEL, edge: Color = GOLD, cut: float = 12.0) -> Control:
	var plate := CutPanel.new()
	plate.setup(fill, edge, cut)
	return plate


# PART2
# ---------------------------------------------------------------- 自绘基类

class Face extends Control:
	var ui_font: Font
	var num_font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func body_font() -> Font:
		if ui_font == null:
			var font := SystemFont.new()
			font.font_names = PackedStringArray(BODY_FONTS)
			ui_font = font
		return ui_font

	func number_font() -> Font:
		if num_font == null:
			var font := SystemFont.new()
			font.font_names = PackedStringArray(SERIF_FONTS)
			num_font = font
		return num_font

	## 切角矩形（八边形）顶点。
	func chamfer(rect: Rect2, cut: float) -> PackedVector2Array:
		var c := clampf(cut, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.end.x
		var y1 := rect.end.y
		return PackedVector2Array([
			Vector2(x0 + c, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c),
			Vector2(x1, y1 - c), Vector2(x1 - c, y1), Vector2(x0 + c, y1),
			Vector2(x0, y1 - c), Vector2(x0, y0 + c),
		])

	func closed(points: PackedVector2Array) -> PackedVector2Array:
		var loop := points.duplicate()
		if not loop.is_empty():
			loop.append(loop[0])
		return loop

	func hairline(from_point: Vector2, to_point: Vector2, color: Color, width: float = 1.0) -> void:
		draw_line(Vector2(snappedf(from_point.x, 0.5), snappedf(from_point.y, 0.5)),
			Vector2(snappedf(to_point.x, 0.5), snappedf(to_point.y, 0.5)), color, width, false)

	func diamond(center: Vector2, radius: float, fill: Color, outline: Color, outline_width: float = 1.0) -> void:
		var points := PackedVector2Array([
			center + Vector2(0, -radius), center + Vector2(radius, 0),
			center + Vector2(0, radius), center + Vector2(-radius, 0),
		])
		if fill.a > 0.0:
			draw_colored_polygon(points, fill)
		if outline.a > 0.0:
			draw_polyline(closed(points), outline, outline_width, true)

	## 确定性石纹噪点：同尺寸每次重绘完全一致，不会闪。
	func grain(rect: Rect2, salt: int, strength: float = 0.05) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = salt + int(rect.size.x) * 131 + int(rect.size.y) * 977
		var count := int(clampf(rect.size.x * rect.size.y / 480.0, 6.0, 260.0))
		for i in count:
			var point := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
			var alpha := strength * rng.randf_range(0.25, 1.0)
			if rng.randf() < 0.22:
				draw_rect(Rect2(point.floor(), Vector2(1, 1)), Color(0.0, 0.0, 0.0, alpha * 1.4))
			else:
				draw_rect(Rect2(point.floor(), Vector2(1, 1)), Color(0.94, 0.90, 0.80, alpha))

	## 以 anchor 为文字视觉中心画一行字（先描边后填充，压在任何底上都清楚）。
	func text_center(anchor: Vector2, text: String, font: Font, font_size: int, color: Color,
			outline: Color = Color(0.02, 0.022, 0.02, 0.88), outline_size: int = 2) -> void:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := anchor + Vector2(-width * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		if outline_size > 0 and outline.a > 0.0:
			draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ---------------------------------------------------------------- 血条

class HpBar extends Face:
	var current := 1
	var maximum := 1
	var blocked := 0
	var ratio := 1.0
	var tone := Color("ae5148")
	var show_numbers := true

	func set_values(value: int, max_value: int, block_value: int = 0) -> void:
		current = maxi(value, 0)
		maximum = maxi(max_value, 1)
		blocked = maxi(block_value, 0)
		ratio = clampf(float(current) / float(maximum), 0.0, 1.0)
		queue_redraw()

	func set_block(value: int) -> void:
		blocked = maxi(value, 0)
		queue_redraw()

	func _draw() -> void:
		if size.x < 12.0 or size.y < 6.0:
			return
		var height: float = clampf(minf(size.y, 10.0), 8.0, 10.0)
		var top := floorf((size.y - height) * 0.5)
		var outer := Rect2(0.5, top + 0.5, size.x - 1.0, height - 1.0)
		var inner := outer.grow(-1.0)
		draw_rect(Rect2(outer.position - Vector2(0, 1), outer.size + Vector2(0, 2)), Color(0.0, 0.0, 0.0, 0.35))
		draw_rect(outer, Color(0.055, 0.062, 0.052, 0.95))
		draw_rect(inner, Color("241a17"))
		var fill_width := inner.size.x * ratio
		if fill_width > 0.4:
			draw_rect(Rect2(inner.position, Vector2(fill_width, inner.size.y)), Color(tone.darkened(0.18), 1.0))
			var gloss := maxf(1.0, floorf(inner.size.y * 0.42))
			draw_rect(Rect2(inner.position, Vector2(fill_width, gloss)), Color(tone.lightened(0.26), 0.85))
			draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 1), Vector2(fill_width, 1)), Color(tone.darkened(0.55), 0.9))
			if ratio < 0.999:
				var lost := Rect2(inner.position + Vector2(fill_width, 0), Vector2(inner.size.x - fill_width, inner.size.y))
				draw_rect(lost, Color(0.0, 0.0, 0.0, 0.28))
		else:
			draw_rect(inner, Color(0.0, 0.0, 0.0, 0.45))
		# 格挡：左侧蓝白段
		if blocked > 0:
			var guard_width: float = clampf(inner.size.x * float(blocked) / float(maximum), 5.0, inner.size.x)
			var guard := Rect2(inner.position, Vector2(guard_width, inner.size.y))
			draw_rect(guard, Color(COLD, 0.88))
			draw_rect(Rect2(guard.position, Vector2(guard.size.x, 1)), Color(1.0, 1.0, 1.0, 0.72))
			draw_rect(Rect2(guard.position + Vector2(0, guard.size.y - 1), Vector2(guard.size.x, 1)), Color(COLD.darkened(0.45), 0.9))
			var hatch_x := guard.position.x + 2.0
			while hatch_x < guard.end.x - 1.0:
				draw_line(Vector2(hatch_x, guard.position.y + 1), Vector2(hatch_x - 2.0, guard.end.y - 1), Color(1.0, 1.0, 1.0, 0.20), 1.0, false)
				hatch_x += 4.0
		# 旧金 1px 边
		draw_rect(outer, Color(GOLD, 0.82), false, 1.0)
		draw_rect(outer.grow(1.0), Color(0.0, 0.0, 0.0, 0.45), false, 1.0)
		if not show_numbers:
			return
		var font_size: int = 9 if height <= 10.0 else 11
		var text := str(current) + "/" + str(maximum)
		var tint := BONE if ratio > 0.35 else Color("f3c6ba")
		# 10px 高的细条里给数字一块加深的凹槽，1px 描边，保证压在红色填充上也读得清。
		var text_width := number_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var plate_width := minf(inner.size.x, text_width + 13.0)
		var plate := Rect2(floorf(size.x * 0.5 - plate_width * 0.5), inner.position.y, plate_width, inner.size.y)
		draw_rect(plate, Color(0.025, 0.022, 0.02, 0.62))
		draw_rect(Rect2(plate.position, Vector2(plate.size.x, 1.0)), Color(0.0, 0.0, 0.0, 0.55))
		draw_rect(Rect2(plate.position.x, plate.position.y, 1.0, plate.size.y), Color(GOLD, 0.20))
		draw_rect(Rect2(plate.end.x - 1.0, plate.position.y, 1.0, plate.size.y), Color(GOLD, 0.20))
		text_center(Vector2(size.x * 0.5, top + height * 0.5), text, number_font(), font_size, tint, Color(0.02, 0.02, 0.02, 0.92), 1)


# ---------------------------------------------------------------- 能量球

class EnergyOrb extends Face:
	var value := 3
	var maximum := 3
	var value_text := "3"
	var sub_label := "能量"

	func set_value(new_value: int, new_maximum: int = 3) -> void:
		value = maxi(new_value, 0)
		maximum = maxi(new_maximum, 0)
		value_text = str(value)
		queue_redraw()

	func _draw() -> void:
		if size.x < 24.0 or size.y < 30.0:
			return
		var label_band := 16.0
		var radius := minf(size.x * 0.5, (size.y - label_band) * 0.5) - 1.0
		if radius < 8.0:
			return
		var center := Vector2(size.x * 0.5, radius + 1.0)
		draw_circle(center, radius + 3.0, Color(GOLD, 0.07))
		draw_circle(center, radius + 1.5, Color(GOLD, 0.10))
		var steps := 20
		for index in steps:
			var t := float(index) / float(steps - 1)
			var ring_radius := radius * (1.0 - t * 0.95)
			var color := Color("251a10").lerp(Color("8a6836"), pow(t, 0.85))
			color = color.lerp(Color("c7a66a"), pow(t, 1.9))
			color = color.lerp(Color("f7eccd"), pow(t, 7.0))
			draw_circle(center, ring_radius, color)
		draw_arc(center, radius - 1.5, 0, TAU, 56, Color(0.0, 0.0, 0.0, 0.34), 3.0, true)
		draw_arc(center, radius, 0, TAU, 64, Color(GOLD, 0.95), 2.0, true)
		draw_arc(center, radius + 2.0, 0, TAU, 64, Color(GOLD, 0.16), 1.0, true)
		draw_arc(center, radius * 0.64, deg_to_rad(198.0), deg_to_rad(262.0), 18, Color(1.0, 0.97, 0.90, 0.20), 3.0, true)
		var numeral := clampi(int(radius * 0.92), 18, 34)
		text_center(center + Vector2(0, -radius * 0.03), value_text, number_font(), numeral, Color("fbf2da"), Color(0.10, 0.06, 0.02, 0.92), 3)
		text_center(Vector2(size.x * 0.5, center.y + radius + 10.0), sub_label, body_font(), 11, Color(GOLD, 0.88), Color(0.02, 0.03, 0.02, 0.85), 2)


# ---------------------------------------------------------------- 牌堆计数

class PileCounter extends Face:
	var title := "抽牌"
	var count := 0
	var icon_kind := "draw"
	var tone := Color("c7a66a")

	func setup(new_title: String, new_count: int, new_kind: String) -> void:
		title = new_title
		count = maxi(new_count, 0)
		icon_kind = new_kind
		match icon_kind:
			"discard":
				tone = Color("9fbfc4")
			"exhaust":
				tone = Color("ae5148")
			_:
				tone = Color("c7a66a")
		queue_redraw()

	func set_count(new_count: int) -> void:
		count = maxi(new_count, 0)
		queue_redraw()

	func _draw() -> void:
		if size.x < 20.0 or size.y < 28.0:
			return
		var center_x := floorf(size.x * 0.5)
		text_center(Vector2(center_x, 9.0), title, body_font(), 11, Color(MUTED, 0.95), Color(0.02, 0.03, 0.02, 0.8), 2)
		var card_w := minf(size.x - 24.0, 38.0)
		var card_h := minf(size.y - 22.0, 60.0)
		var base := Vector2(center_x - card_w * 0.5, 16.0)
		for index in range(2, -1, -1):
			var offset := Vector2(index * 2.0 - 2.0, -index * 2.0)
			var rect := Rect2(base + offset, Vector2(card_w, card_h))
			var points := chamfer(rect, 4.0)
			draw_colored_polygon(points, Color(0.09, 0.105, 0.09, 0.95) if index > 0 else Color("232a23"))
			draw_polyline(closed(points), Color(tone, 0.45 if index > 0 else 0.85), 1.0, true)
			if index == 0:
				draw_rect(rect.grow(-4.0), Color(tone, 0.10))
				_draw_glyph(rect.get_center(), minf(card_w, card_h) * 0.28, tone)
		var plaque := Rect2(size.x - 34.0, minf(base.y + card_h - 14.0, size.y - 24.0), 32.0, 22.0)
		var plaque_points := chamfer(plaque, 4.0)
		draw_colored_polygon(plaque_points, Color(0.06, 0.07, 0.06, 0.94))
		draw_polyline(closed(plaque_points), Color(GOLD, 0.7), 1.0, true)
		text_center(plaque.get_center(), str(count), number_font(), 16, BONE, Color(0.02, 0.02, 0.02, 0.9), 2)

	func _draw_glyph(center: Vector2, radius: float, color: Color) -> void:
		match icon_kind:
			"discard":
				var down := PackedVector2Array([
					center + Vector2(-radius * 0.5, -radius * 0.18),
					center + Vector2(0, radius * 0.34),
					center + Vector2(radius * 0.5, -radius * 0.18),
				])
				draw_polyline(down, color, 1.6, true)
				hairline(center + Vector2(0, -radius * 0.6), center + Vector2(0, radius * 0.55), Color(color, 0.55), 1.0)
			"exhaust":
				draw_polyline(PackedVector2Array([center + Vector2(-radius * 0.42, -radius * 0.42), center + Vector2(radius * 0.42, radius * 0.42)]), color, 1.8, true)
				draw_polyline(PackedVector2Array([center + Vector2(radius * 0.42, -radius * 0.42), center + Vector2(-radius * 0.42, radius * 0.42)]), color, 1.8, true)
			_:
				var up := PackedVector2Array([
					center + Vector2(-radius * 0.5, radius * 0.18),
					center + Vector2(0, -radius * 0.34),
					center + Vector2(radius * 0.5, radius * 0.18),
				])
				draw_polyline(up, color, 1.6, true)
				hairline(center + Vector2(0, radius * 0.6), center + Vector2(0, -radius * 0.55), Color(color, 0.55), 1.0)


# PART3
# ---------------------------------------------------------------- 意图徽记

class IntentBadge extends Face:
	var kind := "attack"
	var raw_kind := "attack"
	var value := 0
	var vulnerable := false
	var tone := Color("ae5148")

	var _pulse := 1.0
	var _pulse_clock := 0.0
	var _pulse_active := false

	func set_kind(new_kind: String, animate: bool = true) -> void:
		raw_kind = new_kind
		match new_kind.to_lower():
			"defend", "defence", "defense", "block", "shield", "防御":
				kind = "defend"
				tone = COLD
			"buff", "power", "grow", "增益":
				kind = "buff"
				tone = GOLD
			"debuff", "curse", "削弱":
				kind = "debuff"
				tone = Color("b08fc0")
			_:
				kind = "attack"
				tone = DANGER
		if animate:
			_pulse_now()
		queue_redraw()

	func set_value(new_value: int, animate: bool = true) -> void:
		var changed := new_value != value
		value = new_value
		if animate and changed:
			_pulse_now()
		queue_redraw()

	func set_vulnerable(flag: bool) -> void:
		vulnerable = flag
		queue_redraw()

	func _pulse_now() -> void:
		_pulse_clock = 0.0
		_pulse_active = true
		set_process(true)

	func _process(delta: float) -> void:
		if not _pulse_active:
			set_process(false)
			return
		_pulse_clock += delta
		var duration := 0.26
		if _pulse_clock >= duration:
			_pulse = 1.0
			_pulse_active = false
			set_process(false)
		else:
			var falloff := 1.0 - _pulse_clock / duration
			_pulse = 1.0 + 0.13 * sin(_pulse_clock * PI * 2.0 / duration) * falloff
		queue_redraw()

	func _draw() -> void:
		if size.x < 24.0 or size.y < 24.0:
			return
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		pivot_offset = center
		draw_set_transform(center, 0.0, Vector2(_pulse, _pulse))
		var plate := chamfer(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), radius * 0.34)
		draw_colored_polygon(plate, Color(0.045, 0.055, 0.047, 0.94))
		draw_colored_polygon(chamfer(Rect2(-radius + 2.0, -radius + 2.0, radius * 2.0 - 4.0, radius * 2.0 - 4.0), radius * 0.30), Color(tone, 0.10))
		draw_polyline(closed(plate), Color(tone, 0.80), 1.0, true)
		draw_polyline(closed(chamfer(Rect2(-radius + 2.5, -radius + 2.5, radius * 2.0 - 5.0, radius * 2.0 - 5.0), radius * 0.28)), Color(tone, 0.22), 1.0, true)
		var glyph_radius := radius * 0.46
		var glyph_center := Vector2(0, -radius * 0.06)
		match kind:
			"defend":
				_draw_shield(glyph_center, glyph_radius)
			"buff":
				_draw_arrow(glyph_center, glyph_radius)
			"debuff":
				_draw_arrow(glyph_center, glyph_radius, true)
			_:
				_draw_sword(glyph_center, glyph_radius)
		if value > 0:
			var numeral_center := Vector2(0, radius * 0.42)
			var numeral := clampi(int(radius * 0.62), 13, 24)
			text_center(numeral_center, str(value), number_font(), numeral, tone.lightened(0.38), Color(0.02, 0.02, 0.02, 0.92), 3)
		if vulnerable:
			diamond(Vector2(-radius + 5.0, radius - 5.0), 3.5, Color(DANGER, 0.9), Color(0.02, 0.02, 0.02, 0.9), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_sword(center: Vector2, radius: float) -> void:
		var blade := PackedVector2Array([
			center + Vector2(0, -radius),
			center + Vector2(radius * 0.30, -radius * 0.16),
			center + Vector2(radius * 0.22, radius * 0.34),
			center + Vector2(0, radius * 0.44),
			center + Vector2(-radius * 0.22, radius * 0.34),
			center + Vector2(-radius * 0.30, -radius * 0.16),
		])
		draw_colored_polygon(blade, Color(tone, 0.88))
		draw_polyline(closed(blade), Color(BONE, 0.75), 1.0, true)
		hairline(center + Vector2(0, -radius * 0.72), center + Vector2(0, radius * 0.30), Color(1.0, 1.0, 0.96, 0.45), 1.0)
		hairline(center + Vector2(-radius * 0.52, radius * 0.46), center + Vector2(radius * 0.52, radius * 0.46), Color(tone.lightened(0.3), 0.95), 2.0)
		hairline(center + Vector2(0, radius * 0.46), center + Vector2(0, radius * 0.78), Color(tone.lightened(0.2), 0.9), 2.0)

	func _draw_shield(center: Vector2, radius: float) -> void:
		var body := PackedVector2Array([
			center + Vector2(0, -radius * 0.92),
			center + Vector2(radius * 0.72, -radius * 0.52),
			center + Vector2(radius * 0.60, radius * 0.22),
			center + Vector2(0, radius * 0.92),
			center + Vector2(-radius * 0.60, radius * 0.22),
			center + Vector2(-radius * 0.72, -radius * 0.52),
		])
		draw_colored_polygon(body, Color(tone, 0.86))
		draw_polyline(closed(body), Color(BONE, 0.72), 1.0, true)
		var inner := PackedVector2Array()
		for point in body:
			inner.append(center + (point - center) * 0.60)
		draw_polyline(closed(inner), Color(0.03, 0.05, 0.06, 0.55), 1.0, true)
		hairline(center + Vector2(0, -radius * 0.60), center + Vector2(0, radius * 0.58), Color(1.0, 1.0, 0.98, 0.38), 1.0)

	func _draw_arrow(center: Vector2, radius: float, downward: bool = false) -> void:
		var flip := -1.0 if downward else 1.0
		var head := PackedVector2Array([
			center + Vector2(0, -radius * 0.86 * flip),
			center + Vector2(radius * 0.52, -radius * 0.18 * flip),
			center + Vector2(-radius * 0.52, -radius * 0.18 * flip),
		])
		draw_colored_polygon(head, Color(tone, 0.92))
		draw_polyline(closed(head), Color(BONE, 0.6), 1.0, true)
		var shaft := Rect2(center + Vector2(-radius * 0.16, -radius * 0.24 * flip), Vector2(radius * 0.32, radius * 0.78 * flip))
		draw_rect(shaft, Color(tone, 0.82))
		hairline(center + Vector2(-radius * 0.62, radius * 0.66 * flip), center + Vector2(radius * 0.62, radius * 0.66 * flip), Color(tone.lightened(0.25), 0.85), 1.0)


# ---------------------------------------------------------------- 状态签

class Chip extends Face:
	var text := ""
	var tone := Color("7fa98c")

	func setup(new_text: String, new_tone: Color) -> void:
		text = new_text
		tone = new_tone
		var width: float = body_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0
		custom_minimum_size = Vector2(maxf(width, 34.0), 20.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		if text.is_empty() or size.x < 8.0 or size.y < 8.0:
			return
		var rect := Rect2(0.5, 0.5, size.x - 1.0, size.y - 1.0)
		var points := chamfer(rect, 3.0)
		draw_colored_polygon(points, Color(tone, 0.16))
		draw_colored_polygon(chamfer(rect.grow(-1.0), 2.5), Color(0.04, 0.05, 0.045, 0.55))
		draw_polyline(closed(points), Color(tone, 0.62), 1.0, true)
		draw_rect(Rect2(2.0, 1.0, size.x - 4.0, 1.0), Color(tone.lightened(0.35), 0.20))
		var font_size := 11
		var text_width: float = body_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := Vector2((size.x - text_width) * 0.5, (size.y + body_font().get_ascent(font_size) - body_font().get_descent(font_size)) * 0.5)
		draw_string(body_font(), baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tone.lightened(0.52))


# ---------------------------------------------------------------- 分隔线

class RuleLine extends Face:
	var line_width := 320.0

	func _draw() -> void:
		if size.x < 16.0:
			return
		var center_y := floorf(size.y * 0.5) + 0.5
		var center_x := floorf(size.x * 0.5) + 0.5
		var half := size.x * 0.5
		var gap := 7.0
		var left_end := center_x - gap
		var right_start := center_x + gap
		for index in 26:
			var t := float(index) / 25.0
			var alpha := 0.02 + t * 0.34
			var offset := half * t
			draw_rect(Rect2(center_x - offset - half / 26.0, center_y, half / 26.0 + 0.5, 1.0), Color(GOLD, alpha))
			draw_rect(Rect2(center_x + offset, center_y, half / 26.0 + 0.5, 1.0), Color(GOLD, alpha))
		hairline(Vector2(left_end - 4.0, center_y), Vector2(left_end, center_y), Color(GOLD, 0.55), 1.0)
		hairline(Vector2(right_start, center_y), Vector2(right_start + 4.0, center_y), Color(GOLD, 0.55), 1.0)
		diamond(Vector2(center_x, center_y), 4.0, Color(GOLD, 0.9), Color(0.03, 0.03, 0.03, 0.9), 1.0)
		diamond(Vector2(center_x, center_y), 2.0, Color(0.04, 0.05, 0.04, 0.95), Color(GOLD, 0.5), 1.0)


# ---------------------------------------------------------------- 切角面板

class CutPanel extends Face:
	var fill := Color("1a201c")
	var edge := Color("c7a66a")
	var cut := 12.0

	func setup(new_fill: Color, new_edge: Color, new_cut: float) -> void:
		fill = new_fill
		edge = new_edge
		cut = maxf(new_cut, 0.0)
		queue_redraw()

	func _draw() -> void:
		if size.x < 12.0 or size.y < 12.0:
			return
		var rect := Rect2(1.0, 1.0, size.x - 2.0, size.y - 2.0)
		var points := chamfer(rect, cut)
		var shadow := PackedVector2Array()
		for point in points:
			shadow.append(point + Vector2(0, 3))
		draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.45))
		draw_colored_polygon(points, Color(fill, 0.94))
		# 内阴影：从边缘向内递暗
		for index in 5:
			var inset := 1.0 + index * 1.0
			var alpha := 0.16 - index * 0.03
			draw_polyline(closed(chamfer(rect.grow(-inset), maxf(cut - inset, 0.0))), Color(0.0, 0.0, 0.0, alpha), 1.0, true)
		# 顶部受光
		hairline(points[0] + Vector2(1, 1), points[1] + Vector2(-1, 1), Color(1.0, 0.96, 0.86, 0.06), 1.0)
		# 细双线旧金框
		draw_polyline(closed(points), Color(edge, 0.72), 1.0, true)
		var inner := chamfer(rect.grow(-3.0), maxf(cut - 2.0, 0.0))
		draw_polyline(closed(inner), Color(edge, 0.26), 1.0, true)
		# 四角短刻线
		var corner := chamfer(rect, cut)[0]
		hairline(Vector2(rect.position.x + cut, rect.position.y + 0.5), Vector2(rect.position.x + cut + 12.0, rect.position.y + 0.5), Color(edge, 0.5), 1.0)
		hairline(Vector2(rect.end.x - cut - 12.0, rect.end.y - 0.5), Vector2(rect.end.x - cut, rect.end.y - 0.5), Color(edge, 0.5), 1.0)
		grain(rect.grow(-2.0), 17, 0.032)
