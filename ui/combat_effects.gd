extends Control
## Ephemeral combat feedback. Global coordinates in, no input capture or rule changes.

const GOLD := Color("c7a66a")
const BONE := Color("f5e8ce")
const DAMAGE := Color("ef9a85")
const SHIELD := Color("a7ced1")
const POISON := Color("a4c886")
const HEAL := Color("91d49a")

const FLOAT_ICONS := {
	"hit": "res://assets/art/ui/playfeel/float_dmg.png",
	"shield": "res://assets/art/ui/playfeel/float_block.png",
	"heal": "res://assets/art/ui/playfeel/float_heal.png",
}

var effects: Array[Dictionary] = []
var _float_textures: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in FLOAT_ICONS:
		var path: String = FLOAT_ICONS[key]
		if ResourceLoader.exists(path):
			_float_textures[key] = load(path) as Texture2D


func play_attack(from: Vector2, to: Vector2, style: String = "slash", tint: Color = GOLD) -> void:
	effects.append({"type": "attack", "from": from - global_position, "to": to - global_position, "style": style, "color": tint, "age": 0.0, "duration": 0.42})
	queue_redraw()


func play_area(points: Array, tint: Color = GOLD) -> void:
	if points.is_empty():
		return
	var local_points: Array = []
	for point in points:
		local_points.append(point - global_position)
	effects.append({"type": "area", "points": local_points, "color": tint, "age": 0.0, "duration": 0.75})
	queue_redraw()


func play_hit(at: Vector2, damage: int, blocked: int = 0, poison: bool = false) -> void:
	var point := at - global_position
	if damage > 0:
		effects.append({"type": "hit", "at": point, "color": POISON if poison else DAMAGE, "text": "-%d" % damage, "age": 0.0, "duration": 0.76, "wash": true})
	if blocked > 0:
		effects.append({"type": "shield", "at": point + Vector2(0, -24 if damage > 0 else 0), "color": SHIELD, "text": "格挡 %d" % blocked, "age": 0.0, "duration": 0.78})
	queue_redraw()


func play_heal(at: Vector2, amount: int) -> void:
	if amount > 0:
		effects.append({"type": "heal", "at": at - global_position, "color": HEAL, "text": "+%d" % amount, "age": 0.0, "duration": 0.78})
	queue_redraw()


func play_status(at: Vector2, text_value: String, tint: Color = GOLD) -> void:
	effects.append({"type": "status", "at": at - global_position, "color": tint, "text": text_value, "age": 0.0, "duration": 0.78})
	queue_redraw()


func play_death(at: Vector2) -> void:
	effects.append({"type": "death", "at": at - global_position, "color": GOLD, "age": 0.0, "duration": 0.68})
	queue_redraw()


func clear_effects() -> void:
	effects.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if effects.is_empty():
		return
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["age"] = float(effects[i]["age"]) + delta
		if float(effects[i]["age"]) >= float(effects[i]["duration"]):
			effects.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for effect in effects:
		var progress := clampf(float(effect.age) / float(effect.duration), 0, 1)
		var color: Color = effect.color
		color.a = 1.0 - progress
		match str(effect.type):
			"attack": _attack(effect, progress, color)
			"area": _area(effect, progress, color)
			"hit", "shield", "heal", "status": _impact(effect, progress, color)
			"death": _death(effect, progress, color)


func _attack(effect: Dictionary, progress: float, color: Color) -> void:
	var origin: Vector2 = effect["from"]
	var target: Vector2 = effect["to"]
	var direction := (target - origin).normalized()
	# 1) 起手蓄力：出发点一团收束的光，交代"谁出手"。
	if progress < 0.24:
		var charge := 1.0 - progress / 0.24
		draw_circle(origin, 4.0 + 7.0 * (1.0 - charge), Color(color, color.a * 0.22 * charge))
		draw_circle(origin, 2.4, Color(BONE, color.a * 0.75 * charge))
	# 2) 飞行拖尾：外层柔光 + 中层色带 + 内核白线，尾端散几粒余烬。
	var head := origin.lerp(target, minf(progress * 3.2, 1.0))
	if progress < 0.42:
		var span := maxf(origin.distance_to(head), 1.0)
		var tail := origin.lerp(head, maxf(0.0, 1.0 - 96.0 / span))
		draw_line(tail, head, Color(color, color.a * 0.14), 26.0, true)
		draw_line(tail, head, Color(color, color.a * 0.50), 10.0, true)
		draw_line(tail, head, Color(BONE, color.a * 0.95), 3.0, true)
		draw_circle(head, 4.5, Color(BONE, color.a))
		for index in 3:
			var t := fmod(progress * 4.2 + float(index) * 0.33, 1.0)
			draw_circle(tail.lerp(head, t), 1.5, Color(color, color.a * 0.28 * (1.0 - t)))
		if str(effect.style) in ["magic", "poison", "projectile"]:
			draw_arc(head, 13.0, 0, TAU, 24, Color(color, color.a * 0.75), 2.0, true)
	# 3) 命中：月牙弧光叠冲击波，再加锥形火花与尘团，打出"斩进去"的层次。
	if progress > 0.14:
		var hit := clampf((progress - 0.14) / 0.86, 0.0, 1.0)
		var reach := 18.0 + 66.0 * pow(hit, 0.45)
		var base_angle := (origin - target).angle()
		for index in 3:
			var radius := reach * (1.0 + 0.17 * float(index))
			var width := (7.5 - 1.9 * float(index)) * (1.0 - 0.55 * hit)
			var span := deg_to_rad(96.0 - 10.0 * float(index))
			draw_arc(target, radius, base_angle - span * 0.5, base_angle + span * 0.5, 26,
				Color(color, color.a * (0.52 - 0.12 * float(index))), maxf(1.0, width), true)
		draw_arc(target, reach * 0.86, base_angle - deg_to_rad(46.0), base_angle + deg_to_rad(46.0), 22,
			Color(BONE, color.a * 0.9), maxf(1.0, 4.0 * (1.0 - hit)), true)
		var ring := 10.0 + 56.0 * hit
		draw_arc(target, ring, 0, TAU, 40, Color(BONE, color.a * 0.34 * (1.0 - hit)), 2.0, true)
		draw_arc(target, ring * 0.72, 0, TAU, 32, Color(color, color.a * 0.22 * (1.0 - hit)), 1.0, true)
		for index in 9:
			var spread_angle := (float(index) - 4.0) * 0.20
			var ray := direction.rotated(spread_angle)
			var length := 10.0 + 46.0 * pow(hit, 0.7) * (1.0 - absf(float(index) - 4.0) * 0.08)
			draw_line(target + ray * ring * 0.68, target + ray * (ring * 0.68 + length),
				Color(color, color.a * (0.78 - absf(float(index) - 4.0) * 0.13)), 2.0, true)
		for index in 5:
			var angle := TAU * float(index) / 5.0 + 0.5
			var distance := ring * (0.55 + 0.20 * float(index % 2))
			draw_circle(target + Vector2.from_angle(angle) * distance, 2.0 + 3.6 * hit,
				Color(0.55, 0.48, 0.40, color.a * 0.09 * (1.0 - hit)))


func _area(effect: Dictionary, progress: float, color: Color) -> void:
	var points: Array = effect.points
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= float(points.size())
	var radius := 70.0
	for point in points:
		radius = maxf(radius, center.distance_to(point) + 75.0)
	var expansion := minf(progress * 4.0, 1.0)
	draw_arc(center, radius * expansion, 0, TAU, 64, Color(color, color.a * 0.8), 7.0, true)
	draw_arc(center, radius * expansion * 0.82, 0, TAU, 64, Color(BONE, color.a * 0.65), 2.5, true)
	for point in points:
		draw_line(center, point, Color(color, color.a * 0.6), 4.0, true)
		draw_arc(point, 24 + expansion * 40, 0, TAU, 32, Color(BONE, color.a), 3.0, true)


func _impact(effect: Dictionary, progress: float, color: Color) -> void:
	var at: Vector2 = effect.at
	var kind := str(effect.type)
	if kind == "shield":
		draw_arc(at, 28 + progress * 15, PI * 0.6, PI * 1.4, 24, color, 4.0 * (1.0 - progress) + 1.0, true)
		draw_arc(at, 35 + progress * 18, PI * 0.65, PI * 1.35, 24, Color(color, color.a * 0.4), 1.2, true)
	elif kind == "hit" and progress < 0.55:
		if bool(effect.get("wash", false)) and progress < 0.28:
			draw_rect(Rect2(Vector2.ZERO, size), Color(color.r, color.g, color.b, 0.08 * (1.0 - progress / 0.28)))
		draw_arc(at, 12 + progress * 42, 0, TAU, 32, Color(color, color.a * 0.9), 3.2 * (1.0 - progress) + 0.8, true)
		for i in 8:
			var ray := Vector2.from_angle(i * TAU / 8 + 0.3)
			draw_line(at + ray * (8 + progress * 28), at + ray * (20 + progress * 72), color, 2.4, true)
	elif kind == "heal":
		var center := at + Vector2(0, -20 - progress * 18)
		draw_arc(center, 12 + progress * 23, 0, TAU, 28, Color(color, color.a * 0.76), 2.2 * (1.0 - progress) + 0.7, true)
		draw_line(center - Vector2(5, 0), center + Vector2(5, 0), color, 2, true)
		draw_line(center - Vector2(0, 5), center + Vector2(0, 5), color, 2, true)
		for i in 3:
			var mote := at + Vector2((i - 1) * 17.0, -10.0 - progress * (38.0 + i % 2 * 12.0))
			draw_circle(mote, 2.2 * (1.0 - progress * 0.45), Color(color, color.a * (1.0 - progress * 0.35)))
	elif kind == "status":
		var radius := 13.0 + progress * 21.0
		draw_arc(at, radius, 0.0, TAU, 28, Color(color, color.a * 0.62), 2.0 * (1.0 - progress) + 0.7, true)
		for i in 4:
			var ray := Vector2.from_angle(i * TAU / 4.0 + PI * 0.25)
			draw_line(at + ray * (radius * 0.52), at + ray * (radius + 7.0), Color(color, color.a * 0.68), 1.6, true)
	var font := get_theme_default_font()
	var pop_scale := (1.32 - 0.32 * minf(progress * 4.0, 1.0)) * (1.0 - 0.12 * progress)
	var font_size := int(round((21 if kind in ["shield", "status"] else 36) * pop_scale))
	var text_value := str(effect.text)
	var text_size := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var bounce_y := - (36.0 * sin(minf(progress * 1.8, 1.0) * PI * 0.5) + progress * 28.0)
	var icon: Texture2D = _float_textures.get(kind)
	var icon_size := Vector2(22, 22) if kind == "hit" else Vector2(18, 18)
	var total_width := text_size.x + (icon_size.x + 6.0 if icon != null else 0.0)
	var baseline := at + Vector2(-total_width * 0.5, bounce_y)
	if icon != null:
		var icon_rect := Rect2(baseline.x, baseline.y - icon_size.y * 0.82, icon_size.x, icon_size.y)
		draw_texture_rect(icon, icon_rect, false, Color(1, 1, 1, color.a))
		baseline.x += icon_size.x + 6.0
	draw_string_outline(font, baseline, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0.04, 0.05, 0.04, color.a))
	draw_string(font, baseline, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _death(effect: Dictionary, progress: float, color: Color) -> void:
	var at: Vector2 = effect.at
	for i in 16:
		var ray := Vector2.from_angle(i * TAU / 16.0 + 0.3)
		var point := at + ray * (12 + progress * (30 + i % 3 * 10)) + Vector2(0, -progress * 36)
		draw_circle(point, maxf(0.7, 2.4 * (1.0 - progress)), color)
