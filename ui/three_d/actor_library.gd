extends RefCounted
## 灰誓 · 3D 角色造型库（rig3d）
##
## spec_for(entity, definition, is_player) -> actor_rig.spec
## 七名旅者各有一套专属轮廓；敌人优先查 enemy_forms.gd 的 56 条显式造型，
## 未收录的 id 才按姓名关键词兜底映射到 archetype。
## 只产出数据，不建节点。

const EnemyForms = preload("res://ui/three_d/enemy_forms.gd")

const REQUIRED_TRAVELERS := ["warden", "ranger", "sister", "arcanist", "medium", "bellscribe", "ashlamper"]

const TRAVELERS := {
	# 重甲盾卫：宽肩、钟纹盾、缺口剑、厚重披风
	"warden": {
		"archetype": "knight", "height": 1.88, "bulk": 1.24,
		"palette": {"cloth": "#4a332f", "metal": "#8b8f8c", "trim": "#c0a06a", "accent": "#c76b57", "skin": "#b9997f", "dark": "#171a18"},
		"weapon": "sword", "accessories": ["shield", "cloak"], "extras": ["coat_tails"],
	},
	# 游侠：瘦长、兜帽、长矛、短披风
	"ranger": {
		"archetype": "humanoid", "height": 1.80, "bulk": 0.94,
		"palette": {"cloth": "#2f3b30", "metal": "#6e7368", "trim": "#8eae82", "accent": "#8eae82", "skin": "#c2ab92", "dark": "#141814"},
		"weapon": "spear", "accessories": ["hood", "cloak"], "extras": [],
	},
	# 修女：长袍、兜帽、链香炉杖、经卷
	"sister": {
		"archetype": "caster", "height": 1.84, "bulk": 0.92,
		"palette": {"cloth": "#2b3a40", "metal": "#7f8c92", "trim": "#79b9d6", "accent": "#79b9d6", "skin": "#cbbba6", "dark": "#12181b"},
		"weapon": "staff", "staff_top": "censer", "accessories": ["hood", "books"], "extras": [],
	},
	# 秘术师：星冠、厚重法袍、星辉杖、悬浮书册
	"arcanist": {
		"archetype": "caster", "height": 1.86, "bulk": 0.98,
		"palette": {"cloth": "#2c2940", "metal": "#6f6880", "trim": "#d7b65c", "accent": "#d7b65c", "skin": "#c8b49c", "dark": "#131118"},
		"weapon": "staff", "staff_top": "star", "accessories": ["crown", "cloak", "books"], "extras": [],
	},
	# 灵媒：暗紫长袍、锁链、提灯杖、半面
	"medium": {
		"archetype": "caster", "height": 1.82, "bulk": 0.88,
		"palette": {"cloth": "#2a2433", "metal": "#6b6275", "trim": "#b59cbb", "accent": "#b59cbb", "skin": "#c6c0bb", "dark": "#121016"},
		"weapon": "staff", "staff_top": "lantern", "accessories": ["hood", "chains", "lantern"], "extras": [],
	},
	# 钟书吏：高挑、层叠旧布、铜半面具、手持钟、悬浮书册
	"bellscribe": {
		"archetype": "humanoid", "height": 1.97, "bulk": 0.82,
		"palette": {"cloth": "#27332f", "metal": "#7d6a4f", "trim": "#73c5b5", "accent": "#73c5b5", "skin": "#c9c2b0", "dark": "#101514"},
		"weapon": "bell", "accessories": ["mask", "books"], "extras": ["layers"],
	},
	# 灰灯行者：前倾、煤灰短外套、长柄提灯杖、腰侧余烬罐
	"ashlamper": {
		"archetype": "humanoid", "height": 1.79, "bulk": 0.96,
		"palette": {"cloth": "#3a3129", "metal": "#5f5c53", "trim": "#db9162", "accent": "#db9162", "skin": "#a99a86", "dark": "#141210"},
		"weapon": "staff", "staff_top": "lantern", "accessories": ["hood", "lantern"], "extras": ["coat_tails", "hunch"],
	},
}

const ARCH_WEAPON := {
	"skeleton": "spear", "knight": "sword", "caster": "staff", "sovereign": "sword",
	"automaton": "hammer", "giant": "hammer", "wraith": "scythe", "beast": "claw",
	"moth": "none", "raven": "none", "worm": "none", "eye": "none", "bell": "bell",
	"humanoid": "sword",
}

const ARCH_HEIGHT := {
	"humanoid": 1.72, "skeleton": 1.78, "knight": 1.86, "caster": 1.80, "sovereign": 2.02,
	"automaton": 1.92, "giant": 2.32, "wraith": 1.74, "beast": 1.16, "moth": 1.56,
	"raven": 1.34, "worm": 1.18, "eye": 1.42, "bell": 1.86,
}

const ARCH_BULK := {
	"humanoid": 1.00, "skeleton": 0.86, "knight": 1.16, "caster": 0.92, "sovereign": 1.10,
	"automaton": 1.12, "giant": 1.34, "wraith": 0.90, "beast": 1.12, "moth": 0.86,
	"raven": 0.90, "worm": 1.04, "eye": 1.00, "bell": 1.10,
}

const ARCH_ACCESSORIES := {
	"humanoid": ["cloak"], "skeleton": ["shield"], "knight": ["shield", "cloak"],
	"caster": ["hood", "cloak"], "sovereign": ["crown", "cloak"], "automaton": [],
	"giant": [], "wraith": ["chains"], "beast": [], "moth": [], "raven": [],
	"worm": [], "eye": [], "bell": [], 
}


static func spec_for(entity: Dictionary, definition: Dictionary = {}, is_player: bool = false) -> Dictionary:
	if not definition is Dictionary:
		definition = {}
	if not entity is Dictionary:
		entity = {}
	var kind := str(entity.get("kind", definition.get("kind", "")))
	if not is_player and kind in ["osty", "spirit", "servant"]:
		return _spirit(kind, entity, definition)
	var role_id := str(entity.get("role", entity.get("role_id", "")))
	if role_id.is_empty():
		role_id = str(definition.get("role", ""))
	if is_player:
		if role_id.is_empty():
			role_id = str(definition.get("id", "warden"))
		return _traveler(role_id, definition, entity)
	var display := str(entity.get("name", definition.get("name", "")))
	if display.is_empty():
		display = str(entity.get("id", "无名者"))
	# 显式 56 条敌人造型优先；未收录才走按名字分类的兜底。
	var enemy_id := str(definition.get("id", entity.get("id", "")))
	if not enemy_id.is_empty() and EnemyForms.has_form(enemy_id):
		return EnemyForms.spec(enemy_id, definition)
	var forced := str(definition.get("archetype", entity.get("archetype", "")))
	var arch := forced if not forced.is_empty() else classify(display)
	return _enemy(display, arch, kind, definition, entity)


static func classify(display_name: String) -> String:
	var n := display_name
	if n.contains("蛾"):
		return "moth"
	if n.contains("鸦") or n.contains("鸟"):
		return "raven"
	if n.contains("蠕虫") or n.contains("虫"):
		return "worm"
	if n.contains("观测") or n.contains("占卜"):
		return "caster"
	if n.contains("天穹之眼") or n.contains("眼"):
		return "eye"
	if n.contains("巨人") or n.contains("巨像"):
		return "giant"
	if n.contains("钟"):
		return "bell"
	if n.contains("王") or n.contains("摄政") or n.contains("圣母") or n.contains("储君"):
		return "sovereign"
	if n.contains("傀儡") or n.contains("镜") or n.contains("圣像") or n.contains("机关"):
		return "automaton"
	if n.contains("犬") or n.contains("兽"):
		return "beast"
	if n.contains("骨") or n.contains("掘墓") or n.contains("送葬") or n.contains("守墓") or n.contains("墓园") or n.contains("尸"):
		return "skeleton"
	if n.contains("骑士") or n.contains("近卫") or n.contains("禁卫") or n.contains("卫兵") or n.contains("侍从") or n.contains("双刃") or n.contains("刽子手") or n.contains("门卫") or n.contains("侍者") or n.contains("司祭") or n.contains("守卫") or n.contains("缝卫") or n.contains("审判"):
		return "knight"
	if n.contains("修士") or n.contains("信徒") or n.contains("颂唱") or n.contains("抄经") or n.contains("书记") or n.contains("御医") or n.contains("学徒") or n.contains("导师") or n.contains("执灯") or n.contains("巡猎") or n.contains("信使") or n.contains("传令") or n.contains("侍女") or n.contains("院长") or n.contains("裁星"):
		return "caster"
	if n.contains("残影") or n.contains("旧誓") or n.contains("无名") or n.contains("幽") or n.contains("影"):
		return "wraith"
	return "humanoid"


static func _traveler(role_id: String, definition: Dictionary, entity: Dictionary) -> Dictionary:
	var key := role_id if TRAVELERS.has(role_id) else "warden"
	var base: Dictionary = TRAVELERS[key].duplicate(true)
	var role_color := _color(str(definition.get("color", entity.get("color", ""))), _default_role_color(role_id))
	var palette: Dictionary = base.get("palette", {}).duplicate(true)
	palette["accent"] = role_color
	palette["trim"] = _color(str(palette.get("trim", "")), role_color.lightened(0.18)).lerp(role_color, 0.35).lightened(0.05)
	base["palette"] = palette
	base["id"] = str(entity.get("id", role_id))
	base["name"] = str(definition.get("name", entity.get("name", key)))
	base["role"] = role_id
	base["seed"] = _seed_for(str(base["id"]), "player", role_id)
	base["is_player"] = true
	return base


static func _spirit(kind: String, entity: Dictionary, definition: Dictionary) -> Dictionary:
	var display := str(entity.get("name", "幽魂"))
	var accent := _color(str(definition.get("color", "")), Color("b59cbb"))
	return {
		"id": str(entity.get("id", "spirit")), "name": display, "archetype": "wraith",
		"height": 0.98, "bulk": 0.70,
		"palette": {
			"cloth": accent.darkened(0.62), "metal": accent.darkened(0.3), "trim": accent,
			"accent": accent, "skin": Color("cfc7bb"), "dark": Color("0e0d10"),
		},
		"weapon": "none", "accessories": ["hood"], "extras": [],
		"seed": _seed_for(str(entity.get("id", "spirit")), kind, ""), "is_player": true,
	}


static func _enemy(display: String, arch: String, kind: String, definition: Dictionary, entity: Dictionary) -> Dictionary:
	if not ARCH_HEIGHT.has(arch):
		arch = "humanoid"
	var base := _color(str(definition.get("color", entity.get("color", ""))), Color("9a9484"))
	var rank := 0.0
	if kind == "elite":
		rank = 1.0
	elif kind == "boss":
		rank = 2.0
	elif kind == "minion":
		rank = -0.5
	var height: float = float(ARCH_HEIGHT[arch]) * (1.0 + 0.06 * rank)
	var bulk: float = float(ARCH_BULK[arch]) + 0.06 * rank
	bulk = clampf(bulk, 0.82, 1.35)
	var cloth := base.darkened(0.58).lerp(Color("1b1e1c"), 0.30)
	var metal := base.darkened(0.34).lerp(Color("8a8b85"), 0.42)
	var trim := base.lightened(0.22)
	var skin := Color("c3b49c").lerp(base, 0.38)
	var dark := base.darkened(0.82)
	var accessories: Array = ARCH_ACCESSORIES.get(arch, []).duplicate()
	if kind == "boss" and not accessories.has("horns"):
		accessories.append("horns")
	if arch == "bell" and kind == "boss":
		accessories.append("chains")
	var spec := {
		"id": str(entity.get("id", display)), "name": display, "archetype": arch,
		"height": height, "bulk": bulk,
		"palette": {
			"cloth": cloth, "metal": metal, "trim": trim, "accent": base,
			"skin": skin, "dark": dark,
		},
		"weapon": str(ARCH_WEAPON.get(arch, "sword")),
		"accessories": accessories,
		"extras": [],
		"seed": _seed_for(str(entity.get("id", display)), arch, kind),
		"is_player": false,
		"chapter": int(definition.get("chapter", entity.get("chapter", 0))),
	}
	if arch == "caster":
		spec["staff_top"] = ["orb", "lantern", "star", "censer"][abs(int(spec["seed"])) % 4]
	if arch == "giant":
		spec["extras"] = ["hunch"]
	if kind == "boss":
		spec["extras"] = ["hunch"] if arch in ["giant", "humanoid", "knight"] else []
	return spec


static func _seed_for(id_value: String, arch: String, kind: String) -> int:
	return abs(("%s|%s|%s" % [id_value, arch, kind]).hash())


static func _default_role_color(role_id: String) -> Color:
	match role_id:
		"warden":
			return Color("c76b57")
		"ranger":
			return Color("8eae82")
		"sister":
			return Color("79b9d6")
		"arcanist":
			return Color("d7b65c")
		"medium":
			return Color("b59cbb")
		"bellscribe":
			return Color("73c5b5")
		"ashlamper":
			return Color("db9162")
	return Color("c7a66a")


static func _color(value: String, fallback: Color) -> Color:
	if value.is_empty():
		return fallback
	if not value.begins_with("#"):
		value = "#" + value
	if not Color.html_is_valid(value):
		return fallback
	return Color.html(value)
