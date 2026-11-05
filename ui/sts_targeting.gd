extends Control
## 灰誓 · 《杀戮尖塔》风格二次贝塞尔瞄准系统（Targeting Arrow & Lock-on Reticle）
##
## 特性：
## - 指向性卡牌拖拽时，从卡牌中心向上弓起延伸出动态二次贝塞尔曲线
## - 沿线绘制由小到大平滑渐增的高亮光斑与半透明光晕
## - 终点自适应切线方向绘制锐利三角箭头
## - 光标靠近/命中敌方目标时自动磁吸，曲线颜色由金红转为高亮血红，并在目标周围绘制旋转准星

const RETICLE_TEX_PATH := "res://assets/art/ui/playfeel/target_legal.png"

const COLOR_NORMAL_CORE := Color(1.0, 0.88, 0.65, 0.95)
const COLOR_NORMAL_GLOW := Color(0.85, 0.42, 0.18, 0.45)
const COLOR_LOCKED_CORE := Color(1.0, 0.95, 0.88, 1.0)
const COLOR_LOCKED_GLOW := Color(0.95, 0.18, 0.12, 0.65)
const COLOR_LOCKED_ACCENT := Color(1.0, 0.28, 0.20, 0.95)

var active := false
var origin := Vector2.ZERO
var target := Vector2.ZERO
var locked := false
var locked_target_name := ""
var reticle_texture: Texture2D

var _anim_time := 0.0
var _snap_current := Vector2.ZERO


func _init() -> void:
	name = "StsTargetingArrow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(RETICLE_TEX_PATH):
		reticle_texture = load(RETICLE_TEX_PATH) as Texture2D


func start(from_point: Vector2) -> void:
	active = true
	origin = from_point
	target = from_point
	_snap_current = from_point
	locked = false
	locked_target_name = ""
	_anim_time = 0.0
	show()
	queue_redraw()


func update_target(to_point: Vector2, is_locked: bool = false, snap_pos: Vector2 = Vector2.ZERO, target_name: String = "") -> void:
	if not active:
		return
	locked = is_locked
	locked_target_name = target_name
	if is_locked and snap_pos != Vector2.ZERO:
		# 平滑磁吸到目标中心
		_snap_current = _snap_current.lerp(snap_pos, 0.35) if _snap_current != Vector2.ZERO else snap_pos
		target = _snap_current
	else:
		_snap_current = to_point
		target = to_point
	queue_redraw()


func stop() -> void:
	active = false
	locked = false
	locked_target_name = ""
	hide()
	queue_redraw()


func _process(delta: float) -> void:
	if active:
		_anim_time += delta
		queue_redraw()


## 计算二次贝塞尔曲线点
## B(t) = (1-t)^2 * P0 + 2*(1-t)*t * P1 + t^2 * P2
static func evaluate_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var omt := 1.0 - t
	return omt * omt * p0 + 2.0 * omt * t * p1 + t * t * p2


## 计算控制点 P1（呈现 StS 向上弓起的抛物线张力）
static func calculate_control_point(p0: Vector2, p2: Vector2) -> Vector2:
	var dx := p2.x - p0.x
	var dy := p2.y - p0.y
	var cx := p0.x + dx * 0.25
	# 向上隆起的高度随水平与垂直跨度自适应扩展
	var arc_height := maxf(120.0, absf(dx) * 0.35 + maxf(0.0, dy * 0.15))
	var cy := minf(p0.y, p2.y) - arc_height
	return Vector2(cx, cy)


func _draw() -> void:
	if not active:
		return

	var dist := origin.distance_to(target)
	if dist < 12.0:
		return

	var p0 := origin
	var p2 := target
	var p1 := calculate_control_point(p0, p2)

	var core_color := COLOR_LOCKED_CORE if locked else COLOR_NORMAL_CORE
	var glow_color := COLOR_LOCKED_GLOW if locked else COLOR_NORMAL_GLOW
	var accent_color := COLOR_LOCKED_ACCENT if locked else Color("d7a097")

	# 1. 沿贝塞尔曲线采样圆点
	var count := clampi(int(dist / 38.0), 12, 28)
	var points: Array[Vector2] = []
	for i in range(count):
		var t := float(i) / float(count)
		# 曲线微动态波动
		var wave := sin(_anim_time * 6.0 - t * 4.0) * (1.2 if locked else 0.6)
		var pt := evaluate_bezier(p0, p1, p2, t)
		if i > 0 and i < count - 1:
			var normal := Vector2(-(p2.y - p1.y), p2.x - p1.x).normalized()
			pt += normal * wave
		points.append(pt)

	# 绘制光点（从卡牌到箭头由小递增）
	for i in range(1, points.size()):
		var t := float(i) / float(points.size())
		var pt := points[i]
		var radius := lerpf(3.5, 12.0, pow(t, 1.2))
		if locked:
			radius *= 1.15

		# 脉冲发光
		var alpha_pulse := 0.85 + 0.15 * sin(_anim_time * 8.0 + t * 6.0)
		var current_glow := Color(glow_color, glow_color.a * alpha_pulse)
		var current_core := Color(core_color, core_color.a * alpha_pulse)

		# 外层半透明软光晕
		draw_circle(pt, radius * 1.6, current_glow)
		# 中层发光
		draw_circle(pt, radius * 1.1, Color(current_glow.r, current_glow.g, current_glow.b, current_glow.a * 0.8))
		# 内核高亮
		draw_circle(pt, radius * 0.55, current_core)

	# 2. 终点三角箭头（Arrow Head）
	var tangent := 2.0 * (p2 - p1)
	if tangent.length_squared() < 0.001:
		tangent = Vector2.UP
	var forward := tangent.normalized()
	var right := Vector2(-forward.y, forward.x)

	var head_len := 28.0 if not locked else 34.0
	var head_half_w := 18.0 if not locked else 22.0
	var tip := p2
	var base := p2 - forward * head_len
	var left_wing := base + right * head_half_w
	var right_wing := base - right * head_half_w
	var notch := base + forward * (head_len * 0.3)

	var arrow_poly := PackedVector2Array([tip, left_wing, notch, right_wing])
	# 箭头投影/外晕
	var shadow_poly := PackedVector2Array()
	for v in arrow_poly:
		shadow_poly.append(v + forward * 2.0)
	draw_colored_polygon(shadow_poly, Color(0, 0, 0, 0.45))
	# 箭头外发光
	draw_polyline(arrow_poly, glow_color, 4.0 if locked else 2.5, true)
	# 箭头主体
	draw_colored_polygon(arrow_poly, accent_color if locked else Color("b84a32"))
	# 箭头高光内芯
	var inner_tip := tip - forward * 3.0
	var inner_left := base + forward * (head_len * 0.2) + right * (head_half_w * 0.5)
	var inner_right := base + forward * (head_len * 0.2) - right * (head_half_w * 0.5)
	draw_colored_polygon(PackedVector2Array([inner_tip, inner_left, notch, inner_right]), core_color)

	# 3. 锁定准星（Lock-on Reticle）
	if locked:
		_draw_reticle(p2)


func _draw_reticle(center: Vector2) -> void:
	var pulse := 1.0 + 0.08 * sin(_anim_time * 10.0)
	var angle := _anim_time * 2.2
	var radius := 46.0 * pulse

	# 自绘四角锁定准星刻度
	for i in range(4):
		var base_angle := angle + float(i) * (PI * 0.5)
		var arc_len := PI * 0.22
		draw_arc(center, radius, base_angle - arc_len * 0.5, base_angle + arc_len * 0.5, 12, COLOR_LOCKED_ACCENT, 3.0, true)
		# 准星刻度向外突起角标
		var dir := Vector2.from_angle(base_angle)
		draw_line(center + dir * (radius + 2.0), center + dir * (radius + 12.0), COLOR_LOCKED_CORE, 2.5, true)

	# 内层快速反向微旋转细环
	draw_arc(center, radius * 0.72, -angle * 1.5, -angle * 1.5 + TAU, 28, Color(COLOR_LOCKED_ACCENT, 0.4), 1.5, true)

	# 贴图准星（如果存在）
	if reticle_texture != null:
		var tex_size := reticle_texture.get_size() * (0.65 * pulse)
		var dest_rect := Rect2(center - tex_size * 0.5, tex_size)
		draw_texture_rect(reticle_texture, dest_rect, false, Color(1.0, 0.9, 0.85, 0.85))
