extends Button
## Compact map marker; disabled markers still receive Control hover and tooltips.

const GOLD := Color("c7a66a")
const PAPER := Color("e8dfcc")
const MUTED := Color("9a9e91")
var kind := "normal"
var caption := "小怪"
var reachable := false
var visited := false
var current := false
var preview := false
var legend_mode := false


func _init() -> void:
	custom_minimum_size = Vector2(96, 52)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func configure(node_kind: String, label_text: String, can_enter: bool = false, was_visited: bool = false, is_current: bool = false) -> void:
	kind = node_kind
	caption = label_text
	reachable = can_enter
	visited = was_visited
	current = is_current
	disabled = not reachable
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if reachable else Control.CURSOR_ARROW
	queue_redraw()


func set_preview(value: bool) -> void:
	preview = value
	queue_redraw()


func get_path_center() -> Vector2:
	return global_position + _center()


func _center() -> Vector2:
	return Vector2(18, 18) if legend_mode else Vector2(size.x * 0.5, 21)


func _draw() -> void:
	var center := _center()
	var color := GOLD if reachable or visited or current else MUTED
	if preview:
		color = Color("c1cfb0")
	if not legend_mode:
		draw_circle(center, 19, Color("151914"))
		draw_arc(center, 18, 0, TAU, 40, Color(color, 0.95 if reachable or current or preview else 0.48), 1.8 if reachable else 1.0, true)
		if current:
			draw_arc(center, 22, 0, TAU, 40, GOLD, 1.4, true)
		if reachable or has_focus():
			for side in [-1, 1]:
				_line(center + Vector2(side * 27, -4), center + Vector2(side * 23, 0), color)
				_line(center + Vector2(side * 23, 0), center + Vector2(side * 27, 4), color)
		if is_hovered():
			draw_arc(center, 23, 0, TAU, 40, Color(PAPER, 0.5), 1, true)
		if visited:
			draw_circle(center + Vector2(16, -13), 6, Color("151914"))
			_line(center + Vector2(12, -13), center + Vector2(15, -10), GOLD, 1.5)
			_line(center + Vector2(15, -10), center + Vector2(21, -16), GOLD, 1.5)
	draw_set_transform(center)
	_icon(color)
	draw_set_transform(Vector2.ZERO)
	var font := get_theme_default_font()
	var font_size := 15 if legend_mode else 14
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := Vector2(42, 24) if legend_mode else Vector2((size.x - text_size.x) * 0.5, 51)
	draw_string_outline(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color("111511"))
	draw_string(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _line(from: Vector2, to: Vector2, color: Color, width: float = 1.6) -> void:
	draw_line(from, to, color, width, true)


func _path(points: Array, color: Color, width: float = 1.6, closed: bool = false) -> void:
	var path := PackedVector2Array()
	for point in points:
		path.append(point)
	if closed:
		path.append(path[0])
	draw_polyline(path, color, width, true)


func _icon(color: Color) -> void:
	match kind:
		"normal":
			_path([Vector2(-8, -6), Vector2(-4, -11), Vector2(4, -11), Vector2(9, -5), Vector2(7, 5), Vector2(3, 5), Vector2(3, 10), Vector2(-3, 10), Vector2(-3, 5), Vector2(-7, 5)], color, 1.6, true)
			draw_circle(Vector2(-4, -2), 2, color)
			draw_circle(Vector2(4, -2), 2, color)
			_line(Vector2(0, 4), Vector2(0, 9), color, 1)
		"elite":
			_path([Vector2(-9, -1), Vector2(-12, -11), Vector2(-5, -7), Vector2(0, -10), Vector2(5, -7), Vector2(12, -11), Vector2(9, -1), Vector2(7, 8), Vector2(0, 12), Vector2(-7, 8)], color, 1.8, true)
			_line(Vector2(-6, -1), Vector2(-2, 1), color, 2)
			_line(Vector2(6, -1), Vector2(2, 1), color, 2)
			_line(Vector2(-3, 7), Vector2(3, 7), color)
		"boss":
			_path([Vector2(-11, -8), Vector2(-6, -3), Vector2(0, -13), Vector2(6, -3), Vector2(11, -8), Vector2(8, 8), Vector2(-8, 8)], color, 1.8, true)
			_line(Vector2(-8, 4), Vector2(8, 4), color)
			draw_circle(Vector2(0, -1), 2, color)
			_line(Vector2(-10, 12), Vector2(10, 12), color)
		"treasure":
			_path([Vector2(-11, -3), Vector2(-8, -9), Vector2(8, -9), Vector2(11, -3), Vector2(11, 9), Vector2(-11, 9)], color, 1.6, true)
			_line(Vector2(-11, -2), Vector2(11, -2), color)
			draw_rect(Rect2(-2, -4, 4, 7), color, false, 1.4)
		"shop":
			_path([Vector2(-9, 0), Vector2(-9, 10), Vector2(9, 10), Vector2(9, 0)], color)
			_path([Vector2(-12, -2), Vector2(-8, -10), Vector2(8, -10), Vector2(12, -2)], color, 1.6, true)
			for i in [-1, 0, 1]:
				_line(Vector2(i * 5, -9), Vector2(i * 6, -2), color, 1)
			_path([Vector2(-2, 10), Vector2(-2, 3), Vector2(4, 3), Vector2(4, 10)], color, 1.3)
		"unknown":
			var font := get_theme_default_font()
			draw_string(font, Vector2(-7, 9), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, color)
		"event", "fate":
			_path([Vector2(0, -13), Vector2(10, 0), Vector2(0, 13), Vector2(-10, 0)], color, 1.6, true)
			_path([Vector2(-7, 0), Vector2(0, -4), Vector2(7, 0), Vector2(0, 4)], color, 1.1, true)
			draw_circle(Vector2.ZERO, 2, color)
		"rest":
			_path([Vector2(-7, 6), Vector2(-9, 0), Vector2(-5, -7), Vector2(-3, -1), Vector2(2, -12), Vector2(8, -3), Vector2(8, 3), Vector2(3, 8), Vector2(-3, 8)], color, 1.6, true)
			_line(Vector2(-10, 12), Vector2(9, 9), color, 2)
			_line(Vector2(-9, 9), Vector2(10, 12), color, 2)
		_:
			draw_circle(Vector2.ZERO, 5, color)
