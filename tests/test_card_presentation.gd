extends SceneTree
## Isolated presentation fixture. Never writes user://save.json.
## --demo: interactive memory-only battle; --capture: two-size viewport evidence.

const Rules = preload("res://core/game_engine.gd")
const OUTPUT = "res://docs/evidence/card-effects-20261103"
var ui
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _settle() -> void:
	for ignored in range(4):
		await process_frame


func _fixture() -> void:
	ui.game = Rules.new("")
	ui.game.new_run("warden", 42)
	ui.game.enter_node(1)
	ui.game.state.hand = [
		{"id": "warden_01", "upgraded": false},
		{"id": "warden_02", "upgraded": false},
		{"id": "warden_19", "upgraded": false},
		{"id": "ranger_03", "upgraded": true},
		{"id": "arcanist_03", "upgraded": true},
	]
	ui.game.state.energy = 3
	ui.game.state.souls = 0
	ui.menu_open = false
	ui.save_warning = ""
	ui.selected_target = 0
	ui.notice = "卡牌展示 · 独立内存测试，不写入旅程存档"
	ui._refresh()


func _card(index: int) -> Button:
	return ui.find_child("HandCard_%d" % index, true, false) as Button


func _all_ignore(node: Node) -> bool:
	for child in node.get_children():
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
		if not _all_ignore(child):
			return false
	return true


func _push_key(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	root.push_input(key, true)


func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.title = "灰誓 · 卡牌展示（不写存档）"
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	_fixture()
	await _settle()
	var args := OS.get_cmdline_user_args()
	if "--demo" in args or "--preview" in args:
		print("CARD_DEMO_READY: memory-only, safe to click cards / E / targets")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if "--capture" in args:
		await _capture()
		quit(0)
		return
	await _test_presentation()
	await _test_drop_zones()
	await _test_follower_details()
	await _test_follower_layout()
	var report := {"checks": checks, "failures": failures, "mode": "UI script simulation; no physical mouse evidence", "save_path": "empty (memory-only)"}
	var file := FileAccess.open(OUTPUT + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CARD_PRESENTATION_RESULT " + JSON.stringify(report))
	ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)


func _test_presentation() -> void:
	_check(ui.game._save_path.is_empty(), "fixture persistence disabled")
	_check(_card(0) != null and _card(4) != null, "five hand cards render")
	_check(_card(4).disabled, "soul-short card disabled")
	_check("星辰不足" in _card(4).tooltip_text, "soul-short tooltip explains reason")
	var unavailable = _card(4).find_child("Availability", true, false)
	_check(unavailable is Label and "星辰不足" in unavailable.text, "soul-short reason visible on face")
	_check(_all_ignore(_card(0)), "card visual children never intercept input")
	for index in range(5):
		var description := _card(index).find_child("Description", true, false) as Label
		var tags := _card(index).find_child("Tags", true, false) as Label
		var availability := _card(index).find_child("Availability", true, false) as Label
		_check(description.get_rect().end.y <= tags.position.y, "hand description does not overlap tags: %d" % index)
		_check(tags.get_rect().end.y <= availability.position.y, "hand tags do not overlap status: %d" % index)
	var upgraded: Dictionary = ui.game.card_view(ui.game.state.hand[3])
	_check(str(upgraded.description) in _card(3).tooltip_text.replace("。\n", "。"), "complete upgraded effects retained in tooltip")
	var snapshot := JSON.stringify(ui.game.state)
	var hit_rect := _card(0).get_global_rect()
	_card(0).mouse_entered.emit()
	_card(0).grab_focus()
	await create_timer(0.22).timeout
	_check(_card(0).get_global_rect() == hit_rect, "hover preserves button hit rectangle")
	_card(0).mouse_exited.emit()
	_card(0).release_focus()
	await create_timer(0.22).timeout
	_check(JSON.stringify(ui.game.state) == snapshot, "hover/focus never mutates rules state")
	for ignored in range(10):
		_card(0).mouse_entered.emit()
		_card(0).mouse_exited.emit()
	await create_timer(0.22).timeout
	_check(_card(0).get_global_rect() == hit_rect, "rapid hover leaves stable layout")

	ui.game.state.energy = 0
	ui._refresh()
	await _settle()
	_check(_card(0).disabled and "能量不足" in _card(0).tooltip_text, "energy-short card disabled with reason")
	_check(not _card(3).disabled, "zero-cost card remains usable at zero energy")
	snapshot = JSON.stringify(ui.game.state)
	var disabled_point := _card(0).get_global_rect().get_center()
	ui.push_pointer_button(disabled_point, true)
	ui.push_pointer_button(disabled_point, false)
	_check(ui.overlay.find_child("HandCardDetail", true, false) != null, "unaffordable card still opens details")
	_push_key(KEY_ESCAPE)
	ui.push_pointer_button(disabled_point, true)
	ui.push_pointer_drag(disabled_point, disabled_point + Vector2(24, 0))
	ui.push_pointer_drag(disabled_point + Vector2(24, 0), disabled_point)
	ui.push_pointer_button(disabled_point, false)
	_check(ui.overlay.get_child_count() == 0 and JSON.stringify(ui.game.state) == snapshot, "dragging an unaffordable card back does not play or inspect it")
	ui._play_card(0)
	await _settle()
	_check(JSON.stringify(ui.game.state) == snapshot, "rejected play has no state mutation")
	_check(ui.find_child("CardCastFeedback", true, false) == null, "rejected play has no success feedback")

	_fixture()
	await _settle()
	var count_before: int = ui.game.state.hand.size()
	var energy_before: int = ui.game.state.energy
	var discard_before: int = ui.game.state.discard.size()
	var cost: int = ui.game.card_view(ui.game.state.hand[0]).cost
	var from := _card(0).get_global_rect().get_center()
	snapshot = JSON.stringify(ui.game.state)
	ui.push_pointer_button(from, true)
	ui.push_pointer_drag(from, from + Vector2(3, 0))
	ui.push_pointer_button(from + Vector2(3, 0), false)
	var detail := ui.overlay.find_child("HandCardDetail", true, false) as Label
	var card: Dictionary = ui.game.card_view(ui.game.state.hand[0])
	_check(detail != null and str(card.description) in detail.text.replace("。\n", "。"), "short click shows complete current card effect")
	_check(JSON.stringify(ui.game.state) == snapshot, "opening card details leaves battle unchanged")
	_push_key(KEY_ESCAPE)
	_push_key(KEY_1)
	_check(ui.game.state.hand.size() == count_before, "click and number key do not play a card")
	ui.drag_card(from, from + Vector2(20, 0))
	_check(ui.game.state.hand.size() == count_before and ui.overlay.get_child_count() == 0, "drag released in hand cancels")
	ui.drag_card(from, ui.find_child("EnemyTarget_0", true, false).get_global_rect().get_center())
	await _settle()
	_check(ui.game.state.hand.size() == count_before - 1, "one drag removes exactly one hand card")
	_check(ui.game.state.energy == energy_before - cost, "one drag charges energy once")
	_check(ui.game.state.discard.size() == discard_before + 1, "one drag discards once")
	_check(ui.find_child("CardCastFeedback", true, false) != null, "successful play creates feedback")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_E
	var turn_before: int = ui.game.state.turn
	ui._unhandled_key_input(key)
	await _settle()
	_check(ui.game.state.turn == turn_before, "combat playback prevents duplicate end-turn shortcut")
	var deadline := Time.get_ticks_msec() + 6000
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not ui.combat_busy, "combat playback releases input")
	ui._unhandled_key_input(key)
	_check(ui.game.state.turn == turn_before + 1, "end-turn shortcut works after playback")
	deadline = Time.get_ticks_msec() + 6000
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(ui.find_child("CardCastFeedback", true, false) == null, "feedback is cleaned after refresh/lifetime")

	_fixture()
	while ui.game.state.hand.size() < 10:
		ui.game.state.hand.append({"id": "warden_01", "upgraded": false})
	ui._refresh()
	await _settle()
	var area := ui.find_child("HandArea", true, false) as ScrollContainer
	_check(_card(9) != null, "all ten hand cards created")
	_check(area.get_h_scroll_bar().max_value > area.size.x, "ten-card hand can scroll horizontally")
	area.scroll_horizontal = 9999
	await _settle()
	_check(area.get_global_rect().intersects(_card(9).get_global_rect()), "last hand card reachable through scrolling")
	var end_button := ui.find_child("EndTurnButton", true, false) as Button
	_check(root.get_visible_rect().encloses(end_button.get_global_rect()), "end-turn button within viewport")

	ui.game.state.room = "reward"
	ui.game.state.energy = 0
	ui.game.state.rewards = [{"id": "warden_01", "upgraded": false}, {"id": "arcanist_03", "upgraded": true}, {"id": "warden_19", "upgraded": false}]
	ui._refresh()
	await _settle()
	var visuals: Array[Node] = ui.find_children("CardVisual", "", true, false)
	_check(visuals.size() == 3, "reward uses shared card visuals")
	for visual in visuals:
		_check(not visual.get_parent().disabled and str(visual.availability_reason).is_empty(), "reward unaffected by battle resource shortage")
	ui._show_deck()
	await _settle()
	_check(ui.overlay.find_children("CardVisual", "", true, false).size() == ui.game.state.deck.size(), "deck modal uses shared card visuals")
	ui._clear(ui.overlay)
	await _settle()


func _test_drop_zones() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		_fixture()
		var living: Dictionary = ui.game.state.enemies[0].duplicate(true)
		living.hp = 60
		living.max_hp = 60
		living.block = 0
		var second := living.duplicate(true)
		second.name = "试炼守卫"
		var fallen := living.duplicate(true)
		fallen.hp = 0
		ui.game.state.enemies = [living, second, fallen]
		ui._refresh()
		await _settle()
		var from := _card(0).get_global_rect().get_center()
		var first: Vector2 = ui.find_child("EnemyTarget_0", true, false).get_global_rect().get_center()
		var target: Vector2 = ui.find_child("EnemyTarget_1", true, false).get_global_rect().get_center()
		var dead: Vector2 = ui.find_child("EnemyTarget_2", true, false).get_global_rect().get_center()
		var toolbar: Vector2 = ui.find_child("CombatGlossary", true, false).get_global_rect().get_center()
		var arena_blank: Vector2 = ui.find_child("PlayerActor", true, false).get_global_rect().get_center()
		var state_before := JSON.stringify(ui.game.state)
		var hint: Label = ui.find_child("HandTargetHint", true, false)
		var normal_hint := hint.text

		for destination in [toolbar, dead, Vector2(4, target.y)]:
			ui.push_pointer_button(from, true)
			ui.push_pointer_drag(from, destination)
			_check("取消" in hint.text, "invalid drop warns before release")
			ui.push_pointer_button(destination, false)
			_check(JSON.stringify(ui.game.state) == state_before, "invalid drop keeps battle state (%s, %s)" % [dimensions, destination])
			_check(ui.selected_target == 0 and hint.text == normal_hint, "invalid drop restores hint and selection")

		for cancel in ["escape", "focus", "modal"]:
			ui.push_pointer_button(from, true)
			ui.push_pointer_drag(from, target)
			_check(is_instance_valid(ui.drag_ghost) and "试炼守卫" in hint.text, "drag previews named target")
			if cancel == "escape":
				_push_key(KEY_ESCAPE)
			elif cancel == "focus":
				root.focus_exited.emit()
			else:
				ui._show_rules()
			ui.push_pointer_button(target, false)
			_check(not is_instance_valid(ui.drag_ghost) and not ui.menu_open, "drag cancelled by " + cancel)
			_check(JSON.stringify(ui.game.state) == state_before and hint.text == normal_hint, "cancelled drag leaves state and hint intact")
			ui._clear(ui.overlay)
			await _settle()

		var damage: int = ui.game.preview_card(0, 1).damage
		ui.drag_card(from, target)
		_check(ui.selected_target == 1 and int(ui.game.state.enemies[1].hp) == 60 - damage
			and int(ui.game.state.enemies[0].hp) == 60, "explicit living target alone takes damage")
		_push_key(KEY_ESCAPE)
		await _settle()
		var shield_from := _card(0).get_global_rect().get_center()
		var energy_before: int = ui.game.state.energy
		ui.drag_card(shield_from, first)
		_check(ui.selected_target == 1 and int(ui.game.state.energy) < energy_before, "defense plays without changing locked target")
		_push_key(KEY_ESCAPE)
		await _settle()

		ui.game.state.hand[0] = {"id": "warden_01", "upgraded": false}
		ui._refresh()
		await _settle()
		var hp_before: int = ui.game.state.enemies[1].hp
		ui.drag_card(_card(0).get_global_rect().get_center(), arena_blank)
		_check(ui.selected_target == 1 and int(ui.game.state.enemies[1].hp) < hp_before
			and int(ui.game.state.enemies[0].hp) == 60, "valid open arena uses locked target")
		_push_key(KEY_ESCAPE)
		await _settle()


func _snapshot(name_suffix: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + name_suffix + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " error=", error)


func _test_follower_details() -> void:
	_fixture()
	ui.game.state.role = "medium"
	ui.game.state.osty_hp = 4
	ui.game.state.summons = [{"power": 5, "turns": 2}]
	ui.game.state.hand.append({"id": "token_minion", "upgraded": false})
	ui._refresh()
	await _settle()
	var snapshot := JSON.stringify(ui.game.state)
	var expectations := {
		"OstyFollower": ["替你挡下剩余伤害", "才会让它出手"],
		"SpiritFollower_0": ["第一个还活着的敌人", "造成 5 点伤害", "还能行动 2 次"],
		"ServantCards": ["消耗 0 点能量", "获得11点格挡"],
	}
	for id in expectations:
		var follower := ui.find_child(id, true, false) as Control
		_check(follower != null, "%s appears in battle" % id)
		if follower == null:
			continue
		var point := follower.get_global_rect().get_center()
		ui.push_pointer_button(point, true)
		ui.push_pointer_button(point, false)
		var detail := ui.overlay.find_child("FollowerDetail", true, false) as Label
		for phrase in expectations[id]:
			_check(detail != null and phrase in detail.text, "%s detail explains %s" % [id, phrase])
		_check(JSON.stringify(ui.game.state) == snapshot, "%s detail does not change the battle" % id)
		_push_key(KEY_ESCAPE)


func _test_follower_layout() -> void:
	for dimensions in [Vector2i(1280, 720), Vector2i(1440, 810), Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		for encounter in ["boss", "elite"]:
			_fixture()
			ui.game.state.role = "medium"
			ui.game.state.chapter = 3
			ui.game.state.encounter_kind = encounter
			ui.game._start_battle(encounter)
			ui.game.state.osty_hp = 27
			if encounter == "elite":
				ui.game.state.summons = [{"power": 12, "turns": 3}, {"power": 9, "turns": 2}, {"power": 8, "turns": 1}]
				ui.game.state.hand.append({"id": "token_minion", "upgraded": false})
			ui._refresh()
			await _settle()
			var context := "%s at %s" % [encounter, dimensions]
			var followers := ui.find_child("BattleFollowers", true, false) as Control
			var details := ui.find_child("PlayerDetails", true, false) as ScrollContainer
			var arena := ui.find_child("BattleArena", true, false) as Control
			var bounds: Rect2 = ui.get_global_rect()
			_check(followers != null and not details.is_ancestor_of(followers) and arena.get_global_rect().encloses(followers.get_global_rect()) and bounds.encloses(followers.get_global_rect()), "follower row is fixed inside visible arena " + context)
			if followers == null:
				continue
			var tiles := followers.find_children("*", "BaseButton", true, false)
			_check(tiles.size() == (5 if encounter == "elite" else 1), "all followers render " + context)
			for tile in tiles:
				var caption := tile.get("detail_label") as Label
				_check(caption != null and tile.get_global_rect().encloses(caption.get_global_rect()), str(tile.name) + " caption fully inside tile " + context)
				if tile.name == "OstyFollower":
					_check(caption != null and caption.text == "生命 27", "Osty's exact current life is visible " + context)
			for key in ["HandArea", "EndTurnButton", "EnemyTarget_%d" % (ui.game.state.enemies.size() - 1)]:
				var control := ui.find_child(key, true, false) as Control
				_check(control != null and bounds.encloses(control.get_global_rect()), key + " remains in viewport " + context)


func _capture() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		_fixture()
		await _settle()
		await _snapshot("battle-%dx%d" % [dimensions.x, dimensions.y])
		_card(0).mouse_entered.emit()
		await create_timer(0.2).timeout
		await _snapshot("hover-%dx%d" % [dimensions.x, dimensions.y])
		ui.game.state.room = "reward"
		ui.game.state.rewards = [{"id": "warden_01", "upgraded": false}, {"id": "warden_02", "upgraded": true}, {"id": "warden_19", "upgraded": false}]
		ui._refresh()
		await _snapshot("reward-%dx%d" % [dimensions.x, dimensions.y])
	ui.queue_free()
	await _settle()
