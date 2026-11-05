extends Control
## Offline, deterministic silhouettes. This node only reads snapshots of combatants.

const GOLD := Color("c7a66a")
const BONE := Color("e8dfcc")
const INK := Color("111511")
const RoleArt = preload("res://ui/role_art.gd")

var archetype := "undead"
var player := false
var selected := false
var dead := false
var accent := GOLD
var role_id := ""
var role_art: Texture2D
var rank := "normal"
var active_statuses: Dictionary = {}
var status_flash: Dictionary = {"weak": 0.0, "vulnerable": 0.0, "regen": 0.0}
var heal_time := 0.0
var clock := 0.0
var idle_seed := 0.0
var attack_time := 0.0
var hit_time := 0.0
var death_time := 0.0
var guard_time := 0.0
var shield_hit := false
var held := false
var animation_speed := 1.0
var reduced_motion := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(180, 144)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(entity: Dictionary, definition: Dictionary = {}, is_player: bool = false) -> void:
	player = is_player
	role_id = str(definition.get("id", entity.get("id", "warden")))
	active_statuses = entity.get("status", {}).duplicate(true)
	role_art = null
	rank = str(definition.get("kind", "normal"))
	accent = Color(str(definition.get("color", entity.get("color", "#c7a66a"))))
	dead = int(entity.get("hp", 1)) <= 0
	idle_seed = float(absi(role_id.hash()) % 100) * 0.0628
	archetype = _classify(str(definition.get("name", entity.get("name", ""))))
	if player:
		role_art = RoleArt.texture_for(role_id)
	else:
		var art_candidates: Array[String] = [
			"res://assets/art/monsters/%s.png" % role_id,
			"res://assets/art/monsters/%s.png" % archetype,
			"res://assets/art/enemies/%s.png" % role_id,
		]
		for art_path in art_candidates:
			if not ResourceLoader.exists(art_path):
				continue
			role_art = load(art_path) as Texture2D
			if role_art != null:
				break
	queue_redraw()


func _classify(display_name: String) -> String:
	if player:
		return role_id
	if "蛾" in display_name:
		return "moth"
	if "鸦" in display_name:
		return "raven"
	if "犬" in display_name or "兽" in display_name:
		return "beast"
	if "虫" in display_name:
		return "worm"
	if "天穹之眼" in display_name:
		return "eye"
	if "钟" in display_name and rank != "normal":
		return "bell"
	if ("王" in display_name and not "王庭" in display_name) or "摄政" in display_name or "圣母" in display_name:
		return "sovereign"
	if "骨" in display_name:
		return "skeleton"
	if "傀儡" in display_name or "巨像" in display_name or "圣像" in display_name:
		return "automaton"
	if "骑士" in display_name or "卫" in display_name or "双刃" in display_name or "小卒" in display_name or "刽子" in display_name:
		return "knight"
	if "师" in display_name or "士" in display_name or "学徒" in display_name or "颂唱" in display_name or "经" in display_name or "观测" in display_name or "院长" in display_name or "御医" in display_name or "书记" in display_name or "灯" in display_name:
		return "caster"
	return "undead"


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func play_attack() -> void:
	if not dead:
		attack_time = 0.48


## 从 play_attack 到命中点（lunge 峰值）的实际秒数，供演出调度对齐受击时机。
func attack_impact_delay() -> float:
	return 0.48 * 0.20 / maxf(0.25, animation_speed)


## 远程/施法体型：攻击时身体只小幅前推，不做大幅冲刺。
func _is_ranged_style() -> bool:
	if player:
		return role_id in ["sister", "arcanist", "medium", "ashlamper"]
	return archetype in ["caster", "eye", "sovereign"]


func play_hit(amount: int = 0, blocked: int = 0) -> void:
	shield_hit = blocked > 0 and amount <= 0
	hit_time = 0.42


func play_guard() -> void:
	guard_time = 0.36


func play_status_effect(key: String) -> void:
	if status_flash.has(key):
		status_flash[key] = 0.82
	queue_redraw()


func play_heal() -> void:
	heal_time = 0.78
	queue_redraw()


func play_death() -> void:
	dead = true
	death_time = 0.65
	attack_time = 0.0


func get_impact_position() -> Vector2:
	return global_position + size * Vector2(0.5, 0.47)


func _process(delta: float) -> void:
	if held:
		queue_redraw()
		return
	delta *= animation_speed
	if not reduced_motion:
		clock += delta
	attack_time = maxf(0.0, attack_time - delta)
	hit_time = maxf(0.0, hit_time - delta)
	death_time = maxf(0.0, death_time - delta)
	guard_time = maxf(0.0, guard_time - delta)
	heal_time = maxf(0.0, heal_time - delta)
	for key in status_flash:
		status_flash[key] = maxf(0.0, float(status_flash[key]) - delta)
	queue_redraw()


func _draw() -> void:
	var unit := minf(size.x / 210.0, size.y / 155.0)
	var ground := Vector2(size.x * 0.5, size.y * 0.88)
	draw_set_transform(ground, 0.0, Vector2(unit, unit))
	_ellipse(Vector2(5, 9), Vector2(74, 15), Color(0.025, 0.018, 0.014, 0.23))
	_ellipse(Vector2(1, 8), Vector2(62, 11), Color(0.018, 0.013, 0.012, 0.42))
	_ellipse(Vector2(0, 6), Vector2(45, 7), Color(0.012, 0.01, 0.01, 0.56))
	if rank in ["elite", "boss"] and not dead:
		_ring(Vector2(0, 8), Vector2(74, 15), Color(accent, 0.7 if rank == "boss" else 0.4), 1.8)
	if selected and not dead:
		_ring(Vector2(0, 8), Vector2(64, 12), Color(GOLD, 0.92), 2.2)
		_ring(Vector2(0, 8), Vector2(76, 15), Color(GOLD, 0.28), 1.1)
		for side in [-1, 1]:
			_line(Vector2(side * 82, -50), Vector2(side * 70, -38), GOLD, 1.8)
			_line(Vector2(side * 70, -38), Vector2(side * 82, -26), GOLD, 1.8)
	var idle := sin(clock * 1.25 + idle_seed) * 1.4 if not dead else 0.0
	var lunge := _lunge() * (0.18 if reduced_motion else 1.0)
	var recoil := 0.0
	if hit_time > 0.0:
		var hit_phase := clampf(hit_time / 0.42, 0.0, 1.0)
		recoil = -sin(hit_phase * PI) * (5.0 if shield_hit else 18.0)
	var facing := 1.0 if player else -1.0
	var collapse := (1.0 - death_time / 0.65) if dead else 0.0
	var squash := 0.9 if hit_time > 0.30 else (0.96 if attack_time > 0.34 else 1.0)
	draw_set_transform(ground + Vector2((lunge + recoil) * facing * unit, (idle + collapse * 9.0) * unit), facing * collapse * 0.14, Vector2(unit * facing, unit * squash * (1.0 - collapse * 0.18)))
	var old_accent := accent
	if dead:
		accent = Color("62665c")
	elif hit_time > 0.30:
		accent = Color("d5eef0") if shield_hit else Color("fff3e4")
	elif hit_time > 0.0 and not shield_hit:
		accent = accent.lightened(0.22)
	if role_art != null:
		if not player:
			draw_set_transform(ground + Vector2((lunge + recoil) * facing * unit, (idle + collapse * 9.0) * unit), facing * collapse * 0.14, Vector2(unit, unit * squash * (1.0 - collapse * 0.18)))
		var image_size := role_art.get_size()
		var scale_factor := minf(145.0 / image_size.y, 160.0 / image_size.x)
		var draw_size := image_size * scale_factor
		var tint := Color(0.48, 0.48, 0.48, 0.8) if dead else Color.WHITE
		if hit_time > 0.30:
			tint = Color(1.0, 0.75, 0.72) if not shield_hit else Color(0.75, 0.9, 1.0)
		draw_texture_rect(role_art, Rect2(Vector2(-draw_size.x * 0.5, -draw_size.y), draw_size), false, tint)
		if not player:
			draw_set_transform(ground + Vector2((lunge + recoil) * facing * unit, (idle + collapse * 9.0) * unit), facing * collapse * 0.14, Vector2(unit * facing, unit * squash * (1.0 - collapse * 0.18)))
	else:
		_draw_fallback()
	if rank == "elite" and not dead:
		_star(Vector2(0, -122), 5, 3, accent)
	accent = old_accent
	if guard_time > 0.0:
		var guard_phase := 1.0 - guard_time / 0.36
		_ring(Vector2(0, -58), Vector2(30 + guard_phase * 8, 42 + guard_phase * 6), Color("a7ced1", 0.8 * (1.0 - guard_phase)), 2.4)
	draw_set_transform(Vector2.ZERO)
	_draw_status_effects()


func _draw_status_effects() -> void:
	var weak_active := int(active_statuses.get("weak", 0)) > 0
	var vulnerable_active := int(active_statuses.get("vulnerable", 0)) > 0
	var regen_active := int(active_statuses.get("regen", 0)) > 0
	var weak_flash := float(status_flash.get("weak", 0.0))
	var vulnerable_flash := float(status_flash.get("vulnerable", 0.0))
	var regen_flash := float(status_flash.get("regen", 0.0))
	var center := Vector2(size.x * 0.5, size.y * 0.47)
	var phase := 0.0 if reduced_motion else clock
	if weak_active or weak_flash > 0.0:
		var strength := 0.40 if weak_active else 0.0
		strength = maxf(strength, weak_flash)
		var blue := Color("49c9e8", strength * 0.9)
		var ring_center := center + Vector2(0, 8)
		draw_arc(ring_center, 47 + sin(phase * 2.0) * 2.0, phase * 1.4, phase * 1.4 + PI * 1.25, 32, blue, 3.2, true)
		draw_arc(ring_center, 54, -phase * 0.9, -phase * 0.9 + PI * 0.75, 24, Color(blue, blue.a * 0.58), 1.8, true)
		for i in 3:
			var angle := phase * 1.1 + i * TAU / 3.0
			var mote := ring_center + Vector2.from_angle(angle) * 50.0 + Vector2(0, sin(angle * 1.7) * 5.0)
			draw_circle(mote, 3.1, Color(blue, blue.a))
	if vulnerable_active or vulnerable_flash > 0.0:
		var strength := 0.38 if vulnerable_active else 0.0
		strength = maxf(strength, vulnerable_flash)
		var red := Color("ff624f", strength * 0.88)
		draw_arc(center, 39 + sin(phase * 2.6) * 2.0, -0.2, TAU - 0.2, 36, red, 3.6, true)
		for i in 6:
			var angle := phase * 0.45 + i * TAU / 6.0
			var direction := Vector2.from_angle(angle)
			var origin := center + direction * 38.0
			draw_line(origin, origin + direction * 11.0, Color(red, red.a * 0.92), 2.5, true)
	if regen_active or regen_flash > 0.0:
		var strength := 0.34 if regen_active else 0.0
		strength = maxf(strength, regen_flash)
		var green := Color("7fe49b", strength * 0.94)
		for i in 4:
			var seed := float(i) * 1.71
			var travel := fposmod(phase * 0.48 + seed, 1.0)
			var x := size.x * 0.5 + sin(seed * 3.0) * 35.0
			var y := size.y * 0.75 - travel * size.y * 0.48
			draw_circle(Vector2(x, y), 2.8 + (1.0 - travel), Color(green, green.a * (1.0 - travel * 0.38)))
		if regen_flash > 0.0:
			var plus := center + Vector2(-34, -22 - (0.82 - regen_flash) * 18.0)
			draw_line(plus - Vector2(4, 0), plus + Vector2(4, 0), green, 2.4, true)
			draw_line(plus - Vector2(0, 4), plus + Vector2(0, 4), green, 2.4, true)
	if heal_time > 0.0:
		var progress := 1.0 - heal_time / 0.78
		var heal_color := Color("d6ffd0", (1.0 - progress) * 0.94)
		draw_arc(center, 18.0 + progress * 40.0, 0.0, TAU, 32, heal_color, 3.6 * (1.0 - progress) + 1.0, true)
		for i in 4:
			var ray := Vector2.from_angle(i * TAU / 4.0 + PI * 0.25)
			draw_line(center + ray * (14.0 + progress * 14.0), center + ray * (26.0 + progress * 34.0), heal_color, 2.0, true)


func _draw_fallback() -> void:
	match archetype:
		"raven": _raven()
		"moth": _moth()
		"beast": _beast()
		"worm": _worm()
		"eye": _eye()
		"bell": _bell()
		"sovereign": _humanoid("sovereign")
		"knight", "warden": _humanoid("knight")
		"skeleton": _skeleton()
		"ranger": _humanoid("ranger")
		"sister", "automaton": _automaton()
		"medium", "arcanist", "caster": _humanoid(archetype)
		_: _humanoid("undead")


func _lunge() -> float:
	if attack_time <= 0.0:
		return 0.0
	var phase := clampf(1.0 - attack_time / 0.48, 0.0, 1.0)
	# 近战大幅冲刺；远程施法只做小幅前推，与弹道演出匹配。
	var reach := 12.0 if _is_ranged_style() else 36.0
	var draw_back := 5.0 if _is_ranged_style() else 14.0
	if phase < 0.08:
		return -draw_back * (phase / 0.08)
	if phase < 0.20:
		var strike := (phase - 0.08) / 0.12
		var eased := 1.0 - (1.0 - strike) * (1.0 - strike)
		return lerpf(-draw_back, reach, eased)
	var recover := clampf((phase - 0.20) / 0.80, 0.0, 1.0)
	return lerpf(reach, 0.0, recover * recover)


func _poly(points: Array, color: Color, edge: bool = true) -> void:
	var polygon := PackedVector2Array(points)
	if not edge:
		draw_colored_polygon(polygon, color)
		return
	# Keep the key light on the same screen side when enemies face left.
	var light := Vector2(-0.54 if player else 0.54, -0.84)
	var darkest := INF
	var brightest := -INF
	for point in polygon:
		var exposure := point.dot(light)
		darkest = minf(darkest, exposure)
		brightest = maxf(brightest, exposure)
	var colors := PackedColorArray()
	var shadow := color.lerp(Color(0.055, 0.047, 0.055, color.a), 0.38)
	var highlight := color.lerp(Color(0.88, 0.77, 0.60, color.a), 0.25)
	for point in polygon:
		var exposure := inverse_lerp(darkest, maxf(darkest + 1.0, brightest), point.dot(light))
		colors.append(shadow.lerp(highlight, exposure))
	draw_polygon(polygon, colors)
	polygon.append(polygon[0])
	draw_polyline(polygon, Color(0.045, 0.034, 0.04, 0.92), 2.5, true)
	for i in polygon.size() - 1:
		var a := polygon[i]
		var b := polygon[i + 1]
		var exposure := inverse_lerp(darkest, maxf(darkest + 1.0, brightest), ((a + b) * 0.5).dot(light))
		if exposure > 0.63:
			_line(a.lerp(b, 0.06), a.lerp(b, 0.92), Color(highlight.lightened(0.24), 0.72 * exposure), 1.0)


func _line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	draw_line(a, b, color, width, true)


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 40:
		points.append(center + Vector2(cos(TAU * i / 40.0), sin(TAU * i / 40.0)) * radius)
	draw_colored_polygon(points, color)


func _ring(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 41:
		points.append(center + Vector2(cos(TAU * i / 40.0), sin(TAU * i / 40.0)) * radius)
	draw_polyline(points, color, width, true)


func _star(center: Vector2, outer: float, inner: float, color: Color) -> void:
	var points: Array = []
	for i in 8:
		var angle := i * TAU / 8.0 - PI * 0.5
		points.append(center + Vector2(cos(angle), sin(angle)) * (outer if i % 2 == 0 else inner))
	_poly(points, color, false)


func _humanoid(kind: String) -> void:
	var cloth := accent.darkened(0.66)
	var metal := accent.lerp(Color("697270"), 0.40).darkened(0.30)
	var trim := accent.lerp(Color("d7b382"), 0.44)
	var regal := kind == "sovereign"
	if regal:
		_ring(Vector2(0, -85), Vector2(42, 42), Color(accent, 0.35), 1.0)
		_ring(Vector2(0, -85), Vector2(37, 37), Color(accent, 0.18), 1.0)
	_poly([Vector2(-16, -82), Vector2(-31, -69), Vector2(-37, -37), Vector2(-46, 1), Vector2(-28, -5), Vector2(-19, 1), Vector2(-9, -8), Vector2(7, -3), Vector2(24, 1), Vector2(39, -4), Vector2(27, -57), Vector2(14, -82)], cloth)
	_poly([Vector2(-17, -68), Vector2(-34, -28), Vector2(-42, -2), Vector2(-28, -7)], cloth.lightened(0.10), false)
	_poly([Vector2(10, -65), Vector2(16, -24), Vector2(28, -2), Vector2(19, -36)], cloth.darkened(0.24), false)
	_line(Vector2(-24, -51), Vector2(-31, -12), Color(trim, 0.42), 1.2)
	_line(Vector2(22, -48), Vector2(27, -12), Color(trim, 0.24), 1.2)
	_poly([Vector2(-12, -75), Vector2(11, -74), Vector2(17, -31), Vector2(7, -20), Vector2(1, -31), Vector2(-8, -23), Vector2(-17, -32)], accent.darkened(0.49))
	if kind in ["knight", "undead", "ranger"]:
		_poly([Vector2(-16, -40), Vector2(-3, -40), Vector2(-6, -18), Vector2(-11, -7), Vector2(-13, 3), Vector2(-30, 3), Vector2(-28, -3), Vector2(-20, -6), Vector2(-21, -20)], metal.darkened(0.23))
		_poly([Vector2(4, -40), Vector2(16, -42), Vector2(21, -22), Vector2(19, -7), Vector2(29, 0), Vector2(27, 4), Vector2(9, 4), Vector2(7, -19)], metal)
		_line(Vector2(11, -16), Vector2(17, -16), trim, 1.4)
	if kind in ["knight", "undead"]:
		_poly([Vector2(-19, -73), Vector2(1, -78), Vector2(22, -67), Vector2(16, -39), Vector2(-14, -42)], metal)
		_poly([Vector2(-26, -76), Vector2(-9, -73), Vector2(-12, -59), Vector2(-31, -63)], metal.lightened(0.07))
		_poly([Vector2(17, -75), Vector2(29, -67), Vector2(25, -56), Vector2(12, -61)], metal)
		_poly([Vector2(-15, -70), Vector2(1, -74), Vector2(15, -66), Vector2(1, -57), Vector2(-11, -61)], metal.lightened(0.18), false)
		_poly([Vector2(-14, -58), Vector2(1, -54), Vector2(17, -58), Vector2(12, -48), Vector2(0, -45), Vector2(-11, -48)], metal.darkened(0.24), false)
		_line(Vector2(-13, -57), Vector2(0, -53), trim, 1.3)
		_line(Vector2(0, -53), Vector2(14, -58), trim, 1.3)
		for x in [-22, 20]:
			draw_circle(Vector2(x, -67), 1.65, trim)
		_poly([Vector2(-12, -98), Vector2(-6, -111), Vector2(10, -109), Vector2(17, -97), Vector2(10, -80), Vector2(-9, -82)], metal)
		_poly([Vector2(-10, -96), Vector2(14, -96), Vector2(10, -88), Vector2(-8, -88)], INK, false)
		_line(Vector2(-7, -94), Vector2(10, -94), trim.lightened(0.27), 1.8)
		_line(Vector2(1, -106), Vector2(2, -98), trim, 1.2)
		_poly([Vector2(-8, -87), Vector2(2, -83), Vector2(11, -88), Vector2(8, -81), Vector2(-7, -80)], metal.darkened(0.22), false)
	else:
		_poly([Vector2(-20, -87), Vector2(-13, -107), Vector2(2, -119), Vector2(17, -104), Vector2(22, -83), Vector2(11, -73), Vector2(-11, -76)], cloth.lightened(0.04))
		_poly([Vector2(-11, -96), Vector2(1, -105), Vector2(12, -96), Vector2(8, -80), Vector2(-7, -81)], INK, false)
		_line(Vector2(-6, -93), Vector2(-2, -92), accent.lightened(0.45), 1.8)
		_line(Vector2(4, -92), Vector2(8, -93), accent.lightened(0.45), 1.8)
		_poly([Vector2(-18, -87), Vector2(-11, -104), Vector2(1, -115), Vector2(-3, -101), Vector2(-12, -91)], cloth.lightened(0.16), false)
		_poly([Vector2(-18, -76), Vector2(-4, -64), Vector2(13, -76), Vector2(21, -71), Vector2(3, -54), Vector2(-15, -66)], accent.darkened(0.31))
		_star(Vector2(3, -58), 5, 2, trim)
		_line(Vector2(-11, -48), Vector2(10, -43), trim.darkened(0.28), 2.2)
	if kind == "ranger":
		_poly([Vector2(-29, -81), Vector2(-21, -83), Vector2(-7, -51), Vector2(-15, -49)], cloth.lightened(0.11))
		for i in 3:
			_line(Vector2(-26 + i * 3, -77), Vector2(-33 + i * 3, -92 - i * 3), trim, 1.8)
		draw_arc(Vector2(32, -56), 38, -1.2, 1.2, 20, trim, 3.5, true)
		_line(Vector2(46, -91), Vector2(46, -21), BONE, 0.8)
		_line(Vector2(5, -60), Vector2(61, -60), accent, 2)
		_poly([Vector2(68, -60), Vector2(58, -64), Vector2(58, -56)], BONE, false)
	elif kind in ["caster", "medium", "arcanist"]:
		_line(Vector2(38, -12), Vector2(38, -103), accent.darkened(0.15), 3)
		_ellipse(Vector2(38, -105), Vector2(15, 15), Color(accent, 0.13))
		_ring(Vector2(38, -105), Vector2(11, 11), trim, 1.6)
		_star(Vector2(38, -105), 7, 2.5, accent.lightened(0.55))
		_poly([Vector2(17, -68), Vector2(32, -54), Vector2(40, -61), Vector2(37, -48), Vector2(19, -48)], cloth)
		if kind == "medium":
			for i in 3:
				var mote := Vector2(-35.0 - i * 6, -63.0 - i * 13 + sin(clock * 2.0 + i) * 4)
				_ellipse(mote, Vector2(6, 9), Color(accent, 0.22))
				draw_circle(mote, 2, accent.lightened(0.3))
		if kind == "arcanist":
			_ring(Vector2(-36, -69), Vector2(15, 15), Color(accent, 0.6), 1)
			_star(Vector2(-36, -69), 10, 2, accent)
			_poly([Vector2(-15, -103), Vector2(-11, -115), Vector2(-5, -109), Vector2(0, -124), Vector2(7, -108), Vector2(14, -115), Vector2(16, -101), Vector2(0, -105)], trim.darkened(0.15))
	elif regal:
		_poly([Vector2(-18, -108), Vector2(-21, -124), Vector2(-9, -116), Vector2(0, -132), Vector2(10, -116), Vector2(21, -125), Vector2(17, -107)], accent.darkened(0.15))
		_line(Vector2(38, -4), Vector2(38, -99), accent, 3)
		_star(Vector2(38, -104), 12, 5, accent)
	else:
		_line(Vector2(33, -12), Vector2(40, -100), accent, 3.5)
		_poly([Vector2(37, -101), Vector2(41, -117), Vector2(45, -100), Vector2(39, -32), Vector2(34, -32)], BONE.darkened(0.24))
		_line(Vector2(25, -31), Vector2(47, -29), accent, 3)
		if kind == "knight":
			_poly([Vector2(-44, -69), Vector2(-29, -76), Vector2(-13, -70), Vector2(-13, -40), Vector2(-22, -28), Vector2(-31, -24), Vector2(-43, -37)], trim.darkened(0.22))
			_poly([Vector2(-40, -66), Vector2(-29, -71), Vector2(-17, -66), Vector2(-17, -42), Vector2(-30, -29), Vector2(-39, -39)], accent.darkened(0.54))
			_line(Vector2(-30, -64), Vector2(-29, -35), trim, 1.6)
			_line(Vector2(-37, -53), Vector2(-22, -53), trim, 1.6)
			_ring(Vector2(-29, -53), Vector2(5, 5), trim, 1.1)


func _automaton() -> void:
	var frame := accent.lerp(Color("7e857c"), 0.34).darkened(0.32)
	var joint := frame.darkened(0.48)
	var glow := accent.lightened(0.47)
	for side in [-1, 1]:
		_poly([Vector2(5 * side, -43), Vector2(22 * side, -45), Vector2(24 * side, -24), Vector2(15 * side, -21), Vector2(8 * side, -28)], frame)
		draw_circle(Vector2(16 * side, -24), 6.0, joint)
		_poly([Vector2(12 * side, -25), Vector2(21 * side, -24), Vector2(23 * side, -7), Vector2(30 * side, -1), Vector2(25 * side, 4), Vector2(9 * side, 2)], frame)
		_poly([Vector2(17 * side, -80), Vector2(33 * side, -77), Vector2(39 * side, -66), Vector2(29 * side, -57), Vector2(15 * side, -65)], frame)
		_poly([Vector2(31 * side, -67), Vector2(39 * side, -63), Vector2(42 * side, -43), Vector2(33 * side, -38), Vector2(27 * side, -50)], joint.lightened(0.12))
		_line(Vector2(32 * side, -59), Vector2(37 * side, -47), Color(glow, 0.65), 1.8)
		_poly([Vector2(34 * side, -46), Vector2(42 * side, -44), Vector2(44 * side, -34), Vector2(36 * side, -31), Vector2(31 * side, -37)], frame)
	_poly([Vector2(-22, -81), Vector2(-11, -86), Vector2(14, -84), Vector2(22, -75), Vector2(18, -57), Vector2(11, -49), Vector2(-12, -49), Vector2(-19, -59)], frame)
	_poly([Vector2(-12, -49), Vector2(12, -49), Vector2(18, -41), Vector2(10, -35), Vector2(-9, -35), Vector2(-17, -41)], joint)
	_poly([Vector2(-8, -76), Vector2(9, -76), Vector2(13, -67), Vector2(5, -59), Vector2(-6, -59), Vector2(-13, -67)], joint)
	_ring(Vector2(0, -68), Vector2(6, 6), Color(glow, 0.72), 1.6)
	_star(Vector2(0, -68), 4.2, 1.8, glow)
	_poly([Vector2(-17, -99), Vector2(-11, -111), Vector2(10, -110), Vector2(17, -101), Vector2(15, -88), Vector2(6, -83), Vector2(-10, -85), Vector2(-16, -92)], frame)
	_poly([Vector2(-13, -100), Vector2(13, -99), Vector2(11, -91), Vector2(-11, -92)], INK, false)
	_line(Vector2(-9, -96), Vector2(8, -95), glow, 2.5)
	if player:
		_line(Vector2(-9, -109), Vector2(-16, -120), frame.lightened(0.35), 2.0)
		draw_circle(Vector2(-16, -120), 2.3, glow)
		_line(Vector2(15, -103), Vector2(23, -113), frame.lightened(0.24), 1.6)
	else:
		_poly([Vector2(-21, -99), Vector2(-22, -113), Vector2(-12, -106), Vector2(-13, -97)], frame)
		_poly([Vector2(12, -103), Vector2(20, -115), Vector2(19, -98), Vector2(13, -94)], frame)


func _skeleton() -> void:
	_line(Vector2(0, -87), Vector2(0, -29), BONE.darkened(0.28), 4)
	for i in 4:
		var y := -77.0 + i * 9
		_poly([Vector2(-18 + i, y), Vector2(0, y + 5), Vector2(17 - i, y), Vector2(12 - i, y + 8), Vector2(0, y + 11), Vector2(-13 + i, y + 8)], accent.darkened(0.2))
	_line(Vector2(-13, -27), Vector2(-22, -4), accent, 5)
	_line(Vector2(12, -27), Vector2(23, -2), accent, 5)
	_line(Vector2(-18, -75), Vector2(-31, -45), accent, 4)
	_line(Vector2(17, -74), Vector2(32, -50), accent, 4)
	_poly([Vector2(-13, -110), Vector2(10, -114), Vector2(18, -102), Vector2(10, -85), Vector2(-8, -85), Vector2(-16, -99)], BONE.darkened(0.15))
	draw_circle(Vector2(-7, -100), 4, INK)
	draw_circle(Vector2(7, -101), 4, INK)
	_line(Vector2(-6, -91), Vector2(7, -91), INK, 2)
	for x in [-4, 0, 4]:
		_line(Vector2(x, -93), Vector2(x, -89), BONE.darkened(0.24), 1.1)
	_poly([Vector2(-9, -98), Vector2(-3, -96), Vector2(-10, -91)], BONE.darkened(0.42), false)
	draw_circle(Vector2(7, -101), 1.55, accent.lightened(0.36))
	_poly([Vector2(-13, -35), Vector2(1, -29), Vector2(14, -34), Vector2(10, -24), Vector2(-10, -24)], BONE.darkened(0.24))
	_line(Vector2(34, -7), Vector2(34, -113), accent.darkened(0.24), 3.5)
	_poly([Vector2(29, -112), Vector2(34, -127), Vector2(39, -112)], BONE)


func _raven() -> void:
	var lift := sin(clock * 2.6 + idle_seed) * 5
	_poly([Vector2(-6, -57), Vector2(-42, -94 - lift), Vector2(-72, -97 - lift), Vector2(-59, -78), Vector2(-66, -77), Vector2(-47, -63), Vector2(-55, -61), Vector2(-23, -45)], accent.darkened(0.6))
	_poly([Vector2(2, -61), Vector2(29, -101 - lift), Vector2(64, -112 - lift), Vector2(49, -89), Vector2(58, -91), Vector2(41, -70), Vector2(47, -71), Vector2(18, -45)], accent.darkened(0.47))
	for i in 4:
		var feather := float(i)
		_line(Vector2(-11 - feather * 3, -59 - feather * 4), Vector2(-43 - feather * 6, -64 - feather * 8 - lift), Color(accent, 0.42), 1.3)
		_line(Vector2(13 + feather * 3, -61 - feather * 4), Vector2(34 + feather * 7, -72 - feather * 10 - lift), Color(accent, 0.47), 1.4)
	_poly([Vector2(-16, -65), Vector2(4, -79), Vector2(19, -65), Vector2(10, -35), Vector2(-8, -15), Vector2(-4, -41), Vector2(-24, -24)], accent.darkened(0.25))
	_poly([Vector2(-8, -61), Vector2(4, -70), Vector2(12, -62), Vector2(4, -47), Vector2(-4, -52)], accent.darkened(0.08), false)
	_poly([Vector2(7, -78), Vector2(20, -89), Vector2(33, -83), Vector2(36, -71), Vector2(23, -63), Vector2(10, -65)], accent.darkened(0.42))
	_poly([Vector2(32, -82), Vector2(51, -73), Vector2(33, -73)], BONE.darkened(0.25))
	draw_circle(Vector2(28, -79), 2.5, Color("e6bf79"))
	_line(Vector2(0, -39), Vector2(13, -22), accent, 2)
	_line(Vector2(9, -44), Vector2(22, -29), accent, 2)


func _moth() -> void:
	for side in [-1, 1]:
		_poly([Vector2(side * 7, -62), Vector2(side * 57, -108), Vector2(side * 65, -85), Vector2(side * 57, -59), Vector2(side * 25, -48)], accent.darkened(0.4))
		_poly([Vector2(side * 8, -58), Vector2(side * 43, -45), Vector2(side * 53, -23), Vector2(side * 33, -12), Vector2(side * 12, -35)], accent.darkened(0.58))
		for i in 3:
			var vein := Vector2(side * (36 + i * 11), -60 - i * 11)
			_line(Vector2(side * 14, -60), vein, Color(accent, 0.38), 1.2)
		var eyespot := Vector2(side * 41, -76)
		_ellipse(eyespot, Vector2(12, 15), accent.darkened(0.61))
		_ring(eyespot, Vector2(10, 13), accent.lightened(0.18), 1.7)
		_ellipse(eyespot, Vector2(5, 8), accent.darkened(0.12))
		draw_circle(eyespot + Vector2(-1, -2), 2.5, BONE)
		_line(Vector2(side * 5, -82), Vector2(side * 17, -100), accent, 1)
	_poly([Vector2(0, -88), Vector2(8, -70), Vector2(5, -37), Vector2(0, -23), Vector2(-5, -37), Vector2(-8, -70)], accent.lightened(0.2))
	for i in 4:
		_line(Vector2(-4, -63 + i * 7), Vector2(4, -63 + i * 7), accent.darkened(0.6), 1.5)


func _beast() -> void:
	_poly([Vector2(-37, -43), Vector2(-30, -15), Vector2(-16, -10), Vector2(-12, -13), Vector2(-21, -22), Vector2(-16, -43)], accent.darkened(0.68))
	_poly([Vector2(11, -40), Vector2(22, -21), Vector2(41, -12), Vector2(45, -15), Vector2(32, -24), Vector2(28, -43)], accent.darkened(0.67))
	_poly([Vector2(-64, -41), Vector2(-41, -63), Vector2(-13, -64), Vector2(0, -76), Vector2(3, -69), Vector2(13, -82), Vector2(16, -73), Vector2(26, -77), Vector2(38, -59), Vector2(29, -28), Vector2(-24, -29)], accent.darkened(0.48))
	_poly([Vector2(-54, -44), Vector2(-35, -58), Vector2(-15, -55), Vector2(12, -68), Vector2(18, -57), Vector2(6, -47), Vector2(-21, -43)], accent.darkened(0.31), false)
	_poly([Vector2(-45, -40), Vector2(-44, -9), Vector2(-31, -3), Vector2(-24, -5), Vector2(-33, -15), Vector2(-26, -37)], accent.darkened(0.62))
	_poly([Vector2(15, -43), Vector2(15, -10), Vector2(29, -3), Vector2(38, -4), Vector2(26, -15), Vector2(31, -39)], accent.darkened(0.36))
	_poly([Vector2(17, -60), Vector2(21, -92), Vector2(35, -82), Vector2(44, -96), Vector2(47, -75), Vector2(65, -63), Vector2(58, -52), Vector2(34, -48)], accent.darkened(0.27))
	_poly([Vector2(-51, -47), Vector2(-76, -61), Vector2(-81, -52), Vector2(-64, -28), Vector2(-52, -29)], accent.darkened(0.6))
	_poly([Vector2(35, -67), Vector2(46, -76), Vector2(54, -67), Vector2(44, -63)], accent.darkened(0.63), false)
	draw_circle(Vector2(46, -70), 2.9, Color("e6b776"))
	_poly([Vector2(45, -60), Vector2(62, -62), Vector2(57, -55), Vector2(49, -53)], INK, false)
	_poly([Vector2(51, -59), Vector2(54, -59), Vector2(52, -54)], BONE, false)
	_poly([Vector2(56, -60), Vector2(59, -60), Vector2(57, -56)], BONE.darkened(0.18), false)
	for i in 4:
		var rib := float(i) * 8.0
		_line(Vector2(-19 + rib, -54), Vector2(-23 + rib, -46), Color(accent, 0.62), 1.5)
		_line(Vector2(-23 + rib, -46), Vector2(-19 + rib, -39), Color(accent, 0.40), 1.4)


func _worm() -> void:
	for i in 8:
		var center := Vector2(-54 + i * 14, -19 - sin(i * 0.6) * 24)
		_ellipse(center, Vector2(14, 17), accent.darkened(0.55 - i * 0.035))
		_ellipse(center + Vector2(-3, -5), Vector2(7, 8), Color(accent, 0.22))
		_ring(center, Vector2(12, 15), accent.darkened(0.18), 1.2)
		_line(center + Vector2(-3, 12), center + Vector2(-7, 22), accent, 1.5)
		draw_circle(center + Vector2(2, -4), 1.7, accent.lightened(0.15))
	_ellipse(Vector2(48, -37), Vector2(19, 23), accent.darkened(0.22))
	_ellipse(Vector2(54, -40), Vector2(10, 15), INK)
	for i in 6:
		var a := i * TAU / 6
		_line(Vector2(54, -40) + Vector2(cos(a), sin(a)) * Vector2(8, 13), Vector2(54, -40) + Vector2(cos(a), sin(a)) * Vector2(4, 7), BONE, 2)


func _eye() -> void:
	for i in 3:
		_ring(Vector2(0, -66), Vector2(43 + i * 10, 43 + i * 10), Color(accent, 0.30 - i * 0.07), 1)
	_poly([Vector2(-58, -66), Vector2(-24, -91), Vector2(0, -99), Vector2(25, -90), Vector2(58, -66), Vector2(23, -41), Vector2(0, -34), Vector2(-26, -43)], accent.darkened(0.57))
	_ellipse(Vector2(0, -66), Vector2(24, 29), accent.darkened(0.55))
	_ellipse(Vector2(0, -66), Vector2(19, 26), accent)
	for i in 18:
		var angle := i * TAU / 18.0
		var ray := Vector2(cos(angle), sin(angle))
		_line(Vector2(0, -66) + ray * Vector2(11, 16), Vector2(0, -66) + ray * Vector2(18, 25), Color(accent.lightened(0.40), 0.72), 1.3)
	_ellipse(Vector2(1, -66), Vector2(7, 21), INK)
	draw_circle(Vector2(7, -75), 4, BONE)
	for i in 8:
		var a := i * TAU / 8 + 0.2
		_star(Vector2(cos(a), sin(a)) * 62 + Vector2(0, -66), 4, 1.5, accent)


func _bell() -> void:
	_poly([Vector2(-30, -48), Vector2(-39, -7), Vector2(-19, -3), Vector2(-7, -46)], accent.darkened(0.5))
	_poly([Vector2(10, -45), Vector2(19, -4), Vector2(40, -5), Vector2(32, -49)], accent.darkened(0.4))
	_poly([Vector2(-31, -93), Vector2(-43, -78), Vector2(-48, -34), Vector2(-60, -21), Vector2(59, -21), Vector2(47, -35), Vector2(41, -80), Vector2(28, -95)], accent.darkened(0.48))
	_ring(Vector2(0, -101), Vector2(11, 11), accent, 3)
	_poly([Vector2(-29, -88), Vector2(-37, -73), Vector2(-42, -38), Vector2(-49, -29), Vector2(-31, -31), Vector2(-24, -81)], accent.darkened(0.18), false)
	_poly([Vector2(28, -90), Vector2(39, -78), Vector2(46, -37), Vector2(53, -29), Vector2(35, -28), Vector2(27, -62)], accent.darkened(0.59), false)
	_line(Vector2(-32, -79), Vector2(-24, -72), INK, 1.7)
	_line(Vector2(-24, -72), Vector2(-30, -63), INK, 1.7)
	_line(Vector2(-30, -63), Vector2(-21, -57), INK, 1.7)
	_ellipse(Vector2(0, -23), Vector2(59, 10), accent.darkened(0.21))
	_ellipse(Vector2(0, -22), Vector2(44, 5), INK)
	_poly([Vector2(-20, -82), Vector2(-8, -88), Vector2(16, -83), Vector2(19, -63), Vector2(7, -53), Vector2(-13, -57)], INK)
	_line(Vector2(-9, -72), Vector2(-2, -71), Color("efc58c"), 3)
	_line(Vector2(7, -71), Vector2(13, -73), Color("efc58c"), 3)
	_line(Vector2(-29, -44), Vector2(29, -44), accent, 1.5)
	for i in 5:
		_star(Vector2(-24 + i * 12, -35), 3, 1.2, accent)
