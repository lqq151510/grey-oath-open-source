extends SceneTree
## Balance probe: deterministic heuristic autoplay against the real rules engine.
## Memory-only save (""), no UI, no writes to the player's journey.
## Usage: Godot --headless --path . -s tests/balance_probe.gd -- --runs=8 --roles=warden,ranger

const Rules = preload("res://core/game_engine.gd")
const BuildGuides = preload("res://core/build_guides.gd")
const ROLES := ["warden", "ranger", "sister", "arcanist", "medium", "bellscribe", "ashlamper"]
const MAX_TURNS := 40

var rows: Array = []
var verbose := false
var policy := "greedy"
var rest_policy := "auto"
var battle_turns: Array = []
var battle_enemy_hp: Array = []
var battle_chapters: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _arg(name: String, fallback: String) -> String:
	for entry in OS.get_cmdline_user_args():
		if entry.begins_with("--" + name + "="):
			return entry.split("=", true, 1)[1]
	return fallback


func _run() -> void:
	var runs := int(_arg("runs", "8"))
	var roles := _arg("roles", ",".join(ROLES)).split(",")
	var seed_base := int(_arg("seed", "700"))
	verbose = _arg("verbose", "0") == "1"
	policy = _arg("policy", "greedy")
	rest_policy = _arg("rest", "auto")
	var started := Time.get_ticks_msec()
	for role in roles:
		for offset in range(runs):
			_play(role, seed_base + offset * 31)
	print("ELAPSED_MS=", Time.get_ticks_msec() - started)
	_resume()
	var file := FileAccess.open("res://docs/evidence/balance-20261104/probe.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"rows": rows}, "\t"))
	quit(0)


func _resume() -> void:
	var by_role := {}
	for row in rows:
		var role: String = row.role
		if not by_role.has(role):
			by_role[role] = {"runs": 0, "wins": 0, "deaths": 0, "chapter_sum": 0, "row_sum": 0, "turns_sum": 0, "hp_left": 0}
		var bucket: Dictionary = by_role[role]
		bucket.runs += 1
		bucket.wins += 1 if row.victory else 0
		bucket.deaths += 0 if row.victory else 1
		bucket.chapter_sum += row.chapter
		bucket.row_sum += row.row
		bucket.turns_sum += row.turns
		bucket.hp_left += row.hp
		bucket["min_hp"] = int(bucket.get("min_hp", 0)) + int(row.get("min_hp", row.hp))
		bucket["battles"] = float(bucket.get("battles", 0.0)) + float(row.get("battles", 0))
		bucket["tpb"] = float(bucket.get("tpb", 0.0)) + float(row.get("turns_per_battle", 0))
		bucket["ehp"] = float(bucket.get("ehp", 0.0)) + float(row.get("avg_enemy_hp", 0))
		bucket["tactics"] = int(bucket.get("tactics", 0)) + int(row.get("tactics", 0))
		var ct: Array = bucket.get("ct", [0.0, 0.0, 0.0, 0.0])
		var row_ct: Array = row.get("chapter_turns", [0, 0, 0, 0])
		if ct.size() == 4 and row_ct.size() == 4:
			for i in range(4):
				ct[i] = float(ct[i]) + float(row_ct[i])
		bucket["ct"] = ct
	for role in by_role:
		var b: Dictionary = by_role[role]
		print("%-10s runs=%d win=%d death=%d avg_chapter=%.2f avg_row=%.2f avg_turns=%.1f avg_hp=%.1f" % [
			role, b.runs, b.wins, b.deaths, float(b.chapter_sum) / b.runs, float(b.row_sum) / b.runs,
			float(b.turns_sum) / b.runs, float(b.hp_left) / b.runs]) 
		print("           per_chapter_turns=%.2f/%.2f/%.2f/%.2f" % (b.get("ct", [0,0,0,0]) if b.get("ct", []).size() == 4 else [0,0,0,0]))
		print("           avg_min_hp=%.1f battles=%.1f turns/battle=%.2f enemy_hp=%.1f tactics=%.1f" % [float(b.get("min_hp", 0)) / b.runs, float(b.get("battles", 0)) / b.runs, float(b.get("tpb", 0)) / b.runs, float(b.get("ehp", 0)) / b.runs, float(b.get("tactics", 0)) / b.runs])
	print("BALANCE_ROWS=", JSON.stringify(rows))


func _play(role_id: String, seed_value: int) -> void:
	var game = Rules.new("")
	var plan := ""
	var options := BuildGuides.options(role_id)
	if not options.is_empty():
		plan = str(options[0].id)
	var result = game.new_run(role_id, seed_value, 0, plan)
	if not result.get("ok", false):
		rows.append({"role": role_id, "seed": seed_value, "error": str(result.get("message", "new_run failed"))})
		return
	var node_count := 0
	var tactics_used := 0
	battle_turns = []
	battle_enemy_hp = []
	battle_chapters = []
	var min_hp := int(game.state.hp)
	var hp_by_chapter := [int(game.state.hp)]
	while bool(game.state.active) and node_count < 60:
		node_count += 1
		var lane := _pick_lane(game)
		if lane < 0:
			break
		var entered = game.enter_node(lane)
		if not entered.get("ok", false):
			break
		min_hp = mini(min_hp, int(game.state.hp))
		var room := str(game.state.room)
		if room == "battle":
			var ehp := 0
			for enemy in game.state.enemies:
				ehp += int(enemy.hp)
			battle_enemy_hp.append(ehp)
			battle_chapters.append(int(game.state.chapter))
			tactics_used += _fight(game)
		_resolve_room(game)
		min_hp = mini(min_hp, int(game.state.hp))
		if str(game.state.room) == "defeat" or str(game.state.room) == "victory":
			break
		if str(game.state.room) == "battle":
			# A room resolution can lead straight into combat (unknown node).
			tactics_used += _fight(game)
			_resolve_room(game)
	rows.append({
		"role": role_id, "seed": seed_value, "victory": str(game.state.room) == "victory",
		"chapter": int(game.state.chapter), "row": int(game.state.row), "turns": int(game.state.elapsed_turns),
		"hp": int(game.state.hp), "max_hp": int(game.state.max_hp), "nodes": node_count,
		"deck": int(game.state.deck.size()), "tactics": tactics_used, "relics": int(game.state.relics.size()),
		"min_hp": min_hp,
		"battles": battle_turns.size(),
		"chapter_turns": _chapter_turns(),
		"turns_per_battle": (float(battle_turns.reduce(func(a, b): return a + b, 0)) / maxf(1.0, battle_turns.size())),
		"avg_enemy_hp": (float(battle_enemy_hp.reduce(func(a, b): return a + b, 0)) / maxf(1.0, battle_enemy_hp.size())), "hp_by_chapter": [int(game.state.hp)],
	})


func _pick_lane(game) -> int:
	var lanes: Array = game.available_nodes()
	if lanes.is_empty():
		return -1
	var hp_ratio := float(game.state.hp) / maxf(1.0, float(game.state.max_hp))
	var kinds := {}
	for lane in lanes:
		var row := int(game.state.row) + 1
		if row >= 0 and row < game.state.map.size():
			kinds[lane] = str(game.state.map[row][lane].get("kind", "normal"))
	var preference := ["rest", "treasure", "shop", "normal", "unknown", "event", "fate", "elite", "boss"]
	if hp_ratio < 0.55:
		preference = ["rest", "shop", "treasure", "normal", "unknown", "elite", "boss"]
	for want in preference:
		for lane in lanes:
			if str(kinds.get(lane, "")) == want:
				if want == "elite" and hp_ratio < 0.72:
					continue
				return int(lane)
	return int(lanes[0])


func _resolve_room(game) -> void:
	for guard in range(6):
		var room := str(game.state.room)
		if room == "reward":
			_take_reward(game)
		elif room == "rest":
			_rest(game)
		elif room == "shop":
			_shop(game)
			game.leave_room()
		elif room == "event":
			_event(game)
		elif room == "treasure":
			game.leave_room()
		else:
			return


func _take_reward(game) -> void:
	var best := -1
	var best_score := 8.0
	for index in range(game.state.rewards.size()):
		var score := _card_score(game, game.state.rewards[index])
		if score > best_score:
			best_score = score
			best = index
	game.choose_reward(best)


func _card_score(game, instance: Dictionary) -> float:
	var card: Dictionary = game.card_view(instance)
	if card.is_empty():
		return 0.0
	var cost := maxf(1.0, float(card.get("cost", 1)))
	var score := 0.0
	for effect in card.get("effects", []):
		match str(effect.get("op", "")):
			"damage", "lifesteal", "block_damage", "resonant_damage":
				score += float(effect.get("value", 0)) * float(effect.get("hits", 1))
			"block", "resonant_block":
				score += float(effect.get("value", 0)) * 0.7
			"draw":
				score += float(effect.get("value", 1)) * 2.4
			"energy", "next_energy":
				score += 4.0
			"poison", "vulnerable", "weak":
				score += 3.0
			"strength", "focus", "resonance", "cinder", "stars", "doom":
				score += 3.0
			"channel":
				score += 3.0
			"forge", "shiv", "osty_summon", "soul_card":
				score += 3.5
			"heal":
				score += float(effect.get("value", 0)) * 0.6
	if str(card.get("type", "")) == "power":
		score += 6.0
	if card.get("exhaust", false):
		score -= 1.0
	return score / cost


func _rest(game) -> void:
	if rest_policy != "never" and float(game.state.hp) < float(game.state.max_hp) * 0.62:
		game.rest(-1)
		return
	var target := -1
	for index in range(game.state.deck.size()):
		if not bool(game.state.deck[index].get("upgraded", false)):
			if target < 0 or _card_score(game, game.state.deck[index]) > _card_score(game, game.state.deck[target]):
				target = index
			# stop after finding a decent one
			if _card_score(game, game.state.deck[index]) > 6.0:
				target = index
				break
	game.rest(target)


func _shop(game) -> void:
	for index in range(game.state.shop.size()):
		var item: Dictionary = game.state.shop[index]
		if bool(item.get("sold", false)):
			continue
		if str(item.kind) == "remove":
			continue
		if str(item.kind) == "card":
			if _card_score(game, {"id": item.id, "upgraded": false}) >= 7.0:
				game.buy_item(index)
		elif str(item.kind) == "relic" and int(game.state.gold) >= int(item.price) + 40:
			game.buy_item(index)


func _event(game) -> void:
	var choices: Array = game.state.event.get("choices", [])
	for index in range(choices.size()):
		if game.choose_event(index).get("ok", false):
			return
	game.state.room = "map"


func _incoming(game) -> int:
	var total := 0
	for enemy in game.state.enemies:
		if int(enemy.get("hp", 0)) <= 0:
			continue
		var text := str(enemy.get("intent", ""))
		if not "攻击" in text:
			continue
		for token in text.replace("攻击", " ").split(" ", false):
			if token.is_valid_int():
				total += int(token)
	return total


func _target(game) -> int:
	var best := -1
	var best_hp := 999999
	for index in range(game.state.enemies.size()):
		var enemy: Dictionary = game.state.enemies[index]
		if int(enemy.get("hp", 0)) <= 0:
			continue
		if int(enemy.hp) < best_hp:
			best_hp = int(enemy.hp)
			best = index
	return best


func _best_card(game) -> int:
	var target := _target(game)
	if policy == "random":
		var playable: Array = []
		for index in range(game.state.hand.size()):
			var rc: Dictionary = game.card_view(game.state.hand[index])
			if rc.is_empty() or int(rc.get("cost", 0)) > int(game.state.energy):
				continue
			if bool(rc.get("requires_target", false)) and target < 0:
				continue
			playable.append(index)
		return -1 if playable.is_empty() else int(playable[randi() % playable.size()])
	if policy == "basic":
		for index in range(game.state.hand.size()):
			var bc: Dictionary = game.card_view(game.state.hand[index])
			if not bc.is_empty() and int(bc.get("cost", 0)) <= int(game.state.energy):
				if bool(bc.get("requires_target", false)) and target < 0:
					continue
				return index
		return -1
	var incoming := _incoming(game)
	var block := int(game.state.block)
	var best := -1
	var best_score := 0.01
	for index in range(game.state.hand.size()):
		var card: Dictionary = game.card_view(game.state.hand[index])
		if card.is_empty():
			continue
		if int(card.get("cost", 0)) > int(game.state.energy):
			continue
		if int(card.get("star_cost", 0)) > int(game.state.get("stars", 0)):
			continue
		if int(card.get("soul_cost", 0)) > int(game.state.souls):
			continue
		if bool(card.get("requires_target", false)) and target < 0:
			continue
		var preview: Dictionary = game.preview_card(index, maxi(0, target))
		var score := float(preview.get("damage", 0)) * 1.0
		if incoming > block:
			score += float(preview.get("block", 0)) * 1.05
		else:
			score += float(preview.get("block", 0)) * 0.12
		for effect in card.get("effects", []):
			match str(effect.get("op", "")):
				"draw":
					score += float(effect.get("value", 1)) * 2.6
				"energy", "next_energy":
					score += 4.5
				"power":
					score += 3.0
				"vulnerable", "weak", "poison":
					score += 2.2
		if str(card.get("type", "")) == "power":
			score += 5.0
		if policy == "tactics":
			var last_type := str(game.state.get("tactical_last_type", ""))
			var card_type := str(card.get("type", ""))
			if not last_type.is_empty() and card_type in ["attack", "skill"] and card_type != last_type and int(game.state.get("tactical_gained", 0)) < 2:
				score += 9.0
		if int(preview.get("damage", 0)) >= int((game.state.enemies[target].get("hp", 0)) if target >= 0 else 0) + int((game.state.enemies[target].get("block", 0)) if target >= 0 else 0):
			score += 40.0
		if score > best_score:
			best_score = score
			best = index
	return best


func _use_tactic(game) -> bool:
	var view: Dictionary = game.tactics_view(maxi(0, _target(game)))
	if int(view.get("points", 0)) < 2 or bool(view.get("used", true)):
		return false
	var id := "strike"
	if _incoming(game) > int(game.state.block) + 4:
		id = "guard"
	for option in view.get("options", []):
		if str(option.get("id", "")) == id and bool(option.get("available", false)):
			return bool(game.use_tactic(id, maxi(0, _target(game))).get("ok", false))
	return false


func _chapter_turns() -> Array:
	var sums := [0.0, 0.0, 0.0, 0.0]
	var counts := [0, 0, 0, 0]
	for index in range(battle_turns.size()):
		var chapter := int(battle_chapters[index])
		sums[chapter] += float(battle_turns[index])
		counts[chapter] += 1
	var out := []
	for chapter in range(4):
		out.append(0.0 if counts[chapter] == 0 else sums[chapter] / counts[chapter])
	return out


func _fight(game) -> int:
	var tactics := 0
	var turns := 0
	for turn in range(MAX_TURNS):
		turns += 1
		if str(game.state.room) != "battle" or int(game.state.hp) <= 0:
			break
		if _use_tactic(game):
			tactics += 1
		for step in range(16):
			if str(game.state.room) != "battle":
				break
			if int(game.state.get("pending_discard", 0)) > 0:
				game.choose_discard(0)
				continue
			var index := _best_card(game)
			if index < 0:
				break
			if not game.play_card(index, maxi(0, _target(game))).get("ok", false):
				break
			if _use_tactic(game):
				tactics += 1
		if str(game.state.room) != "battle":
			break
		game.end_turn()
	battle_turns.append(turns)
	return tactics