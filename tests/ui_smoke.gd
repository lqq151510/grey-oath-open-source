extends SceneTree
## Run with --headless --path . --script tests/ui_smoke.gd.
## Omit --headless and add -- --screenshots to render evidence images.
## Edge scenarios use explicit fixtures; they do not prove combat balance.

var ui
var failures: Array[String] = []
var measurements: Array = []
var screenshots := false
var current_window := Vector2i(1440, 900)
var screenshots_written: Array[String] = []
var action_checks: Dictionary = {}


func _initialize() -> void:
	screenshots = OS.get_cmdline_user_args().has("--screenshots")
	call_deferred("run")


func settle() -> void:
	await process_frame
	await process_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func layout(screen: String) -> void:
	var size: Vector2 = ui.content.size
	check(size.x <= 1377 and size.y <= 857, "%s/%s content overflow: %s" % [current_window, screen, size])
	var entry := {"window": [current_window.x, current_window.y], "screen": screen, "logical_viewport": [ui.size.x, ui.size.y], "content": [size.x, size.y]}
	if screen.begins_with("battle"):
		for control_name in ["EndTurnButton", "HandArea"]:
			var control = ui.find_child(control_name, true, false)
			check(control != null, "%s missing %s" % [screen, control_name])
			if control != null:
				var rect: Rect2 = control.get_global_rect()
				entry[control_name] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
				check(rect.end.y <= 880 and rect.end.x <= 1410, "%s/%s out of viewport: %s" % [screen, control_name, rect])
	measurements.append(entry)


func capture(screen: String) -> void:
	if not screenshots or current_window != Vector2i(1440, 900):
		return
	await RenderingServer.frame_post_draw
	var path := "res://docs/evidence/%s.png" % screen
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	check(error == OK, "screenshot failed: " + path)
	if error == OK:
		screenshots_written.append(path)


func fresh_run(role_id: String = "warden") -> void:
	ui.game = load("res://core/game_engine.gd").new("")
	ui.game.profile.total_wins = 100
	check(ui.game.new_run(role_id, 729).get("ok", false), "fixture new_run: " + role_id)
	ui.menu_open = false
	ui.save_warning = ""
	ui.notice = ""


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence"))
	for window in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		current_window = window
		root.size = window
		ui = load("res://tests/ui_shell.gd").new()
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(ui)
		await settle()
		layout("menu")
		await capture("menu")
		fresh_run()
		ui._refresh()
		await settle()
		layout("map")
		await capture("map")
		ui._enter_node(1)
		await settle()
		layout("battle")
		await capture("battle")
		for room in ["reward", "shop", "rest", "event", "treasure", "victory", "defeat"]:
			ui.game.state.room = room
			if room == "reward":
				ui.game.state.rewards = ui.game.state.deck.slice(0, 3)
			if room == "shop":
				ui.game._make_shop()
			if room == "event":
				ui.game.state.event = ui.game.data.events[0]
			ui._refresh()
			await settle()
			layout(room)
		ui._show_deck("view")
		await settle()
		layout("deck")
		ui._clear(ui.overlay)
		await edge_cases()
		root.remove_child(ui)
		ui.queue_free()
		await settle()
	await exercise_actions()
	var result := {
		"godot_version": Engine.get_version_info().string,
		"verification": "programmatic UI fixtures, button signals and viewport drag input",
		"windows": [[1440, 900], [1280, 800]],
		"edge_fixture": {"all_events": 40, "roles": 5, "enemies": 3, "hand": 10, "status_types": 7, "summons": 3, "long_log_entries": 12},
		"checks": measurements,
		"actions": action_checks,
		"screenshots": screenshots_written,
		"failures": failures,
		"passed": failures.is_empty()
	}
	var file := FileAccess.open("res://docs/evidence/ui-validation.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	else:
		failures.append("failed to save ui-validation.json")
	print("UI_SMOKE checks=", measurements.size(), " actions=", action_checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)


func edge_cases() -> void:
	fresh_run()
	for event_data in ui.game.data.events:
		ui.game.state.room = "event"
		ui.game.state.event = event_data
		ui._refresh()
		await settle()
		layout("event:" + str(event_data.id))
	for role in ui.game.data.roles:
		fresh_run(str(role.id))
		ui.game.enter_node(1)
		var enemy: Dictionary = ui.game.state.enemies[0].duplicate(true)
		ui.game.state.enemies = [enemy.duplicate(true), enemy.duplicate(true), enemy.duplicate(true)]
		ui.game.state.status = {"strength": 4, "weak": 2, "vulnerable": 3, "poison": 5, "thorns": 6, "regen": 2, "next_energy": 3}
		for target in ui.game.state.enemies:
			target.status = ui.game.state.status.duplicate(true)
		ui.game.state.hand.clear()
		for ignored in range(10):
			ui.game.state.hand.append({"id": "medium_29", "upgraded": false})
		ui.game.state.potions = ["potion_poison", "potion_stars", "potion_poison"]
		ui.game.state.summons = [{"power": 12, "turns": 3}, {"power": 12, "turns": 2}, {"power": 15, "turns": 1}]
		ui.game.state.log.clear()
		for index in range(12):
			ui.game.state.log.append("记录%d：召唤物向首个存活敌人发动攻击，获得额外格挡，敌人仍在准备下一轮攻击。" % index)
		ui._refresh()
		await settle()
		layout("battle:complex:" + str(role.id))
		if role.id == "medium":
			await capture("battle-complex")
	var obstruction := "/tmp/grey-oath-ui-save-obstruction-%d" % OS.get_process_id()
	var blocking_file := FileAccess.open(obstruction, FileAccess.WRITE)
	blocking_file.store_string("intentional UI save-error test fixture")
	blocking_file.close()
	ui.game._save_path = obstruction + "/save.json"
	ui._accept(ui.game.end_turn())
	await settle()
	check(not ui.save_warning.is_empty() and ui.notice_label.text == ui.save_warning, "save warning not exposed")
	DirAccess.remove_absolute(obstruction)
	ui.game._save_path = ""
	await duplicate_relic()


func duplicate_relic() -> void:
	fresh_run()
	for event_data in ui.game.data.events:
		for choice in event_data.get("choices", []):
			if not choice.has("relic"):
				continue
			ui.game.state.relics.append(str(choice.relic))
			ui.game.state.room = "event"
			ui.game.state.event = event_data
			ui._refresh()
			await settle()
			var disabled_found := false
			for button in ui.find_children("*", "Button", true, false):
				if "已拥有此遗物" in button.text and button.disabled:
					disabled_found = true
			check(disabled_found, "duplicate relic choice not disabled")
			return
	check(false, "missing duplicate relic event fixture")


func exercise_actions() -> void:
	root.size = Vector2i(1440, 900)
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await settle()
	ui.find_child("NewJourneyButton", true, false).pressed.emit()
	await settle()
	ui.menu_page = "roles"
	ui._refresh()
	await settle()
	ui.seed_input.text = "729"
	ui._begin_run()
	check(ui.game.state.room == "map" and ui.game.state.active, "start run")
	ui._enter_node(1)
	check(ui.game.state.room == "battle", "map to battle")
	var iterations := 0
	while ui.game.state.room == "battle" and iterations < 200:
		iterations += 1
		await settle()
		var chosen := -1
		for index in range(ui.game.state.hand.size()):
			var card: Dictionary = ui.game.card_view(ui.game.state.hand[index])
			if int(card.cost) <= int(ui.game.state.energy) and card.type == "attack":
				chosen = index
				break
		if chosen < 0:
			for index in range(ui.game.state.hand.size()):
				var card: Dictionary = ui.game.card_view(ui.game.state.hand[index])
				if int(card.cost) <= int(ui.game.state.energy):
					chosen = index
					break
		if chosen >= 0:
			var button = ui.find_child("HandCard_%d" % chosen, true, false)
			check(button != null, "hand button missing")
			if button:
				var enemy = ui.find_child("EnemyTarget_%d" % ui.selected_target, true, false)
				check(enemy != null, "drag target missing")
				if enemy:
					ui.drag_card(button.get_global_rect().get_center(), enemy.get_global_rect().get_center())
		else:
			ui.find_child("EndTurnButton", true, false).pressed.emit()
		var deadline := Time.get_ticks_msec() + 6000
		while ui.combat_busy and Time.get_ticks_msec() < deadline:
			await process_frame
		check(not ui.combat_busy, "combat feedback exceeded bounded playback")
	check(ui.game.state.room == "reward", "first battle did not reach reward")
	if ui.game.state.room == "reward":
		var previous_count: int = ui.game.state.deck.size()
		ui._accept(ui.game.choose_reward(0))
		check(ui.game.state.deck.size() == previous_count + 1 and ui.game.state.room == "map", "reward did not add card and return to map")
	action_checks = {"iterations": iterations, "room": ui.game.state.room, "hp": ui.game.state.hp, "save_path_empty": ui.game._save_path.is_empty()}
	root.remove_child(ui)
	ui.queue_free()
