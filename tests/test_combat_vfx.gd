extends SceneTree
## 战斗特效层与事件接线回归：不写存档，不依赖键鼠输入。
## 覆盖分类查表、新 API 入队、绘制路径、生命周期，以及出牌/药剂到特效的映射。

const Rules = preload("res://core/game_engine.gd")
const CombatEffects = preload("res://ui/combat_effects.gd")

var checks := 0
var failures: Array[String] = []
var ui


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)


func _settle() -> void:
	for ignored in 4:
		await process_frame


func _types(fx: Control) -> Array:
	var result: Array = []
	for effect in fx.effects:
		result.append(str(effect["type"]))
	return result


func _last(fx: Control, kind: String) -> Dictionary:
	for index in range(fx.effects.size() - 1, -1, -1):
		if str(fx.effects[index]["type"]) == kind:
			return fx.effects[index]
	return {}


func _wait_until(condition: Callable, timeout_msec: int = 2000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _enemy(definition: Dictionary) -> Dictionary:
	return {"id": definition.id, "name": definition.name, "hp": 80, "max_hp": 80, "block": 0,
		"status": {}, "pattern": [{"intent": "等待", "effects": []}],
		"turn": 0, "intent": "等待", "color": definition.color}


func _fixture() -> void:
	ui.game = Rules.new("")
	ui.game.new_run("warden", 42)
	ui.game.enter_node(1)
	ui.game.state.enemies = [_enemy(ui.game.data.enemies[0])]
	ui.game.state.hand = [{"id": "warden_01", "upgraded": false}, {"id": "neutral_03", "upgraded": false}]
	ui.game.state.energy = 5
	ui.game.state.potions = []
	ui.game.state.hp = maxi(1, int(ui.game.state.max_hp) - 20)
	ui.menu_open = false
	ui.selected_target = 0
	ui.save_warning = ""
	ui._refresh()
	await _settle()


func _run() -> void:
	await _test_lookup()
	await _test_layer_api()
	await _test_draw_paths()
	await _test_wiring()
	var report := {"checks": checks, "failures": failures, "mode": "headless script-driven VFX fixtures"}
	print("COMBAT_VFX_RESULT " + JSON.stringify(report))
	if ui != null:
		ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)


func _test_lookup() -> void:
	_check(CombatEffects.category_for("strength") == "buff", "strength is a buff")
	_check(CombatEffects.category_for("regen") == "buff", "regen is a buff")
	_check(CombatEffects.category_for("weak") == "debuff", "weak is a debuff")
	_check(CombatEffects.category_for("vulnerable") == "debuff" and CombatEffects.category_for("sunder") == "debuff", "vulnerable and sunder are debuffs")
	_check(CombatEffects.category_for("energy") == "resource" and CombatEffects.category_for("draw") == "resource", "energy and draw are resources")
	_check(CombatEffects.category_for("frost") == "orb" and CombatEffects.category_for("dark") == "orb", "orb keys map to orb visuals")
	_check(CombatEffects.category_for("unknown_key") == "neutral", "unknown status falls back to generic")
	_check(CombatEffects.tone_for("poison") != CombatEffects.tone_for("strength"), "status tones differ by key")
	_check(CombatEffects.potion_tone("damage") != CombatEffects.potion_tone("recovery"), "potion tones differ by effect")
	_check(CombatEffects.school_tone("attack") != CombatEffects.school_tone("skill"), "card schools have distinct tones")


func _test_layer_api() -> void:
	var fx := CombatEffects.new()
	root.add_child(fx)
	await _settle()
	_check(fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "effects layer never captures input")
	_check(fx.effects is Array[Dictionary], "effects keep the typed Dictionary array")

	fx.play_attack(Vector2(120, 160), Vector2(460, 240), "magic", Color("c7a66a"), 1.6)
	var attack := _last(fx, "attack")
	_check(not attack.is_empty() and str(attack["style"]) == "magic", "attack keeps style")
	_check(absf(float(attack["power"]) - 1.6) < 0.001, "attack carries damage power")
	_check(attack["from"] != attack["to"], "attack stores distinct local endpoints")

	fx.play_area([Vector2(200, 200), Vector2(400, 200)], Color("c7a66a"))
	_check(_last(fx, "area")["points"].size() == 2, "area stores every target point")
	var before := fx.effects.size()
	fx.play_area([])
	_check(fx.effects.size() == before, "empty area emits no effect")

	fx.play_hit(Vector2(300, 220), 24, 6, false, true)
	var hit := _last(fx, "hit")
	var burst := _last(fx, "impact")
	_check(str(hit["text"]) == "-24" and bool(hit["heavy"]), "hit text scales with damage")
	_check(not burst.is_empty() and bool(burst["heavy"]) and float(burst["power"]) > 1.0, "heavy hit adds a stronger impact burst")
	_check(bool(_last(fx, "shield")["shatter"]) == false, "partial block does not shatter the shield")
	fx.clear_effects()
	fx.play_hit(Vector2(300, 220), 0, 8)
	_check(_types(fx) == ["shield"] and bool(_last(fx, "shield")["shatter"]), "fully blocked hit only shows a shattering shield")
	fx.clear_effects()

	fx.play_heal(Vector2(300, 220), 12)
	_check(str(_last(fx, "heal")["text"]) == "+12" and float(_last(fx, "heal")["power"]) > 0.7, "heal carries amount and power")
	fx.play_guard(Vector2(300, 220), 12)
	_check(str(_last(fx, "guard")["text"]) == "格挡 +12", "guard shows gained block")
	fx.play_guard(Vector2(300, 220), 5, Color("b59acb"), "奥斯蒂承伤 5")
	_check(str(_last(fx, "guard")["text"]) == "奥斯蒂承伤 5", "guard accepts a custom label")

	fx.play_status(Vector2(300, 220), "力量 +2", Color("c7a66a"), "strength")
	fx.play_status(Vector2(300, 220), "虚弱 +2", Color("c7a66a"), "weak")
	fx.play_status(Vector2(300, 220), "能量 +2", Color("c7a66a"), "energy")
	fx.play_status(Vector2(300, 220), "冰霜球 +1", Color("c7a66a"), "frost")
	fx.play_status(Vector2(300, 220), "阶段 2", Color("c7a66a"))
	var routed := _types(fx)
	for kind in ["buff", "debuff", "resource", "orb", "status"]:
		_check(kind in routed, "play_status routes " + kind)
	fx.play_potion(Vector2(300, 220), "凝露药", Color("91d49a"), "recovery")
	_check(str(_last(fx, "potion")["kind"]) == "recovery", "potion carries its effect kind")
	fx.play_skill(Vector2(300, 220), "", Color("8fb7a5"), "skill")
	_check(str(_last(fx, "sigil")["school"]) == "skill", "sigil carries the card school")
	fx.play_death(Vector2(300, 220))
	_check(not _last(fx, "death").is_empty(), "death effect is queued")

	# reduced_motion 关闭全屏染色，time_scale 让特效寿命跟随战斗速度。
	fx.clear_effects()
	fx.reduced_motion = true
	fx.play_hit(Vector2(300, 220), 9)
	_check(not bool(_last(fx, "hit")["wash"]), "reduced motion disables the screen wash")
	fx.time_scale = 2.0
	fx._process(0.25)
	_check(float(_last(fx, "hit")["age"]) > 0.49, "time_scale accelerates effect aging")
	fx._process(2.0)
	_check(fx.effects.is_empty(), "expired effects are removed")
	fx.clear_effects()
	_check(fx.effects.is_empty(), "clear_effects empties the queue")
	fx.queue_free()
	await _settle()


func _test_draw_paths() -> void:
	var fx := CombatEffects.new()
	root.add_child(fx)
	await _settle()
	# 一次性把所有分支排进绘制队列，让引擎真正跑一遍每种 _draw() 路径。
	for style in ["slash", "magic", "poison", "projectile", "heavy", "lightning"]:
		fx.play_attack(Vector2(120, 160), Vector2(460, 240), style, Color("c7a66a"), 1.5)
	fx.play_area([Vector2(200, 220), Vector2(400, 220), Vector2(300, 320)])
	fx.play_hit(Vector2(320, 240), 24, 6, false, true)
	fx.play_hit(Vector2(320, 240), 0, 8)
	fx.play_heal(Vector2(240, 240), 12)
	fx.play_guard(Vector2(340, 240), 12)
	fx.play_buff(Vector2(260, 240), "力量 +2", Color("c7a66a"))
	fx.play_debuff(Vector2(260, 240), "虚弱 +2", Color("e56f5c"))
	fx.play_resource(Vector2(260, 240), "能量 +2", Color("8dd3e2"))
	fx.play_orb(Vector2(260, 240), "冰霜球 +1", Color("8dd3e2"))
	fx.play_potion(Vector2(260, 240), "凝露药", Color("91d49a"), "recovery")
	fx.play_skill(Vector2(260, 240), "", Color("8fb7a5"), "attack")
	fx.play_skill(Vector2(260, 240), "", Color("c7a66a"), "power")
	fx.play_skill(Vector2(260, 240), "", Color("8fb7a5"), "skill")
	fx.play_status(Vector2(260, 240), "阶段 2", Color("c7a66a"))
	fx.play_death(Vector2(320, 240))
	_check(fx.effects.size() >= 20, "all visual branches queued together")
	fx.reduced_motion = false
	for ignored in 8:
		await process_frame
	fx.reduced_motion = true
	for ignored in 6:
		await process_frame
	_check(true, "drawing every effect branch completes without a script error")
	fx.clear_effects()
	fx.queue_free()
	await _settle()


func _potion_case(id: String, expected: Array, expected_kind: String) -> void:
	ui._refresh()
	ui.game.state.potions = [id]
	ui.game.state.hp = maxi(1, int(ui.game.state.max_hp) - 20)
	ui.game.state.block = 0
	ui._refresh()
	await _settle()
	ui.combat_effects.clear_effects()
	ui._use_potion(0)
	await _settle()
	var present := _types(ui.combat_effects)
	for kind in expected:
		_check(kind in present, "%s produces %s effect (got %s)" % [id, kind, str(present)])
	var bottle := _last(ui.combat_effects, "potion")
	_check(not bottle.is_empty() and str(bottle["kind"]) == expected_kind, "%s uses the %s bottle tone" % [id, expected_kind])


func _test_wiring() -> void:
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	await _fixture()

	ui.combat_effects.clear_effects()
	ui._show_card_feedback({"type": "skill", "name": "旅人盾"})
	var sigil := _last(ui.combat_effects, "sigil")
	_check(not sigil.is_empty() and str(sigil["school"]) == "skill", "playing a skill card lays a skill sigil")
	_check(str(sigil["text"]).is_empty(), "sigil leaves the card name to the cast plaque")

	await _potion_case("potion_heal", ["heal", "potion"], "recovery")
	await _potion_case("potion_guard", ["guard", "potion"], "defense")
	await _potion_case("potion_strength", ["buff", "potion"], "buff")
	await _potion_case("potion_weak", ["debuff", "potion"], "hex")

	ui._refresh()
	ui.game.profile.settings["reduced_motion"] = true
	ui._refresh()
	_check(ui.combat_effects.reduced_motion, "reduced motion setting reaches the effects layer")
	ui.game.profile.settings["reduced_motion"] = false
	ui._refresh()

	ui.game.state.hand = [{"id": "warden_01", "upgraded": false}]
	ui.game.state.energy = 5
	ui._refresh()
	await _settle()
	ui.combat_effects.clear_effects()
	ui._play_card(0)
	_check("sigil" in _types(ui.combat_effects), "attack card also lays a cast sigil")
	_check(await _wait_until(func(): return "hit" in _types(ui.combat_effects)), "damage event reaches hit feedback")
	var played := _types(ui.combat_effects)
	for kind in ["attack", "hit", "impact"]:
		_check(kind in played, "damage event produces " + kind + " (got " + str(played) + ")")
	ui._refresh()
	_check(ui.combat_effects.effects.is_empty(), "refresh clears all transient effects")
