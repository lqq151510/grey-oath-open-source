extends "res://ui/main.gd"
## Test shell avoids reading or writing the player's actual save.

func _ready() -> void:
	_build_theme()
	game = Rules.new("")
	_build_shell()
	menu_open = true
	_refresh()


func push_pointer_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)


func push_pointer_drag(from: Vector2, to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)


func drag_card(from: Vector2, to: Vector2) -> void:
	push_pointer_button(from, true)
	push_pointer_drag(from, to)
	push_pointer_button(to, false)
