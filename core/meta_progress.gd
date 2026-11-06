extends RefCounted
## Meta progression, run setup, oaths, daily vows and achievements, extracted
## verbatim from core/game_engine.gd. Engine counterparts keep the same names:
## new_run(), oath_offers(), oath_view(), current_oath(), elite_affix_view(),
## daily_view(), start_daily_run(), _finish_run(), _record_daily_run(),
## abandon_run(), achievement_entries(), update_setting(),
## _migrate_progression(), is_role_unlocked(), is_card_unlocked() and
## unlocked_difficulty(). Every function is static; engine is the game engine
## instance that owns state/profile/data and the shared helpers.

const Progression = preload("res://core/progression.gd")
const Oaths = preload("res://core/oath_mechanics.gd")
const BuildGuides = preload("res://core/build_guides.gd")
const MIN_DIFFICULTY = -2
const MAX_DIFFICULTY = 8


static func is_role_unlocked(engine, role_id: String) -> bool:
	var role = engine.role_data(role_id)
	# Every playable traveler is available from the first launch.
	return not role.is_empty()


static func is_card_unlocked(engine, card: Dictionary) -> bool:
	var progress = int(engine.profile.total_wins) if card.get("role", "neutral") == "neutral" else int(engine.profile.role_wins.get(str(card.role), 0))
	return progress >= int(card.get("unlock_wins", 0))


static func unlocked_difficulty(engine, role_id: String) -> int:
	return clampi(int(engine.profile.ascension.get(role_id, 0)), 0, MAX_DIFFICULTY)


static func new_run(engine, role_id: String, seed_value: int = -1, difficulty: int = 0, build_plan: String = "", oath_id: String = "") -> Dictionary:
	if not engine.is_role_unlocked(role_id):
		return engine._fail("这个职业尚未解锁。")
	if not oath_id.is_empty() and Oaths.oath(oath_id).is_empty():
		return engine._fail("这条誓约并不存在。")
	if difficulty < MIN_DIFFICULTY or difficulty > engine.unlocked_difficulty(role_id):
		return engine._fail("该职业尚未开放此进阶难度。")
	if bool(engine.state.get("active", false)):
		return engine._fail("已有未完成旅程，请继续或先结束当前旅程。")
	if BuildGuides.plan_for(role_id, build_plan).is_empty():
		return engine._fail("请选择当前旅者可用的流派。")
	engine.state = engine._blank_state()
	var role = engine.role_data(role_id)
	engine.state.build_plan = build_plan
	engine.state.active = true
	engine.profile.stats.runs_started = int(engine.profile.stats.runs_started) + 1
	engine.state.seed = (int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())) & 0x7fffffff if seed_value < 0 else seed_value & 0x7fffffff
	engine.state.run_id = "%s-%s-%s" % [engine.state.seed, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	engine.state.role = role_id
	engine.state.difficulty = difficulty
	engine.state.oath = oath_id
	engine.state.modifiers = Oaths.modifiers_for(oath_id)
	engine.state.max_hp = Oaths.apply_max_hp(int(role.get("max_hp", 80)), engine.state.modifiers)
	engine.state.hp = engine.state.max_hp
	engine.state.gold = maxi(0, 65 + Oaths.value(engine.state.modifiers, "gold_flat"))
	for id in role.get("starter_cards", []):
		if engine.card_data(str(id)).is_empty():
			return engine._fail("初始卡组引用了不存在的卡牌。")
		engine.state.deck.append({"id": str(id), "upgraded": false})
		engine._seen(str(id))
	for card in engine.data.get("cards", []):
		if engine.is_card_unlocked(card):
			engine.state.unlocked_snapshot.append(str(card.id))
	engine._seed_streams(int(engine.state.seed))
	engine._gain_relic(str(role.get("starter_relic", "")))
	engine.state.map = engine._make_map()
	var oath_name := str(Oaths.oath(oath_id).get("name", ""))
	engine._log("%s踏入长夜。种子 %d%s" % [role.name, engine.state.seed, "，立下%s" % oath_name if not oath_name.is_empty() else ""])
	return engine._commit("新的旅程已开始。")


static func oath_offers(engine, seed_value: int) -> Array:
	## Deterministic three-way oath draft used by the character screen.
	return Oaths.offers(seed_value)


static func oath_view(engine, oath_id: String) -> Dictionary:
	return Oaths.oath(oath_id)


static func current_oath(engine) -> Dictionary:
	return Oaths.oath(str(engine.state.get("oath", "")))


static func elite_affix_view(engine) -> Dictionary:
	if engine.state.get("room", "") != "battle":
		return {}
	return Oaths.affix(str(engine.state.get("elite_affix", "")))


static func daily_view(engine) -> Dictionary:
	var key := Oaths.daily_key()
	var role_ids: Array = []
	for role in engine.data.get("roles", []):
		role_ids.append(str(role.id))
	var setup := Oaths.daily_setup(key, role_ids)
	var entry: Dictionary = engine.profile.get("daily", {}) if engine.profile.get("daily") is Dictionary else {}
	var active_today := bool(engine.state.get("active", false)) and bool(engine.state.get("daily", false)) and str(engine.state.get("daily_key", "")) == key
	var played_today := str(entry.get("last_key", "")) == key
	var status := "今日尚未立誓。"
	if active_today:
		status = "今日誓约进行中，可从标题页继续。"
	elif played_today:
		status = "今日已尝试 %d 次，最佳 %d 分。" % [int(entry.get("attempts", 0)), int(entry.get("best", 0))]
	return {
		"key": key,
		"seed": int(setup.seed),
		"role": str(setup.role),
		"role_name": str(engine.role_data(str(setup.role)).get("name", "")),
		"oath": setup.oath_view,
		"modifier": setup.modifier,
		"attempts": int(entry.get("attempts", 0)),
		"best": int(entry.get("best", 0)),
		"best_role": str(entry.get("best_role", "")),
		"streak": int(entry.get("streak", 0)),
		"played_today": played_today,
		"active": active_today,
		"can_start": not bool(engine.state.get("active", false)),
		"status": status,
	}


static func start_daily_run(engine, daily_key: String = "") -> Dictionary:
	## Daily runs are seeded, oath-bound and share a fixed twist. The date can be
	## injected by tests; an empty key means today.
	var key: String = daily_key if not daily_key.is_empty() else Oaths.daily_key()
	if key.length() != 10 or not key.contains("-"):
		return engine._fail("日期格式应为 YYYY-MM-DD。")
	if bool(engine.state.get("active", false)):
		if bool(engine.state.get("daily", false)) and str(engine.state.get("daily_key", "")) == key:
			return engine._commit("继续今日的誓约。")
		return engine._fail("已有未完成旅程，请继续或先结束当前旅程。")
	var role_ids: Array = []
	for role in engine.data.get("roles", []):
		role_ids.append(str(role.id))
	var setup := Oaths.daily_setup(key, role_ids)
	var started: Dictionary = engine.new_run(str(setup.role), int(setup.seed), 0, "", str(setup.oath))
	if not bool(started.get("ok", false)):
		return started
	engine.state.modifiers = setup.modifiers.duplicate(true)
	engine.state.max_hp = Oaths.apply_max_hp(int(engine.role_data(str(engine.state.role)).get("max_hp", 80)), engine.state.modifiers)
	engine.state.hp = engine.state.max_hp
	engine.state.gold = maxi(0, int(engine.state.gold) + Oaths.value(engine.state.modifiers, "gold_flat") - Oaths.value(Oaths.modifiers_for(str(setup.oath)), "gold_flat"))
	engine.state.daily = true
	engine.state.daily_key = key
	engine.state.daily_modifier = str(setup.modifier.id)
	engine._log("每日誓约 · %s：%s，变体「%s」。" % [key, str(setup.oath_view.name), str(setup.modifier.name)])
	return engine._commit("每日誓约已开始。")


static func _finish_run(engine, victory: bool) -> void:
	engine.state.room = "victory" if victory else "defeat"
	engine.state.active = false
	if engine.state.encounter_kind in ["tutorial", "workshop"]:
		return
	if engine.state.get("history_recorded", false):
		return
	engine.state.history_recorded = true
	engine.state.score = Oaths.score(engine.state, victory)
	if bool(engine.state.get("daily", false)):
		engine._record_daily_run(victory)
	if victory:
		engine.profile.clears[engine.state.role] = int(engine.profile.clears.get(engine.state.role, 0)) + 1
		if int(engine.state.difficulty) >= 0:
			engine.profile.ascension[engine.state.role] = mini(MAX_DIFFICULTY, maxi(engine.unlocked_difficulty(str(engine.state.role)), int(engine.state.difficulty) + 1))
		engine._log("长夜退去。四章旅程完成！")
	else:
		engine._log("旅程结束。已经获得的解锁进度将永久保留。")
	engine.profile.history.push_front({"run_id": engine.state.run_id, "role": engine.state.role, "seed": engine.state.seed, "chapter": engine.state.chapter, "row": engine.state.row, "victory": victory, "difficulty": engine.state.difficulty, "turns": engine.state.elapsed_turns, "oath": engine.state.get("oath", ""), "score": int(engine.state.score), "daily": bool(engine.state.get("daily", false)), "date": Time.get_datetime_string_from_system()})
	while engine.profile.history.size() > 30:
		engine.profile.history.pop_back()


static func _record_daily_run(engine, victory: bool) -> void:
	## One attempt per finished daily journey. Best score, streak and a short
	## history are kept locally; no network leaderboard is involved.
	var key := str(engine.state.get("daily_key", ""))
	if key.is_empty():
		return
	var entry: Dictionary = engine.profile.get("daily", {}) if engine.profile.get("daily") is Dictionary else {}
	var result := {
		"key": key, "role": engine.state.role, "score": int(engine.state.score),
		"victory": victory, "oath": engine.state.get("oath", ""),
		"date": Time.get_datetime_string_from_system(),
	}
	entry.attempts = int(entry.get("attempts", 0)) + 1
	entry.key = key
	if int(result.score) > int(entry.get("best", 0)):
		entry.best = int(result.score)
		entry.best_role = str(engine.state.role)
		entry.best_oath = str(engine.state.get("oath", ""))
	if str(entry.get("last_key", "")) != key:
		entry.streak = int(entry.get("streak", 0)) + 1 if str(entry.get("last_key", "")) == Oaths.previous_day(key) else 1
		entry.last_key = key
	var history: Array = entry.get("history", []) if entry.get("history") is Array else []
	history.push_front(result)
	while history.size() > 20:
		history.pop_back()
	entry.history = history
	engine.profile.daily = entry


static func abandon_run(engine) -> Dictionary:
	if engine.state.active:
		engine._finish_run(false)
	engine.state = engine._blank_state()
	engine._random.clear()
	return engine._commit("已结束本局，永久解锁已保留。")


static func achievement_entries(engine) -> Array:
	return Progression.entries(engine.profile, engine.sacred_ids().size(), engine.data.get("cards", []).size())


static func update_setting(engine, key: String, value: Variant) -> Dictionary:
	match key:
		"music", "sound", "reduced_motion":
			if not value is bool:
				return engine._fail("设置值无效。")
		"music_volume", "sound_volume":
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
				return engine._fail("音量需要在 0 到 1 之间。")
		"combat_speed":
			if not (value is float or value is int) or value not in [1.0, 1.5, 2.0]:
				return engine._fail("动画速度无效。")
		_:
			return engine._fail("未知设置。")
	engine.profile.settings[key] = value
	return engine._commit("设置已保存。")


static func _migrate_progression(engine) -> void:
	var defaults = engine._new_profile()
	for section in ["settings", "stats"]:
		var merged: Dictionary = defaults[section].duplicate(true)
		if engine.profile.get(section) is Dictionary:
			merged.merge(engine.profile[section], true)
		engine.profile[section] = merged
	for key in ["music_volume", "sound_volume", "combat_speed"]:
		engine.profile.settings[key] = float(engine.profile.settings[key])
	if not engine.profile.get("achievements") is Dictionary:
		engine.profile.achievements = {}
	var daily: Dictionary = {"key": "", "attempts": 0, "best": 0, "best_role": "", "best_oath": "", "streak": 0, "last_key": "", "history": []}
	if engine.profile.get("daily") is Dictionary:
		daily.merge(engine.profile.daily, true)
	for field in ["attempts", "best", "streak"]:
		daily[field] = maxi(0, int(daily.get(field, 0)))
	if not daily.get("history") is Array:
		daily.history = []
	engine.profile.daily = daily
	var collected: Array = []
	for id in engine.profile.get("seen_cards", []):
		if not engine.card_data(str(id)).is_empty() and not collected.has(str(id)):
			collected.append(str(id))
	engine.profile.seen_cards = collected
	var sacred: Array = []
	var valid_sacred: Array = engine.sacred_ids()
	if engine.profile.get("sacred_collection") is Array:
		for id in engine.profile.sacred_collection:
			if valid_sacred.has(id) and not sacred.has(id):
				sacred.append(id)
	engine.profile.sacred_collection = sacred
	# Legacy saves have no detailed counters: keep them at zero rather than invent history.
	Progression.unlock(engine.profile, valid_sacred.size(), engine.data.get("cards", []).size())
