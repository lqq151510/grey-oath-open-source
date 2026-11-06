extends SceneTree
## 灰誓 · 3D 角色核心 headless 验收（rig3d）
## 运行：Godot --headless --path . --script res://tests/test_actor3d.gd
## 输出：ACTOR3D_RESULT={"checks":N,"failures":[...]}

const ActorRig := preload("res://ui/three_d/actor_rig.gd")
const ActorLibrary := preload("res://ui/three_d/actor_library.gd")
const ActorViewScript := preload("res://ui/three_d/actor_view.gd")
const EnemyForms := preload("res://ui/three_d/enemy_forms.gd")

const REQUIRED_PIVOTS := ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR", "WeaponMount", "Cloak"]
const ALLOWED_ARCH := ["humanoid", "skeleton", "knight", "caster", "beast", "moth", "raven", "worm", "eye", "bell", "sovereign", "automaton", "giant", "wraith"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var catalog := _read_catalog()
	var roles := _index_by_id(catalog.get("roles", []))
	var enemies := _index_by_id(catalog.get("enemies", []))
	_test_travelers(roles)
	_test_enemy_library(enemies)
	_test_empty_spec()
	_test_view_headless(roles, enemies)
	await process_frame
	var payload := {"checks": checks, "failures": failures}
	print("ACTOR3D_RESULT=" + JSON.stringify(payload))
	quit(0 if failures.is_empty() else 1)


func _read_catalog() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/catalog.json")
	if text.is_empty():
		_fail("catalog: data/catalog.json 读取为空")
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_fail("catalog: JSON 解析失败")
		return {}
	return parsed


func _index_by_id(entries: Array) -> Dictionary:
	var out := {}
	for entry in entries:
		if entry is Dictionary and entry.has("id"):
			out[str(entry["id"])] = entry
	return out


func _test_travelers(roles: Dictionary) -> void:
	var role_order := ["warden", "ranger", "sister", "arcanist", "medium", "bellscribe", "ashlamper"]
	var signatures := {}
	for role_id in role_order:
		var definition: Dictionary = roles.get(role_id, {})
		var entity := {
			"id": role_id, "role": role_id, "name": str(definition.get("name", role_id)),
			"hp": int(definition.get("max_hp", 80)), "color": str(definition.get("color", "")),
		}
		var spec: Dictionary = ActorLibrary.spec_for(entity, definition, true)
		_check(not spec.is_empty(), "%s: spec 非空" % role_id)
		_check(str(spec.get("archetype", "")) in ALLOWED_ARCH, "%s: archetype 合法 (%s)" % [role_id, str(spec.get("archetype", ""))])
		_check(str(spec.get("name", "")).length() > 0, "%s: 造型名来自 catalog" % role_id)
		var rig: Node3D = ActorRig.build(spec)
		if rig == null:
			_fail("%s: build 返回 null" % role_id)
			continue
		var h := float(rig.get_meta("height", 0.0))
		_check(h >= 1.5 and h <= 2.6, "%s: 高度 %.3f 在 1.5..2.6" % [role_id, h])
		_check(int(rig.get_meta("mesh_count", 0)) >= 12, "%s: mesh_count %d >= 12" % [role_id, int(rig.get_meta("mesh_count", 0))])
		_check_pivots(rig, role_id)
		var bounds: AABB = rig.get_meta("bounds", AABB())
		var bh := bounds.size.y
		_check(bh >= h * 0.80 and bh <= h * 1.25, "%s: 包围盒高 %.3f 与身高 %.3f 匹配" % [role_id, bh, h])
		_check(bounds.position.y >= -0.06 and bounds.position.y <= 0.10, "%s: 脚底贴地 (min_y=%.3f)" % [role_id, bounds.position.y])
		_check(bounds.size.x > h * 0.10 and bounds.size.z > h * 0.10, "%s: 有体积 (%.2f x %.2f)" % [role_id, bounds.size.x, bounds.size.z])
		var tris := _triangle_count(rig)
		_check(tris >= 200, "%s: 三角面 %d >= 200" % [role_id, tris])
		_check(_flat_shading_violations(rig) == 0, "%s: 全部三角为硬边 flat shading" % role_id)
		var again: Node3D = ActorRig.build(spec)
		if again == null:
			_fail("%s: 二次 build 返回 null" % role_id)
		else:
			_check(int(again.get_meta("mesh_count", -1)) == int(rig.get_meta("mesh_count", -2)), "%s: 同 spec mesh 数确定" % role_id)
			_check(_triangle_count(again) == tris, "%s: 同 spec 三角数确定" % role_id)
			var bounds2: AABB = again.get_meta("bounds", AABB())
			_check(bounds2.size.distance_to(bounds.size) < 0.0001, "%s: 同 spec 包围盒确定" % role_id)
			again.free()
		var signature := "%d|%d|%s" % [int(rig.get_meta("mesh_count", 0)), tris, str(spec.get("archetype", ""))]
		signatures[role_id] = signature
		rig.free()
	_check(signatures.size() == 7, "7 名旅者全部构建")
	var unique := {}
	for key in signatures:
		unique[signatures[key]] = true
	_check(unique.size() >= 5, "7 名旅者造型互不相同 (%d 套签名)" % unique.size())


func _test_enemy_library(enemies: Dictionary) -> void:
	_check(enemies.size() >= 40, "catalog 敌人数 %d" % enemies.size())
	var arch_counts := {}
	var built := {}
	var checked := 0
	for enemy_id in enemies:
		var definition: Dictionary = enemies[enemy_id]
		var entity := {
			"id": enemy_id, "name": str(definition.get("name", enemy_id)),
			"kind": str(definition.get("kind", "normal")), "hp": int(definition.get("hp", 20)),
			"chapter": int(definition.get("chapter", 0)), "color": str(definition.get("color", "")),
		}
		var spec: Dictionary = ActorLibrary.spec_for(entity, definition, false)
		var arch := str(spec.get("archetype", ""))
		var h := float(spec.get("height", 0.0))
		var b := float(spec.get("bulk", 0.0))
		_check(arch in ALLOWED_ARCH, "敌人 %s: archetype %s 合法" % [enemy_id, arch])
		var max_height := 3.6 if str(definition.get("kind", "normal")) in ["elite", "boss"] else 2.8
		_check(h >= 0.9 and h <= max_height, "敌人 %s: 高度 %.2f 在合理区间(<=%.1f)" % [enemy_id, h, max_height])
		_check(b >= 0.82 and b <= 1.35, "敌人 %s: bulk %.2f 遵守契约" % [enemy_id, b])
		var palette: Dictionary = spec.get("palette", {})
		var palette_ok := true
		for key in ["cloth", "metal", "trim", "accent", "skin", "dark"]:
			palette_ok = palette_ok and palette.has(key)
		_check(palette_ok, "敌人 %s: 六色齐全" % enemy_id)
		var accent: Color = palette.get("accent", Color.BLACK)
		if EnemyForms.has_form(enemy_id):
			# 显式造型表（56 条）自带高对比 accent；definition.color 只用于兜底 id。
			var form: Dictionary = EnemyForms.spec(enemy_id, definition)
			var form_palette: Dictionary = form.get("palette", {})
			var form_accent: Color = form_palette.get("accent", Color.BLACK)
			_check(accent.is_equal_approx(form_accent), "敌人 %s: accent 取显式造型表" % enemy_id)
		else:
			var source := Color.html("#" + str(definition.get("color", "")).trim_prefix("#")) if Color.html_is_valid("#" + str(definition.get("color", "")).trim_prefix("#")) else Color.BLACK
			_check(absf(accent.r - source.r) < 0.02 and absf(accent.g - source.g) < 0.02 and absf(accent.b - source.b) < 0.02, "敌人 %s: accent 取 definition.color" % enemy_id)
		arch_counts[arch] = int(arch_counts.get(arch, 0)) + 1
		checked += 1
		if checked <= 6 or not built.has(arch):
			var rig: Node3D = ActorRig.build(spec)
			if rig == null:
				_fail("敌人 %s: build 返回 null" % enemy_id)
			else:
				built[arch] = true
				_check(int(rig.get_meta("mesh_count", 0)) >= 8, "敌人 %s(%s): mesh_count %d >= 8" % [enemy_id, arch, int(rig.get_meta("mesh_count", 0))])
				_check_pivots(rig, "enemy:" + enemy_id)
				_check(_flat_shading_violations(rig) == 0, "敌人 %s: flat shading" % enemy_id)
				rig.free()
	_check(checked >= 40, "敌人 spec 全量遍历 (%d)" % checked)
	_check(arch_counts.size() >= 8, "敌人 archetype 覆盖 %d 类" % arch_counts.size())


func _test_empty_spec() -> void:
	var rig: Node3D = ActorRig.build({})
	if rig == null:
		_fail("空 spec: build 返回 null")
		return
	_check(int(rig.get_meta("mesh_count", 0)) >= 8, "空 spec: 有兜底造型 (%d mesh)" % int(rig.get_meta("mesh_count", 0)))
	_check_pivots(rig, "empty")
	rig.free()


func _test_view_headless(roles: Dictionary, enemies: Dictionary) -> void:
	var view: Control = ActorViewScript.new()
	root.add_child(view)
	view.position = Vector2(100.0, 50.0)
	view.size = Vector2(240.0, 190.0)
	var definition: Dictionary = roles.get("warden", {})
	var entity := {"id": "warden", "role": "warden", "hp": 74, "name": "铁甲战士", "color": "#c76b57"}
	view.setup(entity, definition, true)
	_check(not view.is_rendering(), "headless: 不创建 SubViewport GPU 资源")
	_check(view.get_rig() != null, "headless: setup 仍构建枢轴骨架")
	# 与 ui/combat_actor.gd 对齐：玩家角色的 archetype 就是 role id；敌人保留视觉体型。
	_check(str(view.archetype) == "warden", "view: 玩家 archetype=role id (%s)" % str(view.archetype))
	_check(str(view.role_id) == "warden", "view: role_id 同步 (%s)" % str(view.role_id))
	_check(view.player, "view: player 标记")
	_check(int(view.get_rig().get_meta("mesh_count", 0)) >= 12, "view: rig mesh 数")
	var impact: Vector2 = view.get_impact_position()
	_check(absf(impact.x - 220.0) < 0.6 and absf(impact.y - 139.3) < 0.6, "view: get_impact_position=%s" % str(impact))
	view.set_health(40, 90)
	_check(view.health == 40 and view.max_health == 90, "view: set_health")
	view.set_selected(true)
	_check(view.selected, "view: set_selected")
	view.animation_speed = 1.0
	view.play_attack()
	_check(absf(view.attack_time - 0.48) < 0.001, "view: play_attack attack_time=0.48")
	view.play_hit(6, 0)
	_check(absf(view.hit_time - 0.42) < 0.001 and not view.shield_hit, "view: play_hit 伤害路径")
	view.play_hit(0, 8)
	_check(view.shield_hit, "view: play_hit 格挡路径 shield_hit")
	view.play_guard()
	_check(absf(view.guard_time - 0.36) < 0.001, "view: play_guard guard_time=0.36")
	view.play_death()
	_check(view.dead and absf(view.death_time - 0.65) < 0.001, "view: play_death dead/death_time")
	view.held = true
	view.reduced_motion = true
	await process_frame
	await process_frame
	view.queue_free()

	var enemy: Dictionary = enemies.get("grave_sentry", {})
	if enemy.is_empty():
		for key in enemies:
			if str(enemies[key].get("name", "")).contains("枯骨"):
				enemy = enemies[key]
				break
	if not enemy.is_empty():
		var view2: Control = ActorViewScript.new()
		root.add_child(view2)
		view2.size = Vector2(200.0, 160.0)
		view2.setup(enemy.duplicate(true), enemy.duplicate(true), false)
		_check(view2.get_rig() != null, "view: 敌人 setup 构建骨架")
		_check(not view2.player, "view: 敌人 player=false")
		view2.play_attack()
		view2.play_hit(9, 0)
		view2.play_guard()
		view2.play_death()
		await process_frame
		_check(view2.dead, "view: 敌人 play_death 不报错")
		view2.queue_free()
	else:
		_fail("view: 未找到枯骨系敌人做冒烟")


func _check_pivots(rig: Node3D, label: String) -> void:
	var pivots: Dictionary = rig.get_meta("pivots", {})
	for key in REQUIRED_PIVOTS:
		var path := str(pivots.get(key, ""))
		_check(not path.is_empty(), "%s: 枢轴表含 %s" % [label, key])
		if path.is_empty():
			continue
		var node := rig.get_node_or_null(path)
		_check(node is Node3D, "%s: 枢轴 %s 存在 (%s)" % [label, key, path])
	var hips := rig.get_node_or_null(str(pivots.get("Hips", "")))
	var torso := rig.get_node_or_null(str(pivots.get("Torso", "")))
	if hips != null and torso != null:
		_check(torso.get_parent() == hips, "%s: Torso 挂在 Hips 下" % label)
		for key in ["Head", "ArmL", "ArmR", "Cloak"]:
			var node := rig.get_node_or_null(str(pivots.get(key, "")))
			_check(node != null and node.get_parent() == torso, "%s: %s 挂在 Torso 下" % [label, key])
		for key in ["LegL", "LegR"]:
			var node := rig.get_node_or_null(str(pivots.get(key, "")))
			_check(node != null and node.get_parent() == hips, "%s: %s 挂在 Hips 下" % [label, key])
	var arm_r := rig.get_node_or_null(str(pivots.get("ArmR", "")))
	var mount := rig.get_node_or_null(str(pivots.get("WeaponMount", "")))
	if arm_r != null and mount != null:
		_check(mount.get_parent() == arm_r, "%s: WeaponMount 挂在 ArmR 下" % label)


func _triangle_count(rig: Node3D) -> int:
	var total := 0
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := _indices_of(arrays)
			if indices.size() >= 3:
				total += indices.size() / 3
			else:
				total += verts.size() / 3
	return total


func _indices_of(arrays: Array) -> PackedInt32Array:
	if arrays.size() <= Mesh.ARRAY_INDEX:
		return PackedInt32Array()
	var raw: Variant = arrays[Mesh.ARRAY_INDEX]
	if raw is PackedInt32Array:
		return raw
	return PackedInt32Array()


func _flat_shading_violations(rig: Node3D) -> int:
	var bad := 0
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if normals.is_empty():
				bad += 1
				continue
			var indices := _indices_of(arrays)
			if indices.size() >= 3:
				for i in range(0, indices.size(), 3):
					var a := normals[indices[i]]
					var b := normals[indices[i + 1]]
					var c := normals[indices[i + 2]]
					if a.distance_to(b) > 0.02 or a.distance_to(c) > 0.02:
						bad += 1
			else:
				for i in range(0, normals.size(), 3):
					if i + 2 >= normals.size():
						break
					var a := normals[i]
					var b := normals[i + 1]
					var c := normals[i + 2]
					if a.distance_to(b) > 0.02 or a.distance_to(c) > 0.02:
						bad += 1
	return bad


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		_fail(label)


func _fail(label: String) -> void:
	failures.append(label)
