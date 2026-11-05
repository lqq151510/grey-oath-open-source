extends Control
## Only draws exits supplied by GameEngine.route_exits; preview never advances rules.

var nodes: Array = []
var exits: Array = []
var visited: Array = []
var current_row: int = -1
var current_lane: int = -1
var preview_nodes: Dictionary = {}
var preview_edges: Dictionary = {}
var gold := Color("c7a66a")


func preview_from(row: int, lane: int) -> int:
	preview_nodes.clear()
	preview_edges.clear()
	if row < 0 or row >= nodes.size() or lane < 0 or lane >= nodes[row].size():
		return 0
	var frontier: Array = [lane]
	preview_nodes["%d:%d" % [row, lane]] = true
	for level in range(row, nodes.size() - 1):
		var next_frontier: Array = []
		for source_lane in frontier:
			for destination in _exits(level, int(source_lane)):
				preview_edges["%d:%d:%d" % [level, source_lane, destination]] = true
				preview_nodes["%d:%d" % [level + 1, destination]] = true
				if not next_frontier.has(destination):
					next_frontier.append(destination)
		frontier = next_frontier
	_sync_preview()
	return maxi(0, preview_nodes.size() - 1)


func clear_preview() -> void:
	preview_nodes.clear()
	preview_edges.clear()
	_sync_preview()


func _sync_preview() -> void:
	for row in range(nodes.size()):
		for lane in range(nodes[row].size()):
			var node = nodes[row][lane]
			if is_instance_valid(node) and node.has_method("set_preview"):
				node.set_preview(preview_nodes.has("%d:%d" % [row, lane]))
	queue_redraw()


func _exits(row: int, lane: int) -> Array:
	if row < 0 or row >= exits.size() or lane < 0 or lane >= exits[row].size():
		return []
	return exits[row][lane]


func _was_visited(row: int, lane: int) -> bool:
	return row >= 0 and row < visited.size() and lane >= 0 and lane < visited[row].size() and bool(visited[row][lane])


func _draw() -> void:
	for row in range(nodes.size() - 1):
		for lane in range(nodes[row].size()):
			for next_lane in _exits(row, lane):
				if int(next_lane) < 0 or int(next_lane) >= nodes[row + 1].size():
					continue
				var from_node = nodes[row][lane]
				var to_node = nodes[row + 1][int(next_lane)]
				if not is_instance_valid(from_node) or not is_instance_valid(to_node):
					continue
				var start: Vector2 = from_node.get_path_center() - global_position
				var finish: Vector2 = to_node.get_path_center() - global_position
				var direction := (finish - start).normalized()
				start += direction * 23
				finish -= direction * 23
				var active := row == current_row and lane == current_lane
				var walked := _was_visited(row, lane) and _was_visited(row + 1, int(next_lane))
				var preview := preview_edges.has("%d:%d:%d" % [row, lane, next_lane])
				var color := Color("565c4d")
				if row < current_row and not walked:
					color = Color("30362c")
				if active or walked:
					color = Color(gold, 0.90 if active else 0.62)
				if preview:
					color = Color("b1c3a1")
				if active or walked or preview:
					draw_line(start, finish, color, 2.0 if active or preview else 1.7, true)
				else:
					_dashed_line(start, finish, color)


func _dashed_line(from: Vector2, to: Vector2, color: Color) -> void:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var offset := 0.0
	while offset < length:
		draw_line(from + direction * offset, from + direction * minf(offset + 5, length), color, 1.2, true)
		offset += 9.0
