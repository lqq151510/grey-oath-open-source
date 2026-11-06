extends SceneTree
## Card illustration evidence capture.
## Memory-only fixture (Rules.new("")): never reads or writes user://save.json.
##
## Run:
##   .tools/Godot.app/Contents/MacOS/Godot --path . -s tests/card_art_capture.gd -- --capture
##
## Output (docs/evidence/card-art-20261104/):
##   battle-<role>-<w>x<h>.png   five roles x two viewports, real hand cards in a battle shell
##   gallery-<w>x<h>.png         complete 20-card gallery fitted into the requested viewport
##   gallery-<w>x<H>.png         same gallery at native 230x300 card size (taller than the viewport)
##   capture.json                paths, pixel sizes, byte sizes, per-card illustration state
## Exit code is non-zero whenever any check fails.

const Rules = preload("res://core/game_engine.gd")
const CARD_ART_SCRIPT := "res://ui/card_art.gd"
const OUTPUT := "res://docs/evidence/card-art-20261104"
const OUTPUT_RELATIVE := "docs/evidence/card-art-20261104"
const ROLES := ["warden", "ranger", "sister", "arcanist", "medium"]
const VIEWPORTS := [Vector2i(1440, 900), Vector2i(1280, 800)]
const CARD_SIZE := Vector2(230, 300)
const GAP := 14
const ROW_GAP := 18
const LABEL_WIDTH := 150.0
const GALLERY_PAD := 26.0
const MIN_ENERGY := 3
const GALLERY_INK := Color("0d0b09")
const GALLERY_LABEL := Color("9c8f7c")
const ART_OK_TONE := Color("9ec6a4")
const ART_FALLBACK_TONE := Color("d9a06a")

var ui
var checks := 0
var failures: Array = []
var warnings: Array = []
var images: Array = []
var role_reports: Array = []
var card_reports: Dictionary = {}
var started_at := ""
var command := ""


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _warn(message: String) -> void:
	if message not in warnings:
		warnings.append(message)
		printerr("WARN: " + message)


func _settle() -> void:
	for ignored in range(4):
		await process_frame


func _run() -> void:
	started_at = Time.get_datetime_string_from_system(false, true)
	var user_args := OS.get_cmdline_user_args()
	command = ".tools/Godot.app/Contents/MacOS/Godot --path . -s tests/card_art_capture.gd"
	if not user_args.is_empty():
		command += " -- " + " ".join(user_args)
	root.size = VIEWPORTS[0]
	root.title = "灰誓 · 卡牌插画证据（内存沙盒，不写存档）"
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	print("CAPTURE_BOOT godot=", Engine.get_version_info().get("string", "?"),
		" project=", ProjectSettings.get_setting("application/config/name", ""))
	_check(is_instance_valid(ui.content), "ui shell built")
	_check(ui.game._save_path.is_empty(), "fixture persistence disabled (empty save path)")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))

	var args := OS.get_cmdline_user_args()
	if "--demo" in args:
		print("CARD_ART_DEMO_READY memory-only")
		return

	await _capture_battles()
	await _capture_gallery()

	var report := _report()
	_check(_write_report(report), "capture.json is writable")
	var written := _file_bytes(OUTPUT + "/capture.json")
	_check(written > 0, "capture.json written (%d bytes)" % written)
	report["capture_json_bytes"] = written
	_write_report(report)  # refresh counters so the file agrees with stdout
	print("CAPTURE_RESULT " + JSON.stringify(_summary(report)))
	ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- battle fixtures

func _starter_ids(role: String) -> Array:
	var result: Array = []
	for entry in ui.game.role_data(role).get("starter_cards", []):
		var id := str(entry)
		if id not in result:
			result.append(id)
	return result


func _battle_lane() -> int:
	var lanes: Array = ui.game.available_nodes()
	if lanes.is_empty():
		return 0
	var row: Array = ui.game.state.map[0]
	for lane in lanes:
		if int(lane) < 0 or int(lane) >= row.size():
			continue
		var node: Dictionary = row[int(lane)]
		if str(node.get("kind", "")) in ["normal", "elite", "boss"]:
			return int(lane)
	return int(lanes[0])


func _hand_fixture(role: String) -> Array:
	var ids := _starter_ids(role)
	var hand: Array = []
	for id in ids:
		hand.append({"id": str(id), "upgraded": false})
	hand.append({"id": str(ids[0]), "upgraded": false})
	return hand


func _enemy_fixture() -> Array:
	var pool: Array = ui.game.data.enemies
	var result: Array = []
	for index in range(2):
		var definition: Dictionary = pool[(index * 7) % pool.size()]
		var hp := 60 + index * 15
		result.append({
			"id": str(definition.get("id", "fixture_%d" % index)),
			"kind": "normal", "escort": false,
			"name": str(definition.get("name", "试炼守卫")),
			"hp": hp, "max_hp": hp, "block": 0, "status": {},
			"pattern": definition.get("pattern", []).duplicate(true),
			"turn": 0, "intent": "攻击 6",
			"color": str(definition.get("color", "#c7a279")),
		})
	return result


func _battle_fixture(role: String) -> void:
	ui.game = Rules.new("")
	_check(ui.game._save_path.is_empty(), "%s battle fixture keeps persistence disabled" % role)
	var started: Dictionary = ui.game.new_run(role, 42)
	_check(bool(started.get("ok", false)), "isolated run starts for %s" % role)
	ui.game.enter_node(_battle_lane())
	ui.game.state.room = "battle"
	ui.game.state.turn = 1
	ui.game.state.block = 0
	ui.game.state.energy = 4
	ui.game.state.hand = _hand_fixture(role)
	ui.game.state.enemies = _enemy_fixture()
	ui.menu_open = false
	ui.menu_page = "title"
	ui.save_warning = ""
	ui.selected_target = 0
	ui.notice = "卡牌插画证据 · 内存沙盒，不写旅程存档"
	ui._refresh()


func _hand_card(index: int) -> Button:
	return ui.find_child("HandCard_%d" % index, true, false) as Button


func _living_enemies() -> int:
	var living := 0
	for enemy in ui.game.state.enemies:
		if int(enemy.get("hp", 0)) > 0:
			living += 1
	return living


func _capture_battles() -> void:
	for role in ROLES:
		var hand_ids: Array = []
		var energy := 0
		var living := 0
		for viewport_size: Vector2i in VIEWPORTS:
			root.size = viewport_size
			await _settle()
			_battle_fixture(str(role))
			await _settle()
			hand_ids = []
			for entry in ui.game.state.hand:
				hand_ids.append(str(entry.get("id", "")))
			energy = int(ui.game.state.energy)
			living = _living_enemies()
			var suffix := "%s/%dx%d" % [role, viewport_size.x, viewport_size.y]
			_check(root.size == viewport_size, "%s viewport is %dx%d (got %dx%d)" % [
				suffix, viewport_size.x, viewport_size.y, root.size.x, root.size.y])
			_check(str(ui.game.state.room) == "battle", "%s is in battle room" % suffix)
			var rendered := 0
			for index in range(ui.game.state.hand.size()):
				if _hand_card(index) != null:
					rendered += 1
			_check(rendered == ui.game.state.hand.size(),
				"%s renders %d/%d hand cards" % [suffix, rendered, ui.game.state.hand.size()])
			for id in _starter_ids(str(role)):
				_check(str(id) in hand_ids, "%s hand contains starter card %s" % [suffix, id])
			_check(energy >= MIN_ENERGY, "%s energy >= %d (got %d)" % [suffix, MIN_ENERGY, energy])
			_check(living > 0, "%s has at least one living enemy" % suffix)
			var file_name := "battle-%s-%dx%d.png" % [role, viewport_size.x, viewport_size.y]
			var info: Dictionary = await _save_window_image(file_name, viewport_size)
			info["kind"] = "battle"
			info["role"] = role
			images.append(info)
		role_reports.append({
			"id": role,
			"name": str(ui.game.role_data(str(role)).get("name", role)),
			"starter_cards": _starter_ids(str(role)),
			"hand": hand_ids,
			"energy": energy,
			"living_enemies": living,
		})


# ---------------------------------------------------------------- gallery

func _gallery_content() -> Control:
	var content := VBoxContainer.new()
	content.name = "GalleryContent"
	content.add_theme_constant_override("separation", ROW_GAP)
	content.add_child(_gallery_header())
	for role in ROLES:
		content.add_child(_gallery_row(str(role)))
	return content


func _gallery_header() -> Control:
	var header := VBoxContainer.new()
	header.name = "GalleryHeader"
	header.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = "灰誓 · 起始牌插画"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("f1e7d3"))
	title.add_theme_font_override("font", ui.heading_font)
	header.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "20 张起始牌 · 5 职业 × 4 列 · 真实 CardVisual 渲染（230×300）· 每格标注插画是否生效"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", GALLERY_LABEL)
	header.add_child(subtitle)
	return header


func _gallery_row(role: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "GalleryRow_%s" % role
	row.add_theme_constant_override("separation", GAP)
	var role_data: Dictionary = ui.game.role_data(role)
	var tag := VBoxContainer.new()
	tag.name = "GalleryRoleLabel_%s" % role
	tag.custom_minimum_size = Vector2(LABEL_WIDTH, CARD_SIZE.y)
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tag.add_theme_constant_override("separation", 2)
	var role_name := Label.new()
	role_name.text = str(role_data.get("name", role))
	role_name.add_theme_font_size_override("font_size", 22)
	role_name.add_theme_color_override("font_color", Color(str(role_data.get("color", "#d7b879"))))
	role_name.add_theme_font_override("font", ui.heading_font)
	tag.add_child(role_name)
	var role_id := Label.new()
	role_id.text = role
	role_id.add_theme_font_size_override("font_size", 14)
	role_id.add_theme_color_override("font_color", GALLERY_LABEL)
	tag.add_child(role_id)
	var role_title := Label.new()
	role_title.text = str(role_data.get("title", ""))
	role_title.add_theme_font_size_override("font_size", 13)
	role_title.add_theme_color_override("font_color", Color("6f6759"))
	role_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_title.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	tag.add_child(role_title)
	row.add_child(tag)
	for card_id in _starter_ids(role):
		row.add_child(_gallery_cell(role, str(card_id)))
	return row


func _gallery_cell(role: String, card_id: String) -> Control:
	var cell := VBoxContainer.new()
	cell.name = "GalleryCell_%s" % card_id
	cell.add_theme_constant_override("separation", 4)
	var button: Button = ui._card(cell, {"id": card_id, "upgraded": false},
		func() -> void: pass, CARD_SIZE, "preview")
	button.name = "GalleryCard_%s" % card_id
	button.disabled = false
	button.focus_mode = Control.FOCUS_NONE
	var visual = button.get_node("CardVisual")
	var has_art: bool = visual.illustration != null
	_record_card(role, card_id, visual)
	var caption := Label.new()
	caption.name = "GalleryCaption_%s" % card_id
	caption.text = "%s · %s" % [card_id, "插画 ART" if has_art else "回退 FALLBACK"]
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", ART_OK_TONE if has_art else ART_FALLBACK_TONE)
	cell.add_child(caption)
	return cell


func _record_card(role: String, card_id: String, visual) -> void:
	var definition: Dictionary = ui.game.card_data(card_id)
	var art := str(definition.get("art", ""))
	var has_art: bool = visual.illustration != null
	var texture_size := Vector2i.ZERO
	if has_art:
		var texture_extent: Vector2 = visual.illustration.get_size()
		texture_size = Vector2i(int(texture_extent.x), int(texture_extent.y))
	var entry := {
		"id": card_id,
		"role": role,
		"name": str(definition.get("name", "")),
		"type": str(definition.get("type", "")),
		"art": art,
		"art_file_exists": not art.is_empty() and FileAccess.file_exists(art),
		"art_loadable": not art.is_empty() and ResourceLoader.exists(art),
		"illustration": has_art,
		"texture_size": [texture_size.x, texture_size.y],
	}
	if card_reports.has(card_id):
		var previous: Dictionary = card_reports[card_id]
		_check(bool(previous.get("illustration", false)) == has_art,
			"illustration state stable across gallery renders for %s" % card_id)
		return
	card_reports[card_id] = entry
	if art.is_empty():
		_check(false, "card %s declares an art path" % card_id)
	elif not bool(entry.get("art_file_exists", false)):
		_warn("card %s art file missing: %s" % [card_id, art])
	elif not has_art:
		_warn("card %s art file unresolved (not imported as Texture2D yet): %s" % [card_id, art])


func _capture_gallery() -> void:
	var viewport := SubViewport.new()
	viewport.name = "GalleryViewport"
	viewport.size = Vector2i(VIEWPORTS[0].x, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var background := ColorRect.new()
	background.name = "GalleryBackground"
	background.color = GALLERY_INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	var content := _gallery_content()
	content.theme = ui.theme
	viewport.add_child(content)
	await _settle()
	var content_size := content.get_combined_minimum_size()
	content.size = content_size
	await _settle()
	print("GALLERY_CONTENT %.0fx%.0f" % [content_size.x, content_size.y])

	var native_height := int(ceil(content_size.y)) + int(GALLERY_PAD * 2.0)
	for viewport_size: Vector2i in VIEWPORTS:
		var width: int = viewport_size.x
		var file_name := "gallery-%dx%d.png" % [width, native_height]
		content.scale = Vector2.ONE
		content.position = Vector2((float(width) - content_size.x) * 0.5, GALLERY_PAD)
		viewport.size = Vector2i(width, native_height)
		var info: Dictionary = await _save_viewport_image(viewport, file_name, Vector2i(width, native_height))
		info["kind"] = "gallery-native"
		info["card_size"] = [int(CARD_SIZE.x), int(CARD_SIZE.y)]
		images.append(info)

	for viewport_size: Vector2i in VIEWPORTS:
		var factor: float = minf(
			(float(viewport_size.x) - GALLERY_PAD * 2.0) / maxf(1.0, content_size.x),
			(float(viewport_size.y) - GALLERY_PAD * 2.0) / maxf(1.0, content_size.y))
		factor = minf(factor, 1.0)
		content.scale = Vector2(factor, factor)
		content.position = Vector2(
			(float(viewport_size.x) - content_size.x * factor) * 0.5,
			(float(viewport_size.y) - content_size.y * factor) * 0.5)
		viewport.size = viewport_size
		var file_name := "gallery-%dx%d.png" % [viewport_size.x, viewport_size.y]
		var info: Dictionary = await _save_viewport_image(viewport, file_name, viewport_size)
		info["kind"] = "gallery-fitted"
		info["scale"] = snappedf(factor, 0.001)
		info["native_content_size"] = [int(ceil(content_size.x)), int(ceil(content_size.y))]
		images.append(info)

	_check(card_reports.size() == 20, "gallery covers 20 starter cards (got %d)" % card_reports.size())
	var visuals := content.find_children("CardVisual", "", true, false)
	_check(visuals.size() == 20, "gallery instantiates 20 CardVisual nodes (got %d)" % visuals.size())
	var missing := 0
	for visual in visuals:
		if visual.illustration == null:
			missing += 1
	if missing > 0:
		_warn("%d/20 gallery cards fall back to the crest placeholder (illustration null)" % missing)
	viewport.queue_free()
	await _settle()


# ---------------------------------------------------------------- images and report

func _viewport_image(viewport: SubViewport) -> Image:
	var fallback: Image = null
	for attempt in range(6):
		await _settle()
		await RenderingServer.frame_post_draw
		var texture := viewport.get_texture()
		if texture == null:
			continue
		var image := texture.get_image()
		if image == null:
			continue
		fallback = image
		if image.get_width() == viewport.size.x and image.get_height() == viewport.size.y:
			return image
	return fallback


func _save_window_image(file_name: String, expected: Vector2i) -> Dictionary:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return _write_image(image, file_name, expected)


func _save_viewport_image(viewport: SubViewport, file_name: String, expected: Vector2i) -> Dictionary:
	var image: Image = await _viewport_image(viewport)
	return _write_image(image, file_name, expected)


func _write_image(image: Image, file_name: String, expected: Vector2i) -> Dictionary:
	var relative := "%s/%s" % [OUTPUT_RELATIVE, file_name]
	if image == null:
		_check(false, "%s captured an image" % file_name)
		return {"file": relative, "width": 0, "height": 0, "bytes": 0, "error": "null image"}
	var path := "%s/%s" % [OUTPUT, file_name]
	var error := image.save_png(path)
	_check(error == OK, "%s saved (error %d)" % [file_name, error])
	var bytes := _file_bytes(path)
	_check(bytes > 0, "%s is a non-empty file (got %d bytes)" % [file_name, bytes])
	_check(image.get_width() == expected.x and image.get_height() == expected.y,
		"%s is %dx%d (got %dx%d)" % [file_name, expected.x, expected.y, image.get_width(), image.get_height()])
	print("CAPTURE %s %dx%d %d bytes" % [relative, image.get_width(), image.get_height(), bytes])
	return {
		"file": relative,
		"width": image.get_width(),
		"height": image.get_height(),
		"bytes": bytes,
		"requested_size": [expected.x, expected.y],
	}


func _file_bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size


func _write_report(report: Dictionary) -> bool:
	report["checks"] = checks
	report["failures"] = failures
	report["warnings"] = warnings
	var file := FileAccess.open(OUTPUT + "/capture.json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true


func _report() -> Dictionary:
	var cards: Array = []
	var illustrated := 0
	var files_present := 0
	for role in ROLES:
		for card_id in _starter_ids(str(role)):
			if card_reports.has(str(card_id)):
				var entry: Dictionary = card_reports[str(card_id)]
				cards.append(entry)
				if bool(entry.get("illustration", false)):
					illustrated += 1
				if bool(entry.get("art_file_exists", false)):
					files_present += 1
	return {
		"generated_at": started_at,
		"raw_args": OS.get_cmdline_args(),
		"command": command,
		"project": str(ProjectSettings.get_setting("application/config/name", "")),
		"godot_version": str(Engine.get_version_info().get("string", "")),
		"mode": "windowed native rendering; memory-only fixtures (save path empty)",
		"save_path": "empty (memory-only)",
		"output_dir": OUTPUT_RELATIVE,
		"viewport_sizes": [[VIEWPORTS[0].x, VIEWPORTS[0].y], [VIEWPORTS[1].x, VIEWPORTS[1].y]],
		"card_visual_script": "res://ui/card_visual.gd",
		"card_art_script": CARD_ART_SCRIPT,
		"card_art_script_present": ResourceLoader.exists(CARD_ART_SCRIPT, "GDScript"),
		"notes": [
			"gallery-<w>x<h>.png 是按请求尺寸整幅缩放（kind=gallery-fitted，记录 scale 与 native_content_size）；5 行 x 300px 无法在 900/800 高度内按原生尺寸排下，故另出 gallery-<w>x<H>.png 原生 230x300（kind=gallery-native）作为插画可读性证据。",
			"illustration 为 null 时卡面走 ui/card_visual.gd 的 crest 回退；ui/card_art.gd 存在后重跑即可得到非空插画。",
		],
		"roles": role_reports,
		"cards": cards,
		"art_summary": {
			"total": cards.size(),
			"illustration_non_empty": illustrated,
			"illustration_fallback": cards.size() - illustrated,
			"art_files_present": files_present,
			"art_files_missing": cards.size() - files_present,
		},
		"images": images,
		"checks": checks,
		"failures": failures,
		"warnings": warnings,
	}


func _summary(report: Dictionary) -> Dictionary:
	var battle := 0
	var gallery := 0
	var gallery_heights: Array = []
	for info in images:
		if str(info.get("kind", "")) == "battle":
			battle += 1
		else:
			gallery += 1
			if info.get("height") not in gallery_heights:
				gallery_heights.append(info.get("height"))
	return {
		"ok": failures.is_empty(),
		"images": images.size(),
		"battle_images": battle,
		"gallery_images": gallery,
		"gallery_heights": gallery_heights,
		"illustration_non_empty": int(report.art_summary.illustration_non_empty),
		"art_total": int(report.art_summary.total),
		"checks": checks,
		"failures": failures.size(),
		"warnings": warnings.size(),
		"output": OUTPUT_RELATIVE,
	}
