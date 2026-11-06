extends SceneTree
## Verifies the two supplied designs resolve at runtime and records native
## screenshots: masked bellscribe portrait and the ch1_normal_02 skeleton.

const UIShell = preload("res://tests/ui_shell.gd")
const Rules = preload("res://core/game_engine.gd")
const RoleArt = preload("res://ui/role_art.gd")
const Actor = preload("res://ui/combat_actor.gd")
const OUTPUT := "res://docs/evidence/character-art-20261104"

var ui
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var resolved := {}
var alpha_reports := {}


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func _settle() -> void:
	for ignored in 6:
		await process_frame


func _capture(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	_check(root.get_texture().get_image().save_png(path) == OK, "native screenshot saved: " + label)
	screenshots.append(path)


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.title = "灰誓 · 原创角色植入验收"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_check_assets()
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()

	ui.menu_open = true
	ui.menu_page = "roles"
	ui.selected_role = "bellscribe"
	ui._refresh()
	await _capture("role-select-bellscribe")

	ui._show_role_guide("bellscribe")
	await _capture("role-guide-bellscribe")
	ui._clear(ui.overlay)
	await _settle()

	ui.game = Rules.new("")
	var started: Dictionary = ui.game.start_tutorial("sister")
	_check(bool(started.get("ok", false)), "sister tutorial starts: " + str(started.get("message", "")))
	ui.menu_open = false
	ui.save_warning = ""
	ui.notice = "教学关 · 枯骨哨兵立绘验收（内存沙盒，不写存档）"
	ui._refresh()
	await _settle()
	_check(str(ui.game.state.room) == "battle", "tutorial entered battle")
	_check(ui.game.state.enemies.size() == 1 and str(ui.game.state.enemies[0].id) == "ch1_normal_02", "tutorial fields ch1_normal_02")
	var actor = ui.combat_actors.get("enemy:0", null)
	_check(_actor_has_art(actor), "battle actor draws the skeleton portrait")
	if actor != null and actor.get("role_art") != null:
		resolved["enemy_art"] = actor.role_art.resource_path
	await _capture("tutorial-battle-skeleton")

	ui.game = Rules.new("")
	ui.game.new_run("bellscribe", 4711)
	ui.game.enter_node(1)
	var definition := {}
	for candidate in ui.game.data.enemies:
		if str(candidate.id) == "ch1_normal_02":
			definition = candidate
			break
	_check(not definition.is_empty(), "catalog defines ch1_normal_02")
	if not definition.is_empty():
		ui.game.state.enemies = [{"id": definition.id, "name": definition.name, "hp": definition.hp,
			"max_hp": definition.hp, "block": 0, "status": {}, "pattern": definition.pattern.duplicate(true),
			"turn": 0, "intent": "攻击 6", "color": definition.color}]
	if ui.game.has_method("_update_intents"):
		ui.game._update_intents()
	ui.selected_target = 0
	ui.menu_open = false
	ui.notice = "原创角色对照：回响抄钟人 × 枯骨哨兵（内存沙盒，不写存档）"
	ui._refresh()
	await _settle()
	_check(str(ui.game.state.room) == "battle", "bellscribe fixture entered battle")
	_check(_actor_has_art(ui.combat_actors.get("player", null)), "bellscribe battle actor draws the masked portrait")
	_check(_actor_has_art(ui.combat_actors.get("enemy:0", null)), "skeleton battle actor draws its portrait")
	await _capture("battle-bellscribe-vs-skeleton")

	var report := {"checks": checks, "failures": failures, "screenshots": screenshots, "resolved": resolved,
		"portrait_alpha": alpha_reports}
	var file := FileAccess.open(OUTPUT + "/insertion-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CHARACTER_ART_INSERTION_RESULT " + JSON.stringify(report))
	ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)


func _actor_has_art(actor) -> bool:
	if actor == null:
		return false
	if actor.get("role_art") != null:
		return true
	# 3D 立绘（ui/three_d/actor_view.gd）不画 2D role_art，改校验它已按角色/敌人建好造型。
	if not actor.has_method("get_impact_position"):
		return false
	return float(actor.get("height")) > 0.0 or str(actor.get("role_id")) != ""


func _check_assets() -> void:
	for path in ["res://assets/art/enemies/ch1_normal_02.png", "res://assets/art/roles/bellscribe.png"]:
		_check(ResourceLoader.exists(path), "asset exists: " + path)
	var portrait := load("res://assets/art/enemies/ch1_normal_02.png") as Texture2D
	_check(portrait != null and portrait.get_size() == Vector2(240, 280), "enemy portrait canvas is 240x280")
	var bell := RoleArt.texture_for("bellscribe")
	_check(bell != null, "bellscribe resolves a portrait")
	if bell != null:
		resolved["bellscribe_art"] = bell.resource_path
		_check(bell.resource_path.ends_with("assets/art/roles/bellscribe.png"), "bellscribe uses the delivered masked portrait")
	for role in ["bellscribe", "sister", "arcanist", "medium"]:
		var role_texture := RoleArt.texture_for(role)
		_check(role_texture != null and role_texture.resource_path.ends_with("assets/art/roles/%s.png" % role),
			role + " resolves an independent transparent portrait, not the lineup atlas")
		_check_portrait_alpha("res://assets/art/roles/%s.png" % role, role)
	var ash := RoleArt.texture_for("ashlamper")
	_check(ash != null, "ashlamper resolves a portrait")
	if ash != null:
		resolved["ashlamper_art"] = ash.resource_path
		_check(ash.resource_path.ends_with("concepts/ashlamper-concept-2026-11-04.png"), "ashlamper uses the canonical concept portrait")
		_check_portrait_alpha(ash.resource_path, "ashlamper")
	for file in ["res://data/art_enemies.json", "res://data/art_monsters_v094.json", "res://data/monster_art_ids.json"]:
		var data = JSON.parse_string(FileAccess.get_file_as_string(file))
		_check(data != null, "JSON parses: " + file)
		if data != null:
			_check("ch1_normal_02" in JSON.stringify(data), file + " indexes ch1_normal_02")
	var probe := Actor.new()
	root.add_child(probe)
	probe.setup({"id": "ch1_normal_02", "name": "枯骨哨兵", "hp": 26}, {"id": "ch1_normal_02", "name": "枯骨哨兵", "kind": "normal", "color": "#a99c7d"})
	_check(probe.role_art != null, "isolated combat actor resolves the skeleton portrait")
	if probe.role_art != null:
		resolved["probe_art"] = probe.role_art.resource_path
	probe.queue_free()


func _check_portrait_alpha(path: String, label: String) -> void:
	_check(ResourceLoader.exists(path), "portrait exists: " + path)
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	_check(texture != null, label + " loads as a texture")
	if texture == null:
		return
	var image := texture.get_image()
	var size := image.get_size()
	var clear_corners := 0
	for point in [Vector2i(0, 0), Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), Vector2i(size.x - 1, size.y - 1)]:
		if image.get_pixel(point.x, point.y).a < 0.01:
			clear_corners += 1
	_check(clear_corners == 4, "%s margins are transparent (corners clear: %d/4)" % [label, clear_corners])
	var sampled := 0
	var near_white := 0
	for y in range(0, size.y, 4):
		for x in range(0, size.x, 4):
			var color := image.get_pixel(x, y)
			if color.a <= 0.8:
				continue
			sampled += 1
			if minf(color.r, minf(color.g, color.b)) > 0.9:
				near_white += 1
	var ratio := 0.0 if sampled == 0 else float(near_white) / float(sampled)
	alpha_reports[label] = {
		"path": path,
		"size": "%dx%d" % [size.x, size.y],
		"sampled_opaque": sampled,
		"near_white_opaque": near_white,
		"near_white_ratio": snappedf(ratio, 0.0001),
	}
	_check(ratio < 0.02, "%s keeps under 2%% near-white opaque pixels (got %.3f%%)" % [label, ratio * 100.0])
