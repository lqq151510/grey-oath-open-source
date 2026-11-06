extends RefCounted

const ExpeditionItems = preload("res://core/item_mechanics.gd")

static func build_event(ui) -> void:
	var event_data: Dictionary = ui.game.state.event
	var shell: VBoxContainer = ui._room_shell("长夜奇遇", str(event_data.get("name", "无名之地")), "", null)
	var story := PanelContainer.new()
	story.name = "EventStory"
	story.add_theme_stylebox_override("panel", ui._sts_box(Color(0.086, 0.076, 0.060, 0.92), Color(0.46, 0.37, 0.23, 0.4), 1))
	shell.add_child(story)
	var story_row := HBoxContainer.new()
	story_row.add_theme_constant_override("separation", 16)
	story.add_child(story_row)
	var bar := ColorRect.new()
	bar.color = Color(0.72, 0.58, 0.34, 0.75)
	bar.custom_minimum_size.x = 3
	story_row.add_child(bar)
	var story_margin := MarginContainer.new()
	story_margin.add_theme_constant_override("margin_left", 14)
	story_margin.add_theme_constant_override("margin_right", 18)
	story_margin.add_theme_constant_override("margin_top", 12)
	story_margin.add_theme_constant_override("margin_bottom", 12)
	story_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_row.add_child(story_margin)
	ui._paragraph(story_margin, str(event_data.get("description", "")), 21, ui.PAPER)
	var choices: Array = event_data.get("choices", [])
	var is_altar := str(event_data.get("id", "")) == "expedition_offer"
	var has_cards := false
	for choice in choices:
		has_cards = has_cards or choice.has("card")
	var choice_parent: Control = shell
	if has_cards:
		var scroll := ScrollContainer.new()
		scroll.name = "EventChoices"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		shell.add_child(scroll)
		var columns := HBoxContainer.new()
		columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
		columns.add_theme_constant_override("separation", 16)
		scroll.add_child(columns)
		choice_parent = columns
	else:
		ui._spacer(shell, true)
	for index in range(choices.size()):
		var choice: Dictionary = choices[index]
		var row: VBoxContainer = ui._panel(choice_parent)
		row.name = "EventChoice_%d" % index
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if has_cards:
			row.custom_minimum_size.x = 260
		else:
			row.custom_minimum_size.x = 980
			row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var offered_items: Array = choice.get("items", [])
		var visible_item_ids: Array = offered_items.duplicate()
		if choice.has("relic"):
			visible_item_ids.append(str(choice.relic))
		var description := str(choice.get("description", ""))
		if is_altar and offered_items.any(func(id): return ui.game.item_data(str(id)).get("kind", "") == "permanent"):
			description = ExpeditionItems.PERMANENT_OFFER_DESCRIPTION
		ui._paragraph(row, description, 17)
		if not visible_item_ids.is_empty():
			var offered_icons := HBoxContainer.new()
			offered_icons.name = "EventChoiceItemIcons_%d" % index
			offered_icons.add_theme_constant_override("separation", 7)
			for item_id in visible_item_ids:
				var item_definition: Dictionary = ui.game.item_data(str(item_id))
				var item_category := "item"
				if item_definition.is_empty():
					item_definition = ui.game.relic_data(str(item_id))
					item_category = "relic"
				if not item_definition.is_empty():
					ui._add_item_icon(offered_icons, item_definition, item_category, 42.0)
			row.add_child(offered_icons)
		var effects: Array[String] = []
		for key in ["hp", "gold", "max_hp", "heal"]:
			if choice.has(key) and int(choice[key]) != 0:
				effects.append("%s %+d" % [{"hp": "生命", "gold": "金币", "max_hp": "生命上限", "heal": "回复生命"}[key], int(choice[key])])
		if choice.has("card"):
			effects.append("获得卡牌「%s」" % ui.game.card_data(str(choice.card)).get("name", choice.card))
		if choice.has("relic"):
			var relic: Dictionary = ui.game.relic_data(str(choice.relic))
			effects.append("获得遗物「%s」：%s" % [relic.get("name", choice.relic), relic.get("description", "")])
		for id in offered_items:
			effects.append(ui._expedition_item_detail(str(id)))
		var effect_text := "；".join(effects) if not effects.is_empty() else "不改变生命或资源"
		# 数据里的 description 往往已经写明代价/收益；只对道具类选择补一行结构化说明，避免整行重复。
		if choice.has("items") or description.strip_edges().is_empty():
			if effect_text != description:
				ui._paragraph(row, effect_text, 17, ui.GOLD)
		if choice.has("card"):
			var instance := {"id": str(choice.card), "upgraded": false}
			var definition: Dictionary = ui.game.card_view(instance)
			if not definition.is_empty():
				var preview: Button = ui._card(row, instance, func(): pass, Vector2(230, 248), "preview")
				preview.name = "EventCard_%d" % index
				preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				preview.get_node("CardVisual/Availability").text = "选择下方选项获得此牌"
				var detail: Label = ui._paragraph(row, str(definition.get("description", "")), 16, ui.PAPER)
				detail.name = "EventCardEffect_%d" % index
		if has_cards:
			ui._spacer(row, true)
		var pick: Button = ui._button(row, str(choice.get("label", "继续")), func(): ui._accept(ui.game.choose_event(index)))
		pick.name = "EventPick_%d" % index
		var cannot_pay: bool = int(ui.game.state.gold) + int(choice.get("gold", 0)) < 0 or int(ui.game.state.hp) + int(choice.get("hp", 0)) <= 0 or int(ui.game.state.max_hp) + int(choice.get("max_hp", 0)) <= 0
		var already_owned: bool = choice.has("relic") and ui.game.state.relics.has(str(choice.relic))
		pick.disabled = cannot_pay or already_owned
		if already_owned:
			pick.text += " · 已拥有此遗物"
		elif cannot_pay:
			pick.text += " · 无法支付代价"
	if not has_cards:
		ui._spacer(shell, true)

static func build_treasure(ui) -> void:
	var shell: VBoxContainer = ui._room_shell("遗落的馈赠", "旧箱中仍藏着希望", "以下物品已经加入行囊。", null)
	ui._spacer(shell, true)
	var relic: Dictionary = ui.game.relic_data(str(ui.game.state.get("boss_reward", "")))
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(center)
	var prize := VBoxContainer.new()
	prize.alignment = BoxContainer.ALIGNMENT_CENTER
	prize.add_theme_constant_override("separation", 12)
	center.add_child(prize)
	var opened: Label = ui._label(prize, ui._spaced("宝 箱 已 开"), 13, ui.GOLD)
	opened.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui._add_item_icon(prize, relic, "relic", 88.0)
	var coins: Label = ui._label(prize, "+25 金币", 30, ui.GOLD, true)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var relic_name: Label = ui._label(prize, str(relic.get("name", "遗留的祝福")), 42, ui.PAPER, true)
	relic_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := HBoxContainer.new()
	rule.alignment = BoxContainer.ALIGNMENT_CENTER
	rule.add_theme_constant_override("separation", 12)
	prize.add_child(rule)
	var left_rule: ColorRect = ui._room_rule(Color(0.46, 0.37, 0.23, 0.4))
	left_rule.custom_minimum_size.x = 120
	left_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.add_child(left_rule)
	ui._label(rule, "◆", 14, ui.GOLD)
	var right_rule: ColorRect = ui._room_rule(Color(0.46, 0.37, 0.23, 0.4))
	right_rule.custom_minimum_size.x = 120
	right_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.add_child(right_rule)
	var relic_text: Label = ui._paragraph(prize, str(relic.get("description", "")), 20, ui.PAPER)
	relic_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	relic_text.custom_minimum_size.x = 620
	ui._spacer(shell, true)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(controls)
	ui._wide_button(controls, "收好行囊，继续前行  →", func(): ui._accept(ui.game.leave_room()), 380)
