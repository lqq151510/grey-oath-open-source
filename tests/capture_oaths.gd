extends SceneTree
## Visual evidence for 长夜誓约 (oaths, daily vow, elite affixes, score).
## Run WITHOUT --headless: ./.tools/Godot.app/Contents/MacOS/Godot --path . --script tests/capture_oaths.gd

const OUTPUT := "res://docs/evidence/oaths-20261105"
var ui
var shots: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _settle() -> void:
	for ignored in 8:
		await process_frame


func _wait(frames: int) -> void:
	for ignored in frames:
		await process_frame


func _shot(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	var image := root.get_texture().get_image()
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		failures.append("save failed: " + label)
		printerr("FAIL: save ", label)
	else:
		shots.append(label)


func _fresh_run(oath_id: String = "") -> void:
	ui.game = load("res://core/game_engine.gd").new("")
	ui.game.profile.total_wins = 100
	if not ui.game.new_run("warden", 729, 0, "", oath_id).get("ok", false):
		failures.append("new_run failed")
	ui.menu_open = false
	ui.save_warning = ""
	ui.notice = ""


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 900)
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.game.profile.settings.merge({"music": false, "sound": false}, true)
	ui._sync_audio()
	await _settle()
	await _shot("screen-01-title-daily-vow")

	ui.menu_page = "daily"
	ui._refresh()
	await _shot("screen-02-daily-vow")

	ui.menu_page = "roles"
	ui._refresh()
	await _settle()
	await _shot("screen-03-oaths-offer")
	var card = ui.find_child("OathCard_1", true, false)
	if card is Button:
		card.pressed.emit()
		await _settle()
		await _shot("screen-04-oath-selected")
	else:
		failures.append("OathCard_1 missing")

	root.size = Vector2i(1280, 800)
	ui._refresh()
	await _settle()
	await _shot("screen-05-oaths-1280")
	root.size = Vector2i(1440, 900)

	_fresh_run("blood")
	ui._refresh()
	await _settle()
	await _shot("screen-06-map-oath-chip")

	ui.game.state.chapter = 0
	ui.game.state.row = 0
	ui.game.state.lane = 1
	ui.game.state.encounter_kind = "elite"
	ui.game._start_battle("elite")
	ui.menu_open = false
	ui._refresh()
	await _wait(90)
	await _shot("screen-07-elite-affix")

	ui.game.state.room = "victory"
	ui.game.state.score = 1234
	ui.game.state.daily = true
	ui.game.state.daily_key = str(ui.game.daily_view().key)
	ui._refresh()
	await _settle()
	await _shot("screen-08-victory-score")

	print("CAPTURE_OATHS shots=", shots.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
