extends SceneTree
## rig3d 自检取景脚本：把 4 个 3D 角色排成 contact sheet，另存单张 512 立绘。
## 非 headless 运行：
##   .tools/Godot.app/Contents/MacOS/Godot --path . --script tests/actor3d_capture.gd

const OUTPUT := "res://docs/evidence/ui-rebuild-20261104"
const VIEW := 512
const SLOTS := [
	{"id": "warden", "name": "铁甲战士", "role": "warden", "player": true, "color": "#4a332f"},
	{"id": "ch1_normal_07", "name": "灰鸦", "player": false, "color": "#4e5a5e"},
	{"id": "ch1_normal_03", "name": "墓灯蛾", "player": false, "color": "#5f6a56"},
	{"id": "ch1_boss_12", "name": "沉钟看守", "player": false, "color": "#7d6a4f"},
]
var shots: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _save(image: Image, label: String) -> void:
	var path := OUTPUT + "/" + label + ".png"
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		failures.append("save " + label)
	else:
		shots.append(path)


func _compose(bg: Color, snap: Image) -> Image:
	var out := Image.create(VIEW, VIEW, false, Image.FORMAT_RGBA8)
	out.fill(bg)
	out.blend_rect(snap, Rect2i(0, 0, VIEW, VIEW), Vector2i.ZERO)
	return out


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 900)
	var board := Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#1b1a17")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(backdrop)
	root.add_child(board)
	var views: Array = []
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var view: Control = load("res://ui/three_d/actor_view.gd").new()
		view.position = Vector2(20 + i * 355, 190)
		view.size = Vector2(330, 520)
		view.custom_minimum_size = Vector2(330, 520)
		board.add_child(view)
		var entity := {"id": slot.id, "name": slot.name, "kind": "normal"}
		if slot.player:
			entity["role"] = slot.role
		var definition := {"id": slot.id, "name": slot.name, "color": slot.color}
		view.setup(entity, definition, bool(slot.player))
		views.append([view, slot])
	for ignored in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	for pair in views:
		var view: Control = pair[0]
		var slot: Dictionary = pair[1]
		var snap: Image = view.snapshot()
		if snap == null:
			failures.append("snapshot " + str(slot.id))
			continue
		_save(_compose(Color("#1b1a17"), snap), "actor3d-" + str(slot.id))
	await RenderingServer.frame_post_draw
	var sheet := root.get_texture().get_image()
	_save(sheet, "actor3d-contact-sheet")
	print("ACTOR3D_CAPTURE shots=", shots.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
