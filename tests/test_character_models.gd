extends SceneTree
## Isolated asset acceptance checks. No game rules or player save are loaded.

const MODEL_DIR := "res://assets/models/grey_oath_samples/"
const OUTPUT := "res://docs/evidence/character-models-20261103/"
const EXPECTED := [
	{"id": "warden", "budget": 8000, "min_height": 1.55, "max_height": 2.30},
	{"id": "ch1_normal_02", "budget": 6000, "min_height": 1.40, "max_height": 2.05},
	{"id": "ch1_elite_09", "budget": 12000, "min_height": 2.30, "max_height": 3.20},
]
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var models: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks.append({"ok": ok, "check": message})
	if not ok:
		failures.append(message)
		print("MODEL_CHECK_FAIL ", message)


func _run() -> void:
	for spec in EXPECTED:
		_test_model(spec)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := {
		"date": "2026-11-04",
		"scope": "GLB structure, Godot loading, mesh/material/bounds budgets; no game save or full game regression",
		"checks": checks.size(), "failures": failures,
		"details": checks, "models": models,
		"resource_loader_checked": "--verify-imported" in OS.get_cmdline_user_args(),
		"visual_validation": "reported separately by the gallery screenshot review",
	}
	var file := FileAccess.open(OUTPUT + "model-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MODEL_VALIDATION_RESULT " + JSON.stringify({"checks": checks.size(), "failures": failures, "models": models}))
	quit(0 if failures.is_empty() else 1)


func _test_model(spec: Dictionary) -> void:
	var id: String = spec.id
	var path := MODEL_DIR + id + ".glb"
	_check(FileAccess.file_exists(path), id + ": GLB exists")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var length := file.get_length()
	_check(file.get_32() == 0x46546C67, id + ": GLB magic")
	_check(file.get_32() == 2, id + ": glTF 2 version")
	_check(file.get_32() == length, id + ": declared binary length matches file")
	var json_length := file.get_32()
	_check(file.get_32() == 0x4E4F534A, id + ": JSON chunk present")
	var raw: Variant = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	_check(raw is Dictionary, id + ": valid glTF JSON")
	if not raw is Dictionary:
		return
	var document_json: Dictionary = raw
	_check(not document_json.get("meshes", []).is_empty(), id + ": non-empty exported meshes")
	var material_count: int = document_json.get("materials", []).size()
	_check(material_count > 0 and material_count <= 8, id + ": 1–8 exported materials")
	var external_uris: Array[String] = []
	for collection in ["buffers", "images"]:
		for item in document_json.get(collection, []):
			var uri: String = str(item.get("uri", ""))
			if not uri.is_empty() and not uri.begins_with("data:"):
				external_uris.append(uri)
	_check(external_uris.is_empty(), id + ": no external resources")
	_check(document_json.get("cameras", []).is_empty(), id + ": no exported camera")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	_check(error == OK, id + ": Godot GLTFDocument import")
	if error != OK:
		return
	var scene := document.generate_scene(state)
	_check(scene != null, id + ": scene generated")
	if scene == null:
		return
	root.add_child(scene)
	var mesh_nodes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	var count := 0
	var triangle_count := 0
	var bounds := AABB()
	var has_bounds := false
	var materials_visible := true
	for node in mesh_nodes:
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		count += 1
		var local_bounds: AABB = instance.global_transform * instance.mesh.get_aabb()
		bounds = bounds.merge(local_bounds) if has_bounds else local_bounds
		has_bounds = true
		for surface in range(instance.mesh.get_surface_count()):
			var index_count: int = instance.mesh.surface_get_array_index_len(surface)
			var vertices: int = index_count if index_count > 0 else instance.mesh.surface_get_array_len(surface)
			triangle_count += vertices / 3
			var material: Material = instance.get_active_material(surface)
			if not material is BaseMaterial3D or material.albedo_color.a <= 0.01:
				materials_visible = false
	_check(count > 0, id + ": instantiated meshes visible to engine")
	_check(materials_visible, id + ": surface materials present and non-transparent")
	_check(triangle_count > 0 and triangle_count <= int(spec.budget), id + ": triangle budget")
	_check(bounds.size.y >= float(spec.min_height) and bounds.size.y <= float(spec.max_height), id + ": expected real-world height")
	_check(bounds.position.y >= -0.08 and bounds.position.y <= 0.12, id + ": feet near ground origin")
	_check(scene.find_children("*", "Camera3D", true, false).is_empty(), id + ": no imported camera")
	_check(scene.find_children("*", "Light3D", true, false).is_empty(), id + ": no imported light")
	var animations: Array[String] = []
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		var animation_root := player.get_node(player.root_node)
		for animation_name in player.get_animation_list():
			if animation_name == "RESET":
				continue
			animations.append(animation_name)
			var animation := player.get_animation(animation_name)
			for track in range(animation.get_track_count()):
				var target := animation_root.get_node_or_null(NodePath(animation.track_get_path(track).get_concatenated_names()))
				_check(target != null, id + ": animation track target exists: " + animation_name)
			player.play(animation_name)
			player.advance(minf(0.25, animation.length * 0.5))
			player.stop()
	if "--verify-imported" in OS.get_cmdline_user_args():
		var packed := ResourceLoader.load(path) as PackedScene
		_check(packed != null, id + ": editor-imported PackedScene loads")
		if packed != null:
			var imported := packed.instantiate()
			_check(imported != null, id + ": editor-imported scene instantiates")
			if imported != null:
				imported.free()
	models.append({"id": id, "bytes": length, "mesh_instances": count, "triangles": triangle_count, "materials": material_count,
		"bounds_min": [bounds.position.x, bounds.position.y, bounds.position.z],
		"bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z],
		"animations": animations, "animation_scope": "not_applicable: static sample" if animations.is_empty() else "node animation playback checked"})
	scene.free()
