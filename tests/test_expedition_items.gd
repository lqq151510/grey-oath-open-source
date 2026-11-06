extends SceneTree
## Save isolation and explicit fixtures; optional captures from native Godot rendering.
const Rules = preload("res://core/game_engine.gd")
const Items = preload("res://core/item_mechanics.gd")
const ItemIcon = preload("res://ui/item_icon.gd")
const OUTPUT := "res://docs/evidence/spire-classes-20261104"
var capture := false
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func fixture(seed_value: int = 729):
	var g = Rules.new("")
	g.new_run("warden", seed_value)
	return g

func _test_item_icon_coverage(g) -> void:
	var count := 0
	for group in [["relic", g.data.relics], ["item", g.data.items], ["potion", g.data.potions]]:
		for definition in group[1]:
			var icon = ItemIcon.new()
			icon.setup(definition, str(group[0]), 48.0)
			check(icon.icon_id == str(definition.id), "icon maps to catalog entry " + str(definition.id))
			check(not str(icon.motif_name).is_empty() and icon.accent.a > 0.0, "icon has motif and palette " + str(definition.id))
			icon.free()
			count += 1
	check(count == 117, "all 62 relics, 40 journey items, and 15 potions have icons")

func enter(g, kind: String) -> Dictionary:
	var available: Array = g.available_nodes()
	if available.is_empty(): return {"ok":false}
	var lane: int = int(available[0])
	var node: Dictionary = g.state.map[int(g.state.row) + 1][lane]
	node.kind = kind
	if kind == "unknown": node.resolved_kind = "event"
	return g.enter_node(lane)

func play_attack(g, target: int = 0) -> void:
	g.state.hand = [{"id":"warden_01", "upgraded":false}]
	g.state.energy = 3
	g.play_card(0, target)

func clear_elite(g) -> void:
	for index in g.state.enemies.size():
		g.state.enemies[index].hp = 1
		g.state.enemies[index].block = 0
		play_attack(g, index)

func render(ui, file_name: String) -> void:
	for ignored in 4: await process_frame
	check(ui.body.size.x <= ui.size.x + 2 and ui.body.size.y <= ui.size.y + 2, "room stays within viewport: " + file_name)
	if not capture: return
	# Read the already-rendered frame after settling; a static window may not emit another redraw.
	var path := OUTPUT + "/" + file_name + ".png"
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, "capture " + file_name)
	screenshots.append(path)

func _test_permanent_offers() -> void:
	var found: Dictionary = {}
	for seed_value in range(500):
		var candidate = fixture(seed_value)
		enter(candidate, "unknown")
		if candidate.state.event.choices.size() < 3:
			continue
		var choice: Dictionary = candidate.state.event.choices[1]
		var id: String = str(choice.items[1])
		if candidate.item_data(id).kind != "permanent":
			continue
		found[id] = true
		var before: int = candidate.state.gold
		check(choice.description.contains("营地舍弃"), "permanent offer advertises the camp removal rule")
		check(choice.gold == 120 and candidate.choose_event(1).ok, "permanent offer grants displayed reward")
		check(candidate.state.gold == before + 120 and candidate.state.items.has(id), "permanent cost and reward acquired together")
		var effect: Dictionary = candidate.item_data(id).effects[0]
		check(candidate._relic_total(str(effect.op)) <= int(effect.value), "permanent effect affects calculations")
		for ignored in range(4): Items.complete_node(candidate)
		check(candidate.state.items.has(id), "permanent item does not expire")
		check(not candidate.discard_negative_item(id).ok and candidate.state.items.has(id), "permanent item cannot be discarded outside camp")
		enter(candidate, "rest")
		var path = "user://permanent-item-test-%d.json" % OS.get_process_id()
		candidate._save_path = path
		check(candidate.save_game(), "permanent item saves")
		var loaded = Rules.new(path)
		check(loaded.state.items.has(id), "permanent item survives reload")
		var hp: int = loaded.state.hp
		var held_count: int = loaded.state.items.size()
		check(loaded.discard_negative_item(id).ok and loaded.state.hp == hp - Items.CAMP_COST, "camp discards held permanent item for five current HP")
		check(not loaded.state.items.has(id) and loaded.state.items.size() == held_count - 1, "permanent discard grants no replacement")
		check(loaded.state.room == "map" and not loaded.rest().ok, "permanent discard uses the only camp action")
		var discarded = Rules.new(path)
		check(not discarded.state.items.has(id) and discarded.state.hp == hp - Items.CAMP_COST, "permanent discard persists through reload")
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
		if found.size() == 4: break
	check(found.size() == 4, "all four permanent items are obtainable via event offers")


func _test_permanent_camp_ui(ui) -> void:
	ui.game = fixture()
	enter(ui.game, "unknown")
	var choices: Array = ui.game.state.event.choices
	var old_description := "获得正面道具与120金币；负面效果持续本次冒险，无法净化或舍弃。"
	var old_offer := {"label":"接受永誓", "description":old_description, "items":["good_needle", "permanent_blade"], "gold":120}
	ui.game.state.event.choices = [choices[0], old_offer, choices.back()]
	ui._refresh()
	var event_row = ui.find_child("EventChoice_1", true, false)
	check(event_row != null and event_row.get_child(0).text == Items.PERMANENT_OFFER_DESCRIPTION, "old saved altar uses the current permanent offer description")
	ui.find_child("EventPick_1", true, false).pressed.emit()
	Items.gain(ui.game, "sacred_iron")
	enter(ui.game, "rest")
	ui.game.state.hp = 5
	ui._refresh()
	var before := JSON.stringify(ui.game.state)
	check(ui.find_child("CampDiscard", true, false).disabled and not ui.game.discard_negative_item("permanent_blade").ok and JSON.stringify(ui.game.state) == before, "permanent discard cannot spend the last five HP")
	ui.game.state.hp = 22
	ui._refresh()
	before = JSON.stringify(ui.game.state)
	check(not ui.game.discard_negative_item("good_needle").ok and not ui.game.discard_negative_item("sacred_iron").ok and JSON.stringify(ui.game.state) == before, "camp rejects held positive and sacred items without changing state")
	var discard = ui.find_child("CampDiscard", true, false)
	check(discard != null and not discard.disabled, "camp choice enables for a permanent negative item alone")
	discard.pressed.emit()
	var blade = ui.overlay.find_child("CampDrop_permanent_blade", true, false)
	check(blade != null and ui.overlay.find_child("CampDrop_good_needle", true, false) == null and ui.overlay.find_child("CampDrop_sacred_iron", true, false) == null, "camp lists permanent blade and omits positive and sacred items")
	if blade != null:
		blade.pressed.emit()
		check(ui.game.state.hp == 17 and ui.game.state.room == "map" and not ui.game.state.items.has("permanent_blade") and ui.overlay.get_child_count() == 0, "discarding permanent blade spends five HP and closes camp")
	ui._clear(ui.overlay)


func run() -> void:
	_test_permanent_offers()
	var g = fixture()
	check(g.data.items.size() == 40 and g.sacred_ids().size() == 4, "full item inventory and four unique sacred IDs")
	check(enter(g, "unknown").ok and g.state.event.id == "expedition_offer", "question-mark event offers an item at the altar")
	var good: String = str(g.state.event.choices[0].items[0])
	check(g.item_data(good).kind == "positive", "free gift option is always positive")
	check(g.choose_event(0).ok and g.state.items.has(good), "choose gift through event API")
	check(not g.choose_event(0).ok and g.state.items.size() == 1, "event cannot award same item twice")
	var trial
	for seed_value in range(50):
		var candidate = fixture(seed_value)
		enter(candidate, "unknown")
		if candidate.state.event.choices.size() == 3:
			trial = candidate
			break
	check(trial != null, "question mark can include an optional trial")
	if trial != null:
		var negative: String = str(trial.state.event.choices[1].items[1])
		var before: int = trial.state.gold
		check(trial.choose_event(1).ok and trial.state.items.has(negative) and trial.state.gold == before + (120 if trial.item_data(negative).kind == "permanent" else 30), "trial grants listed reward and negative item once")
		var definition: Dictionary = trial.item_data(negative)
		if definition.kind == "temporary":
			check(trial.state.items[negative].remaining == definition.duration, "acquisition node is not counted against duration")
	g = fixture()
	Items.gain(g, "burden_sore")
	Items.gain(g, "burden_tax")
	check(g._relic_total("start_strength") == -1 and g._relic_total("gold_bonus") == -6, "negative effects included in actual modifier calculation")
	enter(g, "shop")
	check(g.state.items.burden_sore.remaining == 2, "entering shop does not advance duration")
	check(g.leave_room().ok and g.state.items.burden_sore.remaining == 1, "leaving cleared node advances duration once")
	g._mark_node_cleared()
	check(g.state.items.burden_sore.remaining == 1, "same node cannot advance duration twice")
	enter(g, "rest")
	g.rest()
	check(not g.state.items.has("burden_sore") and g.state.items.burden_tax.remaining == 1, "expiring burden disappears on the correct node")
	enter(g, "rest")
	var turned: Dictionary = g.rest()
	check(not g.state.items.has("burden_tax") and g.state.items.has("good_coin") and turned.message.contains("转化"), "third node converts temporary burden into positive item")
	check(g._relic_total("gold_bonus") == 8 and g.profile.sacred_collection.is_empty(), "only the new item modifier remains; normal conversion is not sacred")

	g = fixture()
	Items.gain(g, "curse_iron")
	Items.gain(g, "burden_haze")
	enter(g, "rest")
	g.state.hp = 5
	var snapshot := JSON.stringify(g.state)
	check(not g.discard_negative_item("curse_iron").ok and JSON.stringify(g.state) == snapshot, "camp cannot spend the last five HP")
	g.state.hp = 27
	var max_hp: int = g.state.max_hp
	check(g.discard_negative_item("curse_iron").ok and g.state.hp == 22 and g.state.max_hp == max_hp, "camp removal spends exactly five current HP")
	check(not g.state.items.has("curse_iron") and g.state.items.has("burden_haze") and g.profile.sacred_collection.is_empty(), "camp removes one chosen item with no sacred reward")
	check(not g.rest().ok and not g.discard_negative_item("burden_haze").ok, "camp choices are mutually exclusive")
	enter(g, "rest")
	check(g.rest().ok and g.state.hp == g.state.max_hp, "camp heal restores full life")

	g = fixture()
	for id in ["curse_oath", "curse_veil", "curse_purse", "curse_iron"]:
		Items.gain(g, id)
	enter(g, "shop")
	g.state.gold = 1000
	var goods: Array = []
	for index in g.state.shop.size():
		if g.state.shop[index].kind == "item":
			goods.append(index)
			check(g.item_data(str(g.state.shop[index].id)).kind == "positive", "shop never stocks curses or sacred items")
	check(goods.size() == 3, "shop stocks three separate positive items")
	var remove_index: int = g.state.shop.size() - 1
	g.buy_item(remove_index)
	check(g.state.items.curse_purse.progress == 0, "selecting removal service is not actual spending")
	for index in goods:
		var paid: int = g.state.shop[index].price
		var before: int = g.state.gold
		check(g.buy_item(index).ok and g.state.gold == before - paid, "buy positive item with displayed price")
		check(not g.buy_item(index).ok and g.state.gold == before - paid, "sold item cannot charge a second time")
	check(g.state.items.has("sacred_purse") and not g.state.items.has("curse_purse"), "actual purchases purify purse")
	g.leave_room()
	for index in range(2):
		enter(g, "rest")
		check(g.rest(index).ok and g.state.deck[index].upgraded, "camp upgrades one card")
	check(g.state.items.has("sacred_iron"), "two camp upgrades purify whetstone")
	enter(g, "elite")
	g.state.enemies[0].hp = 10000
	for ignored in range(14): play_attack(g)
	check(g.state.items.curse_veil.progress == 14 and not g.state.items.has("sacred_veil"), "fourteen successful attacks leave curse incomplete")
	check(not g.play_card(0).ok and g.state.items.curse_veil.progress == 14, "rejected attack does not count")
	play_attack(g)
	check(g.state.items.has("sacred_veil") and not g.profile.achievements.has("sacred_complete"), "fifteenth attack purifies veil; three of four cannot grant achievement")
	clear_elite(g)
	check(g.state.items.curse_oath.progress == 1 and g.state.room == "reward", "elite win advances chain objective once")
	g._win_battle()
	check(g.state.items.curse_oath.progress == 1, "duplicate win does not advance objective")
	g.choose_reward(-1)
	enter(g, "elite")
	clear_elite(g)
	check(g.state.items.has("sacred_oath") and g.profile.sacred_collection.size() == 4 and g.profile.achievements.has("sacred_complete"), "all four sacred items unlock Long Night Reliquary")
	var path := "user://expedition-items-test-%d.json" % OS.get_process_id()
	Items.gain(g, "burden_haze")
	g._save_path = path
	check(g.save_game(), "items and permanent collection save")
	var reloaded = Rules.new(path)
	check(reloaded.state.items == g.state.items and reloaded.profile.sacred_collection == g.profile.sacred_collection, "inventory, duration and permanent collection survive reload")
	reloaded.abandon_run()
	check(reloaded.state.items.is_empty() and reloaded.profile.sacred_collection.size() == 4 and reloaded.profile.achievements.has("sacred_complete"), "next journey keeps achievement and collection without granting items")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

	root.title = "灰誓 · 道具与营地验收（测试存档）"
	root.size = Vector2i(1280,800)
	var ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.game = fixture()
	_test_item_icon_coverage(ui.game)
	ui.game.state.potions = ["potion_heal", "potion_poison"]
	ui.menu_open = false
	enter(ui.game, "shop")
	ui.game.state.gold = 1000
	ui._refresh()
	await render(ui, "shop")
	check(ui.find_child("ShopCards", true, false).get_child_count() == 4 and ui.find_child("ShopPositiveItems", true, false).get_child_count() == 4, "shop UI displays card and positive-item sections")
	check(ui.find_children("ItemIcon_*", "Control", true, false).size() >= 4, "shop products display individual item icons")
	check(ui.find_child("ItemIcon_potion_heal", true, false) != null and ui.find_child("ItemIcon_potion_poison", true, false) != null, "battle potion shortcuts display their individual icons")
	ui.find_child("ShopPositiveItemsJump", true, false).pressed.emit()
	await render(ui, "shop-positive")
	ui.game.leave_room()
	enter(ui.game, "unknown")
	ui._refresh()
	await render(ui, "altar")
	check(ui.find_children("ItemIcon_*", "Control", true, false).size() >= 1, "event offers display their item icons")
	ui.find_child("EventPick_0", true, false).pressed.emit()
	check(ui.game.state.items.size() == 1, "event button grants visible gift")
	Items.gain(ui.game, "burden_blunt")
	enter(ui.game, "rest")
	ui.game.state.hp = 22
	ui._refresh()
	await render(ui, "camp")
	var remove_button = ui.find_child("CampDiscard", true, false)
	check(remove_button != null and not remove_button.disabled, "camp third option enabled for payable negative item")
	remove_button.pressed.emit()
	await render(ui, "camp-discard")
	ui.find_child("CampDrop_burden_blunt", true, false).pressed.emit()
	check(ui.game.state.hp == 17 and ui.game.state.room == "map" and not ui.game.state.items.has("burden_blunt"), "camp button completes only the selected action")
	check(ui.overlay.get_child_count() == 0, "successful discard closes the camp overlay before the map is shown")
	_test_permanent_camp_ui(ui)
	ui.game = fixture()
	Items.gain(ui.game, "burden_blunt")
	Items.gain(ui.game, "curse_iron")
	Items.gain(ui.game, "burden_haze")
	ui.game.state.items.burden_blunt.remaining = 1
	enter(ui.game, "rest")
	ui._refresh()
	var needle_effect: String = ui.game.item_data("good_needle").description
	var iron_effect: String = ui.game.item_data("sacred_iron").description
	ui.find_child("ExpeditionInventory", true, false).pressed.emit()
	check(ui.overlay.find_children("ItemIcon_*", "Control", true, false).size() >= 3, "inventory displays each carried item's icon")
	var item_labels: Array[Node] = ui.overlay.find_children("*", "Label", true, false)
	check(item_labels.any(func(label): return label.text.contains("剩余 1 个节点") and label.text.contains("寻隙细针") and label.text.contains(needle_effect)), "inventory previews the timed burden's resulting effect")
	check(item_labels.any(func(label): return label.text.contains("净化任务") and label.text.contains("净火砥石") and label.text.contains(iron_effect)), "inventory previews the curse's sacred effect")
	check(item_labels.any(func(label): return label.text.contains("迷路烟雾") and label.text.contains("到期消失") and not label.text.contains("转化后效果")), "non-transforming burden shows only expiration")
	ui._clear(ui.overlay)
	ui.find_child("CampHeal", true, false).pressed.emit()
	check(ui.notice_label.mouse_filter != Control.MOUSE_FILTER_IGNORE and ui.notice_label.tooltip_text.contains("已转化为「寻隙细针」") and ui.notice_label.tooltip_text.contains(needle_effect), "conversion notice has a readable tooltip with the new item effect")
	ui.find_child("ExpeditionInventory", true, false).pressed.emit()
	item_labels = ui.overlay.find_children("*", "Label", true, false)
	check(item_labels.any(func(label): return label.text.begins_with("[正面] 寻隙细针") and label.text.contains(needle_effect)), "converted positive item shows its effect in inventory")
	check(not item_labels.any(func(label): return label.text.contains("蒙尘刃坠")), "converted burden is no longer listed in inventory")
	ui._clear(ui.overlay)
	ui.game.profile.sacred_collection = g.profile.sacred_collection.duplicate()
	ui._show_achievements()
	ui.find_child("SacredCollection", true, false).pressed.emit()
	await render(ui, "sacred-collection")
	ui._clear(ui.overlay)
	enter(ui.game, "normal")
	ui.game.state.status.weak = 2
	ui.game.state.enemies[0].status.vulnerable = 3
	ui.game.state.hand[0] = {"id":"warden_06", "upgraded":false}
	ui._refresh()
	await render(ui, "battle-status")
	var player_status = ui.find_child("PlayerStatus", true, false)
	var enemy_status = ui.find_child("EnemyStatus_0", true, false)
	check(player_status.text.contains("−25%") and player_status.tooltip_text.contains("剩余 2 回合"), "player Weak shows attack penalty and duration")
	check(enemy_status.text.contains("+50%") and enemy_status.tooltip_text.contains("剩余 3 回合"), "enemy Vulnerable shows damage received and duration")
	var group_card = ui.find_child("HandCard_0", true, false)
	check(group_card.get_node("CardVisual/Tags").text.contains("群攻") and group_card.tooltip_text.contains("无需选择目标"), "hand visibly marks group attack targeting")
	var old_target: int = ui.selected_target
	group_card.mouse_entered.emit()
	await render(ui, "battle-group")
	check(ui.find_child("HandTargetHint", true, false).text.contains("存活敌人") and ui.selected_target == old_target, "hover shows group size without changing the selected enemy")
	group_card.mouse_exited.emit()
	var before_help := JSON.stringify(ui.game.state)
	ui.find_child("CombatStatusHelp", true, false).pressed.emit()
	await render(ui, "status-help")
	check(ui.overlay.get_child_count() > 0 and JSON.stringify(ui.game.state) == before_help, "status help is accessible and does not advance combat")
	var terms: Dictionary = ui.KEYWORD_HELP
	var statuses: Dictionary = ui.STATUS_NAMES
	check(statuses.values().all(func(term): return terms.has(term)), "every displayed status has an in-game explanation")
	ui.find_child("CombatGlossary", true, false).pressed.emit()
	await render(ui, "combat-glossary")
	check(JSON.stringify(ui.game.state) == before_help, "full glossary is read-only during combat")
	ui.queue_free()
	for ignored in 4: await process_frame
	var report := {"checks":checks, "failures":failures, "captures":screenshots, "scope":"explicit item, shop, camp, quest and reload fixtures; UI button signals, not physical mouse"}
	var output := FileAccess.open(OUTPUT + ("/items-capture.json" if capture else "/items.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("EXPEDITION_ITEMS_RESULT=",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
