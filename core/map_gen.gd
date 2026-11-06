extends RefCounted
## Map generation, routing and node resolution, extracted verbatim from
## core/game_engine.gd. Engine counterparts: _make_map(), route_exits() and
## _resolve_node_kind(). Every function is static; rng is duck-typed and only
## needs randi_range(stream, low, high) (RandomStreams or a test stub).

const CHAPTER_NODES = 15
const LANES = 3
const INITIAL_POOL = ["normal", "normal", "normal", "normal", "unknown", "unknown", "elite", "shop", "treasure", "fate"]
const FINAL_POOL = ["normal", "elite", "unknown", "shop", "fate", "treasure"]
const LANDMARKS = [[1, "unknown"], [3, "shop"], [4, "elite"], [5, "treasure"], [6, "fate"], [7, "rest"]]
const POSSIBILITIES = ["normal", "elite", "event", "treasure", "shop", "rest"]


static func generate(rng, chapter_nodes: int = 15) -> Array:
	var result = []
	var pool = INITIAL_POOL.duplicate()
	for row in range(chapter_nodes):
		var nodes = []
		for lane in range(LANES):
			var kind = pool[rng.randi_range("map", 0, pool.size() - 1)]
			if row == 0:
				kind = "normal"
			elif row == chapter_nodes - 2:
				var final_pool = FINAL_POOL.duplicate()
				kind = final_pool[rng.randi_range("map", 0, final_pool.size() - 1)]
			elif row == chapter_nodes - 1:
				kind = "boss"
			elif row == 1 and kind == "elite":
				kind = "normal"
			nodes.append({"kind": kind, "cleared": false, "next": [lane] if row < chapter_nodes - 1 else []})
		result.append(nodes)
	# Guaranteed chapter landmarks, with seed-dependent lanes. Random weights alone
	# could otherwise omit an entire node type from a chapter.
	for landmark in LANDMARKS:
		result[landmark[0]][rng.randi_range("map", 0, 2)].kind = landmark[1]
	# Randomly choose the varied room; the other two are camps.
	var varied_lane = rng.randi_range("map", 0, 2)
	for lane in range(LANES):
		if lane != varied_lane:
			result[chapter_nodes - 2][lane].kind = "rest"
	for row in range(chapter_nodes - 1):
		var diagonal_count = 0
		for left_lane in range(2):
			var direction = rng.randi_range("map", 0, 2)
			# Only one diagonal orientation per adjacent lane pair: the two
			# opposing diagonals would cross without sharing a node.
			if direction == 1:
				result[row][left_lane].next.append(left_lane + 1)
				diagonal_count += 1
			elif direction == 2:
				result[row][left_lane + 1].next.append(left_lane)
				diagonal_count += 1
		if diagonal_count == 0:
			var left_lane = rng.randi_range("map", 0, 1)
			if rng.randi_range("map", 0, 1) == 0:
				result[row][left_lane].next.append(left_lane + 1)
			else:
				result[row][left_lane + 1].next.append(left_lane)
		for node in result[row]:
			node.next.sort()
	return result


static func route_exits(route: Array, row: int, lane: int) -> Array:
	var result = []
	if row < 0 or row >= route.size() - 1:
		return result
	if not route[row] is Array or not route[row + 1] is Array or lane < 0 or lane >= route[row].size():
		return result
	var node = route[row][lane]
	if not node is Dictionary:
		return result
	# Old saves have no explicit edges. Keep their original adjacency rule
	# without rebuilding maps or consuming random numbers during reads.
	var exits = node.get("next", [lane - 1, lane, lane + 1])
	if not exits is Array:
		return result
	for destination in exits:
		if not (destination is int) and not (destination is float):
			continue
		var next_lane = int(destination)
		if float(destination) != float(next_lane) or next_lane < 0 or next_lane >= mini(3, route[row + 1].size()) or absi(next_lane - lane) > 1:
			continue
		if route[row + 1][next_lane] is Dictionary and not result.has(next_lane):
			result.append(next_lane)
	result.sort()
	return result


static func resolve_kind(node: Dictionary, rng) -> String:
	var kind = str(node.get("kind", "normal"))
	if kind == "fate":
		return "event"
	if kind != "unknown":
		return kind
	if node.has("resolved_kind"):
		var resolved = str(node.resolved_kind)
		return resolved if resolved in POSSIBILITIES else "normal"
	var resolved = POSSIBILITIES[rng.randi_range("event", 0, POSSIBILITIES.size() - 1)]
	node.resolved_kind = resolved
	return resolved
