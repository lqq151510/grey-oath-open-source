extends SceneTree
## Real Godot controls and rendered screenshots; fixtures never open the player's save.

const UIShell = preload("res://tests/ui_shell.gd")
const Rules = preload("res://core/game_engine.gd")
const OUTPUT := "res://docs/evidence/tactics-20261104"
var ui: UIShell
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var layouts: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func _settle() -> void:
	for ignored in 5:
		await process_frame


func _idle() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not ui.combat_busy, "combat animation completes within seven seconds")
	await _settle()


func _node(node_name: String) -> Control:
	return ui.find_child(node_name, true, false) as Control


func _press(node_name: String) -> void:
	var button := _node(node_name) as Button
	_check(button != null and not button.disabled, "enabled action exists: " + node_name)
	if button != null and not button.disabled:
		button.pressed.emit()


func _card(id: String) -> Dictionary:
	return {"id": id, "upgraded": false}


func _fixture(role: String = "warden", hand_count: int = 5) -> void:
	ui._clear(ui.overlay)
	ui.game = Rules.new("")
	ui.game.new_run(role, 729)
	ui.game.enter_node(1)
	ui.game.profile.settings.combat_speed = 2.0
	ui.game.profile.settings.music = false
	ui.game.profile.settings.sound = false
	ui.game.profile.settings.reduced_motion = true
	ui.game.state.relics = []
	ui.game.state.status = {}
	ui.game.state.hp = 90
	ui.game.state.max_hp = 90
	ui.game.state.energy = 3
	ui.game.state.block = 0
	ui.game.state.orbs = []
	ui.game.state.hand = []
	ui.game.state.draw = []
	ui.game.state.discard = []
	ui.game.state.exhaust = []
	for index in hand_count:
		ui.game.state.hand.append(_card("warden_01" if index % 2 == 0 else "warden_02"))
	for ignored in 8:
		ui.game.state.draw.append(_card("warden_02"))
	ui.game.state.enemies = []
	for index in 3:
		var definition: Dictionary = ui.game.data.enemies[[0, 4, 6][index]]
		ui.game.state.enemies.append({"id": definition.id, "name": definition.name, "hp": 60, "max_hp": 60,
			"block": 0, "status": {}, "pattern": [{"intent": "攻击", "effects": [{"op": "damage", "value": 3}]}],
			"turn": 0, "intent": "攻击 3", "color": definition.color})
	ui.menu_open = false
	ui.selected_target = 0
	ui.save_warning = ""
	ui.notice = "应变战术 · 内存试玩沙盒 · 不写旅程存档"
	ui._refresh()


func _set_size(dimensions: Vector2i) -> void:
	root.size = dimensions
	# Preserve the shipped 1440 x 900 logical canvas while resizing the window.
	await _settle()


func _assert_visible(control: Control, viewport: Rect2, label: String) -> void:
	_check(control != null and control.is_visible_in_tree(), label + " exists and is visible")
	if control == null:
		return
	var rect := control.get_global_rect()
	_check(viewport.encloses(rect), label + " remains inside viewport")
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			_check(ancestor.get_global_rect().encloses(rect), label + " is not clipped by scroll viewport")
		ancestor = ancestor.get_parent()


func _test_layouts(capture: bool) -> void:
	for dimensions in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		await _set_size(dimensions)
		for role in ["warden", "ranger", "medium", "arcanist", "sister", "bellscribe", "ashlamper"]:
			_fixture(role, 10)
			ui.game.state.tactical_points = 2
			ui.game.state.status = {"strength": 3, "weak": 2, "vulnerable": 2, "dexterity": 2, "regen": 3}
			if role == "medium":
				ui.game.state.osty_hp = 10
				ui.game.state.summons = [{"power": 9, "turns": 3}, {"power": 7, "turns": 2}, {"power": 8, "turns": 1}]
			ui._refresh()
			await _settle()
			var viewport := ui.get_global_rect()
			for node_name in ["TacticalBar", "TacticalPoints", "BattleTactic_strike", "BattleTactic_guard", "BattleTactic_cycle", "HandArea", "EndTurnButton", "EnemyTarget_0", "EnemyTarget_1", "EnemyTarget_2"]:
				_assert_visible(_node(node_name), viewport, "%s %s %s" % [str(dimensions), role, node_name])
			var actions := _node("TacticalActions").get_global_rect()
			var hand := _node("HandArea").get_global_rect()
			_check(not actions.intersects(hand), "tactics never overlap hand: %s %s" % [str(dimensions), role])
			_check(not _node("TacticalBar").get_global_rect().intersects(_node("BattleArena").get_global_rect()), "tactics never overlap battlefield")
			_check(not _node("BattleTactic_strike").get_global_rect().intersects(_node("BattleTactic_guard").get_global_rect()), "tactic buttons do not overlap")
			_check((_node("BattleTactic_cycle") as Button).disabled, "ten-card hand disables cycle")
			layouts.append({"size": str(dimensions), "role": role, "tactics": str(actions), "hand": str(hand)})
			if capture and role in ["warden", "medium"]:
				await _capture("tactics-%s-%dx%d" % [role, dimensions.x, dimensions.y])


func _test_play_sequence() -> void:
	await _set_size(Vector2i(1280, 800))
	_fixture()
	await _settle()
	_check(ui.game._save_path.is_empty(), "fixture uses memory-only save")
	ui.game.state.chapter = 3
	ui._refresh()
	await _settle()
	_check((_node("BattleTactic_strike") as Button).text.contains("12伤害"), "chapter three strike button shows scaled damage")
	_check((_node("BattleTactic_guard") as Button).text.contains("13格挡"), "chapter three guard button shows scaled block")
	ui.game.state.chapter = 0
	ui._refresh()
	await _settle()
	var before_drag := JSON.stringify(ui.game.state)
	ui.drag_card(_node("HandCard_0").get_global_rect().get_center(), _node("TacticalBar").get_global_rect().get_center())
	await _settle()
	_check(JSON.stringify(ui.game.state) == before_drag and not ui.combat_busy, "dropping a card on the tactics strip cancels without firing a tactic")
	for id in ["strike", "guard", "cycle"]:
		_check((_node("BattleTactic_" + id) as Button).disabled, "zero points disable " + id)
	for expected in [0, 1, 2]:
		var hand := _node("HandCard_0")
		var target := _node("EnemyTarget_0")
		ui.drag_card(hand.get_global_rect().get_center(), target.get_global_rect().get_center())
		await _idle()
		_check(int(ui.game.state.tactical_points) == expected, "attack-skill-attack drag produces expected points %d" % expected)
	_check((_node("TacticalPoints") as Label).text.contains("2 / 3"), "earned points appear on meter")
	_press("EnemyTarget_1")
	await _settle()
	_check((_node("BattleTactic_strike") as Button).tooltip_text.contains(str(ui.game.state.enemies[1].name)), "strike tooltip follows selected target")
	ui._clear(ui.overlay)
	var hp: int = ui.game.state.enemies[1].hp
	var energy: int = ui.game.state.energy
	_press("BattleTactic_strike")
	_check(ui.combat_busy, "strike starts presentation input lock")
	_check(int(ui.game.state.enemies[1].hp) == hp - 6 and int(ui.game.state.tactical_points) == 0, "strike hits chosen enemy and spends once")
	var committed := JSON.stringify(ui.game.state)
	ui._use_tactic("strike")
	ui._use_tactic("guard")
	ui._end_turn()
	_check(JSON.stringify(ui.game.state) == committed, "rapid tactics and end-turn cannot commit during animation")
	await _idle()
	_check(int(ui.game.state.energy) == energy and bool(ui.game.state.tactical_used), "strike consumes no energy and retains used flag")
	_check((_node("TacticalHint") as Label).text.contains("已用"), "used tactic status is visible")
	for id in ["strike", "guard", "cycle"]:
		_check((_node("BattleTactic_" + id) as Button).disabled, "used turn disables " + id)
	ui.game.state.tactical_points = 2
	_press("EndTurnButton")
	await _idle()
	_check(not bool(ui.game.state.tactical_used) and not (_node("BattleTactic_guard") as Button).disabled, "new turn restores tactic use while keeping banked points")
	var block: int = ui.game.state.block
	_press("BattleTactic_guard")
	await _idle()
	_check(int(ui.game.state.block) == block + 7 and int(ui.game.state.tactical_points) == 0, "guard button applies seven block once")


func _test_cycle_and_rejections(capture: bool) -> void:
	_fixture("ranger", 2)
	ui.game.state.tactical_points = 2
	ui.game.state.draw = [_card("ranger_08"), _card("warden_02")]
	ui._refresh()
	await _settle()
	_press("BattleTactic_cycle")
	await _idle()
	_check(int(ui.game.state.pending_discard) == 1 and ui.game.state.hand.size() == 4, "cycle draws two then opens one discard")
	_check(ui.overlay.get_child_count() > 0, "discard choice overlay opens")
	for id in ["strike", "guard", "cycle"]:
		_check((_node("BattleTactic_" + id) as Button).disabled, "pending discard disables " + id)
	if capture:
		await _capture("tactics-discard-1280x800")
	var candidates := ui.overlay.find_children("*", "Button", true, false)
	var discarded := false
	for candidate in candidates:
		if candidate.has_node("CardVisual"):
			candidate.pressed.emit()
			discarded = true
			break
	_check(discarded, "discard modal contains a real card button")
	await _idle()
	_check(int(ui.game.state.pending_discard) == 0 and ui.game.state.hand.size() == 3 and ui.overlay.get_child_count() == 0, "discard click resolves and returns to battle")
	_check(int(ui.game.state.tactical_points) == 0, "cycle and discard do not refund or generate points")

	_fixture("warden", 9)
	ui.game.state.tactical_points = 2
	ui._refresh()
	await _settle()
	_check((_node("BattleTactic_cycle") as Button).disabled and (_node("BattleTactic_cycle") as Button).tooltip_text.contains("空位"), "nine-card hand explains insufficient space")
	_fixture("warden", 2)
	ui.game.state.tactical_points = 2
	ui.game.state.draw = [_card("warden_01")]
	ui._refresh()
	await _settle()
	_check((_node("BattleTactic_cycle") as Button).disabled and (_node("BattleTactic_cycle") as Button).tooltip_text.contains("可抽牌不足"), "insufficient draw supply is explained")
	ui.game.state.room = "map"
	ui._refresh()
	await _settle()
	_check(_node("BattleTactic_strike") == null, "leaving battle removes tactical actions")
	var before := JSON.stringify(ui.game.state)
	ui._use_tactic("guard")
	_check(JSON.stringify(ui.game.state) == before, "stale tactical callback outside battle has no effect")


func _capture(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	var picture := root.get_texture().get_image()
	_check(picture.save_png(path) == OK, "screenshot saved: " + label)
	screenshots.append(path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.title = "灰誓 · 应变战术验收沙盒（不写存档）"
	ui = UIShell.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	var capture := "--capture" in OS.get_cmdline_user_args()
	if "--demo" in OS.get_cmdline_user_args():
		await _set_size(Vector2i(1280, 800))
		_fixture()
		print("TACTICS_DEMO_READY memory-only; drag attack-skill-attack to earn two points")
		return
	await _test_layouts(capture)
	if capture:
		await _set_size(Vector2i(1280, 800))
		_fixture("ranger", 2)
		ui.game.state.tactical_points = 2
		ui._refresh()
		await _capture("tactics-ready-1280x800")
		ui.game.use_tactic("cycle")
		ui._refresh()
		await _capture("tactics-discard-1280x800")
		_fixture("warden", 4)
		ui.game.state.chapter = 3
		ui.game.state.tactical_points = 2
		ui.game.state.tactical_last_type = "skill"
		ui._refresh()
		await _capture("tactics-chapter3-1280x800")
	else:
		await _test_play_sequence()
		await _test_cycle_and_rejections(false)
	var report := {"checks": checks, "failures": failures, "screenshots": screenshots, "layouts": layouts,
		"mode": "native rendering of deterministic gameplay fixtures" if capture else "headless script-driven pointer/Button actions",
		"save_path": "empty (memory only)", "physical_mouse_verified": false}
	var file := FileAccess.open(OUTPUT + ("/ui-capture.json" if capture else "/ui-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TACTICS_UI checks=", checks, " failures=", failures.size())
	ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)
