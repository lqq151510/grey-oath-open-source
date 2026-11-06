extends SceneTree
## 3D 角色灯光/材质真渲染特写。
## 用法：Godot --path . --script tests/actor3d_look_capture.gd -- <prefix>
## output: docs/evidence/actor3d-lighting-20261104/<prefix>-<id>.png（512×512，合到 #141a17 底）

const ActorViewScript := preload("res://ui/three_d/actor_view.gd")
const CATALOG := "res://data/catalog.json"
const OUTPUT := "res://docs/evidence/actor3d-lighting-20261104/"
const SIZE := 512
const PICKS := ["ch1_boss_12", "ch1_normal_03", "ch2_elite_10", "ch4_normal_05"]

var prefix := "shot"
var enemies: Dictionary = {}
var views: Array = []
var failures: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = str(args[0])
	_run.call_deferred()


func _run() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not (parsed is Dictionary):
		printerr("CAPTURE ERROR: catalog is not readable")
		quit(1)
		return
	for row in (parsed as Dictionary).get("enemies", []):
		enemies[str(row.get("id", ""))] = row
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 900)
	var bg := ColorRect.new()
	bg.color = Color("141a17")
	bg.size = Vector2(1440, 900)
	root.add_child(bg)

	await _capture({"id": "warden", "name": "铁甲战士", "role": "warden"},
		{"id": "warden", "name": "铁甲战士", "role": "warden", "color": "c76b57"}, true)
	for id in PICKS:
		if not enemies.has(id):
			failures.append(id + ": missing from catalog")
			continue
		var definition: Dictionary = enemies[id]
		var entity := {"id": id, "name": String(definition.get("name", id)), "kind": String(definition.get("kind", "normal"))}
		await _capture(entity, definition, false)
	print("ACTOR3D_LOOK_RESULT=" + JSON.stringify({"prefix": prefix, "views": views.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _capture(entity: Dictionary, definition: Dictionary, is_player: bool) -> void:
	var view = ActorViewScript.new()
	view.size = Vector2(SIZE, SIZE)
	view.custom_minimum_size = Vector2(SIZE, SIZE)
	root.add_child(view)
	view.setup(entity, definition, is_player)
	view.held = true
	for ignored in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = view.snapshot()
	if image == null:
		failures.append(str(entity.get("id", "?")) + ": snapshot null")
		return
	var composed := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	composed.fill(Color("141a17"))
	composed.blend_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	var filename := "%s-%s.png" % [prefix, str(entity.get("id", "actor"))]
	var error := composed.save_png(ProjectSettings.globalize_path(OUTPUT + filename))
	if error != OK:
		failures.append(filename + ": save failed")
		return
	views.append(filename)
	print("SHOT " + filename + " arch=" + str(view.archetype) + " h=" + String.num(view.height, 2))
	view.queue_free()
