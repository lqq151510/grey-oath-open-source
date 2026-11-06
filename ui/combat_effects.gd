extends Control
## 战斗瞬时反馈层：接收全局坐标，只做绘制，不接管输入，也不改动任何规则状态。
##
## 事件→特效的分工：
## - attack / area / impact / death：无文字的舞台动画（弹道、法阵、冲击波、灰烬）。
## - hit / shield / guard / heal / buff / debuff / resource / orb / potion / sigil / status：
##   带徽记与漂浮文字的分类反馈。
## 所有条目都存在 effects 里，靠 _process 推进 age，clear_effects() 由界面刷新调用。

const GOLD := Color("c7a66a")
const BONE := Color("f5e8ce")
const DAMAGE := Color("ef9a85")
const SHIELD := Color("a7ced1")
const POISON := Color("a4c886")
const HEAL := Color("91d49a")
const FROST := Color("8dd3e2")
const ARCANE := Color("b59acb")
const EMBER := Color("e8a15c")
const SUN := Color("f2d08a")
const INK := Color("111511")

const FLOAT_ICONS := {
	"hit": "res://assets/art/ui/playfeel/float_dmg.png",
	"shield": "res://assets/art/ui/playfeel/float_block.png",
	"guard": "res://assets/art/ui/playfeel/float_block.png",
	"heal": "res://assets/art/ui/playfeel/float_heal.png",
	"buff": "res://assets/art/ui/playfeel/float_echo.png",
	"status": "res://assets/art/ui/playfeel/float_echo.png",
	"resource": "res://assets/art/ui/playfeel/float_echo.png",
	"orb": "res://assets/art/ui/playfeel/float_echo.png",
	"debuff": "res://assets/art/ui/playfeel/float_poison.png",
	"poison": "res://assets/art/ui/playfeel/float_poison.png",
	"potion": "res://assets/art/ui/playfeel/float_ember.png",
	"sigil": "res://assets/art/ui/playfeel/float_ember.png",
	"impact": "res://assets/art/ui/playfeel/float_ember.png",
}

const KEY_TONES := {
	"weak": FROST, "vulnerable": Color("e56f5c"), "poison": POISON, "doom": ARCANE,
	"frail": Color("c59a86"), "cinder": EMBER, "sunder": Color("d38b72"),
	"strength": SUN, "dexterity": SUN, "thorns": Color("d9b36b"), "regen": HEAL,
	"intangible": SHIELD, "focus": FROST, "resonance": ARCANE, "osty": ARCANE,
	"next_energy": FROST, "tactical_points": SUN, "energy": FROST, "draw": GOLD,
	"lightning": Color("9fc8f2"), "frost": FROST, "dark": ARCANE,
	"plasma": EMBER, "glass": BONE, "soul_summon": ARCANE,
}

const DEBUFF_KEYS := ["weak", "vulnerable", "poison", "doom", "frail", "cinder", "sunder", "curse"]
const RESOURCE_KEYS := ["next_energy", "tactical_points", "energy", "draw", "souls", "marks", "discard_energy", "discard_draw"]
const ORB_KEYS := ["lightning", "frost", "dark", "plasma", "glass"]

var effects: Array[Dictionary] = []
var _float_textures: Dictionary = {}

## 由 main.gd 同步：减弱动态时去掉全屏染色、减少粒子与光柱层数。
var reduced_motion := false
## 跟随战斗速度设置，保证特效寿命与事件节奏一致。
var time_scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in FLOAT_ICONS:
		var path: String = FLOAT_ICONS[key]
		if ResourceLoader.exists(path):
			_float_textures[key] = load(path) as Texture2D


# ---------------------------------------------------------------- 分类查表

## 状态/属性 key 的视觉分类，供界面决定调用哪一类反馈。
static func category_for(key: String) -> String:
	if key in DEBUFF_KEYS:
		return "debuff"
	if key in RESOURCE_KEYS:
		return "resource"
	if key in ORB_KEYS:
		return "orb"
	if not key.is_empty() and KEY_TONES.has(key):
		return "buff"
	return "neutral"


static func tone_for(key: String) -> Color:
	return KEY_TONES.get(key, GOLD)


## 药剂按主要效果取色，避免所有瓶子都是同一个金色调。
static func potion_tone(kind: String) -> Color:
	match kind:
		"damage": return Color("e88a63")
		"defense": return SHIELD
		"recovery": return HEAL
		"hex": return ARCANE
		"buff": return SUN
		"utility": return FROST
		_: return GOLD


## 卡牌类型对应的施法法阵色。
static func school_tone(school: String) -> Color:
	match school:
		"attack": return Color("dd8a70")
		"power": return GOLD
		"skill": return Color("8fb7a5")
		_: return GOLD


# ---------------------------------------------------------------- 入队 API

func _local(point: Vector2) -> Vector2:
	return point - global_position


func _base(kind: String, at: Vector2, color: Color, duration: float, text: String = "") -> Dictionary:
	return {"type": kind, "at": _local(at), "color": color, "text": text,
		"age": 0.0, "duration": duration}


func _push(entry: Dictionary) -> void:
	effects.append(entry)
	queue_redraw()


## 攻击弹道：power 由实际伤害换算，控制命中弧光与碎屑规模。
func play_attack(from: Vector2, to: Vector2, style: String = "slash", tint: Color = GOLD, power: float = 1.0) -> void:
	var entry := _base("attack", Vector2.ZERO, tint, 0.42)
	entry["from"] = _local(from)
	entry["to"] = _local(to)
	entry["style"] = style
	entry["power"] = clampf(power, 0.5, 2.0)
	_push(entry)


## 群体攻击：把每个落点连成一个展开的法阵。
func play_area(points: Array, tint: Color = GOLD) -> void:
	if points.is_empty():
		return
	var local_points: Array = []
	for point in points:
		local_points.append(_local(point))
	var entry := _base("area", Vector2.ZERO, tint, 0.75)
	entry["points"] = local_points
	_push(entry)


## 受击：伤害数字 + 冲击爆发 + 格挡提示，一次调用把三条反馈对齐到同一时刻。
func play_hit(at: Vector2, damage: int, blocked: int = 0, poison: bool = false, heavy: bool = false) -> void:
	if damage > 0:
		var color := POISON if poison else DAMAGE
		var entry := _base("hit", at, color, 0.76, "-%d" % damage)
		entry["wash"] = not reduced_motion
		entry["heavy"] = heavy
		_push(entry)
		var burst := _base("impact", at, Color(1.0, 0.94, 0.82) if not poison else POISON, 0.34)
		burst["power"] = clampf(0.72 + float(damage) / 22.0, 0.7, 2.1)
		burst["heavy"] = heavy
		_push(burst)
	if blocked > 0:
		var offset := Vector2(0, -26 if damage > 0 else 0)
		var shield := _base("shield", at + offset, SHIELD, 0.78, "格挡 %d" % blocked)
		shield["shatter"] = damage <= 0
		_push(shield)


## 回复：地面涟漪 + 上升光柱 + 治疗十字，强度随治疗量变化。
func play_heal(at: Vector2, amount: int, tint: Color = HEAL) -> void:
	if amount <= 0:
		return
	var entry := _base("heal", at, tint, 0.88, "+%d" % amount)
	entry["power"] = clampf(0.7 + float(amount) / 20.0, 0.7, 1.8)
	_push(entry)


## 防御：六边形盾面 + 罩形护环，用于「获得格挡」事件。
func play_guard(at: Vector2, amount: int, tint: Color = SHIELD, label: String = "") -> void:
	var entry := _base("guard", at, tint, 0.80, label if not label.is_empty() else "格挡 +%d" % amount)
	entry["power"] = clampf(0.8 + float(maxi(amount, 0)) / 24.0, 0.8, 1.8)
	_push(entry)


## 属性加成：key 有分类时自动升级为专属反馈，否则保留通用光环。
func play_status(at: Vector2, text_value: String, tint: Color = GOLD, key: String = "") -> void:
	match category_for(key):
		"buff": play_buff(at, text_value, tint, key)
		"debuff": play_debuff(at, text_value, tint, key)
		"resource": play_resource(at, text_value, tint)
		"orb": play_orb(at, text_value, tint)
		_: _push(_base("status", at, tint, 0.78, text_value))


func play_buff(at: Vector2, text_value: String, tint: Color = GOLD, key: String = "") -> void:
	var entry := _base("buff", at, tint, 0.86, text_value)
	entry["key"] = key
	_push(entry)


func play_debuff(at: Vector2, text_value: String, tint: Color = DAMAGE, key: String = "") -> void:
	var entry := _base("debuff", at, tint, 0.86, text_value)
	entry["key"] = key
	_push(entry)


func play_resource(at: Vector2, text_value: String, tint: Color = FROST) -> void:
	_push(_base("resource", at, tint, 0.82, text_value))


func play_orb(at: Vector2, text_value: String, tint: Color = FROST) -> void:
	_push(_base("orb", at, tint, 0.86, text_value))


## 药剂：瓶身 + 喷涌液滴 + 扩散涟漪，kind 决定色调。
func play_potion(at: Vector2, label: String, tint: Color = GOLD, kind: String = "utility") -> void:
	var entry := _base("potion", at, tint, 0.92, label)
	entry["kind"] = kind
	_push(entry)


## 施法法阵：出牌 / 首领阶段变换时铺在脚下。
func play_skill(at: Vector2, label: String, tint: Color = GOLD, school: String = "skill") -> void:
	var entry := _base("sigil", at, tint, 0.90, label)
	entry["school"] = school
	_push(entry)


func play_death(at: Vector2) -> void:
	_push(_base("death", at, GOLD, 0.68))


func clear_effects() -> void:
	effects.clear()
	queue_redraw()


# ---------------------------------------------------------------- 生命周期

func _process(delta: float) -> void:
	if effects.is_empty():
		return
	var step := delta * maxf(0.25, time_scale)
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["age"] = float(effects[i]["age"]) + step
		if float(effects[i]["age"]) >= float(effects[i]["duration"]):
			effects.remove_at(i)
	queue_redraw()


func _count(base: int) -> int:
	return maxi(2, int(round(float(base) * (0.45 if reduced_motion else 1.0))))


func _draw() -> void:
	for effect in effects:
		var progress := clampf(float(effect["age"]) / float(effect["duration"]), 0.0, 1.0)
		var color: Color = effect["color"]
		color.a = 1.0 - pow(progress, 1.45)
		match str(effect["type"]):
			"attack": _draw_attack(effect, progress, color)
			"area": _draw_area(effect, progress, color)
			"impact": _draw_impact(effect, progress, color)
			"death": _draw_death(effect, progress, color)
			_: _draw_carded(effect, progress, color)


# ---------------------------------------------------------------- 绘制原语

func _ring(center: Vector2, radius: float, color: Color, width: float, segments: int = 40) -> void:
	if radius > 0.5:
		draw_arc(center, radius, 0, TAU, segments, color, maxf(0.8, width), true)


func _polygon(center: Vector2, radius: float, sides: int, rotation: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in sides:
		var angle := TAU * float(index) / float(sides) + rotation
		points.append(center + Vector2.from_angle(angle) * radius)
	points.append(points[0])
	return points


func _diamond(center: Vector2, radius: float, fill: Color, outline: Color, width: float = 1.0) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0),
		center + Vector2(0, -radius),
	])
	if fill.a > 0.0:
		draw_colored_polygon(points, fill)
	if outline.a > 0.0:
		draw_polyline(points, outline, width, true)


func _ease_out(progress: float) -> float:
	return 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 2.4)


# ---------------------------------------------------------------- 攻击弹道

func _draw_attack(effect: Dictionary, progress: float, color: Color) -> void:
	var origin: Vector2 = effect["from"]
	var target: Vector2 = effect["to"]
	var direction := (target - origin).normalized()
	var style := str(effect.get("style", "slash"))
	var power := float(effect.get("power", 1.0))
	# 1) 起手蓄力：按流派铺出不同的蓄力纹样，先交代「谁用什么出手」。
	if progress < 0.24:
		var charge := 1.0 - progress / 0.24
		draw_circle(origin, 5.0 + 9.0 * (1.0 - charge), Color(color, color.a * 0.20 * charge))
		draw_circle(origin, 2.4, Color(BONE, color.a * 0.75 * charge))
		if style in ["magic", "arcane", "spell", "power"]:
			_ring(origin, 13.0 + 7.0 * charge, Color(color, color.a * 0.55 * charge), 1.4, 24)
			for i in 4:
				var ray := Vector2.from_angle(i * TAU / 4.0 + progress * 3.0)
				draw_line(origin + ray * 11.0, origin + ray * 19.0, Color(color, color.a * 0.45 * charge), 1.2, true)
		elif style == "poison":
			for i in 3:
				var bubble := origin + Vector2((i - 1) * 8.0, -6.0 - 5.0 * sin(progress * 12.0 + float(i)))
				draw_circle(bubble, 2.0 + 2.0 * charge, Color(color, color.a * 0.35 * charge))
		elif style in ["projectile", "lightning"]:
			_diamond(origin, 7.0 * charge, Color(color, color.a * 0.18 * charge), Color(BONE, color.a * 0.6 * charge), 1.2)
	# 2) 飞行拖尾：三层光带 + 流派专属头部。
	var head := origin.lerp(target, minf(progress * 3.2, 1.0))
	if progress < 0.42:
		var span := maxf(origin.distance_to(head), 1.0)
		var tail := origin.lerp(head, maxf(0.0, 1.0 - 96.0 / span))
		draw_line(tail, head, Color(color, color.a * 0.14), 26.0 * power, true)
		draw_line(tail, head, Color(color, color.a * 0.50), 10.0, true)
		draw_line(tail, head, Color(BONE, color.a * 0.95), 3.0, true)
		draw_circle(head, 4.5, Color(BONE, color.a))
		for index in _count(4):
			var t := fmod(progress * 4.2 + float(index) * 0.33, 1.0)
			draw_circle(tail.lerp(head, t), 1.5, Color(color, color.a * 0.28 * (1.0 - t)))
		if style in ["magic", "arcane", "spell", "power", "poison", "projectile"]:
			_ring(head, 13.0, Color(color, color.a * 0.7), 2.0, 20)
		match style:
			"projectile":
				_diamond(head, 8.0, Color(color, color.a * 0.55), Color(BONE, color.a * 0.9), 1.4)
			"poison":
				for index in 3:
					var drop := head + Vector2((index - 1) * 6.0, 5.0 + 4.0 * sin(progress * 14.0 + float(index)))
					draw_circle(drop, 2.6, Color(color, color.a * 0.55))
			"lightning":
				var bolt := PackedVector2Array()
				for index in 7:
					var t := float(index) / 6.0
					var jitter := sin(float(index) * 8.7 + progress * 20.0) * 7.0 * (1.0 - t * 0.4)
					bolt.append(origin.lerp(head, t) + Vector2(-direction.y, direction.x) * jitter)
				draw_polyline(bolt, Color(BONE, color.a * 0.85), 1.8, true)
			"magic", "arcane", "spell", "power":
				for index in 3:
					var angle := progress * 7.0 + index * TAU / 3.0
					_diamond(head + Vector2.from_angle(angle) * 13.0, 2.4, Color(color, color.a * 0.5), Color(color, 0.0), 1.0)
	# 3) 命中：月牙弧光 + 冲击波是所有攻击共有的骨架，再叠流派专属的一层。
	if progress > 0.14:
		var hit := clampf((progress - 0.14) / 0.86, 0.0, 1.0)
		var reach := (18.0 + 66.0 * pow(hit, 0.45)) * (0.85 + 0.15 * power)
		var base_angle := (origin - target).angle()
		for index in 3:
			var radius := reach * (1.0 + 0.17 * float(index))
			var width := (7.5 - 1.9 * float(index)) * (1.0 - 0.55 * hit)
			var span := deg_to_rad(96.0 - 10.0 * float(index))
			draw_arc(target, radius, base_angle - span * 0.5, base_angle + span * 0.5, 26,
				Color(color, color.a * (0.52 - 0.12 * float(index))), maxf(1.0, width), true)
		draw_arc(target, reach * 0.86, base_angle - deg_to_rad(46.0), base_angle + deg_to_rad(46.0), 22,
			Color(BONE, color.a * 0.9), maxf(1.0, 4.0 * (1.0 - hit)), true)
		var ring := (10.0 + 56.0 * hit) * (0.9 + 0.12 * power)
		_ring(target, ring, Color(BONE, color.a * 0.34 * (1.0 - hit)), 2.0, 40)
		_ring(target, ring * 0.72, Color(color, color.a * 0.22 * (1.0 - hit)), 1.0, 32)
		for index in _count(9):
			var spread_angle := (float(index) - 4.0) * 0.20
			var ray := direction.rotated(spread_angle)
			var length := 10.0 + 46.0 * pow(hit, 0.7) * (1.0 - absf(float(index) - 4.0) * 0.08)
			draw_line(target + ray * ring * 0.68, target + ray * (ring * 0.68 + length),
				Color(color, color.a * (0.78 - absf(float(index) - 4.0) * 0.13)), 2.0, true)
		for index in _count(5):
			var angle := TAU * float(index) / 5.0 + 0.5
			var distance := ring * (0.55 + 0.20 * float(index % 2))
			draw_circle(target + Vector2.from_angle(angle) * distance, 2.0 + 3.6 * hit,
				Color(0.55, 0.48, 0.40, color.a * 0.09 * (1.0 - hit)))
		match style:
			"magic", "arcane", "spell", "power":
				var rune := 16.0 + 42.0 * _ease_out(hit)
				_ring(target, rune, Color(color, color.a * 0.7 * (1.0 - hit)), 2.0, 48)
				_ring(target, rune * 0.78, Color(BONE, color.a * 0.45 * (1.0 - hit)), 1.0, 48)
				for index in 8:
					var ray := Vector2.from_angle(index * TAU / 8.0 + hit * 0.9)
					draw_line(target + ray * rune * 0.86, target + ray * rune * 1.08,
						Color(color, color.a * 0.6 * (1.0 - hit)), 1.4, true)
			"poison":
				for index in _count(7):
					var angle := TAU * float(index) / 7.0 + hit * 1.4
					var mist := target + Vector2.from_angle(angle) * (14.0 + 30.0 * hit) + Vector2(0, -hit * 14.0)
					draw_circle(mist, 7.0 + 8.0 * hit, Color(color, color.a * 0.10 * (1.0 - hit)))
			"heavy", "slam":
				for index in 4:
					var crack := Vector2.from_angle(0.35 + float(index) * 0.45)
					var start := target + crack * 8.0
					var bend := target + crack * 34.0 + Vector2(0, 12.0)
					var finish := target + crack * 62.0 + Vector2(0, 24.0)
					draw_polyline(PackedVector2Array([start, bend, finish]), Color(INK, color.a * 0.5 * (1.0 - hit)), 2.0, true)
				_ring(target, ring * 1.18, Color(BONE, color.a * 0.30 * (1.0 - hit)), 3.0, 48)
			"projectile":
				for index in _count(6):
					var angle := TAU * float(index) / 6.0 + 0.4
					var chip := target + Vector2.from_angle(angle) * (12.0 + 34.0 * hit)
					draw_circle(chip, maxf(0.8, 2.6 * (1.0 - hit)), Color(BONE, color.a * 0.6 * (1.0 - hit)))


func _draw_area(effect: Dictionary, progress: float, color: Color) -> void:
	var points: Array = effect["points"]
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= float(points.size())
	var radius := 70.0
	for point in points:
		radius = maxf(radius, center.distance_to(point) + 75.0)
	var expansion := _ease_out(minf(progress * 2.2, 1.0))
	_ring(center, radius * expansion, Color(color, color.a * 0.8), 7.0, 64)
	_ring(center, radius * expansion * 0.82, Color(BONE, color.a * 0.65), 2.5, 64)
	_ring(center, radius * expansion * 0.55, Color(color, color.a * 0.30 * (1.0 - progress)), 1.2, 48)
	_diamond(center, 10.0 + 8.0 * expansion, Color(color, color.a * 0.18 * (1.0 - progress)),
		Color(BONE, color.a * 0.55 * (1.0 - progress)), 1.4)
	for point in points:
		draw_line(center, point, Color(color, color.a * 0.6 * (1.0 - progress * 0.4)), 4.0, true)
		var local := 24.0 + expansion * 40.0
		_ring(point, local, Color(BONE, color.a * (1.0 - progress * 0.6)), 3.0, 32)
		_ring(point, local * 0.68, Color(color, color.a * 0.5 * (1.0 - progress)), 1.2, 24)
		for index in 4:
			var ray := Vector2.from_angle(index * TAU / 4.0 + PI * 0.25 + progress)
			draw_line(point + ray * local * 0.8, point + ray * local * 1.12,
				Color(BONE, color.a * 0.6 * (1.0 - progress)), 1.4, true)


# ---------------------------------------------------------------- 打击爆发

func _draw_impact(effect: Dictionary, progress: float, color: Color) -> void:
	var at: Vector2 = effect["at"]
	var power := float(effect.get("power", 1.0))
	var heavy := bool(effect.get("heavy", false))
	var spread := _ease_out(progress)
	var peak := 1.0 - progress
	# 双层冲击环：快环先到，慢环收尾，形成「撞击→余波」两段。
	_ring(at, (9.0 + 42.0 * spread) * power, Color(color, color.a * 0.85 * peak), 3.4 * peak + 0.7, 40)
	_ring(at, (6.0 + 26.0 * spread) * power, Color(BONE, color.a * 0.55 * peak), 1.4, 32)
	# 四道十字锐光，长轴沿水平方向，短轴沿垂直方向。
	for index in 4:
		var ray := Vector2.from_angle(index * TAU / 4.0 + PI * 0.25)
		var reach := (18.0 + 42.0 * spread) * power
		draw_line(at - ray * reach * 0.55, at + ray * reach,
			Color(BONE, color.a * 0.75 * peak), 2.6 * peak + 0.6, true)
	# 径向速度线 + 受重力下坠的碎屑。
	for index in _count(12):
		var angle := TAU * float(index) / 12.0 + 0.15
		var ray := Vector2.from_angle(angle)
		var inner := (12.0 + 20.0 * spread) * power
		draw_line(at + ray * inner, at + ray * (inner + 10.0 + 22.0 * spread) * power,
			Color(color, color.a * 0.6 * peak), 1.6, true)
	for index in _count(8):
		var angle := TAU * float(index) / 8.0 + 0.6
		var ray := Vector2.from_angle(angle)
		var travel := (10.0 + 46.0 * spread) * power
		var chip := at + ray * travel + Vector2(0, progress * progress * 22.0)
		draw_circle(chip, maxf(0.7, 2.2 * peak), Color(color, color.a * 0.7 * peak))
	if progress < 0.22:
		draw_circle(at, (10.0 - progress * 24.0) * power, Color(BONE, color.a * 0.7 * (1.0 - progress / 0.22)))
	if heavy:
		_ring(at, (26.0 + 74.0 * spread) * power, Color(EMBER, color.a * 0.42 * peak), 2.2, 48)
		for index in 4:
			var ray := Vector2.from_angle(index * TAU / 4.0)
			draw_line(at + ray * 30.0, at + ray * (56.0 + 24.0 * spread),
				Color(EMBER, color.a * 0.5 * peak), 1.6, true)


# ---------------------------------------------------------------- 带文字的分类反馈

func _draw_carded(effect: Dictionary, progress: float, color: Color) -> void:
	var at: Vector2 = effect["at"]
	var kind := str(effect["type"])
	match kind:
		"hit": _emblem_hit(effect, progress, color, at)
		"shield": _emblem_shield(effect, progress, color, at)
		"guard": _emblem_guard(effect, progress, color, at)
		"heal": _emblem_heal(effect, progress, color, at)
		"buff": _emblem_buff(effect, progress, color, at)
		"debuff": _emblem_debuff(effect, progress, color, at)
		"resource": _emblem_resource(effect, progress, color, at)
		"orb": _emblem_orb(effect, progress, color, at)
		"potion": _emblem_potion(effect, progress, color, at)
		"sigil": _emblem_sigil(effect, progress, color, at)
		_: _emblem_status(effect, progress, color, at)
	var base_size := 21.0
	var drift := -1.0
	var lift := 30.0
	match kind:
		"hit":
			base_size = 36.0
			lift = 26.0
		"heal":
			base_size = 32.0
			lift = 34.0
		"guard", "shield":
			lift = 32.0
		"buff", "resource", "orb":
			lift = 36.0
		"debuff":
			drift = 0.55
			lift = 6.0
		"potion", "sigil":
			lift = 38.0
		_:
			lift = 28.0
	_floating_text(effect, progress, color, at, base_size, kind, drift, lift)


func _emblem_hit(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	if bool(effect.get("wash", false)) and progress < 0.28:
		var strength := 0.08 if not bool(effect.get("heavy", false)) else 0.13
		draw_rect(Rect2(Vector2.ZERO, size), Color(color.r, color.g, color.b, strength * (1.0 - progress / 0.28)))
	if progress < 0.55:
		_ring(at, 12.0 + progress * 42.0, Color(color, color.a * 0.9), 3.2 * (1.0 - progress) + 0.8, 32)
		for i in _count(8):
			var ray := Vector2.from_angle(i * TAU / 8.0 + 0.3)
			draw_line(at + ray * (8.0 + progress * 28.0), at + ray * (20.0 + progress * 72.0), color, 2.4, true)


func _emblem_shield(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var radius := 26.0 + progress * 16.0
	draw_arc(at, radius, PI * 0.6, PI * 1.4, 24, color, 4.0 * (1.0 - progress) + 1.0, true)
	draw_arc(at, radius + 9.0, PI * 0.65, PI * 1.35, 24, Color(color, color.a * 0.4), 1.2, true)
	draw_polyline(_polygon(at, 14.0 + progress * 5.0, 6, PI / 6.0),
		Color(color, color.a * 0.75 * (1.0 - progress)), 1.6, true)
	if bool(effect.get("shatter", false)):
		for i in _count(5):
			var ray := Vector2.from_angle(PI * 0.7 + float(i) * 0.3)
			draw_line(at + ray * radius * 0.6, at + ray * (radius + 12.0 + progress * 12.0),
				Color(BONE, color.a * 0.55 * (1.0 - progress)), 1.2, true)


func _emblem_guard(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var power := float(effect.get("power", 1.0))
	var swell := _ease_out(minf(progress * 2.4, 1.0))
	var radius := (20.0 + 14.0 * swell) * power
	var fade := 1.0 - progress
	# 六边形盾面：外轮廓 + 内衬 + 中央竖脊。
	draw_colored_polygon(_polygon(at, radius, 6, PI / 6.0), Color(color, color.a * 0.10 * fade))
	draw_polyline(_polygon(at, radius, 6, PI / 6.0), Color(color, color.a * 0.9 * fade), 2.4, true)
	draw_polyline(_polygon(at, radius * 0.68, 6, PI / 6.0), Color(BONE, color.a * 0.45 * fade), 1.0, true)
	draw_line(at + Vector2(0, -radius * 0.58), at + Vector2(0, radius * 0.62), Color(BONE, color.a * 0.6 * fade), 1.4, true)
	draw_line(at + Vector2(-radius * 0.46, -radius * 0.12), at + Vector2(radius * 0.46, -radius * 0.12), Color(color, color.a * 0.7 * fade), 1.2, true)
	# 罩形护环由下往上合拢，外加四角刻线。
	draw_arc(at, radius * 1.28, PI * 0.08, PI * 0.92, 28, Color(color, color.a * 0.55 * fade), 2.0, true)
	draw_arc(at, radius * 1.48, PI * 1.08, PI * 1.92, 28, Color(BONE, color.a * 0.35 * fade), 1.2, true)
	for index in 4:
		var corner := Vector2(-1.0 if index % 2 == 0 else 1.0, -1.0 if index < 2 else 1.0)
		var start := at + corner * radius * 1.55
		draw_line(start, start - corner * 8.0, Color(BONE, color.a * 0.5 * fade), 1.4, true)
	if not reduced_motion:
		for index in 3:
			var t := fmod(progress * 1.4 + float(index) * 0.33, 1.0)
			var mote := at + Vector2((index - 1) * radius * 0.7, radius * 0.8 - t * radius * 1.8)
			draw_circle(mote, 1.8, Color(color, color.a * 0.5 * (1.0 - t) * fade))


func _emblem_heal(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var power := float(effect.get("power", 1.0))
	var fade := 1.0 - progress
	var center := at + Vector2(0, -20.0 - progress * 18.0)
	# 地面涟漪：两道扁椭圆向外扩。
	for index in 2:
		var spread := (0.4 + progress * (0.9 + float(index) * 0.5)) * power
		draw_arc(at + Vector2(0, 12.0), 16.0 * spread, 0, TAU, 28,
			Color(color, color.a * 0.28 * fade), 1.5, true)
	# 上升光柱：分层条带，减弱动态时减半。
	var layers := _count(9)
	for index in layers:
		var t := float(index) / float(layers)
		var band := Rect2(at.x - (16.0 - t * 7.0) * power, at.y + 14.0 - t * 74.0 * power,
			(32.0 - t * 14.0) * power, 10.0)
		draw_rect(band, Color(color, color.a * 0.05 * (1.0 - t) * fade))
	_ring(center, 12.0 + progress * 23.0, Color(color, color.a * 0.76 * fade), 2.2 * fade + 0.7, 28)
	draw_line(center - Vector2(6, 0), center + Vector2(6, 0), Color(BONE, color.a * fade), 2.2, true)
	draw_line(center - Vector2(0, 6), center + Vector2(0, 6), Color(BONE, color.a * fade), 2.2, true)
	for index in _count(5):
		var mote := at + Vector2((index - 2) * 14.0, -8.0 - progress * (38.0 + index % 2 * 16.0))
		draw_circle(mote, 2.2 * fade, Color(color, color.a * (1.0 - progress * 0.35) * fade))


func _emblem_buff(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var fade := 1.0 - progress
	var radius := 15.0 + progress * 22.0
	_ring(at, radius, Color(color, color.a * 0.62 * fade), 2.0 * fade + 0.7, 28)
	_ring(at, radius * 0.72, Color(BONE, color.a * 0.28 * fade), 1.0, 24)
	# 上升箭头：三角头 + 竖柄 + 底部基准线。
	var head := at + Vector2(0, -9.0 - progress * 8.0)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(0, -9.0), head + Vector2(8.0, 1.0), head + Vector2(-8.0, 1.0),
	]), Color(color, color.a * 0.85 * fade))
	draw_line(head + Vector2(0, 1.0), head + Vector2(0, 13.0), Color(BONE, color.a * 0.8 * fade), 2.2, true)
	draw_line(at + Vector2(-12.0, 16.0), at + Vector2(12.0, 16.0), Color(color, color.a * 0.55 * fade), 1.4, true)
	for index in _count(4):
		var t := fmod(progress * 1.2 + float(index) * 0.25, 1.0)
		var mote := at + Vector2((index - 1.5) * 11.0, 14.0 - t * 40.0)
		draw_circle(mote, 1.8 * (1.0 - t), Color(color, color.a * 0.7 * (1.0 - t) * fade))


func _emblem_debuff(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var fade := 1.0 - progress
	var radius := 14.0 + progress * 20.0
	_ring(at, radius, Color(color, color.a * 0.6 * fade), 1.8 * fade + 0.6, 28)
	# 下降箭头 + 两道裂纹，颜色压暗以区别于增益。
	var head := at + Vector2(0, 9.0 + progress * 8.0)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(0, 9.0), head + Vector2(8.0, -1.0), head + Vector2(-8.0, -1.0),
	]), Color(color, color.a * 0.85 * fade))
	draw_line(head + Vector2(0, -1.0), head + Vector2(0, -13.0), Color(color, color.a * 0.8 * fade), 2.2, true)
	for index in 2:
		var sign := -1.0 if index == 0 else 1.0
		var crack := PackedVector2Array([
			at + Vector2(sign * 10.0, -14.0), at + Vector2(sign * 16.0, -4.0),
			at + Vector2(sign * 13.0, 4.0), at + Vector2(sign * 20.0, 16.0),
		])
		draw_polyline(crack, Color(INK, color.a * 0.55 * fade), 1.6, true)
	for index in _count(4):
		var t := fmod(progress * 1.1 + float(index) * 0.27, 1.0)
		var mote := at + Vector2((index - 1.5) * 10.0, -12.0 + t * 32.0)
		draw_circle(mote, 1.6 * (1.0 - t), Color(color, color.a * 0.55 * (1.0 - t) * fade))


func _emblem_resource(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var fade := 1.0 - progress
	var radius := 14.0 + progress * 20.0
	_ring(at, radius, Color(color, color.a * 0.62 * fade), 2.0 * fade + 0.7, 28)
	for index in 8:
		var ray := Vector2.from_angle(index * TAU / 8.0 + progress * 0.8)
		draw_line(at + ray * radius * 0.85, at + ray * radius * 1.12,
			Color(BONE, color.a * 0.55 * fade), 1.3, true)
	# 闪电折线穿过菱形，读作「能量 / 资源」而不是普通增益。
	_diamond(at, 9.0, Color(color, color.a * 0.16 * fade), Color(color, color.a * 0.7 * fade), 1.4)
	draw_polyline(PackedVector2Array([
		at + Vector2(2.0, -13.0), at + Vector2(-3.0, -2.0), at + Vector2(2.0, -1.0), at + Vector2(-2.0, 13.0),
	]), Color(BONE, color.a * 0.9 * fade), 1.8, true)


func _emblem_orb(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var fade := 1.0 - progress
	var orbit := 17.0 + progress * 8.0
	_ring(at, orbit + 8.0, Color(color, color.a * 0.35 * fade), 1.2, 32)
	draw_circle(at, 9.0 + 2.0 * sin(progress * 9.0), Color(color, color.a * 0.28 * fade))
	draw_circle(at, 5.0, Color(BONE, color.a * 0.65 * fade))
	for index in 3:
		var angle := progress * 5.0 + index * TAU / 3.0
		var satellite := at + Vector2.from_angle(angle) * orbit
		draw_circle(satellite, 2.4, Color(color, color.a * 0.85 * fade))
		draw_line(at + Vector2.from_angle(angle) * 9.0, satellite, Color(color, color.a * 0.25 * fade), 1.0, true)


func _emblem_potion(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var fade := 1.0 - progress
	var rise := _ease_out(minf(progress * 1.8, 1.0))
	# 地面涟漪：药液落点向外扩两圈。
	_ring(at + Vector2(0, 14.0), 14.0 + 42.0 * rise, Color(color, color.a * 0.45 * fade), 2.0, 32)
	_ring(at + Vector2(0, 14.0), 8.0 + 26.0 * rise, Color(BONE, color.a * 0.28 * fade), 1.2, 24)
	# 瓶身：圆底 + 收颈 + 瓶塞，瓶口向上喷出液滴。
	var bottle := at + Vector2(0, -14.0 - rise * 10.0)
	var body := PackedVector2Array([
		bottle + Vector2(-5.0, -14.0), bottle + Vector2(5.0, -14.0),
		bottle + Vector2(5.0, -6.0), bottle + Vector2(10.0, 4.0),
		bottle + Vector2(9.0, 14.0), bottle + Vector2(-9.0, 14.0),
		bottle + Vector2(-10.0, 4.0), bottle + Vector2(-5.0, -6.0),
		bottle + Vector2(-5.0, -14.0),
	])
	draw_colored_polygon(body, Color(color, color.a * 0.18 * fade))
	draw_polyline(body, Color(BONE, color.a * 0.8 * fade), 1.8, true)
	draw_line(bottle + Vector2(-6.0, -17.0), bottle + Vector2(6.0, -17.0), Color(color, color.a * 0.85 * fade), 2.4, true)
	draw_line(bottle + Vector2(-8.0, 7.0), bottle + Vector2(-5.0, 0.0), Color(BONE, color.a * 0.45 * fade), 1.2, true)
	for index in _count(6):
		var t := fmod(progress * 1.5 + float(index) * 0.19, 1.0)
		var angle := PI * 0.2 + float(index) * 0.24
		var drop := bottle + Vector2(cos(angle) * (8.0 + 26.0 * t), -18.0 - 32.0 * t + t * t * 26.0)
		draw_circle(drop, 2.6 * (1.0 - t * 0.5), Color(color, color.a * 0.75 * (1.0 - t) * fade))
	if progress < 0.3:
		_diamond(bottle + Vector2(0, -22.0), 7.0 * (1.0 - progress / 0.3),
			Color(BONE, color.a * 0.35 * fade), Color(color, color.a * 0.7 * fade), 1.2)


func _emblem_sigil(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var fade := 1.0 - progress
	var swell := _ease_out(minf(progress * 2.0, 1.0))
	var radius := 22.0 + 26.0 * swell
	var school := str(effect.get("school", "skill"))
	# 双层法阵 + 刻度；旋转方向按卡牌类型区分。
	var spin := progress * (1.1 if school == "attack" else -0.8)
	_ring(at, radius, Color(color, color.a * 0.75 * fade), 2.2, 48)
	_ring(at, radius * 0.76, Color(BONE, color.a * 0.35 * fade), 1.0, 48)
	for index in 8:
		var ray := Vector2.from_angle(index * TAU / 8.0 + spin)
		draw_line(at + ray * radius * 0.82, at + ray * radius * 1.06,
			Color(color, color.a * 0.6 * fade), 1.4, true)
	match school:
		"attack":
			draw_polyline(_polygon(at, radius * 0.5, 3, spin - PI * 0.5), Color(BONE, color.a * 0.8 * fade), 1.8, true)
		"power":
			draw_polyline(_polygon(at, radius * 0.52, 4, spin), Color(BONE, color.a * 0.8 * fade), 1.8, true)
			draw_polyline(_polygon(at, radius * 0.34, 4, spin + PI * 0.25), Color(color, color.a * 0.7 * fade), 1.2, true)
		_:
			draw_polyline(_polygon(at, radius * 0.5, 6, spin), Color(BONE, color.a * 0.7 * fade), 1.6, true)
	_diamond(at, 6.0, Color(BONE, color.a * 0.45 * fade), Color(color, color.a * 0.8 * fade), 1.2)
	# 中心向上的收敛光束。
	if not reduced_motion:
		for index in _count(4):
			var offset := (float(index) - 1.5) * 7.0
			draw_line(at + Vector2(offset, -8.0), at + Vector2(offset * 0.3, -34.0 - swell * 18.0),
				Color(color, color.a * 0.22 * fade), 1.2, true)


func _emblem_status(effect: Dictionary, progress: float, color: Color, at: Vector2) -> void:
	var radius := 13.0 + progress * 21.0
	_ring(at, radius, Color(color, color.a * 0.62), 2.0 * (1.0 - progress) + 0.7, 28)
	for i in 4:
		var ray := Vector2.from_angle(i * TAU / 4.0 + PI * 0.25)
		draw_line(at + ray * (radius * 0.52), at + ray * (radius + 7.0), Color(color, color.a * 0.68), 1.6, true)
	_diamond(at, 4.0, Color(color, color.a * 0.3), Color(BONE, color.a * 0.5), 1.0)


func _floating_text(effect: Dictionary, progress: float, color: Color, at: Vector2,
		base_size: float, icon_key: String, drift: float, lift: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var pop_scale := (1.32 - 0.32 * minf(progress * 4.0, 1.0)) * (1.0 - 0.12 * progress)
	var font_size := int(round(base_size * pop_scale))
	var text_value := str(effect.get("text", ""))
	if text_value.is_empty():
		return
	var text_size := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# 文字从角色头顶上方起步，徽记留在角色身上，两者不再互相压住。
	var bounce_y := drift * (lift + 36.0 * sin(minf(progress * 1.8, 1.0) * PI * 0.5) + progress * 28.0)
	var icon: Texture2D = _float_textures.get(icon_key)
	var icon_size := Vector2(22, 22) if icon_key == "hit" else Vector2(18, 18)
	var total_width := text_size.x + (icon_size.x + 6.0 if icon != null else 0.0)
	var baseline := at + Vector2(-total_width * 0.5, bounce_y)
	if icon != null:
		var icon_rect := Rect2(baseline.x, baseline.y - icon_size.y * 0.82, icon_size.x, icon_size.y)
		draw_texture_rect(icon, icon_rect, false, Color(1, 1, 1, color.a))
		baseline.x += icon_size.x + 6.0
	draw_string_outline(font, baseline, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5,
		Color(0.04, 0.05, 0.04, color.a))
	draw_string(font, baseline, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_death(effect: Dictionary, progress: float, color: Color) -> void:
	var at: Vector2 = effect["at"]
	_ring(at, 12.0 + progress * 46.0, Color(INK, color.a * 0.5 * (1.0 - progress)), 3.0, 32)
	for i in _count(16):
		var ray := Vector2.from_angle(i * TAU / 16.0 + 0.3)
		var point := at + ray * (12.0 + progress * (30.0 + i % 3 * 10.0)) + Vector2(0, -progress * 36.0)
		draw_circle(point, maxf(0.7, 2.4 * (1.0 - progress)), Color(color, color.a * 0.9))
	if not reduced_motion:
		for i in 4:
			var ash := at + Vector2((i - 1.5) * 13.0 + sin(progress * 6.0 + float(i)) * 6.0,
				-10.0 - progress * (40.0 + i * 8.0))
			draw_circle(ash, 1.2 * (1.0 - progress), Color(BONE, color.a * 0.4 * (1.0 - progress)))
