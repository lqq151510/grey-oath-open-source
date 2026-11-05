extends VBoxContainer
## Edits a portable draft. The rules layer validates it again before a trial.

signal draft_changed(pack: Dictionary)
signal trial_requested(pack: Dictionary)
signal back_requested

const WorkshopPack = preload("res://core/workshop_pack.gd")
const GOLD := Color("c7a66a")
const MUTED := Color("aaa99a")
const RED := Color("e5a49c")

var _game
var _pack: Dictionary
var _status: Label
var _deck_picker: OptionButton
var _deck_list: ItemList
var _deck_add: Button
var _deck_remove: Button
var _deck_count: Label
var _item_amount: SpinBox
var _scroll: ScrollContainer


func setup(game, draft: Dictionary) -> void:
	_game = game
	_pack = draft.duplicate(true)
	name = "WorkshopEditor"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	var header := HBoxContainer.new()
	add_child(header)
	var title := _label(header, "本地创意工坊", 36, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "← 返回主菜单", "WorkshopBackButton", func(): back_requested.emit())
	var intro := _label(self, "编辑六类内容，用同一份作品打一场试玩。导出 JSON 后可以和其他玩家交换。", 16, MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var identity := HBoxContainer.new()
	add_child(identity)
	_text(identity, _pack, "title", "作品名称", "WorkshopTitle", 32)

	_scroll = ScrollContainer.new()
	_scroll.name = "WorkshopScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(grid)
	_build_role(grid)
	_build_enemy(grid)
	_build_item(grid)
	_build_card(grid)
	_build_talent(grid)
	_build_deck(grid)

	_status = _label(self, "试玩使用独立战斗，结果不会计入正式旅程。", 15, MUTED)
	_status.name = "WorkshopStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var controls := HBoxContainer.new()
	add_child(controls)
	_button(controls, "导入作品", "WorkshopImportButton", _import_pack)
	_button(controls, "导出作品", "WorkshopExportButton", _export_pack)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	var trial := _button(controls, "开始试玩  →", "WorkshopTrialButton", _start_trial)
	trial.add_theme_color_override("font_color", GOLD)


func _build_role(grid: GridContainer) -> void:
	var section := _section(grid, "01", "角色")
	var role: Dictionary = _pack.role
	_text(section, role, "name", "角色名称", "WorkshopRoleName")
	var choices: Array = []
	for base in _game.data.roles:
		choices.append([str(base.id), str(base.name)])
	var base_choice := _choice(section, role, "base", "沿用职业", "WorkshopRoleBase", choices)
	base_choice.tooltip_text = "沿用此职业的立绘和战斗机制。切换职业会重置下方的起始牌组。"
	base_choice.item_selected.connect(func(_index: int):
		_pack.build.starter_cards = WorkshopPack.default_deck(_game, str(role.base))
		_redraw_deck()
		_show_status("已按新职业重置起始牌组。", MUTED)
		_changed())
	_number(section, role, "hp", "生命上限", "WorkshopRoleHP", 1, 200)


func _build_enemy(grid: GridContainer) -> void:
	var section := _section(grid, "02", "怪物")
	var enemy: Dictionary = _pack.enemy
	_text(section, enemy, "name", "怪物名称", "WorkshopEnemyName")
	_number(section, enemy, "hp", "生命上限", "WorkshopEnemyHP", 1, 200)
	_number(section, enemy, "attack", "攻击伤害", "WorkshopEnemyAttack", 1, 40)
	_number(section, enemy, "block", "格挡数值", "WorkshopEnemyBlock", 0, 40)
	_label(section, "按攻击、格挡的顺序循环。", 14, MUTED)


func _build_item(grid: GridContainer) -> void:
	var section := _section(grid, "03", "道具")
	var item: Dictionary = _pack.item
	_text(section, item, "name", "道具名称", "WorkshopItemName")
	var kind := _choice(section, item, "kind", "使用效果", "WorkshopItemKind", [["heal", "回复生命"], ["block", "获得格挡"], ["energy", "获得能量"]])
	_item_amount = _number(section, item, "amount", "效果数值", "WorkshopItemAmount", 1, 3 if item.kind == "energy" else 40)
	kind.item_selected.connect(func(_index: int):
		_item_amount.max_value = 3 if item.kind == "energy" else 40
		_item_amount.value = minf(_item_amount.value, _item_amount.max_value))
	_label(section, "试玩开始时获得一件，可用一次。", 14, MUTED)


func _build_card(grid: GridContainer) -> void:
	var section := _section(grid, "04", "卡牌")
	var card: Dictionary = _pack.card
	var card_name := _text(section, card, "name", "卡牌名称", "WorkshopCardName")
	card_name.text_changed.connect(func(_text_value: String): _redraw_deck())
	_choice(section, card, "kind", "牌型与效果", "WorkshopCardKind", [["attack", "攻击 · 造成伤害"], ["skill", "技能 · 获得格挡"]])
	_number(section, card, "cost", "能量费用", "WorkshopCardCost", 0, 3)
	_number(section, card, "amount", "效果数值", "WorkshopCardAmount", 1, 40)


func _build_talent(grid: GridContainer) -> void:
	var section := _section(grid, "05", "天赋")
	var talent: Dictionary = _pack.talent
	_text(section, talent, "name", "天赋名称", "WorkshopTalentName")
	_choice(section, talent, "kind", "开战效果", "WorkshopTalentKind", [["strength", "获得力量"], ["block", "获得格挡"]])
	_number(section, talent, "amount", "效果数值", "WorkshopTalentAmount", 1, 20)
	_label(section, "天赋在战斗开始时自动触发。", 14, MUTED)


func _build_deck(grid: GridContainer) -> void:
	var section := _section(grid, "06", "流派")
	var build: Dictionary = _pack.build
	_text(section, build, "name", "流派名称", "WorkshopBuildName")
	_text(section, build, "description", "打法说明", "WorkshopBuildDescription", 240)
	_deck_count = _label(section, "", 15, MUTED)
	_deck_list = ItemList.new()
	_deck_list.name = "WorkshopDeckList"
	_deck_list.custom_minimum_size.y = 96.0
	_deck_list.allow_reselect = true
	_deck_list.item_selected.connect(func(_index: int): _deck_remove.disabled = false)
	section.add_child(_deck_list)
	var controls := HBoxContainer.new()
	section.add_child(controls)
	_deck_picker = OptionButton.new()
	_deck_picker.name = "WorkshopDeckPicker"
	_deck_picker.fit_to_longest_item = false
	_deck_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_deck_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_deck_picker)
	_deck_add = _button(controls, "加牌", "WorkshopDeckAdd", _add_card)
	_deck_remove = _button(controls, "移除", "WorkshopDeckRemove", _remove_card)
	_redraw_deck()


func _redraw_deck() -> void:
	if not is_instance_valid(_deck_picker):
		return
	var current := str(_deck_picker.get_item_metadata(_deck_picker.selected)) if _deck_picker.selected >= 0 else WorkshopPack.CARD_ID
	var selected := _deck_list.get_selected_items()
	_deck_picker.clear()
	var role: Dictionary = _game.role_data(str(_pack.role.base))
	var ids: Array = [WorkshopPack.CARD_ID]
	for id in role.get("starter_cards", []):
		if not ids.has(id):
			ids.append(id)
	for id in ids:
		_deck_picker.add_item(_card_name(str(id)))
		var index := _deck_picker.item_count - 1
		_deck_picker.set_item_metadata(index, id)
		if id == current:
			_deck_picker.select(index)
	_deck_list.clear()
	var cards: Array = _pack.build.starter_cards
	for id in cards:
		_deck_list.add_item(_card_name(str(id)))
	if not selected.is_empty() and selected[0] < cards.size():
		_deck_list.select(selected[0])
	_deck_count.text = "起始牌组 %d / 12 · 至少 5 张，须含自制牌" % cards.size()
	_deck_add.disabled = cards.size() >= 12
	_deck_remove.disabled = _deck_list.get_selected_items().is_empty()


func _card_name(id: String) -> String:
	if id == WorkshopPack.CARD_ID:
		return "%s（自制）" % str(_pack.card.name)
	var card: Dictionary = _game.card_data(id)
	return str(card.get("name", id))


func _add_card() -> void:
	var cards: Array = _pack.build.starter_cards
	if _deck_picker.selected < 0 or cards.size() >= 12:
		return
	cards.append(str(_deck_picker.get_item_metadata(_deck_picker.selected)))
	_redraw_deck()
	_changed()


func _remove_card() -> void:
	var selected := _deck_list.get_selected_items()
	if selected.is_empty():
		return
	_pack.build.starter_cards.remove_at(selected[0])
	_redraw_deck()
	_changed()


func _section(parent: Control, number: String, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	margin.add_child(fields)
	_label(fields, "%s  /  %s" % [number, title], 20, GOLD)
	return fields


func _field(parent: Control, caption: String, node: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, caption, 15, MUTED)
	label.custom_minimum_size.x = 88.0
	node.custom_minimum_size.y = 31.0
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(node)


func _text(parent: Control, section: Dictionary, key: String, caption: String, node_name: String, limit: int = 24) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.max_length = limit
	field.text = str(section[key])
	field.text_changed.connect(func(value: String):
		section[key] = value
		_changed())
	_field(parent, caption, field)
	return field


func _number(parent: Control, section: Dictionary, key: String, caption: String, node_name: String, minimum: int, maximum: int) -> SpinBox:
	var field := SpinBox.new()
	field.name = node_name
	field.min_value = minimum
	field.max_value = maximum
	field.step = 1.0
	field.value = int(section[key])
	field.value_changed.connect(func(value: float):
		section[key] = int(value)
		_changed())
	_field(parent, caption, field)
	return field


func _choice(parent: Control, section: Dictionary, key: String, caption: String, node_name: String, choices: Array) -> OptionButton:
	var field := OptionButton.new()
	field.name = node_name
	field.fit_to_longest_item = false
	for pair in choices:
		field.add_item(str(pair[1]))
		var index := field.item_count - 1
		field.set_item_metadata(index, pair[0])
		if section[key] == pair[0]:
			field.select(index)
	field.item_selected.connect(func(index: int):
		section[key] = field.get_item_metadata(index)
		_changed())
	_field(parent, caption, field)
	return field


func _label(parent: Node, copy: String, size: int, tone: Color) -> Label:
	var label := Label.new()
	label.text = copy
	label.add_theme_color_override("font_color", tone)
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _button(parent: Node, copy: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = copy
	button.custom_minimum_size.y = 38.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _changed() -> void:
	draft_changed.emit(_pack.duplicate(true))


func _show_status(copy: String, tone: Color) -> void:
	_status.text = copy
	_status.add_theme_color_override("font_color", tone)


func _validated_pack() -> Dictionary:
	var result := WorkshopPack.validate(_pack, _game)
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("message", "请检查作品内容。")), RED)
		return {}
	return result.pack


func _start_trial() -> void:
	var validated := _validated_pack()
	if not validated.is_empty():
		trial_requested.emit(validated)


func _file_dialog(mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.name = "WorkshopExportDialog" if mode == FileDialog.FILE_MODE_SAVE_FILE else "WorkshopImportDialog"
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.add_filter("*.json", "灰誓工坊作品")
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	return dialog


func _import_pack() -> void:
	var dialog := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "导入灰誓工坊作品")
	dialog.file_selected.connect(func(path: String):
		dialog.queue_free()
		_read_pack(path))
	dialog.popup_centered_ratio(0.72)


func _read_pack(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_status("无法读取所选文件。", RED)
		return
	if file.get_length() > WorkshopPack.MAX_BYTES:
		_show_status("所选文件超过工坊作品的大小上限。", RED)
		return
	var result := WorkshopPack.parse_text(file.get_as_text(), _game)
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("message", "无法导入这个作品。")), RED)
		return
	_pack = result.pack
	_changed()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()
	_show_status("已导入「%s」。" % _pack.title, GOLD)


func _export_pack() -> void:
	var validated := _validated_pack()
	if validated.is_empty():
		return
	var dialog := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "导出灰誓工坊作品")
	dialog.current_file = "灰誓工坊.json"
	dialog.file_selected.connect(func(path: String):
		dialog.queue_free()
		if _is_journey_save_path(path):
			_show_status("请选择独立的作品文件，不能覆盖旅程存档或其备份。", RED)
			return
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_show_status("无法写入所选位置。", RED)
			return
		file.store_string(JSON.stringify(validated, "\t"))
		file.flush()
		if file.get_error() == OK:
			_show_status("已导出「%s」。" % validated.title, GOLD)
		else:
			_show_status("写入作品失败，请检查可用空间。", RED))
	dialog.popup_centered_ratio(0.72)


func _is_journey_save_path(path: String) -> bool:
	var target := ProjectSettings.globalize_path(path).simplify_path().to_lower()
	for save_path in ["user://save.json", str(_game._save_path)]:
		if save_path.is_empty():
			continue
		var base := ProjectSettings.globalize_path(save_path).simplify_path().to_lower()
		if target in [base, base + ".bak", base + ".tmp"]:
			return true
	return false
