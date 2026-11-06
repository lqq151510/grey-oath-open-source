extends RefCounted

const RoutePaths = preload("res://ui/route_paths.gd")
const MapNodeVisual = preload("res://ui/map_node_visual.gd")

static func build(ui) -> void:
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	ui.body.add_child(columns)
	var chronicle := PanelContainer.new()
	chronicle.name = "MapChronicle"
	chronicle.custom_minimum_size.x = 320
	chronicle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chronicle.add_theme_stylebox_override("panel", ui._sts_box(Color(0.062, 0.055, 0.045, 0.92), Color(0.46, 0.37, 0.23, 0.55), 1))
	columns.add_child(chronicle)
	var chronicle_margin := MarginContainer.new()
	chronicle_margin.add_theme_constant_override("margin_left", 20)
	chronicle_margin.add_theme_constant_override("margin_right", 20)
	chronicle_margin.add_theme_constant_override("margin_top", 18)
	chronicle_margin.add_theme_constant_override("margin_bottom", 16)
	chronicle.add_child(chronicle_margin)
	var introduction := VBoxContainer.new()
	introduction.add_theme_constant_override("separation", 9)
	chronicle_margin.add_child(introduction)
	ui._label(introduction, ui._spaced("第 %d 章 / 四重长夜" % (int(ui.game.state.chapter) + 1)), 12, ui.GOLD)
	ui._label(introduction, str(ui._chapter().get("name", "长夜")), 30, ui.PAPER, true)
	ui._paragraph(introduction, "由下向上，沿连线穿过 %d 层长夜。\n每次选择一处亮金节点，路线随之确定。" % ui.game.state.map.size(), 15)
	introduction.add_child(ui._room_rule())
	ui._label(introduction, "下一步 · 第 %d 层" % (int(ui.game.state.row) + 2), 21, ui.GOLD, true)
	ui._label(introduction, "历练 %d · 战斗胜利 %d / 4" % [int(ui.game.state.get("growth_level", 0)), int(ui.game.state.get("growth_wins", 0)) % 4], 15, ui.GOLD)
	ui._paragraph(introduction, "精英更凶险；营火可休整。\n商店需金币，当前携带 %d。\n问号进入后揭晓，命运需要抉择。" % int(ui.game.state.gold), 15)
	var inspect: Label = ui._paragraph(introduction, "悬停节点，预览从它出发的后续分支。\n预览不会移动角色。", 15, ui.PAPER)
	inspect.name = "MapPreviewInfo"
	inspect.custom_minimum_size.y = 96
	ui._spacer(introduction, true)
	ui._label(introduction, ui._spaced("路 标"), 14, ui.GOLD, true)
	var legend := GridContainer.new()
	legend.name = "MapLegend"
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 6)
	legend.add_theme_constant_override("v_separation", 0)
	introduction.add_child(legend)
	for kind in ["normal", "elite", "treasure", "shop", "unknown", "fate", "rest", "boss"]:
		var marker = MapNodeVisual.new()
		marker.legend_mode = true
		marker.custom_minimum_size = Vector2(140, 34)
		marker.configure(kind, str(ui.KIND_NAMES[kind]))
		marker.tooltip_text = _map_kind_hint(ui, kind)
		legend.add_child(marker)
	ui._paragraph(introduction, "金线：已走 / 可走　绿线：悬停预览\n双环：当前位置　虚线：未来分支", 12)
	ui._label(introduction, "旅程种子  %d" % int(ui.game.state.seed), 12, ui.MUTED)
	var map_frame := PanelContainer.new()
	map_frame.name = "MapFrame"
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.add_theme_stylebox_override("panel", ui._sts_box(Color(0.030, 0.027, 0.023, 0.97), Color(0.46, 0.37, 0.23, 0.55), 1))
	columns.add_child(map_frame)
	var holder := Control.new()
	holder.name = "MapHolder"
	holder.custom_minimum_size = Vector2(560, 560)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.add_child(holder)
	holder.add_child(ui._new_map_backdrop())
	var map_surface := Control.new()
	map_surface.name = "MapSurface"
	map_surface.custom_minimum_size = Vector2(550, 570)
	map_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_scroll := ScrollContainer.new()
	map_scroll.name = "MapScroll"
	map_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_scroll.offset_left = 8
	map_scroll.offset_right = -8
	map_scroll.offset_top = 6
	map_scroll.offset_bottom = -6
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(map_scroll)
	map_surface.custom_minimum_size.y = maxf(570, 78 + (ui.game.state.map.size() - 1) * 57)
	map_scroll.add_child(map_surface)
	map_scroll.set_deferred("scroll_vertical", maxi(0, int(map_surface.custom_minimum_size.y - (int(ui.game.state.row) + 1) * 57 - 420)))
	var lines = RoutePaths.new()
	lines.name = "MapPaths"
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.current_row = int(ui.game.state.row)
	lines.current_lane = int(ui.game.state.lane)
	map_surface.add_child(lines)
	var available: Array = ui.game.available_nodes()
	var all_nodes: Array = []
	var layer_labels: Array = []
	for row_index in range(ui.game.state.map.size()):
		var layer: Label = ui._label(map_surface, "%02d" % (row_index + 1), 13, ui.MUTED)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer_labels.append(layer)
		var buttons: Array = []
		var row_exits: Array = []
		var row_visited: Array = []
		for lane in range(3):
			var node: Dictionary = ui.game.state.map[row_index][lane]
			var active: bool = row_index == int(ui.game.state.row) + 1 and available.has(lane)
			var visited: bool = node.get("cleared", false)
			var current: bool = row_index == int(ui.game.state.row) and lane == int(ui.game.state.lane)
			var kind := _map_display_kind(ui, node)
			var button = MapNodeVisual.new()
			button.name = "MapNode_%d_%d" % [row_index, lane]
			button.configure(kind, str(ui.KIND_NAMES.get(kind, kind)), active, visited, current)
			button.tooltip_text = "第 %d 层 · %s\n%s\n%s" % [row_index + 1, ui.KIND_NAMES.get(kind, kind), _map_kind_hint(ui, kind), "当前位置" if current else ("已走过" if visited else ("点击前往" if active else "仅预览，当前不可前往"))]
			button.pressed.connect(func(): ui._sfx("click", 0.02, -14.0))
			button.pressed.connect(func() -> void: _enter_node(ui, lane))
			button.mouse_entered.connect(func() -> void: _map_preview(ui, row_index, lane, node, lines, inspect))
			button.mouse_exited.connect(func():
				lines.clear_preview()
				inspect.text = "悬停节点，预览从它出发的后续分支。\n预览不会移动角色。")
			map_surface.add_child(button)
			buttons.append(button)
			row_exits.append(ui.game.route_exits(row_index, lane))
			row_visited.append(visited or current)
		all_nodes.append(buttons)
		lines.exits.append(row_exits)
		lines.visited.append(row_visited)
	lines.nodes = all_nodes
	map_surface.resized.connect(func() -> void: _layout_map(ui, map_surface, all_nodes, layer_labels, lines))
	_layout_map(ui, map_surface, all_nodes, layer_labels, lines)

static func _layout_map(ui, surface: Control, nodes: Array, labels: Array, lines: Control) -> void:
	if not is_instance_valid(surface):
		return
	var top := 28.0
	var bottom := maxf(top + maxf(0, nodes.size() - 1) * 57.0, surface.size.y - 48.0)
	for row in range(nodes.size()):
		var y := lerpf(bottom, top, float(row) / maxf(1, nodes.size() - 1))
		labels[row].position = Vector2(8, y - 10)
		for lane in range(nodes[row].size()):
			var marker: Control = nodes[row][lane]
			var jitter := sin(float(row * 7 + lane * 11)) * 18.0
			var x := 64.0 + (surface.size.x - 108.0) * (0.12 + lane * 0.38) + jitter
			marker.size = Vector2(96, 54)
			marker.position = Vector2(x - 48, y - 21)
	lines.queue_redraw()

static func _map_display_kind(ui, node: Dictionary) -> String:
	var kind := str(node.get("kind", "normal"))
	if kind == "unknown" and bool(node.get("cleared", false)):
		return str(node.get("resolved_kind", "unknown"))
	return kind

static func _map_kind_hint(ui, kind: String) -> String:
	return str({
		"normal": "普通敌群，战胜后获得奖励。",
		"elite": "强敌守路，准备好生命和牌组再挑战。",
		"treasure": "发现遗宝，领取后继续旅程。",
		"shop": "分区购买卡牌、正面道具与补给，也可移除卡牌。",
		"unknown": "进入后随机揭晓战斗、精英、奇遇、宝箱、商店或营地。",
		"event": "命运抉择：阅读代价，再作选择。",
		"fate": "命运抉择：阅读代价，再作选择。",
		"rest": "回满生命、强化一张牌，或花5生命舍弃一件负面道具。",
		"boss": "本章最终守关者。做好准备，直面首领。"
	}.get(kind, "沿连线继续旅程。"))

static func _map_preview(ui, row: int, lane: int, node: Dictionary, lines: Control, inspect: Label) -> void:
	var count: int = lines.preview_from(row, lane)
	var kind := _map_display_kind(ui, node)
	var name_text := str(ui.KIND_NAMES.get(kind, kind))
	if str(node.get("kind", "")) == "unknown" and bool(node.get("cleared", false)):
		name_text = "问号 → " + name_text
	inspect.text = "第 %d 层 · %s\n%s\n%s" % [row + 1, name_text, _map_kind_hint(ui, kind), "本章路线终点。" if row == ui.game.state.map.size() - 1 else "后续 %d 处节点可达，绿线显示分支。" % count]

static func _enter_node(ui, lane: int) -> void:
	ui.selected_target = 0
	var result: Dictionary = ui.game.enter_node(lane)
	ui._accept(result)
	if result.get("ok", false) and ui.game.state.room == "battle":
		var draws: Array = []
		for index in ui.game.state.hand.size():
			draws.append({"hand_index": index, "card": ui.game.state.hand[index].duplicate(true)})
		ui._animate_draws(draws, true)
