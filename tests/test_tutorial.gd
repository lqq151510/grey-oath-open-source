extends SceneTree
## Run headless for input and save checks. Use -- --capture-dir PATH with a native window.

const UIShell = preload("res://tests/ui_shell.gd")
const Rules = preload("res://core/game_engine.gd")

var ui: UIShell
var checks := 0
var failures: Array[String] = []
var capture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var capture_arg := args.find("--capture-dir")
	if capture_arg >= 0 and capture_arg + 1 < args.size():
		capture_dir = args[capture_arg + 1]
	var save_path := OS.get_temp_dir().path_join("grey-oath-tutorial-%d.json" % OS.get_process_id())
	var journey := Rules.new(save_path)
	journey.profile.settings.combat_speed = 2.0
	_check(journey.new_run("warden", 729).ok, "fixture can start a journey")
	_check(journey.enter_node(1).ok, "fixture can save an active battle")
	var snapshot := FileAccess.get_file_as_bytes(save_path)
	var backup := FileAccess.get_file_as_bytes(save_path + ".bak")
	var state := journey.state.duplicate(true)
	var profile := journey.profile.duplicate(true)
	_check(not snapshot.is_empty() and not backup.is_empty(), "fixture wrote save and backup")
	_check(not journey.start_tutorial().ok, "a persistent engine rejects training setup")

	root.size = Vector2i(1280, 800)
	ui = UIShell.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.game = journey
	ui._refresh()
	await _settle()
	await _click("TutorialButton")
	await _check_menu_layout()
	await _capture("role-tutorial-menu")
	await _click("TutorialRecommendedStart")
	_check(ui.game != journey and ui.game._save_path.is_empty(), "tutorial has its own engine")
	_check(ui.game.profile.settings == journey.profile.settings, "tutorial uses the player's settings")
	_check(ui.game.state.turn == 1 and ui.game.state.energy == 3, "practice starts with a full first turn")
	_check(ui.game.state.enemies.size() == 1 and ui.game.state.enemies[0].intent == "攻击 5", "first intent is a readable single hit")
	await _check_layout()
	await _capture("role-tutorial-warden")

	await _drag(0, "BattleArena")
	_check(ui.game.state.block == 7 and ui.game.state.energy == 2, "dragging defense grants block and spends energy")
	_check("铁甲·重斩" in _hint(), "the next prompt advances past the defense card")
	await _drag(0, "EnemyTarget_0")
	_check(ui.game.state.enemies[0].hp == 18 and ui.game.state.energy == 1, "the first strike includes the opening strength")
	_check("结束回合" in _hint(), "the next prompt teaches ending a turn")
	await _key(KEY_E)
	_check(ui.game.state.turn == 2 and ui.game.state.energy == 3 and ui.game.state.block == 0, "end-turn refreshes hand, energy and block")
	_check(ui.game.state.hp == ui.game.state.max_hp and "未失去生命" in _hint(), "the first hit was fully blocked")
	await _play("warden_04")
	_check(ui.game.state.status.strength == 4, "Battle Trance increases strength from 1 to 4")
	await _play("warden_01")
	_check(ui.game.state.enemies[0].hp == 6, "strength makes the next strike deal 12")
	await _play("warden_01")
	_check(ui.game.state.room == "victory" and not ui.game.state.active, "two-round route reaches tutorial victory")
	_check(ui.game.profile.total_wins == 0 and ui.game.profile.history.is_empty(), "practice victory awards no journey progress")
	await _capture("role-tutorial-result")
	await _click("TutorialContinueButton")
	_check(ui.game == journey and not ui.menu_open and ui.game.state.room == "battle", "completion resumes the original battle")
	_check(journey.state == state and journey.profile == profile, "journey state and profile are untouched")
	_check(FileAccess.get_file_as_bytes(save_path) == snapshot, "save bytes are unchanged")
	_check(FileAccess.get_file_as_bytes(save_path + ".bak") == backup, "backup bytes are unchanged")

	await _key(KEY_ESCAPE)
	await _click("TutorialButton")
	await _click("TutorialRole_warden")
	await _click("EndTurnButton")
	_check(ui.game.state.turn == 2 and "失去 5 生命" in _hint(), "ending early gives accurate feedback and keeps practice playable")
	await _click("RestartTutorialButton")
	_check(ui.game.state.turn == 1 and ui.game.state.hp == ui.game.state.max_hp, "restart restores a clean encounter")
	await _click("ExitTutorialButton")
	_check(ui.game == journey and ui.menu_open and ui.menu_page == "tutorial", "exiting returns to the tutorial entry and restores the journey")
	_check(journey.state == state and journey.profile == profile, "restart and exit do not mutate the journey")
	_check(FileAccess.get_file_as_bytes(save_path) == snapshot and FileAccess.get_file_as_bytes(save_path + ".bak") == backup,
		"restart and exit do not rewrite save files")

	await _other_roles()
	_check(ui.game == journey and journey.state == state and journey.profile == profile,
		"all seven lessons preserve the original journey")
	_check(FileAccess.get_file_as_bytes(save_path) == snapshot and FileAccess.get_file_as_bytes(save_path + ".bak") == backup,
		"all seven lessons preserve save and backup bytes")

	# Exercise the defeat result with a one-HP fixture, then the retry button.
	ui.game = Rules.new("")
	ui.game.profile.settings.combat_speed = 2.0
	await _click("TutorialRole_warden")
	ui.game.state.hp = 1
	await _click("EndTurnButton")
	_check(ui.game.state.room == "defeat" and ui.game.profile.history.is_empty(), "defeat uses the isolated tutorial result")
	await _click("RetryTutorialButton")
	_check(ui.game.state.room == "battle" and ui.game.state.turn == 1, "defeat screen can retry")
	await _key(KEY_ESCAPE)
	_check(ui.game._save_path.is_empty() and ui.menu_page == "tutorial", "Escape leaves training for its entry")
	await _click("TutorialRole_medium")
	await _play("medium_03")
	await _play("medium_01")
	await _play("medium_04")
	await _key(KEY_E)
	await _click("TutorialContinueButton")
	_check(ui.menu_open and ui.menu_page == "roles" and not ui.game.state.active and ui.selected_role == "medium",
		"a new player can select the practiced traveler")
	await _click("PracticeSelectedRole")
	_check(ui.game.state.role == "medium" and ui.game.state.turn == 1, "the traveler selection page opens the matching lesson")
	await _click("ExitTutorialButton")

	ui.queue_free()
	await _settle()
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path + ".bak")
	print("TUTORIAL_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _other_roles() -> void:
	await _open_role("ranger")
	_check(ui.game.state.hand.size() == 7, "the hunter draws two extra opening cards")
	await _play("ranger_04")
	_check("先完成主动弃牌选择" in _hint(), "the tutorial pauses its next-step advice while an active discard is pending")
	var blocked_hand_card := _node("HandCard_0") as Button
	_check(blocked_hand_card != null and blocked_hand_card.disabled and "先完成主动弃牌选择" in str(blocked_hand_card.get_meta("unavailable_reason", "")),
		"hand cards clearly explain that discarding must finish before more cards are played")
	var choice := _node("DiscardCard_0")
	_check(choice != null and "推荐弃置" in choice.get_node("CardVisual/Availability").text, "the discard window points out the Sly card")
	await _key(KEY_ESCAPE)
	_check(ui.overlay.get_child_count() == 0, "Escape closes the discard window without discarding a card")
	blocked_hand_card = _node("HandCard_0") as Button
	_check(blocked_hand_card != null and blocked_hand_card.disabled and "先完成主动弃牌选择" in str(blocked_hand_card.get_meta("unavailable_reason", "")),
		"closing the discard window keeps unavailable hand cards disabled with a clear reason")
	await _click("EndTurnButton")
	choice = _node("DiscardCard_0")
	_check(choice != null, "the end-turn control reopens the required discard window")
	await _capture("role-tutorial-ranger-discard")
	await _click("DiscardCard_0")
	_check(ui.game.state.enemies[0].hp == 20 and ui.game.state.energy == 2, "active discard plays Sly for free")
	await _play("ranger_03")
	_check(ui.game.state.enemies[0].status.weak == 1 and ui.game.state.energy == 2, "Hamstring weakens the target for zero energy")
	await _play("ranger_01")
	await _key(KEY_E)
	await _play("ranger_01")
	await _play("ranger_01")
	await _finish_role("ranger")

	await _open_role("sister")
	_check(ui.game.state.orbs.size() == 1, "the robot starts with lightning")
	await _play("sister_03")
	_check(ui.game.state.orbs.size() == 2, "Channel adds a second orb")
	await _play("sister_04")
	_check(ui.game.state.orbs.size() == 1 and ui.game.state.enemies[0].hp == 11, "Dualcast evokes one orb twice")
	await _play("sister_02")
	await _key(KEY_E)
	_check(ui.game.state.enemies[0].hp == 8 and ui.game.state.hp == 23, "the remaining orb attacks passively and Block absorbs seven of eight damage")
	await _play("sister_01")
	await _finish_role("sister")

	await _open_role("arcanist")
	_check(ui.game.state.stars == 3, "the regent starts with three Stars")
	await _play("arcanist_04")
	_check(ui.game.state.stars == 5 and ui.game.state.blade == 6, "Forge creates and strengthens the sword")
	await _play("arcanist_03")
	_check(ui.game.state.stars == 3 and ui.game.state.energy == 2, "Falling Star spends Stars separately from energy")
	await _key(KEY_E)
	_check(ui.game.state.hand[0].id == "token_blade", "the sword is retained across turns")
	await _play("token_blade")
	_check(ui.game.state.enemies[0].hp == 8, "the forged sword hits for 16 before enemy block")
	await _play("arcanist_01")
	await _finish_role("arcanist")

	await _open_role("medium")
	await _play("medium_03")
	_check(ui.game.state.osty_hp == 7 and ui.game.state.enemies[0].hp == 18, "Osty grows and attacks with Bodyguard")
	await _play("medium_01")
	await _play("medium_04")
	_check(ui.game.state.enemies[0].status.doom == 10 and ui.game.state.room == "battle", "Doom waits until the enemy acts")
	await _key(KEY_E)
	_check(ui.game.state.hp == 24 and ui.game.state.osty_hp == 0, "Osty absorbed the attack before Doom resolved")
	await _finish_role("medium")

	await _open_role("bellscribe")
	_check(ui.game.state.status.resonance == 2, "the scribe starts with two Resonance")
	await _play("bellscribe_02")
	_check(ui.game.state.status.resonance == 3, "Brace raises Resonance to the threshold")
	await _play("bellscribe_03")
	_check(ui.game.state.enemies[0].hp == 32 and ui.game.state.status.resonance == 0, "Resonance is spent to add eight damage")
	await _play("bellscribe_01")
	await _key(KEY_E)
	_check(ui.game.state.status.resonance == 1, "Resonance survives the turn boundary")
	for id in ["bellscribe_01", "bellscribe_01", "bellscribe_03"]:
		await _play(id)
	_check(ui.game.state.status.resonance == 0, "the second Chime spends the Resonance saved across turns")
	await _finish_role("bellscribe")

	await _open_role("ashlamper")
	await _play("ashlamper_01")
	_check(ui.game.state.enemies[0].status.cinder == 2, "Needle applies two Cinder")
	await _play("ashlamper_04")
	_check(ui.game.state.enemies[0].status.cinder == 5, "Cinder stacks on the same target")
	await _capture("role-tutorial-ashlamper-ignite")
	await _play("ashlamper_03")
	_check(ui.game.state.enemies[0].hp == 22 and not ui.game.state.enemies[0].status.has("cinder"), "Ignite consumes five Cinder for ten additional damage")
	await _key(KEY_E)
	for id in ["ashlamper_01", "ashlamper_01", "ashlamper_03"]:
		await _play(id)
	await _finish_role("ashlamper")


func _open_role(role_id: String) -> void:
	await _click("TutorialRole_" + role_id)
	_check(ui.game.state.role == role_id and ui.game.state.turn == 1, role_id + " enters its own encounter")
	var card := _node("HandCard_0")
	_check(card != null and card.get_node("CardVisual/Availability").text == "建议先打这张", role_id + " marks its opening card")
	await _check_layout()
	await _capture("role-tutorial-" + role_id)


func _finish_role(role_id: String) -> void:
	_check(ui.game.state.room == "victory" and ui.game.profile.total_wins == 0, role_id + " completes without journey progress")
	await _click("SwitchTutorialRole")


func _play(id: String) -> void:
	for index in ui.game.state.hand.size():
		var instance: Dictionary = ui.game.state.hand[index]
		if instance.id == id:
			var card: Dictionary = ui.game.card_view(instance)
			await _drag(index, "EnemyTarget_0" if card.requires_target else "BattleArena")
			return
	_check(false, "expected card in hand: " + id)


func _check_menu_layout() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		await _settle()
		for role in ui.game.data.roles:
			var control := _node("TutorialRole_" + str(role.id))
			_check(control != null and root.get_visible_rect().encloses(control.get_global_rect()),
				"%s tutorial entry fits at %s" % [role.id, dimensions])


func _node(node_name: String) -> Control:
	return ui.find_child(node_name, true, false) as Control


func _hint() -> String:
	var hint := _node("TutorialBattleHint") as Label
	return hint.text if hint != null else ""


func _click(node_name: String) -> void:
	var button := _node(node_name) as Button
	_check(button != null and not button.disabled, "clickable button: " + node_name)
	if button != null and not button.disabled:
		var point := button.get_global_rect().get_center()
		ui.push_pointer_button(point, true)
		ui.push_pointer_button(point, false)
	await _wait_idle()


func _drag(index: int, target_name: String) -> void:
	var card := _node("HandCard_%d" % index)
	var target := _node(target_name)
	_check(card != null and target != null, "drag starts at a card and ends at " + target_name)
	if card != null and target != null:
		ui.drag_card(card.get_global_rect().get_center(), target.get_global_rect().get_center())
	await _wait_idle()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await _wait_idle()


func _check_layout() -> void:
	for dimensions in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = dimensions
		await _settle()
		for node_name in ["TutorialBattleHint", "HandArea", "EndTurnButton", "EnemyIntent_0"]:
			var control := _node(node_name)
			_check(control != null and root.get_visible_rect().encloses(control.get_global_rect()),
				"%s fits at %s" % [node_name, dimensions])


func _capture(label_text: String) -> void:
	if capture_dir.is_empty():
		return
	await process_frame
	RenderingServer.force_draw(false)
	var output := capture_dir.path_join(label_text + ".png")
	_check(root.get_texture().get_image().save_png(output) == OK, "capture " + label_text)


func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while ui.combat_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not ui.combat_busy, "combat animation completed")
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)
