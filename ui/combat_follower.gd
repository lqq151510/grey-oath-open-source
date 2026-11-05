extends BaseButton
## Draws a compact silhouette beside the player using only the current battle snapshot.

const TONES := {"osty": Color("ccafcf"), "spirit": Color("a6c4a9"), "servant": Color("dac18a")}

var kind := ""
var health := 0
var held := false
var animation_speed := 1.0
var reduced_motion := false
var tone := Color.WHITE
var pulse := 0.0
var guard := false
var detail_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(70, 77)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(false)


func setup(follower_kind: String, title: String, detail: String, tooltip: String, compact: bool = false) -> void:
	kind = follower_kind
	tone = TONES[follower_kind]
	tooltip_text = tooltip
	if compact:
		custom_minimum_size = Vector2(60, 60)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lines)
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.offset_top = 35 if compact else 43
	lines.offset_bottom = -3
	lines.add_theme_constant_override("separation", 0)
	_caption(lines, title, 11 if compact else 13, Color("f3ead6"))
	detail_label = _caption(lines, detail, 10 if compact else 12, tone)
	var caption_size := lines.get_combined_minimum_size()
	custom_minimum_size.x = maxf(custom_minimum_size.x, caption_size.x + 8)
	custom_minimum_size.y = maxf(custom_minimum_size.y, lines.offset_top + caption_size.y - lines.offset_bottom)
	queue_redraw()


func _caption(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func set_health(amount: int) -> void:
	health = maxi(0, amount)
	detail_label.text = "生命 %d" % health
	queue_redraw()


func get_impact_position() -> Vector2:
	return global_position + Vector2(size.x * 0.5, 24)


func play_attack() -> void:
	_pulse(false)


func play_guard() -> void:
	_pulse(true)


func _pulse(shield: bool) -> void:
	guard = shield
	pulse = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if held:
		return
	pulse = maxf(0.0, pulse - delta * animation_speed * 3.5)
	queue_redraw()
	if pulse == 0.0:
		set_process(false)


func _draw() -> void:
	var edge := tone.darkened(0.54)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("181b17")
	frame.border_color = edge.lerp(tone, pulse)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(4)
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	var center := Vector2(size.x * 0.5, 24)
	var ink := tone
	if kind == "osty" and health == 0:
		ink = tone.darkened(0.57)
	draw_circle(center, 18, Color(ink, 0.10 + pulse * 0.15))
	draw_arc(center, 18, 0, TAU, 32, Color(ink, 0.34), 1, true)
	if pulse > 0.0:
		draw_arc(center, 19, 0, TAU, 32, Color(ink if guard else Color("e9d0a1"), pulse), 2, true)
	var thrust := pulse * 4.0 if not guard and not reduced_motion else 0.0
	draw_set_transform(center + Vector2(thrust, 0))
	match kind:
		"osty": _draw_osty(ink)
		"spirit": _draw_spirit(ink)
		"servant": _draw_servant(ink)
	draw_set_transform(Vector2.ZERO)


func _draw_osty(ink: Color) -> void:
	var bone := PackedVector2Array([
		Vector2(-15, -13), Vector2(-7, -8), Vector2(-4, -13), Vector2(5, -13),
		Vector2(8, -8), Vector2(15, -13), Vector2(12, -2), Vector2(6, 1),
		Vector2(5, 7), Vector2(-5, 7), Vector2(-7, 1), Vector2(-12, -2),
	])
	draw_colored_polygon(bone, ink)
	draw_circle(Vector2(-5, -4), 2, Color("242126"))
	draw_circle(Vector2(5, -4), 2, Color("242126"))
	draw_line(Vector2(0, 6), Vector2(0, 15), ink, 2, true)
	draw_arc(Vector2(0, 10), 8, 0.22, PI - 0.22, 16, ink, 1.5, true)


func _draw_spirit(ink: Color) -> void:
	var flame := PackedVector2Array([
		Vector2(-14, 4), Vector2(-17, -5), Vector2(-7, -1), Vector2(-7, -8),
		Vector2(-1, -15), Vector2(6, -10), Vector2(9, -3), Vector2(17, -8),
		Vector2(15, 3), Vector2(8, 8), Vector2(1, 15), Vector2(-8, 17), Vector2(-4, 9),
	])
	draw_colored_polygon(flame, ink)
	draw_arc(Vector2(-1, 1), 9, 0.2, PI - 0.2, 16, ink.darkened(0.42), 1.4, true)
	draw_circle(Vector2(0, -6), 2, Color("263429"))
	draw_circle(Vector2(5, -5), 1.5, Color("263429"))


func _draw_servant(ink: Color) -> void:
	var helm := PackedVector2Array([
		Vector2(-8, -7), Vector2(-5, -13), Vector2(4, -13), Vector2(8, -7),
		Vector2(7, 1), Vector2(-7, 1),
	])
	draw_colored_polygon(helm, ink)
	draw_line(Vector2(-6, -6), Vector2(5, -6), Color("3b2c18"), 1.7)
	var shield := PackedVector2Array([
		Vector2(-11, 1), Vector2(10, 1), Vector2(9, 8), Vector2(0, 16), Vector2(-9, 8),
	])
	draw_colored_polygon(shield, ink.darkened(0.17))
	draw_line(Vector2(0, 2), Vector2(0, 12), ink.lightened(0.22), 1.5, true)
