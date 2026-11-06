extends RefCounted


static func build(ui) -> void:
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 16)
	ui._label(wallet, "◈ %d" % int(ui.game.state.gold), 18, ui.GOLD)
	ui._label(wallet, "第 %d 层" % (int(ui.game.state.row) + 1), 15, ui.MUTED)
	var shell: VBoxContainer = ui._room_shell("余烬未熄", "将新的力量带入长夜", "选一张卡加入牌组，也可以跳过。每张候选卡都能免费换一次；金币和遗物已经结算。", wallet)
	ui._build_plan_picker(shell, str(ui.game.state.role), str(ui.game.state.get("build_plan", "")), func(id: String): ui._accept(ui.game.set_build_plan(id)))
	var scroll := ScrollContainer.new()
	scroll.name = "RewardScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var cards := HBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 24)
	scroll.add_child(cards)
	var recommendations: Array = []
	var best_score := -1
	var best_index := -1
	for instance in ui.game.state.rewards:
		var entry: Dictionary = ui.game.build_recommendation(instance)
		recommendations.append(entry)
		if int(entry.score) > best_score:
			best_score = int(entry.score)
			best_index = recommendations.size() - 1
	for index in range(ui.game.state.rewards.size()):
		var column := VBoxContainer.new()
		column.name = "RewardColumn_%d" % index
		column.custom_minimum_size.x = 272
		column.add_theme_constant_override("separation", 4)
		cards.add_child(column)
		var entry: Dictionary = recommendations[index]
		var preferred := index == best_index and best_score > 0
		var preferred_text := "优先推荐 · 核心牌" if entry.tier == "core" else "可以考虑 · 辅助牌"
		var badge: Label = ui._label(column, preferred_text if preferred else str(entry.label), 14, ui.GOLD if entry.tier == "core" else ui.GREEN if entry.tier == "support" else ui.MUTED)
		badge.name = "RewardRecommendation_%d" % index
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var frame := PanelContainer.new()
		frame.name = "RewardCardFrame_%d" % index
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var outline: StyleBoxFlat = ui._sts_box(Color.TRANSPARENT, Color.TRANSPARENT, 0)
		if entry.tier == "core":
			outline = ui._sts_box(Color(0.78, 0.65, 0.42, 0.14), ui.GOLD, 3, true)
		frame.add_theme_stylebox_override("panel", outline)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 6)
		pad.add_theme_constant_override("margin_right", 6)
		pad.add_theme_constant_override("margin_top", 6)
		pad.add_theme_constant_override("margin_bottom", 6)
		frame.add_child(pad)
		var pick: Button = ui._card(pad, ui.game.state.rewards[index], func(): ui._accept(ui.game.choose_reward(index)), Vector2(246, 276), "reward")
		pick.name = "RewardCard_%d" % index
		pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(frame)
		var reason: Label = ui._paragraph(column, str(entry.reason), 15, ui.PAPER)
		reason.name = "RewardReason_%d" % index
		reason.custom_minimum_size = Vector2(272, 44)
		reason.max_lines_visible = 2
		reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		reason.tooltip_text = str(entry.reason)
		if not str(ui.game.state.get("build_plan", "")).is_empty():
			reason.tooltip_text += "\n牌组里已有%d张适合这个方向的牌；这张卡已有%d张。" % [int(entry.core_count), int(entry.owned)]
		var refresh: Dictionary = ui.game.reward_reroll_view(index)
		var refresh_text := "已换过" if refresh.used else "换掉这张 · 免费一次"
		if not refresh.available and not refresh.used:
			refresh_text = "暂无可替换卡牌"
		var reroll: Button = ui._button(column, refresh_text, func(): ui._accept(ui.game.reroll_reward(index)))
		reroll.name = "RewardReroll_%d" % index
		reroll.custom_minimum_size.y = 34
		reroll.add_theme_stylebox_override("normal", ui._sts_box(Color(0.10, 0.088, 0.070, 0.92), Color(0.42, 0.34, 0.22, 0.75), 1))
		reroll.add_theme_stylebox_override("hover", ui._sts_box(Color(0.16, 0.13, 0.095, 0.98), ui.GOLD, 1))
		reroll.disabled = not refresh.available
		reroll.tooltip_text = str(refresh.reason) if not refresh.available else "只换这张卡；本次奖励中出现过的卡不会重复。"
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(controls)
	ui._wide_button(controls, "跳过卡牌，继续前行  →", func(): ui._accept(ui.game.choose_reward(-1))).name = "SkipCardReward"
