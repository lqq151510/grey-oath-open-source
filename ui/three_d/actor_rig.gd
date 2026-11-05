extends RefCounted
## 灰誓 · 3D 角色程序化建模器（rig3d）
##
## 纯静态构建：ActorRig.build(spec) -> Node3D。
## 所有网格由 SurfaceTool 逐三角写入三角形自身法线（flat shading），制造硬边块面；
## 不使用任何外部模型或贴图。根节点名 Rig，正面朝 +Z，脚底在 y=0，
## 枢轴层级：Rig/Idle/Hips -> Torso -> Head/ArmL/ArmR/WeaponMount/Cloak，Hips -> LegL/LegR。
## 同一 spec 的两次构建结果完全一致（seed 固定，无全局随机）。

const REQUIRED_PIVOTS := ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR", "WeaponMount", "Cloak"]
## 顶点色烘焙使用的固定主光方向（左前上方），与 actor_view 三点光的亮面朝向一致。
const KEY_LIGHT_DIR := Vector3(-0.52, 0.72, 0.46)


static func build(spec: Dictionary) -> Node3D:
	return Builder.new().run(spec)


static func pivot(rig: Node3D, key: String) -> Node3D:
	if rig == null:
		return null
	return rig.find_child(key, true, false) as Node3D


class Builder extends RefCounted:
	var root: Node3D
	var spec: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	var mats: Dictionary = {}
	var mat_energy: Array[float] = []
	var pal: Dictionary = {}
	var pivots: Dictionary = {}
	var H := 1.9
	var B := 1.0
	var hip_y := 0.485
	var torso_len := 0.335
	var shoulder_x := 0.10
	var arm_len := 0.355
	var head_h := 0.132
	var mesh_count := 0
	var seen_accessories: Dictionary = {}

	# ---------------------------------------------------------------- 入口

	func run(raw_spec: Dictionary) -> Node3D:
		spec = raw_spec.duplicate(true)
		H = clampf(float(spec.get("height", 1.9)), 1.15, 3.4)
		B = clampf(float(spec.get("bulk", 1.0)), 0.70, 1.65)
		rng.seed = int(spec.get("seed", str(spec.get("id", "rig")).hash()))
		hip_y = 0.485 * H
		torso_len = 0.335 * H
		shoulder_x = 0.100 * H * B
		arm_len = 0.355 * H
		head_h = 0.132 * H
		root = Node3D.new()
		root.name = "Rig"
		_setup_palette()
		_make_materials()
		_make_pivots()
		_build_body()
		_extras()
		_apply_weapon(str(spec.get("weapon", "none")))
		_apply_accessories()
		var bounds := _measure_bounds()
		root.set_meta("height", H)
		root.set_meta("impact_y", hip_y + torso_len * 0.58)
		root.set_meta("mesh_count", mesh_count)
		root.set_meta("bounds_height", bounds.size.y)
		root.set_meta("bounds_min_y", bounds.position.y)
		root.set_meta("bounds", bounds)
		root.set_meta("materials", mats)
		root.set_meta("material_energy", mat_energy)
		root.set_meta("pivots", {
			"Hips": "Idle/Hips", "Torso": "Idle/Hips/Torso", "Head": "Idle/Hips/Torso/Head",
			"ArmL": "Idle/Hips/Torso/ArmL", "ArmR": "Idle/Hips/Torso/ArmR",
			"WeaponMount": "Idle/Hips/Torso/ArmR/WeaponMount",
			"LegL": "Idle/Hips/LegL", "LegR": "Idle/Hips/LegR",
			"Cloak": "Idle/Hips/Torso/Cloak",
		})
		return root

	# ---------------------------------------------------------------- 配色 / 材质

	func _c(value: Variant, fallback: Color) -> Color:
		if value is Color:
			return value
		if value is String and not str(value).is_empty():
			return Color(str(value))
		return fallback

	func _setup_palette() -> void:
		var p: Dictionary = spec.get("palette", {})
		if not p is Dictionary:
			p = {}
		var cloth := _c(p.get("cloth", null), Color("3c4239"))
		var metal := _c(p.get("metal", null), Color("737b76"))
		var trim := _c(p.get("trim", null), Color("c7a66a"))
		var accent := _c(p.get("accent", null), Color("c76b57"))
		var skin := _c(p.get("skin", null), Color("c8b29a"))
		var dark := _c(p.get("dark", null), Color("1b201d"))
		pal["cloth"] = cloth
		pal["cloth_dark"] = cloth.darkened(0.24)
		pal["cloth_light"] = cloth.lightened(0.13)
		pal["leather"] = cloth.lerp(Color(0.24, 0.17, 0.12), 0.62)
		pal["metal"] = metal
		pal["metal_dark"] = metal.darkened(0.28)
		pal["metal_light"] = metal.lightened(0.09)
		pal["rust"] = metal.lerp(accent, 0.42).darkened(0.16)
		pal["trim"] = trim
		pal["trim_dark"] = trim.darkened(0.30)
		pal["accent"] = accent
		pal["skin"] = skin
		pal["dark"] = dark
		pal["bone"] = Color("cfc7ab").lerp(accent, 0.06)
		pal["glow"] = accent.lightened(0.42)

	func _make_materials() -> void:
		_mat("cloth", pal["cloth"], 0.0, 0.96, 0.0)
		_mat("cloth_dark", pal["cloth_dark"], 0.0, 0.97, 0.0)
		_mat("cloth_light", pal["cloth_light"], 0.0, 0.93, 0.0)
		_mat("leather", pal["leather"], 0.05, 0.86, 0.0)
		# 旧金属：低金属度 + 高粗糙度，避免三点光下变成白模高光。
		_mat("metal", pal["metal"], 0.30, 0.62, 0.0)
		_mat("metal_dark", pal["metal_dark"], 0.24, 0.70, 0.0)
		_mat("metal_light", pal["metal_light"], 0.34, 0.54, 0.0)
		_mat("rust", pal["rust"], 0.16, 0.84, 0.0)
		_mat("trim", pal["trim"], 0.34, 0.55, 0.0)
		_mat("trim_dark", pal["trim_dark"], 0.26, 0.68, 0.0)
		_mat("accent", pal["accent"], 0.14, 0.72, 0.0)
		_mat("skin", pal["skin"], 0.0, 0.74, 0.0)
		_mat("dark", pal["dark"], 0.10, 0.92, 0.0)
		_mat("bone", pal["bone"], 0.0, 0.72, 0.0)
		_mat("glow", pal["glow"], 0.0, 0.35, 1.9)
		_apply_grain()

	## 程序化脏旧纹理：布料用低频大斑，金属用高频细砂，128×128 无缝平铺。
	## 缓存用弱引用：场景里还有角色时复用同一张，全部释放后纹理也跟着回收。
	static var _grain_cache: Dictionary = {}


	static func grain_texture(kind: String) -> ImageTexture:
		if _grain_cache.has(kind):
			var ref: WeakRef = _grain_cache[kind]
			var cached = ref.get_ref()
			if cached != null:
				return cached
		var fine := kind == "fine"
		var noise := FastNoiseLite.new()
		noise.seed = 5507 if fine else 1701
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.085 if fine else 0.036
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		var floor_value := 0.80 if fine else 0.74
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		for y in size:
			for x in size:
				var u := float(x) / float(size)
				var v := float(y) / float(size)
				# 四角混合做出左右上下都能接边的噪声，避免平铺出现直线接缝。
				var a := noise.get_noise_2d(float(x), float(y))
				var b := noise.get_noise_2d(float(x - size), float(y))
				var c := noise.get_noise_2d(float(x), float(y - size))
				var d := noise.get_noise_2d(float(x - size), float(y - size))
				var raw := lerpf(lerpf(a, b, u), lerpf(c, d, u), v) * 0.5 + 0.5
				var g := clampf(lerpf(floor_value, 1.0, pow(raw, 1.35)), 0.0, 1.0)
				img.set_pixel(x, y, Color(g, g, g))
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		_grain_cache[kind] = weakref(tex)
		return tex

	## 低模没有 UV，统一用三平面投影贴程序化脏旧纹理：
	## 布料是低频大斑，金属是高频细砂，脏一点才不会像刚出模的白塑料。
	func _apply_grain() -> void:
		var coarse := grain_texture("coarse")
		var fine := grain_texture("fine")
		var metal_keys := ["metal", "metal_dark", "metal_light", "trim", "trim_dark", "rust", "bone"]
		for key in mats:
			if key == "glow":
				continue
			var material: StandardMaterial3D = mats[key]
			if material == null:
				continue
			material.uv1_triplanar = true
			material.uv1_triplanar_sharpness = 7.0
			if key in metal_keys:
				material.albedo_texture = fine
				material.uv1_scale = Vector3(2.8, 2.8, 2.8)
			else:
				material.albedo_texture = coarse
				material.uv1_scale = Vector3(2.4, 2.4, 2.4)

	func _mat(key: String, color: Color, metallic: float, roughness: float, emission: float) -> void:
		var material := StandardMaterial3D.new()
		material.resource_name = key
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = clampf(roughness, 0.02, 1.0)
		material.vertex_color_use_as_albedo = true
		material.emission_enabled = true
		material.emission = color if emission > 0.0 else Color(1.0, 0.96, 0.88)
		material.emission_energy_multiplier = emission
		material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		# 布料/皮肤的高光压到 0.22，旧金属保留 0.45：不然三盏灯会在布面上叠出白斑。
		material.metallic_specular = 0.22 + metallic * 0.75
		# 边缘光强化：提升角色剪影立体感与暗部通透度，避免与暗色背景融成一团
		material.rim_enabled = true
		material.rim = 0.40 + metallic * 0.20
		material.rim_tint = 0.35
		# 暗黑灰烬轮廓描边（Inverted Hull Outline）：硬朗低模剪影
		if key != "glow":
			var outline := StandardMaterial3D.new()
			outline.resource_name = key + "_outline"
			outline.cull_mode = BaseMaterial3D.CULL_FRONT
			outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			outline.albedo_color = Color(0.08, 0.09, 0.10, 1.0)
			outline.grow = true
			outline.grow_amount = 0.0035 * clampf(H / 1.9, 0.75, 1.35)
			material.next_pass = outline
		mats[key] = material
		mat_energy.append(emission)

	# ---------------------------------------------------------------- 枢轴

	func _pivot(parent: Node3D, key: String, at: Vector3) -> Node3D:
		var node := Node3D.new()
		node.name = key
		node.position = at
		parent.add_child(node)
		pivots[key] = node
		return node

	func _make_pivots() -> void:
		var idle := Node3D.new()
		idle.name = "Idle"
		root.add_child(idle)
		var hips := _pivot(idle, "Hips", Vector3(0.0, hip_y, 0.0))
		var torso := _pivot(hips, "Torso", Vector3(0.0, 0.02 * H, 0.0))
		_pivot(hips, "LegL", Vector3(-0.062 * H * B, 0.0, 0.0))
		_pivot(hips, "LegR", Vector3(0.062 * H * B, 0.0, 0.0))
		_pivot(torso, "Head", Vector3(0.0, torso_len, 0.004 * H))
		_pivot(torso, "ArmL", Vector3(-shoulder_x, torso_len * 0.86, 0.0))
		_pivot(torso, "ArmR", Vector3(shoulder_x, torso_len * 0.86, 0.0))
		_pivot(pivots["ArmR"], "WeaponMount", Vector3(0.0, -arm_len * 0.94, 0.028 * H))
		_pivot(torso, "Cloak", Vector3(0.0, torso_len * 0.90, -0.066 * H * B))

	# ---------------------------------------------------------------- 底层图元

	func _tri(surf: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inner: Vector3, shade: float) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return
		if n.dot(((a + b + c) / 3.0) - inner) < 0.0:
			var swap := b
			b = c
			c = swap
			n = (b - a).cross(c - a)
			if n.length_squared() < 1e-14:
				return
		n = n.normalized()
		# 按「左前上方主光」把明暗与冷暖直接烘进顶点色：
		# 亮面偏暖、暗面偏冷，低模即使只有几盏实时灯也有手绘中间调。
		var lambert := clampf(n.dot(KEY_LIGHT_DIR) * 0.5 + 0.5, 0.0, 1.0)
		var tone := lerpf(0.82, 1.08, lambert)
		var chroma := Color(0.86, 0.94, 1.06).lerp(Color(1.06, 1.01, 0.92), lambert)
		# 每面轻微色差：近看能读出旧金属/旧布的斑驳，但整体色相不变。
		var tint := shade * tone * rng.randf_range(0.895, 1.045)
		var col := Color(
			clampf(chroma.r * tint, 0.0, 1.30),
			clampf(chroma.g * tint, 0.0, 1.30),
			clampf(chroma.b * tint, 0.0, 1.30),
			1.0
		)
		for vertex in [a, c, b]:
			surf.set_normal(n)
			surf.set_color(col)
			surf.add_vertex(vertex)

	func _quad(surf: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inner: Vector3, shade: float) -> void:
		if (b - a).cross(c - a).dot(((a + b + c + d) * 0.25) - inner) < 0.0:
			var swap := b
			b = d
			d = swap
		_tri(surf, a, b, c, inner, shade)
		_tri(surf, a, c, d, inner, shade)

	func _finish(parent: Node3D, node_name: String, surf: SurfaceTool, key: String) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		node.name = node_name
		node.mesh = _bake_ground_ao(surf.commit(), _pivot_y(parent))
		node.material_override = mats[key]
		parent.add_child(node)
		mesh_count += 1
		return node

	## 构建期枢轴都是零旋转，位置可直接累加成世界高度。
	func _pivot_y(node: Node) -> float:
		var total := 0.0
		var cur := node
		while cur != null:
			if cur is Node3D:
				total += (cur as Node3D).position.y
			cur = cur.get_parent()
		return total

	## Godot 的 Compatibility 渲染器没有 SSAO，低模在纯灯光下会糊成一团。
	## 这里把「离地越高越亮」的遮挡烘焙进顶点色，脚踝、裙摆与下摆先暗下去，
	## 于是同一块布也有明度层次，接近手绘中间调。
	func _bake_ground_ao(mesh: ArrayMesh, base_y: float) -> ArrayMesh:
		if mesh == null or mesh.get_surface_count() == 0:
			return mesh
		var arrays := mesh.surface_get_arrays(0)
		if arrays.size() <= Mesh.ARRAY_COLOR:
			return mesh
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if verts.is_empty() or colors.size() != verts.size():
			return mesh
		var reach := maxf(0.40, H * 0.62)
		var changed := false
		for i in verts.size():
			var t := clampf((verts[i].y + base_y) / reach, 0.0, 1.0)
			var ao := lerpf(0.64, 1.0, t * t * (3.0 - 2.0 * t))
			if ao < 0.999:
				colors[i] = Color(colors[i].r * ao, colors[i].g * ao, colors[i].b * ao, colors[i].a)
				changed = true
		if not changed:
			return mesh
		arrays[Mesh.ARRAY_COLOR] = colors
		var baked := ArrayMesh.new()
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return baked

	func _open() -> SurfaceTool:
		var surf := SurfaceTool.new()
		surf.begin(Mesh.PRIMITIVE_TRIANGLES)
		return surf

	func _loft(parent: Node3D, node_name: String, rings: Array, key: String, sides: int = 8, caps: bool = true, shade: float = 1.0) -> MeshInstance3D:
		var surf := _open()
		var verts: Array = []
		for ring in rings:
			var center: Vector3 = ring[0]
			var rx: float = ring[1]
			var rz: float = ring[2]
			var pts := PackedVector3Array()
			for i in sides:
				var ang := TAU * float(i) / float(sides)
				pts.append(center + Vector3(sin(ang) * rx, 0.0, cos(ang) * rz))
			verts.append(pts)
		for j in range(verts.size() - 1):
			var inner: Vector3 = ((rings[j][0] as Vector3) + (rings[j + 1][0] as Vector3)) * 0.5
			for i in sides:
				var k := (i + 1) % sides
				_quad(surf, verts[j][i], verts[j][k], verts[j + 1][k], verts[j + 1][i], inner, shade)
		if caps and verts.size() > 1:
			var first_center: Vector3 = rings[0][0]
			var last_center: Vector3 = rings[rings.size() - 1][0]
			var low_inner: Vector3 = (first_center + (rings[1][0] as Vector3)) * 0.5
			var high_inner: Vector3 = (last_center + (rings[rings.size() - 2][0] as Vector3)) * 0.5
			for i in sides:
				var k := (i + 1) % sides
				_tri(surf, first_center, verts[0][i], verts[0][k], low_inner, shade)
				_tri(surf, last_center, verts[verts.size() - 1][i], verts[verts.size() - 1][k], high_inner, shade)
		return _finish(parent, node_name, surf, key)

	func _loft_x(parent: Node3D, node_name: String, rings: Array, key: String, sides: int = 6, caps: bool = true, shade: float = 1.0) -> MeshInstance3D:
		var surf := _open()
		var verts: Array = []
		for ring in rings:
			var center: Vector3 = ring[0]
			var ry: float = ring[1]
			var rz: float = ring[2]
			var pts := PackedVector3Array()
			for i in sides:
				var ang := TAU * float(i) / float(sides)
				pts.append(center + Vector3(0.0, cos(ang) * ry, sin(ang) * rz))
			verts.append(pts)
		for j in range(verts.size() - 1):
			var inner: Vector3 = ((rings[j][0] as Vector3) + (rings[j + 1][0] as Vector3)) * 0.5
			for i in sides:
				var k := (i + 1) % sides
				_quad(surf, verts[j][i], verts[j + 1][i], verts[j + 1][k], verts[j][k], inner, shade)
		if caps and verts.size() > 1:
			var first_center: Vector3 = rings[0][0]
			var last_center: Vector3 = rings[rings.size() - 1][0]
			var low_inner: Vector3 = (first_center + (rings[1][0] as Vector3)) * 0.5
			var high_inner: Vector3 = (last_center + (rings[rings.size() - 2][0] as Vector3)) * 0.5
			for i in sides:
				var k := (i + 1) % sides
				_tri(surf, first_center, verts[0][i], verts[0][k], low_inner, shade)
				_tri(surf, last_center, verts[verts.size() - 1][i], verts[verts.size() - 1][k], high_inner, shade)
		return _finish(parent, node_name, surf, key)

	func _tube(parent: Node3D, node_name: String, path: Array, radii: Array, key: String, sides: int = 6, caps: bool = true, shade: float = 1.0) -> MeshInstance3D:
		var surf := _open()
		var rings: Array = []
		var count := path.size()
		for j in count:
			var p: Vector3 = path[j]
			var prev: Vector3 = path[maxi(0, j - 1)]
			var next: Vector3 = path[mini(count - 1, j + 1)]
			var tangent := (next - prev)
			if tangent.length_squared() < 1e-12:
				tangent = Vector3.UP
			tangent = tangent.normalized()
			var helper := Vector3.UP if absf(tangent.y) < 0.94 else Vector3.RIGHT
			var side_axis := tangent.cross(helper).normalized()
			var across := tangent.cross(side_axis).normalized()
			var radius: float = radii[mini(j, radii.size() - 1)]
			var ring := PackedVector3Array()
			for i in sides:
				var ang := TAU * float(i) / float(sides)
				ring.append(p + (side_axis * cos(ang) + across * sin(ang)) * radius)
			rings.append(ring)
		for j in range(count - 1):
			var inner: Vector3 = ((path[j] as Vector3) + (path[j + 1] as Vector3)) * 0.5
			for i in sides:
				var k := (i + 1) % sides
				_quad(surf, rings[j][i], rings[j][k], rings[j + 1][k], rings[j + 1][i], inner, shade)
		if caps and count > 1:
			var inner_a: Vector3 = ((path[0] as Vector3) + (path[1] as Vector3)) * 0.5
			var inner_b: Vector3 = ((path[count - 1] as Vector3) + (path[count - 2] as Vector3)) * 0.5
			for i in sides:
				var k := (i + 1) % sides
				_tri(surf, path[0], rings[0][i], rings[0][k], inner_a, shade)
				_tri(surf, path[count - 1], rings[count - 1][i], rings[count - 1][k], inner_b, shade)
		return _finish(parent, node_name, surf, key)

	func _block(parent: Node3D, node_name: String, center: Vector3, dims: Vector3, key: String, rot: Vector3 = Vector3.ZERO, shade: float = 1.0) -> MeshInstance3D:
		var surf := _open()
		var basis := Basis.from_euler(rot)
		var hx := dims.x * 0.5
		var hy := dims.y * 0.5
		var hz := dims.z * 0.5
		var corners: Array[Vector3] = []
		for ix in [-1.0, 1.0]:
			for iy in [-1.0, 1.0]:
				for iz in [-1.0, 1.0]:
					corners.append(center + basis * Vector3(ix * hx, iy * hy, iz * hz))
		# index: (x,y,z) -> 0..7, x major, then y, then z (z inner)
		var c000 := corners[0]
		var c001 := corners[1]
		var c010 := corners[2]
		var c011 := corners[3]
		var c100 := corners[4]
		var c101 := corners[5]
		var c110 := corners[6]
		var c111 := corners[7]
		var inner := center
		_quad(surf, c001, c101, c111, c011, inner, shade) # +Z
		_quad(surf, c100, c000, c010, c110, inner, shade) # -Z
		_quad(surf, c101, c100, c110, c111, inner, shade) # +X
		_quad(surf, c000, c001, c011, c010, inner, shade) # -X
		_quad(surf, c010, c011, c111, c110, inner, shade) # +Y
		_quad(surf, c000, c100, c101, c001, inner, shade) # -Y
		return _finish(parent, node_name, surf, key)

	func _rect(w: float, h: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)])

	func _plate(parent: Node3D, node_name: String, poly: PackedVector2Array, depth: float, at: Vector3, key: String, shade: float = 1.0) -> MeshInstance3D:
		var surf := _open()
		var indices := Geometry2D.triangulate_polygon(poly)
		if indices.is_empty() and poly.size() >= 3:
			for i in range(1, poly.size() - 1):
				indices.append_array([0, i, i + 1])
		var front := at
		var back := at - Vector3(0.0, 0.0, depth)
		var inner_front := at - Vector3(0.0, 0.0, depth * 1.5)
		var inner_back := at + Vector3(0.0, 0.0, depth * 0.5)
		for i in range(0, indices.size(), 3):
			var pa := poly[indices[i]]
			var pb := poly[indices[i + 1]]
			var pc := poly[indices[i + 2]]
			_tri(surf, front + Vector3(pa.x, pa.y, 0.0), front + Vector3(pb.x, pb.y, 0.0), front + Vector3(pc.x, pc.y, 0.0), inner_front, shade)
			_tri(surf, back + Vector3(pa.x, pa.y, 0.0), back + Vector3(pb.x, pb.y, 0.0), back + Vector3(pc.x, pc.y, 0.0), inner_back, shade)
		var centroid := Vector2.ZERO
		for point in poly:
			centroid += point
		centroid /= float(poly.size())
		var side_inner := Vector3(centroid.x, centroid.y, at.z - depth * 0.5)
		for i in poly.size():
			var k := (i + 1) % poly.size()
			var a := front + Vector3(poly[i].x, poly[i].y, 0.0)
			var b := front + Vector3(poly[k].x, poly[k].y, 0.0)
			var a2 := back + Vector3(poly[i].x, poly[i].y, 0.0)
			var b2 := back + Vector3(poly[k].x, poly[k].y, 0.0)
			_quad(surf, a, b, b2, a2, side_inner, shade)
		return _finish(parent, node_name, surf, key)

	func _ring(parent: Node3D, node_name: String, center: Vector3, radius: float, thickness: float, key: String, segments: int = 10, normal: Vector3 = Vector3.UP, shade: float = 1.0) -> MeshInstance3D:
		var surf := _open()
		var axis := normal.normalized()
		var helper := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var u := axis.cross(helper).normalized()
		var v := axis.cross(u).normalized()
		var rings: Array = []
		for j in segments:
			var ang := TAU * float(j) / float(segments)
			var center_ring := center + (u * cos(ang) + v * sin(ang)) * radius
			var tangent := (u * -sin(ang) + v * cos(ang)).normalized()
			var side_axis := tangent.cross(axis).normalized()
			var ring := PackedVector3Array()
			var sides := 4
			for i in sides:
				var a2 := TAU * float(i) / float(sides)
				ring.append(center_ring + (side_axis * cos(a2) + axis * sin(a2)) * thickness)
			rings.append(ring)
		for j in segments:
			var k := (j + 1) % segments
			var inner: Vector3 = center + (u * cos(TAU * (float(j) + 0.5) / float(segments)) + v * sin(TAU * (float(j) + 0.5) / float(segments))) * radius
			for i in 4:
				var i2 := (i + 1) % 4
				_quad(surf, rings[j][i], rings[j][i2], rings[k][i2], rings[k][i], inner, shade)
		return _finish(parent, node_name, surf, key)

	# ---------------------------------------------------------------- 身体

	func _build_body() -> void:
		var arch := str(spec.get("archetype", "humanoid"))
		match arch:
			"skeleton":
				_humanoid_body({"torso": "bone", "head": "skull", "legs": "bone", "arms": "bone"})
			"knight":
				_humanoid_body({"torso": "armor", "head": "helm", "legs": "armor", "arms": "armor"})
			"caster":
				_humanoid_body({"torso": "robe", "head": "hood", "legs": "thin", "arms": "robe"})
			"sovereign":
				_humanoid_body({"torso": "royal", "head": "crown", "legs": "armor", "arms": "armor"})
			"automaton":
				_humanoid_body({"torso": "gear", "head": "gear", "legs": "gear", "arms": "gear"})
			"giant":
				_humanoid_body({"torso": "giant", "head": "small", "legs": "giant", "arms": "giant"})
			"wraith":
				_wraith_body()
			"beast":
				_beast_body()
			"moth":
				_moth_body()
			"raven":
				_raven_body()
			"worm":
				_worm_body()
			"eye":
				_eye_body()
			"bell":
				_bell_body()
			_:
				_humanoid_body({})

	func _humanoid_body(mods: Dictionary) -> void:
		var torso_style := str(mods.get("torso", "cloth"))
		var head_style := str(mods.get("head", "human"))
		var leg_style := str(mods.get("legs", "human"))
		var arm_style := str(mods.get("arms", "human"))
		var hips := pivots["Hips"] as Node3D
		var torso := pivots["Torso"] as Node3D
		var tl := torso_len
		var torso_w := 1.0
		var chest_depth := 0.074 * H * B
		var chest := 0.110 * H * B
		if torso_style == "armor":
			torso_w = 1.05
		elif torso_style == "robe":
			torso_w = 0.93
		elif torso_style == "royal":
			torso_w = 1.04
		elif torso_style == "giant":
			torso_w = 1.20
		elif torso_style == "gear":
			torso_w = 1.02
		chest *= torso_w

		# 腰胯
		if torso_style != "bone":
			_loft(hips, "Pelvis", [
				[Vector3(0, -0.030 * H, 0.0), 0.082 * H * B, 0.060 * H * B],
				[Vector3(0, 0.050 * H, -0.004 * H), 0.096 * H * B, 0.068 * H * B],
				[Vector3(0, 0.112 * H, 0.0), 0.078 * H * B, 0.056 * H * B],
			], "cloth_dark" if torso_style in ["cloth", "robe", "royal"] else "metal_dark", 8)

		# 躯干
		if torso_style == "bone":
			_bone_torso(torso, tl)
		elif torso_style == "gear":
			_gear_torso(torso, tl)
		else:
			var waist := 0.086 * H * B * torso_w
			var material := "cloth" if torso_style in ["cloth", "robe", "royal"] else "metal"
			_loft(torso, "Torso", [
				[Vector3(0, 0.0, 0.0), waist * 0.94, chest_depth * 0.86],
				[Vector3(0, tl * 0.20, 0.006 * H), waist * 1.06, chest_depth * 0.96],
				[Vector3(0, tl * 0.52, 0.010 * H), chest, chest_depth],
				[Vector3(0, tl * 0.80, 0.004 * H), chest * 0.94, chest_depth * 0.94],
				[Vector3(0, tl * 0.98, 0.0), 0.050 * H, 0.044 * H],
			], material, 9)
			if torso_style in ["armor", "royal"]:
				_plate(torso, "ChestPlate", PackedVector2Array([
					Vector2(-0.92 * chest, -0.20 * tl), Vector2(-1.04 * chest, -0.02 * tl),
					Vector2(-0.72 * chest, 0.20 * tl), Vector2(0.0, 0.235 * tl),
					Vector2(0.72 * chest, 0.20 * tl), Vector2(1.04 * chest, -0.02 * tl),
					Vector2(0.92 * chest, -0.20 * tl), Vector2(0.0, -0.27 * tl),
				]), 0.020 * H, Vector3(0.0, tl * 0.55, chest_depth * 0.86), "metal")
				_tube(torso, "ChestRidge", [Vector3(0, tl * 0.28, chest_depth * 0.98), Vector3(0, tl * 0.72, chest_depth * 0.96)], [0.010 * H], "trim", 4)
				_loft(torso, "Gorget", [
					[Vector3(0, tl * 0.88, 0.0), 0.072 * H, 0.060 * H],
					[Vector3(0, tl * 1.0, 0.0), 0.060 * H, 0.052 * H],
				], "metal", 9)
			elif torso_style == "robe":
				_loft(torso, "Stole", [
					[Vector3(0, tl * 0.30, chest_depth * 0.92), 0.030 * H, 0.012 * H],
					[Vector3(0, tl * 0.90, chest_depth * 0.82), 0.042 * H, 0.012 * H],
				], "trim", 4)
			_loft(torso, "Collar", [
				[Vector3(0, tl * 0.92, 0.0), 0.060 * H, 0.050 * H],
				[Vector3(0, tl * 1.02, 0.0), 0.052 * H, 0.044 * H],
			], "trim_dark" if torso_style != "giant" else "metal_dark", 8)

		# 腰带 / 裙甲 / 长袍
		if torso_style in ["cloth", "armor", "royal", "gear", "giant", "robe"]:
			_loft(hips, "Belt", [
				[Vector3(0, 0.082 * H, 0.0), 0.098 * H * B, 0.070 * H * B],
				[Vector3(0, 0.116 * H, 0.0), 0.092 * H * B, 0.066 * H * B],
			], "leather", 9)
			_block(hips, "Buckle", Vector3(0.0, 0.100 * H, 0.068 * H * B), Vector3(0.055 * H, 0.040 * H, 0.014 * H), "trim")
		if torso_style == "armor":
			for side in [-1.0, 1.0]:
				_plate(hips, "Tasset_%d" % int(side), PackedVector2Array([
					Vector2(-0.042 * H, -0.075 * H), Vector2(0.042 * H, -0.070 * H),
					Vector2(0.038 * H, 0.045 * H), Vector2(-0.038 * H, 0.040 * H),
				]), 0.016 * H, Vector3(side * 0.085 * H * B, 0.045 * H, 0.058 * H * B), "metal")
		if torso_style in ["robe", "royal"]:
			_loft(hips, "RobeSkirt", [
				[Vector3(0, 0.090 * H, 0.0), 0.100 * H * B, 0.076 * H * B],
				[Vector3(0, -0.080 * H, 0.012 * H), 0.150 * H * B, 0.112 * H * B],
				[Vector3(0, -0.260 * H, 0.020 * H), 0.178 * H * B, 0.134 * H * B],
				[Vector3(0, -0.320 * H, 0.022 * H), 0.166 * H * B, 0.126 * H * B],
			], "cloth", 10)
			_loft(hips, "SkirtHem", [
				[Vector3(0, -0.300 * H, 0.022 * H), 0.176 * H * B, 0.132 * H * B],
				[Vector3(0, -0.332 * H, 0.022 * H), 0.170 * H * B, 0.128 * H * B],
			], "trim_dark", 10)

		# 腿
		_leg("LegL", -1.0, leg_style)
		_leg("LegR", 1.0, leg_style)

		# 肩甲 / 手臂
		if torso_style in ["armor", "royal", "gear"]:
			_pauldron(torso, -1.0, tl * 0.84, 1.06 if torso_style == "armor" else 0.94)
			_pauldron(torso, 1.0, tl * 0.84, 1.0 if torso_style == "armor" else 0.92)
		_arm("ArmL", -1.0, arm_style)
		_arm("ArmR", 1.0, arm_style)

		# 头
		_head(head_style)

	func _bone_torso(torso: Node3D, tl: float) -> void:
		for i in 7:
			var y := tl * (0.04 + 0.135 * float(i))
			_loft(torso, "Spine_%d" % i, [
				[Vector3(0, y - 0.012 * H, -0.010 * H), 0.020 * H, 0.020 * H],
				[Vector3(0, y + 0.012 * H, -0.010 * H), 0.023 * H, 0.022 * H],
			], "bone", 6)
		for row in 4:
			var y := tl * (0.20 + 0.145 * float(row))
			var width := (0.080 + 0.012 * float(row)) * H * B
			for side in [-1.0, 1.0]:
				_tube(torso, "Rib_%d_%d" % [row, int(side)], [
					Vector3(0.0, y + 0.012 * H, -0.018 * H),
					Vector3(side * width * 0.7, y + 0.008 * H, -0.030 * H),
					Vector3(side * width, y - 0.002 * H, 0.004 * H),
					Vector3(side * width * 0.72, y - 0.014 * H, 0.042 * H),
					Vector3(side * 0.016 * H, y - 0.020 * H, 0.050 * H),
				], [0.008 * H, 0.010 * H, 0.009 * H, 0.008 * H, 0.006 * H], "bone", 4)
		_tube(torso, "Sternum", [Vector3(0, tl * 0.18, 0.046 * H), Vector3(0, tl * 0.78, 0.044 * H)], [0.010 * H, 0.012 * H], "bone", 5)
		_tube(torso, "CollarBone", [Vector3(-0.085 * H * B, tl * 0.90, 0.010 * H), Vector3(0.085 * H * B, tl * 0.90, 0.010 * H)], [0.009 * H], "bone", 5)
		_loft(torso, "BonePelvis", [
			[Vector3(0, tl * 0.02, 0.0), 0.050 * H, 0.036 * H],
			[Vector3(0, tl * 0.07, 0.0), 0.062 * H, 0.042 * H],
		], "bone", 7)

	func _gear_torso(torso: Node3D, tl: float) -> void:
		_block(torso, "GearChest", Vector3(0, tl * 0.56, 0.010 * H), Vector3(0.190 * H * B, tl * 0.50, 0.120 * H * B), "metal")
		_block(torso, "GearAbdomen", Vector3(0, tl * 0.20, 0.006 * H), Vector3(0.150 * H * B, tl * 0.28, 0.104 * H * B), "metal_dark")
		_block(torso, "GearCore", Vector3(0, tl * 0.54, 0.072 * H * B), Vector3(0.070 * H, 0.070 * H, 0.020 * H), "glow")
		_ring(torso, "GearCoreRing", Vector3(0, tl * 0.54, 0.080 * H * B), 0.056 * H, 0.010 * H, "trim", 12, Vector3.FORWARD)
		for i in 3:
			_tube(torso, "GearPipe_%d" % i, [
				Vector3((-0.6 + 0.6 * i) * 0.09 * H, tl * 0.28, 0.055 * H * B),
				Vector3((-0.4 + 0.4 * i) * 0.09 * H, tl * 0.66, 0.060 * H * B),
			], [0.008 * H], "rust", 4)
		for side in [-1.0, 1.0]:
			_block(torso, "GearRivet_%d" % int(side), Vector3(side * 0.082 * H * B, tl * 0.80, 0.056 * H * B), Vector3(0.020 * H, 0.020 * H, 0.016 * H), "trim")

	# ---------------------------------------------------------------- 头

	func _head(key: String) -> void:
		var head := pivots["Head"] as Node3D
		var hh := head_h
		var wr := 0.060 * H
		if key == "small":
			hh *= 0.78
			wr *= 0.78
		var neck_mat := "metal_dark" if key in ["helm", "gear"] else "skin"
		_tube(head, "Neck", [Vector3(0, -0.040 * H, -0.004 * H), Vector3(0, 0.014 * H, 0.002 * H)], [0.030 * H, 0.034 * H], neck_mat, 6)

		match key:
			"skull":
				_loft(head, "Cranium", [
					[Vector3(0, 0.008 * H, 0.0), wr * 0.86, wr * 0.94],
					[Vector3(0, hh * 0.42, 0.0), wr, wr * 1.02],
					[Vector3(0, hh * 0.78, -0.004 * H), wr * 0.90, wr * 0.96],
					[Vector3(0, hh * 0.98, -0.010 * H), wr * 0.46, wr * 0.50],
				], "bone", 8)
				_loft(head, "Muzzle", [
					[Vector3(0, hh * 0.10, 0.030 * H), wr * 0.54, wr * 0.52],
					[Vector3(0, hh * 0.38, 0.040 * H), wr * 0.68, wr * 0.60],
				], "bone", 6)
				for side in [-1.0, 1.0]:
					_plate(head, "Socket_%d" % int(side), PackedVector2Array([
						Vector2(-0.020 * H, -0.013 * H), Vector2(0.018 * H, -0.016 * H),
						Vector2(0.022 * H, 0.014 * H), Vector2(-0.016 * H, 0.017 * H),
					]), 0.008 * H, Vector3(side * wr * 0.42, hh * 0.56, wr * 0.93), "dark")
					_plate(head, "Cheek_%d" % int(side), _rect(0.012 * H, 0.016 * H), 0.010 * H, Vector3(side * wr * 0.92, hh * 0.30, wr * 0.36), "bone")
					_loft_x(head, "CheekBone_%d" % int(side), [
						[Vector3(side * wr * 0.48, hh * 0.42, 0.030 * H), 0.010 * H, 0.014 * H],
						[Vector3(side * wr * 0.96, hh * 0.38, 0.010 * H), 0.008 * H, 0.012 * H],
					], "bone", 5)
				_block(head, "Jaw", Vector3(0, hh * 0.10, 0.026 * H), Vector3(wr * 1.24, hh * 0.20, wr * 0.92), "bone")
				for tooth in 5:
					_block(head, "Tooth_%d" % tooth, Vector3((-2.0 + float(tooth)) * 0.011 * H, hh * 0.20, wr * 0.64), Vector3(0.008 * H, 0.016 * H, 0.010 * H), "bone")
				_plate(head, "NoseCavity", PackedVector2Array([
					Vector2(-0.010 * H, -0.012 * H), Vector2(0.010 * H, -0.012 * H), Vector2(0.0, 0.012 * H),
				]), 0.008 * H, Vector3(0, hh * 0.40, wr * 0.98), "dark")
			"helm":
				_loft(head, "Helm", [
					[Vector3(0, -0.004 * H, 0.0), wr * 0.94, wr * 1.0],
					[Vector3(0, hh * 0.46, 0.0), wr * 1.04, wr * 1.06],
					[Vector3(0, hh * 0.92, -0.004 * H), wr * 0.90, wr * 0.94],
					[Vector3(0, hh * 1.06, -0.012 * H), wr * 0.34, wr * 0.40],
				], "metal", 9)
				# 面甲：压暗整张脸，只留一条暗缝，避免头盔变成一块高光白块。
				_plate(head, "FacePlate", PackedVector2Array([
					Vector2(-wr * 0.84, -0.030 * H), Vector2(wr * 0.84, -0.030 * H),
					Vector2(wr * 0.92, hh * 0.30), Vector2(wr * 0.34, hh * 0.62),
					Vector2(0.0, hh * 0.70), Vector2(-wr * 0.34, hh * 0.62),
					Vector2(-wr * 0.92, hh * 0.30),
				]), 0.016 * H, Vector3(0, hh * 0.48, wr * 0.99), "metal_dark")
				_block(head, "VisorSlit", Vector3(0, hh * 0.54, wr * 1.03), Vector3(wr * 1.52, hh * 0.085, 0.010 * H), "dark")
				_block(head, "VisorBrow", Vector3(0, hh * 0.64, wr * 1.01), Vector3(wr * 1.58, hh * 0.055, 0.014 * H), "trim_dark")
				for side in [-1.0, 1.0]:
					_block(head, "CheekGuard_%d" % int(side), Vector3(side * wr * 0.84, hh * 0.26, wr * 0.86), Vector3(0.020 * H, hh * 0.30, wr * 0.30), "trim_dark", Vector3(0.0, side * 0.28, 0.0))
				_plate(head, "NoseGuard", PackedVector2Array([
					Vector2(-0.012 * H, -0.036 * H), Vector2(0.012 * H, -0.036 * H),
					Vector2(0.009 * H, 0.030 * H), Vector2(-0.009 * H, 0.030 * H),
				]), 0.014 * H, Vector3(0, hh * 0.46, wr * 1.10), "trim")
				_plate(head, "Crest", PackedVector2Array([
					Vector2(-0.010 * H, -0.070 * H), Vector2(0.020 * H, -0.030 * H),
					Vector2(0.034 * H, 0.020 * H), Vector2(0.012 * H, 0.062 * H),
					Vector2(-0.006 * H, 0.028 * H), Vector2(-0.016 * H, -0.020 * H),
				]), 0.014 * H, Vector3(0, hh * 1.0, -0.010 * H), "accent")
				for i in 4:
					_block(head, "HelmRivet_%d" % i, Vector3((-1.5 + float(i)) * wr * 0.55, hh * 0.86, wr * 0.72), Vector3(0.008 * H, 0.008 * H, 0.008 * H), "trim")
			"hood", "void":
				_loft(head, "Face", [
					[Vector3(0, 0.0, 0.010 * H), wr * 0.72, wr * 0.76],
					[Vector3(0, hh * 0.52, 0.010 * H), wr * 0.84, wr * 0.86],
					[Vector3(0, hh * 0.94, 0.002 * H), wr * 0.60, wr * 0.66],
				], "dark" if key == "void" else "skin", 7)
				_loft(head, "Hood", [
					[Vector3(0, -0.030 * H, -0.004 * H), wr * 1.04, wr * 1.06],
					[Vector3(0, hh * 0.52, -0.004 * H), wr * 1.14, wr * 1.16],
					[Vector3(0, hh * 1.02, -0.010 * H), wr * 0.82, wr * 0.90],
					[Vector3(0, hh * 1.16, -0.026 * H), wr * 0.22, wr * 0.30],
				], "cloth", 9)
				_plate(head, "HoodRim", PackedVector2Array([
					Vector2(-wr * 1.0, -0.018 * H), Vector2(-wr * 0.92, 0.030 * H),
					Vector2(0.0, 0.040 * H), Vector2(wr * 0.92, 0.030 * H),
					Vector2(wr * 1.0, -0.018 * H), Vector2(0.0, -0.006 * H),
				]), 0.010 * H, Vector3(0, hh * 0.42, wr * 1.02), "cloth_dark")
				if key == "void":
					for side in [-1.0, 1.0]:
						_block(head, "HoodEye_%d" % int(side), Vector3(side * wr * 0.30, hh * 0.56, wr * 0.80), Vector3(0.014 * H, 0.009 * H, 0.010 * H), "glow")
				else:
					for side in [-1.0, 1.0]:
						_block(head, "Eye_%d" % int(side), Vector3(side * wr * 0.31, hh * 0.54, wr * 0.82), Vector3(0.014 * H, 0.008 * H, 0.008 * H), "dark")
			"crown":
				_loft(head, "Skull", [
					[Vector3(0, 0.004 * H, 0.004 * H), wr * 0.86, wr * 0.92],
					[Vector3(0, hh * 0.46, 0.004 * H), wr, wr],
					[Vector3(0, hh * 0.84, 0.0), wr * 0.90, wr * 0.92],
					[Vector3(0, hh, -0.006 * H), wr * 0.44, wr * 0.48],
				], "skin", 8)
				_loft(head, "Jaw", [
					[Vector3(0, -0.012 * H, 0.012 * H), wr * 0.60, wr * 0.58],
					[Vector3(0, hh * 0.28, 0.014 * H), wr * 0.76, wr * 0.70],
				], "skin", 6)
				for side in [-1.0, 1.0]:
					_block(head, "Eye_%d" % int(side), Vector3(side * wr * 0.32, hh * 0.54, wr * 0.85), Vector3(0.016 * H, 0.007 * H, 0.008 * H), "dark")
				_tube(head, "Nose", [Vector3(0, hh * 0.58, wr * 0.86), Vector3(0, hh * 0.36, wr * 1.0)], [0.009 * H, 0.007 * H], "skin", 4)
				_loft(head, "Hair", [
					[Vector3(0, hh * 0.72, -0.004 * H), wr * 1.04, wr * 1.02],
					[Vector3(0, hh * 1.0, -0.008 * H), wr * 0.92, wr * 0.94],
					[Vector3(0, hh * 1.12, -0.026 * H), wr * 0.34, wr * 0.40],
				], "dark", 8)
				for i in 6:
					var a := TAU * float(i) / 6.0
					var cx := cos(a) * wr * 0.78
					var cz := sin(a) * wr * 0.78 - 0.010 * H
					_tube(head, "CrownSpike_%d" % i, [
						Vector3(cx, hh * 0.94, cz), Vector3(cx * 1.06, hh * 1.10, cz * 1.06), Vector3(cx * 1.14, hh * 1.28, cz * 1.14),
					], [0.014 * H, 0.010 * H, 0.003 * H], "trim", 4)
				_ring(head, "CrownBand", Vector3(0, hh * 0.98, -0.006 * H), wr * 0.86, 0.011 * H, "trim", 12)
			"gear":
				_block(head, "GearHead", Vector3(0, hh * 0.50, 0.004 * H), Vector3(wr * 1.66, hh * 0.92, wr * 1.50), "metal")
				_block(head, "GearVisor", Vector3(0, hh * 0.58, wr * 0.76), Vector3(wr * 1.20, hh * 0.16, 0.012 * H), "dark")
				for side in [-1.0, 1.0]:
					_block(head, "GearEye_%d" % int(side), Vector3(side * wr * 0.34, hh * 0.58, wr * 0.80), Vector3(0.014 * H, hh * 0.09, 0.010 * H), "glow")
				_tube(head, "Antenna", [Vector3(0, hh * 0.95, -0.010 * H), Vector3(wr * 0.30, hh * 1.18, -0.030 * H), Vector3(wr * 0.52, hh * 1.30, -0.050 * H)], [0.008 * H, 0.006 * H, 0.002 * H], "rust", 4)
				_block(head, "GearJaw", Vector3(0, hh * 0.14, wr * 0.30), Vector3(wr * 1.0, hh * 0.16, wr * 1.0), "metal_dark")
			"beak":
				_block(head, "BirdHead", Vector3(0, hh * 0.46, 0.006 * H), Vector3(wr * 1.30, hh * 0.82, wr * 1.40), "dark")
				_tube(head, "Beak", [
					Vector3(0, hh * 0.46, wr * 0.52), Vector3(0, hh * 0.40, wr * 1.10), Vector3(0, hh * 0.34, wr * 1.52),
				], [0.024 * H, 0.016 * H, 0.003 * H], "trim", 5)
				for side in [-1.0, 1.0]:
					_block(head, "BirdEye_%d" % int(side), Vector3(side * wr * 0.46, hh * 0.60, wr * 0.62), Vector3(0.014 * H, 0.012 * H, 0.010 * H), "glow")
			_:
				_loft(head, "Skull", [
					[Vector3(0, 0.004 * H, 0.004 * H), wr * 0.86, wr * 0.92],
					[Vector3(0, hh * 0.46, 0.004 * H), wr, wr],
					[Vector3(0, hh * 0.84, 0.0), wr * 0.90, wr * 0.92],
					[Vector3(0, hh, -0.006 * H), wr * 0.44, wr * 0.48],
				], "skin", 8)
				_loft(head, "Jaw", [
					[Vector3(0, -0.012 * H, 0.012 * H), wr * 0.60, wr * 0.58],
					[Vector3(0, hh * 0.28, 0.014 * H), wr * 0.76, wr * 0.70],
				], "skin", 6)
				_block(head, "Brow", Vector3(0, hh * 0.66, wr * 0.80), Vector3(wr * 1.50, hh * 0.10, 0.012 * H), "skin")
				for side in [-1.0, 1.0]:
					_block(head, "Eye_%d" % int(side), Vector3(side * wr * 0.32, hh * 0.54, wr * 0.85), Vector3(0.016 * H, 0.007 * H, 0.008 * H), "dark")
				_tube(head, "Nose", [Vector3(0, hh * 0.58, wr * 0.86), Vector3(0, hh * 0.36, wr * 1.0)], [0.009 * H, 0.007 * H], "skin", 4)
				_loft(head, "Hair", [
					[Vector3(0, hh * 0.74, -0.004 * H), wr * 1.06, wr * 1.04],
					[Vector3(0, hh * 1.02, -0.010 * H), wr * 0.90, wr * 0.94],
					[Vector3(0, hh * 1.10, -0.028 * H), wr * 0.30, wr * 0.36],
				], "dark", 8)

	# ---------------------------------------------------------------- 四肢

	func _leg(key: String, side: float, style: String) -> void:
		var leg := pivots[key] as Node3D
		var knee := -0.236 * H
		var ankle := -0.446 * H
		var bottom := -hip_y + 0.001 * H
		var thick := 1.0
		if style == "giant":
			thick = 1.45
		elif style == "bone":
			thick = 0.72
		elif style == "thin":
			thick = 0.82
		var flesh := "skin"
		var outer := "cloth"
		if style in ["armor", "giant"]:
			flesh = "metal_dark"
			outer = "metal"
		elif style == "gear":
			flesh = "metal_dark"
			outer = "metal"
		elif style == "bone":
			flesh = "bone"
			outer = "bone"
		if style == "gear":
			_block(leg, "ThighBlock", Vector3(0.0, knee * 0.45, 0.004 * H), Vector3(0.070 * H * B, -knee * 0.86, 0.074 * H * B), "metal_dark")
			_block(leg, "ShinBlock", Vector3(0.0, (knee + ankle) * 0.5, 0.012 * H), Vector3(0.060 * H * B, (ankle - knee) * 0.94, 0.066 * H * B), "metal")
			_block(leg, "AnkleJoint", Vector3(0.0, ankle, 0.010 * H), Vector3(0.066 * H * B, 0.030 * H, 0.070 * H), "rust")
			_block(leg, "GearFoot", Vector3(0.0, bottom + 0.020 * H, 0.030 * H), Vector3(0.080 * H * B, 0.042 * H, 0.150 * H), "metal_dark")
			return
		if style == "hoof":
			_tube(leg, "Thigh", [Vector3(0, 0.01 * H, 0.0), Vector3(0, knee * 0.55, 0.010 * H), Vector3(0, knee, 0.020 * H)], [0.038 * H * B, 0.042 * H * B, 0.030 * H * B], "cloth_dark", 6)
			_tube(leg, "Calf", [Vector3(0, knee, 0.020 * H), Vector3(0, (knee + ankle) * 0.5, -0.020 * H), Vector3(0, ankle, 0.006 * H)], [0.030 * H * B, 0.024 * H * B, 0.018 * H * B], "cloth_dark", 6)
			_block(leg, "Hoof", Vector3(0, bottom + 0.022 * H, 0.030 * H), Vector3(0.062 * H * B, 0.048 * H, 0.086 * H), "dark")
			return
		if style == "talon":
			_tube(leg, "BirdThigh", [Vector3(0, 0.01 * H, 0.0), Vector3(0, knee * 0.6, -0.010 * H), Vector3(0, knee, 0.006 * H)], [0.034 * H * B], "dark", 5)
			_tube(leg, "BirdShin", [Vector3(0, knee, 0.006 * H), Vector3(0, ankle, 0.0)], [0.018 * H * B], "dark", 5)
			for toe in 3:
				var tx := (float(toe) - 1.0) * 0.030 * H
				_tube(leg, "Talon_%d" % toe, [
					Vector3(0, ankle, 0.010 * H), Vector3(tx, ankle + 0.010 * H, 0.050 * H), Vector3(tx * 1.4, bottom, 0.090 * H),
				], [0.010 * H, 0.008 * H, 0.003 * H], "bone", 4)
			return
		# 大腿 / 小腿
		_tube(leg, "Thigh", [
			Vector3(0, 0.012 * H, 0.0), Vector3(side * 0.004 * H, knee * 0.55, 0.008 * H), Vector3(0, knee, 0.014 * H),
		], [0.040 * H * B * thick, 0.036 * H * B * thick, 0.028 * H * B * thick], "skin" if style == "bone" else (flesh if style in ["armor", "giant"] else "cloth_dark"), 6)
		_loft(leg, "Knee", [
			[Vector3(0, knee - 0.016 * H, 0.012 * H), 0.030 * H * B * thick, 0.026 * H * B],
			[Vector3(0, knee + 0.016 * H, 0.015 * H), 0.034 * H * B * thick, 0.030 * H * B],
		], "metal_light" if style in ["armor", "giant"] else ("bone" if style == "bone" else "cloth_dark"), 6)
		_tube(leg, "Shin", [
			Vector3(0, knee, 0.014 * H), Vector3(side * 0.002 * H, (knee + ankle) * 0.5, 0.006 * H), Vector3(0, ankle, 0.004 * H),
		], [0.026 * H * B * thick, 0.023 * H * B * thick, 0.017 * H * B * thick], flesh if style == "armor" else ("bone" if style == "bone" else "cloth_dark"), 6)
		if style == "bone":
			for toe in 3:
				var tx := (float(toe) - 1.0) * 0.030 * H
				_tube(leg, "BoneToe_%d" % toe, [
					Vector3(0, ankle, 0.010 * H), Vector3(tx, ankle + 0.008 * H, 0.060 * H), Vector3(tx, bottom + 0.010 * H, 0.110 * H),
				], [0.010 * H, 0.008 * H, 0.005 * H], "bone", 4)
			return
		# 靴 / 护胫
		_loft(leg, "Greave", [
			[Vector3(0, ankle + 0.010 * H, 0.008 * H), 0.030 * H * B, 0.030 * H * B],
			[Vector3(0, ankle - 0.018 * H, 0.020 * H), 0.036 * H * B, 0.046 * H * B],
			[Vector3(0, bottom + 0.030 * H, 0.018 * H), 0.030 * H * B, 0.044 * H * B],
		], outer if style in ["armor", "giant"] else "leather", 7)
		_block(leg, "Foot", Vector3(0, bottom + 0.018 * H, 0.052 * H), Vector3(0.070 * H * B, 0.036 * H, 0.130 * H), "metal_dark" if style in ["armor", "giant"] else "leather")
		_block(leg, "ToeCap", Vector3(0, bottom + 0.012 * H, 0.112 * H), Vector3(0.052 * H * B, 0.024 * H, 0.038 * H), "metal" if style in ["armor", "giant"] else "dark")

	func _arm(key: String, side: float, style: String) -> void:
		var arm := pivots[key] as Node3D
		var elbow := -0.180 * H
		var wrist := -0.322 * H
		var thick := 1.0
		if style == "giant":
			thick = 1.5
		elif style == "bone":
			thick = 0.7
		elif style == "robe":
			thick = 0.95
		var upper_mat := "skin"
		var fore_mat := "skin"
		if style in ["armor", "giant"]:
			upper_mat = "metal_dark"
			fore_mat = "metal"
		elif style == "gear":
			upper_mat = "metal_dark"
			fore_mat = "metal"
		elif style == "bone":
			upper_mat = "bone"
			fore_mat = "bone"
		elif style == "robe":
			upper_mat = "cloth"
			fore_mat = "skin"
		else:
			upper_mat = "cloth_dark"
			fore_mat = "skin"
		if style == "gear":
			_block(arm, "UpperArmBlock", Vector3(side * 0.010 * H, elbow * 0.45, 0.004 * H), Vector3(0.062 * H * B, -elbow * 0.82, 0.066 * H * B), "metal_dark")
			_block(arm, "ElbowJoint", Vector3(side * 0.014 * H, elbow, 0.012 * H), Vector3(0.064 * H * B, 0.036 * H, 0.070 * H), "rust")
			_block(arm, "ForearmBlock", Vector3(side * 0.020 * H, (elbow + wrist) * 0.5, 0.020 * H), Vector3(0.058 * H * B, (wrist - elbow) * 0.86, 0.062 * H * B), "metal")
			_block(arm, "GearHand", Vector3(side * 0.022 * H, wrist - 0.020 * H, 0.030 * H), Vector3(0.058 * H * B, 0.062 * H, 0.056 * H), "metal_dark")
			return
		_tube(arm, "UpperArm", [
			Vector3(0, 0.006 * H, 0.0), Vector3(side * 0.006 * H, elbow * 0.5, 0.006 * H), Vector3(side * 0.010 * H, elbow, 0.010 * H),
		], [0.038 * H * B * thick, 0.032 * H * B * thick, 0.024 * H * B * thick], upper_mat, 6)
		if style == "robe":
			_loft_x(arm, "Sleeve", [
				[Vector3(side * 0.004 * H, 0.0, 0.0), 0.030 * H * B, 0.030 * H * B],
				[Vector3(side * 0.016 * H, elbow * 0.55, 0.012 * H), 0.050 * H * B, 0.050 * H * B],
				[Vector3(side * 0.030 * H, elbow * 0.96, 0.024 * H), 0.070 * H * B, 0.066 * H * B],
			], "cloth", 7, false)
		if style in ["armor", "giant"]:
			_loft(arm, "ElbowCop", [
				[Vector3(side * 0.012 * H, elbow - 0.018 * H, 0.012 * H), 0.030 * H * B, 0.030 * H * B],
				[Vector3(side * 0.012 * H, elbow + 0.014 * H, 0.012 * H), 0.034 * H * B, 0.032 * H * B],
			], "metal_light", 6)
		elif style == "bone":
			_loft(arm, "ElbowBone", [
				[Vector3(side * 0.008 * H, elbow - 0.012 * H, 0.010 * H), 0.020 * H, 0.018 * H],
				[Vector3(side * 0.008 * H, elbow + 0.012 * H, 0.010 * H), 0.022 * H, 0.020 * H],
			], "bone", 5)
		_tube(arm, "Forearm", [
			Vector3(side * 0.010 * H, elbow, 0.010 * H), Vector3(side * 0.018 * H, (elbow + wrist) * 0.5, 0.020 * H), Vector3(side * 0.020 * H, wrist, 0.026 * H),
		], [0.026 * H * B * thick, 0.023 * H * B * thick, 0.018 * H * B * thick], fore_mat, 6)
		if style in ["armor", "giant"]:
			_loft(arm, "Vambrace", [
				[Vector3(side * 0.018 * H, wrist + 0.020 * H, 0.024 * H), 0.026 * H * B, 0.028 * H * B],
				[Vector3(side * 0.020 * H, wrist - 0.002 * H, 0.026 * H), 0.022 * H * B, 0.024 * H * B],
			], "metal", 7)
		# 手
		_block(arm, "Hand", Vector3(side * 0.020 * H, wrist - 0.028 * H, 0.032 * H), Vector3(0.048 * H * B, 0.052 * H, 0.042 * H), "metal_dark" if style in ["armor", "gear", "giant"] else "skin")
		for finger in 3:
			_block(arm, "Finger_%d" % finger, Vector3(side * 0.020 * H + (float(finger) - 1.0) * 0.012 * H, wrist - 0.054 * H, 0.044 * H), Vector3(0.009 * H, 0.020 * H, 0.012 * H), "skin" if style not in ["armor", "gear", "giant"] else "metal_dark")

	func _pauldron(parent: Node3D, side: float, y: float, size_scale: float) -> void:
		var label := "L" if side < 0.0 else "R"
		var cx := side * shoulder_x * 0.96
		_loft_x(parent, "Pauldron_" + label, [
			[Vector3(cx - side * 0.052 * H, y + 0.010 * H, 0.0), 0.052 * H * size_scale, 0.056 * H * size_scale],
			[Vector3(cx + side * 0.008 * H, y + 0.020 * H, 0.0), 0.070 * H * size_scale, 0.072 * H * size_scale],
			[Vector3(cx + side * 0.072 * H, y - 0.014 * H, 0.0), 0.044 * H * size_scale, 0.048 * H * size_scale],
		], "metal", 7)
		_loft_x(parent, "PauldronTrim_" + label, [
			[Vector3(cx + side * 0.030 * H, y + 0.006 * H, 0.0), 0.066 * H * size_scale, 0.068 * H * size_scale],
			[Vector3(cx + side * 0.048 * H, y - 0.002 * H, 0.0), 0.058 * H * size_scale, 0.060 * H * size_scale],
		], "trim", 7)

	# ---------------------------------------------------------------- 异形体型

	func _wraith_body() -> void:
		var hips := pivots["Hips"] as Node3D
		var torso := pivots["Torso"] as Node3D
		var tl := torso_len
		_loft(torso, "WraithCore", [
			[Vector3(0, -0.03 * H, 0.0), 0.070 * H, 0.056 * H],
			[Vector3(0, tl * 0.45, 0.0), 0.086 * H, 0.062 * H],
			[Vector3(0, tl * 0.90, 0.0), 0.060 * H, 0.048 * H],
		], "cloth_dark", 8)
		_loft(hips, "WraithRobe", [
			[Vector3(0, 0.10 * H, 0.0), 0.104 * H, 0.078 * H],
			[Vector3(0, -0.16 * H, 0.010 * H), 0.150 * H, 0.112 * H],
			[Vector3(0, -0.40 * H, 0.020 * H), 0.190 * H, 0.142 * H],
			[Vector3(0, -0.455 * H, 0.020 * H), 0.150 * H, 0.112 * H],
		], "cloth", 10)
		for i in 5:
			var ang := TAU * float(i) / 5.0
			_block(hips, "Tatter_%d" % i, Vector3(cos(ang) * 0.130 * H, -0.470 * H, sin(ang) * 0.100 * H + 0.010 * H), Vector3(0.040 * H, 0.060 * H, 0.020 * H), "cloth_dark", Vector3(0.0, ang, 0.0))
		_head("void")
		for side in [-1.0, 1.0]:
			_tube(pivots["Arm" + ("L" if side < 0.0 else "R")], "WraithArm", [
				Vector3(0, 0.0, 0.0), Vector3(side * 0.030 * H, -0.14 * H, 0.020 * H), Vector3(side * 0.050 * H, -0.28 * H, 0.060 * H),
			], [0.026 * H, 0.020 * H, 0.014 * H], "cloth_dark", 5)
			for finger in 3:
				_tube(pivots["Arm" + ("L" if side < 0.0 else "R")], "WraithClaw_%d_%d" % [int(side), finger], [
					Vector3(side * 0.050 * H, -0.28 * H, 0.060 * H),
					Vector3(side * (0.050 + float(finger - 1) * 0.014) * H, -0.34 * H, 0.110 * H),
					Vector3(side * (0.050 + float(finger - 1) * 0.020) * H, -0.37 * H, 0.180 * H),
				], [0.008 * H, 0.005 * H, 0.0015 * H], "bone", 4)
		pivots["Hips"].position.y = 0.50 * H
		pivots["LegL"].visible = false
		pivots["LegR"].visible = false

	func _beast_body() -> void:
		var hips := pivots["Hips"] as Node3D
		var torso := pivots["Torso"] as Node3D
		hips.position = Vector3(0.0, 0.54 * H, 0.0)
		# 四足躯干：沿 Z 横置，肩高臀低，块面分明。
		_loft_x(torso, "BeastBody", [
			[Vector3(0, 0.020 * H, -0.20 * H), 0.062 * H, 0.070 * H],
			[Vector3(0, 0.040 * H, -0.08 * H), 0.086 * H, 0.096 * H],
			[Vector3(0, 0.050 * H, 0.06 * H), 0.096 * H, 0.104 * H],
			[Vector3(0, 0.036 * H, 0.18 * H), 0.080 * H, 0.088 * H],
			[Vector3(0, 0.020 * H, 0.26 * H), 0.056 * H, 0.060 * H],
		], "cloth_dark", 8)
		for i in 5:
			var t := float(i) / 4.0
			_tube(torso, "BeastSpine_%d" % i, [
				Vector3(0, 0.128 * H - 0.040 * H * t, -0.17 * H + 0.36 * H * t),
				Vector3(0, 0.168 * H - 0.050 * H * t, -0.165 * H + 0.36 * H * t),
			], [0.016 * H, 0.005 * H], "bone", 4)
		for side in [-1.0, 1.0]:
			var leg := pivots["Leg" + ("L" if side < 0.0 else "R")] as Node3D
			leg.position = Vector3(side * 0.070 * H, -0.030 * H, -0.12 * H)
			_tube(leg, "Haunch", [Vector3(0, 0.02 * H, 0.0), Vector3(side * 0.012 * H, -0.16 * H, -0.030 * H), Vector3(side * 0.016 * H, -0.30 * H, -0.045 * H)], [0.058 * H, 0.040 * H, 0.026 * H], "cloth_dark", 6)
			_tube(leg, "Hock", [Vector3(side * 0.016 * H, -0.30 * H, -0.045 * H), Vector3(side * 0.014 * H, -0.42 * H, -0.006 * H), Vector3(side * 0.014 * H, -0.505 * H, 0.030 * H)], [0.028 * H, 0.020 * H, 0.015 * H], "dark", 5)
			_block(leg, "Paw", Vector3(side * 0.014 * H, -0.518 * H, 0.062 * H), Vector3(0.070 * H, 0.044 * H, 0.110 * H), "dark")
		for side in [-1.0, 1.0]:
			var arm := pivots["Arm" + ("L" if side < 0.0 else "R")] as Node3D
			arm.position = Vector3(side * 0.078 * H, 0.020 * H, 0.20 * H)
			_tube(arm, "Foreleg", [Vector3(0, 0, 0), Vector3(side * 0.014 * H, -0.24 * H, 0.030 * H), Vector3(side * 0.018 * H, -0.480 * H, 0.060 * H)], [0.048 * H, 0.032 * H, 0.022 * H], "cloth_dark", 6)
			_block(arm, "ForePaw", Vector3(side * 0.018 * H, -0.545 * H, 0.096 * H), Vector3(0.072 * H, 0.044 * H, 0.110 * H), "dark")
			for claw in 3:
				_tube(arm, "BeastClaw_%d_%d" % [int(side), claw], [
					Vector3(side * 0.018 * H + (float(claw) - 1.0) * 0.018 * H, -0.548 * H, 0.146 * H),
					Vector3(side * 0.018 * H + (float(claw) - 1.0) * 0.024 * H, -0.556 * H, 0.196 * H),
				], [0.008 * H, 0.002 * H], "bone", 4)
		_tube(torso, "BeastNeck", [Vector3(0, 0.050 * H, 0.20 * H), Vector3(0, 0.110 * H, 0.28 * H)], [0.054 * H, 0.044 * H], "cloth_dark", 6)
		var head := pivots["Head"] as Node3D
		head.position = Vector3(0.0, 0.130 * H, 0.30 * H)
		_block(head, "BeastHead", Vector3(0, 0.020 * H, 0.020 * H), Vector3(0.150 * H, 0.120 * H, 0.180 * H), "dark")
		_block(head, "BeastSnout", Vector3(0, -0.006 * H, 0.130 * H), Vector3(0.096 * H, 0.070 * H, 0.110 * H), "dark")
		for side in [-1.0, 1.0]:
			_block(head, "BeastEye_%d" % int(side), Vector3(side * 0.045 * H, 0.046 * H, 0.096 * H), Vector3(0.020 * H, 0.014 * H, 0.014 * H), "glow")
			_tube(head, "BeastHorn_%d" % int(side), [
				Vector3(side * 0.058 * H, 0.070 * H, 0.010 * H), Vector3(side * 0.078 * H, 0.108 * H, -0.030 * H), Vector3(side * 0.100 * H, 0.140 * H, -0.085 * H),
			], [0.018 * H, 0.012 * H, 0.002 * H], "bone", 4)
		for tooth in 4:
			_block(head, "Fang_%d" % tooth, Vector3((float(tooth) - 1.5) * 0.022 * H, -0.032 * H, 0.152 * H), Vector3(0.012 * H, 0.034 * H, 0.012 * H), "bone")
		_tube(hips, "Tail", [
			Vector3(0, 0.010 * H, -0.20 * H), Vector3(0, 0.040 * H, -0.32 * H), Vector3(0, 0.140 * H, -0.40 * H), Vector3(0, 0.250 * H, -0.42 * H),
		], [0.030 * H, 0.022 * H, 0.014 * H, 0.005 * H], "dark", 5)

	func _moth_body() -> void:
		_humanoid_body({"torso": "cloth", "head": "hood", "legs": "human", "arms": "bone"})
		var torso := pivots["Torso"] as Node3D
		var hips := pivots["Hips"] as Node3D
		# 毛领
		_loft(torso, "FurCollar", [
			[Vector3(0, torso_len * 0.86, 0.0), 0.088 * H, 0.078 * H],
			[Vector3(0, torso_len * 0.95, 0.0), 0.100 * H, 0.088 * H],
			[Vector3(0, torso_len * 1.02, 0.0), 0.070 * H, 0.062 * H],
		], "cloth_light", 10, false)
		# 蛾腹：向后下垂的节段，暗灰蓝布料 + 骨白环 + 灯芯橙点。
		_loft(hips, "MothAbdomen", [
			[Vector3(0, 0.040 * H, -0.060 * H), 0.074 * H, 0.086 * H],
			[Vector3(0, -0.090 * H, -0.110 * H), 0.064 * H, 0.078 * H],
			[Vector3(0, -0.220 * H, -0.140 * H), 0.042 * H, 0.052 * H],
			[Vector3(0, -0.310 * H, -0.150 * H), 0.016 * H, 0.022 * H],
		], "cloth_dark", 9)
		for i in 3:
			_ring(hips, "MothAbdomenBand_%d" % i, Vector3(0, -0.020 * H - 0.085 * H * float(i), -0.078 * H - 0.020 * H * float(i)), 0.070 * H - 0.015 * H * float(i), 0.006 * H, "trim_dark", 10)
		_ring(hips, "MothLantern", Vector3(0, -0.150 * H, -0.180 * H), 0.026 * H, 0.008 * H, "glow", 10, Vector3.FORWARD)
		# 翅膀挂在 Cloak 枢轴：两对叠层 + 暗色翼脉 + 灯芯橙眼斑。
		var cloak := pivots["Cloak"] as Node3D
		for side in [-1.0, 1.0]:
			for pair in 2:
				var span := (0.30 + 0.10 * float(pair)) * H
				var rise := (0.16 + 0.10 * float(pair)) * H
				_plate(cloak, "Wing_%d_%d" % [int(side), pair], PackedVector2Array([
					Vector2(0.0, 0.02 * H), Vector2(side * span * 0.55, 0.05 * H + rise * 0.4),
					Vector2(side * span, 0.02 * H + rise), Vector2(side * span * 0.82, -0.10 * H + rise * 0.3),
					Vector2(side * span * 0.38, -0.12 * H), Vector2(side * 0.10 * H, -0.06 * H + float(pair) * 0.03 * H),
				]), 0.010 * H, Vector3(0.0, -0.02 * H - float(pair) * 0.05 * H, -0.030 * H), ["cloth_dark", "cloth"][pair])
				_tube(cloak, "WingRib_%d_%d" % [int(side), pair], [
					Vector3(side * 0.02 * H, 0.04 * H, -0.038 * H),
					Vector3(side * span * 0.52, 0.10 * H + rise * 0.4, -0.040 * H),
					Vector3(side * span * 0.96, 0.02 * H + rise * 0.9, -0.040 * H),
				], [0.009 * H, 0.006 * H, 0.002 * H], "trim_dark", 4)
				_ring(cloak, "WingEye_%d_%d" % [int(side), pair], Vector3(side * span * 0.50, 0.06 * H + rise * 0.42, -0.046 * H), 0.026 * H, 0.004 * H, "accent", 10, Vector3.FORWARD)
		var head := pivots["Head"] as Node3D
		for side in [-1.0, 1.0]:
			_tube(head, "Antenna_%d" % int(side), [
				Vector3(side * 0.040 * H, head_h * 0.92, 0.030 * H), Vector3(side * 0.070 * H, head_h * 1.20, 0.020 * H), Vector3(side * 0.100 * H, head_h * 1.34, -0.020 * H),
			], [0.007 * H, 0.005 * H, 0.002 * H], "dark", 4)
		for side in [-1.0, 1.0]:
			_block(head, "MothEye_%d" % int(side), Vector3(side * 0.040 * H, head_h * 0.56, 0.060 * H), Vector3(0.034 * H, 0.030 * H, 0.016 * H), "glow")

	func _raven_body() -> void:
		var hips := pivots["Hips"] as Node3D
		var torso := pivots["Torso"] as Node3D
		hips.position = Vector3(0.0, 0.46 * H, 0.0)
		torso.rotation.x = 0.30
		_loft(torso, "RavenBody", [
			[Vector3(0, -0.02 * H, -0.12 * H), 0.090 * H, 0.100 * H],
			[Vector3(0, 0.06 * H, 0.04 * H), 0.110 * H, 0.115 * H],
			[Vector3(0, 0.12 * H, 0.16 * H), 0.080 * H, 0.085 * H],
		], "dark", 8)
		for side in [-1.0, 1.0]:
			var leg := pivots["Leg" + ("L" if side < 0.0 else "R")] as Node3D
			leg.position = Vector3(side * 0.060 * H, -0.02 * H, 0.0)
			_tube(leg, "RavenLeg", [Vector3(0, 0.02 * H, 0.0), Vector3(side * 0.012 * H, -0.22 * H, 0.020 * H), Vector3(side * 0.016 * H, -0.40 * H, 0.0)], [0.030 * H, 0.018 * H, 0.012 * H], "dark", 5)
			for toe in 3:
				_tube(leg, "RavenTalon_%d_%d" % [int(side), toe], [
					Vector3(side * 0.016 * H, -0.42 * H, 0.0),
					Vector3(side * 0.016 * H + (float(toe) - 1.0) * 0.026 * H, -0.455 * H, 0.050 * H),
					Vector3(side * 0.016 * H + (float(toe) - 1.0) * 0.036 * H, -0.465 * H, 0.090 * H),
				], [0.008 * H, 0.006 * H, 0.002 * H], "bone", 4)
		var cloak := pivots["Cloak"] as Node3D
		for side in [-1.0, 1.0]:
			_plate(cloak, "RavenWing_%d" % int(side), PackedVector2Array([
				Vector2(0.0, 0.06 * H), Vector2(side * 0.26 * H, 0.10 * H),
				Vector2(side * 0.44 * H, 0.02 * H), Vector2(side * 0.34 * H, -0.16 * H),
				Vector2(side * 0.16 * H, -0.22 * H), Vector2(side * 0.04 * H, -0.10 * H),
			]), 0.012 * H, Vector3(0, -0.03 * H, -0.02 * H), "cloth_dark")
			for feather in 3:
				_tube(cloak, "WingBone_%d_%d" % [int(side), feather], [
					Vector3(0, 0.05 * H, -0.03 * H),
					Vector3(side * 0.18 * H, 0.06 * H - float(feather) * 0.05 * H, -0.04 * H),
					Vector3(side * 0.40 * H, 0.04 * H - float(feather) * 0.10 * H, -0.05 * H),
				], [0.010 * H, 0.007 * H, 0.003 * H], "bone", 4)
		var head := pivots["Head"] as Node3D
		head.position = Vector3(0.0, torso_len * 0.92, 0.16 * H)
		_head("beak")
		# 尾羽
		for feather in 4:
			_plate(hips, "TailFeather_%d" % feather, PackedVector2Array([
				Vector2(-0.018 * H, 0.0), Vector2(0.018 * H, 0.0),
				Vector2((float(feather) - 1.5) * 0.020 * H, -0.30 * H - float(feather % 2) * 0.06 * H),
			]), 0.008 * H, Vector3(0, -0.04 * H, -0.14 * H - float(feather) * 0.012 * H), "dark")

	func _worm_body() -> void:
		var hips := pivots["Hips"] as Node3D
		var torso := pivots["Torso"] as Node3D
		hips.position = Vector3(0.0, 0.16 * H, 0.0)
		# 盘绕的身体：从尾部地面到抬起的前段
		for i in 8:
			var t := float(i) / 7.0
			# 尾巴贴地、身体呈 S 形抬起，避免整条虫悬空。
			var center := Vector3(sin(t * 5.0) * 0.08 * H, -0.145 * H + 0.520 * H * pow(t, 1.55) + sin(t * 3.2) * 0.10 * H, 0.34 * H - t * 0.50 * H)
			var r := (0.085 - 0.030 * t) * H
			_loft(torso, "Segment_%d" % i, [
				[center + Vector3(0, -0.035 * H, 0), r * 0.92, r * 0.92],
				[center + Vector3(0, 0.035 * H, 0), r, r],
			], "cloth_dark" if i % 2 == 0 else "cloth", 7)
			_ring(torso, "SegmentBand_%d" % i, center, r * 1.02, 0.008 * H, "rust", 10, Vector3.UP)
		var head := pivots["Head"] as Node3D
		head.position = Vector3(0.0, 0.600 * H, -0.20 * H)
		_loft(head, "WormHead", [
			[Vector3(0, -0.06 * H, 0.0), 0.070 * H, 0.090 * H],
			[Vector3(0, 0.04 * H, 0.03 * H), 0.062 * H, 0.078 * H],
		], "dark", 7)
		for side in [-1.0, 1.0]:
			_tube(head, "Mandible_%d" % int(side), [
				Vector3(side * 0.050 * H, 0.0, 0.060 * H), Vector3(side * 0.090 * H, -0.02 * H, 0.110 * H), Vector3(side * 0.100 * H, -0.06 * H, 0.170 * H),
			], [0.014 * H, 0.010 * H, 0.002 * H], "bone", 4)
			_block(head, "WormEye_%d" % int(side), Vector3(side * 0.045 * H, 0.035 * H, 0.070 * H), Vector3(0.018 * H, 0.014 * H, 0.012 * H), "glow")
		pivots["LegL"].visible = false
		pivots["LegR"].visible = false
		pivots["ArmL"].visible = false
		pivots["ArmR"].visible = false

	func _eye_body() -> void:
		var torso := pivots["Torso"] as Node3D
		torso.position.y = 0.58 * H
		_loft(torso, "EyeMass", [
			[Vector3(0, -0.18 * H, 0.0), 0.050 * H, 0.050 * H],
			[Vector3(0, -0.10 * H, 0.0), 0.150 * H, 0.140 * H],
			[Vector3(0, 0.0, 0.0), 0.200 * H, 0.185 * H],
			[Vector3(0, 0.12 * H, 0.0), 0.165 * H, 0.150 * H],
			[Vector3(0, 0.20 * H, 0.0), 0.070 * H, 0.070 * H],
		], "cloth_dark", 10)
		_ring(torso, "EyeIris", Vector3(0, 0.02 * H, 0.150 * H), 0.095 * H, 0.022 * H, "accent", 14, Vector3.FORWARD)
		_loft(torso, "EyePupil", [
			[Vector3(0, -0.06 * H, 0.170 * H), 0.030 * H, 0.030 * H],
			[Vector3(0, 0.04 * H, 0.175 * H), 0.040 * H, 0.040 * H],
			[Vector3(0, 0.10 * H, 0.168 * H), 0.018 * H, 0.018 * H],
		], "dark", 8, true, 0.9)
		_ring(torso, "EyeHalo", Vector3(0, 0.02 * H, -0.02 * H), 0.260 * H, 0.010 * H, "trim", 20)
		for i in 6:
			var ang := TAU * float(i) / 6.0
			_tube(torso, "Tentacle_%d" % i, [
				Vector3(cos(ang) * 0.13 * H, -0.10 * H, sin(ang) * 0.13 * H),
				Vector3(cos(ang) * 0.24 * H, -0.24 * H, sin(ang) * 0.20 * H),
				Vector3(cos(ang) * 0.30 * H, -0.390 * H, sin(ang) * 0.24 * H),
			], [0.022 * H, 0.014 * H, 0.004 * H], "cloth_dark", 5)
		pivots["Hips"].position.y = 0.0
		# 触须脚尖落地：眼体 0.40H 高，避免整只眼悬浮。
		torso.position.y = 0.400 * H
		pivots["LegL"].visible = false
		pivots["LegR"].visible = false
		pivots["Head"].visible = false
		pivots["ArmL"].visible = false
		pivots["ArmR"].visible = false

	func _bell_body() -> void:
		var hips := pivots["Hips"] as Node3D
		var torso := pivots["Torso"] as Node3D
		hips.position = Vector3(0.0, 0.20 * H, 0.0)
		# 钟体：钟口朝下、肩部收窄；旧铜色靠块面与锈斑区分。
		_loft(torso, "BellBody", [
			[Vector3(0, 0.070 * H, 0.0), 0.236 * H * B, 0.204 * H * B],
			[Vector3(0, 0.140 * H, 0.0), 0.222 * H * B, 0.192 * H * B],
			[Vector3(0, 0.300 * H, 0.0), 0.190 * H * B, 0.164 * H * B],
			[Vector3(0, 0.480 * H, 0.0), 0.148 * H * B, 0.128 * H * B],
			[Vector3(0, 0.640 * H, 0.0), 0.098 * H * B, 0.086 * H * B],
			[Vector3(0, 0.740 * H, 0.0), 0.056 * H * B, 0.052 * H * B],
		], "metal", 14)
		_loft(torso, "BellLip", [
			[Vector3(0, 0.056 * H, 0.0), 0.246 * H * B, 0.212 * H * B],
			[Vector3(0, 0.100 * H, 0.0), 0.228 * H * B, 0.198 * H * B],
		], "trim", 14)
		_loft(torso, "BellMouth", [
			[Vector3(0, 0.052 * H, 0.0), 0.220 * H * B, 0.190 * H * B],
			[Vector3(0, 0.075 * H, 0.0), 0.205 * H * B, 0.176 * H * B],
		], "dark", 12, true, 0.5)
		for i in 5:
			var ang := TAU * float(i) / 5.0 + 0.3
			_block(torso, "BellRune_%d" % i, Vector3(cos(ang) * 0.150 * H * B, 0.430 * H, sin(ang) * 0.126 * H * B), Vector3(0.018 * H, 0.052 * H, 0.014 * H), "trim_dark", Vector3(0.0, -ang, 0.0))
		_ring(torso, "BellCrown", Vector3(0, 0.742 * H, 0.0), 0.058 * H, 0.010 * H, "trim", 12)
		_tube(torso, "ClapperStem", [Vector3(0, 0.300 * H, 0.0), Vector3(0, 0.046 * H, 0.0)], [0.012 * H], "dark", 5)
		_loft(torso, "Clapper", [
			[Vector3(0, 0.006 * H, 0.0), 0.020 * H, 0.020 * H],
			[Vector3(0, 0.030 * H, 0.0), 0.038 * H, 0.038 * H],
			[Vector3(0, 0.060 * H, 0.0), 0.024 * H, 0.024 * H],
		], "trim", 8)
		for side in [-1.0, 1.0]:
			_block(torso, "BellEye_%d" % int(side), Vector3(side * 0.062 * H, 0.470 * H, 0.126 * H * B), Vector3(0.034 * H, 0.020 * H, 0.014 * H), "glow")
			var arm := pivots["Arm" + ("L" if side < 0.0 else "R")] as Node3D
			arm.position = Vector3(side * 0.196 * H * B, 0.360 * H, 0.0)
			_tube(arm, "BellArm", [
				Vector3(0, 0, 0), Vector3(side * 0.030 * H, -0.120 * H, 0.026 * H), Vector3(side * 0.044 * H, -0.230 * H, 0.052 * H),
			], [0.034 * H, 0.026 * H, 0.017 * H], "metal_dark", 6)
			_block(arm, "BellHand", Vector3(side * 0.044 * H, -0.252 * H, 0.060 * H), Vector3(0.052 * H, 0.050 * H, 0.048 * H), "metal_dark")
			var leg := pivots["Leg" + ("L" if side < 0.0 else "R")] as Node3D
			_tube(leg, "BellLeg", [Vector3(0, 0.010 * H, 0.0), Vector3(side * 0.012 * H, -0.090 * H, 0.012 * H), Vector3(side * 0.014 * H, -0.160 * H, 0.024 * H)], [0.030 * H, 0.024 * H, 0.018 * H], "metal_dark", 6)
			_block(leg, "BellFoot", Vector3(side * 0.014 * H, -0.180 * H, 0.036 * H), Vector3(0.058 * H, 0.040 * H, 0.090 * H), "dark")
		pivots["Head"].visible = false

	# ---------------------------------------------------------------- 配件 / 武器

	func _extras() -> void:
		var extras: Array = spec.get("extras", [])
		for item in extras:
			match str(item):
				"coat_tails":
					for side in [-1.0, 1.0]:
						_plate(pivots["Hips"], "CoatTail_%d" % int(side), PackedVector2Array([
							Vector2(-0.055 * H, 0.0), Vector2(0.055 * H, 0.0),
							Vector2(0.070 * H, -0.30 * H), Vector2(0.020 * H, -0.26 * H),
							Vector2(-0.030 * H, -0.32 * H), Vector2(-0.060 * H, -0.24 * H),
						]), 0.010 * H, Vector3(side * 0.070 * H, 0.070 * H, -0.055 * H * B), "cloth_dark")
				"layers":
					for i in 6:
						var ang := TAU * float(i) / 6.0
						_plate(pivots["Hips"], "Layer_%d" % i, PackedVector2Array([
							Vector2(-0.024 * H, 0.02 * H), Vector2(0.024 * H, 0.02 * H),
							Vector2(0.020 * H, -0.26 * H), Vector2(-0.018 * H, -0.30 * H),
						]), 0.008 * H, Vector3(cos(ang) * 0.14 * H, 0.08 * H, sin(ang) * 0.10 * H), "cloth")
				"hunch":
					(pivots["Torso"] as Node3D).rotation.x = 0.14

	func _apply_weapon(key: String) -> void:
		if key == "" or key == "none":
			return
		var mount := pivots["WeaponMount"] as Node3D
		var sway := Vector3(deg_to_rad(-6.0), 0.0, deg_to_rad(-10.0))
		match key:
			"sword":
				# 剑尖朝前下方：待机时剑身离开躯干轮廓，不再被身体挡住。
				sway = Vector3(deg_to_rad(-26.0), 0.0, deg_to_rad(-8.0))
			"scythe":
				sway = Vector3(deg_to_rad(-4.0), 0.0, deg_to_rad(-14.0))
			"hammer":
				sway = Vector3(deg_to_rad(-8.0), 0.0, deg_to_rad(-8.0))
		mount.rotation = sway
		match key:
			"sword":
				_weapon_sword(mount)
			"spear":
				_weapon_spear(mount)
			"staff":
				_weapon_staff(mount, str(spec.get("staff_top", "orb")))
			"scythe":
				_weapon_scythe(mount)
			"claw":
				_weapon_claw(mount)
			"hammer":
				_weapon_hammer(mount)
			"banner":
				_weapon_banner(mount)
			"bell":
				_weapon_bell(mount)
			_:
				_weapon_sword(mount)

	func _weapon_sword(parent: Node3D) -> void:
		# 手持剑：剑尖从手部朝前下方垂落，剪影完整、不贴进躯干。
		_plate(parent, "Blade", PackedVector2Array([
			Vector2(-0.014 * H, -0.075 * H), Vector2(0.014 * H, -0.075 * H),
			Vector2(0.018 * H, -0.330 * H), Vector2(0.006 * H, -0.385 * H),
			Vector2(0.0, -0.480 * H), Vector2(-0.015 * H, -0.360 * H),
			Vector2(-0.018 * H, -0.245 * H),
		]), 0.012 * H, Vector3(0, 0, 0.010 * H), "metal_light")
		_block(parent, "BladeRidge", Vector3(0, -0.260 * H, 0.014 * H), Vector3(0.008 * H, 0.300 * H, 0.008 * H), "metal")
		_block(parent, "Guard", Vector3(0, -0.062 * H, 0.010 * H), Vector3(0.152 * H, 0.020 * H, 0.036 * H), "trim")
		for side in [-1.0, 1.0]:
			_block(parent, "GuardTip_%d" % int(side), Vector3(side * 0.070 * H, -0.070 * H, 0.010 * H), Vector3(0.022 * H, 0.040 * H, 0.026 * H), "trim_dark")
		_tube(parent, "Grip", [Vector3(0, -0.052 * H, 0.010 * H), Vector3(0, 0.070 * H, 0.010 * H)], [0.013 * H], "leather", 5)
		_block(parent, "Pommel", Vector3(0, 0.084 * H, 0.010 * H), Vector3(0.036 * H, 0.032 * H, 0.036 * H), "trim")

	func _weapon_spear(parent: Node3D) -> void:
		_tube(parent, "SpearShaft", [Vector3(0, -0.210 * H, 0.010 * H), Vector3(0, 0.520 * H, 0.010 * H)], [0.011 * H], "leather", 6)
		_plate(parent, "SpearHead", PackedVector2Array([
			Vector2(-0.026 * H, 0.500 * H), Vector2(0.0, 0.660 * H), Vector2(0.026 * H, 0.500 * H), Vector2(0.0, 0.462 * H),
		]), 0.012 * H, Vector3(0, 0, 0.010 * H), "metal_light")
		_block(parent, "SpearCollar", Vector3(0, 0.492 * H, 0.010 * H), Vector3(0.036 * H, 0.020 * H, 0.026 * H), "trim")
		_plate(parent, "SpearRibbon", PackedVector2Array([
			Vector2(0.0, 0.470 * H), Vector2(0.050 * H, 0.430 * H), Vector2(0.030 * H, 0.330 * H), Vector2(0.010 * H, 0.380 * H),
		]), 0.006 * H, Vector3(0, 0, 0.010 * H), "accent")

	func _weapon_staff(parent: Node3D, top: String) -> void:
		_tube(parent, "StaffShaft", [Vector3(0, -0.220 * H, 0.010 * H), Vector3(0, 0.480 * H, 0.010 * H)], [0.013 * H], "leather", 6)
		_ring(parent, "StaffBand", Vector3(0, 0.300 * H, 0.010 * H), 0.020 * H, 0.007 * H, "trim", 10, Vector3.UP)
		match top:
			"star":
				_ring(parent, "StaffHalo", Vector3(0, 0.560 * H, 0.010 * H), 0.070 * H, 0.010 * H, "trim", 14, Vector3.FORWARD)
				for i in 4:
					var ang := TAU * float(i) / 4.0 + 0.4
					_tube(parent, "StarRay_%d" % i, [
						Vector3(cos(ang) * 0.060 * H, 0.560 * H + sin(ang) * 0.060 * H, 0.010 * H),
						Vector3(cos(ang) * 0.120 * H, 0.560 * H + sin(ang) * 0.120 * H, 0.010 * H),
					], [0.010 * H, 0.002 * H], "trim", 4)
				_block(parent, "StarCore", Vector3(0, 0.560 * H, 0.010 * H), Vector3(0.040 * H, 0.040 * H, 0.030 * H), "glow")
			"lantern":
				_tube(parent, "LanternHook", [Vector3(0, 0.480 * H, 0.010 * H), Vector3(0.050 * H, 0.560 * H, 0.010 * H), Vector3(0.050 * H, 0.600 * H, 0.010 * H)], [0.008 * H], "metal_dark", 4)
				_lantern(Vector3(0.050 * H, 0.560 * H, 0.010 * H), 0.75, parent)
			"censer":
				_ring(parent, "CenserHalo", Vector3(0, 0.590 * H, 0.010 * H), 0.060 * H, 0.008 * H, "trim", 14, Vector3.FORWARD)
				_tube(parent, "CenserChain", [Vector3(0, 0.520 * H, 0.010 * H), Vector3(0, 0.550 * H, 0.010 * H)], [0.004 * H], "trim_dark", 4)
				_loft(parent, "Censer", [
					[Vector3(0, 0.470 * H, 0.010 * H), 0.024 * H, 0.024 * H],
					[Vector3(0, 0.500 * H, 0.010 * H), 0.036 * H, 0.036 * H],
					[Vector3(0, 0.532 * H, 0.010 * H), 0.020 * H, 0.020 * H],
				], "trim", 8)
				_block(parent, "CenserGlow", Vector3(0, 0.480 * H, 0.010 * H), Vector3(0.030 * H, 0.026 * H, 0.030 * H), "glow")
			_:
				_loft(parent, "StaffHead", [
					[Vector3(0, 0.470 * H, 0.010 * H), 0.018 * H, 0.018 * H],
					[Vector3(0, 0.520 * H, 0.010 * H), 0.030 * H, 0.030 * H],
					[Vector3(0, 0.560 * H, 0.010 * H), 0.014 * H, 0.014 * H],
				], "trim", 7)
				_ring(parent, "StaffRing", Vector3(0, 0.600 * H, 0.010 * H), 0.045 * H, 0.008 * H, "trim", 14, Vector3.FORWARD)
				_block(parent, "StaffOrb", Vector3(0, 0.600 * H, 0.010 * H), Vector3(0.034 * H, 0.034 * H, 0.030 * H), "glow")

	func _weapon_scythe(parent: Node3D) -> void:
		_tube(parent, "ScytheShaft", [Vector3(0, -0.240 * H, 0.010 * H), Vector3(0, 0.430 * H, 0.010 * H)], [0.014 * H], "dark", 6)
		# 刀身以杆顶为根部张开，内缘回收到杆上，避免刀与杆之间出现空洞。
		var base := 0.430 * H
		var blade := PackedVector2Array([
			Vector2(0.0, base), Vector2(0.058 * H, base + 0.118 * H),
			Vector2(0.156 * H, base + 0.152 * H), Vector2(0.258 * H, base + 0.112 * H),
			Vector2(0.196 * H, base + 0.042 * H), Vector2(0.106 * H, base + 0.006 * H),
			Vector2(0.032 * H, base - 0.052 * H),
		])
		_plate(parent, "ScytheBlade", blade, 0.012 * H, Vector3(0, 0, 0.010 * H), "metal_light")
		_block(parent, "ScytheSocket", Vector3(0, base + 0.018 * H, 0.010 * H), Vector3(0.044 * H, 0.070 * H, 0.036 * H), "trim")
		_block(parent, "ScytheFerrule", Vector3(0, base - 0.010 * H, 0.010 * H), Vector3(0.036 * H, 0.030 * H, 0.030 * H), "trim")
		_tube(parent, "ScytheChain", [Vector3(0, 0.360 * H, 0.010 * H), Vector3(0.050 * H, 0.300 * H, 0.030 * H), Vector3(0.030 * H, 0.240 * H, 0.050 * H)], [0.005 * H], "trim_dark", 4)

	func _weapon_claw(parent: Node3D) -> void:
		for i in 3:
			var spread := (float(i) - 1.0) * 0.026 * H
			_tube(parent, "Claw_%d" % i, [
				Vector3(spread, -0.040 * H, 0.020 * H), Vector3(spread * 1.4, -0.120 * H, 0.090 * H), Vector3(spread * 1.8, -0.200 * H, 0.150 * H),
			], [0.012 * H, 0.008 * H, 0.0015 * H], "bone", 4)
		_block(parent, "ClawGuard", Vector3(0, -0.030 * H, 0.020 * H), Vector3(0.090 * H, 0.024 * H, 0.030 * H), "metal_dark")

	func _weapon_hammer(parent: Node3D) -> void:
		_tube(parent, "HammerShaft", [Vector3(0, -0.120 * H, 0.010 * H), Vector3(0, 0.258 * H, 0.010 * H)], [0.016 * H], "leather", 6)
		_block(parent, "HammerHead", Vector3(0, 0.300 * H, 0.010 * H), Vector3(0.228 * H, 0.112 * H, 0.104 * H), "metal")
		_block(parent, "HammerBand", Vector3(0, 0.300 * H, 0.010 * H), Vector3(0.238 * H, 0.028 * H, 0.112 * H), "rust")
		for side in [-1.0, 1.0]:
			_block(parent, "HammerFace_%d" % int(side), Vector3(side * 0.120 * H, 0.300 * H, 0.010 * H), Vector3(0.022 * H, 0.092 * H, 0.094 * H), "metal_dark")

	func _weapon_banner(parent: Node3D) -> void:
		_tube(parent, "BannerPole", [Vector3(0, -0.220 * H, 0.010 * H), Vector3(0, 0.560 * H, 0.010 * H)], [0.010 * H], "dark", 6)
		_plate(parent, "BannerFlag", PackedVector2Array([
			Vector2(0.006 * H, 0.520 * H), Vector2(0.170 * H, 0.470 * H), Vector2(0.150 * H, 0.380 * H),
			Vector2(0.168 * H, 0.300 * H), Vector2(0.090 * H, 0.330 * H), Vector2(0.060 * H, 0.280 * H),
			Vector2(0.006 * H, 0.320 * H),
		]), 0.006 * H, Vector3(0, 0, 0.010 * H), "cloth_light")
		_ring(parent, "BannerFinial", Vector3(0, 0.590 * H, 0.010 * H), 0.024 * H, 0.007 * H, "trim", 10, Vector3.FORWARD)

	func _weapon_bell(parent: Node3D) -> void:
		_tube(parent, "BellHandle", [Vector3(0, -0.100 * H, 0.010 * H), Vector3(0, 0.010 * H, 0.010 * H)], [0.012 * H], "trim_dark", 5)
		_loft(parent, "HandBell", [
			[Vector3(0, 0.010 * H, 0.010 * H), 0.040 * H, 0.040 * H],
			[Vector3(0, 0.030 * H, 0.010 * H), 0.062 * H, 0.062 * H],
			[Vector3(0, 0.100 * H, 0.010 * H), 0.054 * H, 0.054 * H],
			[Vector3(0, 0.150 * H, 0.010 * H), 0.030 * H, 0.030 * H],
			[Vector3(0, 0.165 * H, 0.010 * H), 0.014 * H, 0.014 * H],
		], "trim", 9, false)
		_ring(parent, "BellRim", Vector3(0, 0.020 * H, 0.010 * H), 0.060 * H, 0.008 * H, "trim_dark", 12)
		_block(parent, "BellClapper", Vector3(0, -0.002 * H, 0.010 * H), Vector3(0.024 * H, 0.034 * H, 0.024 * H), "dark")
		for i in 2:
			_ring(parent, "EchoRing_%d" % i, Vector3(0, 0.120 * H + 0.090 * H * float(i + 1), 0.010 * H), 0.050 * H * float(i + 1), 0.004 * H, "accent", 14, Vector3.FORWARD)

	func _apply_accessories() -> void:
		var list: Array = spec.get("accessories", [])
		for entry in list:
			var key := str(entry)
			if seen_accessories.get(key, false):
				continue
			seen_accessories[key] = true
			match key:
				"cloak":
					_cloak()
				"hood":
					_hood()
				"horns":
					_horns()
				"crown":
					_crown()
				"wings":
					_wings()
				"shield":
					_shield()
				"lantern":
					_lantern(Vector3(0.130 * H, -0.020 * H, 0.020 * H), 1.0, pivots["Hips"])
				"chains":
					_chains()
				"mask":
					_mask()
				"books":
					_books()

	func _cloak() -> void:
		var cloak := pivots["Cloak"] as Node3D
		var span := 0.150 * H * B
		var drop := 0.520 * H
		var tatter := PackedVector2Array([
			Vector2(-span, -0.020 * H), Vector2(-span * 0.95, -drop * 0.55),
			Vector2(-span * 0.62, -drop * 0.92), Vector2(-span * 0.30, -drop * 0.80),
			Vector2(0.0, -drop), Vector2(span * 0.34, -drop * 0.84),
			Vector2(span * 0.70, -drop * 0.96), Vector2(span * 0.92, -drop * 0.50),
			Vector2(span, -0.020 * H), Vector2(0.0, 0.045 * H),
		])
		_plate(cloak, "CloakMain", tatter, 0.014 * H, Vector3(0, 0, 0.0), "cloth_dark")
		_plate(cloak, "CloakCollar", PackedVector2Array([
			Vector2(-span * 0.75, 0.045 * H), Vector2(span * 0.75, 0.045 * H),
			Vector2(span * 0.62, 0.090 * H), Vector2(-span * 0.62, 0.090 * H),
		]), 0.012 * H, Vector3(0, 0, 0.010 * H), "cloth")
		for side in [-1.0, 1.0]:
			_plate(cloak, "CloakEdge_%d" % int(side), PackedVector2Array([
				Vector2(side * span * 0.86, -0.020 * H), Vector2(side * span * 0.98, -0.020 * H),
				Vector2(side * span * 0.88, -drop * 0.62), Vector2(side * span * 0.74, -drop * 0.50),
			]), 0.006 * H, Vector3(0, 0, 0.016 * H), "trim_dark")

	func _hood() -> void:
		var head := pivots["Head"] as Node3D
		var hh := head_h
		var wr := 0.060 * H
		# 已有兜帽头型的角色不重复加壳
		for child in head.get_children():
			if str(child.name).begins_with("Hood"):
				return
		_loft(head, "HoodShell", [
			[Vector3(0, -0.020 * H, -0.006 * H), wr * 1.06, wr * 1.08],
			[Vector3(0, hh * 0.60, -0.008 * H), wr * 1.14, wr * 1.16],
			[Vector3(0, hh * 1.02, -0.016 * H), wr * 0.80, wr * 0.88],
			[Vector3(0, hh * 1.10, -0.030 * H), wr * 0.30, wr * 0.38],
		], "cloth", 9)
		_plate(head, "HoodBrim", PackedVector2Array([
			Vector2(-wr * 0.98, -0.010 * H), Vector2(-wr * 0.82, 0.024 * H),
			Vector2(0.0, 0.030 * H), Vector2(wr * 0.82, 0.024 * H),
			Vector2(wr * 0.98, -0.010 * H), Vector2(0.0, 0.004 * H),
		]), 0.012 * H, Vector3(0, hh * 0.40, wr * 0.98), "cloth_dark")

	func _horns() -> void:
		var head := pivots["Head"] as Node3D
		var hh := head_h
		for side in [-1.0, 1.0]:
			_tube(head, "Horn_%d" % int(side), [
				Vector3(side * 0.042 * H, hh * 0.84, 0.006 * H),
				Vector3(side * 0.070 * H, hh * 1.05, -0.020 * H),
				Vector3(side * 0.080 * H, hh * 1.20, -0.070 * H),
				Vector3(side * 0.070 * H, hh * 1.22, -0.130 * H),
			], [0.020 * H, 0.014 * H, 0.008 * H, 0.002 * H], "bone", 5)

	func _crown() -> void:
		var head := pivots["Head"] as Node3D
		var hh := head_h
		var wr := 0.060 * H
		_ring(head, "CrownBand", Vector3(0, hh * 0.96, -0.004 * H), wr * 0.82, 0.012 * H, "trim", 12)
		for i in 6:
			var ang := TAU * float(i) / 6.0
			var cx := cos(ang) * wr * 0.74
			var cz := sin(ang) * wr * 0.74 - 0.004 * H
			_tube(head, "CrownPoint_%d" % i, [
				Vector3(cx, hh * 0.98, cz), Vector3(cx * 1.06, hh * 1.14, cz * 1.06), Vector3(cx * 1.1, hh * 1.24, cz * 1.1),
			], [0.012 * H, 0.008 * H, 0.002 * H], "trim", 4)

	func _wings() -> void:
		var cloak := pivots["Cloak"] as Node3D
		for side in [-1.0, 1.0]:
			_plate(cloak, "Wing_%d" % int(side), PackedVector2Array([
				Vector2(0.0, 0.06 * H), Vector2(side * 0.260 * H, 0.14 * H),
				Vector2(side * 0.380 * H, 0.04 * H), Vector2(side * 0.300 * H, -0.16 * H),
				Vector2(side * 0.140 * H, -0.24 * H), Vector2(side * 0.030 * H, -0.10 * H),
			]), 0.010 * H, Vector3(0, 0, -0.020 * H), "cloth_dark")
			_tube(cloak, "WingArm_%d" % int(side), [
				Vector3(0, 0.05 * H, -0.026 * H), Vector3(side * 0.150 * H, 0.10 * H, -0.030 * H), Vector3(side * 0.340 * H, 0.03 * H, -0.034 * H),
			], [0.012 * H, 0.008 * H, 0.003 * H], "bone", 4)

	func _shield() -> void:
		var arm := pivots["ArmL"] as Node3D
		# 左臂略外展，盾牌挂在手臂外侧并向前/向外翻 20°，露出躯干、臂甲与披风。
		arm.rotation = Vector3(0.0, 0.0, deg_to_rad(-16.0))
		var mount := Node3D.new()
		mount.name = "ShieldMount"
		mount.position = Vector3(-0.082 * H, -0.182 * H, 0.086 * H)
		mount.rotation = Vector3(deg_to_rad(6.0), deg_to_rad(-24.0), deg_to_rad(-7.0))
		arm.add_child(mount)
		var s := 0.142 * H
		var outline := PackedVector2Array([
			Vector2(0, -s * 1.05), Vector2(s * 0.70, -s * 0.62), Vector2(s * 0.78, s * 0.30),
			Vector2(s * 0.38, s * 0.78), Vector2(-s * 0.38, s * 0.78), Vector2(-s * 0.78, s * 0.30),
			Vector2(-s * 0.70, -s * 0.62),
		])
		_plate(mount, "ShieldFace", outline, 0.024 * H, Vector3.ZERO, "cloth_dark")
		var rim := PackedVector2Array()
		for point in outline:
			rim.append(point * 1.12)
		_plate(mount, "ShieldRim", rim, 0.012 * H, Vector3(0, 0, -0.014 * H), "trim")
		# 盾心与徽记：旧金压边 + 暗红底，近看有层次，不再是整块黑板。
		_plate(mount, "ShieldGlyph", PackedVector2Array([
			Vector2(0, s * 0.34), Vector2(s * 0.20, 0.0), Vector2(0, -s * 0.36), Vector2(-s * 0.20, 0.0),
		]), 0.006 * H, Vector3(0, 0, 0.012 * H), "accent")
		_loft_x(mount, "ShieldBoss", [
			[Vector3(-0.052 * H, 0.0, 0.026 * H), 0.028 * H, 0.032 * H],
			[Vector3(0.0, 0.0, 0.052 * H), 0.042 * H, 0.046 * H],
			[Vector3(0.052 * H, 0.0, 0.026 * H), 0.028 * H, 0.032 * H],
		], "metal", 6)
		_ring(mount, "ShieldSeal", Vector3(0, 0, 0.050 * H), s * 0.30, 0.008 * H, "trim", 10, Vector3.FORWARD)
		_block(mount, "ShieldStrap", Vector3(0, 0, -0.030 * H), Vector3(0.040 * H, 0.120 * H, 0.020 * H), "leather")

	func _lantern(at: Vector3, scale_value: float, parent: Node3D) -> void:
		var s := 0.060 * H * scale_value
		_tube(parent, "LanternHook", [Vector3(at.x, at.y + s * 1.10, at.z), Vector3(at.x, at.y + s * 1.45, at.z)], [0.006 * H], "metal_dark", 4)
		_ring(parent, "LanternHandle", Vector3(at.x, at.y + s * 1.10, at.z), s * 0.52, 0.006 * H, "trim_dark", 10, Vector3.FORWARD)
		_block(parent, "LanternTop", Vector3(at.x, at.y + s * 0.86, at.z), Vector3(s * 1.08, s * 0.22, s * 1.08), "metal_dark")
		_block(parent, "LanternBottom", Vector3(at.x, at.y - s * 0.86, at.z), Vector3(s * 1.00, s * 0.20, s * 1.00), "metal_dark")
		for i in 4:
			var ang := TAU * float(i) / 4.0
			_tube(parent, "LanternPost_%d" % i, [
				Vector3(at.x + cos(ang) * s * 0.48, at.y - s * 0.82, at.z + sin(ang) * s * 0.48),
				Vector3(at.x + cos(ang) * s * 0.48, at.y + s * 0.82, at.z + sin(ang) * s * 0.48),
			], [0.008 * H], "trim_dark", 4)
		_block(parent, "LanternGlow", Vector3(at.x, at.y, at.z), Vector3(s * 0.62, s * 1.10, s * 0.62), "glow")

	func _chains() -> void:
		var hips := pivots["Hips"] as Node3D
		# 链尾不能穿地：可下垂长度随胯高收缩（钟形等低胯角色自动变短）。
		var span := minf(0.500 * H, hips.position.y + 0.070 * H - 0.070 * H)
		span = minf(span, hips.position.y + 0.070 * H - 0.062 * H)
		span = maxf(span, 0.120 * H)
		for side in [-1.0, 1.0]:
			for link in 7:
				var t := float(link) / 6.0
				var center := Vector3(side * (0.115 - 0.030 * t) * H, 0.070 * H - t * span, 0.030 * H + sin(t * 3.0) * 0.030 * H)
				var normal := Vector3.RIGHT if link % 2 == 0 else Vector3.FORWARD
				_ring(hips, "Chain_%d_%d" % [int(side), link], center, 0.024 * H, 0.006 * H, "trim_dark", 8, normal)

	func _mask() -> void:
		var head := pivots["Head"] as Node3D
		var hh := head_h
		var wr := 0.060 * H
		_plate(head, "Mask", PackedVector2Array([
			Vector2(-wr * 0.72, -hh * 0.30), Vector2(wr * 0.72, -hh * 0.30),
			Vector2(wr * 0.82, hh * 0.32), Vector2(wr * 0.36, hh * 0.54),
			Vector2(0.0, hh * 0.60), Vector2(-wr * 0.36, hh * 0.54),
			Vector2(-wr * 0.82, hh * 0.32),
		]), 0.014 * H, Vector3(0, hh * 0.42, wr * 1.02), "trim")
		for side in [-1.0, 1.0]:
			_block(head, "MaskSlit_%d" % int(side), Vector3(side * wr * 0.36, hh * 0.50, wr * 1.10), Vector3(0.026 * H, 0.008 * H, 0.008 * H), "dark")
		_block(head, "MaskNose", Vector3(0, hh * 0.36, wr * 1.10), Vector3(0.014 * H, hh * 0.22, 0.014 * H), "trim_dark")

	func _books() -> void:
		var torso := pivots["Torso"] as Node3D
		var spots := [
			Vector3(-0.190 * H, 0.030 * H, 0.160 * H),
			Vector3(0.210 * H, -0.020 * H, 0.080 * H),
			Vector3(0.160 * H, 0.130 * H, -0.060 * H),
		]
		for i in spots.size():
			var at: Vector3 = spots[i]
			var rot := Vector3(0.10 * float(i) - 0.10, 0.5 * float(i), 0.20 * float(i) - 0.20)
			_block(torso, "Book_%d" % i, at, Vector3(0.090 * H, 0.024 * H, 0.066 * H), ["cloth_dark", "accent", "cloth"][i % 3], rot)
			_block(torso, "BookPages_%d" % i, at + Vector3(0.0, 0.0, 0.0), Vector3(0.084 * H, 0.016 * H, 0.060 * H), "bone", rot)
			_block(torso, "BookSpine_%d" % i, at + Vector3(-0.043 * H, 0.0, 0.0), Vector3(0.010 * H, 0.028 * H, 0.068 * H), "trim", rot)

	# ---------------------------------------------------------------- 统计

	func _measure_bounds() -> AABB:
		var box := AABB()
		var first := true
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var instance := node as MeshInstance3D
			if instance.mesh == null:
				continue
			var xform := Transform3D.IDENTITY
			var cursor: Node = instance
			while cursor != null and cursor != root:
				if cursor is Node3D:
					xform = (cursor as Node3D).transform * xform
				cursor = cursor.get_parent()
			var local: AABB = xform * instance.mesh.get_aabb()
			box = local if first else box.merge(local)
			first = false
		return box
