extends RefCounted
## Grey Oath deterministic rules. No scene tree or animation dependencies.

const Progression = preload("res://core/progression.gd")
const SAVE_VERSION = 1
const MIN_DIFFICULTY = -2
const MAX_DIFFICULTY = 8
const CHAPTER_NODES = 15
const Classes = preload("res://core/class_mechanics.gd")
const TutorialLessons = preload("res://core/tutorial_lessons.gd")
const Items = preload("res://core/item_mechanics.gd")
const BattleTactics = preload("res://core/battle_tactics.gd")
const BuildGuides = preload("res://core/build_guides.gd")
const WorkshopPack = preload("res://core/workshop_pack.gd")
const Oaths = preload("res://core/oath_mechanics.gd")
const SaveStore = preload("res://core/save_store.gd")
const RandomStreams = preload("res://core/random_streams.gd")
const MapGen = preload("res://core/map_gen.gd")
const ContentDB = preload("res://core/content_db.gd")
const RunFlow = preload("res://core/run_flow.gd")
const MetaProgress = preload("res://core/meta_progress.gd")
const CombatFlow = preload("res://core/combat_flow.gd")
const WORKSHOP_CARD_ID = WorkshopPack.CARD_ID
const WORKSHOP_ENEMY_ID = "workshop_enemy"
const WORKSHOP_POTION_ID = "workshop_potion"
const STREAMS = ["map", "battle", "loot", "event"]
const EFFECT_OPS = ["damage", "block", "draw", "energy", "heal", "self_damage", "poison", "weak", "vulnerable", "strength", "thorns", "regen", "soul", "summon", "mark", "lifesteal", "block_damage", "cleanse", "exhaust_hand", "next_energy", "stars", "forge", "fetch_blade", "minion", "osty_summon", "osty_attack", "osty_sacrifice", "doom", "soul_card", "shiv", "discard", "channel", "evoke", "dualcast", "orb_slots", "focus", "dexterity", "intangible", "frail", "exhaust_block", "exhaust_draw", "strength_each_turn", "retain_block", "shiv_damage", "poison_multiply", "discard_draw", "discard_energy", "soul_summon", "resonance", "resonant_damage", "resonant_block", "cinder", "ignite"]

var data: Dictionary = {}
var state: Dictionary = {}
var profile: Dictionary = {}
var last_error: String = ""
var _save_path: String = ""
var _indexes: Dictionary = {}
var _content = ContentDB.new()
var _random = RandomStreams.new()
var _workshop_definitions: Dictionary = {}
var _action_busy = false
## Transient presentation results: never saved and never used to determine rules.
var combat_events: Array = []
var _combat_recording := false
var _item_notices: Array[String] = []


func _init(save_path: String = "user://save.json") -> void:
	_save_path = save_path
	_content = ContentDB.new()
	if not _content.load_from(ContentDB.DEFAULT_PATH):
		last_error = _content.last_error
	data = _content.data
	_indexes = _content.indexes
	profile = _new_profile()
	state = _blank_state()
	if not _save_path.is_empty() and (FileAccess.file_exists(_save_path) or FileAccess.file_exists(_save_path + ".bak")):
		load_game()


func _new_profile() -> Dictionary:
	return {"total_wins": 0, "role_wins": {}, "clears": {}, "ascension": {}, "seen_cards": [], "sacred_collection": [], "history": [], "settings": {"music": true, "sound": true, "music_volume": 0.7, "sound_volume": 0.8, "combat_speed": 1.0, "reduced_motion": false}, "stats": {"runs_started": 0, "cards_played": 0, "cards_upgraded": 0, "elite_wins": 0, "boss_wins": 0}, "achievements": {}, "daily": {"key": "", "attempts": 0, "best": 0, "best_role": "", "best_oath": "", "streak": 0, "last_key": "", "history": []}}


func _blank_state() -> Dictionary:
	return {"active": false, "run_id": "", "seed": 0, "role": "warden", "difficulty": 0, "chapter": 0, "row": -1, "lane": -1, "room": "map", "hp": 0, "max_hp": 0, "gold": 0, "deck": [], "relics": [], "items": {}, "item_claimed": [], "potions": [], "map": [], "hand": [], "draw": [], "discard": [], "exhaust": [], "enemies": [], "energy": 0, "block": 0, "status": {}, "souls": 0, "marks": [], "summons": [], "combo": 0, "turn": 0, "rewards": [], "build_plan": "", "reward_rerolls_used": [], "reward_seen": [], "shop": [], "event": {}, "log": [], "unlocked_snapshot": [], "processed_encounters": [], "rng_states": {}, "encounter_kind": "normal", "first_damage_used": false, "sister_used": false, "selected_shop_remove": -1, "battle_rewarded": false, "history_recorded": false, "boss_reward": "", "elapsed_turns": 0, "growth_wins": 0, "growth_level": 0, "boss_phase": 1, "boss_phases": 1, "stars": 0, "blade": 0, "blade_created": false, "orbs": [], "orb_slots": 3, "osty_hp": 0, "pending_discard": 0, "tactical_points": 0, "tactical_last_type": "", "tactical_gained": 0, "tactical_used": false, "oath": "", "modifiers": {}, "daily": false, "daily_key": "", "daily_modifier": "", "elite_affix": "", "run_elites": 0, "run_bosses": 0, "score": 0}


func role_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == state.role:
		return _workshop_definitions.role
	return _content.role_data(id)


func card_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == WORKSHOP_CARD_ID:
		return _workshop_definitions.card
	return _content.card_data(id)


func relic_data(id: String) -> Dictionary:
	return _content.relic_data(id)


func potion_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == WORKSHOP_POTION_ID:
		return _workshop_definitions.potion
	return _content.potion_data(id)


func item_data(id: String) -> Dictionary:
	return _content.item_data(id)


func enemy_data(id: String) -> Dictionary:
	if state.get("encounter_kind") == "workshop" and id == WORKSHOP_ENEMY_ID:
		return _workshop_definitions.enemy
	return _content.enemy_data(id)


func sacred_ids() -> Array:
	return _content.sacred_ids()


func card_view(instance: Dictionary) -> Dictionary:
	var bonus = int(state.get("status", {}).get("shiv_damage", 0))
	return _content.view(instance, card_data(str(instance.get("id", ""))), bonus)


func is_role_unlocked(role_id: String) -> bool:
	return MetaProgress.is_role_unlocked(self,role_id)

func is_card_unlocked(card: Dictionary) -> bool:
	return MetaProgress.is_card_unlocked(self,card)

func unlocked_difficulty(role_id: String) -> int:
	return MetaProgress.unlocked_difficulty(self,role_id)

func start_tutorial(role_id: String = "warden") -> Dictionary:
	if not _save_path.is_empty() or state.active:
		return _fail("教学需要单独的练习场。")
	var lesson: Dictionary = TutorialLessons.LESSONS.get(role_id, {})
	if lesson.is_empty() or role_data(role_id).is_empty():
		return _fail("没有这个旅者的教学关卡。")
	var opponent: Dictionary = _indexes.enemies.get(lesson.enemy, {})
	if opponent.is_empty():
		return _fail("练习对手尚未就绪。")
	var deck: Array = []
	for id in lesson.deck:
		if card_data(id).is_empty():
			return _fail("练习卡牌尚未就绪。")
		deck.append({"id": id, "upgraded": false})

	state = _blank_state()
	state.active = true
	state.run_id = "tutorial"
	state.role = role_id
	state.room = "battle"
	state.encounter_kind = "tutorial"
	state.hp = 24
	state.max_hp = state.hp
	state.deck = deck
	state.draw = deck.duplicate(true)
	state.draw.reverse()
	state.enemies.append({
		"id": opponent.id, "name": opponent.name, "kind": "normal",
		"hp": lesson.hp, "max_hp": lesson.hp, "block": 0, "status": {}, "turn": 0,
		"pattern": opponent.pattern.duplicate(true), "intent": "", "color": opponent.color,
	})
	_seed_streams(int(state.seed))
	_log("练习开始。先观察敌人头顶的行动意图。")
	Classes.start_combat(self)
	_begin_player_turn()
	_update_intents()
	return _commit("练习开始。")


func start_workshop(pack: Dictionary) -> Dictionary:
	if not _save_path.is_empty() or state.active:
		return _fail("工坊试玩需要独立的试玩场。")
	var checked: Dictionary = WorkshopPack.validate(pack, self)
	if not checked.get("ok", false):
		return _fail(str(checked.get("message", "工坊作品无效。")))
	var design: Dictionary = checked.pack
	var base_role: Dictionary = _indexes.roles[design.role.base].duplicate(true)
	base_role.name = design.role.name
	base_role.max_hp = design.role.hp
	var card_op := "damage" if design.card.kind == "attack" else "block"
	var opponent := {
		"id": WORKSHOP_ENEMY_ID, "name": design.enemy.name, "kind": "normal", "chapter": 0,
		"hp": design.enemy.hp, "color": "#c7a279", "pattern": [
			{"intent": "攻击", "effects": [{"op": "damage", "value": design.enemy.attack}]},
			{"intent": "防御", "effects": [{"op": "block", "value": design.enemy.block}]},
		],
	}
	_workshop_definitions = {
		"role": base_role,
		"card": {
			"id": WORKSHOP_CARD_ID, "name": design.card.name, "role": design.role.base,
			"type": design.card.kind, "rarity": "starter", "cost": design.card.cost,
			"description": _workshop_effect_text(card_op, design.card.amount),
			"effects": [{"op": card_op, "value": design.card.amount}],
		},
		"potion": {
			"id": WORKSHOP_POTION_ID, "name": design.item.name,
			"description": _workshop_effect_text(design.item.kind, design.item.amount),
			"effects": [{"op": design.item.kind, "value": design.item.amount}],
		},
		"enemy": opponent,
	}

	state = _blank_state()
	state.workshop_pack = design.duplicate(true)
	state.active = true
	state.run_id = "workshop"
	state.role = design.role.base
	state.room = "battle"
	state.encounter_kind = "workshop"
	state.max_hp = design.role.hp
	state.hp = state.max_hp
	state.potions = [WORKSHOP_POTION_ID]
	for id in design.build.starter_cards:
		state.deck.append({"id": id, "upgraded": false})
	state.draw = state.deck.duplicate(true)
	_seed_streams(int(state.seed))
	_shuffle(state.draw, "battle")
	var signature_index: int = state.draw.find_custom(func(card): return card.id == WORKSHOP_CARD_ID)
	state.draw.append(state.draw.pop_at(signature_index))
	state.enemies.append({
		"id": opponent.id, "name": opponent.name, "kind": opponent.kind,
		"hp": opponent.hp, "max_hp": opponent.hp, "block": 0, "status": {}, "turn": 0,
		"pattern": opponent.pattern.duplicate(true), "intent": "", "color": opponent.color,
	})
	Classes.start_combat(self)
	_begin_player_turn()
	_player_effect({"op": design.talent.kind, "value": design.talent.amount}, 0)
	_log("%s使用流派「%s」迎战%s。" % [base_role.name, design.build.name, opponent.name])
	_log("天赋「%s」：%s" % [design.talent.name, _workshop_effect_text(design.talent.kind, design.talent.amount)])
	_update_intents()
	return _commit("工坊试玩开始。")


func _workshop_effect_text(op: String, amount: int) -> String:
	match op:
		"damage": return "造成 %d 点伤害。" % amount
		"block": return "获得 %d 点格挡。" % amount
		"heal": return "回复 %d 点生命。" % amount
		"energy": return "获得 %d 点能量。" % amount
		"strength": return "获得 %d 点力量。" % amount
	return ""


func new_run(role_id: String, seed_value: int = -1, difficulty: int = 0, build_plan: String = "", oath_id: String = "") -> Dictionary:
	return MetaProgress.new_run(self,role_id,seed_value,difficulty,build_plan,oath_id)

func oath_offers(seed_value: int) -> Array:
	return MetaProgress.oath_offers(self,seed_value)

func oath_view(oath_id: String) -> Dictionary:
	return MetaProgress.oath_view(self,oath_id)

func current_oath() -> Dictionary:
	return MetaProgress.current_oath(self)

func elite_affix_view() -> Dictionary:
	return MetaProgress.elite_affix_view(self)

func daily_view() -> Dictionary:
	return MetaProgress.daily_view(self)

func start_daily_run(daily_key: String = "") -> Dictionary:
	return MetaProgress.start_daily_run(self,daily_key)

func _seed_streams(seed_value: int) -> void:
	_random.seed_with(seed_value)
	_sync_rng()


func _sync_rng() -> void:
	state.rng_states = _random.snapshot()


func _restore_rng() -> void:
	var snapshot = state.get("rng_states", {})
	if not snapshot is Dictionary:
		snapshot = {}
	_random.restore(int(state.seed), snapshot)


func _random_int(stream: String, low: int, high: int) -> int:
	return _random.randi_range(stream, low, high)


func _shuffle(items: Array, stream: String) -> void:
	_random.shuffle(items, stream)


func _make_map() -> Array:
	return MapGen.generate(_random)


func route_exits(row: int, lane: int) -> Array:
	var route = state.get("map", [])
	if not route is Array:
		return []
	return MapGen.route_exits(route, row, lane)


func available_nodes() -> Array:
	var result = []
	if not state.active or state.room != "map":
		return result
	if int(state.row) < 0:
		if not state.map.is_empty() and state.map[0] is Array:
			for lane in range(mini(3, state.map[0].size())):
				if state.map[0][lane] is Dictionary:
					result.append(lane)
		return result
	return route_exits(int(state.row), int(state.lane))


func _resolve_node_kind(node: Dictionary) -> String:
	return MapGen.resolve_kind(node, _random)


func enter_node(lane: int) -> Dictionary:
	if not available_nodes().has(lane):
		return _fail("无法前往这个节点。请选择连线上的下一层。")
	state.row = int(state.row) + 1
	state.lane = lane
	var node: Dictionary = state.map[int(state.row)][lane]
	var kind = _resolve_node_kind(node)
	state.encounter_kind = kind
	state.selected_shop_remove = -1
	match kind:
		"normal", "elite", "boss":
			_start_battle(kind)
		"shop":
			state.room = "shop"
			_make_shop()
		"rest":
			state.room = "rest"
		"event":
			state.room = "event"
			state.event = Items.offer(self) if node.kind == "unknown" or (node.kind == "fate" and _random_int("event", 0, 2) == 0) else {}
			if state.event.is_empty():
				var options = []
				for event in data.get("events", []):
					if int(event.get("chapter", 0)) == int(state.chapter):
						options.append(event)
				if options.is_empty():
					state.room = "rest"
				else:
					state.event = options[_random_int("event", 0, options.size() - 1)].duplicate(true)
		"treasure":
			state.room = "treasure"
			var relic = _random_relic(false)
			state.boss_reward = relic
			_gain_relic(relic)
			state.gold = int(state.gold) + 25
			_log("开启遗留箱：获得25金币与%s。" % relic_data(relic).get("name", "一份祝福"))
	return _commit("抵达新的节点。")


func _start_battle(kind: String) -> void:
	CombatFlow._start_battle(self,kind)

func _apply_battle_modifiers(kind: String) -> void:
	CombatFlow._apply_battle_modifiers(self,kind)

func _enemy_names() -> Array[String]:
	return CombatFlow._enemy_names(self)

func _begin_player_turn() -> void:
	CombatFlow._begin_player_turn(self)

func _draw_cards(amount: int) -> void:
	CombatFlow._draw_cards(self,amount)

func _requires_enemy(effects: Array) -> bool:
	return ContentDB.requires_enemy(effects)


func _valid_target(index: int) -> bool:
	return CombatFlow._valid_target(self,index)

func play_card(hand_index: int, target_index: int = 0) -> Dictionary:
	return CombatFlow.play_card(self,hand_index,target_index)

func _record_tactical_play(card_type: String) -> void:
	CombatFlow._record_tactical_play(self,card_type)

func tactics_view(target_index: int = 0) -> Dictionary:
	return CombatFlow.tactics_view(self,target_index)

func use_tactic(id: String, target_index: int = 0) -> Dictionary:
	return CombatFlow.use_tactic(self,id,target_index)

func _effect_value(effect: Dictionary, target_index: int = 0) -> int:
	return CombatFlow._effect_value(self,effect,target_index)

func _player_effect(effect: Dictionary, target_index: int) -> void:
	CombatFlow._player_effect(self,effect,target_index)

func _exhaust_instance(instance: Dictionary) -> void:
	CombatFlow._exhaust_instance(self,instance)

func choose_discard(index: int, target_index: int = 0) -> Dictionary:
	return CombatFlow.choose_discard(self,index,target_index)

func calculate_damage(base: int, source_status: Dictionary, target_status: Dictionary) -> int:
	return CombatFlow.calculate_damage(self,base,source_status,target_status)

func preview_card(hand_index: int, target_index: int = 0) -> Dictionary:
	return CombatFlow.preview_card(self,hand_index,target_index)

func _add_status(target: Dictionary, key: String, amount: int) -> void:
	CombatFlow._add_status(self,target,key,amount)

func _damage_enemy(index: int, amount: int, retaliate: bool = true, source: String = "player") -> int:
	return CombatFlow._damage_enemy(self,index,amount,retaliate,source)

func _damage_player(amount: int, source_index: int = -1, retaliate: bool = true, source: String = "") -> int:
	return CombatFlow._damage_player(self,amount,source_index,retaliate,source)

func _heal(amount: int) -> void:
	CombatFlow._heal(self,amount)

func _decay_turn_status(status: Dictionary) -> void:
	CombatFlow._decay_turn_status(self,status)

func end_turn() -> Dictionary:
	return CombatFlow.end_turn(self)

func _enemy_pressure(enemy: Dictionary) -> int:
	return CombatFlow._enemy_pressure(self,enemy)

func _enemy_desperation(enemy: Dictionary) -> int:
	return CombatFlow._enemy_desperation(self,enemy)

func _enemy_attack_value(value: int, op: String, enemy: Dictionary) -> int:
	return CombatFlow._enemy_attack_value(self,value,op,enemy)

func _enemy_echo_bonus() -> int:
	return CombatFlow._enemy_echo_bonus(self)

func _enemy_heal_target(index: int) -> int:
	return CombatFlow._enemy_heal_target(self,index)

func _enemy_effect(effect: Dictionary, index: int) -> void:
	CombatFlow._enemy_effect(self,effect,index)

func _first_living_enemy() -> int:
	return CombatFlow._first_living_enemy(self)

func _update_intents() -> void:
	CombatFlow._update_intents(self)

func _check_battle_end() -> void:
	CombatFlow._check_battle_end(self)

func _advance_boss_phase() -> bool:
	return CombatFlow._advance_boss_phase(self)

func _battle_growth() -> void:
	CombatFlow._battle_growth(self)

func _win_battle() -> void:
	CombatFlow._win_battle(self)

func _eligible_cards(rare_only: bool = false) -> Array:
	return RunFlow._eligible_cards(self, rare_only)
func _make_card_rewards(count: int, rare_only: bool = false) -> Array:
	return RunFlow._make_card_rewards(self, count, rare_only)
func build_plan_options(role_id: String) -> Array:
	return RunFlow.build_plan_options(self, role_id)
func set_build_plan(plan_id: String) -> Dictionary:
	return RunFlow.set_build_plan(self, plan_id)
func build_recommendation(instance: Dictionary) -> Dictionary:
	return RunFlow.build_recommendation(self, instance)
func _migrate_reward_guidance() -> void:
	RunFlow._migrate_reward_guidance(self)
func _reward_reroll_candidates() -> Array:
	return RunFlow._reward_reroll_candidates(self)
func reward_reroll_view(index: int) -> Dictionary:
	return RunFlow.reward_reroll_view(self, index)
func reroll_reward(index: int) -> Dictionary:
	return RunFlow.reroll_reward(self, index)
func choose_reward(index: int) -> Dictionary:
	return RunFlow.choose_reward(self, index)
func _relic_total(op: String) -> int:
	return RunFlow._relic_total(self, op)
func _random_relic(boss: bool = false) -> String:
	return RunFlow._random_relic(self, boss)
func _gain_relic(id: String) -> void:
	RunFlow._gain_relic(self, id)
func _make_shop() -> void:
	RunFlow._make_shop(self)
func _shop_price(base: int) -> int:
	return RunFlow._shop_price(self, base)
func buy_item(index: int) -> Dictionary:
	return RunFlow.buy_item(self, index)
func remove_card(deck_index: int) -> Dictionary:
	return RunFlow.remove_card(self, deck_index)
func rest(upgrade_deck_index: int = -1) -> Dictionary:
	return RunFlow.rest(self, upgrade_deck_index)
func discard_negative_item(id: String) -> Dictionary:
	return RunFlow.discard_negative_item(self, id)
func choose_event(index: int) -> Dictionary:
	return RunFlow.choose_event(self, index)
func use_potion(slot: int, target_index: int = 0) -> Dictionary:
	return CombatFlow.use_potion(self,slot,target_index)

func leave_room() -> Dictionary:
	return RunFlow.leave_room(self)
func _mark_node_cleared() -> void:
	RunFlow._mark_node_cleared(self)
func _finish_run(victory: bool) -> void:
	MetaProgress._finish_run(self,victory)

func _record_daily_run(victory: bool) -> void:
	MetaProgress._record_daily_run(self,victory)

func abandon_run() -> Dictionary:
	return MetaProgress.abandon_run(self)

func _seen(id: String) -> void:
	if not profile.seen_cards.has(id):
		profile.seen_cards.append(id)


func _log(message: String) -> void:
	state.log.append(message)
	while state.log.size() > 12:
		state.log.pop_front()


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


func _commit(message: String) -> Dictionary:
	_combat_recording = false
	_sync_rng()
	if not _item_notices.is_empty():
		message += " " + " ".join(_item_notices)
		_item_notices.clear()
	if state.encounter_kind in ["tutorial", "workshop"]:
		return {"ok": true, "message": message}
	var unlocked = Progression.unlock(profile, sacred_ids().size(), data.get("cards", []).size())
	if not save_game():
		return {"ok": true, "message": message + "（自动保存失败，请勿关闭游戏。）", "save_error": last_error, "achievements": unlocked}
	return {"ok": true, "message": message, "achievements": unlocked}


func _reset_combat_events() -> void:
	combat_events.clear()
	_combat_recording = false


func _combat_event(kind: String, source: String, target: String, amount: int = 0, blocked: int = 0, style: String = "slash") -> void:
	if not _combat_recording:
		return
	combat_events.append({"kind": kind, "source": source, "target": target, "amount": amount, "blocked": blocked, "style": style})


func _combat_damage(source: String, target: String, hp_before: int, hp_after: int, blocked: int) -> void:
	var style = "poison" if source == "poison" else ("projectile" if source.begins_with("summon:") else "slash")
	_combat_event("damage", source, target, hp_before - hp_after, blocked, style)
	if hp_before > 0 and hp_after <= 0:
		if target.begins_with("enemy:") and state.encounter_kind == "boss" and int(state.get("boss_phase", 1)) < int(state.get("boss_phases", 1)):
			return
		_combat_event("death", source, target)


func save_game() -> bool:
	if _save_path.is_empty():
		return true
	_sync_rng()
	var envelope = {"save_version": SAVE_VERSION, "content_version": data.get("version", "1"), "profile": profile, "state": state}
	var written: Dictionary = SaveStore.write(_save_path, envelope)
	last_error = str(written.get("error", ""))
	return bool(written.get("ok", false))


func load_game() -> bool:
	if _save_path.is_empty():
		return false
	var loaded: Dictionary = SaveStore.load_envelope(_save_path, Callable(self, "_valid_save"))
	if not bool(loaded.get("ok", false)):
		last_error = str(loaded.get("error", ""))
		return false
	var parsed: Dictionary = loaded.value
	profile = _new_profile()
	profile.merge(_normalize_numbers(parsed.profile), true)
	_migrate_progression()
	state = _blank_state()
	state.merge(_normalize_numbers(parsed.state), true)
	_migrate_state()
	_migrate_reward_guidance()
	_restore_rng()
	last_error = "已从上一份备份恢复存档。" if bool(loaded.from_backup) else ""
	return true


func _migrate_state() -> void:
	## Older saves have no oath fields at all; merge() already fills defaults,
	## but corrupted dictionaries still need a safe shape.
	if not state.get("modifiers") is Dictionary:
		state.modifiers = {}
	for field in ["run_elites", "run_bosses", "score"]:
		state[field] = maxi(0, int(state.get(field, 0)))
	for field in ["oath", "daily_key", "daily_modifier", "elite_affix"]:
		if not state.get(field) is String:
			state[field] = ""
	state.daily = bool(state.get("daily", false))


func _normalize_numbers(val):
	return ContentDB.normalize_numbers(val)


func _valid_save(value) -> bool:
	if not value is Dictionary or int(value.get("save_version", -1)) != SAVE_VERSION:
		return false
	if str(_normalize_numbers(value.get("content_version", ""))) != str(data.get("version", "1")):
		return false
	if not value.get("profile") is Dictionary or not value.get("state") is Dictionary:
		return false
	var saved = value.state
	if saved.get("encounter_kind") == "workshop":
		return false
	if not saved.get("build_plan", "") is String or not saved.get("reward_rerolls_used", []) is Array or not saved.get("reward_seen", []) is Array:
		return false
	for used in saved.get("reward_rerolls_used", []):
		if not used is bool:
			return false
	for id in saved.get("reward_seen", []):
		if not id is String:
			return false
	if not saved.get("items", {}) is Dictionary or not saved.get("item_claimed", []) is Array:
		return false
	for id in saved.get("items", {}):
		var record = saved.items[id]
		if item_data(str(id)).is_empty() or not record is Dictionary or not record.has("remaining") or not record.has("progress"):
			return false
	for key in ["active", "role", "room", "hp", "max_hp", "deck", "map", "hand", "draw", "discard", "exhaust", "enemies", "rng_states"]:
		if not saved.has(key):
			return false
	if saved.room not in ["map", "battle", "reward", "shop", "rest", "event", "treasure", "victory", "defeat"]:
		return false
	if saved.active and (role_data(str(saved.role)).is_empty() or not saved.deck is Array or int(saved.get("max_hp", 0)) <= 0):
		return false
	for zone in ["deck", "hand", "draw", "discard", "exhaust"]:
		if not saved[zone] is Array:
			return false
		for card in saved[zone]:
			if not card is Dictionary or card_data(str(card.get("id", ""))).is_empty():
				return false
	return true


func _migrate_progression() -> void:
	MetaProgress._migrate_progression(self)

func achievement_entries() -> Array:
	return MetaProgress.achievement_entries(self)

func update_setting(key: String, value: Variant) -> Dictionary:
	return MetaProgress.update_setting(self,key,value)

