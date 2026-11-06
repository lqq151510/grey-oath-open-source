extends SceneTree
## End-to-end presentation fixtures. No reads/writes of the player's normal save.
const OUTPUT := "res://docs/evidence/experience-20261104"
var ui
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var capture := false

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func settle() -> void:
	for frame in 4:
		await process_frame

func image_file(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + label + ".png"
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, "capture " + label)
	captures.append(path)

func key_escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	ui._unhandled_key_input(key)

func run() -> void:
	root.title = "灰誓 · 体验验收（内存存档）"
	for window in [Vector2i(1440, 900), Vector2i(1280, 800)]:
		root.size = window
		ui = load("res://tests/ui_shell.gd").new()
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(ui)
		await settle()
		check(ui.menu_page == "title" and ui.seed_input == null, "title separated from character selection")
		check(ui.game._save_path.is_empty(), "isolated user save")
		check(ui.background.texture.resource_path.ends_with("title_background.jpg"), "title illustration loaded")
		check(ui.content.size.y <= ui.size.y - 40, "title fits viewport")
		await image_file("title-%dx%d" % [window.x, window.y])
		var before := JSON.stringify(ui.game.profile)
		ui.find_child("CollectionButton", true, false).pressed.emit()
		await settle()
		check(ui.find_child("CollectionGrid", true, false).get_child_count() == 8, "collection paginated to eight cards")
		check(JSON.stringify(ui.game.profile) == before, "opening collection does not grant cards or achievements")
		ui.collection_owned = true
		ui._show_collection()
		await settle()
		check(ui.find_child("CollectionGrid", true, false).get_child_count() == 0, "empty owned filter")
		ui.collection_owned = false
		key_escape()
		check(ui.overlay.get_child_count() == 0 and ui.menu_open, "Escape closes modal before title")
		ui.find_child("NewJourneyButton", true, false).pressed.emit()
		await settle()
		check(ui.menu_page == "roles" and is_instance_valid(ui.seed_input), "new journey enters character screen")
		var role_buttons: Array = ui.content.find_children("*", "Button", true, false).filter(func(button): return button.text in ["已选择", "选择旅者"])
		check(role_buttons.size() == 7 and role_buttons.all(func(button): return not button.disabled), "seven selectable roles at zero wins")
		var begin := ui.find_child("BeginJourney", true, false) as Button
		check(begin != null and begin.get_global_rect().end.y <= ui.size.y - 20, "journey button fits below the role grid")
		await image_file("roles-%dx%d" % [window.x, window.y])
		var new_role := "bellscribe" if window.x == 1440 else "ashlamper"
		ui.find_child("PickRole_" + new_role, true, false).pressed.emit()
		await settle()
		check(ui.selected_role == new_role, "role card selects " + new_role)
		ui.seed_input.text = "729"
		ui.find_child("BeginJourney", true, false).pressed.emit()
		await settle()
		check(ui.game.state.active and not ui.menu_open, "new journey enters map")
		check(ui.game.state.role == new_role, "journey starts with " + new_role)
		check(ui.game.profile.achievements.has("first_oath"), "new journey achievement")
		ui._show_collection()
		await settle()
		var grid = ui.find_child("CollectionGrid", true, false)
		var collected: Array = grid.get_children().filter(func(button): return not button.disabled)
		check(collected.size() == 4, "four unique starter cards visible")
		await image_file("collection-%dx%d" % [window.x, window.y])
		before = JSON.stringify(ui.game.profile)
		collected[0].pressed.emit()
		await settle()
		check(JSON.stringify(ui.game.profile) == before, "card comparison does not mutate profile")
		await image_file("card-detail-%dx%d" % [window.x, window.y])
		ui._clear(ui.overlay)
		ui.collection_role = "neutral"
		ui._show_collection()
		await settle()
		check(ui.find_child("CollectionGrid", true, false).get_child_count() == 8, "neutral filter renders")
		ui.collection_query = "不存在的牌"
		ui._show_collection()
		await settle()
		check(ui.find_child("CollectionGrid", true, false).get_child_count() == 0, "search no-results")
		ui.collection_query = ""
		ui.collection_role = "all"
		ui._show_achievements()
		await settle()
		await image_file("achievements-%dx%d" % [window.x, window.y])
		ui._show_settings()
		await settle()
		await image_file("settings-%dx%d" % [window.x, window.y])
		ui._clear(ui.overlay)
		ui.game.update_setting("combat_speed", 2.0)
		ui.game.update_setting("reduced_motion", true)
		ui._enter_node(1)
		await settle()
		var deadline := Time.get_ticks_msec() + 5000
		while ui.combat_busy and Time.get_ticks_msec() < deadline:
			await process_frame
		check(not ui.combat_busy, "opening draw animation finishes")
		check(ui.combat_actors.player.animation_speed == 2.0 and ui.combat_actors.player.reduced_motion, "actor settings applied")
		ui._begin_shake(10)
		ui._pulse_impact(1, true)
		check(ui.shake_left == 0 and ui.impact_flash.color.a == 0, "reduced motion suppresses camera flash and shake")
		var played_before: int = ui.game.profile.stats.cards_played
		ui._play_card(0)
		var committed := JSON.stringify(ui.game.state)
		ui._play_card(0)
		check(JSON.stringify(ui.game.state) == committed, "animation rejects duplicate play")
		key_escape()
		await settle()
		check(JSON.stringify(ui.game.state) == committed and int(ui.game.profile.stats.cards_played) == played_before + 1, "skip animation cannot repeat committed action")
		await image_file("battle-%dx%d" % [window.x, window.y])
		ui.game.update_setting("music_volume", 0.0)
		ui._sync_audio()
		check(not ui.audio.music_player.playing and not ui.audio._music_spare.playing, "zero music volume silences both crossfade players")
		ui.game.update_setting("music_volume", 0.5)
		ui._sync_audio()
		await create_timer(0.9).timeout
		check(ui.audio.music_player.playing, "music resumes after unmute")
		ui.audio.play_music("explore")
		await create_timer(0.9).timeout
		check(ui.audio._current_music == "explore" and not ui.audio._music_spare.playing, "exploration crossfade retires previous track")
		ui.queue_free()
		await settle()
	var report := {"checks": checks, "failures": failures, "captures": captures, "mode": "native render and button-signal fixtures" if capture else "headless UI fixtures", "save": "memory only"}
	var file := FileAccess.open(OUTPUT + ("/ui-capture.json" if capture else "/ui-experience.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("EXPERIENCE_RESULT=", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
