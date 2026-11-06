extends SceneTree
## 真渲染（非 headless）56 个敌人造型的视觉抽样：4 章 x（普通 + 精英 + 首领）。
## 依赖队友 rig3d 的 ui/three_d/actor_rig.gd；输出 docs/evidence/ui-rebuild-20261104/enemy3d-*.png。
## 用法：Godot --path . --script tests/enemy_forms_capture.gd（不要加 --headless）

const ActorRig = preload("res://ui/three_d/actor_rig.gd")
const EnemyForms = preload("res://ui/three_d/enemy_forms.gd")
const CATALOG := "res://data/catalog.json"
const OUTPUT := "res://docs/evidence/ui-rebuild-20261104/"
const SHOT_SIZE := 640
const PICKS := [
	"ch1_normal_02", "ch1_elite_09", "ch1_boss_12",
	"ch2_normal_02", "ch2_elite_10", "ch2_boss_13",
	"ch3_normal_04", "ch3_elite_09", "ch3_boss_13",
	"ch4_normal_05", "ch4_elite_09", "ch4_boss_12",
]
## 补充：每个未在主样本里露面的 archetype 各一张，验证轮廓互不混淆。
const EXTRA_PICKS := [
	"ch1_normal_01", "ch1_normal_03", "ch1_normal_05", "ch1_normal_07",
	"ch2_normal_03", "ch2_normal_05", "ch3_normal_02", "ch3_normal_03", "ch4_normal_03",
]

var enemies: Dictionary = {}
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var stage: Node3D
var failures: Array[String] = []
var shots: Array[String] = []
var _dark := false
var _out_dir := OUTPUT


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var text := FileAccess.get_file_as_string(CATALOG)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		printerr("CAPTURE ERROR: catalog is not readable")
		quit(1)
		return
	for row in (parsed as Dictionary).get("enemies", []):
		enemies[String(row.get("id", ""))] = row
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = Array(arg.substr(7).split(","))
		elif arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg == "--dark":
			_dark = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_build_stage()
	await process_frame
	if not only.is_empty():
		for id in only:
			await _capture(id)
	else:
		for id in PICKS:
			await _capture(id)
		for id in EXTRA_PICKS:
			await _capture(id)
	print("ENEMY_FORMS_CAPTURE_RESULT=" + JSON.stringify({"shots": shots, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _build_stage() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(SHOT_SIZE, SHOT_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0e1311")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("93a89f")
	environment.ambient_light_energy = 0.22 if _dark else 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES if _dark else Environment.TONE_MAPPER_FILMIC
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.light_color = Color("f2dfb8")
	key.light_energy = 1.05 if _dark else 1.45
	key.rotation_degrees = Vector3(-38, -34, 0)
	key.shadow_enabled = true
	world.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9fbfc4")
	rim.light_energy = 0.50 if _dark else 0.95
	rim.rotation_degrees = Vector3(-16, 148, 0)
	world.add_child(rim)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30, 30)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("141a17")
	floor_material.roughness = 0.94
	floor_instance.material_override = floor_material
	floor_instance.position = Vector3(0, -0.006, 0)
	world.add_child(floor_instance)

	camera = Camera3D.new()
	camera.fov = 32.0
	camera.near = 0.05
	camera.far = 80.0
	world.add_child(camera)
	camera.current = true

	stage = Node3D.new()
	world.add_child(stage)


func _capture(enemy_id: String) -> void:
	if not enemies.has(enemy_id):
		failures.append(enemy_id + ": missing from catalog")
		return
	var spec := EnemyForms.spec(enemy_id, enemies[enemy_id])
	var rig := ActorRig.build(spec)
	if rig == null:
		failures.append(enemy_id + ": ActorRig.build returned null")
		return
	for child in stage.get_children():
		child.queue_free()
	stage.add_child(rig)
	rig.rotation_degrees.y = -22.0
	var height := maxf(0.8, float(rig.get_meta("height", spec.get("height", 1.9))))
	_fit_camera(height)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var tier := String(spec.get("tier", "normal"))
	var chapter := int(spec.get("chapter", 0)) + 1
	var filename := "enemy3d-ch%d-%s-%s.png" % [chapter, tier, enemy_id]
	var absolute := ProjectSettings.globalize_path(_out_dir + filename)
	var error := image.save_png(absolute)
	if error != OK:
		failures.append(enemy_id + ": save_png failed " + str(error))
		return
	shots.append(filename)
	print("SHOT " + filename + " h=" + String.num(height, 2) + " arch=" + String(spec.get("archetype", "")) + " min_y=" + String.num(float(rig.get_meta("bounds_min_y", 0.0)), 3) + " meshes=" + str(rig.get_meta("mesh_count", 0)))


func _fit_camera(height: float) -> void:
	var target := Vector3(0, height * 0.50, 0)
	var direction := Vector3(0.55, 0.30, 0.82).normalized()
	camera.position = target + direction * height * 2.45
	camera.look_at(target, Vector3.UP)
