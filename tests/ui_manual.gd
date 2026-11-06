extends SceneTree
## Manual input verification sandbox; never writes the player's normal save.

func _initialize() -> void:
	call_deferred("open_game")

func open_game() -> void:
	root.title = "灰誓 · 鼠标验收沙盒"
	var ui = load("res://main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.game = load("res://core/game_engine.gd").new("")
	ui.menu_open = true
	ui.save_warning = ""
	ui._refresh()
