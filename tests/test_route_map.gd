extends SceneTree
## Isolated route generation and room-transition checks, never the player's save.

const Rules = preload("res://core/game_engine.gd")
const REQUIRED = ["normal", "elite", "treasure", "shop", "unknown", "fate", "boss", "rest"]
var checks := 0
var failures: Array[String] = []
var maps_checked := 0
var unknown_outcomes: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func game(seed_value: int = 42):
	var instance = Rules.new("")
	instance.new_run("warden", seed_value)
	return instance


func _run() -> void:
	_test_generation()
	_test_explicit_edges()
	_test_legacy()
	_test_unknown()
	_test_rooms_and_chapters()
	print("ROUTE_MAP_RESULT=" + JSON.stringify({"checks": checks, "failures": failures, "maps_checked": maps_checked, "unknown_outcomes": unknown_outcomes, "scope": "seeded route invariants, legacy compatibility, isolated saves and fixture room transitions; no manual-play or balance claim"}))
	quit(0 if failures.is_empty() else 1)


func _test_generation() -> void:
	var preboss_kinds: Dictionary = {}
	for seed_value in range(48):
		var left = game(seed_value)
		var right = game(seed_value)
		for chapter in range(4):
			left.state.chapter = chapter
			right.state.chapter = chapter
			if chapter > 0:
				left.state.map = left._make_map()
				right.state.map = right._make_map()
			check(left.state.map == right.state.map, "same seed and chapter sequence gives identical map")
			_validate_map(left, "seed %d chapter %d" % [seed_value, chapter])
			for node in left.state.map[Rules.CHAPTER_NODES - 2]: preboss_kinds[node.kind] = true
			maps_checked += 1
	for kind in ["rest", "normal", "elite", "unknown", "shop", "fate", "treasure"]:
		check(preboss_kinds.has(kind), "pre-boss floor can contain " + kind)
	var first = game(1)
	var second = game(2)
	check(first.state.map != second.state.map, "different seeds produce different routes")


func _validate_map(instance, context: String) -> void:
	var route: Array = instance.state.map
	check(route.size() == Rules.CHAPTER_NODES, context + " has the configured floor count")
	var last := route.size() - 1
	var counts: Dictionary = {}
	var reachable: Array = [0, 1, 2]
	var branches := 0
	var merges := 0
	for row in range(route.size()):
		check(route[row].size() == 3, context + " has three lanes")
		check(reachable.size() == 3, context + " every node is reachable from an entrance")
		var next_reachable: Array = []
		var incoming = [0, 0, 0]
		for lane in range(3):
			var node = route[row][lane]
			var kind = str(node.kind)
			counts[kind] = int(counts.get(kind, 0)) + 1
			check(REQUIRED.has(kind) and not node.cleared, context + " supported fresh node")
			check(not node.has("resolved_kind"), context + " question node not prematurely revealed")
			if row == 0:
				check(kind == "normal", context + " opening is normal combat")
			elif row == 1:
				check(kind != "elite", context + " no early elite")
			elif row == last:
				check(kind == "boss", context + " final floor is boss")
			check(node.has("next") and node.next is Array, context + " explicit edges stored")
			var exits: Array = instance.route_exits(row, lane)
			check(exits == node.next, context + " generated edges already valid and unique")
			if row == last:
				check(exits.is_empty(), context + " boss has no outgoing edges")
			else:
				check(exits.has(lane), context + " straight edge guarantees no dead end")
				if exits.size() > 1:
					branches += 1
				for destination in exits:
					check(absi(destination - lane) <= 1, context + " edge connects adjacent lanes only")
					incoming[destination] += 1
					if reachable.has(lane) and not next_reachable.has(destination):
						next_reachable.append(destination)
		if row < last:
			for lane in range(2):
				check(not (route[row][lane].next.has(lane + 1) and route[row][lane + 1].next.has(lane)), context + " opposing diagonal edges never cross")
			for count in incoming:
				if count > 1:
					merges += 1
		reachable = next_reachable
	check(route[last - 1].filter(func(node): return node.kind == "rest").size() == 2, context + " exactly two pre-boss camps")
	for kind in REQUIRED:
		check(int(counts.get(kind, 0)) > 0, context + " includes " + kind)
	check(branches > 0 and merges > 0, context + " contains true branches and merges")


func _test_explicit_edges() -> void:
	var instance = game()
	instance.state.row = 0
	instance.state.lane = 0
	instance.state.map[0][0].next = [0]
	var before = JSON.stringify(instance.state)
	check(instance.available_nodes() == [0], "availability follows explicit edges")
	check(not instance.enter_node(1).ok, "adjacent but unconnected lane is rejected")
	check(JSON.stringify(instance.state) == before, "rejected route move has no state or RNG effect")
	instance.state.map[1][0].kind = "rest"
	check(instance.enter_node(0).ok and instance.state.room == "rest", "connected route can be entered")
	instance.state.map[0][0].next = []
	check(instance.route_exits(0, 0).is_empty(), "explicit empty edges never fall back to legacy adjacency")
	instance.state.map[0][0].next = [0, 2, -1, 1.5, "1", true, 1, 1]
	check(instance.route_exits(0, 0) == [0, 1], "invalid, duplicate and nonadjacent destinations are rejected")
	instance.state.map[0][0].next = "invalid"
	check(instance.route_exits(0, 0).is_empty(), "invalid explicit edge type fails closed")
	for coordinate in [[-1, 0], [0, -1], [0, 3], [Rules.CHAPTER_NODES - 1, 1], [Rules.CHAPTER_NODES, 1]]:
		check(instance.route_exits(coordinate[0], coordinate[1]).is_empty(), "invalid or final route coordinates have no exits")


func _test_legacy() -> void:
	var instance = game()
	instance.state.map = instance.state.map.slice(0, 10)
	for row in instance.state.map:
		for node in row:
			node.erase("next")
	var before = JSON.stringify(instance.state)
	check(instance.route_exits(0, 0) == [0, 1], "legacy left lane retains old adjacency")
	check(instance.route_exits(0, 1) == [0, 1, 2], "legacy middle lane retains old adjacency")
	check(instance.route_exits(0, 2) == [1, 2], "legacy right lane retains old adjacency")
	check(instance.route_exits(9, 1).is_empty(), "ten-floor legacy route stops at its own final floor")
	check(JSON.stringify(instance.state) == before, "legacy reads do not migrate or regenerate maps")
	var path = "user://route-legacy-test-%d.json" % Time.get_ticks_usec()
	instance._save_path = path
	check(instance.save_game(), "legacy-shaped fixture saves")
	var loaded = Rules.new(path)
	check(loaded.state.map == instance.state.map and not loaded.state.map[0][0].has("next"), "loading preserves old map verbatim")
	loaded.state.map[0][1].kind = "event"
	check(loaded.enter_node(1).ok and loaded.state.room == "event", "legacy event node still resolves")
	_cleanup(path)


func _test_unknown() -> void:
	for seed_value in range(96):
		var instance = game(seed_value)
		instance.state.map[0][1].kind = "unknown"
		var before = JSON.stringify(instance.state)
		for ignored in range(3):
			instance.available_nodes()
			instance.route_exits(0, 1)
		check(JSON.stringify(instance.state) == before, "route preview does not resolve unknown or advance RNG")
		var expected_rng = RandomNumberGenerator.new()
		expected_rng.seed = int(instance.state.rng_states.event.seed)
		expected_rng.state = int(instance.state.rng_states.event.state)
		var possibilities = ["normal", "elite", "event", "treasure", "shop", "rest"]
		var expected = possibilities[expected_rng.randi_range(0, possibilities.size() - 1)]
		check(instance.enter_node(1).ok, "unknown node enters a supported room")
		var node = instance.state.map[0][1]
		var resolved = str(node.resolved_kind)
		check(resolved == expected, "question follows uniform seeded event-stream selection")
		check(node.kind == "unknown" and resolved in ["normal", "elite", "event", "treasure", "shop", "rest"], "question keeps its identity and records actual encounter")
		check(instance.state.encounter_kind == resolved, "encounter kind is actual resolved type")
		check(instance.state.room == ("battle" if resolved in ["normal", "elite"] else resolved), "resolved type dispatches correct existing room")
		var rng_before = JSON.stringify(instance.state.rng_states)
		check(instance._resolve_node_kind(node) == resolved, "resolved question is reused")
		instance._sync_rng()
		check(JSON.stringify(instance.state.rng_states) == rng_before, "reusing resolution consumes no RNG")
		if not unknown_outcomes.has(resolved):
			unknown_outcomes[resolved] = seed_value
			_test_unknown_save(seed_value, resolved)
	for kind in ["normal", "elite", "event", "treasure", "shop", "rest"]:
		check(unknown_outcomes.has(kind), "question can reveal " + kind)


func _test_unknown_save(seed_value: int, expected: String) -> void:
	var instance = game(seed_value)
	instance.state.map[0][1].kind = "unknown"
	var path = "user://route-unknown-test-%d.json" % Time.get_ticks_usec()
	instance._save_path = path
	check(instance.save_game(), "unrevealed question save succeeds")
	var loaded = Rules.new(path)
	check(not loaded.state.map[0][1].has("resolved_kind"), "loading does not reveal question")
	instance.enter_node(1)
	loaded.enter_node(1)
	check(loaded.state.map[0][1].resolved_kind == expected, "saving before question preserves eventual outcome")
	check(JSON.stringify(instance.state) == JSON.stringify(loaded.state), "pre-entry reload reproduces exact room, rewards and RNG")
	var after = Rules.new(path)
	check(JSON.stringify(after.state) == JSON.stringify(loaded.state), "post-entry reload preserves resolved room and map")
	var before = JSON.stringify(after.state)
	check(not after.enter_node(1).ok and JSON.stringify(after.state) == before, "cannot enter question twice while its room is active")
	check(after._resolve_node_kind(after.state.map[0][1]) == expected, "post-entry resolution remains fixed")
	_cleanup(path)


func _test_rooms_and_chapters() -> void:
	for kind in ["fate", "event", "treasure", "shop", "rest"]:
		var instance = game()
		instance.state.map[0][1].kind = kind
		check(instance.enter_node(1).ok, "can enter " + kind)
		if kind in ["fate", "event"]:
			check(instance.state.room == "event" and instance.state.encounter_kind == "event", "fate and legacy event reuse event room")
			check(not instance.state.event.get("choices", []).is_empty(), "fate contains real catalog choices")
			var selected := false
			for choice in range(instance.state.event.choices.size()):
				if instance.choose_event(choice).ok:
					selected = true
					break
			check(selected, "fate/event has an affordable exit")
		elif kind == "rest":
			check(instance.rest().ok, "camp completes")
		else:
			check(instance.leave_room().ok, kind + " completes")
		check(instance.state.room == "map" and instance.state.map[0][1].cleared, kind + " marks visited node cleared")
		check(not instance.available_nodes().is_empty(), kind + " continues along route")
	var instance = game()
	for chapter in range(4):
		instance.state.row = instance.state.map.size() - 2
		instance.state.lane = 1
		instance.state.room = "map"
		check(instance.enter_node(1).ok and instance.state.encounter_kind == "boss", "boss entrance follows final edge")
		for phase in range(int(instance.state.boss_phases)):
			for enemy in instance.state.enemies:
				enemy.hp = 0
			instance._check_battle_end()
		check(instance.state.room == "reward", "fixture boss clear produces rewards")
		check(instance.choose_reward(-1).ok, "boss reward can complete")
		if chapter < 3:
			check(instance.state.chapter == chapter + 1 and instance.state.row == -1 and instance.state.lane == -1, "boss advances and resets route position")
			check(instance.state.room == "map" and instance.available_nodes() == [0, 1, 2], "next chapter exposes three entrance choices")
			_validate_map(instance, "boss transition chapter %d" % (chapter + 1))
		else:
			check(instance.state.room == "victory" and not instance.state.active, "fourth boss still completes entire run")
	check(Rules.SAVE_VERSION == 1, "route extension retains save version")


func _cleanup(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
