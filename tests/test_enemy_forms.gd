extends SceneTree
## 56 个敌人造型表的纯数据验收（不创建任何 GPU 资源，headless 可跑）。
## 断言：id 全覆盖、palette 六键、height/bulk 区间、确定性、14 原型全覆盖、
## 精英/首领尺度规则、四章色温区分、武器/配件合法性。
## 输出：ENEMY_FORMS_RESULT={"checks":N,"failures":[]}

const EnemyForms = preload("res://ui/three_d/enemy_forms.gd")
const CATALOG := "res://data/catalog.json"
const PALETTE_KEYS := ["cloth", "metal", "trim", "accent", "skin", "dark"]
const TIER_RANGE := {
	"normal": [0.86, 1.12],
	"elite": [1.10, 1.25],
	"boss": [1.35, 1.80],
}

var checks := 0
var failures: Array[String] = []
var catalog: Dictionary = {}
var enemies: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	if not _load_catalog():
		_finish()
		return
	_check(enemies.size() == 56, "catalog holds 56 enemies (got %d)" % enemies.size())
	_test_coverage()
	_test_entries()
	_test_determinism()
	_test_archetypes()
	_test_tiers()
	_test_chapter_temperatures()
	_test_fallback()
	_finish()


func _load_catalog() -> bool:
	var text := FileAccess.get_file_as_string(CATALOG)
	_check(not text.is_empty(), "catalog file is readable")
	if text.is_empty():
		return false
	var parsed = JSON.parse_string(text)
	_check(parsed is Dictionary, "catalog parses as Dictionary")
	if not (parsed is Dictionary):
		return false
	catalog = parsed
	_check(catalog.get("enemies", []) is Array, "catalog enemies is Array")
	enemies = catalog.get("enemies", [])
	return true


func _test_coverage() -> void:
	var catalog_ids := {}
	for row in enemies:
		catalog_ids[String(row.get("id", ""))] = true
	var spec_ids := {}
	for id in EnemyForms.all_ids():
		spec_ids[String(id)] = true
	_check(EnemyForms.all_ids().size() == 56, "spec table holds exactly 56 entries")
	for id in catalog_ids:
		_check(spec_ids.has(id), "catalog id has a spec: " + id)
	for id in spec_ids:
		_check(catalog_ids.has(id), "spec id exists in catalog: " + id)


func _test_entries() -> void:
	for row in enemies:
		var id := String(row.get("id", ""))
		var kind := String(row.get("kind", "normal"))
		var spec := EnemyForms.spec(id, row)
		var label := id + ": "
		_check(not spec.is_empty(), label + "spec is not empty")
		if spec.is_empty():
			continue
		_check(String(spec.get("id", "")) == id, label + "id round-trips")
		_check(not String(spec.get("name", "")).is_empty(), label + "has display name")
		_check(kind == String(spec.get("tier", "")), label + "tier matches catalog kind")

		var archetype := String(spec.get("archetype", ""))
		_check(EnemyForms.ARCHETYPES.has(archetype), label + "archetype is contract-listed: " + archetype)
		var weapon := String(spec.get("weapon", ""))
		_check(EnemyForms.WEAPONS.has(weapon), label + "weapon is contract-listed: " + weapon)
		if spec.has("staff_top"):
			_check(weapon == "staff", label + "staff_top only appears on staff wielders")
			_check(["orb", "star", "lantern", "censer"].has(String(spec["staff_top"])),
				label + "staff_top is an actor_rig-supported variant: " + String(spec["staff_top"]))

		var accessories = spec.get("accessories", [])
		_check(accessories is Array, label + "accessories is Array")
		for accessory in accessories:
			_check(EnemyForms.ACCESSORIES.has(String(accessory)), label + "accessory is contract-listed: " + String(accessory))

		var height := float(spec.get("height", 0.0))
		_check(height >= 0.6 and height <= 3.4, label + "height within 0.6..3.4 (got %.3f)" % height)
		var bulk := float(spec.get("bulk", 0.0))
		_check(bulk >= 0.82 and bulk <= 1.35, label + "bulk within 0.82..1.35 (got %.3f)" % bulk)

		_check(spec.get("seed", null) is int, label + "seed is int")
		_check(spec.get("palette", null) is Dictionary, label + "palette is Dictionary")
		var palette: Dictionary = spec.get("palette", {})
		_check(palette.size() == 6, label + "palette has exactly six keys")
		for key in PALETTE_KEYS:
			_check(palette.has(key), label + "palette has key " + key)
			if palette.has(key):
				_check(typeof(palette[key]) == TYPE_COLOR, label + "palette[" + key + "] is Color")
		if kind == "normal":
			_check(bulk <= 1.10, label + "normal bulk stays under elite weight (got %.3f)" % bulk)
		elif kind in ["elite", "boss"]:
			_check(not accessories.is_empty(), label + "elite/boss carries signature accessories")


func _test_determinism() -> void:
	for row in enemies:
		var id := String(row.get("id", ""))
		var first := EnemyForms.spec(id, row)
		var second := EnemyForms.spec(id, row)
		_check(JSON.stringify(first) == JSON.stringify(second), id + ": repeated spec() is identical")
	first_mutation_guard()


func first_mutation_guard() -> void:
	var row: Dictionary = enemies[0]
	var id := String(row.get("id", ""))
	var one := EnemyForms.spec(id, row)
	one["height"] = 99.0
	one["palette"]["cloth"] = Color("ff0000")
	var two := EnemyForms.spec(id, row)
	_check(float(two.get("height", 0.0)) != 99.0, id + ": spec() returns an independent copy (height)")
	_check(two.get("palette", {}).get("cloth", Color()) != Color("ff0000"), id + ": palette copy is independent")


func _test_archetypes() -> void:
	var used := {}
	for row in enemies:
		var spec := EnemyForms.spec(String(row.get("id", "")), row)
		used[String(spec.get("archetype", ""))] = true
	for archetype in EnemyForms.ARCHETYPES:
		_check(used.has(archetype), "archetype is used at least once: " + archetype)


func _test_tiers() -> void:
	var chapter_normal_max_bulk := {}
	for row in enemies:
		var spec := EnemyForms.spec(String(row.get("id", "")), row)
		var chapter := int(spec.get("chapter", 0))
		var tier := String(spec.get("tier", "normal"))
		var archetype := String(spec.get("archetype", ""))
		var base := float(EnemyForms.BASE_HEIGHTS.get(archetype, 0.0))
		_check(base > 0.0, String(spec.get("id", "")) + ": archetype has a base height")
		if base <= 0.0:
			continue
		var ratio := float(spec.get("height", 0.0)) / base
		var window: Array = TIER_RANGE[tier]
		_check(ratio >= float(window[0]) - 0.005 and ratio <= float(window[1]) + 0.005,
			"%s: %s scale %.3fx within %.2f..%.2f" % [spec.get("id", ""), tier, ratio, window[0], window[1]])
		var bulk := float(spec.get("bulk", 0.0))
		if tier == "elite":
			_check(bulk >= 1.12, String(spec.get("id", "")) + ": elite is heavier than normal (bulk %.3f)" % bulk)
		elif tier == "boss":
			_check(bulk >= 1.22, String(spec.get("id", "")) + ": boss is heaviest (bulk %.3f)" % bulk)
			_check(float(spec.get("height", 0.0)) >= base * 1.35 - 0.005, String(spec.get("id", "")) + ": boss towers over normal")
		elif tier == "normal":
			var previous := float(chapter_normal_max_bulk.get(chapter, 0.0))
			chapter_normal_max_bulk[chapter] = maxf(previous, bulk)
	for chapter in chapter_normal_max_bulk:
		for row in enemies:
			var spec := EnemyForms.spec(String(row.get("id", "")), row)
			if int(spec.get("chapter", -1)) != chapter:
				continue
			if String(spec.get("tier", "")) in ["elite", "boss"]:
				_check(float(spec.get("bulk", 0.0)) > float(chapter_normal_max_bulk[chapter]),
					"%s: %s is heavier than every chapter normal" % [spec.get("id", ""), spec.get("tier", "")])


func _test_chapter_temperatures() -> void:
	var means := {}
	var counts := {}
	for row in enemies:
		var spec := EnemyForms.spec(String(row.get("id", "")), row)
		var chapter := int(spec.get("chapter", 0))
		var palette: Dictionary = spec.get("palette", {})
		var total := Color(0, 0, 0)
		for key in PALETTE_KEYS:
			if palette.has(key):
				total = total + palette[key]
		if not means.has(chapter):
			means[chapter] = Color(0, 0, 0)
			counts[chapter] = 0
		means[chapter] = means[chapter] + total / 6.0
		counts[chapter] = int(counts[chapter]) + 1
	_check(means.size() == 4, "four chapters contribute palettes")
	for chapter in means:
		means[chapter] = means[chapter] / float(counts[chapter])
	var keys := means.keys()
	keys.sort()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Color = means[keys[i]]
			var b: Color = means[keys[j]]
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			_check(distance >= 0.06, "chapter %d vs %d palette mean distance %.3f >= 0.06" % [keys[i], keys[j], distance])
	# 沉钟墓园：灰绿（绿高于蓝）；荆棘修道院：暗红；失星观测所：冷蓝；无日王庭：旧金。
	var ch1: Color = means.get(0, Color())
	_check(ch1.g - ch1.b >= 0.05, "chapter 0 (sunken bells) reads grey-green (g-b %.3f)" % (ch1.g - ch1.b))
	var ch2: Color = means.get(1, Color())
	_check(ch2.r - ch2.g >= 0.10, "chapter 1 (thorn abbey) reads dark red (r-g %.3f)" % (ch2.r - ch2.g))
	var ch3: Color = means.get(2, Color())
	_check(ch3.b - ch3.r >= 0.09, "chapter 2 (lost star) reads cold blue (b-r %.3f)" % (ch3.b - ch3.r))
	var ch4: Color = means.get(3, Color())
	_check(ch4.r - ch4.b >= 0.15, "chapter 3 (sunless court) reads old gold (r-b %.3f)" % (ch4.r - ch4.b))


func _test_fallback() -> void:
	_check(not EnemyForms.has_form("not_a_real_enemy"), "unknown id is not in the explicit table")
	var fallback := EnemyForms.spec("not_a_real_enemy", {"name": "未命名", "chapter": 2, "kind": "normal"})
	_check(not fallback.is_empty(), "unknown id still yields a spec")
	_check(String(fallback.get("name", "")) == "未命名", "fallback keeps definition name")
	_check(String(fallback.get("archetype", "")) in EnemyForms.ARCHETYPES, "fallback uses a contract archetype")
	_check((fallback.get("palette", {}) as Dictionary).size() == 6, "fallback palette has six keys")
	_check(JSON.stringify(fallback) == JSON.stringify(EnemyForms.spec("not_a_real_enemy", {"name": "未命名", "chapter": 2, "kind": "normal"})),
		"fallback is deterministic")


func _finish() -> void:
	var result := {"checks": checks, "failures": failures}
	print("ENEMY_FORMS_RESULT=" + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
