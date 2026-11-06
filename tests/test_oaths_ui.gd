extends SceneTree

const UIShell = preload("res://tests/ui_shell.gd")

var ui
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func settle() -> void:
	for ignored in 6:
		await process_frame


func node(name_value: String) -> Node:
	return ui.find_child(name_value, true, false)


func press(name_value: String) -> void:
	var target = node(name_value)
	check(target is Button and not target.disabled, "button available: " + name_value)
	if target is Button and not target.disabled:
		target.pressed.emit()
	await settle()


func make_ui() -> void:
	root.size = Vector2i(1440, 900)
	var ui_script := load("res://tests/ui_shell.gd") as GDScript
	ui = ui_script.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.game.profile.settings.merge({"music": false, "sound": false}, true)
	ui._sync_audio()
	await settle()


func inside(control: Control) -> bool:
	return control != null and control.is_visible_in_tree() and Rect2(Vector2.ZERO, ui.size).encloses(control.get_global_rect())


func run() -> void:
	await test_title_menu()
	await test_daily_screen()
	await test_oath_draft()
	await test_begin_with_oath()
	await test_daily_conflict()
	await test_elite_and_ending()
	print("OATHS_UI checks=%d failures=%s" % [checks, str(failures)])
	quit(0 if failures.is_empty() else 1)


func test_title_menu() -> void:
	await make_ui()
	check(ui.menu_page == "title", "title menu opens first")
	var entry := node("DailyVowButton") as Button
	check(entry != null and entry.is_visible_in_tree(), "daily vow entry exists on the title menu")
	check(ui.content.size.y <= ui.size.y - 40, "title menu still fits the viewport with the daily entry")
	if entry != null:
		var box := entry.get_parent()
		var subtitle: Label = null
		for child in box.get_children():
			if child is Label and not str(child.text).strip_edges().is_empty():
				subtitle = child
		check(subtitle != null, "daily vow entry has a subtitle line")
		ui.queue_free()
	await settle()


func test_daily_screen() -> void:
	await make_ui()
	var entry := node("DailyVowButton") as Button
	check(entry != null, "daily vow entry exists")
	if entry == null:
		return
	entry.pressed.emit()
	await settle()
	check(ui.menu_page == "daily", "daily entry opens the daily page")
	var screen := node("DailyVowScreen") as Control
	check(inside(screen), "daily screen is laid out inside the canvas")
	check(screen != null and screen.find_child("DailyVowDetail", true, false) != null, "daily screen shows the oath and modifier detail")
	var status := node("DailyStatusText") as Label
	check(status != null and not status.text.strip_edges().is_empty(), "daily screen shows a status line")
	var view: Dictionary = ui.game.daily_view()
	check(not str(view.get("key", "")).is_empty(), "daily view exposes its date key")
	check(screen != null and not str(view.get("status", "")).is_empty(), "daily view carries a status message")
	var back := node("DailyBackButton") as Button
	check(inside(back), "daily back button is usable")
	if back != null:
		back.pressed.emit()
		await settle()
	check(ui.menu_page == "title", "daily back button returns to the title menu")
	await press("DailyVowButton")
	var start := node("StartDailyButton") as Button
	check(start != null and not start.disabled, "daily start button is enabled")
	check(start != null and inside(start), "daily start button is inside the canvas")
	if start != null and not start.disabled:
		start.pressed.emit()
		await settle()
	check(bool(ui.game.state.active) and bool(ui.game.state.daily), "start daily begins a daily run")
	check(not ui.menu_open, "daily run enters the map or battle")
	var daily_chip := node("DailyChip") as Label
	check(daily_chip != null and str(daily_chip.text).begins_with("每日 · "), "hud shows a daily chip")
	ui.menu_open = true
	ui.menu_page = "title"
	ui._refresh()
	await settle()
	await press("DailyVowButton")
	check(ui.menu_page == "daily", "daily page reopens on the title menu")
	var resume := node("StartDailyButton") as Button
	check(resume != null and resume.text.contains("继续今日誓约"), "daily start button offers to continue the run")
	ui.queue_free()
	await settle()


func test_oath_draft() -> void:
	await make_ui()
	await press("NewJourneyButton")
	check(ui.menu_page == "roles", "new journey opens the character screen")
	var draft := node("OathDraft")
	check(draft != null and draft.is_visible_in_tree(), "oath draft panel is inline on the character screen")
	check(ui.oath_draft_seed >= 0 and ui.oath_draft_seed <= 2147483647, "character screen drafts a seed once")
	var offers: Array = ui.game.oath_offers(int(ui.oath_draft_seed))
	check(offers.size() == 3, "draft seed produces three oath offers")
	for index in 3:
		var card := node("OathCard_%d" % index) as Button
		check(card != null and card.is_visible_in_tree(), "oath card %d is present" % index)
		check(card != null and not card.disabled, "oath card %d is selectable" % index)
		if card != null and index < offers.size():
			check(card.text.contains(str(offers[index].get("name", ""))), "oath card %d shows its name" % index)
			check(card.text.contains("恩惠") and card.text.contains("代价"), "oath card %d shows boon and price" % index)
	var first_id := str(offers[0].get("id", "")) if offers.size() > 0 else ""
	await press("OathCard_0")
	check(ui.selected_oath == first_id, "clicking an oath card selects that oath")
	var picked := node("OathCard_0") as Button
	check(picked != null and picked.text.contains("已立下此誓"), "selected oath card shows its selected state")
	var begin := node("BeginJourney") as Button
	check(begin != null and begin.text.contains(str(offers[0].get("name", ""))), "begin button reflects the selected oath")
	await press("OathCard_0")
	check(ui.selected_oath == "", "clicking the selected oath card again clears it")
	if offers.size() > 1:
		await press("OathCard_1")
		check(ui.selected_oath == str(offers[1].get("id", "")), "a different oath card can be selected")
	await press("SkipOathButton")
	check(ui.selected_oath == "", "skip oath clears the selection")
	ui.menu_page = "title"
	ui._refresh()
	await settle()
	check(ui.selected_oath == "", "leaving the character screen clears the oath selection")
	check(ui.oath_draft_active == false, "leaving the character screen retires the draft")
	ui.queue_free()
	await settle()


func test_begin_with_oath() -> void:
	await make_ui()
	await press("NewJourneyButton")
	var offers: Array = ui.game.oath_offers(int(ui.oath_draft_seed))
	check(offers.size() == 3, "draft seed still produces three oath offers")
	var chosen: Dictionary = offers[2] if offers.size() > 2 else {}
	var chosen_id := str(chosen.get("id", ""))
	var chosen_name := str(chosen.get("name", ""))
	await press("OathCard_2")
	check(ui.selected_oath == chosen_id, "third oath card selects the third oath")
	var draft_seed := int(ui.oath_draft_seed)
	var begin := node("BeginJourney") as Button
	check(begin != null and not begin.disabled, "begin journey is enabled before a run")
	if begin != null and not begin.disabled:
		begin.pressed.emit()
		await settle()
	check(bool(ui.game.state.active) and not ui.menu_open, "begin journey starts the run in one click")
	check(str(ui.game.state.get("oath", "")) == chosen_id, "run state carries the selected oath")
	check(int(ui.game.state.get("seed", -1)) == draft_seed, "a blank seed falls back to the oath draft seed")
	var chip := node("OathChip") as Label
	check(chip != null, "hud shows an oath chip once a vow is sworn")
	check(chip != null and str(chip.text) == chosen_name, "oath chip names the sworn oath")
	check(chip != null and str(chip.get_parent().tooltip_text).contains("恩惠"), "oath chip tooltip explains the oath")
	check(str(ui.game.current_oath().get("id", "")) == chosen_id, "engine reports the current oath")
	ui.queue_free()
	await settle()


func test_elite_and_ending() -> void:
	await make_ui()
	ui.game.new_run("ranger", 424242, 0)
	ui.game._start_battle("elite")
	ui.menu_open = false
	ui._refresh()
	await settle()
	var affix: Dictionary = ui.game.elite_affix_view()
	check(not affix.is_empty(), "elite fixture carries an affix")
	var banner := node("EliteAffixBanner") as Control
	check(inside(banner), "elite affix banner is laid out at the top of the battle")
	var arena := node("BattleArena") as Control
	check(banner != null and arena != null and banner.get_global_rect().end.y <= arena.get_global_rect().position.y + 1.0,
		"elite affix banner never covers the arena")
	var banner_text := ""
	if banner != null:
		for label in banner.find_children("*", "Label", true, false):
			banner_text += str(label.text) + " "
	check(banner_text.contains(str(affix.get("name", ""))), "elite affix banner names the affix")
	check(banner_text.contains(str(affix.get("description", ""))), "elite affix banner explains the affix")
	ui.game.state.room = "victory"
	ui.game.state.score = 777
	ui.game.state.daily = true
	ui.game.state.daily_key = str(ui.game.daily_view().key)
	ui._refresh()
	await settle()
	var frame := node("EndingFrame")
	check(frame != null, "ending screen is built")
	var labels: Array[String] = []
	if frame != null:
		for label in frame.find_children("*", "Label", true, false):
			labels.append(str(label.text))
	check(labels.has("得 分"), "ending stats include a score chip")
	check(labels.has("777"), "ending score chip shows the run score")
	var summary := node("DailyEndingSummary") as Label
	check(summary != null and summary.text.begins_with("今日最佳"), "daily runs append the daily record line to the ending")
	var score_value := node("ScoreValue") as Label
	check(score_value != null and score_value.text == "777", "score chip exposes the run score as a named node")
	ui.queue_free()
	await settle()


func test_daily_conflict() -> void:
	await make_ui()
	ui.game.new_run("ranger", 31337, 0)
	ui.menu_open = true
	ui.menu_page = "title"
	ui._refresh()
	await settle()
	await press("DailyVowButton")
	var start := node("StartDailyButton") as Button
	check(start != null and not start.disabled, "daily start stays clickable with a run in progress")
	if start != null and not start.disabled:
		start.pressed.emit()
		await settle()
	check(ui.menu_page == "daily", "a rejected daily start keeps the daily page open")
	var failure := node("DailyError") as Label
	check(failure != null and not failure.text.strip_edges().is_empty(), "a rejected daily start shows the engine message inline")
	check(not bool(ui.game.state.daily), "a rejected daily start leaves the current run untouched")
	ui.queue_free()
	await settle()
