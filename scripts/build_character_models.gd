extends SceneTree
## Original, deterministic character studies. Meter units, Y up, front +Z.
## Run with Godot --headless --path . --script scripts/build_character_models.gd

const OUTPUT := "res://assets/models/grey_oath_samples/"
var palette: Dictionary = {}
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _material(key: String, color: String, metallic: float = 0.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.albedo_color = Color(color)
	mat.roughness = 0.88
	mat.metallic = metallic
	palette[key] = mat


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_material("Iron", "596b70", 0.3)
	_material("IronLight", "879498", 0.25)
	_material("Gold", "bf9857", 0.35)
	_material("Cloth", "354c44")
	_material("Dark", "20292c")
	_material("Bone", "c8c3a5")
	_material("Stone", "92948a")
	_material("Bronze", "9e7250", 0.35)
	var definitions: Array[Dictionary] = []
	definitions.append(_export_model(_warden(), "warden", "守誓者"))
	definitions.append(_export_model(_skeleton(), "ch1_normal_02", "枯骨哨兵"))
	definitions.append(_export_model(_giant(), "ch1_elite_09", "负钟巨人"))
	var manifest := {"version": 1, "authored": "2026-11-04", "authoring": "Original deterministic Godot mesh construction", "units": "meters", "up": "+Y", "front": "+Z", "origin": "ground between feet", "animation_type": "static sample; no skeletal rig", "external_textures": false, "models": definitions, "failures": failures}
	var file := FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("CHARACTER_EXPORT_RESULT ", JSON.stringify(manifest))
	quit(0 if failures.is_empty() else 1)


func _root(id: String) -> Node3D:
	var model := Node3D.new()
	model.name = id
	root.add_child(model)
	return model


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Author with conventional outward cross-products; Godot uses clockwise faces.
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.1:
		return
	for vertex in [a, c, b]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)


func _commit(parent: Node3D, name_value: String, surface: SurfaceTool, material: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_value
	node.mesh = surface.commit()
	node.material_override = palette[material]
	parent.add_child(node)
	node.owner = parent
	return node


func _loft(parent: Node3D, name_value: String, rings: Array, material: String, sides: int = 10, caps: bool = true) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: Array[PackedVector3Array] = []
	for ring in rings:
		var points := PackedVector3Array()
		var center: Vector3 = ring[0]
		for i in range(sides):
			var angle := TAU * float(i) / float(sides)
			points.append(center + Vector3(sin(angle) * float(ring[1]), 0, cos(angle) * float(ring[2])))
		vertices.append(points)
	for j in range(vertices.size() - 1):
		for i in range(sides):
			var next := (i + 1) % sides
			_triangle(surface, vertices[j][i], vertices[j][next], vertices[j + 1][next])
			_triangle(surface, vertices[j][i], vertices[j + 1][next], vertices[j + 1][i])
	if caps:
		for i in range(sides):
			var next := (i + 1) % sides
			_triangle(surface, rings[0][0], vertices[0][next], vertices[0][i])
			_triangle(surface, rings[-1][0], vertices[-1][i], vertices[-1][next])
	return _commit(parent, name_value, surface, material)


func _stone(parent: Node3D, name_value: String, center: Vector3, radii: Vector3, material: String, sides: int = 8) -> MeshInstance3D:
	var rings: Array = []
	for i in range(7):
		var angle := PI * float(i) / 6.0
		var radius := maxf(0.035, sin(angle))
		rings.append([center + Vector3(0, -cos(angle) * radii.y, 0), radius * radii.x, radius * radii.z])
	return _loft(parent, name_value, rings, material, sides)


func _tube(parent: Node3D, name_value: String, path: Array[Vector3], radii: Array[float], material: String, sides: int = 6) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for j in range(path.size()):
		var tangent: Vector3 = (path[mini(j + 1, path.size() - 1)] - path[maxi(0, j - 1)]).normalized()
		var helper := Vector3.UP if absf(tangent.y) < 0.95 else Vector3.RIGHT
		var side := tangent.cross(helper).normalized()
		var across := tangent.cross(side).normalized()
		var ring := PackedVector3Array()
		for i in range(sides):
			var angle := TAU * float(i) / float(sides)
			ring.append(path[j] + (side * cos(angle) + across * sin(angle)) * radii[mini(j, radii.size() - 1)])
		rings.append(ring)
	for j in range(rings.size() - 1):
		for i in range(sides):
			var next := (i + 1) % sides
			_triangle(surface, rings[j][i], rings[j][next], rings[j + 1][next])
			_triangle(surface, rings[j][i], rings[j + 1][next], rings[j + 1][i])
	for i in range(sides):
		var next := (i + 1) % sides
		_triangle(surface, path[0], rings[0][next], rings[0][i])
		_triangle(surface, path[-1], rings[-1][i], rings[-1][next])
	return _commit(parent, name_value, surface, material)


func _bone(parent: Node3D, name_value: String, a: Vector3, b: Vector3, radius: float, material: String = "Bone") -> void:
	_tube(parent, name_value, [a, a.lerp(b, 0.12), a.lerp(b, 0.5), a.lerp(b, 0.88), b], [radius * 0.8, radius * 1.12, radius * 0.63, radius * 1.12, radius * 0.8], material)


func _plate(parent: Node3D, name_value: String, polygon: PackedVector2Array, depth: float, at: Vector3, material: String) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var a := Vector3(polygon[indices[i]].x, polygon[indices[i]].y, depth * 0.5) + at
		var b := Vector3(polygon[indices[i + 1]].x, polygon[indices[i + 1]].y, depth * 0.5) + at
		var c := Vector3(polygon[indices[i + 2]].x, polygon[indices[i + 2]].y, depth * 0.5) + at
		_triangle(surface, a, b, c)
		_triangle(surface, a - Vector3(0, 0, depth), c - Vector3(0, 0, depth), b - Vector3(0, 0, depth))
	for i in range(polygon.size()):
		var next := (i + 1) % polygon.size()
		var a := Vector3(polygon[i].x, polygon[i].y, depth * 0.5) + at
		var b := Vector3(polygon[next].x, polygon[next].y, depth * 0.5) + at
		_triangle(surface, a, a - Vector3(0, 0, depth), b - Vector3(0, 0, depth))
		_triangle(surface, a, b - Vector3(0, 0, depth), b)
	return _commit(parent, name_value, surface, material)


func _rect(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)])


func _warden() -> Node3D:
	var model := _root("warden")
	# Broad stance, swept boots, overlapping greaves and a flared armor skirt.
	for side in [-1.0, 1.0]:
		var x: float = side * 0.19
		_loft(model, "Boot_%s" % side, [[Vector3(x, 0.0, 0.09), 0.145, 0.24], [Vector3(x, 0.1, 0.10), 0.16, 0.25], [Vector3(x, 0.23, -0.01), 0.11, 0.13]], "Dark", 6)
		_loft(model, "Greave_%s" % side, [[Vector3(x, 0.18, 0), 0.105, 0.12], [Vector3(x, 0.49, -0.035), 0.13, 0.145], [Vector3(x, 0.63, 0), 0.17, 0.16]], "IronLight", 6)
		_stone(model, "Knee_%s" % side, Vector3(x, 0.62, 0.09), Vector3(0.16, 0.14, 0.12), "Iron")
		_bone(model, "Thigh_%s" % side, Vector3(x, 0.65, -0.02), Vector3(side * 0.13, 0.97, -0.02), 0.16, "Dark")
	_loft(model, "Gambeson", [[Vector3(0, 0.68, 0), 0.39, 0.25], [Vector3(0, 0.97, 0), 0.29, 0.20], [Vector3(0, 1.30, 0), 0.35, 0.22]], "Cloth", 8)
	for side in [-1.0, 1.0]:
		_plate(model, "SkirtPlate_%s" % side, PackedVector2Array([Vector2(-0.13, -0.17), Vector2(0.13, -0.12), Vector2(0.11, 0.16), Vector2(-0.12, 0.16)]), 0.07, Vector3(side * 0.19, 0.80, 0.205), "Iron")
	_loft(model, "Breastplate", [[Vector3(0, 0.96, 0), 0.27, 0.20], [Vector3(0, 1.12, 0.025), 0.35, 0.245], [Vector3(0, 1.37, 0), 0.39, 0.23], [Vector3(0, 1.47, -0.015), 0.25, 0.15]], "Iron", 8)
	_plate(model, "ChestBellSeal", PackedVector2Array([Vector2(-0.095, -0.08), Vector2(0.095, -0.08), Vector2(0.06, 0.06), Vector2(0.035, 0.09), Vector2(-0.035, 0.09), Vector2(-0.06, 0.06)]), 0.018, Vector3(0, 1.25, 0.247), "Gold")
	_loft(model, "NeckGuard", [[Vector3(0, 1.44, 0), 0.20, 0.18], [Vector3(0, 1.52, 0), 0.23, 0.19]], "Gold", 10)
	_loft(model, "Helmet", [[Vector3(0, 1.50, 0), 0.185, 0.18], [Vector3(0, 1.67, 0), 0.22, 0.205], [Vector3(0, 1.80, -0.025), 0.21, 0.19], [Vector3(0, 1.91, -0.045), 0.065, 0.08]], "IronLight", 10)
	_plate(model, "VisorShadow", PackedVector2Array([Vector2(-0.18, -0.026), Vector2(0.18, -0.026), Vector2(0.16, 0.035), Vector2(-0.16, 0.035)]), 0.012, Vector3(0, 1.715, 0.191), "Dark")
	_plate(model, "VisorNose", PackedVector2Array([Vector2(-0.025, -0.11), Vector2(0.035, -0.07), Vector2(0.024, 0.12), Vector2(-0.024, 0.12)]), 0.025, Vector3(0, 1.67, 0.221), "Gold")
	# A broad, irregular cape is a silhouette rather than a flat rectangle.
	_plate(model, "TornCape", PackedVector2Array([Vector2(-0.43, -0.55), Vector2(-0.19, -0.45), Vector2(-0.02, -0.59), Vector2(0.17, -0.48), Vector2(0.40, -0.54), Vector2(0.31, 0.42), Vector2(-0.31, 0.42)]), 0.035, Vector3(0, 1.01, -0.245), "Cloth")
	for side in [-1.0, 1.0]:
		_bone(model, "UpperArm_%s" % side, Vector3(side * 0.38, 1.37, 0), Vector3(side * 0.51, 1.08, 0.04), 0.14, "Dark")
		_loft(model, "Shoulder_%s" % side, [[Vector3(side * 0.43, 1.26, 0), 0.23, 0.225], [Vector3(side * 0.43, 1.43, 0), 0.245, 0.21], [Vector3(side * 0.42, 1.53 if side < 0 else 1.49, 0), 0.105, 0.12]], "IronLight" if side < 0 else "Iron", 8)
		_bone(model, "Vambrace_%s" % side, Vector3(side * 0.51, 1.08, 0.04), Vector3(side * 0.52, 0.86, 0.15), 0.15, "Iron")
		_stone(model, "Gauntlet_%s" % side, Vector3(side * 0.52, 0.84, 0.16), Vector3(0.13, 0.14, 0.13), "IronLight")
	var shield := PackedVector2Array([Vector2(0, -0.49), Vector2(0.31, -0.24), Vector2(0.34, 0.27), Vector2(0.19, 0.40), Vector2(-0.20, 0.40), Vector2(-0.34, 0.27), Vector2(-0.31, -0.24)])
	_plate(model, "OathShieldRim", shield, 0.10, Vector3(-0.57, 0.94, 0.31), "Gold")
	var inner := PackedVector2Array()
	for point in shield: inner.append(point * 0.87)
	_plate(model, "OathShieldFace", inner, 0.035, Vector3(-0.57, 0.94, 0.38), "Cloth")
	_plate(model, "ShieldBell", PackedVector2Array([Vector2(-0.13, -0.12), Vector2(0.13, -0.12), Vector2(0.095, 0.04), Vector2(0.06, 0.12), Vector2(-0.06, 0.12), Vector2(-0.095, 0.04)]), 0.025, Vector3(-0.57, 0.99, 0.414), "Gold")
	_plate(model, "BellClapperMark", _rect(0.025, 0.045), 0.03, Vector3(-0.57, 0.82, 0.42), "Gold")
	_plate(model, "Sword", PackedVector2Array([Vector2(0, -0.66), Vector2(0.065, -0.48), Vector2(0.065, -0.30), Vector2(0.025, -0.24), Vector2(0.065, -0.19), Vector2(0.065, 0.12), Vector2(-0.065, 0.12), Vector2(-0.065, -0.48)]), 0.05, Vector3(0.61, 0.82, 0.25), "IronLight")
	_plate(model, "SwordGuard", _rect(0.145, 0.026), 0.07, Vector3(0.61, 0.98, 0.25), "Gold")
	_bone(model, "SwordGrip", Vector3(0.61, 0.99, 0.25), Vector3(0.61, 1.12, 0.25), 0.04, "Dark")
	return model


func _skeleton() -> Node3D:
	var model := _root("ch1_normal_02")
	for side in [-1.0, 1.0]:
		var ankle := Vector3(side * 0.17, 0.14, 0.04)
		var knee := Vector3(side * 0.22, 0.51, -0.09)
		var hip := Vector3(side * 0.13, 0.91, -0.09)
		_bone(model, "Shin_%s" % side, ankle, knee, 0.055)
		_bone(model, "Femur_%s" % side, knee, hip, 0.069)
		_stone(model, "Knee_%s" % side, knee, Vector3(0.075, 0.075, 0.070), "Bone", 6)
		for toe in range(3):
			_bone(model, "Foot_%s_%d" % [side, toe], Vector3(side * 0.17 + (toe - 1) * 0.045, 0.055, 0.02), Vector3(side * 0.17 + (toe - 1) * 0.05, 0.035, 0.25 - absf(toe - 1) * 0.035), 0.028)
		_plate(model, "Pelvis_%s" % side, PackedVector2Array([Vector2(-0.10, -0.07), Vector2(0.09, -0.05), Vector2(0.12, 0.10), Vector2(-0.075, 0.12)]), 0.09, Vector3(side * 0.10, 0.90, -0.07), "Bone")
	for i in range(7):
		_stone(model, "Spine_%d" % i, Vector3(0, 0.94 + i * 0.063, -0.10 + i * 0.018), Vector3(0.065, 0.046, 0.063), "Bone", 6)
	# Curved separate ribs leave real empty chest space.
	for row in range(4):
		var y := 1.16 + row * 0.078
		var width := 0.18 + row * 0.018
		for side in [-1.0, 1.0]:
			_tube(model, "Rib_%d_%s" % [row, side], [Vector3(0, y + 0.045, -0.04), Vector3(side * width * 0.72, y + 0.04, -0.07), Vector3(side * width, y, 0.06), Vector3(side * width * 0.72, y - 0.04, 0.18), Vector3(side * 0.055, y - 0.055, 0.20)], [0.025, 0.032, 0.030, 0.026, 0.021], "Bone", 5)
	_bone(model, "Sternum", Vector3(0, 1.10, 0.20), Vector3(0, 1.39, 0.20), 0.035)
	_bone(model, "Collar", Vector3(-0.26, 1.43, 0.01), Vector3(0.26, 1.43, 0.01), 0.038)
	_bone(model, "Neck", Vector3(0, 1.41, 0.03), Vector3(0, 1.52, 0.12), 0.055)
	_stone(model, "Cranium", Vector3(0.015, 1.68, 0.135), Vector3(0.18, 0.21, 0.16), "Bone", 10)
	for side in [-1.0, 1.0]:
		_plate(model, "EyeSocket_%s" % side, PackedVector2Array([Vector2(-0.055, -0.045), Vector2(0.05, -0.035), Vector2(0.065, 0.04), Vector2(-0.045, 0.06)]), 0.018, Vector3(side * 0.082 + 0.015, 1.70, 0.284), "Dark")
		_bone(model, "Cheek_%s" % side, Vector3(side * 0.13 + 0.015, 1.61, 0.22), Vector3(side * 0.10 + 0.015, 1.53, 0.24), 0.035)
	_plate(model, "NoseCavity", PackedVector2Array([Vector2(-0.027, -0.035), Vector2(0.028, -0.035), Vector2(0, 0.035)]), 0.02, Vector3(0.015, 1.63, 0.292), "Dark")
	_plate(model, "Jaw", PackedVector2Array([Vector2(-0.11, -0.035), Vector2(0.11, -0.035), Vector2(0.13, 0.03), Vector2(-0.13, 0.03)]), 0.10, Vector3(0.015, 1.51, 0.20), "Bone")
	for tooth in range(5):
		_plate(model, "Tooth_%d" % tooth, _rect(0.014, 0.027), 0.03, Vector3(-0.065 + tooth * 0.04, 1.565, 0.27), "Bone")
	for side in [-1.0, 1.0]:
		var elbow := Vector3(side * 0.36, 1.14, 0.06)
		var hand := Vector3(side * 0.40, 0.99, 0.24)
		_bone(model, "Humerus_%s" % side, Vector3(side * 0.26, 1.40, 0.02), elbow, 0.052)
		_bone(model, "Radius_%s" % side, elbow + Vector3(0.018, 0, 0), hand + Vector3(0.018, 0, 0), 0.029)
		_bone(model, "Ulna_%s" % side, elbow - Vector3(0.018, 0, 0), hand - Vector3(0.018, 0, 0), 0.029)
		_stone(model, "Knuckle_%s" % side, hand, Vector3(0.063, 0.078, 0.045), "Bone", 6)
	_loft(model, "SinglePauldron", [[Vector3(-0.27, 1.33, 0), 0.17, 0.14], [Vector3(-0.27, 1.46, 0), 0.18, 0.14], [Vector3(-0.27, 1.51, 0), 0.06, 0.06]], "Bronze", 6)
	_plate(model, "Rag", PackedVector2Array([Vector2(-0.19, -0.22), Vector2(-0.07, -0.15), Vector2(0.0, -0.25), Vector2(0.08, -0.14), Vector2(0.18, -0.19), Vector2(0.15, 0.10), Vector2(-0.15, 0.10)]), 0.025, Vector3(0, 0.89, 0.015), "Cloth")
	_plate(model, "BrokenShield", PackedVector2Array([Vector2(-0.20, -0.22), Vector2(0.0, -0.31), Vector2(0.21, -0.14), Vector2(0.17, -0.02), Vector2(0.07, 0.04), Vector2(0.20, 0.08), Vector2(0.14, 0.25), Vector2(-0.18, 0.22)]), 0.055, Vector3(-0.43, 1.02, 0.33), "Bronze")
	_bone(model, "SpearHaft", Vector3(0.44, 0.10, 0.23), Vector3(0.48, 1.65, 0.21), 0.027, "Dark")
	_plate(model, "SpearHead", PackedVector2Array([Vector2(-0.07, -0.10), Vector2(0, 0.19), Vector2(0.065, -0.10), Vector2(0, -0.055)]), 0.035, Vector3(0.48, 1.69, 0.21), "IronLight")
	return model


func _bell(parent: Node3D, at: Vector3) -> void:
	var rings: Array = [
		[at + Vector3(0, 0.03, 0), 0.65, 0.51], [at + Vector3(0, 0.09, 0), 0.69, 0.55],
		[at + Vector3(0, 0.18, 0), 0.65, 0.51], [at + Vector3(0, 0.35, 0), 0.52, 0.42],
		[at + Vector3(0, 0.75, 0), 0.42, 0.35], [at + Vector3(0, 0.91, 0), 0.30, 0.25],
		[at + Vector3(0, 1.00, 0), 0.16, 0.14], [at + Vector3(0, 1.04, 0), 0.13, 0.11],
		[at + Vector3(0, 0.98, 0), 0.11, 0.09], [at + Vector3(0, 0.87, 0), 0.24, 0.19],
		[at + Vector3(0, 0.71, 0), 0.35, 0.28], [at + Vector3(0, 0.31, 0), 0.45, 0.35],
		[at + Vector3(0, 0.13, 0), 0.58, 0.44], [at + Vector3(0, 0.03, 0), 0.58, 0.44],
		[at + Vector3(0, 0.03, 0), 0.65, 0.51],
	]
	_loft(parent, "HollowBurdenBell", rings, "Bronze", 16, false)
	_loft(parent, "BellLipBand", [[at + Vector3(0, 0.08, 0), 0.695, 0.555], [at + Vector3(0, 0.13, 0), 0.675, 0.535]], "Gold", 16, false)
	_bone(parent, "BellClapperStem", at + Vector3(0, 0.88, 0), at + Vector3(0, -0.05, 0), 0.04, "Dark")
	_stone(parent, "BellClapper", at + Vector3(0, -0.09, 0), Vector3(0.13, 0.16, 0.12), "Gold")
	_tube(parent, "BellCrown", [at + Vector3(-0.13, 1.01, 0), at + Vector3(-0.11, 1.17, 0), at + Vector3(0.11, 1.17, 0), at + Vector3(0.13, 1.01, 0)], [0.05], "Dark", 8)
	# A recessed-looking jagged dark fissure, offset in front of the bronze wall.
	_tube(parent, "BellFissure", [at + Vector3(0.26, 0.22, 0.465), at + Vector3(0.20, 0.40, 0.405), at + Vector3(0.27, 0.52, 0.36), at + Vector3(0.16, 0.67, 0.337)], [0.015], "Dark", 4)


func _giant() -> Node3D:
	var model := _root("ch1_elite_09")
	for side in [-1.0, 1.0]:
		_loft(model, "MassiveFoot_%s" % side, [[Vector3(side * 0.37, 0.0, 0.17), 0.25, 0.37], [Vector3(side * 0.37, 0.12, 0.18), 0.26, 0.37], [Vector3(side * 0.36, 0.24, 0.02), 0.20, 0.21]], "Stone", 7)
		_bone(model, "Calf_%s" % side, Vector3(side * 0.36, 0.20, 0.02), Vector3(side * 0.43, 0.59, 0.16), 0.23, "Stone")
		_stone(model, "Knee_%s" % side, Vector3(side * 0.43, 0.61, 0.22), Vector3(0.25, 0.22, 0.22), "Stone", 7)
		_bone(model, "Thigh_%s" % side, Vector3(side * 0.43, 0.65, 0.13), Vector3(side * 0.28, 1.04, -0.14), 0.31, "Stone")
	_loft(model, "StoneTorso", [[Vector3(0, 0.91, -0.13), 0.40, 0.30], [Vector3(0, 1.23, -0.18), 0.58, 0.41], [Vector3(0, 1.60, -0.13), 0.68, 0.43], [Vector3(0, 1.89, -0.08), 0.52, 0.38], [Vector3(0, 2.04, -0.07), 0.32, 0.28]], "Stone", 9)
	_loft(model, "WaistWrap", [[Vector3(0, 0.77, -0.13), 0.46, 0.32], [Vector3(0, 1.07, -0.13), 0.43, 0.32]], "Cloth", 9)
	for side in [-1.0, 1.0]:
		_stone(model, "Shoulder_%s" % side, Vector3(side * 0.65, 1.67, 0.01), Vector3(0.32, 0.35, 0.32), "Stone", 7)
		_bone(model, "UpperArm_%s" % side, Vector3(side * 0.70, 1.59, 0.06), Vector3(side * 0.87, 1.16, 0.18), 0.27, "Stone")
		_stone(model, "Elbow_%s" % side, Vector3(side * 0.87, 1.13, 0.18), Vector3(0.25, 0.27, 0.25), "Stone", 7)
		_bone(model, "Forearm_%s" % side, Vector3(side * 0.87, 1.10, 0.18), Vector3(side * 0.83, 0.66, 0.38), 0.31, "Stone")
		_stone(model, "Fist_%s" % side, Vector3(side * 0.82, 0.53, 0.43), Vector3(0.29, 0.29, 0.28), "Stone", 7)
		for finger in range(3):
			_stone(model, "Knuckle_%s_%d" % [side, finger], Vector3(side * 0.82 + (finger - 1) * 0.12, 0.51, 0.65), Vector3(0.08, 0.115, 0.07), "Iron", 6)
		# Bronze bands and dark bindings read as a harness around the bulky body.
		_tube(model, "ChestHarness_%s" % side, [Vector3(side * 0.35, 1.91, -0.22), Vector3(side * 0.39, 1.79, 0.22), Vector3(side * 0.30, 1.40, 0.29), Vector3(side * 0.23, 1.06, 0.18)], [0.065], "Dark", 4)
		_plate(model, "HarnessBuckle_%s" % side, _rect(0.08, 0.075), 0.055, Vector3(side * 0.32, 1.49, 0.32), "Gold")
	_stone(model, "HunchedHead", Vector3(0, 1.96, 0.32), Vector3(0.24, 0.25, 0.23), "Stone", 8)
	_plate(model, "HeavyBrow", PackedVector2Array([Vector2(-0.22, -0.025), Vector2(0.20, -0.045), Vector2(0.22, 0.07), Vector2(-0.20, 0.09)]), 0.08, Vector3(0, 2.01, 0.52), "Iron")
	for side in [-1.0, 1.0]:
		_plate(model, "RecessedEye_%s" % side, _rect(0.055, 0.022), 0.025, Vector3(side * 0.10, 1.97, 0.545), "Dark")
	_plate(model, "Chin", PackedVector2Array([Vector2(-0.15, -0.09), Vector2(0.15, -0.09), Vector2(0.19, 0.06), Vector2(-0.19, 0.06)]), 0.12, Vector3(0, 1.82, 0.48), "Stone")
	_plate(model, "Mouth", _rect(0.11, 0.017), 0.015, Vector3(0, 1.84, 0.55), "Dark")
	_bell(model, Vector3(0, 1.50, -0.55))
	# Six alternating low-poly links on both sides of the burden.
	for side in [-1.0, 1.0]:
		for link in range(6):
			var center := Vector3(side * (0.46 + 0.024 * link), 2.38 - 0.135 * link, -0.33 + 0.10 * link)
			var points: Array[Vector3] = []
			for point in range(9):
				var angle := TAU * point / 8.0
				var offset := Vector3(cos(angle) * 0.06, sin(angle) * 0.09, 0) if link % 2 == 0 else Vector3(0, sin(angle) * 0.09, cos(angle) * 0.06)
				points.append(center + offset)
			_tube(model, "Chain_%s_%d" % [side, link], points, [0.020], "Dark", 5)
	return model


func _export_model(model: Node3D, id: String, title: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(model, state)
	if error == OK:
		error = document.write_to_filesystem(state, ProjectSettings.globalize_path(OUTPUT + id + ".glb"))
	if error != OK:
		failures.append(id + ": " + error_string(error))
	var bounds := AABB()
	var first := true
	var triangle_count := 0
	var meshes := 0
	var material_names: Array[String] = []
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var local_bounds: AABB = instance.transform * instance.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
		meshes += 1
		for surface_index in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangle_count += (indices.size() if not indices.is_empty() else positions.size()) / 3
		var material := instance.material_override as StandardMaterial3D
		if material.resource_name not in material_names:
			material_names.append(material.resource_name)
	var result := {"id": id, "name": title, "file": id + ".glb", "mesh_count": meshes, "triangles": triangle_count, "materials": material_names, "bounds_min": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z], "animations": [], "rig": "none; static model", "export_error": error_string(error)}
	model.queue_free()
	print("EXPORTED ", id, " ", triangle_count, " triangles ", error_string(error))
	return result
