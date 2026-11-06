extends SceneTree
## Use the UI shell's memory-only game for both interaction regressions.

const UIShell = preload("res://tests/ui_shell.gd")

var ui: UIShell
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	ui = UIShell.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	_test_journey_setup()
	await _test_hand_scroll()
	ui.queue_free()
	await _settle()
	for failure in failures:
		printerr(failure)
	print("INTERACTION_CONTINUITY failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_journey_setup() -> void:
	_press("NewJourneyButton")
	ui.seed_input.text = "2147483648"
	_press("BeginJourney")
	_check(not ui.game.state.active, "invalid seed must not start a journey")
	_check(ui.seed_input.text == "2147483648", "invalid seed must remain editable")
	_check(ui.seed_input.has_focus() and ui.seed_error.visible, "invalid seed must show inline feedback and focus the field")
	_press("PickRole_ranger")
	_check(ui.seed_input.text == "2147483648" and ui.seed_error.visible, "switching traveler must preserve the draft and its feedback")
	ui.seed_input.text = "729"
	ui.seed_input.text_changed.emit(ui.seed_input.text)
	_check(not ui.seed_error.visible, "editing the seed must clear old feedback")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	ui._unhandled_key_input(escape)
	_press("NewJourneyButton")
	_check(ui.seed_input.text.is_empty() and not ui.seed_error.visible, "returning to setup must start a clean draft")
	ui.seed_input.text = "729"
	_press("PickRole_warden")
	_press("BeginJourney")
	_check(ui.game.state.active and ui.game.state.seed == 729, "a valid draft must reach the run unchanged")


func _test_hand_scroll() -> void:
	var result: Dictionary = ui.game.enter_node(1)
	if not result.get("ok", false) or ui.game.state.room != "battle":
		_check(false, "fixture must open a battle")
		return
	ui.game.state.enemies.append(ui.game.state.enemies[0].duplicate(true))
	ui.game.state.hand.clear()
	for _index in 10:
		ui.game.state.hand.append({"id": "warden_02", "upgraded": false})
	ui._refresh()
	await _settle()
	var bar := _hand_area().get_h_scroll_bar()
	_hand_area().scroll_horizontal = int(bar.max_value - bar.page)
	var offset := _hand_area().scroll_horizontal
	_check(offset > 0, "ten-card hand must be wider than the viewport")
	_press("EnemyTarget_1")
	ui._clear(ui.overlay)
	_press("EnemyTarget_0")
	ui._clear(ui.overlay)
	_check(ui.selected_target == 0, "both target clicks must take effect after closing details")
	await _settle()
	_check(_hand_area().scroll_horizontal == offset, "two target refreshes in one frame must keep the hand offset")
	ui._play_card(9)
	var deadline := Time.get_ticks_msec() + 3000
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not ui.combat_busy, "the card's presentation must finish")
	await _settle()
	bar = _hand_area().get_h_scroll_bar()
	var available := int(bar.max_value - bar.page)
	_check(ui.game.state.hand.size() == 9, "playing the rightmost card must resolve once")
	_check(available > 0 and available < offset and _hand_area().scroll_horizontal == available,
		"after playing a card, keep the right end in view and clamp to the shorter hand")
	ui.game.state.turn += 1
	ui._refresh()
	await _settle()
	_check(_hand_area().scroll_horizontal == 0, "a new turn must show the hand from the start")
	_hand_area().scroll_horizontal = available
	ui.game.state.lane += 1
	ui._refresh()
	await _settle()
	_check(_hand_area().scroll_horizontal == 0, "another encounter must not inherit the offset")


func _press(node_name: String) -> void:
	var button := ui.find_child(node_name, true, false) as Button
	_check(button != null and not button.disabled, "expected enabled button: " + node_name)
	if button != null and not button.disabled:
		button.pressed.emit()


func _hand_area() -> ScrollContainer:
	return ui.find_child("HandArea", true, false) as ScrollContainer


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
