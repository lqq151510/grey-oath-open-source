extends SceneTree
## 架构守卫：把重构期间"不能被悄悄改掉"的对外契约固化成断言。
##
## 覆盖：
##   1. core/game_engine.gd 的 23 个公开 API 仍在（has_method 在实例上验证）；
##   2. _blank_state() 仍返回全部契约键（键集合只增不减）；
##   3. SAVE_VERSION 仍为 1；
##   4. data/catalog.json 的 cards=290 / roles=7 / enemies=56；
##   5. ui/main.gd 仍含 docs/UI_REBUILD_20261104.md 规定的战斗节点名（弱但稳定的文本断言）；
##   6. scenes/battle.gd 没有被任何 .gd/.tscn 引用（旧战斗场景已废弃）；
##   7. --strict 时要求 core/random_streams.gd、core/map_gen.gd、core/content_db.gd 已存在；
##      默认只 WARN，因为拆分在逐步落地。
##
## 运行：
##   .tools/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_architecture.gd
##   ... --script tests/test_architecture.gd --strict
##
## 输出最后一行：ARCHITECTURE_RESULT {"checks":N,"failures":[...],"warnings":[...]}
## 退出码：0 = 无失败；1 = 有失败。

const EngineScript = preload("res://core/game_engine.gd")

const ENGINE_PATH := "res://core/game_engine.gd"
const MAIN_UI_PATH := "res://ui/main.gd"
const CATALOG_PATH := "res://data/catalog.json"
const LEGACY_BATTLE := "res://scenes/battle.gd"
const GUARD_PATH := "res://tests/test_architecture.gd"

const REQUIRED_API := [
	"new_run", "start_tutorial", "start_workshop", "enter_node", "play_card",
	"end_turn", "choose_reward", "buy_item", "rest", "choose_event",
	"use_potion", "leave_room", "save_game", "load_game", "card_view",
	"preview_card", "tactics_view", "use_tactic", "route_exits", "available_nodes",
	"daily_view", "start_daily_run", "oath_offers",
]

## 存档 v1 的状态键契约：重构可以把状态搬进子模块，但这些键必须还在。
const REQUIRED_STATE_KEYS := [
	"active", "run_id", "seed", "role", "difficulty", "chapter", "row", "lane", "room",
	"hp", "max_hp", "gold", "deck", "relics", "items", "item_claimed", "potions", "map",
	"hand", "draw", "discard", "exhaust", "enemies", "energy", "block", "status", "souls",
	"marks", "summons", "combo", "turn", "rewards", "build_plan", "reward_rerolls_used",
	"reward_seen", "shop", "event", "log", "unlocked_snapshot", "processed_encounters",
	"rng_states", "encounter_kind", "first_damage_used", "sister_used", "selected_shop_remove",
	"battle_rewarded", "history_recorded", "boss_reward", "elapsed_turns", "growth_wins",
	"growth_level", "boss_phase", "boss_phases", "stars", "blade", "blade_created", "orbs",
	"orb_slots", "osty_hp", "pending_discard", "tactical_points", "tactical_last_type",
	"tactical_gained", "tactical_used", "oath", "modifiers", "daily", "daily_key",
	"daily_modifier", "elite_affix", "run_elites", "run_bosses", "score",
]

## docs/UI_REBUILD_20261104.md 规定的战斗节点名（前缀型节点只断言前缀）。
const REQUIRED_NODES := [
	"BattleArena", "HandArea", "EndTurnButton", "PlayerActor", "PlayerColumn",
	"PlayerStatus", "PlayerDetails", "EnemyColumn_", "EnemyActor_", "EnemyTarget_",
	"EnemyIntent_", "EnemyStatus_", "DrawPile", "DiscardPile", "HandTargetHint",
	"TacticalBar", "TacticalPoints", "BattleTactic_", "PlayerPortraitDetails",
	"BattleFollowers",
]

## 规定里还有、但当前主线尚未实现的节点：只 WARN，不阻塞重构。
const WARN_NODES := ["PlayerHand"]

const SPLIT_MODULES := [
	"res://core/random_streams.gd",
	"res://core/map_gen.gd",
	"res://core/content_db.gd",
]

var checks := 0
var failures: Array[String] = []
var warnings: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String, detail: String = "") -> void:
	checks += 1
	if condition:
		print("[ok]   ", message)
	else:
		var line := message if detail.is_empty() else message + " — " + detail
		failures.append(line)
		print("[FAIL] ", line)


func warn(message: String) -> void:
	warnings.append(message)
	print("[warn] ", message)


func _has_strict() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "--strict":
			return true
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict":
			return true
	return false


func _guard_api(engine) -> void:
	var missing: Array[String] = []
	for name in REQUIRED_API:
		if not engine.has_method(name):
			missing.append(name)
	check(missing.is_empty(), "engine 暴露 %d 个公开 API" % REQUIRED_API.size(),
		"缺失: " + ", ".join(missing))


func _guard_blank_state(engine) -> void:
	var state = engine._blank_state()
	check(state is Dictionary, "_blank_state() 返回 Dictionary")
	if not (state is Dictionary):
		return
	var keys: Dictionary = state
	var missing: Array[String] = []
	for key in REQUIRED_STATE_KEYS:
		if not keys.has(key):
			missing.append(key)
	check(missing.is_empty(), "state 键包含全部 %d 个契约键" % REQUIRED_STATE_KEYS.size(),
		"缺失: " + ", ".join(missing))
	check(keys.size() >= REQUIRED_STATE_KEYS.size(),
		"state 键数量未缩水（当前 %d）" % keys.size(),
		"少于契约键数量 %d" % REQUIRED_STATE_KEYS.size())


func _guard_save_version() -> void:
	var script_res: Script = load(ENGINE_PATH)
	check(script_res != null, "engine 脚本可加载")
	if script_res == null:
		return
	var constants: Dictionary = script_res.get_script_constant_map()
	check(constants.has("SAVE_VERSION"), "engine 仍声明 SAVE_VERSION")
	if constants.has("SAVE_VERSION"):
		check(int(constants["SAVE_VERSION"]) == 1, "SAVE_VERSION == 1",
			"当前为 %s" % str(constants["SAVE_VERSION"]))


func _guard_catalog() -> void:
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	check(not text.is_empty(), "catalog.json 可读")
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	check(parsed is Dictionary, "catalog.json 是 JSON 对象")
	if not (parsed is Dictionary):
		return
	var catalog: Dictionary = parsed
	for expect in [["cards", 290], ["roles", 7], ["enemies", 56]]:
		var key: String = expect[0]
		var want: int = expect[1]
		var got := -1
		if catalog.has(key) and catalog[key] is Array:
			got = (catalog[key] as Array).size()
		check(got == want, "catalog.%s == %d" % [key, want], "当前为 %d" % got)


func _guard_ui_nodes() -> void:
	var text := FileAccess.get_file_as_string(MAIN_UI_PATH)
	check(not text.is_empty(), "ui/main.gd 可读")
	if text.is_empty():
		return
	var missing: Array[String] = []
	for node in REQUIRED_NODES:
		if not text.contains(node):
			missing.append(node)
	check(missing.is_empty(), "ui/main.gd 含全部 %d 个战斗节点名" % REQUIRED_NODES.size(),
		"缺失: " + ", ".join(missing))
	for node in WARN_NODES:
		if not text.contains(node):
			warn("ui/main.gd 未出现文档要求的节点名 %s（已知缺口，见 docs/ARCHITECTURE.md）" % node)


func _scan_refs(dir_path: String, hits: Array[String], skip_dirs: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not skip_dirs.has(name):
				_scan_refs(full, hits, skip_dirs)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			if full != GUARD_PATH and full != LEGACY_BATTLE:
				var text := FileAccess.get_file_as_string(full)
				if text.contains("scenes/battle.gd"):
					hits.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _guard_legacy_battle() -> void:
	var hits: Array[String] = []
	_scan_refs("res://", hits, [".git", ".godot", ".tools", "docs", "build", "node_modules"])
	check(hits.is_empty(), "scenes/battle.gd 未被任何 .gd/.tscn 引用",
		"引用者: " + ", ".join(hits))


func _guard_split_modules(strict: bool) -> void:
	var missing: Array[String] = []
	for path in SPLIT_MODULES:
		if not FileAccess.file_exists(path):
			missing.append(path.get_file())
	if missing.is_empty():
		check(true, "拆分模块已落地（random_streams / map_gen / content_db）")
	elif strict:
		check(false, "--strict: 拆分模块应已存在", "缺失: " + ", ".join(missing))
	else:
		warn("拆分模块尚未接线: " + ", ".join(missing) + "（--strict 时视为失败）")


func run() -> void:
	print("== Grey Oath 架构守卫 ==")
	print("engine: ", ENGINE_PATH)
	var strict := _has_strict()
	print("strict: ", strict)

	_guard_save_version()
	_guard_catalog()
	_guard_ui_nodes()
	_guard_legacy_battle()
	_guard_split_modules(strict)

	var engine = EngineScript.new("")
	check(engine != null, "EngineScript.new(\"\") 可实例化")
	if engine != null:
		_guard_api(engine)
		if engine.has_method("_blank_state"):
			_guard_blank_state(engine)
		else:
			check(false, "engine 仍暴露 _blank_state()（state 契约无法验证）")

	print("ARCHITECTURE_RESULT ", JSON.stringify({
		"checks": checks,
		"failures": failures,
		"warnings": warnings,
	}))
	quit(0 if failures.is_empty() else 1)
