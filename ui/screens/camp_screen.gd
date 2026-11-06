extends RefCounted

const ExpeditionItems = preload("res://core/item_mechanics.gd")

static func build_shop(ui) -> void:
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 16)
	ui._label(wallet, "◈ %d" % int(ui.game.state.gold), 18, ui.GOLD)
	ui._label(wallet, "第 %d 层" % (int(ui.game.state.row) + 1), 15, ui.MUTED)
	var shell: VBoxContainer = ui._room_shell("路边行商", "以余财换取生机", "卡牌与正面道具分区陈列，离开后无法返回当前行商。", wallet)
	var shortcuts := HBoxContainer.new()
	shortcuts.add_theme_constant_override("separation", 10)
	shell.add_child(shortcuts)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 14)
	scroll.add_child(sections)
	for section in [["卡牌", "ShopCards", ["card"]], ["正面道具", "ShopPositiveItems", ["item", "relic"]], ["补给与服务", "ShopSupplies", ["potion", "remove"]]]:
		var heading_row := HBoxContainer.new()
		heading_row.add_theme_constant_override("separation", 12)
		sections.add_child(heading_row)
		var heading: Label = ui._label(heading_row, str(section[0]), 24, ui.GOLD, true)
		ui._spacer(heading_row, false)
		var heading_rule: ColorRect = ui._room_rule(Color(0.46, 0.37, 0.23, 0.28))
		heading_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		heading_row.add_child(heading_rule)
		var jump: Button = ui._button(shortcuts, str(section[0]), func(): scroll.scroll_vertical = roundi(heading.position.y))
		jump.name = str(section[1]) + "Jump"
		jump.custom_minimum_size = Vector2(112, 34)
		jump.add_theme_stylebox_override("normal", ui._sts_box(Color(0.10, 0.088, 0.070, 0.92), Color(0.44, 0.36, 0.23, 0.8), 1))
		jump.add_theme_stylebox_override("hover", ui._sts_box(Color(0.17, 0.14, 0.105, 0.98), ui.GOLD, 1))
		jump.add_theme_color_override("font_color", ui.GOLD)
		jump.add_theme_color_override("font_hover_color", ui.PAPER)
		var grid := GridContainer.new()
		grid.name = str(section[1])
		grid.columns = 4 if grid.name == "ShopCards" else 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 10)
		sections.add_child(grid)
		for index in range(ui.game.state.shop.size()):
			if ui.game.state.shop[index].kind in section[2]:
				_shop_product(ui, grid, index)
		if grid.get_child_count() == 0:
			ui._label(grid, "本次没有可售商品。", 16, ui.MUTED)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(controls)
	ui._wide_button(controls, "离开行商  →", func(): ui._accept(ui.game.leave_room()))

static func build_rest(ui) -> void:
	var fire = ui._new_campfire_art()
	fire.name = "CampfireArt"
	var shell: VBoxContainer = ui._room_shell("短暂的暖意", "营火仍在燃烧", "歇息、淬炼、舍弃，三选一。做出选择后继续旅程。", fire)
	ui._spacer(shell, true)
	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 20)
	shell.add_child(choices)
	var heal := _camp_choice(ui, choices, "歇息", "将当前生命恢复至上限。\n当前生命 %d / %d" % [ui.game.state.hp, ui.game.state.max_hp])
	ui._button(heal, "回满生命", func(): ui._accept(ui.game.rest(-1)), true).name = "CampHeal"
	var upgrade := _camp_choice(ui, choices, "淬炼", "永久强化牌组中的一张卡牌。\n已强化的卡牌不可再次升级。")
	ui._button(upgrade, "选择要强化的卡牌", ui._show_deck.bind("upgrade"))
	var cleanse := _camp_choice(ui, choices, "舍弃", "支付 %d 点当前生命，舍弃一件限时负面道具、诅咒或永久负面道具。被舍弃的道具不会转化。" % ExpeditionItems.CAMP_COST)
	var negatives := _negative_item_ids(ui)
	var drop: Button = ui._button(cleanse, "选择负面道具", func() -> void: _show_camp_discard(ui))
	drop.name = "CampDiscard"
	if negatives.is_empty():
		drop.disabled = true
		drop.text = "没有随行负面道具"
	elif int(ui.game.state.hp) <= ExpeditionItems.CAMP_COST:
		drop.disabled = true
		drop.text = "生命不足以支付"
	ui._spacer(shell, true)

static func _shop_product(ui, parent: Control, index: int) -> void:
	var item: Dictionary = ui.game.state.shop[index]
	var definition: Dictionary = {}
	match str(item.kind):
		"item": definition = ui.game.item_data(str(item.id))
		"relic": definition = ui.game.relic_data(str(item.id))
		"potion": definition = ui.game.potion_data(str(item.id))
		"remove": definition = {"name":"遗忘一张卡牌", "description":"选定卡牌后才扣款，牌组至少保留五张。"}
	var box: VBoxContainer = ui._panel(parent)
	box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var can_buy := not bool(item.sold) and int(ui.game.state.gold) >= int(item.price)
	var price_label := "购买 · %d 金币" % int(item.price)
	if item.kind == "card":
		var instance := {"id": str(item.id), "upgraded": false}
		var inspect := func():
			var card: Dictionary = ui.game.card_view(instance)
			ui._confirm(str(card.get("name", "卡牌")), ui._wrap_tooltip(str(card.get("description", ""))), func(): pass, "知道了")
		var preview: Button = ui._card(box, instance, inspect, Vector2(218, 270))
		preview.name = "ShopCard_%d" % index
		if not can_buy:
			price_label = "金币不足 · 需 %d 金币" % int(item.price)
	else:
		box.get_parent().custom_minimum_size = Vector2(290, 168)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		box.add_child(header)
		if item.kind != "remove":
			ui._add_item_icon(header, definition, str(item.kind), 52.0)
		var product_copy := VBoxContainer.new()
		product_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(product_copy)
		ui._label(product_copy, str(definition.get("name", "商品")), 21, ui.PAPER, true)
		ui._paragraph(box, str(definition.get("description", "")), 17)
	ui._spacer(box, true)
	var buy: Button = ui._button(box, "已售出" if item.sold else price_label, func() -> void: _buy(ui, index))
	buy.name = "ShopBuy_%d" % index
	buy.disabled = not can_buy

static func _buy(ui, index: int) -> void:
	var result: Dictionary = ui.game.buy_item(index)
	ui._accept(result)
	if result.get("ok", false) and ui.game.state.shop[index].kind == "remove":
		ui._show_deck("remove")

static func _camp_choice(ui, parent: Node, title_text: String, body_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(336, 268)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ui._sts_box(Color(0.072, 0.063, 0.050, 0.94), Color(0.46, 0.37, 0.23, 0.6), 1))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	ui._label(box, ui._spaced(title_text), 13, ui.GOLD)
	ui._label(box, title_text, 34, ui.PAPER, true)
	ui._paragraph(box, body_text, 17)
	ui._spacer(box, true)
	return box

static func _negative_item_ids(ui) -> Array:
	return ui.game.state.items.keys().filter(func(id): return ExpeditionItems.is_negative(ui.game.item_data(str(id))))

static func _show_camp_discard(ui) -> void:
	var box: VBoxContainer = ui._modal("舍弃负面道具", "选择后失去 %d 点当前生命，并离开本处营地。" % ExpeditionItems.CAMP_COST)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id in _negative_item_ids(ui):
		var item_id := str(id)
		var item: Dictionary = ui.game.item_data(item_id)
		var row: VBoxContainer = ui._panel(list)
		var detail_row := HBoxContainer.new()
		detail_row.add_theme_constant_override("separation", 10)
		row.add_child(detail_row)
		ui._add_item_icon(detail_row, item, "item", 40.0)
		ui._paragraph(detail_row, ui._expedition_item_detail(item_id), 18)
		ui._button(row, "舍弃「%s」 · 失去 %d 生命" % [item.name, ExpeditionItems.CAMP_COST], func() -> void: _discard_camp_item(ui, item_id)).name = "CampDrop_" + item_id

static func _discard_camp_item(ui, id: String) -> void:
	var result: Dictionary = ui.game.discard_negative_item(id)
	if result.get("ok", false):
		ui._clear(ui.overlay)
	ui._accept(result)
