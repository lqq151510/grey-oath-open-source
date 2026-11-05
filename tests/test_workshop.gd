extends SceneTree
## Exercises authoring, data validation, actual combat and the ordinary save boundary.

const Rules = preload("res://core/game_engine.gd")
const Workshop = preload("res://core/workshop_pack.gd")
const UIShell = preload("res://tests/ui_shell.gd")

var ui: UIShell
var checks := 0
var failures := 0
var capture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var capture_arg := args.find("--capture-dir")
	if capture_arg >= 0 and capture_arg + 1 < args.size():
		capture_dir = args[capture_arg + 1]
	_test_pack_and_rules()
	await _test_editor_and_save()
	print("WORKSHOP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_pack_and_rules() -> void:
	var game := Rules.new("")
	var pack := Workshop.default_pack(game)
	pack.role.name = "测试旅者"
	pack.role.hp = 37
	pack.enemy = {"name": "测试守卫", "hp": 27, "attack": 6, "block": 4}
	pack.item = {"name": "护盾试剂", "kind": "block", "amount": 5}
	pack.card = {"name": "钟摆", "kind": "attack", "cost": 0, "amount": 9}
	pack.talent = {"name": "旧誓", "kind": "strength", "amount": 3}
	pack.build.starter_cards = ["warden_02", "warden_02", "warden_01", "warden_01", Workshop.CARD_ID]
	var from_file := Workshop.parse_text(JSON.stringify(pack), game)
	_check(from_file.get("ok", false) and from_file.get("pack") == pack, "JSON roundtrip retains all six definitions")
	var invalid := pack.duplicate(true)
	invalid.card.amount = 0.5
	_check(not game.start_workshop(invalid).get("ok", false) and not game.state.active, "fractional values are rejected before starting a run")
	invalid = pack.duplicate(true)
	invalid.enemy["script"] = "res://anything.gd"
	_check(not Workshop.validate(invalid, game).ok, "unknown executable fields are rejected")
	invalid = pack.duplicate(true)
	invalid.build.starter_cards[0] = "ranger_01"
	_check(not Workshop.validate(invalid, game).ok, "deck rejects a card outside the selected base's starter list")
	invalid.build.starter_cards[0] = "warden_01"
	invalid.build.starter_cards[4] = "warden_01"
	_check(not Workshop.validate(invalid, game).ok, "deck requires at least one signature card")
	_check(not Workshop.parse_text("x".repeat(Workshop.MAX_BYTES + 1), game).ok, "oversized pack is rejected before parsing")
	if not _check(game.start_workshop(pack).get("ok", false), "valid pack starts a trial"):
		return
	_check(game.state.role == "warden" and game.role_data("warden").name == "测试旅者" and game.state.hp == 37, "trial hero uses custom name and HP with the original class")
	_check(game.state.enemies[0].name == "测试守卫" and game.state.enemies[0].intent == "攻击 6", "custom enemy opens with the configured attack")
	_check(game.state.status.strength == 4, "starting talent stacks with original Warden strength")
	_check(game.state.deck.map(func(instance): return instance.id) == pack.build.starter_cards, "custom build is used as the real starting deck")
	pack.card.amount = 39
	var signature := _card_index(game.state.hand)
	if _check(signature >= 0 and game.card_view(game.state.hand[signature]).name == "钟摆", "signature card is in the opening hand"):
		_check(game.play_card(signature, 0).ok and game.state.energy == 3 and game.state.enemies[0].hp == 14, "custom card deals base damage plus talent and class bonuses at its configured cost")
	_check(game.use_potion(0).ok and game.state.block == 5 and game.state.potions.is_empty(), "custom potion grants block and is consumed")
	_check(game.end_turn().ok and game.state.hp == 36 and game.state.enemies[0].intent == "格挡 4", "configured attack resolves and enemy telegraphs its custom guard")
	_check(game.end_turn().ok and game.state.enemies[0].block == 4 and game.state.enemies[0].intent.begins_with("攻击"), "enemy guard resolves before cycling to its attack")
	_check(Rules.new("").card_data(Workshop.CARD_ID).is_empty(), "signature card cannot leak into another engine")


func _test_editor_and_save() -> void:
	var save_path := OS.get_temp_dir().path_join("grey-oath-workshop-test-%d.json" % OS.get_process_id())
	var normal := Rules.new(save_path)
	normal.profile.settings.music = false
	normal.profile.settings.sound = false
	normal.profile.settings.combat_speed = 2.0
	normal.profile.settings.reduced_motion = true
	_check(normal.new_run("warden", 14).ok and normal.enter_node(0).ok, "ordinary journey and backup are established")
	var snapshot := FileAccess.get_file_as_bytes(save_path)
	var backup := FileAccess.get_file_as_bytes(save_path + ".bak")
	var normal_state := normal.state.duplicate(true)
	var normal_profile := normal.profile.duplicate(true)
	_check(not snapshot.is_empty() and not backup.is_empty(), "ordinary save bytes exist before trial")
	_check(not normal.start_workshop(Workshop.default_pack(normal)).ok, "persistent engine rejects workshop content")
	root.size = Vector2i(1280, 800)
	ui = UIShell.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.game = normal
	ui._refresh()
	await _settle()
	if await _press("WorkshopButton"):
		await _check_editor_flow(normal)
	_check(ui.game == normal and normal.state == normal_state and normal.profile == normal_profile, "exit restores the original journey and its progression")
	_check(FileAccess.get_file_as_bytes(save_path) == snapshot and FileAccess.get_file_as_bytes(save_path + ".bak") == backup, "ordinary save and backup stay byte-identical")
	ui.queue_free()
	await _settle()
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path + ".bak")


func _check_editor_flow(normal) -> void:
	var entry := _node("WorkshopEditor")
	if not _check(entry != null, "main menu opens the workshop editor"):
		return
	var trial := _node("WorkshopTrialButton")
	_check(trial != null and root.get_visible_rect().encloses(trial.get_global_rect()), "playtest button fits the 1280×800 window")
	await _capture("workshop-editor")
	var card_name := _node("WorkshopCardName") as LineEdit
	var card_amount := _node("WorkshopCardAmount") as SpinBox
	var enemy_hp := _node("WorkshopEnemyHP") as SpinBox
	if not _check(card_name != null and card_amount != null and enemy_hp != null, "editor offers real card and monster fields"):
		return
	card_name.text = "试炼重击"
	card_name.text_changed.emit(card_name.text)
	card_amount.value = 20
	enemy_hp.value = 10
	await _check_file_roundtrip(normal)
	if not await _press("WorkshopTrialButton"):
		return
	if not _check(ui.game != normal and ui.game.state.encounter_kind == "workshop", "edited pack starts an isolated workshop battle"):
		return
	_check(_node("TacticalBar") != null and _node("WorkshopReturnButton") != null, "trial retains combat tactics and can return to the editor")
	await _capture("workshop-battle")
	var index := _card_index(ui.game.state.hand)
	if not _check(index >= 0 and ui.game.card_view(ui.game.state.hand[index]).name == "试炼重击", "the edited card appears in the actual first hand"):
		await _press("WorkshopReturnButton")
		return
	var hand_card := _node("HandCard_%d" % index)
	var target := _node("EnemyTarget_0")
	if _check(hand_card != null and target != null, "custom card and enemy have interactive battle controls"):
		ui.drag_card(hand_card.get_global_rect().get_center(), target.get_global_rect().get_center())
		await _settle()
		var deadline := Time.get_ticks_msec() + 5000
		while ui.combat_busy and Time.get_ticks_msec() < deadline:
			await process_frame
		await _settle()
	_check(ui.game.state.room == "victory" and _node("WorkshopTrialResult") != null, "playing the edited card reaches the workshop result")
	_check(ui.game.profile.history.is_empty() and ui.game.profile.total_wins == 0, "trial victory awards no campaign progress")
	await _capture("workshop-result")
	if await _press("WorkshopEditButton"):
		var restored := _node("WorkshopCardName") as LineEdit
		_check(restored != null and restored.text == "试炼重击", "returning to the editor preserves the authored draft")


func _check_file_roundtrip(normal) -> void:
	var path := OS.get_temp_dir().path_join("grey-oath-workshop-pack-%d.json" % OS.get_process_id())
	if not await _press("WorkshopExportButton"):
		return
	var export_dialog := ui.find_child("WorkshopExportDialog", true, false) as FileDialog
	if not _check(export_dialog != null, "export opens a file chooser"):
		return
	export_dialog.hide()
	export_dialog.file_selected.emit(path)
	await _settle()
	var saved := Workshop.parse_text(FileAccess.get_file_as_string(path), normal)
	_check(saved.get("ok", false) and saved.pack.card.name == "试炼重击", "export writes an editable pack containing the latest form values")
	if await _press("WorkshopExportButton"):
		export_dialog = ui.find_child("WorkshopExportDialog", true, false) as FileDialog
		if export_dialog != null:
			var bytes := FileAccess.get_file_as_bytes(normal._save_path)
			export_dialog.hide()
			export_dialog.file_selected.emit(normal._save_path)
			await _settle()
			var status := _node("WorkshopStatus") as Label
			_check(status != null and "存档" in status.text and FileAccess.get_file_as_bytes(normal._save_path) == bytes, "export refuses to overwrite a journey save even when it is explicitly selected")
	var field := _node("WorkshopCardName") as LineEdit
	field.text = "尚未导入"
	field.text_changed.emit(field.text)
	if await _press("WorkshopImportButton"):
		var import_dialog := ui.find_child("WorkshopImportDialog", true, false) as FileDialog
		if _check(import_dialog != null, "import opens a file chooser"):
			import_dialog.hide()
			import_dialog.file_selected.emit(path)
			await _settle()
			var restored := _node("WorkshopCardName") as LineEdit
			_check(restored != null and restored.text == "试炼重击", "import refreshes the editor with the exported values")
	DirAccess.remove_absolute(path)


func _card_index(hand: Array) -> int:
	return hand.find_custom(func(instance): return instance.id == Workshop.CARD_ID)


func _node(node_name: String) -> Control:
	return ui.find_child(node_name, true, false) as Control


func _press(node_name: String) -> bool:
	var button := _node(node_name) as Button
	if not _check(button != null and not button.disabled, "action available: " + node_name):
		return false
	var point := button.get_global_rect().get_center()
	ui.push_pointer_button(point, true)
	ui.push_pointer_button(point, false)
	await _settle()
	return true


func _settle() -> void:
	for ignored in 5:
		await process_frame


func _capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "capture " + name)


func _check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)
	return ok
