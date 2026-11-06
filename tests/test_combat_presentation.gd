extends SceneTree
## Isolated rules and UI fixture. --capture renders evidence; --demo accepts real input.

const Rules = preload("res://core/game_engine.gd")
const Actor = preload("res://ui/combat_actor.gd")
const OUTPUT := "res://docs/evidence/combat-effects-20261103"
var ui
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var recording := false


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func _settle() -> void:
	for ignored in 4:
		await process_frame


func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 6500
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not ui.combat_busy, "feedback finishes within 6.5 seconds")
	await _settle()


func _wait_until(condition: Callable, timeout_msec: int = 2500) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _enemy(definition: Dictionary) -> Dictionary:
	return {"id": definition.id, "name": definition.name, "hp": 60, "max_hp": 60, "block": 0,
		"status": {}, "pattern": [{"intent": "攻击", "effects": [{"op": "damage", "value": 6}]}],
		"turn": 0, "intent": "攻击 6", "color": definition.color}


func _fixture(count: int = 1) -> void:
	ui.game = Rules.new("")
	ui.game.new_run("warden", 42)
	ui.game.enter_node(1)
	ui.game.state.enemies = []
	for index in count:
		ui.game.state.enemies.append(_enemy(ui.game.data.enemies[[0, 4, 6][index]]))
	ui.game.state.hand = [{"id": "warden_01", "upgraded": false}, {"id": "warden_02", "upgraded": false},
		{"id": "warden_01", "upgraded": false}, {"id": "warden_03", "upgraded": false}, {"id": "warden_01", "upgraded": false}]
	ui.game.state.energy = 3
	ui.game.state.potions = [str(ui.game.data.potions[0].id)]
	ui.menu_open = false
	ui.selected_target = 0
	ui.save_warning = ""
	ui.notice = "交锋演示 · 内存沙盒，不写旅程存档 · Esc 可跳过动画"
	ui._refresh()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	ui._unhandled_key_input(event)


func _run() -> void:
	root.title = "灰誓 · 敌人与交锋验收（不写存档）"
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	_fixture(3)
	await _settle()
	if "--demo" in OS.get_cmdline_user_args():
		print("COMBAT_DEMO_READY memory-only")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	else:
		await _test_status_effects()
		await _test_behaviors()
		await _test_layout_and_actors()
		await _test_fixed_player_visibility()
	var report := {"checks": checks, "failures": failures, "screenshots": screenshots,
		"mode": "native rendering" if "--capture" in OS.get_cmdline_user_args() else "script-driven UI; no physical mouse evidence", "save_path": "empty (memory only)"}
	var file := FileAccess.open(OUTPUT + ("/capture-results.json" if "--capture" in OS.get_cmdline_user_args() else "/presentation-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("COMBAT_PRESENTATION_RESULT " + JSON.stringify(report))
	ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)


func _test_status_effects() -> void:
	_fixture(1)
	ui.game.state.status = {"weak": 2, "regen": 2}
	ui.game.state.enemies[0].status = {"vulnerable": 3, "regen": 1}
	ui._refresh()
	await _settle()
	var player_actor = ui.combat_actors.get("player")
	var enemy_actor = ui.combat_actors.get("enemy:0")
	var player_overlay = player_actor.get("_effect_overlay") if player_actor != null else null
	var enemy_overlay = enemy_actor.get("_effect_overlay") if enemy_actor != null else null
	_check(player_overlay != null and int(player_overlay.statuses.get("weak", 0)) == 2, "3D player overlay retains active weak status")
	_check(enemy_overlay != null and int(enemy_overlay.statuses.get("vulnerable", 0)) == 3 and int(enemy_overlay.statuses.get("regen", 0)) == 1, "3D enemy overlay retains vulnerable and regen statuses")
	if player_actor != null and player_overlay != null:
		player_actor.play_status_effect("weak")
		player_actor.play_heal()
		_check(float(player_overlay.flashes.get("weak", 0.0)) > 0.0, "weak status starts a transient visual pulse")
		_check(float(player_overlay.heal_time) > 0.0, "healing starts the green recovery animation")
	if enemy_actor != null and enemy_overlay != null:
		enemy_actor.play_status_effect("vulnerable")
		enemy_actor.play_status_effect("regen")
		_check(float(enemy_overlay.flashes.get("vulnerable", 0.0)) > 0.0 and float(enemy_overlay.flashes.get("regen", 0.0)) > 0.0, "vulnerable and regen start their distinct pulses")
	_fixture(3)
	await _settle()


func _test_behaviors() -> void:
	_fixture(3)
	ui.game.state.enemies[1].status.weak = 2
	ui.game.state.enemies[1].pattern[0].effects[0].hits = 2
	ui.game.state.enemies[1].pattern[0].effects.append({"op": "poison", "value": 2})
	ui.game.state.enemies[1].pattern.append({"intent": "缝誓", "effects": [{"op": "heal_ally", "value": 11, "fallback_block": 7}]})
	ui.game._update_intents()
	ui._refresh()
	await _settle()
	_check(ui.game._save_path.is_empty(), "memory-only fixture")
	_check(ui.combat_actors.size() == 4, "player and three enemy actors exist")
	_check(ui.combat_effects.mouse_filter == Control.MOUSE_FILTER_IGNORE, "effects never capture clicks")
	var before_inspection := JSON.stringify(ui.game.state)
	var target_center: Vector2 = ui.find_child("EnemyTarget_1", true, false).get_global_rect().get_center()
	var intent_center: Vector2 = ui.find_child("EnemyIntent_1", true, false).get_global_rect().get_center()
	ui.push_pointer_button(target_center, true)
	ui.push_pointer_drag(target_center, intent_center)
	ui.push_pointer_button(intent_center, false)
	await _settle()
	_check(ui.overlay.get_child_count() == 0 and ui.selected_target == 0, "releasing on a strip after pressing elsewhere does not inspect")
	for strip_name in ["EnemyIntent_1", "EnemyStatus_1"]:
		var center: Vector2 = ui.find_child(strip_name, true, false).get_global_rect().get_center()
		ui.push_pointer_button(center, true)
		ui.push_pointer_button(center, false)
		await _settle()
		_check(ui.overlay.find_child("EnemyDetailScroll", true, false) != null and ui.selected_target == 0, strip_name + " opens enemy details without switching targets")
		_key(KEY_ESCAPE)
		await _settle()
	ui.push_pointer_button(target_center, true)
	ui.push_pointer_button(target_center, false)
	await _settle()
	_check(ui.selected_target == 1 and ui.combat_actors["enemy:1"].selected, "enemy selection follows click")
	var enemy_detail = ui.overlay.find_child("EnemyDetailScroll", true, false)
	var enemy_intent = ui.overlay.find_child("EnemyIntentDetails", true, false)
	var status_panel = ui.overlay.find_child("CurrentStatusDetails", true, false)
	var first_move = ui.overlay.find_child("EnemyPatternStep_0", true, false)
	var second_move = ui.overlay.find_child("EnemyPatternStep_1", true, false)
	_check(enemy_detail != null and status_panel != null and "虚弱 · 剩余 2 回合" in str(status_panel.get_child(1).text), "enemy click opens current status with its value")
	_check(status_panel != null and enemy_intent != null and status_panel.get_parent().get_index() < enemy_intent.get_parent().get_index(), "current statuses appear above action forecast")
	_check(enemy_intent != null and "施毒 2" in str(enemy_intent.get_child(1).text) and "绕过格挡" in str(enemy_intent.get_child(2).text), "enemy action explains its displayed effects")
	_check(enemy_intent != null and "攻击 4×2" in str(enemy_intent.get_child(1).text), "next-action forecast reflects Weak and hit count")
	_check(first_move != null and "下一步" in first_move.text and "每次基础伤害 6" in first_move.text and "使你获得 2 层中毒" in first_move.text, "ordered move shows base values and target separately from the forecast")
	_check(second_move != null and "缝誓" in second_move.text and "存活同伴" in second_move.text and "自身获得 7 点格挡" in second_move.text, "support move lists healing target and block fallback")
	_check(JSON.stringify(ui.game.state) == before_inspection, "enemy inspection does not mutate combat state")
	_key(KEY_ESCAPE)
	var expected_damage: int = ui.game.preview_card(0, 1).damage
	var hp_before: int = ui.game.state.enemies[1].hp
	ui.drag_card(ui.find_child("HandCard_0", true, false).get_global_rect().get_center(),
		ui.find_child("EnemyTarget_1", true, false).get_global_rect().get_center())
	_check(ui.combat_busy, "attack enters playback lock")
	_check(ui.game.state.enemies[1].hp == hp_before - expected_damage, "one drag applies actual damage exactly once")
	var committed := JSON.stringify(ui.game.state)
	ui._play_card(0)
	ui._use_potion(0)
	ui._end_turn()
	_key(KEY_E)
	ui.find_child("EnemyTarget_2", true, false).pressed.emit()
	_check(JSON.stringify(ui.game.state) == committed, "rapid cards, potion and E cannot execute again during playback")
	_check(ui.selected_target == 1, "target does not switch during playback")
	var player_actor: Control = ui.combat_actors["player"]
	var target_actor: Control = ui.combat_actors["enemy:1"]
	_check(await _wait_until(func(): return float(player_actor.attack_time) > 0.0), "player performs attack movement")
	_check(await _wait_until(func(): return float(target_actor.hit_time) > 0.0), "target performs hit reaction")
	_check(not ui.combat_effects.effects.is_empty(), "attack and hit particles appear")
	await _wait_idle()
	_check(ui.combat_effects.effects.is_empty(), "refresh clears transient effects")
	_check(not ui.find_child("EndTurnButton", true, false).disabled, "controls unlock after playback")
	var turn_before: int = ui.game.state.turn
	ui._end_turn()
	_check(ui.game.state.turn == turn_before + 1 and ui.combat_busy, "end turn commits once before visual sequence")
	_check(ui.find_child("TurnBanner", true, false) != null, "turn-end banner precedes enemy attack")
	var enemy_actor: Control = ui.combat_actors["enemy:0"]
	player_actor = ui.combat_actors["player"]
	_check(await _wait_until(func(): return float(enemy_actor.attack_time) > 0.0), "enemy performs attack movement")
	_check(await _wait_until(func(): return float(player_actor.hit_time) > 0.0), "player performs hit reaction")
	await _wait_idle()

	_fixture(3)
	ui.game.state.hand = [{"id": "warden_06", "upgraded": false}]
	ui.game.state.energy = 5
	ui._refresh()
	await _settle()
	ui._play_card(0)
	var area_effects: Array = ui.combat_effects.effects.filter(func(effect): return effect.get("type", "") == "area")
	_check(area_effects.size() == 1 and area_effects[0].points.size() == 3, "area attack highlights every affected enemy")
	await _wait_idle()

	_fixture()
	ui.game.state.energy = 0
	ui._refresh()
	await _settle()
	committed = JSON.stringify(ui.game.state)
	ui._play_card(0)
	_check(not ui.combat_busy and ui.combat_effects.effects.is_empty(), "rejected card has no playback lock or effects")
	_check(JSON.stringify(ui.game.state) == committed, "rejected card preserves state")

	_fixture()
	await _settle()
	ui._play_card(0)
	committed = JSON.stringify(ui.game.state)
	_key(KEY_ESCAPE)
	_check(not ui.combat_busy, "Escape cancels remaining animation")
	_check(JSON.stringify(ui.game.state) == committed, "Escape preserves the already committed action")
	await create_timer(1.0).timeout
	_check(not ui.combat_busy and ui.combat_effects.effects.is_empty(), "cancelled coroutine cannot restore stale effects")

	_fixture()
	await _settle()
	ui._play_card(0)
	ui.menu_open = true
	ui._refresh()
	await create_timer(1.0).timeout
	_check(ui.menu_open and not ui.combat_busy and ui.combat_actors.is_empty(), "refresh safely cancels actor playback")

	_fixture()
	ui.game.state.enemies[0].hp = 1
	ui._refresh()
	await _settle()
	var lethal_enemy: Control = ui.combat_actors["enemy:0"]
	ui._play_card(0)
	_check(ui.game.state.room == "reward" and ui.combat_busy, "lethal attack commits reward but retains battlefield during animation")
	_check(await _wait_until(func(): return lethal_enemy.dead), "lethal enemy plays death reaction")
	await _wait_idle()
	_check(ui.combat_actors.is_empty() and ui.find_child("EndTurnButton", true, false) == null, "reward UI replaces battlefield after death")

	_fixture()
	ui.game.state.hp = 1
	ui.game.state.block = 0
	ui._refresh()
	await _settle()
	var lethal_player: Control = ui.combat_actors["player"]
	ui._end_turn()
	_check(ui.game.state.room == "defeat" and ui.combat_busy, "lethal enemy attack commits defeat while showing feedback")
	_check(await _wait_until(func(): return lethal_player.dead), "player plays death reaction")
	await _wait_idle()
	_check(ui.combat_actors.is_empty(), "defeat exits battlefield cleanly")


func _test_layout_and_actors() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		for count in [1, 3]:
			_fixture(count)
			while ui.game.state.hand.size() < 10:
				ui.game.state.hand.append({"id": "warden_01", "upgraded": false})
			ui._refresh()
			await _settle()
			var bounds: Rect2 = ui.get_global_rect()
			var details := ui.find_child("PlayerDetails", true, false) as ScrollContainer
			var vertical := details.get_v_scroll_bar()
			_check(vertical.max_value <= vertical.page + 1.0, "standard player details fit without clipped log at %s with %d enemies" % [dimensions, count])
			for key in ["EndTurnButton", "HandArea"]:
				_check(bounds.encloses(ui.find_child(key, true, false).get_global_rect()), "%s visible at %s with %d enemies" % [key, dimensions, count])
			for actor in ui.combat_actors.values():
				_check(bounds.encloses(actor.get_global_rect()), "actor visible at %s with %d enemies" % [dimensions, count])
				_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "actor children allow target click")
	var actor := Actor.new()
	ui.add_child(actor)
	var archetypes: Dictionary = {}
	for definition in ui.game.data.enemies:
		actor.setup(_enemy(definition), definition)
		_check(not actor.archetype.is_empty(), "enemy visual mapping: " + str(definition.id))
		archetypes[actor.archetype] = true
	_check(archetypes.size() >= 8, "enemy roster has at least eight distinct silhouette classes")
	for role in ui.game.data.roles:
		actor.setup({"hp": 60}, role, true)
		_check(actor.archetype == role.id, "player role visual mapping: " + str(role.id))
	actor.queue_free()
	await _settle()


func _snapshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	_check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)
	screenshots.append(path)


func _test_fixed_player_visibility() -> void:
	var roles: Array = ui.game.data.roles.duplicate(true)
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		for role in roles:
			_fixture(3)
			ui.game.state.role = str(role.id)
			ui.game.state.status = {"strength": 12, "weak": 3, "vulnerable": 4, "poison": 5, "thorns": 6, "regen": 7, "next_energy": 8}
			ui.game.state.souls = 30
			ui.game.state.marks = [1, 2, 3]
			ui.game.state.summons = [{"power": 9, "turns": 3}, {"power": 7, "turns": 2}, {"power": 8, "turns": 1}]
			ui.game.state.log = ["本测试使用较长状态与日志，检查主角形象不会随详情滚出画面。".repeat(5), "战斗记录保留完整原文，并允许玩家滚动阅读。".repeat(5)]
			ui._refresh()
			await _settle()
			var actor := ui.find_child("PlayerActor", true, false) as Control
			var details := ui.find_child("PlayerDetails", true, false) as ScrollContainer
			var bounds: Rect2 = ui.get_global_rect()
			var before: Rect2 = actor.get_global_rect()
			var context := "%s at %s" % [role.id, dimensions]
			_check(not details.is_ancestor_of(actor), "player actor outside scrolling details: " + context)
			_check(bounds.encloses(before), "complex-state player visible: " + context)
			_check(actor.archetype == role.id, "correct player role shown: " + context)
			_check(details.get_v_scroll_bar().max_value > details.get_v_scroll_bar().page, "complex-state details are scrollable: " + context)
			details.scroll_vertical = 99999
			await _settle()
			_check(details.scroll_vertical > 0, "complex-state scroll actually moved: " + context)
			_check(actor.get_global_rect() == before and bounds.encloses(actor.get_global_rect()), "player stays fixed when details scroll: " + context)


func _capture() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		_fixture(3)
		await _settle()
		var suffix := "%dx%d" % [dimensions.x, dimensions.y]
		await _snapshot("battle-" + suffix)
		ui.game.state.status = {"weak": 2, "regen": 2}
		ui.game.state.enemies[0].status = {"vulnerable": 2, "regen": 2}
		ui._refresh()
		await _settle()
		await _snapshot("status-fx-" + suffix)
		var player_actor = ui.combat_actors.get("player")
		if player_actor != null:
			player_actor.play_heal()
			ui.combat_effects.play_heal(player_actor.get_impact_position(), 6)
			await create_timer(0.08).timeout
			await _snapshot("heal-fx-" + suffix)
		_fixture(3)
		await _settle()
		if dimensions.x == 1280:
			_film()
		ui._play_card(0)
		if dimensions.x == 1280:
			# 录一段出牌特效胶片；峰值帧同时充当该尺寸的静态证据。
			await _attack_film()
		else:
			await create_timer(0.20).timeout
			await _snapshot("player-attack-" + suffix)
		await _wait_idle()
		ui._end_turn()
		await create_timer(0.22).timeout
		await _snapshot("enemy-attack-" + suffix)
		await _wait_idle()
		while recording:
			await process_frame


func _attack_film() -> void:
	var folder := "res://docs/evidence/art-pass-20261105/fx-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var peak: Image = null
	# 只靠定时器推进，不用 frame_post_draw 等信号：特效结束后窗口可能不再重绘，等信号会卡死。
	for index in 14:
		await create_timer(0.04).timeout
		var frame := root.get_texture().get_image()
		if frame == null:
			print("ATTACK_FILM skip frame ", index)
			continue
		print("ATTACK_FILM frame ", index, " ", frame.get_size())
		_check(frame.save_png(folder + "/fx-%02d.png" % index) == OK, "attack frame %d" % index)
		if index == 5:
			peak = frame.duplicate()
	if peak != null:
		_check(peak.save_png(OUTPUT + "/player-attack-1280x800.png") == OK, "attack peak still")
		screenshots.append(OUTPUT + "/player-attack-1280x800.png")


func _film() -> void:
	recording = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "/frames"))
	for index in 30:
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(OUTPUT + "/frames/frame-%03d.png" % index)
		_check(error == OK, "animation frame %d" % index)
		await create_timer(0.1).timeout
	recording = false
