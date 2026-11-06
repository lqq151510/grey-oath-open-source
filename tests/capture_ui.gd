extends SceneTree
## Lead visual capture harness for the StS-style rebuild.
## Run WITHOUT --headless: .tools/Godot.app/Contents/MacOS/Godot --path . --script tests/capture_ui.gd

const OUTPUT := "res://docs/evidence/ui-rebuild-20261104"
var ui
var shots: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _settle() -> void:
	for ignored in 6:
		await process_frame


func _wait(frames: int) -> void:
	for ignored in frames:
		await process_frame


func _shot(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		failures.append("save failed: " + label)
		printerr("FAIL: save ", label)
	else:
		shots.append(label)


func fresh_run(role_id: String = "warden") -> void:
	ui.game = load("res://core/game_engine.gd").new("")
	ui.game.profile.total_wins = 100
	if not ui.game.new_run(role_id, 729).get("ok", false):
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
	await _settle()
	await _shot("screen-01-menu")

	ui.menu_page = "roles"
	ui._refresh()
	await _shot("screen-02-roles")
	ui.menu_page = "menu"

	fresh_run()
	ui._refresh()
	await _shot("screen-03-map")

	ui._enter_node(1)
	await _wait(90)
	await _shot("screen-04-battle")

	for room in ["reward", "shop", "rest", "event", "treasure", "victory", "defeat"]:
		ui.game.state.room = room
		if room == "reward":
			ui.game.state.rewards = ui.game.state.deck.slice(0, 3)
		if room == "shop":
			ui.game._make_shop()
		if room == "event":
			ui.game.state.event = ui.game.data.events[0]
		ui._refresh()
		await _shot("screen-05-" + room)

	ui.game.state.room = "map"
	ui._refresh()
	await _settle()
	ui._show_deck("view")
	await _shot("screen-06-deck")
	ui._clear(ui.overlay)
	ui._show_relics()
	await _shot("screen-07-relics")
	ui._clear(ui.overlay)

	root.size = Vector2i(1280, 800)
	fresh_run("medium")
	ui._refresh()
	await _settle()
	ui._enter_node(1)
	await _wait(90)
	await _shot("screen-08-battle-1280")

	print("CAPTURE shots=", shots.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
