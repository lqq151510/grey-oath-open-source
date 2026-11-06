extends SceneTree
## Exercises both guide entry points with an isolated in-memory game.
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await process_frame
	ui.menu_page = "roles"
	ui._refresh()
	await process_frame
	check(ui.find_child("RoleGuideSelection", true, false) != null, "selection entry exists")
	var state_before := JSON.stringify(ui.game.state)
	for role in ui.game.data.roles:
		ui._show_role_guide(str(role.id))
		await process_frame
		var portrait = ui.overlay.find_child("GuidePortrait", true, false)
		var scroll = ui.overlay.find_child("RoleGuideScroll", true, false)
		check(portrait != null and portrait.texture != null, "%s portrait" % role.id)
		check(scroll != null and scroll.get_child(0).get_child_count() >= 3, "%s sections" % role.id)
		check(JSON.stringify(ui.game.state) == state_before, "%s guide is read-only" % role.id)
		if str(role.id) == "medium" and "--capture" in OS.get_cmdline_user_args():
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/grey-oath-role-guide.png")
	ui._clear(ui.overlay)
	var result: Dictionary = ui.game.new_run("medium", 729, 0)
	check(result.get("ok", false), "start isolated run")
	var lane := 0
	for node in ui.game.state.map[0]:
		if str(node.get("kind", "")) == "battle":
			lane = int(node.lane)
			break
	ui.game.enter_node(lane)
	if ui.game.state.room != "battle":
		ui.game.state.room = "battle"
	ui.menu_open = false
	ui._refresh()
	await process_frame
	var battle_button = ui.find_child("RoleGuideBattle", true, false)
	check(battle_button != null, "battle entry exists")
	if battle_button != null:
		battle_button.pressed.emit()
		await process_frame
		check(ui.overlay.find_child("GuidePortrait", true, false) != null, "battle entry opens guide")
		ui._clear(ui.overlay)
	for window in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = window
		ui.game.state.status = {"weak": 2, "thorns": 3}
		ui.game.state.items["good_needle"] = {"remaining": 0, "progress": 0}
		ui.game.state.tactical_points = 2
		ui._refresh()
		for frame in 4: await process_frame
		var before_inspection := JSON.stringify(ui.game.state)
		var actor_center: Vector2 = ui.find_child("PlayerActor", true, false).get_global_rect().get_center()
		ui.push_pointer_button(actor_center, true)
		ui.push_pointer_button(actor_center, false)
		await process_frame
		var current = ui.overlay.find_child("PlayerCurrentEffects", true, false)
		var status = ui.overlay.find_child("CurrentStatusDetails", true, false)
		check(current != null and "能量" in str(current.get_child(1).text) and "应变 2 / 3" in str(current.get_child(1).text), "%s portrait opens current battle details" % window)
		check(status != null and "虚弱 · 剩余 2 回合" in str(status.get_child(1).text) and "荆棘 · 当前 3" in str(status.get_child(2).text), "%s portrait explains active statuses with values" % window)
		check(JSON.stringify(ui.game.state) == before_inspection, "%s portrait inspection is read-only" % window)
		ui._clear(ui.overlay)
	print("ROLE_GUIDE_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
