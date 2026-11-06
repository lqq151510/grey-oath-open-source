extends RefCounted
## 战斗界面装饰层：角色祭坛底座、敌人意图图标、生命条叠加层。
## 只做绘制，不接管输入，也不改动任何规则状态。

const GOLD := Color("c7a66a")


## 角色格底座：暖暗渐变 + 背光 + 落点椭圆 + 四角金线 + 浮尘。
class Altar extends Control:
	var accent: Color = Color("c7a66a")
	var selected := false
	var dead := false
	var _t := 0.0

	static func ellipse_points(center: Vector2, rx: float, ry: float, steps: int = 36) -> PackedVector2Array:
		var points := PackedVector2Array()
		for index in steps:
			var angle := TAU * float(index) / float(steps)
			points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
		return points

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(not dead)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 8.0:
			return
		var fade := 0.3 if dead else 1.0
		# 竖直渐变：顶部近乎透明，落地处压深，让角色溶进舞台而不是浮在黑框里。
		var bands := 24
		for index in bands:
			var t0 := float(index) / float(bands)
			var t1 := float(index + 1) / float(bands)
			var alpha := lerpf(0.015, 0.30, pow(t0, 1.55)) * fade
			draw_rect(Rect2(0.0, h * t0, w, h * (t1 - t0) + 1.0), Color(0.055, 0.048, 0.038, alpha))
		# 从上方打下来的一束微光：七层同心收束叠加，边缘不再是一条硬直线。
		for layer in 7:
			var shrink := 1.0 - float(layer) * 0.135
			var top_y := h * (0.055 + 0.012 * float(layer))
			var bottom_y := h * (0.905 - 0.010 * float(layer))
			var cone := PackedVector2Array([
				Vector2(w * 0.5 - w * 0.052 * shrink, top_y),
				Vector2(w * 0.5 + w * 0.052 * shrink, top_y),
				Vector2(w * 0.5 + w * 0.335 * shrink, bottom_y),
				Vector2(w * 0.5 - w * 0.335 * shrink, bottom_y),
			])
			draw_colored_polygon(cone, Color(accent, 0.016 * fade))
		# 落点椭圆辉光：三层收束，代替生硬的方块底。
		var floor_point := Vector2(w * 0.5, h * 0.905)
		draw_colored_polygon(ellipse_points(floor_point, w * 0.44, h * 0.075, 44), Color(accent, 0.085 * fade))
		draw_colored_polygon(ellipse_points(floor_point, w * 0.30, h * 0.048, 40), Color(accent, 0.12 * fade))
		draw_colored_polygon(ellipse_points(floor_point, w * 0.17, h * 0.026, 32), Color(1.0, 0.92, 0.76, 0.075 * fade))
		# 四角 L 形金线：舞台镶边的暗示，比整圈描边轻。
		var inset := 6.0
		var arm := 16.0
		var bracket := Color(accent, (0.42 if selected else 0.22) * fade)
		draw_line(Vector2(inset, inset), Vector2(inset + arm, inset), bracket, 1.0, true)
		draw_line(Vector2(inset, inset), Vector2(inset, inset + arm), bracket, 1.0, true)
		draw_line(Vector2(w - inset, inset), Vector2(w - inset - arm, inset), bracket, 1.0, true)
		draw_line(Vector2(w - inset, inset), Vector2(w - inset, inset + arm), bracket, 1.0, true)
		draw_line(Vector2(inset, h - inset), Vector2(inset + arm, h - inset), bracket, 1.0, true)
		draw_line(Vector2(inset, h - inset), Vector2(inset, h - inset - arm), bracket, 1.0, true)
		draw_line(Vector2(w - inset, h - inset), Vector2(w - inset - arm, h - inset), bracket, 1.0, true)
		draw_line(Vector2(w - inset, h - inset), Vector2(w - inset, h - inset - arm), bracket, 1.0, true)
		# 顶沿一道细光，收住格子顶部。
		draw_line(Vector2(w * 0.16, 0.5), Vector2(w * 0.84, 0.5), Color(accent, (0.30 if selected else 0.16) * fade), 1.0, true)
		# 浮尘：缓慢上升，只在活着的角色格出现。
		if not dead:
			for index in 4:
				var speed := 8.0 + float(index) * 2.4
				var travel := fmod(_t * speed + float(index) * 27.0, h * 0.60)
				var y := h * 0.92 - travel
				var base_x := w * (0.24 + 0.52 * float((index * 37) % 100) / 100.0)
				var x := base_x + sin(_t * 0.85 + float(index) * 1.7) * 5.0
				var rise := clampf((y - h * 0.26) / (h * 0.30), 0.0, 1.0)
				draw_circle(Vector2(x, y), 0.9 + 0.3 * float(index % 2), Color(accent, 0.20 * rise * fade))
		if selected:
			draw_rect(Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0)), Color(accent, 0.16), false, 1.0)


## 意图条上的小图标：剑 / 盾 / 上行箭头 / 毒滴 / 菱形。
class IntentGlyph extends Control:
	var kind := "attack"
	var tint: Color = Color("e7b7a0")

	static func intent_kind(text: String) -> String:
		if "攻击" in text or "伤害" in text or "斩" in text:
			return "attack"
		if "防御" in text or "格挡" in text or "护" in text:
			return "guard"
		if "强化" in text or "力量" in text or "敏捷" in text or "再生" in text or "召唤" in text:
			return "buff"
		if "虚弱" in text or "易伤" in text or "中毒" in text or "灾厄" in text or "削弱" in text:
			return "hex"
		return "omen"

	func setup(text: String, hot: bool) -> void:
		kind = intent_kind(text)
		tint = Color("f0c2a6") if hot else Color("d8d3ba")
		custom_minimum_size = Vector2(23, 23)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var k := clampf(size.x / 19.0, 0.9, 1.6)
		var color := Color(tint, 0.98)
		var ghost := Color(tint, 0.10)
		# 先铺一层柔和外晕，图标在暗红意图条上也能跳出来。
		draw_circle(c, 9.6 * k, ghost)
		match kind:
			"attack":
				# 剑身：斜向 45° 的一道刃光；护手垂直压过剑身，剑柄末端一点配重。
				draw_line(c + Vector2(-3.4, 3.9) * k, c + Vector2(4.9, -4.7) * k, color, 2.3 * k, true)
				draw_line(c + Vector2(2.4, -2.3) * k, c + Vector2(4.9, -4.7) * k, Color(1.0, 0.97, 0.90, 0.92), 1.4 * k, true)
				draw_line(c + Vector2(-4.0, 1.0) * k, c + Vector2(-0.4, 4.4) * k, color, 2.0 * k, true)
				draw_circle(c + Vector2(-4.4, 4.9) * k, 1.4 * k, color)
			"guard":
				var shield := PackedVector2Array([
					c + Vector2(-5.4, -5.8) * k, c + Vector2(5.4, -5.8) * k, c + Vector2(4.7, 0.4) * k,
					c + Vector2(0.0, 6.5) * k, c + Vector2(-4.7, 0.4) * k, c + Vector2(-5.4, -5.8) * k,
				])
				draw_polyline(shield, color, 2.0 * k, true)
				draw_line(c + Vector2(0.0, -3.6) * k, c + Vector2(0.0, 2.9) * k, Color(color, 0.62), 1.4 * k, true)
			"buff":
				draw_polyline(PackedVector2Array([
					c + Vector2(-5.0, 1.6) * k, c + Vector2(0.0, -4.8) * k, c + Vector2(5.0, 1.6) * k,
				]), color, 2.2 * k, true)
				draw_line(c + Vector2(0.0, -2.9) * k, c + Vector2(0.0, 5.6) * k, Color(color, 0.85), 1.9 * k, true)
			"hex":
				var drop := PackedVector2Array([
					c + Vector2(0.0, -6.8) * k, c + Vector2(4.3, 1.4) * k, c + Vector2(3.8, 3.8) * k,
					c + Vector2(0.0, 5.6) * k, c + Vector2(-3.8, 3.8) * k, c + Vector2(-4.3, 1.4) * k,
					c + Vector2(0.0, -6.8) * k,
				])
				draw_polyline(drop, color, 2.0 * k, true)
				draw_circle(c + Vector2(0.0, 1.8) * k, 1.7 * k, Color(color, 0.7))
			_:
				draw_polyline(PackedVector2Array([
					c + Vector2(0.0, -6.1) * k, c + Vector2(5.6, 0.0) * k, c + Vector2(0.0, 6.1) * k,
					c + Vector2(-5.6, 0.0) * k, c + Vector2(0.0, -6.1) * k,
				]), color, 1.8 * k, true)
				draw_circle(c, 1.6 * k, Color(color, 0.75))


## 生命条叠加：顶部高光、底部暗边、25/50/75 刻度、右端亮边、低血脉冲。
class VitalOverlay extends Control:
	var bar: ProgressBar
	var tint: Color = Color("a84a3f")
	var _pulse := 0.0

	func bind(target: ProgressBar, color: Color) -> void:
		bar = target
		tint = color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bar != null:
			bar.value_changed.connect(_on_value_changed)
			_on_value_changed(bar.value)

	func _on_value_changed(_value: float) -> void:
		set_process(bar != null and bar.value > 0.0 and bar.value / maxf(1.0, bar.max_value) <= 0.3)
		queue_redraw()

	func _process(delta: float) -> void:
		_pulse += delta
		queue_redraw()

	func _draw() -> void:
		if bar == null:
			return
		var w := size.x
		var h := size.y
		if w < 4.0 or h < 4.0:
			return
		var ratio := clampf(bar.value / maxf(1.0, bar.max_value), 0.0, 1.0)
		var filled := w * ratio
		# 顶部受光与底部压暗，让纯色条有厚度。
		draw_rect(Rect2(0.0, 0.5, filled, 2.0), Color(1.0, 0.95, 0.86, 0.14))
		draw_rect(Rect2(0.0, 0.5, filled, 1.0), Color(1.0, 0.97, 0.90, 0.26))
		draw_rect(Rect2(0.0, h - 2.5, filled, 2.5), Color(0.0, 0.0, 0.0, 0.26))
		# 四分之一刻度：读血量不再靠猜。
		for step in [0.25, 0.5, 0.75]:
			var x := w * float(step)
			draw_line(Vector2(x, 1.5), Vector2(x, h - 1.5), Color(0.0, 0.0, 0.0, 0.34), 1.0)
			draw_line(Vector2(x + 1.0, 1.5), Vector2(x + 1.0, h - 1.5), Color(1.0, 0.96, 0.88, 0.06), 1.0)
		# 当前血量右端的高亮切面。
		if ratio > 0.02 and ratio < 0.995:
			draw_rect(Rect2(filled - 1.5, 0.5, 1.5, h - 1.0), Color(1.0, 0.93, 0.82, 0.38))
		# 低血脉冲：只在残血时闪，不干扰常态。
		if ratio <= 0.3 and bar.value > 0.0:
			var alpha := 0.16 + 0.13 * sin(_pulse * 4.4)
			draw_rect(Rect2(0.5, 0.5, w - 1.0, h - 1.0), Color(tint.lightened(0.30), alpha), false, 1.5)
