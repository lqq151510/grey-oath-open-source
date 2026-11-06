extends SceneTree
## Self-contained regression tests for the extracted core modules.
## Run: Godot --headless --path . --script tests/test_core_modules.gd
## Prints one CORE_MODULES_RESULT line and exits non-zero on failure.

const RandomStreams = preload("res://core/random_streams.gd")
const MapGen = preload("res://core/map_gen.gd")
const ContentDB = preload("res://core/content_db.gd")

const SEED := 20261105
const STREAMS := ["map", "battle", "loot", "event"]
const CHAPTER_NODES := 15

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _same(left, right) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _run() -> void:
	_test_random_streams()
	_test_map_generation()
	_test_route_exits()
	_test_resolve_kind()
	_test_content_db()
	print("CORE_MODULES_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- random streams


func _sample_sequence(seed_value: int) -> Array:
	var rng = RandomStreams.new()
	rng.seed_with(seed_value)
	var result = []
	for i in range(40):
		result.append(rng.randi_range(STREAMS[i % STREAMS.size()], -50, 200))
	return result


func _test_random_streams() -> void:
	_check(_same(RandomStreams.STREAMS, STREAMS), "stream list is [map, battle, loot, event]")
	_check(RandomStreams.new().snapshot().is_empty(), "snapshot is empty before seeding")

	# Seeding formula must match game_engine._seed_streams().
	for i in range(STREAMS.size()):
		var stream = STREAMS[i]
		var module_rng = RandomStreams.new()
		module_rng.seed_with(4242)
		var manual = RandomNumberGenerator.new()
		manual.seed = 4242 + (i + 1) * 104729
		_check(module_rng.randi_range(stream, 0, 1000) == manual.randi_range(0, 1000), "stream %s uses seed + (index + 1) * 104729" % stream)

	# Same seed -> identical sequence across all streams.
	_check(_same(_sample_sequence(SEED), _sample_sequence(SEED)), "same seed produces the same sequence")
	_check(not _same(_sample_sequence(SEED), _sample_sequence(SEED + 1)), "different seeds produce different sequences")

	# Snapshot after partial consumption must resume the same tail.
	var first = RandomStreams.new()
	first.seed_with(SEED)
	var head = []
	for i in range(6):
		head.append(first.randi_range("map", 0, 99))
	var saved = first.snapshot()
	_check(saved.size() == STREAMS.size(), "snapshot covers all four streams")
	for key in STREAMS:
		var entry = saved.get(key, {})
		_check(entry is Dictionary and entry.has("seed") and entry.has("state"), "snapshot entry for %s stores seed and state" % key)
		_check(entry.get("seed") is String and entry.get("state") is String, "snapshot for %s serializes seed and state as strings" % key)
	var tail = []
	for i in range(16):
		tail.append(first.randi_range("battle", 0, 99))
	var clone = RandomStreams.new()
	clone.restore(SEED, saved)
	var clone_tail = []
	for i in range(16):
		clone_tail.append(clone.randi_range("battle", 0, 99))
	_check(_same(tail, clone_tail), "restore resumes the exact stream tail")

	# Partial snapshots fall back to the per-stream seed formula.
	var fresh = RandomStreams.new()
	fresh.seed_with(SEED)
	var fallback = RandomStreams.new()
	fallback.restore(SEED, {})
	var fresh_seq = []
	var fallback_seq = []
	for i in range(20):
		fresh_seq.append(fresh.randi_range("event", 0, 999))
		fallback_seq.append(fallback.randi_range("event", 0, 999))
	_check(_same(fresh_seq, fallback_seq), "empty snapshot falls back to seeded streams")

	var partial = RandomStreams.new()
	partial.restore(SEED, {"map": saved.get("map", {})})
	var partial_map = []
	var first_map = []
	for i in range(6):
		partial_map.append(partial.randi_range("map", 0, 99))
		first_map.append(first.randi_range("map", 0, 99))
	_check(_same(partial_map, first_map), "partial snapshot continues only the recorded stream")

	# A dropped stream is rebuilt from the recorded seed/state, not restarted.
	var erased = RandomStreams.new()
	erased.seed_with(SEED)
	erased.randi_range("battle", 0, 100)
	erased._rng.erase("battle")
	var erased_next = erased.randi_range("battle", 0, 100)
	var twin = RandomStreams.new()
	twin.seed_with(SEED)
	twin.randi_range("battle", 0, 100)
	_check(erased_next == twin.randi_range("battle", 0, 100), "missing stream restores from the recorded seed and state")

	# Shuffle keeps every element exactly once and is deterministic.
	var source = []
	for i in range(24):
		source.append(i)
	var left = source.duplicate()
	var right = source.duplicate()
	var shuffle_a = RandomStreams.new()
	shuffle_a.seed_with(SEED)
	shuffle_a.shuffle(left, "loot")
	var shuffle_b = RandomStreams.new()
	shuffle_b.seed_with(SEED)
	shuffle_b.shuffle(right, "loot")
	_check(_same(left, right), "shuffle is deterministic for the same seed")
	_check(left.size() == source.size(), "shuffle keeps the element count")
	var sorted_left = left.duplicate()
	sorted_left.sort()
	_check(_same(sorted_left, source), "shuffle keeps every element exactly once")
	_check(not _same(left, source), "shuffle actually reorders a 24 card list")
	var empty: Array = []
	shuffle_a.shuffle(empty, "loot")
	_check(empty.is_empty(), "shuffle tolerates an empty array")
	var single := [7]
	shuffle_a.shuffle(single, "loot")
	_check(_same(single, [7]), "shuffle leaves a single element untouched")

	# clear() drops the live streams; the next draw rebuilds from the recorded seed.
	var cleared = RandomStreams.new()
	cleared.seed_with(1)
	cleared.clear()
	_check(not cleared.has_stream("map"), "clear() drops the live streams")
	_check(typeof(cleared.randi_range("map", 0, 1)) == TYPE_INT, "drawing after clear() rebuilds the streams")


# ---------------------------------------------------------------- map generation


func _make_map(seed_value: int = SEED) -> Array:
	var rng = RandomStreams.new()
	rng.seed_with(seed_value)
	return MapGen.generate(rng)


func _test_map_generation() -> void:
	var route = _make_map()
	_check(route.size() == CHAPTER_NODES, "map has 15 rows")
	var cells := 0
	for row in range(route.size()):
		_check(route[row] is Array, "row %d is an array" % row)
		_check(route[row].size() == 3, "row %d has three lanes" % row)
		for lane in range(route[row].size()):
			var node = route[row][lane]
			cells += 1
			_check(node is Dictionary, "node %d/%d is a dictionary" % [row, lane])
			_check(bool(node.get("cleared", true)) == false, "node %d/%d starts uncleared" % [row, lane])
			_check(node.get("next") is Array, "node %d/%d has edges" % [row, lane])
	_check(cells == 45, "map holds 45 nodes")

	for lane in range(3):
		_check(route[0][lane].kind == "normal", "first row lane %d is normal" % lane)
		_check(route[CHAPTER_NODES - 1][lane].kind == "boss", "last row lane %d is boss" % lane)
		_check(route[CHAPTER_NODES - 1][lane].next.is_empty(), "boss row lane %d has no exits" % lane)

	# Edges only connect adjacent lanes, never duplicate and are sorted.
	for row in range(CHAPTER_NODES - 1):
		for lane in range(3):
			var exits: Array = route[row][lane].next
			_check(not exits.is_empty(), "node %d/%d has at least one exit" % [row, lane])
			var seen := {}
			for destination in exits:
				_check(destination is int, "node %d/%d edge is an int" % [row, lane])
				_check(absi(int(destination) - lane) <= 1, "node %d/%d edge %d stays adjacent" % [row, lane, int(destination)])
				_check(int(destination) >= 0 and int(destination) <= 2, "node %d/%d edge %d stays in range" % [row, lane, int(destination)])
				_check(not seen.has(int(destination)), "node %d/%d edge %d is unique" % [row, lane, int(destination)])
				seen[int(destination)] = true
			var sorted_exits = exits.duplicate()
			sorted_exits.sort()
			_check(_same(exits, sorted_exits), "node %d/%d edges are sorted" % [row, lane])

	# Guaranteed landmarks.
	for landmark in MapGen.LANDMARKS:
		var row: int = landmark[0]
		var kind: String = landmark[1]
		var row_kinds := []
		for node in route[row]:
			row_kinds.append(str(node.kind))
		_check(row_kinds.has(kind), "row %d contains guaranteed %s" % [row, kind])

	# Row chapter_nodes - 2 is one varied room plus two camps.
	var varied: Array = []
	for node in route[CHAPTER_NODES - 2]:
		varied.append(str(node.kind))
	_check(varied.count("rest") == 2, "penultimate row has two camps")
	var varied_kinds := varied.filter(func(kind): return kind != "rest")
	_check(varied_kinds.size() == 1, "penultimate row has one varied room")
	_check(varied_kinds[0] in MapGen.FINAL_POOL, "varied room comes from the final pool")
	_check(route[1][0].kind != "elite" and route[1][1].kind != "elite" and route[1][2].kind != "elite", "row 1 never keeps an elite")

	# Same seed -> identical map; map generation consumes only the map stream.
	_check(_same(route, _make_map()), "same seed produces the same map")
	var map_rng = RandomStreams.new()
	map_rng.seed_with(SEED)
	MapGen.generate(map_rng)
	var fresh_rng = RandomStreams.new()
	fresh_rng.seed_with(SEED)
	var battle_untouched := true
	for i in range(5):
		if map_rng.randi_range("battle", 0, 999) != fresh_rng.randi_range("battle", 0, 999):
			battle_untouched = false
	_check(battle_untouched, "map generation consumes only the map stream")


# ------------------------------------------------------------------- route exits


func _test_route_exits() -> void:
	var legacy := [
		[{"kind": "normal"}, {"kind": "normal"}, {"kind": "normal"}],
		[{"kind": "normal"}, {"kind": "normal"}, {"kind": "normal"}],
	]
	_check(_same(MapGen.route_exits(legacy, 0, 1), [0, 1, 2]), "legacy row falls back to lane-1/lane/lane+1")
	_check(_same(MapGen.route_exits(legacy, 0, 0), [0, 1]), "legacy edge lane clamps at the left border")
	_check(_same(MapGen.route_exits(legacy, 0, 2), [1, 2]), "legacy edge lane clamps at the right border")
	_check(MapGen.route_exits(legacy, 1, 0).is_empty(), "last row has no exits")
	_check(MapGen.route_exits(legacy, -1, 0).is_empty(), "negative row has no exits")
	_check(MapGen.route_exits(legacy, 0, 3).is_empty(), "lane out of range has no exits")
	_check(MapGen.route_exits(legacy, 0, -1).is_empty(), "negative lane has no exits")

	var short_row := [
		[{"kind": "normal"}, {"kind": "normal"}, {"kind": "normal"}],
		[{"kind": "normal"}, {"kind": "normal"}],
	]
	_check(_same(MapGen.route_exits(short_row, 0, 2), [1]), "exits respect the next row's width")

	var explicit := [
		[{"next": []}, {"next": [2, 2, 0, -1, 3, "x", 1.5, true]}, {"next": []}],
		[{"kind": "normal"}, {"kind": "normal"}, {"kind": "normal"}],
	]
	_check(_same(MapGen.route_exits(explicit, 0, 1), [0, 2]), "explicit edges filter junk, duplicates and jumps")
	var broken := [
		[{"next": [1]}, {"next": [1]}],
		[{"kind": "normal"}, null],
	]
	_check(MapGen.route_exits(broken, 0, 0).is_empty(), "edges require dictionary destinations")
	var bad_exits := [
		[{"next": "bad"}],
		[{"kind": "normal"}],
	]
	_check(MapGen.route_exits(bad_exits, 0, 0).is_empty(), "non-array edge payload is rejected")

	# route_exits() agrees with the stored edges of a generated map.
	var route = _make_map()
	for row in range(CHAPTER_NODES - 1):
		for lane in range(3):
			_check(_same(MapGen.route_exits(route, row, lane), route[row][lane].next), "route_exits matches stored edges at %d/%d" % [row, lane])


# ---------------------------------------------------------------- node resolution


func _test_resolve_kind() -> void:
	var rng = RandomStreams.new()
	rng.seed_with(SEED)
	var fate := {"kind": "fate"}
	_check(MapGen.resolve_kind(fate, rng) == "event", "fate resolves to event")
	_check(not fate.has("resolved_kind"), "fate does not write resolved_kind")
	var shop := {"kind": "shop"}
	_check(MapGen.resolve_kind(shop, rng) == "shop", "concrete kinds pass through")
	var pinned := {"kind": "unknown", "resolved_kind": "treasure"}
	_check(MapGen.resolve_kind(pinned, rng) == "treasure", "unknown reuses resolved_kind")
	var invalid := {"kind": "unknown", "resolved_kind": "boss"}
	_check(MapGen.resolve_kind(invalid, rng) == "normal", "invalid resolved_kind falls back to normal")
	var defaulted := {}
	_check(MapGen.resolve_kind(defaulted, rng) == "normal", "missing kind defaults to normal")

	var unknown := {"kind": "unknown"}
	var resolved = MapGen.resolve_kind(unknown, rng)
	_check(resolved in MapGen.POSSIBILITIES, "unknown resolves to a real room")
	_check(str(unknown.get("resolved_kind", "")) == resolved, "unknown writes resolved_kind back")
	_check(MapGen.resolve_kind(unknown, rng) == resolved, "second visit reuses the cached kind")

	# Only an open unknown node consumes the event stream.
	var consumer = RandomStreams.new()
	consumer.seed_with(SEED)
	var control = RandomStreams.new()
	control.seed_with(SEED)
	MapGen.resolve_kind({"kind": "fate"}, consumer)
	MapGen.resolve_kind({"kind": "shop"}, consumer)
	MapGen.resolve_kind({"kind": "unknown", "resolved_kind": "rest"}, consumer)
	_check(consumer.randi_range("event", 0, 999) == control.randi_range("event", 0, 999), "non-random kinds do not consume the event stream")

	var a = RandomStreams.new()
	a.seed_with(777)
	var b = RandomStreams.new()
	b.seed_with(777)
	var first_node := {"kind": "unknown"}
	var second_node := {"kind": "unknown"}
	_check(MapGen.resolve_kind(first_node, a) == MapGen.resolve_kind(second_node, b), "unknown resolution is deterministic for a seed")


# -------------------------------------------------------------------- content db


func _test_content_db() -> void:
	_check(ContentDB.normalize_numbers(3.0) == 3, "normalize_numbers 3.0 -> 3")
	_check(typeof(ContentDB.normalize_numbers(3.0)) == TYPE_INT, "normalize_numbers returns int for whole floats")
	_check(ContentDB.normalize_numbers(3.5) == 3.5, "normalize_numbers keeps fractions")
	var normalized = ContentDB.normalize_numbers({"a": [1.0, 2.5], 2: {"b": 4.0}})
	_check(typeof(normalized.a[0]) == TYPE_INT and normalized.a[0] == 1, "normalize_numbers walks arrays")
	_check(normalized.a[1] == 2.5, "normalize_numbers keeps fractional array entries")
	_check(normalized.has("2") and normalized["2"].b == 4, "normalize_numbers stringifies keys and walks dictionaries")
	_check(ContentDB.normalize_numbers("1") == "1", "normalize_numbers leaves strings alone")

	_check(ContentDB.requires_enemy([{"op": "damage"}]), "damage requires an enemy")
	_check(ContentDB.requires_enemy([{"op": "poison"}]), "poison requires an enemy")
	_check(ContentDB.requires_enemy([{"op": "osty_attack", "target": "enemy"}]), "osty_attack requires an enemy")
	_check(not ContentDB.requires_enemy([{"op": "damage", "target": "all"}]), "AOE damage requires no target")
	_check(not ContentDB.requires_enemy([{"op": "damage", "target": "self"}]), "self-targeted effects require no enemy")
	_check(not ContentDB.requires_enemy([{"op": "draw"}]), "non-hostile ops require no enemy")
	_check(not ContentDB.requires_enemy([]), "empty effects require no enemy")

	var missing = ContentDB.new()
	_check(not missing.load_from("res://data/__missing_catalog__.json"), "missing catalog reports failure")
	_check(not missing.last_error.is_empty(), "missing catalog records last_error")

	var db = ContentDB.new()
	_check(db.load_from(), "catalog loads from res://data/catalog.json")
	_check(db.data.get("version") != null, "catalog carries a version")
	_check(db.data.get("cards", []).size() == 290, "catalog defines 290 cards")
	_check(db.data.get("tokens", []).size() == 4, "catalog defines 4 tokens")
	_check(db.data.get("roles", []).size() == 7, "catalog defines 7 roles")
	_check(db.data.get("enemies", []).size() == 56, "catalog defines 56 enemies")
	for group in ContentDB.GROUPS:
		_check(db.indexes.has(group) and db.indexes[group] is Dictionary, "index group %s exists" % group)
	_check(db.indexes["cards"].size() == 294, "card index holds 290 cards plus 4 tokens")
	_check(db.indexes["roles"].size() == 7, "role index holds 7 entries")
	_check(db.indexes["enemies"].size() == 56, "enemy index holds 56 entries")

	for card in db.data.get("cards", []):
		_check(db.indexes["cards"].has(str(card.id)), "card %s is indexed" % str(card.id))
	for token in db.data.get("tokens", []):
		var token_id := str(token.id)
		_check(db.indexes["cards"].has(token_id), "token %s is merged into the card index" % token_id)
		_check(str(db.card_data(token_id).get("id", "")) == token_id, "token %s is readable through card_data" % token_id)
	_check(db.sacred_ids().size() == 4, "four sacred items are listed")
	_check(db.sacred_ids().has("sacred_oath"), "sacred ids use item ids")

	_check(not db.role_data("warden").is_empty(), "role_data resolves warden")
	_check(str(db.role_data("warden").get("id", "")) == "warden", "role_data keeps the definition")
	_check(not db.enemy_data(str(db.data.get("enemies", [{}])[0].get("id", ""))).is_empty(), "enemy_data resolves a catalog enemy")
	_check(not db.relic_data(str(db.data.get("relics", [{}])[0].get("id", ""))).is_empty(), "relic_data resolves a catalog relic")
	_check(not db.potion_data(str(db.data.get("potions", [{}])[0].get("id", ""))).is_empty(), "potion_data resolves a catalog potion")
	_check(not db.item_data(str(db.data.get("items", [{}])[0].get("id", ""))).is_empty(), "item_data resolves a catalog item")
	for lookup in ["role_data", "card_data", "relic_data", "potion_data", "item_data", "enemy_data"]:
		_check(db.call(lookup, "__missing__").is_empty(), "%s returns an empty dictionary for unknown ids" % lookup)

	# Plain view: no upgrade merge, derived presentation fields present.
	var fire_def: Dictionary = db.card_data("neutral_07")
	_check(not fire_def.is_empty(), "fixture card neutral_07 exists")
	var fire: Dictionary = db.view({"id": "neutral_07", "upgraded": false}, fire_def)
	_check(str(fire.get("name", "")) == "燧火", "plain view keeps the card name")
	_check(int(fire.get("cost", -1)) == 1, "plain view keeps the base cost")
	_check(int(fire.effects[0].value) == 4, "plain view keeps base effects")
	_check(str(fire.get("description", "")) == str(fire_def.get("description", "")), "plain view keeps the base description")
	_check(str(fire.get("area_kind", "")) == "attack", "AOE damage is an attack area")
	_check(not bool(fire.get("requires_target", true)), "AOE damage needs no target")
	_check(bool(fire.get("upgraded", true)) == false, "plain view reports upgraded = false")

	var fire_up: Dictionary = db.view({"id": "neutral_07", "upgraded": true}, fire_def)
	_check(str(fire_up.get("name", "")) == "燧火+", "upgraded view appends + to the name")
	_check(int(fire_up.get("cost", -1)) == 1, "upgraded view keeps the base cost when upgrade_cost is absent")
	_check(int(fire_up.effects[0].value) == 9, "upgraded view merges upgrade_effects")
	_check(str(fire_up.get("description", "")) == str(fire_def.get("upgrade_description", "")), "upgraded view merges upgrade_description")
	_check(bool(fire_up.get("upgraded", false)), "upgraded view reports upgraded = true")
	_check(str(fire_up.get("area_kind", "")) == "attack", "upgraded AOE damage is still an attack area")

	var mist: Dictionary = db.view({"id": "ranger_09", "upgraded": false}, db.card_data("ranger_09"))
	_check(str(mist.get("area_kind", "")) == "effect", "AOE debuffs are effect areas")
	_check(not bool(mist.get("requires_target", true)), "AOE debuffs need no target")

	var bottle: Dictionary = db.view({"id": "neutral_19", "upgraded": false}, db.card_data("neutral_19"))
	_check(str(bottle.get("area_kind", "x")) == "", "single-target cards have no area kind")
	_check(bool(bottle.get("requires_target", false)), "single-target damage needs a target")

	var shiv_def: Dictionary = db.card_data("token_shiv")
	_check(not shiv_def.is_empty(), "token_shiv exists")
	var shiv_plain: Dictionary = db.view({"id": "token_shiv", "upgraded": false}, shiv_def)
	_check(int(shiv_plain.effects[0].value) == 6, "token_shiv base damage is 6")
	var shiv_bonus: Dictionary = db.view({"id": "token_shiv", "upgraded": false}, shiv_def, 3)
	_check(int(shiv_bonus.effects[0].value) == 9, "token_shiv adds the shiv_damage bonus")
	# The shipped catalog text has no space between the number and 点, so view()
	# supports both "%d 点伤害" and "%d点伤害" and the tooltip follows the bonus.
	var shiv_bonus_text := str(shiv_bonus.get("description", ""))
	_check(shiv_bonus_text.contains("9点伤害"), "token_shiv tooltip reflects the bonus without a space")
	_check(not shiv_bonus_text.contains("6点伤害"), "token_shiv tooltip drops the base number without a space")
	var shiv_up: Dictionary = db.view({"id": "token_shiv", "upgraded": true}, shiv_def, 3)
	_check(str(shiv_up.get("name", "")) == "小刀+", "upgraded token_shiv keeps the + suffix")
	_check(int(shiv_up.effects[0].value) == 14, "upgraded token_shiv adds the bonus to the upgraded damage")
	_check(int(shiv_def.effects[0].value) == 6, "view() never mutates the catalog definition")

	# The replacement itself is exercised with the exact engine pattern.
	var spaced_def := {
		"id": "token_shiv", "name": "测试小刀", "cost": 0, "type": "attack",
		"effects": [{"op": "damage", "value": 6}],
		"description": "对目标造成6 点伤害。",
		"upgrade_effects": [{"op": "damage", "value": 11}],
		"upgrade_description": "对目标造成11 点伤害。",
	}
	var spaced: Dictionary = db.view({"id": "token_shiv", "upgraded": false}, spaced_def, 3)
	_check(int(spaced.effects[0].value) == 9, "token_shiv bonus applies to the damage value")
	_check(str(spaced.get("description", "")).contains("9 点伤害"), "token_shiv tooltip reflects the bonus")
	_check(not str(spaced.get("description", "")).contains("6 点伤害"), "token_shiv tooltip drops the base number")
	var spaced_up: Dictionary = db.view({"id": "token_shiv", "upgraded": true}, spaced_def, 3)
	_check(int(spaced_up.effects[0].value) == 14, "upgraded token_shiv bonus applies to upgraded damage")
	_check(str(spaced_up.get("description", "")).contains("14 点伤害"), "upgraded token_shiv tooltip reflects the total")
	_check(not str(spaced_up.get("description", "")).contains("11 点伤害"), "upgraded token_shiv tooltip drops the base number")
	_check(db.view({}, {}).is_empty(), "view() returns an empty dictionary for a missing definition")
