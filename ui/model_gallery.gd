extends Node3D
## Isolated model viewer: it never loads the game rules or the player's save.

const MODEL_DIR := "res://assets/models/grey_oath_samples/"
const EVIDENCE := "res://docs/evidence/character-models-20261103/"
const MODELS := [
	{"id": "warden", "name": "守誓者", "kind": "旅者 / 沉钟之盾", "detail": "缺口剑 · 守誓盾 · 灰铁重甲", "color": Color("c7a66a")},
	{"id": "ch1_normal_02", "name": "枯骨哨兵", "kind": "普通敌人 / 沉钟墓园", "detail": "残骨 · 锈矛 · 破损护甲", "color": Color("aab6a1")},
	{"id": "ch1_elite_09", "name": "负钟巨人", "kind": "精英敌人 / 沉钟墓园", "detail": "负重姿态 · 空心铜钟 · 石质躯体", "color": Color("bd9372")},
]
const PAPER := Color("e8dfcc")
const GOLD := Color("c7a66a")
var models: Array[Node3D] = []
var pedestals: Array[Node3D] = []
var camera: Camera3D
var selected := -1
var rotating := false
var status: Label
var caption: Label
var model_labels: HBoxContainer
var display_font: SystemFont
var errors: Array[String] = []


func _ready() -> void:
	get_window().title = "灰誓 · 3D 角色与怪物造型样例"
	_build_stage()
	_load_models()
	_build_interface()
	_focus(-1)
	if "--capture-models" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _mat(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.87
	return material


func _mesh(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("151a1c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b4c3ca")
	environment.ambient_light_energy = 0.20
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	_mesh(self, floor_mesh, _mat(Color("0c1114")), Vector3(0, -0.18, 0))
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffdfad")
	key.light_energy = 0.9
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 30
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("8eb4cd")
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-25, 150, 0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 5, -3)
	rim.light_color = Color("b1c9c8")
	rim.light_energy = 0.7
	rim.omni_range = 13
	add_child(rim)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.4
	camera.position = Vector3(0, 3.8, 10)
	add_child(camera)
	camera.look_at(Vector3(0, 1.25, 0))
	camera.current = true
	for i in range(3):
		var pedestal := Node3D.new()
		pedestal.name = "DisplayPlinth_%d" % i
		pedestal.position.x = (i - 1) * 3.0
		add_child(pedestal)
		pedestals.append(pedestal)
		var disc := CylinderMesh.new()
		disc.top_radius = 1.09 if i == 2 else 0.94
		disc.bottom_radius = disc.top_radius + 0.08
		disc.height = 0.16
		disc.radial_segments = 48
		_mesh(pedestal, disc, _mat(Color("333b39")), Vector3(0, -0.08, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = disc.top_radius - 0.035
		ring.outer_radius = disc.top_radius
		ring.rings = 48
		ring.ring_segments = 8
		_mesh(pedestal, ring, _mat(Color(MODELS[i].color).darkened(0.32), 0.35), Vector3(0, 0.004, 0))


func _load_models() -> void:
	for i in range(MODELS.size()):
		var holder := Node3D.new()
		holder.name = "Model_%s" % MODELS[i].id
		holder.position.x = (i - 1) * 3.0
		holder.rotation.y = 0.27
		add_child(holder)
		models.append(holder)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var path: String = MODEL_DIR + str(MODELS[i].id) + ".glb"
		var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
		if error != OK:
			errors.append("%s：加载失败 %s" % [MODELS[i].name, error_string(error)])
			continue
		var model := document.generate_scene(state)
		if model == null:
			errors.append("%s：模型场景为空" % MODELS[i].name)
			continue
		holder.add_child(model)
		_play_on(holder, "idle")


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 15
	box.content_margin_right = 15
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box


func _label(parent: Node, text: String, font_size: int, color: Color = PAPER, serif: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if serif:
		label.add_theme_font_override("font", display_font)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Songti SC", "Noto Serif CJK SC", "serif"])
	var style := Theme.new()
	style.default_font = font
	style.default_font_size = 16
	style.set_color("font_color", "Button", PAPER)
	style.set_stylebox("normal", "Button", _style(Color("202827"), Color("536059")))
	style.set_stylebox("hover", "Button", _style(Color("344039"), GOLD))
	style.set_stylebox("pressed", "Button", _style(Color("414536"), GOLD))
	style.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), GOLD))
	ui.theme = style
	var title := VBoxContainer.new()
	title.position = Vector2(48, 32)
	title.add_theme_constant_override("separation", 5)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title)
	_label(title, "G R E Y   O A T H    /    C R E A T U R E   S T U D I E S", 13, GOLD)
	_label(title, "沉钟之下", 44, PAPER, true)
	caption = _label(title, "旅者与墓园之敌  /  3D 造型样例", 17, Color("aeb8af"))
	var help := _label(ui, "拖拽旋转 · 滚轮缩放\nR 重置视角    1 / 2 / 3 单体查看", 14, Color("b0b9b1"))
	help.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help.offset_left = -340
	help.offset_right = -48
	help.offset_top = 42
	help.offset_bottom = 90
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	model_labels = HBoxContainer.new()
	model_labels.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	model_labels.offset_left = 86
	model_labels.offset_right = -86
	model_labels.offset_top = -225
	model_labels.offset_bottom = -125
	model_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(model_labels)
	for data in MODELS:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 5)
		model_labels.add_child(column)
		for label in [_label(column, str(data.kind), 13, data.color), _label(column, str(data.name), 27, PAPER, true), _label(column, str(data.detail), 14, Color("aeb8af"))]:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 48
	bottom.offset_right = -48
	bottom.offset_top = -112
	bottom.offset_bottom = -23
	bottom.add_theme_constant_override("separation", 12)
	ui.add_child(bottom)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	bottom.add_child(controls)
	_button(controls, "全体", func(): _focus(-1))
	for i in range(MODELS.size()):
		_button(controls, str(MODELS[i].name), _focus.bind(i))
	_button(controls, "转身 45°", func(): _turn(PI / 4.0))
	if _has_animation("idle"):
		_button(controls, "待机", _play.bind("idle"))
	if _has_animation("attack"):
		_button(controls, "攻击", _play.bind("attack"))
	_button(controls, "自动旋转", func(): rotating = not rotating)
	status = _label(bottom, "", 13, Color("9aa79e"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not errors.is_empty():
		status.text = " / ".join(errors)
		status.add_theme_color_override("font_color", Color("ed9d82"))
	else:
		status.text = "角色与怪物造型预览 · 可独立旋转查看 · 不影响旅程进度" if _has_animation("idle") else "静态造型样例 · 拖拽查看正面与背面 · 不影响旅程进度"


func _focus(index: int) -> void:
	selected = index
	rotating = false
	for i in range(models.size()):
		models[i].visible = index == -1 or index == i
		pedestals[i].visible = models[i].visible
		var x := float(i - 1) * 3.0 if index == -1 else 0.0
		models[i].position.x = x
		pedestals[i].position.x = x
		models[i].rotation.y = 0.27
	camera.size = 6.4 if index == -1 else (4.8 if index == 2 else 3.8)
	camera.position = Vector3(0, 3.8, 10) if index == -1 else Vector3(0, 2.8, 8)
	camera.look_at(Vector3(0, 1.25 if index == -1 or index == 2 else 1.0, 0))
	model_labels.visible = index == -1
	caption.text = "旅者与墓园之敌  /  3D 造型样例" if index == -1 else "%s  /  %s" % [MODELS[index].name, MODELS[index].detail]


func _turn(angle: float) -> void:
	for model in models:
		if model.visible:
			model.rotation.y += angle


func _play_on(model: Node3D, animation: String) -> bool:
	var played := false
	for child in model.find_children("*", "AnimationPlayer", true, false):
		var player := child as AnimationPlayer
		for animation_name in player.get_animation_list():
			if str(animation_name).to_lower().ends_with(animation):
				player.play(animation_name)
				played = true
				break
	return played


func _has_animation(animation: String) -> bool:
	for model in models:
		for child in model.find_children("*", "AnimationPlayer", true, false):
			for animation_name in child.get_animation_list():
				if str(animation_name).to_lower().ends_with(animation):
					return true
	return false


func _play(animation: String) -> void:
	var played := false
	for model in models:
		if model.visible:
			played = _play_on(model, animation) or played
	status.text = ("演示：待机" if animation == "idle" else "演示：攻击姿态") if played else "当前模型为静态造型样例"


func _process(delta: float) -> void:
	if rotating:
		_turn(delta * 0.45)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		rotating = false
		_turn(event.relative.x * 0.012)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = maxf(2.4, camera.size - 0.3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = minf(9.0, camera.size + 0.3)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_focus(-1)
		elif event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_focus(event.keycode - KEY_1)


func _snapshot(filename: String) -> void:
	for i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(EVIDENCE + filename + ".png")
	print("MODEL_CAPTURE ", filename, " ", error_string(error))
	if error != OK:
		errors.append("Screenshot: " + filename)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	get_window().size = Vector2i(1440, 900)
	_focus(-1)
	await _snapshot("overview")
	for i in range(MODELS.size()):
		_focus(i)
		await _snapshot(str(MODELS[i].id) + "-front")
		_turn(PI)
		await _snapshot(str(MODELS[i].id) + "-back")
	_focus(-1)
	get_tree().quit(0 if errors.is_empty() else 1)
