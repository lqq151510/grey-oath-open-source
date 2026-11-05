extends Control
## 尖塔读屏战斗；夜二+时长；Boss 半血阶段横幅/淡雾/召怪

var traveler: String = "灰烬卫"
var night_id: String = "night_1"
var player: Dictionary
var enemy: Dictionary
var energy: int = 3
var hand: Array = []
var draw_pile: Array = []
var discard: Array = []
var turn: int = 0
var started_hp: int = 70
var dmg_mult: float = 1.0
var phase_fired: Dictionary = {}
var summon_count: int = 0
var art_ui: Dictionary = {}
var art_phase: Dictionary = {}
var intent_px: int = 42
var powers: Dictionary = {}
var discards_this_turn: int = 0
var next_attack_bonus: int = 0

func _ready() -> void:
	AudioDirector.play_battle()
	$EndTurn.pressed.connect(_end_turn)
	_load_art()
	var pool := "pool_mid"
	var kind := "combat"
	var run_hp := -1
	var run_mhp := -1
	if FileAccess.file_exists("user://grey_oath_run.json"):
		var rd = JSON.parse_string(FileAccess.open("user://grey_oath_run.json", FileAccess.READ).get_as_text())
		if typeof(rd) == TYPE_DICTIONARY:
			traveler = str(rd.get("traveler", traveler))
			var n: int = int(rd.get("night", 1))
			if "current_night" in GameMeta and int(GameMeta.current_night) > n:
				n = int(GameMeta.current_night)
			night_id = "night_%d" % max(1, n)
			pool = str(rd.get("encounter_pool", pool))
			kind = str(rd.get("encounter_kind", kind))
			if kind == "elite":
				pool = "elite"
			elif kind == "boss":
				pool = "boss"
			run_hp = int(rd.get("hp", -1))
			run_mhp = int(rd.get("max_hp", -1))
	var mhp: int = run_mhp if run_mhp > 0 else GameRules.traveler_max_hp(traveler)
	var php: int = clampi(run_hp, 1, mhp) if run_hp > 0 else mhp
	player = {"hp": php, "max_hp": mhp, "block": 0, "light_shield": 0, "counter": 0, "strength": 0, "temp_strength": 0, "echo": 0}
	started_hp = php
	dmg_mult = float(GameRules.night_mult(night_id).get("damage", 1.0))
	var enc: Dictionary = GameRules.pick_encounter(pool, night_id)
	var ehp_raw = enc.get("hp", 36)
	var ehp: int = 0
	if typeof(ehp_raw) == TYPE_ARRAY:
		for v in ehp_raw:
			ehp += int(v)
	else:
		ehp = int(ehp_raw)
	var intents: Array = enc.get("intents", ["攻击 8", "格挡 10", "攻击 11"])
	# 精英/Boss：蓄力前强制亮 1 回合（表已含；运行时兜底插）
	if pool in ["elite", "boss"]:
		intents = _ensure_charge_telegraph(intents)
	var base_id := str(enc.get("base_id", enc.get("id", "")))
	if "__" in base_id:
		base_id = base_id.split("__")[0]
	enemy = {
		"name": str(enc.get("name", "雾狼")),
		"base_id": base_id,
		"hp": ehp,
		"max_hp": ehp,
		"block": 0,
		"poison": 0,
		"weak": 0,
		"vulnerable": 0,
		"ember": 0,
		"intents": intents,
		"ix": 0,
		"telegraph_charge": true,
		"kind": pool,
		"phases": enc.get("phases", GameRules.boss_phase_table(night_id).get("phases", [])),
		"art_phase2": false
	}
	GameMeta.note_combat_start()
	_build_deck()
	_ensure_enemy_status()
	_ensure_vignette()
	_ensure_run_hud()
	_apply_owned_powers()
	_apply_traveler_combat_start()
	_new_turn()

func _load_art() -> void:
	if FileAccess.file_exists("res://data/art_gameplay_ui.json"):
		art_ui = JSON.parse_string(FileAccess.open("res://data/art_gameplay_ui.json", FileAccess.READ).get_as_text())
	if FileAccess.file_exists("res://data/art_boss_phases.json"):
		art_phase = JSON.parse_string(FileAccess.open("res://data/art_boss_phases.json", FileAccess.READ).get_as_text())
	intent_px = 42
	if FileAccess.file_exists("res://data/art_card_shell_v071.json"):
		var shell = JSON.parse_string(FileAccess.open("res://data/art_card_shell_v071.json", FileAccess.READ).get_as_text())
		if typeof(shell) == TYPE_DICTIONARY:
			intent_px = int(shell.get("intent_font_px", 42))
	elif art_ui.has("readability"):
		intent_px = int(art_ui.get("readability", {}).get("intent_damage_font_px", 42))

func _ensure_charge_telegraph(intents: Array) -> Array:
	var out: Array = []
	for i in intents.size():
		var s: String = str(intents[i])
		if s.contains("蓄力") and (i == 0 or not str(intents[i - 1]).contains("蓄力") and not str(intents[i - 1]).contains("蓄力预告")):
			# 若蓄力本身不是「下回合」预告，前插一拍可见蓄力
			if not s.contains("下回合") and (out.is_empty() or not str(out.back()).contains("蓄力")):
				out.append("蓄力（下回合重击）")
		out.append(s)
	return out if out.size() else intents

func _ensure_vignette() -> void:
	# 夜二战斗底
	var bg_path := "res://assets/art/nights/night1_wasteland.png"
	if night_id == "night_2":
		bg_path = "res://assets/art/nights/night2_rustcity.png"
	elif int(night_id.replace("night_", "1")) >= 2:
		bg_path = "res://assets/art/nights/night2_rustcity.png"
	if ResourceLoader.exists(bg_path):
		var bg := TextureRect.new()
		bg.name = "NightBattleBg"
		bg.texture = load(bg_path)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.modulate = Color(1, 1, 1, 0.42)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg, 0)
	_setup_enemy_presentation()
	var path: String = str(art_phase.get("combat_vignette", "assets/art/ui/combat_vignette.png"))
	if path != "" and ResourceLoader.exists("res://" + path.trim_prefix("res://")):
		var tr := TextureRect.new()
		tr.name = "Vignette"
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.texture = load("res://" + path.trim_prefix("res://"))
		tr.modulate = Color(1, 1, 1, 0.55)
		add_child(tr)

func _enemy_art() -> Dictionary:
	## 优先美术 v0.9.4：enemies/<base_id>.png + 意图圆标 + 三档血条壳
	var out: Dictionary = {}
	if FileAccess.file_exists("res://data/art_enemies.json"):
		var legacy = JSON.parse_string(FileAccess.open("res://data/art_enemies.json", FileAccess.READ).get_as_text())
		if typeof(legacy) == TYPE_DICTIONARY:
			out = legacy
	if FileAccess.file_exists("res://data/art_monsters_v094.json"):
		var v = JSON.parse_string(FileAccess.open("res://data/art_monsters_v094.json", FileAccess.READ).get_as_text())
		if typeof(v) == TYPE_DICTIONARY:
			out["version"] = v.get("version", "0.9.4")
			out["enemies"] = v.get("enemies", {})
			out["intent_icons"] = v.get("intents", out.get("intent_icons", {}))
			out["hp_shells"] = v.get("hp_shells", {})
			out["portrait_dir"] = "assets/art/enemies/"
			out["style"] = v.get("style", "")
	return out

func _art_base_alias(base_id: String) -> String:
	var aliases := {
		"mist_pair": "twin_shade",
		"pinch_pair": "twin_shade",
		"fog_beast": "mist_beast",
		"rot_crow": "carrion_crow",
		"bandit": "road_bandit",
		"rust_crow": "carrion_crow"
	}
	return str(aliases.get(base_id, base_id))

func _enemy_silhouette_path(nm: String, base_id: String = "", phase2: bool = false) -> String:
	var art: Dictionary = _enemy_art()
	var enemies: Dictionary = art.get("enemies", {})
	var bid := base_id
	if bid == "":
		bid = str(enemy.get("base_id", "")) if typeof(enemy) == TYPE_DICTIONARY else ""
	bid = _art_base_alias(bid)
	var suffix := "_p2" if phase2 else ""
	# 1) 直挂 enemies/<base_id>[_p2].png
	if bid != "":
		var direct := "res://assets/art/enemies/%s%s.png" % [bid, suffix]
		if ResourceLoader.exists(direct):
			return direct
		# 索引 path（phase2 时仍尝试 _p2 旁路）
		if enemies.has(bid):
			var ep: String = str(enemies[bid].get("path", ""))
			if phase2:
				var p2try := ep.replace(".png", "_p2.png")
				var rp2 := "res://" + p2try.trim_prefix("res://")
				if ResourceLoader.exists(rp2):
					return rp2
			elif ep != "":
				var rp := "res://" + ep.trim_prefix("res://")
				if ResourceLoader.exists(rp):
					return rp
		# 兼容旧文件名别名
		var file_alias := {
			"carrion_crow": "rot_crow",
			"road_bandit": "bandit",
			"mist_beast": "fog_beast",
			"twin_shade": "twin_shade"
		}
		if file_alias.has(bid):
			var alt := "res://assets/art/enemies/%s%s.png" % [str(file_alias[bid]), suffix]
			if ResourceLoader.exists(alt):
				return alt
	# 2) 中文名索引（旧 art_enemies.by_name → bosses/ 兜底）
	var by: Dictionary = art.get("by_name", {})
	for k in by.keys():
		if nm.contains(str(k)):
			var fn: String = str(by[k])
			if phase2:
				fn = fn.replace(".png", "_p2.png")
			var p_en := "res://assets/art/enemies/%s" % fn
			if ResourceLoader.exists(p_en):
				return p_en
			var p_bo := "res://assets/art/bosses/%s" % fn
			if ResourceLoader.exists(p_bo):
				return p_bo
	var m := {
		"锈鼠": "rust_rat.png", "废铁卫": "scrap_guard.png", "夹击锈鸦": "rust_crow.png", "锈鸦": "rust_crow.png",
		"油溅虫": "oil_spitter.png", "锈刃百夫": "rust_captain.png", "熔渣心核": "slag_heart.png",
		"雾行兽": "mist_beast.png", "雾狼": "fog_wolf.png", "雾首狼": "fog_alpha.png", "雾魁": "fog_alpha.png",
		"腐鸦": "carrion_crow.png", "路匪": "road_bandit.png", "雾中双影": "twin_shade.png", "双影": "twin_shade.png"
	}
	for k in m.keys():
		if nm.contains(k):
			var fn2: String = str(m[k])
			if phase2:
				fn2 = fn2.replace(".png", "_p2.png")
			var pe := "res://assets/art/enemies/%s" % fn2
			if ResourceLoader.exists(pe):
				return pe
			var pb := "res://assets/art/bosses/%s" % fn2
			if ResourceLoader.exists(pb):
				return pb
	return ""

func _setup_enemy_presentation() -> void:
	var art: Dictionary = _enemy_art()
	var kind := str(enemy.get("kind", "normal"))
	var ring_key := "boss" if kind == "boss" else ("elite" if kind == "elite" else "normal")
	var ring_path := "res://" + str(art.get("rings", {}).get(ring_key, "assets/art/ui/enemy_ring_%s.png" % ring_key))
	var shadow_path := "res://" + str(art.get("shadow", "assets/art/ui/enemy_ground_shadow.png"))
	var base := Vector2(860, 90)
	if ResourceLoader.exists(shadow_path):
		var sh := TextureRect.new()
		sh.name = "EnemyShadow"
		sh.texture = load(shadow_path)
		sh.position = base + Vector2(40, 430)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sh)
	if ResourceLoader.exists(ring_path):
		var rg := TextureRect.new()
		rg.name = "EnemyRing"
		rg.texture = load(ring_path)
		rg.position = base + Vector2(-20, -10)
		rg.custom_minimum_size = Vector2(360, 360)
		rg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rg.modulate = Color(1, 1, 1, 0.85)
		add_child(rg)
	var sil := _enemy_silhouette_path(str(enemy.get("name", "")), str(enemy.get("base_id", "")), false)
	if sil != "" and ResourceLoader.exists(sil):
		var es := TextureRect.new()
		es.name = "EnemySilhouette"
		es.texture = load(sil)
		es.position = base + Vector2(20, 20)
		es.custom_minimum_size = Vector2(300, 300)
		es.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		es.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		es.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(es)
		var tw := create_tween().set_loops()
		tw.tween_property(es, "position:y", es.position.y - 6.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(es, "position:y", es.position.y + 6.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 三档血条壳（normal/elite/boss）+ 旧 fill 兼容
	var shells: Dictionary = art.get("hp_shells", {})
	var shell_p := "res://" + str(shells.get(ring_key, art.get("hp_bar", {}).get("bg", "assets/art/ui/enemy_hp_bar_bg.png")))
	if ResourceLoader.exists(shell_p):
		var hpbg := TextureRect.new()
		hpbg.name = "EnemyHpBarBg"
		hpbg.texture = load(shell_p)
		hpbg.position = Vector2(900, 470)
		hpbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hpbg)
	var fill_p := "res://" + str(art.get("hp_bar", {}).get("fill", "assets/art/ui/enemy_hp_bar_fill.png"))
	if ResourceLoader.exists(fill_p):
		var fill := TextureRect.new()
		fill.name = "EnemyHpBarFill"
		fill.texture = load(fill_p)
		fill.position = Vector2(902, 472)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
	_refresh_enemy_hp_bar()
	_refresh_intent_badge()

func _swap_enemy_portrait_phase2() -> void:
	if bool(enemy.get("art_phase2", false)):
		return
	var sil := _enemy_silhouette_path(str(enemy.get("name", "")), str(enemy.get("base_id", "")), true)
	if sil == "" or not ResourceLoader.exists(sil):
		return
	var es := get_node_or_null("EnemySilhouette")
	if es == null:
		return
	es.texture = load(sil)
	enemy["art_phase2"] = true

func _intent_kind(raw: String) -> String:
	if raw.contains("毒"):
		return "poison"
	if raw.contains("蓄力"):
		return "charge"
	if raw.contains("召唤"):
		return "summon"
	if raw.contains("逃跑") or raw.contains("遁"):
		return "escape"
	if raw.contains("攻击") or raw.contains("重击"):
		if raw.contains("×") or raw.contains("x") or raw.contains("次"):
			return "attack_multi"
		return "attack"
	if raw.contains("格挡") or raw.contains("防御"):
		return "defend"
	if raw.contains("强化") or raw.contains("力量") or raw.contains("增益"):
		return "buff"
	if raw.contains("虚弱") or raw.contains("易伤") or raw.contains("减益"):
		return "debuff"
	return "unknown"

func _intent_number(raw: String) -> String:
	var rx := RegEx.new()
	rx.compile("(\\d+)")
	var m := rx.search(raw)
	return m.get_string(1) if m else ""

func _refresh_intent_badge() -> void:
	var art: Dictionary = _enemy_art()
	var icons: Dictionary = art.get("intent_icons", {})
	var raw := _intent_text()
	var kind := _intent_kind(raw)
	var ipath := "res://" + str(icons.get(kind, icons.get("unknown", "assets/art/ui/intent_unknown.png")))
	var badge := get_node_or_null("IntentBadge")
	if badge == null:
		badge = Control.new()
		badge.name = "IntentBadge"
		badge.position = Vector2(820, 70)
		add_child(badge)
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.custom_minimum_size = Vector2(64, 64)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(ic)
		var num := Label.new()
		num.name = "Num"
		num.position = Vector2(70, 8)
		num.add_theme_font_size_override("font_size", 36)
		num.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
		badge.add_child(num)
	var icn: TextureRect = badge.get_node("Icon")
	if ResourceLoader.exists(ipath):
		icn.texture = load(ipath)
	var nlab: Label = badge.get_node("Num")
	nlab.text = _intent_number(raw)
	# 尖塔读屏：左图标右大数；文字意图仍保留在 Intent 节点
	if has_node("Intent"):
		$Intent.add_theme_font_size_override("font_size", 18)
		$Intent.modulate = Color(0.85, 0.85, 0.88, 0.9)

func _refresh_enemy_hp_bar() -> void:
	var fill := get_node_or_null("EnemyHpBarFill")
	if fill == null:
		return
	var pct: float = float(enemy.get("hp", 0)) / max(1.0, float(enemy.get("max_hp", 1)))
	fill.scale = Vector2(maxi(0.02, pct), 1.0)

func _ensure_enemy_status() -> void:
	if not enemy.has("weak"):
		enemy["weak"] = 0
	if not enemy.has("vulnerable"):
		enemy["vulnerable"] = 0
	if not enemy.has("poison"):
		enemy["poison"] = 0
	if not enemy.has("block"):
		enemy["block"] = 0

func _build_deck() -> void:
	if GameMeta.run_deck.size() > 0:
		for c in GameMeta.run_deck:
			draw_pile.append(c.duplicate(true))
		draw_pile.shuffle()
		return
	var cards = GameMeta.cards_data
	for i in 5:
		draw_pile.append(cards["common"][0].duplicate())
	for i in 4:
		draw_pile.append(cards["common"][1].duplicate())
	for c in cards["travelers"][traveler]["cards"]:
		if c.get("rarity") == "starter":
			draw_pile.append(c.duplicate())
			GameMeta.unlock_card(c.get("id", ""))
	draw_pile.shuffle()

func _new_turn() -> void:
	turn += 1
	discards_this_turn = 0
	powers.erase("suppress_card_hp_loss")
	energy = GameRules.energy_per_turn()
	_apply_turn_start_powers()
	while hand.size() < GameRules.draw_per_turn():
		if draw_pile.is_empty():
			draw_pile = discard.duplicate()
			discard.clear()
			draw_pile.shuffle()
		if draw_pile.is_empty():
			break
		hand.append(draw_pile.pop_back())
	_refresh()

func _intent_text() -> String:
	return str(enemy["intents"][enemy["ix"] % enemy["intents"].size()])

func _refresh() -> void:
	_refresh_potions()
	_refresh_intent_badge()
	_refresh_enemy_hp_bar()
	var it := _intent_text()
	var charge := it.contains("蓄力")
	$Intent.text = "意图  %s" % it
	$Intent.add_theme_font_size_override("font_size", (intent_px + 6) if charge else intent_px)
	_update_charge_ring(charge)
	$EnemyHP.text = "%s  HP %d/%d  盾%d 毒%d 弱%d 伤%d 烬%d" % [enemy["name"], enemy["hp"], enemy["max_hp"], enemy["block"], enemy["poison"], int(enemy.get("weak", 0)), int(enemy.get("vulnerable", 0)), int(enemy.get("ember", 0))]
	$PlayerHP.text = "%s  HP %d/%d  盾%d 光盾%d 反击%d 回响%d" % [traveler, player["hp"], player["max_hp"], player["block"], player["light_shield"], player["counter"], int(player.get("echo", 0))]
	$Energy.text = "费 %d/%d   抽%d 弃%d · %s" % [energy, GameRules.energy_per_turn(), draw_pile.size(), discard.size(), night_id]
	for c in $Hand.get_children():
		c.queue_free()
	for i in hand.size():
		var card: Dictionary = hand[i]
		var b := Button.new()
		b.text = "(%d) %s\n%s" % [card.get("cost", 0), card.get("name", ""), card.get("text", "")]
		b.custom_minimum_size = Vector2(160, 110)
		var idx := i
		b.pressed.connect(func(): _play(idx))
		$Hand.add_child(b)

func _play(idx: int) -> void:
	if idx < 0 or idx >= hand.size():
		return
	var card: Dictionary = hand[idx]
	var cost := int(card.get("cost", 0))
	if energy < cost:
		return
	energy -= cost
	AudioDirector.sfx_card_play()
	FxQueue.play_card()
	GameMeta.unlock_card(card.get("id", ""))
	hand.remove_at(idx)
	_resolve_card(card)
	var exhaust_it := bool(card.get("exhaust", false)) or bool(card.get("exhaust_self", false)) or str(card.get("type", "")) == "能力"
	if not exhaust_it:
		discard.append(card)
	_check_boss_phase()
	_check_light_threshold()
	_refresh()
	if enemy["hp"] <= 0:
		_win()

func _flash_hit() -> void:
	var path := "res://assets/art/vfx/hit_flash.png"
	if not ResourceLoader.exists(path):
		return
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.position = Vector2(900, 120)
	tr.modulate = Color(1, 0.35, 0.3, 0.85)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	var tw := create_tween()
	tw.tween_property(tr, "modulate:a", 0.0, 0.22)
	tw.tween_callback(tr.queue_free)

func _tonk_block() -> void:
	var path := "res://assets/art/vfx/block.png"
	if not ResourceLoader.exists(path):
		return
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.position = Vector2(80, 420)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	var tw := create_tween()
	tw.tween_property(tr, "modulate:a", 0.0, 0.28)
	tw.tween_callback(tr.queue_free)

func _damage_enemy(dmg: int) -> void:
	var d := float(dmg)
	if int(enemy.get("vulnerable", 0)) > 0:
		d *= 1.5
	var di := int(round(d))
	var b: int = int(enemy.get("block", 0))
	var use = mini(b, di)
	enemy["block"] = b - use
	enemy["hp"] -= max(0, di - use)

func _check_boss_phase() -> void:
	if str(enemy.get("kind", "")) != "boss":
		return
	var phases: Array = enemy.get("phases", [])
	if phases.is_empty():
		phases = GameRules.boss_phase_table(night_id).get("phases", [])
	var pct: float = 100.0 * float(enemy["hp"]) / max(1.0, float(enemy["max_hp"]))
	for ph in phases:
		var pid: String = str(ph.get("id", ""))
		if phase_fired.get(pid, false):
			continue
		var atp: float = float(ph.get("at_hp_percent", 100))
		if atp >= 100.0:
			continue
		if pct <= atp + 0.01:
			phase_fired[pid] = true
			_trigger_phase(ph)

func _trigger_phase(ph: Dictionary) -> void:
	_swap_enemy_portrait_phase2()
	var gain: int = int(ph.get("gain_block", 0))
	if gain > 0:
		enemy["block"] = int(enemy.get("block", 0)) + gain
	# 横幅
	var banner_id: String = str(ph.get("banner", ""))
	var banners: Dictionary = art_phase.get("boss_phases", {})
	var bpath: String = str(banners.get(banner_id, ""))
	if bpath != "":
		var res := "res://" + bpath.trim_prefix("res://")
		if ResourceLoader.exists(res):
			var tr := TextureRect.new()
			tr.name = "PhaseBanner"
			tr.texture = load(res)
			tr.position = Vector2(360, 40)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tr)
			var tw := create_tween()
			tw.tween_interval(1.4)
			tw.tween_property(tr, "modulate:a", 0.0, 0.35)
			tw.tween_callback(tr.queue_free)
	if bool(ph.get("wave_fog", false)):
		var fog: String = str(banners.get("wave_fog_soft", "assets/art/vfx/wave_fog_soft.png"))
		var fres := "res://" + fog.trim_prefix("res://")
		if ResourceLoader.exists(fres):
			var fr := TextureRect.new()
			fr.texture = load(fres)
			fr.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			fr.offset_top = -120
			fr.modulate = Color(1, 1, 1, 0.7)
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(fr)
			var tw2 := create_tween()
			tw2.tween_interval(1.0)
			tw2.tween_property(fr, "modulate:a", 0.0, 0.5)
			tw2.tween_callback(fr.queue_free)
	# 召怪钩子：半血再召 — 本壳用加敌方最大生命+当前生命模拟「多体血条」
	var sm = ph.get("summon", {})
	if typeof(sm) == TYPE_DICTIONARY and sm.has("id"):
		var max_total: int = int(sm.get("max_total", 2))
		if summon_count < max_total:
			summon_count += int(sm.get("count", 1))
			var add_hp := 42
			enemy["max_hp"] = int(enemy["max_hp"]) + add_hp
			enemy["hp"] = int(enemy["hp"]) + add_hp
			if has_node("Log"):
				$Log.text = "阶段：%s · 召 %s" % [str(ph.get("name", "")), str(sm.get("id", ""))]

func _end_turn() -> void:
	if enemy["poison"] > 0:
		enemy["hp"] -= enemy["poison"]
		enemy["poison"] = max(0, enemy["poison"] - 1)
		_check_boss_phase()
	if enemy["hp"] <= 0:
		_win()
		return
	var keep_hand: Array = []
	for c in hand:
		if bool(c.get("ethereal", false)):
			pass  # 消耗，不进弃牌
		else:
			keep_hand.append(c)
	discard.append_array(keep_hand)
	hand.clear()
	var raw: String = _intent_text()
	var rbx := RegEx.new()
	rbx.compile("格挡\\s*(\\d+)")
	var mb := rbx.search(raw)
	if mb:
		enemy["block"] = int(enemy.get("block", 0)) + int(mb.get_string(1))
	var rx := RegEx.new()
	rx.compile("攻击\\s*(\\d+)")
	var m := rx.search(raw)
	if m:
		var dmg := int(round(float(m.get_string(1)) * dmg_mult))
		if int(enemy.get("weak", 0)) > 0:
			dmg = int(round(float(dmg) * 0.75))
		var remain := dmg
		var ls: int = int(player["light_shield"])
		var use_ls = mini(ls, remain)
		player["light_shield"] = ls - use_ls
		remain -= use_ls
		var blk: int = int(player["block"])
		var use_b = mini(blk, remain)
		player["block"] = blk - use_b
		remain -= use_b
		if remain > 0:
			player["hp"] -= remain
			_flash_hit()
		if remain > 0 and int(player["counter"]) > 0:
			enemy["hp"] -= int(player["counter"])
			_check_boss_phase()
	GameRules.end_of_player_turn(player)
	if int(enemy.get("weak", 0)) > 0:
		enemy["weak"] = int(enemy["weak"]) - 1
	if int(enemy.get("vulnerable", 0)) > 0:
		enemy["vulnerable"] = int(enemy["vulnerable"]) - 1
	enemy["ix"] = int(enemy["ix"]) + 1
	if player["hp"] <= 0:
		$Log.text = "战败"
		await get_tree().create_timer(1.2).timeout
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if enemy["hp"] <= 0:
		_win()
		return
	_new_turn()

func _win() -> void:
	GameRules.apply_post_combat_heal(player, traveler)
	if FileAccess.file_exists("user://grey_oath_run.json"):
		var rd = JSON.parse_string(FileAccess.open("user://grey_oath_run.json", FileAccess.READ).get_as_text())
		if typeof(rd) != TYPE_DICTIONARY:
			rd = {}
		rd["hp"] = int(player["hp"])
		rd["max_hp"] = int(player["max_hp"])
		FileAccess.open("user://grey_oath_run.json", FileAccess.WRITE).store_string(JSON.stringify(rd))
	GameMeta.enemies_killed += 1
	GameMeta.grant_achievement("first_victory")
	if str(enemy.get("name", "")).contains("熔渣") or str(enemy.get("name", "")).contains("雾行"):
		GameMeta.grant_achievement("boss_mist")
	if player["hp"] >= started_hp:
		GameMeta.grant_achievement("no_damage_fight")
	GameMeta.save_meta()
	get_tree().change_scene_to_file("res://scenes/reward.tscn")

func _refresh_potions() -> void:
	var bar: HBoxContainer = get_node_or_null("PotionBar")
	if bar == null:
		bar = HBoxContainer.new()
		bar.name = "PotionBar"
		bar.position = Vector2(40, 8)
		add_child(bar)
	for c in bar.get_children():
		c.queue_free()
	var slots: int = int(GameMeta.potions_data.get("slots", 3))
	for i in range(slots):
		var b := Button.new()
		b.custom_minimum_size = Vector2(72, 28)
		if i < GameMeta.potions_owned.size():
			var pid: String = str(GameMeta.potions_owned[i])
			b.text = "⚗"
			b.tooltip_text = pid + "（点击使用，不占能量）"
			var slot := i
			b.pressed.connect(func(): _use_potion(slot))
		else:
			b.text = "·"
			b.disabled = true
		bar.add_child(b)

func _use_potion(slot: int) -> void:
	if GameMeta.drink_potion(slot, player, enemy):
		if player.get("bonus_energy", 0):
			energy += int(player["bonus_energy"])
			player["bonus_energy"] = 0
		_check_boss_phase()
		if int(enemy.get("hp", 1)) <= 0:
			_win()
			return
		_refresh()


func _update_charge_ring(on: bool) -> void:
	var ring := get_node_or_null("ChargeRing")
	var path := "res://assets/art/vfx/charge_telegraph.png"
	if not on:
		if ring: ring.visible = false
		return
	if ring == null and ResourceLoader.exists(path):
		ring = TextureRect.new()
		ring.name = "ChargeRing"
		ring.texture = load(path)
		ring.position = Vector2(920, 200)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ring)
	if ring:
		ring.visible = true


func _resolve_card(card: Dictionary) -> void:
	# 尖塔式字段：条件伤/盾、能力钩子；不改表内数字
	card = _apply_bridge_penalty(card)
	if card.has("self_damage") and not powers.get("suppress_card_hp_loss", false):
		var lost := int(card["self_damage"])
		player["hp"] -= lost
		_on_hp_loss_from_card(lost)
	# 力量
	var str_b: int = int(player.get("strength", 0))
	var dmg := 0
	if card.has("damage") and str(card.get("effect", "")) not in ["optional_consume_all_poison_for_2_each", "spend_all_block_as_damage", "spend_all_light_shield_damage_2_each"]:
		dmg = int(card["damage"]) + str_b + next_attack_bonus
		next_attack_bonus = 0
	if card.has("bonus_if_block") and int(player.get("block", 0)) > 0:
		dmg += int(card["bonus_if_block"])
	if card.has("bonus_if_curse_in_hand") and _hand_has_curse():
		dmg += int(card["bonus_if_curse_in_hand"])
	var light_bonus_hit := 0
	if card.has("bonus_if_light_shield_gte"):
		var thr = card["bonus_if_light_shield_gte"]
		if typeof(thr) == TYPE_ARRAY and thr.size() >= 2:
			if int(player.get("light_shield", 0)) >= int(thr[0]):
				light_bonus_hit = int(thr[1]) + str_b
	if str(card.get("damage_from", "")) == "current_block":
		dmg = int(player.get("block", 0)) + str_b
	elif str(card.get("damage_from", "")) == "current_block_plus_3":
		dmg = int(player.get("block", 0)) + 3 + str_b
	elif str(card.get("damage_from", "")) == "block_half_ceil_keep":
		dmg = int(card.get("damage", 0)) + int(ceil(float(player.get("block", 0)) / 2.0)) + str_b
	var discard_hits := 0
	if bool(card.get("discard_any", false)) and card.has("damage_per_discard"):
		discard_hits = hand.size()
		_discard_n(discard_hits)
		var per := int(card["damage_per_discard"]) + str_b
		for _i in range(discard_hits):
			_damage_enemy(per)
		AudioDirector.sfx_hit()
		_flash_hit()
	elif card.has("damage_per_discard"):
		var nd := int(card.get("discard", 0))
		_discard_n(nd)
		dmg = int(card.get("damage", dmg)) + str_b + nd * int(card["damage_per_discard"])
		if dmg > 0:
			_damage_enemy(dmg)
			AudioDirector.sfx_hit()
			_flash_hit()
	elif dmg > 0:
		var hits := maxi(1, int(card.get("hits", 1)))
		for _h in range(hits):
			_damage_enemy(dmg)
		if light_bonus_hit > 0:
			_damage_enemy(light_bonus_hit)
		AudioDirector.sfx_hit()
		FxQueue.play_hit()
		FxQueue.play_dmg()
		_flash_hit()
		if card.has("splash_if_block") and int(player.get("block", 0)) > 0:
			_damage_enemy(int(card["splash_if_block"]))
	if card.has("block"):
		var blk_gain := int(card["block"])
		if str(card.get("type", "")) == "技能":
			if powers.get("skill_block_bonus_2", false):
				blk_gain += 2
			elif powers.get("skill_block_bonus_3", false):
				blk_gain += 3
		player["block"] += blk_gain
		AudioDirector.sfx_block()
		FxQueue.play_block()
		_tonk_block()
		if str(powers.get("on_gain_block_counter_1", "")) != "" or powers.get("on_gain_block_counter_1", false):
			player["counter"] = int(player.get("counter", 0)) + 1
	if bool(card.get("clear_block", false)):
		player["block"] = 0
	if card.has("counter"):
		player["counter"] += int(card["counter"])
	if card.has("counter_if_has_counter") and int(player.get("counter", 0)) > 0:
		player["counter"] += int(card["counter_if_has_counter"])
	if card.has("poison"):
		enemy["poison"] += int(card["poison"])
	if card.has("light_shield"):
		player["light_shield"] += int(card["light_shield"])
		_check_light_threshold()
	if card.has("draw"):
		_draw_cards(int(card["draw"]))
	if card.has("draw_if_block") and int(player.get("block", 0)) > 0:
		_draw_cards(int(card["draw_if_block"]))
	if card.has("draw_if_counter") and int(player.get("counter", 0)) > 0:
		_draw_cards(int(card["draw_if_counter"]))
	if card.has("next_attack_bonus_if_block") and int(player.get("block", 0)) > 0:
		next_attack_bonus += int(card["next_attack_bonus_if_block"])
	# 弃牌类（自动弃抽牌顶，避免 UI 点选）
	if card.has("discard_upto"):
		var n := mini(int(card["discard_upto"]), hand.size())
		_discard_n(n)
		if card.has("energy_per_discard"):
			energy += n * int(card["energy_per_discard"])
	if bool(card.get("discard_any", false)) and not card.has("damage_per_discard"):
		var n2 := hand.size()
		_discard_n(n2)
		if card.has("draw_per_discard"):
			_draw_cards(n2 * int(card["draw_per_discard"]))
	elif card.has("discard") and not card.has("damage_per_discard"):
		_discard_n(int(card["discard"]))
	# 反协同/特殊 effect
	var eff := str(card.get("effect", ""))
	if eff == "spend_echo_3_bonus_damage":
		if int(player.get("echo", 0)) >= 3:
			player["echo"] = int(player["echo"]) - 3
			_damage_enemy(int(card.get("bonus_spend_echo", 0)) + int(player.get("strength", 0)))
	elif eff == "spend_echo_3_bonus_block":
		if int(player.get("echo", 0)) >= 3:
			player["echo"] = int(player["echo"]) - 3
			player["block"] = int(player.get("block", 0)) + int(card.get("bonus_spend_echo", 0))
	elif eff == "ignite_ember_damage_2_each":
		var em := int(enemy.get("ember", 0))
		enemy["ember"] = 0
		_damage_enemy(em * 2 + int(player.get("strength", 0)))
		_flash_hit()
	if eff == "add_shivs_to_hand":
		var nsh := int(card.get("count", 1))
		_add_shivs(nsh, str(card.get("shiv_id", "shade_shiv")))
	if card.has("hp_loss") and not powers.get("suppress_card_hp_loss", false):
		var lost2 := int(card["hp_loss"])
		player["hp"] -= lost2
		_on_hp_loss_from_card(lost2)
	if card.has("energy"):
		energy += int(card["energy"])
	if card.has("temp_strength"):
		var ts := int(card["temp_strength"])
		player["strength"] = int(player.get("strength", 0)) + ts
		player["temp_strength"] = int(player.get("temp_strength", 0)) + ts
	if card.has("exhaust_random_hand"):
		_exhaust_random(int(card["exhaust_random_hand"]))
	if card.has("echo"):
		player["echo"] = int(player.get("echo", 0)) + int(card["echo"])
	if card.has("ember"):
		enemy["ember"] = int(enemy.get("ember", 0)) + int(card["ember"])
	if int(GameMeta.cards_data.get("travelers", {}).get(traveler, {}).get("passive", {}).get("attacks_apply_ember", 0)) > 0 and str(card.get("type","")) == "攻击":
		enemy["ember"] = int(enemy.get("ember", 0)) + int(GameMeta.cards_data["travelers"][traveler]["passive"]["attacks_apply_ember"])
	if card.has("apply_weak"):
		enemy["weak"] = int(enemy.get("weak", 0)) + int(card["apply_weak"])
	if card.has("apply_vulnerable"):
		enemy["vulnerable"] = int(enemy.get("vulnerable", 0)) + int(card["apply_vulnerable"])
	if eff == "exhaust_curse_gain_energy_draw":
		if _exhaust_one_curse():
			energy += int(card.get("energy", 1))
			_draw_cards(int(card.get("draw", 1)))
	elif eff == "exhaust_curse_bonus_damage":
		if _exhaust_one_curse():
			_damage_enemy(int(card.get("bonus_exhaust_curse", 0)) + int(player.get("strength", 0)))
	if eff == "spend_all_block_as_damage":
		var blk := int(player.get("block", 0))
		player["block"] = 0
		_damage_enemy(blk + int(player.get("strength", 0)))
		AudioDirector.sfx_hit()
		_flash_hit()
		if bool(card.get("clear_counter", false)):
			player["counter"] = 0
	elif eff == "optional_consume_all_poison_for_2_each":
		var ps := int(enemy.get("poison", 0))
		enemy["poison"] = 0
		_damage_enemy(int(card.get("damage", 0)) + ps * 2 + int(player.get("strength", 0)))
		_flash_hit()
	elif eff == "spend_all_light_shield_damage_2_each":
		var ls := int(player.get("light_shield", 0))
		player["light_shield"] = 0
		_damage_enemy(ls * 2 + int(player.get("strength", 0)))
		_flash_hit()
	if card.has("heal"):
		player["hp"] = mini(int(player["max_hp"]), int(player["hp"]) + int(card["heal"]))
	if str(card.get("power_this_turn", "")) == "suppress_card_hp_loss":
		powers["suppress_card_hp_loss"] = true
	# 能力
	if card.has("power"):
		var pid := str(card["power"])
		powers[pid] = true
		var pen = card.get("penalty", {})
		if typeof(pen) == TYPE_DICTIONARY and str(pen.get("while_owned", "")) == "halve_bridge_numeric_effects":
			powers["halve_bridge_numeric_effects"] = true

func _on_hp_loss_from_card(amount: int) -> void:
	if amount <= 0:
		return
	if powers.get("on_card_hp_loss_gain_strength_1", false):
		player["strength"] = int(player.get("strength", 0)) + 1

func _discard_n(n: int) -> void:
	for i in range(n):
		if hand.is_empty():
			break
		var c: Dictionary = hand.pop_back()
		discard.append(c)
		discards_this_turn += 1
		# 弃影宗：前 2 次弃牌抽 1
		if powers.get("on_discard_draw_1_max_2_per_turn", false) and discards_this_turn <= 2:
			_draw_cards(1)
		elif powers.get("on_discard_draw_1_max_3_per_turn", false) and discards_this_turn <= 3:
			_draw_cards(1)

func _draw_cards(n: int) -> void:
	for i in range(n):
		if draw_pile.is_empty():
			draw_pile = discard.duplicate()
			discard.clear()
			draw_pile.shuffle()
		if draw_pile.is_empty():
			break
		hand.append(draw_pile.pop_back())


func _apply_bridge_penalty(card: Dictionary) -> Dictionary:
	var cc: Dictionary = card.duplicate(true)
	if str(cc.get("branch", "")) != "bridge":
		return cc
	if not _has_halve_bridge_penalty():
		return cc
	for k in ["damage", "block", "counter", "poison", "draw", "bonus_if_block", "splash_if_block", "light_shield"]:
		if cc.has(k) and typeof(cc[k]) in [TYPE_INT, TYPE_FLOAT]:
			cc[k] = int(ceil(float(cc[k]) * 0.5))
	return cc

func _has_halve_bridge_penalty() -> bool:
	for c in GameMeta.run_deck:
		var pen = c.get("penalty", {})
		if typeof(pen) == TYPE_DICTIONARY and str(pen.get("while_owned", "")) == "halve_bridge_numeric_effects":
			return true
	# 已打出的能力
	if powers.get("halve_bridge_numeric_effects", false):
		return true
	return false

func _apply_owned_powers() -> void:
	for c in GameMeta.run_deck:
		if c.has("power") and str(c.get("type", "")) == "能力":
			# 仅永久向：进战斗生效的稀有偏科
			var pid := str(c["power"])
			powers[pid] = true
			var pen = c.get("penalty", {})
			if typeof(pen) == TYPE_DICTIONARY and str(pen.get("while_owned", "")) == "halve_bridge_numeric_effects":
				powers["halve_bridge_numeric_effects"] = true

func _ensure_run_hud() -> void:
	var path := "res://assets/art/ui/run_top_hud_sts.png"
	if get_node_or_null("RunHud") == null and ResourceLoader.exists(path):
		var hud := TextureRect.new()
		hud.name = "RunHud"
		hud.texture = load(path)
		hud.position = Vector2(0, 0)
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hud)
		move_child(hud, 0)
	# 顶栏数字：金 / 层 / 抽弃
	var lab := get_node_or_null("HudStats")
	if lab == null:
		lab = Label.new()
		lab.name = "HudStats"
		lab.position = Vector2(200, 6)
		lab.add_theme_font_size_override("font_size", 16)
		add_child(lab)
	var floor_n := 0
	if FileAccess.file_exists("user://grey_oath_run.json"):
		var rd = JSON.parse_string(FileAccess.open("user://grey_oath_run.json", FileAccess.READ).get_as_text())
		if typeof(rd) == TYPE_DICTIONARY:
			floor_n = int(rd.get("floor", 0))
	lab.text = "金 %d · 层 %d · 药 %d/3 · 抽%d 弃%d" % [GameMeta.gold, floor_n, GameMeta.potions_owned.size(), draw_pile.size(), discard.size()]


func _add_shivs(n: int, shiv_id: String = "shade_shiv") -> void:
	var sid := shiv_id if shiv_id != "" else "shade_shiv"
	var proto: Dictionary = GameMeta.card_by_id(sid)
	if proto.is_empty():
		proto = GameMeta.card_by_id("shade_shiv")
	if proto.is_empty():
		proto = {"id": sid, "name": "火花", "type": "攻击", "cost": 0, "damage": 4, "exhaust_self": true, "text": "造成 4 点伤害。消耗。"}
	for i in range(n):
		hand.append(proto.duplicate(true))

func _exhaust_random(n: int) -> void:
	for i in range(n):
		if hand.is_empty():
			break
		var ix := randi() % hand.size()
		hand.remove_at(ix)

func _apply_turn_start_powers() -> void:
	if powers.get("turn_start_block_3", false):
		player["block"] = int(player.get("block", 0)) + 3
	if powers.get("turn_start_block_4", false):
		player["block"] = int(player.get("block", 0)) + 4
	if powers.get("turn_start_hp_loss_1_energy_1", false):
		player["hp"] = int(player["hp"]) - 1
		energy += 1
		_on_hp_loss_from_card(1)

func _check_light_threshold() -> void:
	if powers.get("enter_light_threshold_5_strength_2", false) and not powers.get("_lit_thr_fired", false):
		if int(player.get("light_shield", 0)) >= 5:
			player["strength"] = int(player.get("strength", 0)) + 2
			powers["_lit_thr_fired"] = true
	if powers.get("enter_light_threshold_5_strength_3", false) and not powers.get("_lit_thr_fired", false):
		if int(player.get("light_shield", 0)) >= 5:
			player["strength"] = int(player.get("strength", 0)) + 3
			powers["_lit_thr_fired"] = true


func _apply_traveler_combat_start() -> void:
	var kit: Dictionary = GameMeta.cards_data.get("travelers", {}).get(traveler, {})
	var pas: Dictionary = kit.get("passive", {})
	if int(pas.get("on_combat_start_block", 0)) > 0:
		player["block"] = int(player.get("block", 0)) + int(pas["on_combat_start_block"])
	if int(pas.get("on_combat_start_echo", 0)) > 0:
		player["echo"] = int(player.get("echo", 0)) + int(pas["on_combat_start_echo"])
	if int(pas.get("start_with_curse", 0)) > 0:
		var curse := {"id": "curse_guilt", "name": "咎印", "type": "诅咒", "rarity": "curse", "cost": -1, "text": "无法打出。", "tags": ["curse"]}
		# prefer real curses table
		var cl = []
		if FileAccess.file_exists("res://data/curses.json"):
			var cd = JSON.parse_string(FileAccess.open("res://data/curses.json", FileAccess.READ).get_as_text())
			if typeof(cd) == TYPE_DICTIONARY:
				cl = cd.get("curses", cd.get("cards", []))
		if cl.size():
			curse = cl[0].duplicate(true)
			curse["rarity"] = "curse"
			if not curse.has("tags"):
				curse["tags"] = ["curse"]
		draw_pile.append(curse.duplicate(true))
		draw_pile.shuffle()
