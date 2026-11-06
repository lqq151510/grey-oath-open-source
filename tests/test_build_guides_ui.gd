extends SceneTree

const UIShell = preload("res://tests/ui_shell.gd")
const Rules = preload("res://core/game_engine.gd")
const OUTPUT = "res://docs/evidence/build-guides-20261104"
var ui
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func settle() -> void:
	for ignored in 5:
		await process_frame


func node(name_value: String):
	return ui.find_child(name_value, true, false)


func visible(control: Control, label: String) -> void:
	check(control != null and control.is_visible_in_tree(), label + " is visible")
	if control == null:
		return
	var rect := control.get_global_rect()
	check(Rect2(Vector2.ZERO, ui.size).encloses(rect), label + " stays inside the canvas")
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			check(ancestor.get_global_rect().encloses(rect), label + " is not clipped by scrolling")
		ancestor = ancestor.get_parent()


func press(name_value: String) -> void:
	var target = node(name_value)
	check(target is Button and not target.disabled, "button available: " + name_value)
	if target is Button and not target.disabled:
		target.pressed.emit()
	await settle()


func select_plan(id: String) -> void:
	var select = node("BuildPlanSelect") as OptionButton
	check(select != null, "build picker exists")
	if select == null:
		return
	for index in select.item_count:
		if str(select.get_item_metadata(index)) == id:
			select.select(index)
			select.item_selected.emit(index)
			await settle()
			return
	check(false, "requested build exists: " + id)


func reward_fixture(role: String = "ranger", plan: String = "poison") -> void:
	ui._clear(ui.overlay)
	ui.game = Rules.new("")
	ui.game.new_run(role, 47190, 0, plan)
	ui.game.profile.settings.music = false
	ui.game.profile.settings.sound = false
	ui.game.enter_node(1)
	ui.game._win_battle()
	if role == "ranger":
		ui.game.state.rewards = [{"id": "ranger_05", "upgraded": false}, {"id": "ranger_06", "upgraded": false}, {"id": "ranger_13", "upgraded": false}]
		ui.game.state.reward_seen = []
		ui.game._migrate_reward_guidance()
	ui.menu_open = false
	ui.notice = ""
	ui.save_warning = ""
	ui._refresh()


func capture(label: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "native screenshot saved: " + label)
	screenshots.append(path)


func test_presets() -> void:
	ui.game = Rules.new("")
	ui.game.profile.settings.music = false
	ui.game.profile.settings.sound = false
	ui.menu_open = true
	ui.menu_page = "roles"
	ui.selected_role = "ranger"
	ui.selected_build_plan = "blade"
	ui._refresh()
	await settle()
	check(ui.selected_build_plan == "", "returning from another traveler clears an incompatible preset")
	check(node("BuildPlanSelect").get_item_metadata(0) == "", "free choice appears before every preset")
	check(not node("BeginJourney").disabled, "starting does not require a preset")
	await select_plan("poison")
	node("JourneySeed").text = "47190"
	await press("BeginJourney")
	check(ui.game.state.active and ui.game.state.build_plan == "poison" and ui.game.state.seed == 47190, "pre-play preset survives the actual start button")


func test_actions() -> void:
	reward_fixture()
	await settle()
	check(node("RewardRecommendation_1").text.contains("核心"), "poison card is recommended")
	check(node("RewardCardFrame_1").get_theme_stylebox("panel").border_color.a > 0.0, "matching card has a visible gold outline")
	check(node("RewardCardFrame_0").get_theme_stylebox("panel").border_color.a == 0.0, "unmatched card does not falsely glow")
	for slot in 3:
		check(not node("RewardCard_%d" % slot).disabled, "every offered card remains selectable")
	var offers: Array = ui.game.state.rewards.duplicate(true)
	await select_plan("shiv")
	check(ui.game.state.rewards == offers and node("RewardRecommendation_0").text.contains("核心"), "changing preference updates highlight without changing offers")
	await select_plan("")
	check(node("BuildPlanDescription") != null and node("BuildPlanDescription").text.contains("自动标出"), "free build explains its inferred recommendation direction")
	var has_auto_outline := false
	for slot in 3:
		has_auto_outline = has_auto_outline or node("RewardCardFrame_%d" % slot).get_theme_stylebox("panel").border_color.a > 0.0
	check(has_auto_outline, "free build still highlights the best deck-synergy reward")
	await select_plan("poison")
	await press("RewardReroll_1")
	check(ui.game.state.rewards[0] == offers[0] and ui.game.state.rewards[2] == offers[2] and ui.game.state.rewards[1] != offers[1], "refresh button replaces only its own card")
	check(node("RewardReroll_1").disabled and not node("RewardReroll_0").disabled and not node("RewardReroll_2").disabled, "only refreshed position is disabled")
	await select_plan("shiv")
	check(node("RewardReroll_1").disabled, "changing build does not renew a used refresh button")
	await press("RewardReroll_0")
	await press("RewardReroll_2")
	check(ui.game.state.reward_rerolls_used == [true, true, true], "all three button actions consume exactly one allowance each")
	var count: int = ui.game.state.deck.size()
	var selected_id := str(ui.game.state.rewards[2].id)
	await press("RewardCard_2")
	check(ui.game.state.room == "map" and ui.game.state.deck.size() == count + 1 and ui.game.state.deck.back().id == selected_id, "refreshed card is actually added through UI")
	reward_fixture()
	await settle()
	await press("RewardCard_0")
	check(ui.game.state.deck.back().id == "ranger_05", "nonrecommended small knife card can be chosen under poison preset")
	reward_fixture()
	await settle()
	count = ui.game.state.deck.size()
	await press("SkipCardReward")
	check(ui.game.state.room == "map" and ui.game.state.deck.size() == count, "skip remains available with a preset")


func test_layouts(make_captures: bool) -> void:
	for dimensions in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		await settle()
		var roles: Array = ui.game.data.roles.duplicate(true)
		for role in roles:
			ui.game = Rules.new("")
			ui.game.profile.settings.music = false
			ui.game.profile.settings.sound = false
			ui.menu_open = true
			ui.menu_page = "roles"
			ui.selected_role = str(role.id)
			ui.selected_build_plan = str(ui.game.build_plan_options(str(role.id))[1].id)
			ui._refresh()
			await settle()
			visible(node("BuildPlanSelect"), "preset picker " + str(role.id))
			visible(node("BeginJourney"), "start button " + str(role.id))
			if make_captures and role.id == "ranger":
				await capture("preset-%dx%d" % [dimensions.x, dimensions.y])
			for plan in ui.game.build_plan_options(str(role.id)):
				reward_fixture(str(role.id), str(plan.id))
				await settle()
				visible(node("BuildPlanSelect"), "reward picker")
				visible(node("SkipCardReward"), "skip button")
				for slot in ui.game.state.rewards.size():
					visible(node("RewardCard_%d" % slot), "reward card")
					visible(node("RewardReroll_%d" % slot), "refresh button")
					visible(node("RewardReason_%d" % slot), "recommendation reason")
				if make_captures and role.id == "ranger" and plan.id == "poison":
					await capture("reward-poison-%dx%d" % [dimensions.x, dimensions.y])
					await press("RewardReroll_1")
					await capture("reward-refreshed-%dx%d" % [dimensions.x, dimensions.y])


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.title = "灰誓 · 流派推荐与奖励刷新验收（不写正式存档）"
	ui = UIShell.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await settle()
	var native := "--capture" in OS.get_cmdline_user_args()
	await test_presets()
	await test_actions()
	await test_layouts(native)
	var report := {"checks": checks, "failures": failures, "screenshots": screenshots, "mode": "native render with scripted UI actions" if native else "headless scripted UI actions", "player_save_used": false, "physical_mouse_verified": false}
	var file := FileAccess.open(OUTPUT + ("/ui-capture.json" if native else "/ui-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BUILD_GUIDES_UI checks=", checks, " failures=", failures.size())
	ui.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
