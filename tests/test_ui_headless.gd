extends SceneTree

func _initialize() -> void:
	print("Starting UI Headless Test...")
	var root = preload("res://tests/ui_shell.gd").new()
	get_root().add_child(root)
	
	await process_frame
	
	print("UI instantiated successfully!")
	print("Menu open: ", root.menu_open)
	print("Game active: ", root.game.state.active)
	
	# Start run
	if root.menu_open:
		root._begin_run()
		await process_frame
		print("Run started: active=", root.game.state.active, " room=", root.game.state.room)
		
	# Enter map node
	if root.game.state.room == "map":
		var available = root.game.available_nodes()
		print("Available nodes: ", available)
		if not available.is_empty():
			root._enter_node(available[0])
			await process_frame
			print("Entered node: room=", root.game.state.room)
			
	# Battle round
	if root.game.state.room == "battle":
		print("Battle enemies: ", root.game.state.enemies.size())
		print("Player hand: ", root.game.state.hand.size())
		print("Player energy: ", root.game.state.energy)
		
		# Play first playable card
		for i in range(root.game.state.hand.size()):
			var view = root.game.card_view(root.game.state.hand[i])
			if view.cost <= root.game.state.energy:
				print("Playing card ", i, ": ", view.name)
				root._play_card(i)
				await process_frame
				break
				
		print("Energy after play: ", root.game.state.energy)
		print("Ending turn...")
		root._accept(root.game.end_turn())
		await process_frame
		print("Turn ended successfully, turn=", root.game.state.turn)
		
	print("ALL UI HEADLESS TESTS PASSED!")
	root.queue_free()
	quit(0)
