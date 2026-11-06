extends SceneTree
## 战斗特效视觉证据：在真实战斗界面上叠加各类特效，逐张截图到 docs/evidence/combat-vfx-*。
## 运行：godot --headless --path . --script tests/capture_combat_vfx.gd
## 只调用表现层 API，不改动任何规则状态，也不写存档。

const Rules = preload("res://core/game_engine.gd")
const OUTPUT := "res://docs/evidence/combat-vfx-20261106"

var ui
var shots: Array[String] = []
var failures: Array[String] = []
var player_at := Vector2.ZERO
var enemy_at := Vector2.ZERO
var enemy2_at := Vector2.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _settle() -> void:
	for ignored in 4:
		await process_frame


func _enemy(definition: Dictionary, hp: int = 80) -> Dictionary:
	return {"id": definition.id, "name": definition.name, "hp": hp, "max_hp": hp, "block": 0,
		"status": {}, "pattern": [{"intent": "攻击", "effects": [{"op": "damage", "value": 6}]}],
		"turn": 0, "intent": "攻击 6", "color": definition.color}


func _fixture() -> void:
	ui.game = Rules.new("")
	ui.game.new_run("warden", 42)
	ui.game.enter_node(1)
	ui.game.state.enemies = [
		_enemy(ui.game.data.enemies[0]),
		_enemy(ui.game.data.enemies[4], 70),
	]
	ui.game.state.hand = [{"id": "warden_01", "upgraded": false}, {"id": "warden_02", "upgraded": false},
		{"id": "warden_03", "upgraded": false}, {"id": "neutral_03", "upgraded": false}]
	ui.game.state.energy = 5
	ui.game.state.potions = ["potion_heal", "potion_guard", "potion_ember"]
	ui.menu_open = false
	ui.selected_target = 0
	ui.save_warning = ""
	ui.notice = "交锋特效演示 · 内存沙盒，不写旅程存档"
	ui._refresh()
	await _settle()
	player_at = ui.combat_actors["player"].get_impact_position()
	enemy_at = ui.combat_actors["enemy:0"].get_impact_position()
	enemy2_at = ui.combat_actors["enemy:1"].get_impact_position()


func _shot(label: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		failures.append(label + ": no viewport image")
		return
	var path := OUTPUT + "/" + label + ".png"
	if image.save_png(path) != OK:
		failures.append(label + ": save failed")
		return
	shots.append(path)


func _case(label: String, wait: float, setup: Callable) -> void:
	ui.combat_effects.clear_effects()
	setup.call()
	await create_timer(wait).timeout
	await _shot(label)


func _run() -> void:
	root.title = "灰誓 · 战斗特效证据（不写存档）"
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	ui = load("res://tests/ui_shell.gd").new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _settle()
	await _fixture()

	await _case("01-battle-baseline", 0.05, func(): pass)
	await _case("02-attack-slash", 0.17, func():
		ui.combat_effects.play_attack(player_at, enemy_at, "slash", Color("c7a66a"), 1.5)
		ui.combat_effects.play_hit(enemy_at, 22, 0, false, true))
	await _case("03-attack-magic", 0.17, func():
		ui.combat_effects.play_attack(player_at, enemy_at, "magic", Color("b59acb"), 1.4)
		ui.combat_effects.play_hit(enemy_at, 14, 0, false, false))
	await _case("04-attack-poison", 0.17, func():
		ui.combat_effects.play_attack(player_at, enemy_at, "poison", Color("a4c886"), 1.1)
		ui.combat_effects.play_hit(enemy_at, 9, 0, true, false))
	await _case("05-attack-heavy", 0.17, func():
		ui.combat_effects.play_attack(player_at, enemy_at, "heavy", Color("e8a15c"), 1.9)
		ui.combat_effects.play_hit(enemy_at, 28, 0, false, true))
	await _case("06-attack-projectile", 0.13, func():
		ui.combat_effects.play_attack(player_at, enemy2_at, "projectile", Color("c7a66a"), 1.2))
	await _case("07-area-sigil", 0.18, func():
		ui.combat_effects.play_area([enemy_at, enemy2_at], Color("dd8a70")))
	await _case("08-defense-guard", 0.16, func():
		ui.combat_effects.play_guard(player_at, 14)
		ui.combat_effects.play_hit(enemy_at, 0, 8))
	await _case("09-recovery-heal", 0.17, func():
		ui.combat_effects.play_heal(player_at, 12))
	await _case("10-attribute-effects", 0.17, func():
		ui.combat_effects.play_buff(player_at + Vector2(-64, 4), "力量 +2", Color("f2d08a"))
		ui.combat_effects.play_debuff(enemy_at, "虚弱 +2", Color("e56f5c"))
		ui.combat_effects.play_resource(player_at + Vector2(72, 10), "能量 +2", Color("8dd3e2"))
		ui.combat_effects.play_orb(enemy2_at, "冰霜球 +1", Color("8dd3e2")))
	await _case("11-potion-effects", 0.17, func():
		ui.combat_effects.play_potion(player_at, "凝露药", Color("91d49a"), "recovery")
		ui.combat_effects.play_potion(enemy_at, "余烬瓶", Color("e88a63"), "damage"))
	await _case("12-skill-sigils", 0.17, func():
		ui.combat_effects.play_skill(player_at, "", Color("8fb7a5"), "skill")
		ui.combat_effects.play_skill(enemy_at, "", Color("dd8a70"), "attack")
		ui.combat_effects.play_skill(enemy2_at, "", Color("c7a66a"), "power"))
	await _case("13-combined", 0.17, func():
		ui.combat_effects.play_attack(player_at, enemy_at, "magic", Color("c7a66a"), 1.6)
		ui.combat_effects.play_hit(enemy_at, 19, 6, false, true)
		ui.combat_effects.play_guard(player_at, 10)
		ui.combat_effects.play_heal(player_at + Vector2(0, -30), 8)
		ui.combat_effects.play_potion(enemy2_at, "铁肤药", Color("a7ced1"), "defense"))

	var report := {"shots": shots, "failures": failures, "mode": "native viewport capture", "save": "memory only"}
	print("COMBAT_VFX_CAPTURE " + JSON.stringify(report))
	var report_file := FileAccess.open(OUTPUT + "/capture-results.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	ui.queue_free()
	await _settle()
	quit(0 if failures.is_empty() else 1)
