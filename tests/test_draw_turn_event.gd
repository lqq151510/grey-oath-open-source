extends SceneTree
## Memory-only rule/UI checks; --capture exports actual Godot frames.

const Rules = preload("res://core/game_engine.gd")
const OUTPUT := "res://docs/evidence/draw-turn-event-20261104"
var ui
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func settle() -> void:
	for ignored in 4:
		await process_frame


func idle() -> void:
	var deadline := Time.get_ticks_msec() + 6500
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not ui.combat_busy, "playback finishes within 6.5 seconds")
	await settle()


func fixture(script = Rules):
	var game = script.new("")
	game.new_run("warden", 42)
	game.state.run_id = "draw-turn-fixture"
	game.enter_node(1)
	game.state.enemies = [{"id": "fixture", "name": "试炼守卫", "hp": 100, "max_hp": 100, "block": 0, "status": {},
		"pattern": [{"intent": "攻击 6", "effects": [{"op": "damage", "value": 6}]}], "turn": 0, "intent": "攻击 6", "color": "#c7a66a"}]
	game.state.relics = []
	game._indexes.cards["draw_test"] = {"id": "draw_test", "name": "循光", "description": "抽取2张牌。", "cost": 0, "type": "skill", "effects": [{"op": "draw", "value": 2}]}
	game.state.hand = [{"id": "draw_test", "upgraded": false}, {"id": "token_blade", "upgraded": false}]
	game.state.draw = [{"id": "warden_01", "upgraded": false}, {"id": "warden_01", "upgraded": true}]
	game.state.discard = []
	return game


func show_fixture() -> void:
	ui.game = fixture()
	ui.menu_open = false
	ui.notice = "抽牌与回合特效 · 内存演示，不写旅程存档 · Esc 跳过"
	ui._refresh()


func events(game, kind: String) -> Array:
	return game.combat_events.filter(func(event): return event.kind == kind)


func key_escape() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	ui._unhandled_key_input(key)


func test_rules() -> void:
	var game = fixture()
	game.play_card(0)
	var draws := events(game, "draw")
	check(draws.size() == 2, "two actual draws recorded")
	check(draws[0].hand_index == 1 and draws[1].hand_index == 2, "draws append after retained hand slot")
	check(draws[0].card.upgraded and not draws[1].card.upgraded, "same-ID upgraded cards preserve draw order")
	check(draws[0].card == game.state.hand[1], "draw snapshot matches actual instance")
	check(not game.state.has("combat_events"), "presentation stays outside persistent state")
	game.end_turn()
	check(game.combat_events[0].kind == "turn_end", "end-turn phase precedes enemy effects")
	check(events(game, "turn_start").size() == 1, "surviving turn has one turn-start event")
	check(game.state.hand[0].id == "token_blade", "retained card remains first")
	check(events(game, "draw").size() == 3, "reshuffle records actual three cards rather than requested five")
	game.play_card(99)
	check(game.combat_events.is_empty(), "rejected action clears stale draw/phase events")
	game = fixture()
	while game.state.hand.size() < 10:
		game.state.hand.append({"id": "warden_01", "upgraded": false})
	game._combat_recording = true
	game._draw_cards(5)
	check(events(game, "draw").is_empty() and game.state.hand.size() == 10, "full hand produces no phantom draws")
	game = fixture()
	game.state.draw = []
	game.state.discard = []
	game._combat_recording = true
	game._draw_cards(5)
	check(events(game, "draw").is_empty(), "empty piles produce no phantom draws")
	game = fixture()
	game.state.hp = 1
	game.end_turn()
	check(game.state.room == "defeat" and events(game, "turn_start").is_empty() and events(game, "draw").is_empty(), "lethal enemy turn never announces or draws a new hand")


func test_ui() -> void:
	show_fixture()
	await settle()
	ui._play_card(0)
	var committed := JSON.stringify(ui.game.state)
	ui._end_turn()
	check(ui.combat_busy and JSON.stringify(ui.game.state) == committed, "draw action commits once and rejects repeated end-turn")
	var ghost := await wait_draw_ghost()
	check(ghost != null, "card-based draw creates flying card faces")
	check(ghost != null and ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE, "draw ghost ignores input")
	await idle()
	check(JSON.stringify(ui.game.state) == committed, "draw animation never changes rules or RNG")
	check(ui.find_child("DrawGhost_*", true, false) == null, "draw ghosts cleaned after playback")
	ui._end_turn()
	committed = JSON.stringify(ui.game.state)
	check(ui.find_child("TurnBanner", true, false) != null, "turn-end banner appears immediately")
	check(ui.find_child("DiscardGhost", true, false) != null, "ordinary hand cards fly into discard pile")
	check(ui.find_child("HandCard_0", true, false).modulate.a == 1.0, "retained card does not disappear with discarded cards")
	key_escape()
	check(not ui.combat_busy and JSON.stringify(ui.game.state) == committed, "Escape skips turn animation without repeating action")
	await create_timer(0.9).timeout
	check(ui.find_child("DrawGhost_*", true, false) == null and ui.find_child("TurnBanner", true, false) == null, "skipped coroutine never restores stale effects")
	show_fixture()
	await settle()
	ui._play_card(0)
	await wait_draw_ghost()
	committed = JSON.stringify(ui.game.state)
	key_escape()
	await create_timer(0.9).timeout
	check(not ui.combat_busy and ui.find_child("DrawGhost_*", true, false) == null, "Escape cancels active draw tweens")
	check(JSON.stringify(ui.game.state) == committed, "draw skip preserves committed hand")
	ui.game = Rules.new("")
	ui.game.new_run("warden", 42)
	ui._refresh()
	ui._enter_node(1)
	check(ui.combat_busy, "opening hand animates on actual node entry")
	await idle()
	check(ui.find_child("HandCard_0", true, false).modulate.a == 1.0, "opening hand becomes visible and interactive")
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		for event in ui.game.data.events:
			ui.game.state.room = "event"
			ui.game.state.event = event
			ui._refresh()
			await settle()
			for index in event.choices.size():
				var choice: Dictionary = event.choices[index]
				if not choice.has("card"):
					continue
				var preview := ui.find_child("EventCard_%d" % index, true, false) as Button
				var detail := ui.find_child("EventCardEffect_%d" % index, true, false) as Label
				check(preview != null and detail != null, "event has visible card and full effect: " + str(event.id))
				check(detail.text == ui.game.card_data(choice.card).description, "event reads actual card effect: " + str(event.id))
				check(ui.get_global_rect().encloses(preview.get_global_rect()), "event card fits viewport: " + str(dimensions) + str(event.id))
				check(ui.get_global_rect().encloses(ui.find_child("EventPick_%d" % index, true, false).get_global_rect()), "event action fits viewport: " + str(dimensions) + str(event.id))
				var state := JSON.stringify(ui.game.state)
				preview.pressed.emit()
				check(JSON.stringify(ui.game.state) == state, "preview click never chooses event")


func snapshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)
	screenshots.append(path)


func capture() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		var suffix := "%dx%d" % [dimensions.x, dimensions.y]
		show_fixture()
		await settle()
		ui._play_card(0)
		await create_timer(0.55).timeout
		await snapshot("draw-" + suffix)
		await idle()
		ui._end_turn()
		await create_timer(0.12).timeout
		await snapshot("turn-end-" + suffix)
		var deadline := Time.get_ticks_msec() + 6000
		while ui.find_child("DrawGhost_*", true, false) == null and ui.combat_busy and Time.get_ticks_msec() < deadline:
			await process_frame
		await create_timer(0.12).timeout
		await snapshot("turn-start-" + suffix)
		await idle()
		ui.game.state.room = "event"
		for event in ui.game.data.events:
			if event.name == "第一次誓言":
				ui.game.state.event = event
		ui._refresh()
		await settle()
		await snapshot("event-" + suffix)


func _run() -> void:
	root.title = "灰誓 · 抽牌与回合特效验收（不写存档）"
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await settle()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
	else:
		test_rules()
		await test_ui()
	var report := {"checks": checks, "failures": failures, "screenshots": screenshots, "save_path": "empty (memory only)", "mode": "native capture" if "--capture" in OS.get_cmdline_user_args() else "script simulation"}
	var file := FileAccess.open(OUTPUT + ("/capture-results.json" if "--capture" in OS.get_cmdline_user_args() else "/results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("DRAW_TURN_EVENT_RESULT " + JSON.stringify(report))
	ui.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)


func wait_draw_ghost() -> Control:
	var deadline := Time.get_ticks_msec() + 2500
	var ghost := ui.find_child("DrawGhost_*", true, false) as Control
	while ghost == null and ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
		ghost = ui.find_child("DrawGhost_*", true, false) as Control
	return ghost
