extends Control
## Presentation only: every rule-changing action goes through the rules API.

const Rules = preload("res://core/game_engine.gd")
const TutorialLessons = preload("res://core/tutorial_lessons.gd")
const ExpeditionItems = preload("res://core/item_mechanics.gd")
const RoutePaths = preload("res://ui/route_paths.gd")
const MapNodeVisual = preload("res://ui/map_node_visual.gd")
const CardVisual = preload("res://ui/card_visual.gd")
const ItemIconVisual = preload("res://ui/item_icon.gd")
const CombatActor = preload("res://ui/combat_actor.gd")
const CombatFollower = preload("res://ui/combat_follower.gd")
const CombatEffects = preload("res://ui/combat_effects.gd")
const BattleFlair = preload("res://ui/battle_flair.gd")
const AudioDirector = preload("res://ui/audio_manager.gd")
const TitleAtmosphere = preload("res://ui/title_atmosphere.gd")
const RoleGuide = preload("res://ui/role_guide.gd")
const StsTargeting = preload("res://ui/sts_targeting.gd")
const WorkshopPack = preload("res://core/workshop_pack.gd")
const WorkshopEditor = preload("res://ui/workshop_editor.gd")
const RewardScreen = preload("res://ui/screens/reward_screen.gd")
const CampScreen = preload("res://ui/screens/camp_screen.gd")
const EventScreen = preload("res://ui/screens/event_screen.gd")
const RouteScreen = preload("res://ui/screens/route_screen.gd")
const INK := Color("111311")
const PAPER := Color("e8dfcc")
const MUTED := Color("aaa99a")
const GOLD := Color("c7a66a")
const RED := Color("ae5148")
const GREEN := Color("91aa8c")
const BORDER := Color("44483b")
const DROP_DEFEATED := -3
const DROP_CANCEL := -2
const DROP_UNTARGETED := -1
const CARD_DRAG_THRESHOLD := 12.0
const KIND_NAMES := {"normal": "小怪", "elite": "精英", "boss": "首领", "rest": "营火", "shop": "商店", "event": "命运", "fate": "命运", "unknown": "问号", "treasure": "宝箱"}
const STATUS_NAMES := {
	"strength": "力量", "weak": "虚弱", "vulnerable": "易伤", "poison": "中毒",
	"thorns": "荆棘", "regen": "再生", "next_energy": "下回合能量", "doom": "灾厄",
	"dexterity": "敏捷", "focus": "集中", "intangible": "虚化", "frail": "脆弱",
	"exhaust_block": "消耗格挡", "exhaust_draw": "消耗抽牌", "strength_each_turn": "每回合力量",
	"retain_block": "格挡保留", "shiv_damage": "小刀增伤", "discard_draw": "弃牌抽牌",
	"discard_energy": "弃牌能量", "soul_summon": "灵魂召唤", "cinder": "余烬", "resonance": "回响",
	"tactical_points": "应变",
}
const TYPE_NAMES := {"attack": "攻击", "skill": "技能", "power": "能力"}
const DIFFICULTY_DETAILS := {
	-2: "敌人生命降低 35%，攻击基础伤害降低 30%。通关计入记录，进阶从初次长夜开启。",
	-1: "敌人生命降低 20%，攻击基础伤害降低 15%。通关计入记录，进阶从初次长夜开启。",
	0: "标准战斗规则。用此旅者通关后开放进阶 1。",
	1: "普通敌人生命提高 10%，包括精英战中的随从。",
	2: "精英本体的攻击基础伤害提高 10%。",
	3: "商店价格提高 15%。",
	4: "首领各阶段的生命提高约 15%。",
	5: "延续进阶 4 的规则。通关后开放进阶 6。",
	6: "精英本体的生命提高 15%。",
	7: "所有敌人的攻击基础伤害再提高 15%。",
	8: "首领各阶段的生命再提高 20%。",
}
const RARITY_NAMES := {"starter": "初始", "common": "普通", "uncommon": "罕见", "rare": "稀有", "boss": "首领"}
const KEYWORD_HELP := {
	"应变": "同一回合交替主动打出攻击牌和技能牌时获得1点应变，每回合最多获得2点、持有上限3点。能力牌不参与也不打断；机巧自动出牌不计入。应变跨回合保留，新战斗清零。消耗2点发动一种战术，每回合限一次，不消耗能量。",
	"战术": "追击：对选中敌人造成固定伤害（基础6点，每章+2），受格挡与虚化影响，不触发攻击加成、荆棘或出牌效果。固守：获得固定格挡（基础7点，每章+2），不受敏捷、脆弱影响。整备：抽2张再主动弃1张，可触发机巧；需要至少2个手牌空位与2张可抽牌。",
	"回响": "回响在本场战斗中跨回合保留，最多6点。写有回响追加效果的牌在至少3点时消耗3点。",
	"余烬": "每个敌人可累积至多8层。引燃时清空该目标的全部印记，按每层结算固定伤害，格挡可以吸收。",
	"虚弱": "这个单位打出的攻击伤害 ×0.75（降低25%）。例如基础攻击10变为7。重复施加只累加剩余回合；这个单位自己的回合结束后减1。",
	"易伤": "这个单位受到的攻击伤害 ×1.5（提高50%）。例如基础攻击10变为15。重复施加只累加剩余回合；这个单位自己的回合结束后减1。",
	"虚化": "每次直接伤害和主动失去生命最多1点，再结算格挡。重复施加延长时间，敌人行动结束后减1回合。中毒和灾厄不受影响。",
	"虚无": "与虚化不同：回合结束时，这张牌若还在手中就消耗。保留不能阻止虚无。",
	"中毒": "在所属单位回合开始失去等于层数的生命，绕过格挡和虚化，再减少1层。不同来源叠加层数；例如3层再加2层，下次先扣5生命，然后剩4层。",
	"消耗": "移入本场消耗区，正常洗牌不会再抽到；战斗结束恢复。能力牌移出循环，但不触发消耗联动。",
	"保留": "回合结束不弃置，仍占用手牌上限10张；能量不会因此保留。",
	"机巧": "在自己的回合被主动选择弃置时，这张牌会免费打出；回合末自动弃牌不触发。",
	"力量": "每段攻击的基础伤害增加等于力量的数值，多段攻击每段都受益；不增强球、毒与奥斯蒂。",
	"敏捷": "卡牌和药水每次提供格挡时，加上当前敏捷；可叠加，持续本场。若有脆弱，加完敏捷再乘0.75并取整。充能球、遗物和消耗联动的格挡不受影响。",
	"灾厄": "不同来源叠加层数，平时不扣血也不递减。目标在自己的回合结束时，灾厄≥当前生命就会倒下，绕过格挡，所以敌人仍可能先行动。",
	"奥斯蒂": "每回合召唤1生命，可通过召唤恢复或复活。先用你的格挡，再用奥斯蒂生命承受剩余攻击；其攻击独立于你的力量、虚弱。",
	"星辰": "与能量分开支付，跨回合保留；下一场战斗重新初始化。手动出牌先付星辰，再结算效果，所以按当前星辰计算的牌使用扣费后的数值。",
	"锻造": "首次创造一张保留的君王之剑；继续锻造提高同一把剑在本场的伤害。剑打出后进入弃牌，可再次抽到。",
	"充能球": "按从左到右排列，满槽生成时先激发最左球。闪电：末尾随机3/激发8伤害；冰霜：末尾2/激发5格挡；黑暗：末尾蓄6/激发攻击最低生命；等离子：开头1/激发2能量；玻璃：末尾全体4，逐次减1，激发为当前值2倍。",
	"集中": "增强闪电伤害、冰霜格挡、黑暗蓄力和玻璃伤害，不影响等离子；球不吃力量、虚弱或易伤。",
	"能力": "打出后本场持续生效，卡牌移出抽牌循环；这一步不算消耗，不能触发消耗格挡或消耗抽牌。",
	"小刀": "0费攻击，打出后消耗。基础伤害6，可叠加小刀增伤，再按力量、虚弱、易伤计算每一击。",
	"弃牌": "主动弃牌才触发机巧、弃牌抽牌和弃牌能量。先结算机巧牌，再触发弃牌收益；回合末自动弃置不触发。",
	"灵魂": "0费抽2张的临时技能，打出后消耗；灵魂召唤能力在打出时为奥斯蒂恢复或增加生命。",
	"格挡": "吸收普通伤害。玩家的格挡通常在自己回合开始清空；敌人的格挡在自己的行动开始清空。中毒、灾厄和主动失去生命绕过格挡。",
	"脆弱": "卡牌和药水获得格挡时，先加敏捷，再乘0.75并向下取整。已有的格挡不会减少。重复施加只延长时间，自己的回合结束后减1。",
	"荆棘": "受攻击时用当前层数反击；即使这次攻击被格挡，仍可反击。反伤可被格挡，不再触发对方荆棘。层数可叠加，持续本场。",
	"再生": "自己的回合开始时回复等于当前层数的生命，再减1层。先结算中毒，再结算再生。重复施加会增加层数。",
	"下回合能量": "可叠加。下个玩家回合开始时，把存下的能量一次加入基础能量，随后清零。",
	"消耗格挡": "每消耗一张牌就获得等于该状态数值的格挡。多份能力可相加；打出能力牌本身不会触发。",
	"消耗抽牌": "每消耗一张牌就抽取相应数量的牌，受10张手牌上限限制。多份能力可相加。",
	"每回合力量": "从下个回合起，每回合开始增加所示力量，已加的力量会累积到本场结束。重复打出该能力会增加每回合的增量。",
	"格挡保留": "有此能力时，玩家回合开始不会清空剩余格挡。多次获得此能力不会让同一份格挡翻倍。",
	"小刀增伤": "每张小刀的基础伤害增加所示数值，可叠加，持续本场；加成会直接显示在手中小刀的说明里。",
	"弃牌抽牌": "主动选择弃置一张牌后，抽取所示数量的牌。机巧牌先免费结算，再抽牌。回合末自动弃牌不触发。",
	"弃牌能量": "主动选择弃置一张牌后，获得所示数量的能量。回合末自动弃牌不触发。多份能力可以相加。",
	"灵魂召唤": "每打出一张灵魂，按状态数值恢复或增加奥斯蒂生命，可以复活。多份能力可相加，持续本场。",
	"献血": "主动失去牌面写明的生命，绕过格挡；若降至0，后面的收益不会结算。虚化时单次最多失去1点。",
	"侍从": "将这张牌以外、非君王之剑的手牌变成临时侍从，不修改永久牌组。侍从是0费格挡牌，打出后消耗。",
	"激发": "结算最左一颗充能球的激发效果，并移除它。多次激发可以依次移除多颗；重复激发同一颗只移除一颗。",
	"困兽": "敌人生命降至一半或以下时，每段攻击的基础伤害增加2；回复到一半以上后消失。意图中的攻击数字已包含加成。",
	"蓄势": "敌人每行动2次，之后每段攻击基础伤害增加1，最多增加3。意图中的攻击数字已包含蓄势；中毒等非攻击伤害不受影响。",
	"群攻": "直接攻击所有存活敌人，各自结算易伤和格挡。多段群攻每一段都会检查存活目标；倒下的敌人不再被命中。没有单体效果的群攻不需要选目标。",
	"全体效果": "按牌面给每个存活敌人施加所列状态。若只有中毒或灾厄，不会立即造成攻击伤害；按对应状态的回合时机结算。",
}
const KEYWORD_GROUPS := {
	"应变与战术": ["应变", "战术"],
	"伤害与防御": ["蓄势", "困兽", "格挡", "力量", "虚弱", "易伤", "群攻", "全体效果", "敏捷", "脆弱", "虚化", "荆棘", "献血"],
	"回合开始与结束": ["中毒", "灾厄", "再生", "下回合能量", "每回合力量", "格挡保留"],
	"卡牌去向和联动": ["能力", "消耗", "虚无", "保留", "弃牌", "机巧", "消耗格挡", "消耗抽牌", "弃牌抽牌", "弃牌能量"],
	"职业资源": ["小刀", "小刀增伤", "星辰", "锻造", "侍从", "奥斯蒂", "灵魂", "灵魂召唤", "充能球", "集中", "激发", "回响", "余烬"],
}

var game
var content: VBoxContainer
var body: VBoxContainer
var overlay: Control
var card_feedback_layer: Control
var background: TextureRect
var shade: ColorRect
var notice_label: Label
var notice := ""
var save_warning := ""
var menu_open := false
var selected_role := "warden"
var selected_build_plan := ""
var selected_target := 0
var difficulty := 0
var seed_input: LineEdit
var seed_error: Label
var hand_scroll_turn := ""
var hand_scroll_offset := 0
var heading_font: SystemFont
var combat_actors: Dictionary = {}
var battle_followers: Dictionary = {}
var combat_effects: Control
var impact_flash: ColorRect
var vignette: Control
var combat_busy := false
var drag_card_index := -1
var drag_start := Vector2.ZERO
var drag_moved := false
var drag_source: Button
var drag_card_data: Dictionary = {}
var drag_ghost: Control
var drag_target_outline: Panel
var targeting_arrow: Control
var coach_pulse_tween: Tween
var _combat_generation := 0
var impact_tween: Tween
var punch_tween: Tween
var audio
var stage: Control
var shake_left := 0.0
var shake_mag := 0.0
var _shake_rng := RandomNumberGenerator.new()
var _heard_room := ""
var menu_page := "title"
var journey_game
var workshop_draft: Dictionary = {}
var workshop_return_game
var workshop_return_ui: Dictionary = {}
var workshop_start_error := ""
var tutorial_notice := ""
var tutorial_return_target := 0
var title_atmosphere: Control
var collection_role := "all"
var collection_rarity := "all"
var collection_owned := false
var collection_query := ""
var collection_page := 0
var achievement_toast: Control
var selected_oath := ""
var oath_draft_seed := -1
var oath_draft_active := false
var oath_draft_offers: Array = []
var oath_card_buttons: Array[Button] = []
var oath_begin_button: Button
var daily_error := ""


func _ready() -> void:
	_shake_rng.seed = 90210
	_build_theme()
	game = Rules.new()
	save_warning = game.last_error
	menu_open = true
	_build_shell()
	_refresh()


func _build_theme() -> void:
	var main_font := SystemFont.new()
	main_font.font_names = PackedStringArray(["PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	var chinese_fallback := SystemFont.new()
	chinese_fallback.font_names = PackedStringArray(["Songti SC", "Heiti SC", "Microsoft YaHei", "sans-serif"])
	main_font.fallbacks = [chinese_fallback]
	heading_font = SystemFont.new()
	heading_font.font_names = PackedStringArray(["Songti SC", "Noto Serif CJK SC", "serif"])
	var ui_theme := Theme.new()
	ui_theme.default_font = main_font
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Label", Color("ded2ba"))
	ui_theme.set_color("font_shadow_color", "Label", Color(0.014, 0.011, 0.009, 0.94))
	ui_theme.set_constant("shadow_offset_x", "Label", 0)
	ui_theme.set_constant("shadow_offset_y", "Label", 1)
	ui_theme.set_constant("shadow_outline_size", "Label", 1)
	ui_theme.set_color("font_color", "Button", Color("dfd2b8"))
	ui_theme.set_color("font_hover_color", "Button", Color("f6ecd8"))
	ui_theme.set_color("font_pressed_color", "Button", Color("cbb079"))
	ui_theme.set_color("font_disabled_color", "Button", Color("6d6a5f"))
	ui_theme.set_stylebox("normal", "Button", _sts_box(Color(0.105, 0.09, 0.072, 0.96), Color("4d4030"), 1))
	ui_theme.set_stylebox("hover", "Button", _sts_box(Color(0.17, 0.145, 0.112, 0.98), Color("c7a66a"), 1))
	ui_theme.set_stylebox("pressed", "Button", _sts_box(Color(0.075, 0.064, 0.05, 1.0), Color("e0c48a"), 1))
	ui_theme.set_stylebox("disabled", "Button", _sts_box(Color(0.065, 0.06, 0.052, 0.82), Color("322c24"), 1))
	ui_theme.set_stylebox("focus", "Button", _sts_box(Color(0, 0, 0, 0), Color("c7a66a", 0.7), 1))
	ui_theme.set_stylebox("panel", "PanelContainer", _sts_box(Color(0.07, 0.06, 0.05, 0.94), Color("4a3d2c"), 1))
	ui_theme.set_stylebox("normal", "LineEdit", _sts_box(Color(0.06, 0.055, 0.048, 0.95), Color("44392a"), 1))
	ui_theme.set_stylebox("focus", "LineEdit", _sts_box(Color(0.09, 0.08, 0.065, 0.98), Color("c7a66a"), 1))
	ui_theme.set_color("font_color", "LineEdit", Color("ded2ba"))
	ui_theme.set_color("font_placeholder_color", "LineEdit", Color("8b8574"))
	ui_theme.set_color("font_color", "ProgressBar", Color("ded2ba"))
	ui_theme.set_constant("separation", "VBoxContainer", 10)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	theme = ui_theme


func _set_atmosphere(kind: String, strained: bool = false) -> void:
	if not is_instance_valid(background) or not is_instance_valid(shade):
		return
	match kind:
		"menu":
			background.modulate = Color(1.0, 0.97, 0.91, 1.0)
			shade.color = Color(0.02, 0.025, 0.025, 0.12)
		"battle":
			if strained:
				background.modulate = Color(0.72, 0.52, 0.46, 0.92)
				shade.color = Color(0.14, 0.03, 0.02, 0.48)
			else:
				background.modulate = Color(0.72, 0.66, 0.58, 0.95)
				shade.color = Color(0.035, 0.03, 0.024, 0.62)
		"victory":
			background.modulate = Color(1.0, 0.86, 0.68, 0.82)
			shade.color = Color(0.08, 0.06, 0.03, 0.36)
		"defeat":
			background.modulate = Color(0.34, 0.26, 0.24, 0.55)
			shade.color = Color(0.07, 0.02, 0.018, 0.62)
		_:
			background.modulate = Color(0.72, 0.66, 0.56, 0.74)
			shade.color = Color(0.03, 0.028, 0.024, 0.5)


func _style(fill: Color, edge: Color, width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = edge
	result.set_border_width_all(width)
	result.set_corner_radius_all(2)
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result


func _sts_box(fill: Color, edge: Color, width: int = 1, glow: bool = false) -> StyleBoxFlat:
	# Slay-the-Spire flavoured stone slab: dark warm fill, hairline gilding, soft drop shadow.
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = edge
	result.set_border_width_all(width)
	result.set_corner_radius_all(2)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	result.shadow_color = Color(0, 0, 0, 0.55)
	result.shadow_size = 6 if glow else 3
	result.shadow_offset = Vector2(0, 3)
	return result


func _sts_actor_frame(selected: bool, dead: bool = false) -> StyleBoxFlat:
	# 半透明格底，让下层祭坛的暖光透上来；选中只靠金边与辉光区分。
	var fill := Color(0.075, 0.062, 0.052, 0.34) if selected else Color(0.05, 0.045, 0.04, 0.22)
	var edge := Color(0.83, 0.70, 0.45, 0.82) if selected else Color(0.36, 0.31, 0.23, 0.55)
	if dead:
		fill = Color(0.04, 0.04, 0.035, 0.30)
		edge = Color(0.24, 0.23, 0.2, 0.45)
	return _sts_box(fill, edge, 2 if selected else 1, selected)


func _hp_caption(bar: Control, value: String, font_size: int = 12) -> Label:
	var bar_control := bar as ProgressBar
	if bar_control != null:
		bar_control.show_percentage = false
	var caption := _label(bar, value, font_size, PAPER)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.01, 0.95))
	caption.add_theme_constant_override("shadow_outline_size", 3)
	return caption


func _icon_button(parent: Node, glyph: String, tip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = glyph
	button.custom_minimum_size = Vector2(48, 48)
	button.add_theme_font_size_override("font_size", 19)
	button.tooltip_text = tip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var fill: Color = {"normal": Color(0.10, 0.086, 0.072, 0.95), "hover": Color(0.17, 0.14, 0.11, 0.98), "pressed": Color(0.06, 0.05, 0.04, 1.0), "disabled": Color(0.07, 0.066, 0.06, 0.7)}[state_name]
		var edge := GOLD if state_name == "hover" else Color("4b3f2e")
		button.add_theme_stylebox_override(state_name, _sts_box(fill, edge, 1))
	button.pressed.connect(func() -> void:
		if is_instance_valid(button) and not button.text.is_empty():
			_sfx("click", 0.02, -14.0))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_item_icon(parent: Node, definition: Dictionary, category: String, diameter: float = 52.0) -> Control:
	if definition.is_empty():
		return null
	var icon = ItemIconVisual.new()
	icon.name = "ItemIcon_" + str(definition.get("id", "unknown"))
	icon.setup(definition, category, diameter)
	parent.add_child(icon)
	return icon


func _new_actor() -> Control:
	# Prefer the 3D rig when it shipped; the 2D vector actor keeps the UI playable otherwise.
	var script_path := "res://ui/three_d/actor_view.gd"
	if ResourceLoader.exists(script_path):
		var script: Script = load(script_path)
		if script != null and script.can_instantiate():
			return script.new()
	return CombatActor.new()


func _status_lines(text_value: String, per_line: int) -> String:
	# StS status strips are short: break the joined status text into compact rows.
	if text_value.length() <= 0 or per_line <= 0:
		return text_value
	var parts := text_value.split(" · ")
	if parts.size() <= per_line:
		return text_value
	var rows: Array[String] = []
	var row: Array[String] = []
	for part in parts:
		row.append(part)
		if row.size() >= per_line:
			rows.append(" · ".join(row))
			row.clear()
	if not row.is_empty():
		rows.append(" · ".join(row))
	return "\n".join(rows)


func _chip(parent: Node, text_value: String, tone: Color) -> Label:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sts_box(Color(tone.r * 0.3, tone.g * 0.3, tone.b * 0.3, 0.55), Color(tone.r, tone.g, tone.b, 0.5), 1))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(frame)
	var chip := _label(frame, text_value, 12, tone)
	chip.add_theme_constant_override("outline_size", 0)
	return chip


func _build_shell() -> void:
	var base := ColorRect.new()
	base.color = INK
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	background = TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_path := "res://assets/art/battle_background.png"
	if ResourceLoader.exists(art_path):
		background.texture = load(art_path)
	background.modulate = Color(0.78, 0.74, 0.66, 0.8)
	add_child(background)
	shade = ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.03, 0.46)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	title_atmosphere = TitleAtmosphere.new()
	add_child(title_atmosphere)
	vignette = BattleVignette.new()
	add_child(vignette)
	stage = Control.new()
	stage.name = "Stage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	stage.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	card_feedback_layer = Control.new()
	card_feedback_layer.name = "CardFeedbackLayer"
	card_feedback_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_feedback_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(card_feedback_layer)
	combat_effects = CombatEffects.new()
	combat_effects.name = "CombatEffects"
	combat_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(combat_effects)
	impact_flash = ColorRect.new()
	impact_flash.color = Color(0, 0, 0, 0)
	impact_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	impact_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(impact_flash)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	audio = AudioDirector.new()
	audio.name = "AudioDirector"
	add_child(audio)
	get_window().focus_exited.connect(_cancel_card_drag)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _refresh() -> void:
	var setup_open := menu_open and menu_page == "roles"
	var seed_draft := seed_input.text if setup_open and is_instance_valid(seed_input) else ""
	var seed_error_visible := setup_open and is_instance_valid(seed_error) and seed_error.visible
	seed_input = null
	seed_error = null
	oath_begin_button = null
	if not setup_open and oath_draft_active:
		selected_oath = ""
		oath_draft_seed = -1
		oath_draft_offers = []
		oath_card_buttons = []
		oath_draft_active = false
	if not (menu_open and menu_page == "daily"):
		daily_error = ""
	_combat_generation += 1
	_cancel_card_drag()
	combat_busy = false
	_stop_shake()
	combat_actors.clear()
	battle_followers.clear()
	if is_instance_valid(combat_effects):
		combat_effects.clear_effects()
	_clear(content)
	content.add_theme_constant_override("separation", 14)
	if is_instance_valid(card_feedback_layer):
		_clear(card_feedback_layer)
	if is_instance_valid(background):
		background.scale = Vector2.ONE
		var atmosphere := "field"
		if menu_open:
			atmosphere = "menu"
		elif str(game.state.room) == "battle":
			atmosphere = "battle"
		elif str(game.state.room) == "victory":
			atmosphere = "victory"
		elif str(game.state.room) == "defeat":
			atmosphere = "defeat"
		var strained := atmosphere == "battle" and int(game.state.max_hp) > 0 and float(game.state.hp) / float(game.state.max_hp) <= 0.3
		_set_atmosphere(atmosphere, strained)
	_sync_audio()
	title_atmosphere.visible = menu_open and menu_page == "title"
	vignette.visible = not title_atmosphere.visible
	title_atmosphere.reduced = bool(game.profile.settings.get("reduced_motion", false))
	var art := "res://assets/art/title_background.jpg" if menu_open and menu_page == "title" else "res://assets/art/battle_background.png"
	if ResourceLoader.exists(art):
		background.texture = load(art)
	if is_instance_valid(impact_flash):
		impact_flash.color = Color(0, 0, 0, 0)
	if game.data.get("roles", []).is_empty():
		_label(content, "灰誓", 64, GOLD, true)
		_label(content, "内容文件尚未就绪", 28)
		_label(content, "未找到有效的 data/catalog.json。请完成内容构建后重新启动。", 18, MUTED)
		return
	if menu_open:
		if menu_page == "roles":
			_role_select(seed_draft, seed_error_visible)
		elif menu_page == "tutorial":
			_tutorial()
		elif menu_page == "workshop":
			_workshop()
		elif menu_page == "daily":
			_daily()
		else:
			_menu()
		return
	_hud()
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	if workshop_return_game != null and game.state.room != "battle":
		_workshop_trial_result()
		_footer()
		return
	if journey_game != null and game.state.room != "battle":
		_tutorial_result()
		_footer()
		return
	match str(game.state.room):
		"victory", "defeat": _ending()
		"battle": _battle()
		"map": _map()
		"reward": _reward()
		"shop": _shop()
		"rest": _rest()
		"event": _event()
		"treasure": _treasure()
		_:
			menu_open = true
			_refresh()
			return
	_footer()


func _label(parent: Node, value: String, font_size: int = 18, color: Color = PAPER, serif: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if serif:
		label.add_theme_font_override("font", heading_font)
	parent.add_child(label)
	return label


func _paragraph(parent: Node, value: String, font_size: int = 18, color: Color = MUTED) -> Label:
	var label := _label(parent, value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _spacer(parent: Node, vertical: bool = false) -> Control:
	var space := Control.new()
	if vertical:
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(space)
	return space


func _button(parent: Node, text_value: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 44
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		button.add_theme_stylebox_override("normal", _style(Color("a68b54"), GOLD))
		button.add_theme_stylebox_override("hover", _style(Color("ccb57c"), PAPER))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
	button.pressed.connect(func() -> void:
		if is_instance_valid(button) and not button.text.is_empty():
			_sfx("click", 0.02, -14.0))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _panel(parent: Node, fill: Color = Color(0.075, 0.09, 0.07, 0.93), edge: Color = BORDER) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(fill, edge))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box


func _title(parent: Node, kicker: String, title_text: String, subtitle: String = "") -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 1)
	parent.add_child(block)
	var kicker_label := _label(block, _spaced(kicker), 12, GOLD)
	kicker_label.add_theme_constant_override("outline_size", 0)
	_label(block, title_text, 38, PAPER, true)
	if not subtitle.is_empty():
		_paragraph(block, subtitle)


func _role_select(seed_draft: String, seed_error_visible: bool) -> void:
	if not game.build_plan_options(selected_role).any(func(plan): return str(plan.id) == selected_build_plan):
		selected_build_plan = ""
	var header := HBoxContainer.new()
	content.add_child(header)
	_title(header, "THE OATHKEEPERS", "选择英雄")
	_spacer(header)
	_button(header, "练习此英雄", _start_tutorial.bind(selected_role)).name = "PracticeSelectedRole"
	_button(header, "← 返回主菜单", func():
		menu_page = "title"
		_refresh())
	var traveler_scroll := ScrollContainer.new()
	traveler_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	traveler_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(traveler_scroll)
	var travelers := VBoxContainer.new()
	travelers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	travelers.add_theme_constant_override("separation", 14)
	traveler_scroll.add_child(travelers)
	var roles := GridContainer.new()
	roles.name = "RoleGrid"
	roles.columns = 4
	roles.add_theme_constant_override("h_separation", 14)
	roles.add_theme_constant_override("v_separation", 10)
	travelers.add_child(roles)
	for role in game.data.roles:
		var role_id := str(role.id)
		var unlocked: bool = game.is_role_unlocked(role_id)
		var selected: bool = selected_role == role_id
		var role_box := _panel(roles, Color(0.07, 0.09, 0.07, 0.95), GOLD if selected else BORDER)
		role_box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var summary := HBoxContainer.new()
		summary.add_theme_constant_override("separation", 8)
		role_box.add_child(summary)
		var role_texture: Texture2D = preload("res://ui/role_art.gd").texture_for(role_id)
		if role_texture != null:
			var portrait := TextureRect.new()
			portrait.name = "RolePortrait_" + role_id
			portrait.texture = role_texture
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size = Vector2(72, 86)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			summary.add_child(portrait)
		var profile_text := VBoxContainer.new()
		profile_text.add_theme_constant_override("separation", 2)
		profile_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		summary.add_child(profile_text)
		_label(profile_text, str(role.get("title", "旅者")), 13, GOLD if unlocked else MUTED)
		_label(profile_text, str(role.name), 23, PAPER if unlocked else MUTED, true)
		_label(profile_text, "生命 %d" % int(role.max_hp), 15, MUTED)
		var pick := _button(role_box, "已选择" if selected else ("选择旅者" if unlocked else "%d 场战斗胜利解锁" % int(role.unlock_wins)), func():
			selected_role = role_id
			selected_build_plan = ""
			difficulty = 0
			_refresh())
		pick.name = "PickRole_" + role_id
		pick.disabled = not unlocked
	var selected = game.role_data(selected_role)
	var details := _panel(travelers)
	_label(details, "%s · %s" % [selected.name, selected.get("title", "")], 25, GOLD, true)
	_paragraph(details, str(selected.get("description", "")), 20, PAPER)
	_paragraph(details, "目标：每章走十五层，在多阶段首领前守住誓言。只走亮起的相邻道路。", 17)
	var relic: Dictionary = game.relic_data(str(selected.get("starter_relic", "")))
	var starter_relic_row := HBoxContainer.new()
	starter_relic_row.add_theme_constant_override("separation", 12)
	details.add_child(starter_relic_row)
	_add_item_icon(starter_relic_row, relic, "relic", 48.0)
	var relic_copy := VBoxContainer.new()
	relic_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	starter_relic_row.add_child(relic_copy)
	_label(relic_copy, "初始遗物 · %s" % relic.get("name", "无"), 17, GOLD, true)
	_paragraph(relic_copy, str(relic.get("description", "")), 16, PAPER)
	var setup := _panel(content)
	_build_plan_picker(setup, selected_role, selected_build_plan, func(id: String): selected_build_plan = id)
	var options := HBoxContainer.new()
	setup.add_child(options)
	_button(options, "英雄玩法说明", func(): _show_role_guide(selected_role)).name = "RoleGuideSelection"
	_label(options, "%s · 难度" % selected.name, 16, MUTED)
	var unlocked_level: int = game.unlocked_difficulty(selected_role)
	if difficulty > unlocked_level:
		difficulty = 0
	var levels := OptionButton.new()
	levels.name = "DifficultySelect"
	levels.custom_minimum_size = Vector2(160, 44)
	for level in range(Rules.MIN_DIFFICULTY, Rules.MAX_DIFFICULTY + 1):
		var locked := level > unlocked_level
		levels.add_item(_difficulty_name(level) + (" · 未解锁" if locked else ""))
		var index := levels.item_count - 1
		levels.set_item_metadata(index, level)
		levels.set_item_disabled(index, locked)
		if level == difficulty:
			levels.select(index)
	options.add_child(levels)
	var difficulty_note := _paragraph(setup, _difficulty_description(difficulty), 16)
	difficulty_note.name = "DifficultyDescription"
	levels.item_selected.connect(func(index: int):
		difficulty = int(levels.get_item_metadata(index))
		difficulty_note.text = _difficulty_description(difficulty))
	seed_input = LineEdit.new()
	seed_input.name = "JourneySeed"
	seed_input.placeholder_text = "可选：数字种子"
	seed_input.custom_minimum_size = Vector2(220, 44)
	seed_input.max_length = 10
	seed_input.text = seed_draft
	seed_input.tooltip_text = "留空时用本次灰誓草稿种子：地图与三张誓约都由它决定。"
	options.add_child(seed_input)
	_spacer(options)
	if game.state.active:
		_button(options, "继续旅程", func():
			menu_open = false
			_refresh(), true)
		_button(options, "结束当前旅程", _confirm_abandon)
	_oath_draft_panel(setup)
	var begin_row := HBoxContainer.new()
	begin_row.add_theme_constant_override("separation", 10)
	setup.add_child(begin_row)
	_spacer(begin_row)
	var begin := _button(begin_row, _begin_run_caption(), _begin_run, true)
	begin.name = "BeginJourney"
	begin.custom_minimum_size.x = 252
	begin.disabled = bool(game.state.active)
	begin.tooltip_text = _begin_run_hint()
	oath_begin_button = begin
	seed_error = _paragraph(setup, "种子需要是 0 至 2147483647 的整数。", 16, RED)
	seed_error.name = "JourneySeedError"
	seed_error.visible = seed_error_visible
	seed_input.text_changed.connect(func(_text: String):
		seed_error.hide()
		_refresh_oath_draft())
	_refresh_oath_draft()
	_footer()


func _difficulty_name(level: int) -> String:
	match level:
		-2: return "故事"
		-1: return "轻松"
		0: return "初次长夜"
	return "进阶 %d" % level


func _difficulty_description(level: int) -> String:
	var description := str(DIFFICULTY_DETAILS.get(level, ""))
	return "进阶效果逐级叠加。" + description if level > 0 else description


func _oath_draft_panel(parent: Node) -> VBoxContainer:
	var panel := _panel(parent, Color(0.072, 0.078, 0.062, 0.95), Color(0.40, 0.35, 0.24, 0.75))
	panel.get_parent().name = "OathDraft"
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	panel.add_child(head)
	var mark := _label(head, _spaced("灰誓"), 12, GOLD)
	mark.add_theme_constant_override("outline_size", 0)
	var hint := _paragraph(head, "三张誓约由本次种子决定；选中一条带入整局，也可以不立誓。", 13, MUTED)
	hint.add_theme_constant_override("outline_size", 0)
	var skip := _button(head, "不立誓", _skip_oath)
	skip.name = "SkipOathButton"
	skip.custom_minimum_size = Vector2(96, 30)
	skip.add_theme_font_size_override("font_size", 13)
	var cards := HBoxContainer.new()
	cards.name = "OathCards"
	cards.add_theme_constant_override("separation", 10)
	panel.add_child(cards)
	oath_card_buttons.clear()
	for index in range(3):
		var card := Button.new()
		card.name = "OathCard_%d" % index
		card.custom_minimum_size = Vector2(0, 92)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.add_theme_font_size_override("font_size", 12)
		card.pressed.connect(_toggle_oath.bind(index))
		cards.add_child(card)
		oath_card_buttons.append(card)
	if oath_draft_seed < 0:
		oath_draft_seed = randi_range(0, 2147483647)
	oath_draft_active = true
	_refresh_oath_draft()
	return panel


func _oath_seed_value() -> int:
	var raw := seed_input.text.strip_edges() if is_instance_valid(seed_input) else ""
	if not raw.is_empty() and raw.is_valid_int():
		var parsed := int(raw)
		if parsed >= 0 and parsed <= 2147483647:
			return parsed
	return maxi(0, oath_draft_seed)


func _refresh_oath_draft() -> void:
	if oath_card_buttons.is_empty() or not is_instance_valid(oath_card_buttons[0]):
		return
	oath_draft_offers = game.oath_offers(_oath_seed_value())
	while oath_draft_offers.size() < 3:
		oath_draft_offers.append({})
	if not selected_oath.is_empty() and not oath_draft_offers.any(func(entry): return str(entry.get("id", "")) == selected_oath):
		selected_oath = ""
	for index in range(oath_card_buttons.size()):
		var card := oath_card_buttons[index]
		if not is_instance_valid(card):
			continue
		var entry: Dictionary = oath_draft_offers[index]
		_paint_oath_card(card, entry, not entry.is_empty() and str(entry.get("id", "")) == selected_oath)
	if is_instance_valid(oath_begin_button):
		oath_begin_button.text = _begin_run_caption()
		oath_begin_button.tooltip_text = _begin_run_hint()


func _paint_oath_card(card: Button, entry: Dictionary, picked: bool) -> void:
	if entry.is_empty():
		card.text = "誓约尚未显形"
		card.disabled = true
		return
	card.disabled = false
	var oath_name := str(entry.get("name", "誓约"))
	var kicker := str(entry.get("kicker", ""))
	card.text = "%s%s · %s\n恩惠：%s\n代价：%s\n%s" % [
		"◆ " if picked else "",
		oath_name,
		kicker,
		str(entry.get("boon", "")),
		str(entry.get("price", "")),
		"已立下此誓 · 再点一次撤销" if picked else "点一下立下这条誓约",
	]
	var fill := Color(0.158, 0.126, 0.082, 0.98) if picked else Color(0.088, 0.083, 0.068, 0.95)
	var edge := GOLD if picked else Color(0.34, 0.30, 0.23, 0.85)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state_name, _sts_box(fill, edge, 2 if picked else 1, picked))
	card.add_theme_color_override("font_color", PAPER if picked else Color("cfc4ae"))
	card.add_theme_color_override("font_hover_color", Color("f3e7cd"))
	card.tooltip_text = "%s · %s\n恩惠：%s\n代价：%s" % [oath_name, kicker, str(entry.get("boon", "")), str(entry.get("price", ""))]


func _toggle_oath(index: int) -> void:
	if index < 0 or index >= oath_draft_offers.size():
		return
	var entry: Dictionary = oath_draft_offers[index]
	if entry.is_empty():
		return
	var oath_id := str(entry.get("id", ""))
	selected_oath = "" if selected_oath == oath_id else oath_id
	_refresh_oath_draft()


func _skip_oath() -> void:
	selected_oath = ""
	_refresh_oath_draft()


func _begin_run_caption() -> String:
	var oath: Dictionary = game.oath_view(selected_oath)
	if oath.is_empty():
		return "立下灰誓  →"
	return "立下灰誓 · %s  →" % str(oath.get("name", "誓约"))


func _begin_run_hint() -> String:
	var lines: Array[String] = []
	var oath: Dictionary = game.oath_view(selected_oath)
	if not oath.is_empty():
		lines.append("已选 %s：%s" % [str(oath.get("name", "")), str(oath.get("boon", ""))])
		lines.append("代价：%s" % str(oath.get("price", "")))
	if oath_draft_seed >= 0:
		lines.append("草稿种子 %d：种子留空时用它决定地图与誓约。" % oath_draft_seed)
	if lines.is_empty():
		return "选择一条誓约，或直接出发。"
	return "\n".join(lines)


func _begin_run() -> void:
	var seed_value := -1
	var raw := seed_input.text.strip_edges() if is_instance_valid(seed_input) else ""
	if not raw.is_empty():
		if not raw.is_valid_int() or int(raw) < 0 or int(raw) > 2147483647:
			seed_error.show()
			seed_input.grab_focus()
			return
		seed_value = int(raw)
	elif oath_draft_seed >= 0:
		seed_value = oath_draft_seed
	var result: Dictionary = game.new_run(selected_role, seed_value, difficulty, selected_build_plan, selected_oath)
	if result.get("ok", false):
		menu_open = false
		selected_target = 0
	_accept(result)


func _hud() -> void:
	var frame := PanelContainer.new()
	frame.name = "HudBar"
	frame.add_theme_stylebox_override("panel", _sts_box(Color(0.062, 0.052, 0.043, 0.94), Color("4a3d2c"), 1))
	content.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	frame.add_child(row)
	var crest := VBoxContainer.new()
	crest.custom_minimum_size.x = 132
	crest.add_theme_constant_override("separation", 0)
	row.add_child(crest)
	var brand := _label(crest, "灰 誓", 23, GOLD, true)
	brand.add_theme_constant_override("outline_size", 0)
	var crest_line := HBoxContainer.new()
	crest_line.add_theme_constant_override("separation", 5)
	crest.add_child(crest_line)
	var role_caption := _label(crest_line, str(game.role_data(str(game.state.role)).get("name", "旅者")), 12, Color("9a8f79"))
	role_caption.add_theme_constant_override("outline_size", 0)
	var oath: Dictionary = game.current_oath()
	if not oath.is_empty():
		var oath_chip := _chip(crest_line, str(oath.get("name", "誓约")), GOLD)
		oath_chip.name = "OathChip"
		oath_chip.get_parent().tooltip_text = "%s · %s\n恩惠：%s\n代价：%s" % [str(oath.get("name", "")), str(oath.get("kicker", "")), str(oath.get("boon", "")), str(oath.get("price", ""))]
	if bool(game.state.get("daily", false)):
		var daily_modifier := _daily_modifier_name(str(game.state.get("daily_modifier", "")))
		var daily_chip := _chip(crest_line, "每日 · %s" % daily_modifier, Color("9fb6c8"))
		daily_chip.name = "DailyChip"
		daily_chip.get_parent().tooltip_text = "每日誓约 · %s\n今日与所有旅者共享同一场考验。" % daily_modifier
	var health := VBoxContainer.new()
	health.custom_minimum_size.x = 236
	health.add_theme_constant_override("separation", 1)
	row.add_child(health)
	var health_line := HBoxContainer.new()
	health_line.add_theme_constant_override("separation", 6)
	health.add_child(health_line)
	_label(health_line, "生命", 12, Color("9a8f79")).add_theme_constant_override("outline_size", 0)
	_spacer(health_line)
	_chip(health_line, "格挡 %d" % int(game.state.block), Color("9fb6c8"))
	var bar := _health_bar(health, int(game.state.hp), int(game.state.max_hp), Color("b4453c"))
	bar.custom_minimum_size.y = 14
	_hp_caption(bar, "%d / %d" % [int(game.state.hp), int(game.state.max_hp)], 12)
	if journey_game != null:
		_spacer(row)
		if game.state.room == "battle":
			_button(row, "重练", _start_tutorial.bind(str(game.state.role))).name = "RestartTutorialButton"
			_button(row, "退出练习", _exit_tutorial).name = "ExitTutorialButton"
		return
	var purse := VBoxContainer.new()
	purse.add_theme_constant_override("separation", 0)
	row.add_child(purse)
	var gold_label := _label(purse, "◈ %d" % int(game.state.gold), 19, GOLD)
	gold_label.add_theme_constant_override("outline_size", 0)
	var place_text := "工坊试玩" if workshop_return_game != null else "%s · 第 %d 层" % [str(_chapter().get("name", "长夜")), int(game.state.row) + 1]
	var place := _label(purse, place_text, 11, Color("9a8f79"))
	place.add_theme_constant_override("outline_size", 0)
	_spacer(row)
	var potions := HBoxContainer.new()
	potions.add_theme_constant_override("separation", 6)
	row.add_child(potions)
	for slot in range(3):
		var potion_name := "空"
		var description := "战斗中可以使用药剂，最多携带三瓶。"
		var potion: Dictionary = {}
		var exists: bool = slot < game.state.potions.size()
		if exists:
			potion = game.potion_data(str(game.state.potions[slot]))
			potion_name = str(potion.get("name", "药剂"))
			description = str(potion.get("description", ""))
		var button := Button.new()
		button.text = "" if exists else "空"
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size = Vector2(54, 48)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var fill: Color = Color(0.09, 0.08, 0.065, 0.9)
			if exists:
				fill = Color(0.16, 0.115, 0.075, 0.95) if state_name != "hover" else Color(0.23, 0.17, 0.10, 1.0)
			button.add_theme_stylebox_override(state_name, _sts_box(fill, Color("5a4a33") if exists else Color("322c24"), 1))
		button.disabled = not exists or game.state.room != "battle"
		button.tooltip_text = "%s\n%s" % [potion_name, description]
		button.pressed.connect(_use_potion.bind(slot))
		if exists:
			_add_item_icon(button, potion, "potion", 40.0)
		potions.add_child(button)
	var inventory := _icon_button(row, "遗", "遗物与随行道具 · 查看剩余节点与诅咒任务。", _show_relics)
	inventory.name = "ExpeditionInventory"
	var deck := _icon_button(row, "牌", "查看旅者牌组。", _show_deck.bind("view"))
	deck.name = "HudDeckButton"
	if workshop_return_game != null:
		if game.state.room == "battle":
			_button(row, "返回工坊", _leave_workshop_trial).name = "WorkshopReturnButton"
	else:
		_icon_button(row, "≡", "菜单：设置、图鉴与退出。", func():
			menu_open = true
			_refresh())


func _footer() -> void:
	var footer := HBoxContainer.new()
	content.add_child(footer)
	if journey_game != null or (menu_open and menu_page == "tutorial"):
		notice_label = _label(footer, tutorial_notice, 15, GOLD)
		_spacer(footer)
		_label(footer, "独立练习 · 不写入旅程存档", 14, MUTED)
		return
	notice_label = _label(footer, save_warning if not save_warning.is_empty() else notice, 15, RED if not save_warning.is_empty() else GOLD)
	notice_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice_label.tooltip_text = notice_label.text
	notice_label.mouse_filter = Control.MOUSE_FILTER_PASS
	notice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not save_warning.is_empty():
		_button(footer, "重试保存", func():
			if game.save_game():
				save_warning = ""
				notice = "旅程已保存。"
			else:
				save_warning = game.last_error
			_refresh())
	_label(footer, "工坊试玩 · 独立战斗" if workshop_return_game != null else "离线旅程 · 自动存档", 14, MUTED)


func _health_bar(parent: Node, hp: int, max_hp: int, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, max_hp)
	bar.value = hp
	bar.show_percentage = false
	bar.custom_minimum_size.y = 13
	if hp > 0 and float(hp) / float(maxi(1, max_hp)) <= 0.3:
		color = color.lightened(0.16)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("16130f")
	track.border_color = Color("3c362e")
	track.set_border_width_all(1)
	track.set_corner_radius_all(2)
	track.shadow_color = Color(0, 0, 0, 0.45)
	track.shadow_size = 2
	track.shadow_offset = Vector2(0, 1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	# 血条叠加层：受光、刻度、右端亮边、低血脉冲（也压在血量文字下面）。
	var vitals := BattleFlair.VitalOverlay.new()
	vitals.name = "VitalOverlay"
	vitals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(vitals)
	vitals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vitals.bind(bar, color)
	return bar


func _chapter() -> Dictionary:
	var chapters: Array = game.data.get("chapters", [])
	return chapters[clampi(int(game.state.chapter), 0, chapters.size() - 1)] if not chapters.is_empty() else {}


func _map() -> void:
	RouteScreen.build(self)


func _layout_map(surface: Control, nodes: Array, labels: Array, lines: Control) -> void:
	RouteScreen._layout_map(self, surface, nodes, labels, lines)


func _map_display_kind(node: Dictionary) -> String:
	return RouteScreen._map_display_kind(self, node)


func _map_kind_hint(kind: String) -> String:
	return RouteScreen._map_kind_hint(self, kind)


func _map_preview(row: int, lane: int, node: Dictionary, lines: Control, inspect: Label) -> void:
	RouteScreen._map_preview(self, row, lane, node, lines, inspect)


func _enter_node(lane: int) -> void:
	RouteScreen._enter_node(self, lane)


func _new_map_backdrop() -> Control:
	return MapBackdrop.new()


func _new_campfire_art() -> Control:
	return CampfireArt.new()


func _battle() -> void:
	_ensure_target()
	content.add_theme_constant_override("separation", 6)
	body.add_theme_constant_override("separation", 6)
	var context := HBoxContainer.new()
	context.name = "BattleContext"
	context.add_theme_constant_override("separation", 8)
	body.add_child(context)
	var kind_name := str(KIND_NAMES.get(str(game.state.encounter_kind), "战斗"))
	var location := "%s · %s · 第 %d 层" % [_chapter().get("name", "长夜"), kind_name, int(game.state.row) + 1]
	if workshop_return_game != null:
		location = "工坊试玩 · " + str(game.state.workshop_pack.title)
	elif journey_game != null:
		location = "旅者教学 · " + str(TutorialLessons.LESSONS[game.state.role].title)
	var place := _label(context, "◆ " + location, 14, Color("a8916b"))
	place.add_theme_constant_override("outline_size", 0)
	if workshop_return_game != null:
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		place.mouse_filter = Control.MOUSE_FILTER_PASS
		place.tooltip_text = "流派：%s\n%s\n天赋：%s" % [game.state.workshop_pack.build.name, game.state.workshop_pack.build.description, game.state.workshop_pack.talent.name]
	_spacer(context)
	for tool in [["战斗记事", _show_combat_log]]:
		var tool_button := _button(context, str(tool[0]), tool[1])
		tool_button.custom_minimum_size.y = 30
		tool_button.add_theme_font_size_override("font_size", 13)
	if journey_game == null:
		for tool in [["状态与技能", func(): _show_role_guide(str(game.state.role)), "RoleGuideBattle"], ["全部词条", _show_rules, "CombatGlossary"], ["虚弱 / 易伤", _show_attack_status_help, "CombatStatusHelp"]]:
			var tool_button := _button(context, str(tool[0]), tool[1])
			tool_button.name = str(tool[2])
			tool_button.custom_minimum_size.y = 30
			tool_button.add_theme_font_size_override("font_size", 13)
	var turn_badge := _label(context, "回合 %02d" % int(game.state.turn), 14, Color("a8916b"))
	turn_badge.add_theme_constant_override("outline_size", 0)
	var affix: Dictionary = game.elite_affix_view()
	if not affix.is_empty():
		var banner := PanelContainer.new()
		banner.name = "EliteAffixBanner"
		banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banner.add_theme_stylebox_override("panel", _sts_box(Color(0.105, 0.058, 0.05, 0.92), Color(0.66, 0.40, 0.30, 0.85), 1))
		body.add_child(banner)
		var affix_row := HBoxContainer.new()
		affix_row.add_theme_constant_override("separation", 10)
		banner.add_child(affix_row)
		var affix_tag := _label(affix_row, "◆ 精英词缀", 12, Color("c07a63"))
		affix_tag.add_theme_constant_override("outline_size", 0)
		affix_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label(affix_row, str(affix.get("name", "无名词缀")), 15, Color("e2b78c"), true)
		var affix_copy := _paragraph(affix_row, str(affix.get("description", "")), 14, Color("c9bda6"))
		affix_copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		banner.tooltip_text = "精英词缀只作用于这具精英本体，击败后消失。"
	var arena := PanelContainer.new()
	arena.name = "BattleArena"
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.add_theme_stylebox_override("panel", _sts_box(Color(0.048, 0.042, 0.036, 0.97), Color("54452f"), 1, true))
	body.add_child(arena)
	var backdrop := StsBackdrop.new()
	backdrop.chapter = int(game.state.chapter)
	backdrop.role = str(game.state.role)
	backdrop.wounded = float(game.state.hp) / float(maxi(1, game.state.max_hp)) <= 0.34
	arena.add_child(backdrop)
	var arena_row := HBoxContainer.new()
	arena_row.name = "ArenaRow"
	arena_row.add_theme_constant_override("separation", 44)
	arena.add_child(arena_row)
	var player_column := VBoxContainer.new()
	player_column.name = "PlayerColumn"
	player_column.custom_minimum_size.x = 296
	player_column.add_theme_constant_override("separation", 3)
	arena_row.add_child(player_column)
	var player_heading := HBoxContainer.new()
	player_heading.add_theme_constant_override("separation", 8)
	player_column.add_child(player_heading)
	var role_title := _label(player_heading, str(game.role_data(str(game.state.role)).get("name", "旅者")), 24, Color("ece0c6"), true)
	role_title.add_theme_constant_override("outline_size", 0)
	_spacer(player_heading)
	var block_label := _chip(player_heading, "格挡 %d" % int(game.state.block), Color("9fb6c8"))
	block_label.mouse_filter = Control.MOUSE_FILTER_PASS
	block_label.tooltip_text = KEYWORD_HELP["格挡"]
	var player_frame := PanelContainer.new()
	player_frame.name = "PlayerFrame"
	player_frame.custom_minimum_size = Vector2(296, 196)
	player_frame.add_theme_stylebox_override("panel", _sts_box(Color(0.07, 0.06, 0.05, 0.16), Color(0.80, 0.67, 0.42, 0.72), 1))
	player_column.add_child(player_frame)
	var player_altar := BattleFlair.Altar.new()
	player_altar.name = "PlayerAltar"
	player_altar.accent = GOLD
	player_altar.selected = true
	player_frame.add_child(player_altar)
	player_altar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var player_actor := _new_actor()
	player_actor.name = "PlayerActor"
	player_actor.custom_minimum_size = Vector2(272, 190)
	player_frame.add_child(player_actor)
	_configure_actor(player_actor)
	player_actor.setup(game.state.duplicate(true), game.role_data(str(game.state.role)), true)
	var player_details := _button(player_actor, "", func():
		if not combat_busy and overlay.get_child_count() == 0:
			_show_role_guide(str(game.state.role)))
	player_details.name = "PlayerPortraitDetails"
	player_details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_details.tooltip_text = "点击查看当前状态和职业技能"
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		player_details.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	combat_actors["player"] = player_actor
	var followers_shown := _show_battle_followers(player_column)
	if followers_shown:
		var compact_followers := get_viewport_rect().size.y < 860
		player_actor.custom_minimum_size.y = 120 if compact_followers else 142
		player_frame.custom_minimum_size.y = 126 if compact_followers else 148
	var player_bar_row := HBoxContainer.new()
	player_bar_row.add_theme_constant_override("separation", 6)
	player_column.add_child(player_bar_row)
	_label(player_bar_row, "生命", 11, Color("9a8f79")).add_theme_constant_override("outline_size", 0)
	var player_bar := _health_bar(player_bar_row, int(game.state.hp), int(game.state.max_hp), Color("b4453c"))
	player_bar.custom_minimum_size.y = 15
	player_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_caption(player_bar, "%d / %d" % [int(game.state.hp), int(game.state.max_hp)], 12)
	var player_scroll := ScrollContainer.new()
	player_scroll.name = "PlayerDetails"
	player_scroll.custom_minimum_size.y = 50
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	player_column.add_child(player_scroll)
	var player := VBoxContainer.new()
	player.add_theme_constant_override("separation", 3)
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(player)
	var player_status := _combat_status(player, game.state.status, "PlayerStatus", 14, Color("c3b28c"))
	player_status.text = _status_lines(player_status.text, 2)
	player_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_status.max_lines_visible = 4
	_paragraph(player, _class_summary(), 13, Color("a8916b"))
	var enemies := HBoxContainer.new()
	enemies.name = "EnemyRow"
	enemies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemies.alignment = BoxContainer.ALIGNMENT_CENTER
	enemies.add_theme_constant_override("separation", 18)
	arena_row.add_child(enemies)
	for index in range(game.state.enemies.size()):
		_enemy(enemies, index)
	var recommended_card := ""
	if journey_game != null:
		recommended_card = _tutorial_battle_hint()
	else:
		_battle_tactics(body)
	var divider := ColorRect.new()
	divider.color = Color(0.56, 0.44, 0.26, 0.35)
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(divider)
	var dock_frame := PanelContainer.new()
	dock_frame.name = "HandDockPanel"
	dock_frame.custom_minimum_size.y = 246
	dock_frame.add_theme_stylebox_override("panel", _sts_box(Color(0.045, 0.039, 0.033, 0.97), Color("4a3d2c"), 1, true))
	body.add_child(dock_frame)
	var dock := HBoxContainer.new()
	dock.name = "HandDock"
	dock.add_theme_constant_override("separation", 14)
	dock_frame.add_child(dock)
	var energy_now := int(game.state.energy)
	var orb_column := VBoxContainer.new()
	orb_column.custom_minimum_size.x = 124
	orb_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orb_column.add_theme_constant_override("separation", 2)
	dock.add_child(orb_column)
	var orb := StsOrb.new()
	orb.name = "EnergyOrb"
	orb.configure(energy_now, 3, heading_font)
	orb_column.add_child(orb)
	var marks := EnergyMarks.new()
	marks.set_energy(energy_now)
	marks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	orb_column.add_child(marks)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 2)
	dock.add_child(middle)
	var hint := "点击看牌 · 拖到敌人或战场出牌"
	if int(game.state.get("pending_discard", 0)) > 0:
		hint = "先完成主动弃牌选择，再继续出牌。"
	elif energy_now <= 0:
		hint = "点击看牌 · 能量已尽，仍可拖出 0 费牌"
	var hint_row := HBoxContainer.new()
	middle.add_child(hint_row)
	var hand_hint := _label(hint_row, hint, 13, Color("8f8877"))
	hand_hint.name = "HandTargetHint"
	hand_hint.set_meta("idle_text", hint)
	hand_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hand_hint.add_theme_constant_override("outline_size", 0)
	var scroll := ScrollContainer.new()
	scroll.name = "HandArea"
	scroll.custom_minimum_size.y = 216
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	middle.add_child(scroll)
	var turn_key := "%s:%d:%d:%d:%d" % [game.state.run_id, game.state.chapter, game.state.row, game.state.lane, game.state.turn]
	if journey_game == null:
		if turn_key != hand_scroll_turn:
			hand_scroll_turn = turn_key
			hand_scroll_offset = 0
		_restore_hand_scroll(scroll)
	var hand := HBoxContainer.new()
	hand.add_theme_constant_override("separation", 10)
	scroll.add_child(hand)
	for index in range(game.state.hand.size()):
		var card: Dictionary = game.card_view(game.state.hand[index])
		var unavailable: Array[String] = []
		if int(card.get("cost", 0)) > int(game.state.energy):
			unavailable.append("能量不足")
		if int(card.get("star_cost", 0)) > int(game.state.get("stars", 0)):
			unavailable.append("星辰不足")
		if int(card.get("soul_cost", 0)) > int(game.state.souls):
			unavailable.append("灵魂不足")
		if int(game.state.get("pending_discard", 0)) > 0:
			unavailable.append("先完成主动弃牌选择")
		var reason := " · ".join(unavailable)
		var button := _card(hand, game.state.hand[index], _show_hand_card_detail.bind(card, reason), Vector2(178, 218), "hand")
		button.gui_input.connect(_hand_card_input.bind(index, button))
		button.name = "HandCard_%d" % index
		button.disabled = not reason.is_empty()
		button.set_meta("unavailable_reason", reason)
		button.get_node("CardVisual").set_availability(reason)
		if reason.is_empty():
			button.mouse_default_cursor_shape = Control.CURSOR_DRAG
			var availability := button.get_node("CardVisual/Availability") as Label
			availability.text = "拖拽到战场出牌"
			if not recommended_card.is_empty() and game.state.hand[index].id == recommended_card:
				availability.text = "建议先打这张"
				availability.add_theme_color_override("font_color", GOLD)
				recommended_card = ""
		button.tooltip_text = _card_tooltip(card)
		if not str(card.get("area_kind", "")).is_empty():
			button.mouse_entered.connect(_preview_area_hint.bind(hand_hint, card))
			button.mouse_exited.connect(func():
				if drag_card_index < 0 and is_instance_valid(hand_hint):
					hand_hint.text = hint)
		if not reason.is_empty():
			button.tooltip_text += "\n无法施放：" + reason
		button.tooltip_text += "\n点击查看效果" if button.disabled else "\n点击查看效果 · 拖拽到战场出牌"
	if game.state.hand.is_empty():
		var empty := _label(hand, "手中已无卡牌，结束回合后重新抽牌。", 18, Color("8f8877"))
		empty.custom_minimum_size = Vector2(360, 0)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 186
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 6)
	dock.add_child(right)
	var end_turn_button := Button.new()
	end_turn_button.name = "EndTurnButton"
	end_turn_button.text = "结束回合" if int(game.state.get("pending_discard", 0)) <= 0 else "选择弃牌"
	end_turn_button.custom_minimum_size = Vector2(168, 62)
	end_turn_button.add_theme_font_size_override("font_size", 21)
	end_turn_button.add_theme_font_override("font", heading_font)
	end_turn_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	end_turn_button.tooltip_text = "把回合交给敌人。格挡通常在下回合开始清空；格挡保留能力可以阻止清空。"
	end_turn_button.add_theme_stylebox_override("normal", _sts_box(Color(0.34, 0.16, 0.12, 0.96), Color("b98a52"), 2, true))
	end_turn_button.add_theme_stylebox_override("hover", _sts_box(Color(0.46, 0.22, 0.15, 1.0), Color("e6c58a"), 2, true))
	end_turn_button.add_theme_stylebox_override("pressed", _sts_box(Color(0.24, 0.11, 0.09, 1.0), Color("d8b478"), 2))
	end_turn_button.add_theme_stylebox_override("disabled", _sts_box(Color(0.12, 0.10, 0.085, 0.9), Color("3a3228"), 1))
	end_turn_button.add_theme_color_override("font_color", Color("f2e2c4"))
	end_turn_button.add_theme_color_override("font_hover_color", Color("fff4de"))
	end_turn_button.pressed.connect(func() -> void:
		if is_instance_valid(end_turn_button) and not end_turn_button.text.is_empty():
			_sfx("click", 0.02, -14.0))
	end_turn_button.pressed.connect(_end_turn)
	right.add_child(end_turn_button)
	_apply_end_turn_coach(end_turn_button)
	var piles := VBoxContainer.new()
	piles.add_theme_constant_override("separation", 1)
	right.add_child(piles)
	var draw_pile := _label(piles, "抽牌  %d" % game.state.draw.size(), 14, Color("c9b98f"))
	draw_pile.name = "DrawPile"
	draw_pile.tooltip_text = "新卡牌从这里进入手牌；抽牌堆为空时，洗入弃牌堆。"
	var discard_pile := _label(piles, "弃牌  %d" % game.state.discard.size(), 14, Color("8f8877"))
	discard_pile.name = "DiscardPile"
	var exhaust_pile := _label(piles, "消耗  %d" % game.state.exhaust.size(), 14, Color("8f8877"))
	exhaust_pile.name = "ExhaustPile"
	if int(game.state.get("pending_discard", 0)) > 0:
		end_turn_button.tooltip_text = "出牌或结束回合前，先完成这次主动弃牌。"
		(func():
			if is_inside_tree() and not combat_busy and game.state.room == "battle" and int(game.state.get("pending_discard", 0)) > 0:
				_show_discard_choice()).call_deferred()


func _battle_tactics(parent: Control) -> void:
	var view: Dictionary = game.tactics_view(selected_target)
	var bar := HBoxContainer.new()
	bar.name = "TacticalBar"
	bar.add_theme_constant_override("separation", 12)
	parent.add_child(bar)
	var meter := _label(bar, "应变  %d / %d" % [int(view.points), int(view.max_points)], 19, GOLD)
	meter.name = "TacticalPoints"
	meter.tooltip_text = KEYWORD_HELP["应变"]
	meter.mouse_filter = Control.MOUSE_FILTER_PASS
	_label(bar, "每次 %d 点" % int(view.cost), 14, MUTED)
	var actions := HBoxContainer.new()
	actions.name = "TacticalActions"
	actions.add_theme_constant_override("separation", 6)
	bar.add_child(actions)
	for option in view.options:
		var title: String = str(option.get("title", option.name))
		var button := _button(actions, title, _use_tactic.bind(str(option.id)), bool(option.available))
		button.name = "BattleTactic_" + str(option.id)
		button.custom_minimum_size.y = 40
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		button.disabled = not bool(option.available)
		button.tooltip_text = str(option.description) + "\n消耗 %d 应变 · 不耗能量 · 每回合限一次" % int(view.cost)
		if not str(option.reason).is_empty():
			button.tooltip_text += "\n" + str(option.reason)
	var hint := _label(bar, "本回合战术已用 · 下回合恢复" if bool(view.used) else str(view.hint), 15, MUTED)
	hint.name = "TacticalHint"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.tooltip_text = "%s\n本回合已获得 %d / %d 点。\n%s" % [str(view.hint), int(view.gained), int(view.gain_limit), KEYWORD_HELP["应变"]]
	hint.mouse_filter = Control.MOUSE_FILTER_PASS


func _use_tactic(id: String) -> void:
	if combat_busy or drag_card_index >= 0:
		return
	_ensure_target()
	_present_combat(game.use_tactic(id, selected_target))


func _restore_hand_scroll(scroll: ScrollContainer) -> void:
	# The range is set by the container once its new hand has been laid out.
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	scroll.scroll_horizontal = hand_scroll_offset
	hand_scroll_offset = scroll.scroll_horizontal
	scroll.get_h_scroll_bar().value_changed.connect(func(value: float): hand_scroll_offset = int(value))


func _preview_area_hint(label: Label, card: Dictionary) -> void:
	if combat_busy or drag_card_index >= 0 or not is_instance_valid(label):
		return
	var living: int = game.state.enemies.filter(func(enemy): return int(enemy.hp) > 0).size()
	var verb := "群攻" if card.get("area_kind", "") == "attack" else "全体效果"
	label.text = "%s：影响 %d 个存活敌人%s" % [verb, living, "，另有单体目标" if card.get("requires_target", false) else "，无需选敌"]


func _enemy(parent: Node, index: int) -> void:
	var enemy: Dictionary = game.state.enemies[index]
	var definition: Dictionary = {}
	if workshop_return_game != null:
		definition = game.enemy_data(str(enemy.id))
	else:
		for candidate in game.data.enemies:
			if candidate.id == enemy.id:
				definition = candidate
				break
	var mechanic_hint := str(definition.get("mechanic_hint", ""))
	var alive := int(enemy.hp) > 0
	var column := VBoxContainer.new()
	column.name = "EnemyColumn_%d" % index
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.custom_minimum_size.x = 232
	parent.add_child(column)
	var selected: bool = index == selected_target and alive
	var threatening: bool = "攻击" in str(enemy.intent) or "施毒" in str(enemy.intent)
	var badge := PanelContainer.new()
	badge.name = "EnemyIntentBadge_%d" % index
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if alive:
		var tone := Color(0.30, 0.12, 0.10, 0.94) if threatening else Color(0.12, 0.17, 0.15, 0.94)
		var edge := Color("c08a5c") if threatening else Color("6f8468")
		badge.add_theme_stylebox_override("panel", _sts_box(tone, edge, 1))
	else:
		badge.add_theme_stylebox_override("panel", _sts_box(Color(0.10, 0.10, 0.09, 0.7), Color("3a3630"), 1))
	column.add_child(badge)
	# 图标 + 文字的横排：意图类型一眼可辨，文字仍是测试与提示的锚点。
	var intent_row := HBoxContainer.new()
	intent_row.name = "EnemyIntentRow_%d" % index
	intent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	intent_row.add_theme_constant_override("separation", 6)
	badge.add_child(intent_row)
	var intent_text := "已倒下"
	if alive:
		intent_text = str(enemy.intent).replace("▸ ", "").replace("◇ ", "")
		var glyph := BattleFlair.IntentGlyph.new()
		glyph.setup(intent_text, threatening)
		intent_row.add_child(glyph)
	var intent := _label(intent_row, intent_text, 15, Color("e7b7a0") if threatening else Color("c9c3a6"), threatening)
	intent.name = "EnemyIntent_%d" % index
	intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent.custom_minimum_size.x = 174
	intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intent.add_theme_constant_override("outline_size", 0)
	if not mechanic_hint.is_empty() and alive:
		intent.tooltip_text = _wrap_tooltip(mechanic_hint)
	_add_enemy_detail_button(intent, index, definition)
	var target := _button(column, "", _inspect_enemy.bind(index, definition))
	target.name = "EnemyTarget_%d" % index
	target.tooltip_text = "点击查看状态和行动" if selected or not alive else "点击查看并选为目标"
	if not mechanic_hint.is_empty() and alive:
		target.tooltip_text += "\n" + _wrap_tooltip(mechanic_hint)
	target.custom_minimum_size.y = 178
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		target.add_theme_stylebox_override(state_name, _sts_actor_frame(selected, not alive))
	var altar := BattleFlair.Altar.new()
	altar.name = "EnemyAltar_%d" % index
	altar.accent = GOLD
	altar.selected = selected
	altar.dead = not alive
	target.add_child(altar)
	altar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var actor := _new_actor()
	actor.name = "EnemyActor_%d" % index
	target.add_child(actor)
	actor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_configure_actor(actor)
	actor.setup(enemy.duplicate(true), definition, false)
	actor.set_selected(selected)
	combat_actors["enemy:%d" % index] = actor
	var rank_name := ""
	if not definition.is_empty():
		rank_name = {"elite": "精英", "boss": "首领"}.get(str(definition.get("kind", "")), "")
	if bool(enemy.get("escort", false)):
		rank_name = "小怪"
	var shown_name := str(enemy.name) if rank_name.is_empty() else "%s · %s" % [enemy.name, rank_name]
	if game.state.encounter_kind == "boss":
		shown_name += "  <%d>" % int(game.state.get("boss_phase", 1))
	var name_line := HBoxContainer.new()
	name_line.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(name_line)
	if selected:
		_chip(name_line, "目标", GOLD)
	var name_label := _label(name_line, shown_name, 20, Color("ece0c6") if alive else Color("7c776b"), true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_constant_override("outline_size", 0)
	var enemy_bar := _health_bar(column, int(enemy.hp), int(enemy.max_hp), Color("a84a3f"))
	enemy_bar.custom_minimum_size.y = 15
	_hp_caption(enemy_bar, "%d / %d" % [int(enemy.hp), int(enemy.max_hp)], 12)
	if int(enemy.block) > 0:
		var block_caption := _hp_caption(enemy_bar, "格挡 %d" % int(enemy.block), 12)
		block_caption.add_theme_color_override("font_color", Color("cdd9e2"))
	var status := _combat_status(column, enemy.status, "EnemyStatus_%d" % index, 13, Color("c3b28c"))
	status.text = _status_lines(status.text, 1)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.max_lines_visible = 2
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_constant_override("outline_size", 0)
	_add_enemy_detail_button(status, index, definition)


func _add_enemy_detail_button(strip: Control, index: int, definition: Dictionary) -> void:
	var button := Button.new()
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "点击查看敌人详情"
	if not strip.tooltip_text.is_empty():
		button.tooltip_text += "\n" + strip.tooltip_text
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	strip.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(_inspect_enemy.bind(index, definition, false))


func _inspect_enemy(index: int, definition: Dictionary, select_target: bool = true) -> void:
	if combat_busy or overlay.get_child_count() > 0:
		return
	_sfx("click", 0.01, -16.0)
	var enemy: Dictionary = game.state.enemies[index]
	var alive := int(enemy.hp) > 0
	if select_target and alive and selected_target != index:
		selected_target = index
		_refresh()
	var box := _modal(str(enemy.name), "生命 %d / %d  ·  格挡 %d" % [enemy.hp, enemy.max_hp, enemy.block])
	var scroll := ScrollContainer.new()
	scroll.name = "EnemyDetailScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_show_status_details(list, enemy.status)
	var action := _panel(list)
	action.name = "EnemyIntentDetails"
	_label(action, "下一步行动", 22, GOLD, true)
	var intent := str(enemy.intent)
	_paragraph(action, intent if alive else "已倒下，本场不会再行动。", 19, PAPER)
	if alive:
		for term in ["格挡", "施毒", "虚弱", "易伤", "力量", "荆棘", "蓄势", "困兽"]:
			if term in intent:
				var keyword: String = "中毒" if term == "施毒" else term
				_paragraph(action, "%s · %s" % [term, KEYWORD_HELP[keyword]], 17)
	_show_enemy_pattern(list, enemy, alive)
	var description := str(definition.get("description", ""))
	var mechanic := str(definition.get("mechanic_hint", ""))
	if not description.is_empty() or not mechanic.is_empty():
		var behavior := _panel(list)
		_label(behavior, "敌人特点", 22, GOLD, true)
		if not description.is_empty():
			_paragraph(behavior, description, 18, PAPER)
		if not mechanic.is_empty() and mechanic != description:
			_paragraph(behavior, mechanic, 18, PAPER)


func _show_enemy_pattern(parent: Control, enemy: Dictionary, alive: bool) -> void:
	var panel := _panel(parent)
	panel.name = "EnemyPatternDetails"
	var title := "招式顺序"
	if game.state.encounter_kind == "boss":
		title = "本阶段招式 · 第 %d / %d 阶段" % [int(game.state.boss_phase), int(game.state.boss_phases)]
	_label(panel, title, 22, GOLD, true)
	var pattern: Array = enemy.get("pattern", [])
	if pattern.is_empty():
		_paragraph(panel, "没有固定招式。", 18)
		return
	_paragraph(panel, "从上到下循环。攻击数值为本阶段基础伤害，当前预告见上方。", 17)
	var next_index := int(enemy.turn) % pattern.size() if alive else -1
	for index in pattern.size():
		var move: Dictionary = pattern[index]
		var effects: Array[String] = []
		for effect in move.get("effects", []):
			effects.append(_enemy_move_effect_text(effect))
		var name_text := str(move.get("intent", "招式 %d" % (index + 1)))
		if index == next_index:
			name_text += " · 下一步"
		var row_text := name_text + "\n" + ("等待" if effects.is_empty() else "\n".join(effects))
		_paragraph(panel, row_text, 18, GOLD if index == next_index else PAPER).name = "EnemyPatternStep_%d" % index


func _enemy_move_effect_text(effect: Dictionary) -> String:
	var op := str(effect.get("op", ""))
	var value := maxi(0, int(effect.get("value", 0)))
	var target := "自身" if effect.get("target", "") == "self" else "你"
	match op:
		"damage", "charge_strike", "echo_strike", "lifesteal", "block_damage", "summon":
			var hits := clampi(int(effect.get("hits", 1)), 1, 30)
			var attack := "攻击你，基础伤害 %d" % value
			if hits > 1:
				attack = "攻击你 %d 次，每次基础伤害 %d" % [hits, value]
			match op:
				"charge_strike": attack += "。若它本回合损失生命，攻击会被打断"
				"echo_strike": attack += "。本回合你从第 4 张牌起，每多打出一张，基础伤害 +2，最多 +6"
				"lifesteal": attack += "。按实际扣除的生命值回复自身生命"
				"block_damage": attack += "。将自身当前格挡加到每次攻击的基础伤害"
			return attack
		"block": return "自身获得 %d 点格挡" % value
		"sunder": return "移除你最多 %d 点格挡" % value
		"heal_ally": return "为损失生命最多的存活同伴回复最多 %d 点生命。没有受伤同伴时，自身获得 %d 点格挡" % [value, int(effect.get("fallback_block", 0))]
		"heal": return "自身回复最多 %d 点生命" % value
		"self_damage": return "自身失去 %d 点生命" % value
		"poison": return "使%s获得 %d 层中毒" % [target, value]
		"weak", "vulnerable": return "使%s%s %d 回合" % [target, STATUS_NAMES[op], value]
		"strength", "thorns", "regen": return "自身获得 %d 点%s" % [value, STATUS_NAMES[op]]
		"cleanse": return "清除自身的中毒、虚弱和易伤"
	return "其他效果"


func _status_text(status: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["weak", "vulnerable", "poison", "doom", "intangible"] + STATUS_NAMES.keys().filter(func(key): return key not in ["weak", "vulnerable", "poison", "doom", "intangible"]):
		if int(status.get(key, 0)) != 0:
			if key == "weak":
				parts.append("虚弱 %d 回合 · 打出攻击 −25%%" % int(status[key]))
			elif key == "vulnerable":
				parts.append("易伤 %d 回合 · 受到攻击 +50%%" % int(status[key]))
			elif key == "poison":
				parts.append("中毒 %d · 下回合开始失去生命" % int(status[key]))
			elif key == "doom":
				parts.append("灾厄 %d · 回合末生命不足则倒下" % int(status[key]))
			elif key == "intangible":
				parts.append("虚化 %d 回合 · 单次直接伤害至多 1" % int(status[key]))
			else:
				parts.append("%s %d" % [STATUS_NAMES[key], int(status[key])])
	return " · ".join(parts) if not parts.is_empty() else "无额外状态"


func _combat_status(parent: Node, status: Dictionary, node_name: String, font_size: int, color: Color) -> Label:
	var label := _paragraph(parent, _status_text(status), font_size, color)
	label.name = node_name
	var details := _status_details(status)
	if not details.is_empty():
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.tooltip_text = _wrap_tooltip("\n\n".join(details))
	return label


func _status_details(status: Dictionary) -> Array[String]:
	var details: Array[String] = []
	for key in STATUS_NAMES:
		var value := int(status.get(key, 0))
		if value != 0:
			var title := str(STATUS_NAMES[key])
			var shown := "剩余 %d 回合" % value if key in ["weak", "vulnerable", "frail", "intangible"] else "当前 %d" % value
			details.append("%s · %s\n%s" % [title, shown, KEYWORD_HELP[title]])
	return details


func _show_status_details(parent: Node, status: Dictionary) -> void:
	var panel := _panel(parent)
	panel.name = "CurrentStatusDetails"
	_label(panel, "当前状态", 22, GOLD, true)
	var details := _status_details(status)
	if details.is_empty():
		_paragraph(panel, "当前没有额外状态。", 18)
	for detail in details:
		_paragraph(panel, detail, 18, PAPER)


func _wrap_tooltip(value: String) -> String:
	var lines: Array[String] = []
	for line in value.split("\n"):
		if line.is_empty():
			lines.append("")
		else:
			for offset in range(0, line.length(), 42):
				lines.append(line.substr(offset, 42))
	return "\n".join(lines)


func _show_attack_status_help() -> void:
	var box := _modal("战斗状态 · 虚弱与易伤", "看清是谁身上的状态：虚弱影响打出去的攻击，易伤影响被打中时承受的攻击。")
	for keyword in ["虚弱", "易伤"]:
		var panel := _panel(box)
		_label(panel, keyword, 26, GOLD, true)
		_paragraph(panel, str(KEYWORD_HELP[keyword]), 21, PAPER)
	_paragraph(box, "两者同时存在：攻击者虚弱、被攻击者易伤时，10 × 0.75 × 1.5 = 11.25，向下取整为 11，再由格挡吸收。中毒、灾厄和充能球伤害不受这两种状态修正。", 18)
	_button(box, "查看全部战斗词条", _show_rules)


func _ensure_target() -> void:
	if selected_target >= 0 and selected_target < game.state.enemies.size() and int(game.state.enemies[selected_target].hp) > 0:
		return
	for index in range(game.state.enemies.size()):
		if int(game.state.enemies[index].hp) > 0:
			selected_target = index
			return


func _show_hand_card_detail(card: Dictionary, reason: String) -> void:
	if combat_busy or overlay.get_child_count() > 0 or int(game.state.get("pending_discard", 0)) > 0:
		return
	var hint := "拖到敌人身上出牌。" if card.get("requires_target", false) else "拖到战场出牌。"
	if not reason.is_empty():
		hint = "现在打不出这张牌 · " + reason
	var box := _modal(str(card.get("name", "卡牌")), hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_paragraph(scroll, _card_tooltip(card, false), 21, PAPER).name = "HandCardDetail"


func _hand_card_input(event: InputEvent, index: int, button: Button) -> void:
	if combat_busy or drag_card_index >= 0 or overlay.get_child_count() > 0 or int(game.state.get("pending_discard", 0)) > 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		drag_card_index = index
		drag_source = button
		drag_start = button.get_global_transform_with_canvas() * event.position
		drag_card_data = game.card_view(game.state.hand[index])
		button.accept_event()


func _input(event: InputEvent) -> void:
	if drag_card_index < 0:
		return
	if event is InputEventMouseMotion:
		_move_card_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var index := drag_card_index
		var destination := _card_drop_destination(event.position) if is_instance_valid(drag_ghost) else DROP_CANCEL
		var clicked: bool = not drag_moved and event.position.distance_to(drag_start) < CARD_DRAG_THRESHOLD and is_instance_valid(drag_source) and _has_viewport_point(drag_source, event.position)
		var card := drag_card_data
		var reason := str(drag_source.get_meta("unavailable_reason", "")) if clicked else ""
		_cancel_card_drag()
		if destination >= DROP_UNTARGETED:
			if destination >= 0:
				selected_target = destination
			_play_card(index)
		elif clicked:
			_show_hand_card_detail(card, reason)
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_cancel_card_drag()
	else:
		return
	get_viewport().set_input_as_handled()


func _card_drop_destination(point: Vector2) -> int:
	var arena := find_child("BattleArena", true, false) as Control
	if arena == null or not _has_viewport_point(arena, point):
		return DROP_CANCEL
	if not drag_card_data.get("requires_target", false):
		return DROP_UNTARGETED
	for index in range(game.state.enemies.size()):
		var enemy := arena.find_child("EnemyColumn_%d" % index, true, false) as Control
		if enemy != null and _has_viewport_point(enemy, point):
			return index if int(game.state.enemies[index].hp) > 0 else DROP_DEFEATED
	return selected_target if selected_target >= 0 and selected_target < game.state.enemies.size() and int(game.state.enemies[selected_target].hp) > 0 else DROP_CANCEL


func _has_viewport_point(control: Control, point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * point)


func _ensure_targeting_arrow() -> Control:
	if not is_instance_valid(targeting_arrow) or targeting_arrow.get_parent() != card_feedback_layer:
		targeting_arrow = StsTargeting.new()
		card_feedback_layer.add_child(targeting_arrow)
	return targeting_arrow


func _move_card_drag(point: Vector2) -> void:
	if not is_instance_valid(drag_ghost):
		if point.distance_to(drag_start) < CARD_DRAG_THRESHOLD:
			return
		drag_moved = true
		if drag_source.disabled:
			return
		drag_ghost = _card(card_feedback_layer, game.state.hand[drag_card_index], func(): pass, drag_source.size, "hand")
		drag_ghost.name = "DragCardGhost"
		drag_ghost.size = drag_source.size
		drag_ghost.modulate.a = 0.88
		_ignore_mouse(drag_ghost)
		drag_source.modulate.a = 0.35
		drag_target_outline = Panel.new()
		drag_target_outline.name = "DragTargetOutline"
		drag_target_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_target_outline.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, GOLD, 3))
		card_feedback_layer.add_child(drag_target_outline)
		if drag_card_data.get("requires_target", false):
			var arrow := _ensure_targeting_arrow()
			var card_start := card_feedback_layer.get_global_transform_with_canvas().affine_inverse() * (drag_source.get_global_rect().get_center() + Vector2(0, -drag_source.size.y * 0.35))
			arrow.start(card_start)
	var layer_from_viewport := card_feedback_layer.get_global_transform_with_canvas().affine_inverse()
	var ghost_limit := (card_feedback_layer.size - drag_ghost.size).max(Vector2.ZERO)
	var requires_target: bool = drag_card_data.get("requires_target", false)
	if requires_target:
		var resting_pos := (layer_from_viewport * drag_start) + Vector2(0, -48.0)
		drag_ghost.position = resting_pos.clamp(Vector2.ZERO, ghost_limit)
	else:
		drag_ghost.position = (layer_from_viewport * point + Vector2(18, 16)).clamp(Vector2.ZERO, ghost_limit)
	var destination := _card_drop_destination(point)
	var hint := find_child("HandTargetHint", true, false) as Label
	if is_instance_valid(hint):
		hint.add_theme_color_override("font_color", GOLD if destination >= DROP_UNTARGETED else Color("d7a097"))
	drag_target_outline.hide()
	var is_locked := false
	var snap_center := Vector2.ZERO
	var target_enemy_name := ""
	match destination:
		DROP_CANCEL:
			if is_instance_valid(hint):
				hint.text = "松手取消 · 拖入战场出牌"
		DROP_DEFEATED:
			if is_instance_valid(hint):
				hint.text = "目标已倒下 · 松手取消"
		DROP_UNTARGETED:
			if is_instance_valid(hint):
				hint.text = "松手出牌 · 无需指定目标"
		_:
			target_enemy_name = str(game.state.enemies[destination].name)
			if is_instance_valid(hint):
				hint.text = "松手：对「%s」出牌" % target_enemy_name
			var target := find_child("EnemyTarget_%d" % destination, true, false) as Control
			if is_instance_valid(target):
				var bounds: Rect2 = layer_from_viewport * target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)
				drag_target_outline.position = bounds.position
				drag_target_outline.size = bounds.size
				drag_target_outline.show()
				snap_center = bounds.get_center()
				is_locked = true
	if requires_target and is_instance_valid(targeting_arrow):
		var target_pt := layer_from_viewport * point
		targeting_arrow.update_target(target_pt, is_locked, snap_center, target_enemy_name)


func _cancel_card_drag() -> void:
	if drag_card_index < 0:
		return
	drag_card_index = -1
	drag_moved = false
	if is_instance_valid(targeting_arrow):
		targeting_arrow.stop()
	if is_instance_valid(drag_source):
		drag_source.modulate.a = 1.0
	drag_source = null
	drag_card_data = {}
	for visual in [drag_ghost, drag_target_outline]:
		if is_instance_valid(visual):
			card_feedback_layer.remove_child(visual)
			visual.queue_free()
	drag_ghost = null
	drag_target_outline = null
	var hint := find_child("HandTargetHint", true, false) as Label
	if hint != null:
		hint.text = str(hint.get_meta("idle_text"))
		hint.add_theme_color_override("font_color", MUTED)


func _play_card(index: int) -> void:
	if combat_busy:
		return
	_ensure_target()
	var card: Dictionary = {}
	if index >= 0 and index < game.state.hand.size():
		card = game.card_view(game.state.hand[index])
	var played := find_child("HandCard_%d" % index, true, false) as Control
	var result: Dictionary = game.play_card(index, selected_target)
	if result.get("ok", false) and played != null:
		played.pivot_offset = played.size * 0.5
		var drop := played.create_tween().set_parallel(true)
		drop.tween_property(played, "modulate:a", 0.28, 0.08)
		drop.tween_property(played, "scale", Vector2(0.94, 0.94), 0.1)
	_present_combat(result, card)


func _show_card_feedback(card: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "CardCastFeedback"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(size.x * 0.5 - 140, size.y * 0.53)
	panel.custom_minimum_size = Vector2(280, 60)
	var tone: Color = {"attack": Color("ba8070"), "skill": Color("8ca695"), "power": GOLD}.get(str(card.get("type", "skill")), GOLD)
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.10, 0.07, 0.95), tone))
	card_feedback_layer.add_child(panel)
	var kind_label := str(TYPE_NAMES.get(str(card.get("type", "skill")), "技能"))
	var label := _label(panel, "%s  ·  %s" % [kind_label, card.get("name", "卡牌")], 23, PAPER, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := panel.create_tween()
	tween.tween_property(panel, "position:y", panel.position.y - 16, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.10).from(0.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.28).set_delay(0.18)
	tween.tween_callback(panel.queue_free)


func _use_potion(slot: int) -> void:
	if combat_busy:
		return
	_ensure_target()
	_present_combat(game.use_potion(slot, selected_target))


func _has_playable_cards() -> bool:
	if game == null or game.state == null or game.state.room != "battle" or game.state.hand.is_empty():
		return false
	var energy: int = int(game.state.energy)
	var stars: int = int(game.state.get("stars", 0))
	var souls: int = int(game.state.souls)
	for card_data in game.state.hand:
		var view: Dictionary = game.card_view(card_data)
		if int(view.get("cost", 0)) <= energy \
			and int(view.get("star_cost", 0)) <= stars \
			and int(view.get("soul_cost", 0)) <= souls:
			return true
	return false


func _apply_end_turn_coach(button: Button) -> void:
	if not is_instance_valid(button):
		return
	if coach_pulse_tween and coach_pulse_tween.is_valid():
		coach_pulse_tween.kill()
	if int(game.state.get("pending_discard", 0)) > 0 or _has_playable_cards() or game.state.room != "battle":
		button.scale = Vector2.ONE
		return
	button.pivot_offset = button.size * 0.5
	coach_pulse_tween = button.create_tween().set_loops()
	coach_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	coach_pulse_tween.tween_property(button, "scale", Vector2(1.035, 1.035), 0.7)
	coach_pulse_tween.tween_property(button, "scale", Vector2.ONE, 0.7)


func _end_turn() -> void:
	if coach_pulse_tween and coach_pulse_tween.is_valid():
		coach_pulse_tween.kill()
	if not combat_busy:
		if int(game.state.get("pending_discard", 0)) > 0:
			_show_discard_choice()
		else:
			_present_combat(game.end_turn())


func _lock_combat_buttons(node: Node) -> void:
	if node is BaseButton:
		node.disabled = true
	for child in node.get_children():
		_lock_combat_buttons(child)


func _actor_at(key: String):
	var actor = combat_actors.get(key, battle_followers.get(key))
	return actor if is_instance_valid(actor) else null


func _show_battle_followers(parent: Control) -> bool:
	var osty_hp := int(game.state.get("osty_hp", 0))
	var show_osty: bool = game.state.role == "medium" or osty_hp > 0
	var spirits: Array = game.state.get("summons", [])
	var servants: int = game.state.hand.filter(func(card): return card.get("id") == "token_minion").size()
	if not show_osty and spirits.is_empty() and servants == 0:
		return false
	var group := VBoxContainer.new()
	group.name = "BattleFollowers"
	group.add_theme_constant_override("separation", 3)
	parent.add_child(group)
	_label(group, "己方随从 · 点击看效果", 13, GOLD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	group.add_child(row)
	if show_osty:
		var osty := _add_battle_follower(row, "OstyFollower", "osty", "奥斯蒂", "生命 %d" % osty_hp, "敌人攻击时，先扣你的格挡，奥斯蒂再用自己的生命替你挡下剩余伤害。\n你的回合开始时，它增加 1 点生命。召唤牌也能增加它的生命，或让它回来。\n它有生命时，打出写着「奥斯蒂攻击」的牌才会让它出手。")
		osty.set_health(osty_hp)
		battle_followers["osty"] = osty
	for index in spirits.size():
		var spirit: Dictionary = spirits[index]
		var power := int(spirit.get("power", 0))
		var turns := int(spirit.get("turns", 0))
		if turns <= 0:
			continue
		var follower := _add_battle_follower(row, "SpiritFollower_%d" % index, "spirit", "幽魂 %d" % (index + 1), "伤%d · %d回合" % [power, turns], "你结束回合后、敌人行动前，幽魂自动攻击第一个还活着的敌人，造成 %d 点伤害。敌人的格挡可以挡住。\n还能行动 %d 次，之后消失。" % [power, turns])
		battle_followers["summon:%d" % index] = follower
	if servants > 0:
		var card: Dictionary = game.card_view({"id": "token_minion", "upgraded": false})
		_add_battle_follower(row, "ServantCards", "servant", "侍从牌", "手中 %d 张" % servants, "侍从是手里的临时牌。拖出「%s」时消耗 %d 点能量。%s" % [card.name, card.cost, card.description])
	return true


func _add_battle_follower(parent: Control, node_name: String, kind: String, title: String, detail: String, tooltip: String) -> CombatFollower:
	var follower := CombatFollower.new()
	follower.name = node_name
	parent.add_child(follower)
	_configure_actor(follower)
	follower.setup(kind, title, detail, tooltip, get_viewport_rect().size.y < 860)
	follower.pressed.connect(func():
		if combat_busy or overlay.get_child_count() > 0:
			return
		var box := _modal(title, follower.detail_label.text)
		_paragraph(box, follower.tooltip_text, 21, PAPER).name = "FollowerDetail")
	return follower


func _present_combat(result: Dictionary, card: Dictionary = {}) -> void:
	_cancel_card_drag()
	# Rules commit once, synchronously. Keep the old actors alive until feedback finishes.
	_record_result(result)
	if not result.get("ok", false) or combat_actors.is_empty():
		_accept(result)
		return
	var events: Array = game.combat_events.duplicate(true)
	if events.is_empty():
		_accept(result)
		if not card.is_empty():
			_sfx("card", 0.03, -6.0)
			_show_card_feedback(card)
		return
	combat_busy = true
	var generation := _combat_generation
	var draws: Array = []
	var new_turn := false
	_lock_combat_buttons(content)
	var end_button = find_child("EndTurnButton", true, false)
	if end_button != null:
		end_button.text = "交锋中…"
	if not card.is_empty():
		_sfx("card", 0.03, -6.0)
		_show_card_feedback(card)
	if card.get("area_kind", "") == "attack":
		var area_points: Array = []
		for event in events:
			var key := str(event.get("target", ""))
			if event.get("kind", "") == "damage" and key.begins_with("enemy:"):
				var target = _actor_at(key)
				if target != null and not area_points.has(target.get_impact_position()):
					area_points.append(target.get_impact_position())
		if not area_points.is_empty():
			combat_effects.play_area(area_points)
			_begin_shake(6.0)
	# Large multi-hit effects accelerate; even maximum-hit cards have a bounded display time.
	var speed := float(game.profile.settings.get("combat_speed", 1.0))
	var beat := minf(0.16, 3.0 / maxf(1.0, float(events.size()))) / speed
	for event in events:
		if generation != _combat_generation or not is_inside_tree():
			return
		var kind := str(event.get("kind", ""))
		if kind == "turn_end":
			_show_turn_banner("回合结束", "敌人即将行动", RED)
			_animate_discard()
			_sfx("card", 0.0, -12.0, 0.72)
			await get_tree().create_timer(0.32 / speed).timeout
			continue
		if kind == "turn_start":
			new_turn = true
			var osty = _actor_at("osty")
			if osty != null and game.state.role == "medium":
				osty.set_health(osty.health + 1)
			continue
		if kind == "draw":
			draws.append(event)
			continue
		var target = _actor_at(str(event.get("target", "")))
		if target == null:
			continue
		var point: Vector2 = target.get_impact_position()
		var source_key := str(event.get("source", ""))
		var source = _actor_at(source_key)
		var follower_attack := source_key == "osty" or source_key.begins_with("summon:")
		if follower_attack and source == null:
			source = _actor_at("player")
		match str(event.get("kind", "")):
			"damage":
				if source != null and source != target:
					if not follower_attack or battle_followers.has(source_key):
						source.play_attack()
					var style := str(event.get("style", "slash"))
					if follower_attack or (source_key == "player" and str(game.state.role) in ["ranger", "medium", "arcanist", "sister"]):
						style = "projectile"
					elif source.archetype in ["caster", "eye", "sovereign"]:
						style = "projectile"
					combat_effects.play_attack(source.get_impact_position(), point, style, GOLD if source_key == "player" or follower_attack else RED)
					# 受击等待与攻击动作的命中点对齐：之前固定 0.072s，目标会在挥臂/弹道到达前先受击。
					var impact_wait: float = beat * 0.45
					if source.has_method("attack_impact_delay"):
						impact_wait = clampf(source.attack_impact_delay(), beat * 0.45, 0.20) / speed
					await get_tree().create_timer(impact_wait).timeout
					if generation != _combat_generation or not is_instance_valid(target):
						return
				var amount := int(event.get("amount", 0))
				var blocked := int(event.get("blocked", 0))
				target.play_hit(amount, blocked)
				if blocked > 0:
					target.play_guard()
				combat_effects.play_hit(point, amount, blocked, source_key == "poison")
				if source_key in ["thorns", "self"]:
					combat_effects.play_status(point + Vector2(0, 28), "荆棘反伤" if source_key == "thorns" else "生命代价", MUTED)
				if amount > 0:
					if source_key == "poison":
						_sfx("slash", 0.02, -16.0, 0.62)
					else:
						_sfx("slash", 0.05, -5.0, 0.86 if source_key == "self" else 1.0)
					var hurt_player := str(event.get("target", "")) == "player"
					_pulse_impact(1.2 if hurt_player else 0.95, hurt_player)
					_begin_shake(8.0 if hurt_player else 5.5)
					_hold_actors(true)
					var pause := (0.062 / speed) if events.size() <= 2 else minf(0.045 / speed, beat * 0.28)
					await get_tree().create_timer(pause).timeout
					if generation != _combat_generation or not is_inside_tree():
						return
					_hold_actors(false)
				elif blocked > 0:
					_sfx("shield", 0.03, -8.0)
					_begin_shake(1.8)
			"death":
				target.play_death()
				combat_effects.play_death(point)
				_pulse_impact(1.15, str(event.get("target", "")) == "player")
				_begin_shake(7.0)
				if str(event.get("target", "")) != "player":
					_sfx("bell", 0.02, -12.0, 0.9)
			"osty_guard":
				if source != null and battle_followers.has("osty"):
					source.set_health(source.health - int(event.amount))
					point = source.get_impact_position()
					source.play_guard()
				else:
					target.play_guard()
				combat_effects.play_status(point, "奥斯蒂承伤 %d" % int(event.amount), Color("b59acb"))
			"phase":
				_show_turn_banner("首领 · 阶段 %d" % int(event.amount), "誓约未尽，交锋继续", RED)
				target.play_guard()
				combat_effects.play_status(point, "阶段 %d / %d" % [int(event.amount), int(game.state.boss_phases)], GOLD)
				_sfx("bell", 0.0, -9.0, 0.8)
			"heal":
				target.play_heal()
				combat_effects.play_heal(point, int(event.amount))
				_sfx("heal", 0.03, -7.0)
			"block":
				target.play_guard()
				combat_effects.play_status(point, "格挡 +%d" % int(event.amount), GREEN)
				_sfx("shield", 0.04, -8.0)
			"status":
				var key := str(event.get("style", ""))
				var label: String = {"osty":"奥斯蒂生命", "lightning":"闪电球", "frost":"冰霜球", "dark":"黑暗球", "plasma":"等离子球", "glass":"玻璃球", "resonance":"回响"}.get(key, STATUS_NAMES.get(key, key))
				var amount := int(event.amount)
				var osty = _actor_at("osty") if key == "osty" else null
				if osty != null:
					osty.set_health(osty.health + amount)
					point = osty.get_impact_position()
				var status_text := "格挡 −%d" % amount if key == "sunder" else "%s +%d" % [label, amount]
				target.play_status_effect(key)
				var tint := Color("e56f5c") if key == "vulnerable" else Color("8dd3e2") if key == "weak" else Color("91d49a") if key in ["regen", "poison"] else GOLD
				combat_effects.play_status(point, status_text, tint)
		await get_tree().create_timer(beat).timeout
	if generation != _combat_generation or not is_inside_tree():
		return
	await get_tree().create_timer(0.36 / speed).timeout
	if generation == _combat_generation and is_inside_tree():
		combat_busy = false
		_accept(result)
		if game.state.room == "battle" and (not draws.is_empty() or new_turn):
			_animate_draws(draws, new_turn)


func _show_turn_banner(title_text: String, subtitle: String, tone: Color = GOLD) -> void:
	var banner := PanelContainer.new()
	banner.name = "TurnBanner"
	banner.position = Vector2(size.x * 0.5 - 210, size.y * 0.40 - 36)
	banner.custom_minimum_size = Vector2(420, 76)
	banner.add_theme_stylebox_override("panel", _style(Color(0.035, 0.043, 0.035, 0.94), tone))
	card_feedback_layer.add_child(banner)
	var lines := VBoxContainer.new()
	banner.add_child(lines)
	var title_label := _label(lines, title_text, 29, tone, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle_label := _label(lines, subtitle, 14, PAPER)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignore_mouse(banner)
	var tween := banner.create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.07).from(0.0)
	tween.tween_property(banner, "modulate:a", 0.0, 0.12).set_delay(0.14)
	tween.tween_callback(banner.queue_free)


func _pile_position(node_name: String) -> Vector2:
	var pile := find_child(node_name, true, false) as Control
	return pile.get_global_rect().get_center() - card_feedback_layer.global_position if pile != null else Vector2(size.x - 220, size.y - 290)


## 二次贝塞尔取点：飞牌走一条弧线，比直线位移更像“被抽出来”。
func _flight_point(start: Vector2, control: Vector2, finish: Vector2, progress: float) -> Vector2:
	var inverse := 1.0 - progress
	return start * inverse * inverse + control * 2.0 * inverse * progress + finish * progress * progress


## 牌堆标签落点反馈：只是提亮一下，不改变布局和计数。
func _pulse_pile(node_name: String, delay: float, tint: Color) -> void:
	var pile := find_child(node_name, true, false) as Control
	if pile == null:
		return
	var tween := pile.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_property(pile, "modulate", tint, 0.09)
	tween.tween_property(pile, "modulate", Color.WHITE, 0.26)


func _animate_discard() -> void:
	var area := find_child("HandArea", true, false) as Control
	if area == null:
		return
	var destination := _pile_position("DiscardPile")
	var speed := float(game.profile.settings.get("combat_speed", 1.0))
	var reduced := bool(game.profile.settings.get("reduced_motion", false))
	var travel := (0.22 if reduced else 0.30) / speed
	var cards: Array[Control] = []
	for button in area.find_children("HandCard_*", "Button", true, false):
		var visual = button.get_node("CardVisual")
		if visual.card.get("retain", false) or not area.get_global_rect().intersects(button.get_global_rect()):
			continue
		cards.append(button)
	var last_delay := 0.0
	for index in cards.size():
		var button := cards[index]
		var visual = button.get_node("CardVisual")
		var ghost := _card(card_feedback_layer, visual.card, func(): pass, button.size, "hand")
		ghost.name = "DiscardGhost"
		var start := button.global_position - card_feedback_layer.global_position
		ghost.position = start
		ghost.pivot_offset = ghost.size * 0.5
		_ignore_mouse(ghost)
		button.modulate.a = 0.0
		var delay := minf(index * 0.03, 0.20) / speed
		last_delay = maxf(last_delay, delay)
		var fan := float(index) - (cards.size() - 1) * 0.5
		var finish := destination - ghost.size * 0.5 + Vector2(fan * 2.0, 0)
		var control := start.lerp(finish, 0.5) + Vector2(46.0 + fan * 6.0, -74.0 - absf(fan) * 4.0)
		var spin := 0.0 if reduced else (0.10 + 0.02 * float(index % 3)) * (1.0 if index % 2 == 0 else -1.0)
		var tween := ghost.create_tween()
		tween.tween_interval(delay)
		# 先抬手再被收起：有预备动作，丢弃不再是一起塌下去。
		tween.tween_property(ghost, "position", start + Vector2(0, -9), 0.05 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(ghost, "scale", Vector2.ONE * 1.04, 0.05 / speed)
		tween.tween_method(func(progress: float): ghost.position = _flight_point(start + Vector2(0, -9), control, finish, progress), 0.0, 1.0, travel).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(ghost, "scale", Vector2(0.40, 0.40), travel).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(ghost, "rotation", spin, travel)
		tween.parallel().tween_property(ghost, "modulate:a", 0.12, travel * 0.6).set_delay(travel * 0.45)
		tween.tween_callback(ghost.queue_free)
	if cards.is_empty():
		return
	_pulse_pile("DiscardPile", last_delay + travel * 0.9, Color("e9d6a8"))


func _animate_draws(draws: Array, new_turn: bool = false) -> void:
	# The new hand is already committed. Only its visible presentation moves.
	combat_busy = true
	var generation := _combat_generation
	_lock_combat_buttons(content)
	for draw in draws:
		var button := find_child("HandCard_%d" % int(draw.hand_index), true, false) as Control
		if button != null:
			button.modulate.a = 0.0
	for ignored in 2:
		await get_tree().process_frame
		if generation != _combat_generation or not is_inside_tree():
			return
	if new_turn:
		_show_turn_banner("你的回合", "第 %d 回合 · 能量 %d" % [int(game.state.turn), int(game.state.energy)])
	var area := find_child("HandArea", true, false) as Control
	var origin := _pile_position("DrawPile")
	var speed := float(game.profile.settings.get("combat_speed", 1.0))
	var reduced := bool(game.profile.settings.get("reduced_motion", false))
	var travel := (0.24 if reduced else 0.36) / speed
	var settle := 0.12 / speed
	var visible_count := 0
	var last_delay := 0.0
	if not draws.is_empty():
		_pulse_pile("DrawPile", 0.0, Color("f0dfb6"))
	for draw in draws:
		var button := find_child("HandCard_%d" % int(draw.hand_index), true, false) as Control
		if button == null or area == null:
			continue
		var rect := button.get_global_rect()
		if not area.get_global_rect().encloses(rect):
			button.modulate.a = 1.0
			continue
		var ghost := _card(card_feedback_layer, draw.card, func(): pass, button.size, "hand")
		ghost.name = "DrawGhost_%d" % int(draw.hand_index)
		ghost.get_node("CardVisual/Availability").text = "进入手牌"
		ghost.pivot_offset = ghost.size * 0.5
		var start := origin - ghost.size * 0.5
		var finish := rect.position - card_feedback_layer.global_position
		# 每张牌错开一点起飞，并沿着自己的弧线扇开，避免叠成一条线。
		var delay := minf(visible_count * 0.062, 0.30) / speed
		last_delay = maxf(last_delay, delay)
		var fan := 0.0 if reduced else (float(visible_count % 5) - 2.0) * 10.0
		var lift := -40.0 if reduced else -96.0 - float(visible_count % 3) * 6.0
		var control := start.lerp(finish, 0.45) + Vector2(fan, lift)
		ghost.position = start
		ghost.scale = Vector2(0.24, 0.24)
		ghost.rotation = 0.0 if reduced else -0.22 + 0.05 * float(visible_count % 3)
		ghost.modulate.a = 0.0
		_ignore_mouse(ghost)
		var tween := ghost.create_tween()
		tween.tween_interval(delay)
		tween.tween_callback(func(): _sfx("card", 0.0, -15.0, 1.06 + 0.03 * float(visible_count % 3)))
		# 位置用曲线减速落位，缩放略有过冲，最后一帧再收回手牌原位。
		tween.tween_method(func(progress: float): ghost.position = _flight_point(start, control, finish, progress), 0.0, 1.0, travel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(ghost, "scale", Vector2.ONE * 1.03, travel * 0.84).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(ghost, "rotation", 0.0, travel).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(ghost, "modulate:a", 1.0, 0.08 / speed)
		# 落位瞬间亮起手牌并让残影淡出，衔接真实卡牌。
		tween.tween_callback(func():
			if is_instance_valid(button):
				button.modulate.a = 1.0
				var visual := button.get_node_or_null("CardVisual")
				if visual != null:
					var glow := button.create_tween()
					glow.tween_property(visual, "glow", 0.80, 0.05 / speed)
					glow.tween_property(visual, "glow", 0.0, 0.24 / speed))
		tween.parallel().tween_property(ghost, "scale", Vector2.ONE, settle).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(ghost, "modulate:a", 0.0, settle)
		tween.tween_callback(ghost.queue_free)
		visible_count += 1
	if not draws.is_empty():
		# 往上偏开，避免压住右下角的「抽牌 N」计数。
		combat_effects.play_status(origin + combat_effects.global_position + Vector2(-96, -58), "抽牌 +%d" % draws.size(), GOLD)
	await get_tree().create_timer(maxf(last_delay + travel + settle + 0.08, (0.60 if not draws.is_empty() else 0.36) / speed)).timeout
	if generation == _combat_generation and is_inside_tree():
		_refresh()


func _card(parent: Node, instance: Dictionary, callback: Callable, dimensions: Vector2 = Vector2(230, 290), context: String = "browse") -> Button:
	var card: Dictionary = game.card_view(instance)
	var button := _button(parent, "", callback)
	button.custom_minimum_size = dimensions
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	var visual := CardVisual.new()
	button.add_child(visual)
	visual.configure(button, card, dimensions, heading_font, context)
	if context in ["compare", "preview"]:
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW
		button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = _card_tooltip(card)
	return button


func _class_summary() -> String:
	match str(game.state.role):
		"bellscribe": return "回响 %d / 6\n蓄满3点可打出回响追加效果" % int(game.state.status.get("resonance", 0))
		"ashlamper": return "给目标叠加余烬印记\n引燃清空目标印记并造成伤害"
		"warden": return "力量 %d · 消耗联动\n格挡 +%d / 抽牌 +%d" % [int(game.state.status.get("strength", 0)), int(game.state.status.get("exhaust_block", 0)), int(game.state.status.get("exhaust_draw", 0))]
		"ranger": return "小刀 / 中毒 / 机巧\n主动弃牌可触发免费施放"
		"arcanist": return "星辰 %d · 锻造 %d\n君王之剑基础伤害 %d" % [int(game.state.get("stars", 0)), int(game.state.get("blade", 0)), 10 + int(game.state.get("blade", 0))]
		"medium": return "奥斯蒂生命 %d\n灾厄在敌人回合结束时收割" % int(game.state.get("osty_hp", 0))
		"sister":
			var names: Array[String] = []
			for orb in game.state.get("orbs", []):
				names.append({"lightning":"雷", "frost":"冰", "dark":"暗%d" % int(orb.value), "plasma":"能", "glass":"璃%d" % int(orb.value)}.get(str(orb.kind), "球"))
			return "集中 %d · 球槽 %d / %d\n%s" % [int(game.state.status.get("focus", 0)), names.size(), int(game.state.get("orb_slots", 3)), " → ".join(names) if not names.is_empty() else "尚未生成充能球"]
	return ""


func _show_role_guide(role_id: String) -> void:
	if not RoleGuide.GUIDES.has(role_id):
		return
	var role: Dictionary = game.role_data(role_id)
	var guide: Dictionary = RoleGuide.GUIDES[role_id]
	var in_battle: bool = not menu_open and game.state.room == "battle" and str(game.state.role) == role_id
	var heading := "状态与技能" if in_battle else "角色指南"
	var box := _modal("%s · %s" % [heading, role.get("name", "旅者")], str(guide.lead))
	var layout := HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 20)
	box.add_child(layout)
	var art := VBoxContainer.new()
	art.custom_minimum_size.x = 190
	layout.add_child(art)
	var portrait := TextureRect.new()
	portrait.name = "GuidePortrait"
	portrait.texture = preload("res://ui/role_art.gd").texture_for(role_id)
	portrait.custom_minimum_size = Vector2(190, 300)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(portrait)
	_paragraph(art, str(role.get("title", "旅者")), 16, GOLD)
	var scroll := ScrollContainer.new()
	scroll.name = "RoleGuideScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	if in_battle:
		_show_current_player_effects(list)
		_label(list, "职业技能", 22, GOLD, true)
	for section in guide.sections:
		var row := _panel(list, Color(0.10, 0.12, 0.10, 0.98), Color(str(role.get("color", "#c7a66a"))))
		_label(row, "%s  %s" % [section[0], section[1]], 22, GOLD, true)
		_paragraph(row, str(section[2]), 18, PAPER)
	if in_battle:
		_show_carried_effects(list)


func _show_current_player_effects(parent: Node) -> void:
	var snapshot := _panel(parent)
	snapshot.name = "PlayerCurrentEffects"
	_label(snapshot, "本场战斗", 22, GOLD, true)
	var tactics: Dictionary = game.tactics_view(selected_target)
	_paragraph(snapshot, "生命 %d / %d  ·  格挡 %d  ·  能量 %d  ·  应变 %d / %d" % [game.state.hp, game.state.max_hp, game.state.block, game.state.energy, tactics.points, tactics.max_points], 19, PAPER)
	var resources := _class_summary()
	if not resources.is_empty():
		_paragraph(snapshot, resources, 18, PAPER)
	_show_status_details(parent, game.state.status)


func _show_carried_effects(parent: Node) -> void:
	if game.state.items.is_empty() and game.state.relics.is_empty():
		return
	var carried := _panel(parent)
	_label(carried, "携带的道具与遗物", 22, GOLD, true)
	for id in game.state.items:
		var item_id := str(id)
		var item: Dictionary = game.item_data(item_id)
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 12)
		carried.add_child(entry)
		_add_item_icon(entry, item, "item", 38.0)
		var item_copy := VBoxContainer.new()
		item_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(item_copy)
		_label(item_copy, str(item.get("name", item_id)), 18, GOLD, true)
		_paragraph(item_copy, _expedition_item_detail(item_id), 16, PAPER)
	for id in game.state.relics:
		var relic_id := str(id)
		var relic: Dictionary = game.relic_data(relic_id)
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 12)
		carried.add_child(entry)
		_add_item_icon(entry, relic, "relic", 38.0)
		var relic_copy := VBoxContainer.new()
		relic_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(relic_copy)
		_label(relic_copy, str(relic.get("name", relic_id)), 18, GOLD, true)
		_paragraph(relic_copy, str(relic.get("description", "")), 16, PAPER)


func _show_rules() -> void:
	var box := _modal("英雄玩法说明", str(game.role_data(str(game.state.role)).get("description", "")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_paragraph(list, "灰誓成长：每4场胜利提高1历练，生命上限+3并回复5；每2级增加1回合格挡（最多4），每3级增加1初始力量（最多3）。换章生命上限+8并回复35%，基础能量3→4，抽牌5→6。", 17, GOLD)
	_paragraph(list, "卡池逐章展开：每职业44张。第一章开放18张（含4种初始牌），之后依次加入10 / 8 / 8张；后期逐步加入持续触发、资源转换和多段联动。永久胜场解锁仍在新旅程生效。", 17, GOLD)
	for group in KEYWORD_GROUPS:
		_label(list, str(group), 26, GOLD, true)
		for keyword in KEYWORD_GROUPS[group]:
			var row := _panel(list)
			_label(row, keyword, 21, GOLD, true)
			_paragraph(row, str(KEYWORD_HELP[keyword]), 17, PAPER)


func _show_discard_choice() -> void:
	var box := _modal("主动弃牌 · 还需 %d 张" % int(game.state.get("pending_discard", 0)), "点击要弃置的牌。带机巧的牌会免费打出；其余牌进入弃牌堆。")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	for index in game.state.hand.size():
		var pick := _card(grid, game.state.hand[index], _choose_discard.bind(index), Vector2(210, 254), "reward")
		pick.name = "DiscardCard_%d" % index
		var recommended: bool = journey_game != null and game.state.hand[index].id == "ranger_08"
		pick.get_node("CardVisual/Availability").text = "推荐弃置 · 免费打出" if recommended else "选择弃置此牌"


func _choose_discard(index: int) -> void:
	if combat_busy:
		return
	_clear(overlay)
	_present_combat(game.choose_discard(index, selected_target))


func _card_tooltip(card: Dictionary, wrap: bool = true) -> String:
	var detail := str(card.get("description", "")).replace("。", "。\n")
	var tags: Array[String] = [str(TYPE_NAMES.get(str(card.get("type", "skill")), "技能")), str(RARITY_NAMES.get(str(card.get("rarity", "common")), "普通"))]
	var area_kind := str(card.get("area_kind", ""))
	var scope := ""
	if not area_kind.is_empty():
		scope = "群攻" if area_kind == "attack" else "全体效果"
		tags.append(scope + ("；另需选择单体目标" if card.get("requires_target", false) else "；无需选择目标"))
	if card.get("upgraded", false):
		tags.append("已升级")
	if card.get("type", "") == "power":
		tags.append("能力：移出循环，不触发消耗")
	elif card.get("exhaust", false):
		tags.append("消耗：本场战斗不再抽到此牌")
	if card.has("min_chapter") and card.get("rarity", "") != "starter":
		tags.append("第%d章起进入奖励与商店池" % (int(card.min_chapter) + 1))
	if card.get("retain", false):
		tags.append("保留：回合结束留在手中")
	if int(card.get("soul_cost", 0)) > 0:
		tags.append("额外消耗 %d 灵魂" % int(card.soul_cost))
	if int(card.get("star_cost", 0)) > 0:
		tags.append("额外消耗 %d 星辰" % int(card.star_cost))
	var explanations: Array[String] = []
	for keyword in KEYWORD_HELP:
		if keyword in detail or keyword == scope:
			explanations.append(keyword + "：" + str(KEYWORD_HELP[keyword]))
	var text := "%s · 消耗 %d 能量\n%s\n%s\n%s" % [card.get("name", "卡牌"), int(card.get("cost", 0)), " · ".join(tags), detail.strip_edges(), "\n".join(explanations)]
	return _wrap_tooltip(text) if wrap else text


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _build_plan_picker(parent: Node, role_id: String, current_plan: String, on_change: Callable) -> void:
	var options: Array = game.build_plan_options(role_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_label(row, "玩法方向（可选）", 18, GOLD)
	var select := OptionButton.new()
	select.name = "BuildPlanSelect"
	select.custom_minimum_size = Vector2(230, 40)
	row.add_child(select)
	var selected_index := 0
	for index in options.size():
		select.add_item(str(options[index].name))
		select.set_item_metadata(index, str(options[index].id))
		if str(options[index].id) == current_plan:
			selected_index = index
	select.select(selected_index)
	var hint := _paragraph(row, "战斗胜利后会按此方向推荐卡牌；你仍可自由选择，也能在奖励页调整。", 16)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var description := _paragraph(box, str(options[selected_index].description), 16, PAPER)
	description.name = "BuildPlanDescription"
	select.item_selected.connect(func(index: int):
		description.text = str(options[index].description)
		on_change.call(str(options[index].id)))


func _spaced(value: String) -> String:
	var out := ""
	for index in value.length():
		out += value[index]
		if index < value.length() - 1:
			out += " "
	return out


func _room_rule(color: Color = Color(0.52, 0.42, 0.26, 0.34)) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size.y = 1
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rule


func _room_shell(kicker: String, title_text: String, subtitle_text: String, trailing: Control = null) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.name = "RoomShell"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _sts_box(Color(0.055, 0.049, 0.041, 0.90), Color(0.46, 0.37, 0.23, 0.55), 1))
	body.add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	column.add_child(head)
	var mark := ColorRect.new()
	mark.color = Color(0.80, 0.66, 0.42, 0.88)
	mark.custom_minimum_size = Vector2(3, 58)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var kick := _label(titles, _spaced(kicker), 12, GOLD)
	kick.name = "RoomKicker"
	var heading := _label(titles, title_text, 32, PAPER, true)
	heading.name = "RoomTitle"
	if not subtitle_text.is_empty():
		_paragraph(titles, subtitle_text, 15, MUTED)
	if trailing != null:
		trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(trailing)
	column.add_child(_room_rule())
	var content_box := VBoxContainer.new()
	content_box.name = "RoomContent"
	content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 10)
	column.add_child(content_box)
	return content_box


func _wide_button(parent: Node, text_value: String, callback: Callable, width: float = 320.0) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(width, 50)
	button.add_theme_font_override("font", heading_font)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_stylebox_override("normal", _sts_box(Color(0.10, 0.088, 0.070, 0.94), Color(0.52, 0.42, 0.26, 0.85), 1))
	button.add_theme_stylebox_override("hover", _sts_box(Color(0.17, 0.14, 0.105, 0.98), GOLD, 1, true))
	button.add_theme_stylebox_override("pressed", _sts_box(Color(0.23, 0.17, 0.10, 1.0), GOLD, 1))
	button.add_theme_stylebox_override("disabled", _sts_box(Color(0.075, 0.07, 0.06, 0.85), Color(0.30, 0.28, 0.24, 0.5), 1))
	button.add_theme_color_override("font_color", Color(0.90, 0.84, 0.72))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.80))
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void:
		if is_instance_valid(button) and not button.text.is_empty():
			_sfx("click", 0.02, -14.0))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _reward() -> void:
	RewardScreen.build(self)


func _shop() -> void:
	CampScreen.build_shop(self)


func _shop_product(parent: Control, index: int) -> void:
	CampScreen._shop_product(self, parent, index)


func _buy(index: int) -> void:
	CampScreen._buy(self, index)


func _rest() -> void:
	CampScreen.build_rest(self)


func _camp_choice(parent: Node, title_text: String, body_text: String) -> VBoxContainer:
	return CampScreen._camp_choice(self, parent, title_text, body_text)


func _negative_item_ids() -> Array:
	return CampScreen._negative_item_ids(self)


func _show_camp_discard() -> void:
	CampScreen._show_camp_discard(self)


func _discard_camp_item(id: String) -> void:
	CampScreen._discard_camp_item(self, id)


func _event() -> void:
	EventScreen.build_event(self)


func _treasure() -> void:
	EventScreen.build_treasure(self)


func _ending() -> void:
	var victory: bool = game.state.room == "victory"
	var level := int(game.state.difficulty)
	var ending_message := "生命已经耗尽。战斗胜场和已获得的解锁会留下，可以从营地再出发。"
	if victory:
		var unlocked_level: int = game.unlocked_difficulty(str(game.state.role))
		ending_message = "四章已经走完。此旅者当前最高可选难度为「%s」。" % _difficulty_name(unlocked_level)
	var frame := PanelContainer.new()
	frame.name = "EndingFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _sts_box(Color(0.045, 0.040, 0.034, 0.86), Color(0.46, 0.37, 0.23, 0.5), 1))
	body.add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_spacer(column, true)
	var kicker := "誓 约 铭 刻 于 灰 烬" if victory else "誓 约 未 竟"
	var kicker_label := _label(column, kicker, 15, GOLD if victory else RED)
	kicker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var heading := _label(column, "长夜退去" if victory else "此行止于灰烬", 62, PAPER, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ornament := HBoxContainer.new()
	ornament.alignment = BoxContainer.ALIGNMENT_CENTER
	ornament.add_theme_constant_override("separation", 12)
	column.add_child(ornament)
	var left_rule := _room_rule(Color(0.46, 0.37, 0.23, 0.5))
	left_rule.custom_minimum_size.x = 180
	left_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ornament.add_child(left_rule)
	_label(ornament, "◆", 15, GOLD)
	var right_rule := _room_rule(Color(0.46, 0.37, 0.23, 0.5))
	right_rule.custom_minimum_size.x = 180
	right_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ornament.add_child(right_rule)
	var message := _paragraph(column, ending_message, 20, PAPER)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.custom_minimum_size.x = 700
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 14)
	column.add_child(stats)
	for entry in [["得分", "%d" % int(game.state.score)], ["难度", _difficulty_name(level)], ["抵达", "%s · 第 %d 层" % [_chapter().get("name", "长夜"), int(game.state.row) + 1]], ["历经", "%d 回合" % int(game.state.elapsed_turns)], ["牌组", "%d 张" % game.state.deck.size()], ["遗物", "%d 件" % game.state.relics.size()]]:
		var chip := PanelContainer.new()
		if str(entry[0]) == "得分":
			chip.name = "ScoreStat"
			chip.tooltip_text = "本局得分：战斗、精英与首领都会累计。"
		chip.add_theme_stylebox_override("panel", _sts_box(Color(0.10, 0.088, 0.070, 0.92), Color(0.42, 0.34, 0.22, 0.6), 1))
		stats.add_child(chip)
		var chip_margin := MarginContainer.new()
		chip_margin.add_theme_constant_override("margin_left", 14)
		chip_margin.add_theme_constant_override("margin_right", 14)
		chip_margin.add_theme_constant_override("margin_top", 7)
		chip_margin.add_theme_constant_override("margin_bottom", 7)
		chip.add_child(chip_margin)
		var chip_box := VBoxContainer.new()
		chip_box.add_theme_constant_override("separation", 1)
		chip_margin.add_child(chip_box)
		var key_label := _label(chip_box, _spaced(str(entry[0])), 11, MUTED)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var value_label := _label(chip_box, str(entry[1]), 17, PAPER)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if str(entry[0]) == "得分":
			value_label.name = "ScoreValue"
	if bool(game.state.get("daily", false)):
		var record: Dictionary = game.profile.get("daily", {})
		var daily_summary := _label(column, "今日最佳 %d 分 · 连续 %d 天" % [int(record.get("best", 0)), int(record.get("streak", 0))], 17, GOLD)
		daily_summary.name = "DailyEndingSummary"
		daily_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spacer(column, true)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(controls)
	var back := _wide_button(controls, "回到旅者营地", func():
		menu_open = true
		_refresh(), 320)
	back.name = "EndingReturn"


func _modal(title_text: String, subtitle: String = "") -> VBoxContainer:
	_cancel_card_drag()
	_clear(overlay)
	var veil := ColorRect.new()
	veil.color = Color(0.01, 0.02, 0.01, 0.88)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	overlay.add_child(margin)
	var box := _panel(margin, Color("171c17"), GOLD)
	var header := HBoxContainer.new()
	box.add_child(header)
	_label(header, title_text, 32, GOLD, true)
	_spacer(header)
	_button(header, "关闭 [Esc]", func(): _clear(overlay))
	if not subtitle.is_empty():
		_paragraph(box, subtitle, 18)
	return box


func _collection_shell(kicker: String, title_text: String, subtitle: String) -> VBoxContainer:
	_cancel_card_drag()
	_clear(overlay)
	var veil := ColorRect.new()
	veil.color = Color(0.008, 0.010, 0.009, 0.9)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 44)
	overlay.add_child(margin)
	var frame := PanelContainer.new()
	frame.name = "CollectionFrame"
	frame.add_theme_stylebox_override("panel", _sts_box(Color(0.050, 0.045, 0.038, 0.985), Color(0.50, 0.40, 0.25, 0.7), 1))
	margin.add_child(frame)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 16)
	frame.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var bar := ColorRect.new()
	bar.color = Color(0.72, 0.58, 0.34, 0.8)
	bar.custom_minimum_size = Vector2(3, 58)
	header.add_child(bar)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	_label(title_box, _spaced(kicker), 12, GOLD)
	_label(title_box, title_text, 30, PAPER, true)
	_label(title_box, subtitle, 15, MUTED)
	var close := _button(header, "关闭 [Esc]", func(): _clear(overlay))
	close.custom_minimum_size = Vector2(120, 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rule := _room_rule(Color(0.46, 0.37, 0.23, 0.4))
	column.add_child(rule)
	var body_box := VBoxContainer.new()
	body_box.name = "CollectionBody"
	body_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_box.add_theme_constant_override("separation", 10)
	column.add_child(body_box)
	return body_box


func _relic_medallion(parent: Node, tone: Color = GOLD) -> PanelContainer:
	var medal := PanelContainer.new()
	medal.custom_minimum_size = Vector2(56, 56)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.085, 0.065, 0.98)
	style.border_color = tone
	style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(tone.r, tone.g, tone.b, 0.22)
	style.shadow_size = 10
	medal.add_theme_stylebox_override("panel", style)
	var glyph := _label(medal, "◆", 24, tone)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(medal)
	return medal


func _collection_row(parent: Node, title_text: String, body_text: String, tone: Color, glyph_text: String = "◆", width: float = 0.0, icon_id: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sts_box(Color(0.068, 0.060, 0.048, 0.95), Color(tone.r, tone.g, tone.b, 0.55), 1))
	if width > 0.0:
		card.custom_minimum_size.x = width
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_SHRINK_BEGIN
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var icon_definition: Dictionary = {}
	var icon_category := "item"
	if not icon_id.is_empty():
		icon_definition = game.item_data(icon_id)
		if icon_definition.is_empty():
			icon_definition = game.relic_data(icon_id)
			icon_category = "relic"
	if not icon_definition.is_empty():
		_add_item_icon(row, icon_definition, icon_category, 44.0)
	else:
		var medal := PanelContainer.new()
		medal.custom_minimum_size = Vector2(44, 44)
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.10, 0.075, 0.98)
		style.border_color = Color(tone.r, tone.g, tone.b, 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(22)
		medal.add_theme_stylebox_override("panel", style)
		row.add_child(medal)
		var symbol := _label(medal, glyph_text, 18, tone)
		symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 1)
	row.add_child(texts)
	_label(texts, title_text, 19, tone, true)
	_paragraph(texts, body_text, 15, PAPER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card


func _show_deck(mode: String = "view") -> void:
	var titles := {"view": "旅者牌组", "upgrade": "选择要强化的卡牌", "remove": "选择要遗忘的卡牌"}
	var kickers := {"view": "行囊 · 卡牌", "upgrade": "营火 · 淬炼", "remove": "行商 · 遗忘"}
	var subtitle := "共 %d 张。点击卡牌查看完整描述。" % game.state.deck.size()
	if mode == "upgrade":
		subtitle = "点击未升级卡牌查看强化后的效果，再确认选择。"
	elif mode == "remove":
		subtitle = "确认后扣除删牌费用，并从本局永久移除该卡牌。"
	var body_box := _collection_shell(kickers.get(mode, "行囊 · 卡牌"), titles.get(mode, "牌组"), subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for index in range(game.state.deck.size()):
		var instance: Dictionary = game.state.deck[index]
		var button := _card(grid, instance, _deck_pick.bind(mode, index), Vector2(220, 280))
		button.disabled = mode == "upgrade" and bool(instance.get("upgraded", false))
		if mode == "upgrade":
			button.get_node("CardVisual/Availability").text = "已强化" if button.disabled else "预览强化"
		elif mode == "remove":
			button.get_node("CardVisual/Availability").text = "查看遗忘费用"


func _deck_pick(mode: String, index: int) -> void:
	var instance: Dictionary = game.state.deck[index]
	var card: Dictionary = game.card_view(instance)
	if mode == "view":
		_confirm(str(card.get("name", "卡牌")), str(card.get("description", "")), func(): pass, "知道了")
	elif mode == "upgrade":
		var upgraded := instance.duplicate(true)
		upgraded.upgraded = true
		var improved: Dictionary = game.card_view(upgraded)
		_confirm("强化「%s」" % card.name, "当前：%s\n强化后：%s\n能量消耗：%d → %d" % [card.description, improved.description, card.cost, improved.cost], func():
			_clear(overlay)
			_accept(game.rest(index)), "确认强化")
	elif mode == "remove":
		var selected: int = int(game.state.get("selected_shop_remove", -1))
		var price: int = int(game.state.shop[selected].price) if selected >= 0 else 0
		_confirm("遗忘「%s」" % card.name, "支付 %d 金币，从本局牌组永久移除这张卡牌。" % price, func():
			_clear(overlay)
			_accept(game.remove_card(index)), "确认遗忘")


func _show_relics() -> void:
	var body_box := _collection_shell("行囊 · 遗物", "随行道具", "神圣收藏 %d / %d · 限时负面道具在完成后续节点时倒计时。" % [game.profile.sacred_collection.size(), game.sacred_ids().size()])
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_box.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	if not game.state.items.is_empty():
		_label(page, "随行道具", 22, GOLD, true)
		var item_grid := GridContainer.new()
		item_grid.columns = 3
		item_grid.add_theme_constant_override("h_separation", 12)
		item_grid.add_theme_constant_override("v_separation", 8)
		page.add_child(item_grid)
		for id in game.state.items:
			var data: Dictionary = game.item_data(str(id))
			var negative: bool = ExpeditionItems.is_negative(data)
			var tone := RED if negative else GOLD
			var glyph := "✖" if str(data.get("kind", "")) == "curse" else "◇"
			_collection_row(item_grid, str(data.get("name", id)), _expedition_item_detail(str(id)), tone, glyph, 0.0, str(id)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not game.state.relics.is_empty():
		_label(page, "遗物", 22, GOLD, true)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 8)
		page.add_child(grid)
		for id in game.state.relics:
			var relic: Dictionary = game.relic_data(str(id))
			_collection_row(grid, str(relic.get("name", id)), str(relic.get("description", "")), GOLD, "◆", 0.0, str(id)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if game.state.items.is_empty() and game.state.relics.is_empty():
		var empty := _label(page, "行囊里空无一物。", 20, MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 160


func _expedition_item_detail(id: String) -> String:
	var item: Dictionary = game.item_data(id)
	var record: Dictionary = game.state.items.get(id, {})
	var result := "[%s] %s：%s" % [ExpeditionItems.KIND_NAMES.get(item.get("kind", ""), "道具"), item.get("name", id), item.get("description", "")]
	var next_item: Dictionary = game.item_data(str(item.get("transforms_to", "")))
	if item.get("kind", "") == "temporary":
		result += "  剩余 %d 个节点；到期%s。" % [int(record.get("remaining", item.duration)), "消失" if next_item.is_empty() else "转化为「%s」" % next_item.name]
	elif item.get("kind", "") == "curse":
		result += "  净化任务：%s %d / %d；完成后转化为「%s」。" % [item.task.label, int(record.get("progress", 0)), int(item.task.goal), next_item.get("name", "神圣道具")]
	elif item.get("kind", "") == "permanent":
		result += "  效果持续至冒险结束或在营地舍弃。没有净化任务。"
	if not next_item.is_empty():
		result += "\n转化后效果 · %s" % next_item.description
	return result


func _confirm(title_text: String, description: String, callback: Callable, confirm_text: String = "确认") -> void:
	_cancel_card_drag()
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.dialog_text = description
	dialog.ok_button_text = confirm_text
	dialog.cancel_button_text = "返回"
	dialog.min_size = Vector2i(520, 220)
	dialog.confirmed.connect(func():
		callback.call()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _confirm_abandon() -> void:
	_confirm("结束当前旅程", "当前旅程将结束，战斗胜场和职业解锁会保留。此操作无法继续本局。", func():
		_accept(game.abandon_run()))


func _record_result(result: Dictionary) -> void:
	if journey_game != null:
		tutorial_notice = str(result.get("message", ""))
		return
	notice = str(result.get("message", ""))
	if result.has("save_error"):
		save_warning = str(result.save_error)
	elif result.get("ok", false) and game.last_error.is_empty():
		save_warning = ""


func _accept(result: Dictionary) -> void:
	_record_result(result)
	_refresh()
	_show_achievement_toast(result.get("achievements", []))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if combat_busy:
		# Escape may skip the remaining animation, but never re-executes the committed action.
		if event.keycode == KEY_ESCAPE:
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if overlay.get_child_count() > 0:
			_clear(overlay)
		elif workshop_return_game != null:
			_leave_workshop_trial()
		elif journey_game != null:
			_exit_tutorial()
		elif menu_open and menu_page != "title":
			menu_page = "title"
			_refresh()
		elif not menu_open:
			menu_page = "title"
			menu_open = true
			_refresh()
		elif game.state.active:
			menu_open = false
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if menu_open or overlay.get_child_count() > 0 or game.state.room != "battle":
		return
	if event.keycode == KEY_E:
		_end_turn()
		get_viewport().set_input_as_handled()


func _sfx(sfx_name: String, pitch_range: float = 0.04, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if audio != null:
		audio.play_sfx(sfx_name, pitch_range, volume_db, pitch)


func _sync_audio() -> void:
	if audio == null or game == null:
		return
	var room := "menu" if menu_open else str(game.state.room)
	audio.apply_settings(game.profile.settings)
	audio.play_music("battle" if room == "battle" else ("explore" if room in ["map", "shop", "rest", "event", "treasure"] else "title"))
	if room == _heard_room:
		return
	if room == "victory":
		_sfx("victory", 0.0, -5.0)
	elif room == "defeat":
		_sfx("defeat", 0.0, -5.0)
	_heard_room = room


func _shift(node: Control, offset: Vector2) -> void:
	if not is_instance_valid(node):
		return
	node.offset_left = offset.x
	node.offset_top = offset.y
	node.offset_right = offset.x
	node.offset_bottom = offset.y


func _stop_shake() -> void:
	shake_left = 0.0
	shake_mag = 0.0
	_shift(stage, Vector2.ZERO)
	_shift(background, Vector2.ZERO)


func _begin_shake(magnitude: float) -> void:
	if bool(game.profile.settings.get("reduced_motion", false)):
		return
	shake_mag = maxf(shake_mag if shake_left > 0.0 else 0.0, magnitude)
	shake_left = 0.16


func _process(delta: float) -> void:
	if shake_left <= 0.0:
		return
	shake_left = maxf(0.0, shake_left - delta)
	var falloff := shake_left / 0.16
	var kick := Vector2(_shake_rng.randf_range(-1.0, 1.0), _shake_rng.randf_range(-0.6, 0.6)) * shake_mag * falloff
	_shift(stage, kick)
	_shift(background, kick * 0.35)
	if shake_left <= 0.0:
		_stop_shake()


func _hold_actors(value: bool) -> void:
	for actor in combat_actors.values() + battle_followers.values():
		if is_instance_valid(actor):
			actor.held = value


func _pulse_impact(power: float, hurt_player: bool) -> void:
	if bool(game.profile.settings.get("reduced_motion", false)):
		return
	if is_instance_valid(impact_flash):
		if impact_tween != null and impact_tween.is_valid():
			impact_tween.kill()
		var peak := Color(0.62, 0.16, 0.12, 0.34 * power) if hurt_player else Color(0.95, 0.86, 0.7, 0.2 * power)
		impact_flash.color = Color(peak.r, peak.g, peak.b, 0.0)
		impact_tween = create_tween()
		impact_tween.tween_property(impact_flash, "color", peak, 0.03)
		impact_tween.tween_property(impact_flash, "color:a", 0.0, 0.14)
	if is_instance_valid(background):
		if punch_tween != null and punch_tween.is_valid():
			punch_tween.kill()
		background.pivot_offset = background.size * 0.5
		punch_tween = create_tween()
		punch_tween.tween_property(background, "scale", Vector2.ONE * (1.0 + 0.016 * power), 0.04)
		punch_tween.tween_property(background, "scale", Vector2.ONE, 0.14)



class MapBackdrop extends Control:
	var _motes: Array[Vector3] = []
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for index in 22:
			_motes.append(Vector3(randf(), randf(), randf()))

	func _process(delta: float) -> void:
		_time += delta
		if int(_time * 8.0) != int((_time - delta) * 8.0):
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := maxf(size.y, 1.0)
		draw_rect(Rect2(0, 0, w, h), Color(0.030, 0.026, 0.022, 0.96))
		for index in 26:
			var t := float(index) / 25.0
			var band := lerpf(0.10, 0.03, t)
			draw_rect(Rect2(0, h * t, w, h / 25.0 + 1.0), Color(band, band * 0.90, band * 0.70, 0.92))
		for index in 5:
			var y := h * (0.18 + index * 0.17)
			draw_line(Vector2(0, y), Vector2(w, y), Color(0.52, 0.42, 0.26, 0.06), 1.0)
		var edge := Color(0.52, 0.42, 0.26, 0.42)
		for corner in [Vector2(10, 10), Vector2(w - 10, 10), Vector2(10, h - 10), Vector2(w - 10, h - 10)]:
			var sx := 1.0 if corner.x < w * 0.5 else -1.0
			var sy := 1.0 if corner.y < h * 0.5 else -1.0
			draw_line(corner, corner + Vector2(26 * sx, 0), edge, 1.4)
			draw_line(corner, corner + Vector2(0, 26 * sy), edge, 1.4)
		for mote in _motes:
			var x := fposmod(mote.x * w + sin(_time * 0.16 + mote.z * 10.0) * 14.0, w)
			var y := fposmod(mote.y * h - _time * (2.5 + mote.z * 4.0), h)
			var alpha := 0.05 + 0.06 * sin(_time * 0.7 + mote.z * 9.0)
			draw_circle(Vector2(x, y), 0.9 + mote.z * 0.9, Color(0.88, 0.80, 0.60, maxf(alpha, 0.0)))


class CampfireArt extends Control:
	var _time := 0.0
	var _sparks: Array[Vector3] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(116, 96)
		for index in 12:
			_sparks.append(Vector3(randf(), randf(), randf()))

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var base := Vector2(size.x * 0.5, size.y - 8.0)
		var flicker := 0.94 + 0.06 * sin(_time * 7.3) + 0.03 * sin(_time * 13.1)
		for index in 5:
			var ring := float(index)
			draw_circle(base + Vector2(0, 2), 40.0 + ring * 5.0, Color(0.95, 0.55, 0.18, 0.030))
		draw_rect(Rect2(base.x - 26, base.y - 4, 52, 5), Color(0.16, 0.11, 0.07, 0.95))
		draw_line(base + Vector2(-24, 0), base + Vector2(20, -8), Color(0.30, 0.20, 0.11, 0.9), 4.0, true)
		draw_line(base + Vector2(-20, -8), base + Vector2(24, 0), Color(0.36, 0.24, 0.13, 0.9), 4.0, true)
		var outer := PackedVector2Array([
			base + Vector2(0, -64.0 * flicker),
			base + Vector2(17, -34),
			base + Vector2(22, -10),
			base + Vector2(0, 0),
			base + Vector2(-22, -10),
			base + Vector2(-17, -34),
		])
		draw_colored_polygon(outer, Color(0.72, 0.28, 0.08, 0.88))
		var inner := PackedVector2Array([
			base + Vector2(0, -44.0 * flicker),
			base + Vector2(11, -24),
			base + Vector2(13, -8),
			base + Vector2(0, 0),
			base + Vector2(-13, -8),
			base + Vector2(-11, -24),
		])
		draw_colored_polygon(inner, Color(0.98, 0.72, 0.28, 0.92))
		var core := PackedVector2Array([
			base + Vector2(0, -24.0 * flicker),
			base + Vector2(6, -12),
			base + Vector2(0, -1),
			base + Vector2(-6, -12),
		])
		draw_colored_polygon(core, Color(1.0, 0.93, 0.70, 0.95))
		for spark in _sparks:
			var life := fposmod(_time * (0.25 + spark.z * 0.35) + spark.y, 1.0)
			var position := base + Vector2(sin(_time * 2.2 + spark.x * 12.0) * (6.0 + spark.x * 16.0), -30.0 - life * 78.0)
			draw_circle(position, 1.4, Color(1.0, 0.75, 0.34, (1.0 - life) * 0.7))


class StsBackdrop extends Control:
	var chapter := 0
	var role := "warden"
	var wounded := false
	var _time := 0.0
	var _last := 0.0
	var _motes: Array[Vector3] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rng := RandomNumberGenerator.new()
		rng.seed = 48021
		for index in 26:
			_motes.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.2, 0.9)))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_time += delta
		if _time - _last >= 0.05:
			_last = _time
			queue_redraw()

	func _accent() -> Color:
		match chapter:
			0:
				return Color("6f8a74")
			1:
				return Color("8d4b41")
			2:
				return Color("5a7392")
			_:
				return Color("9a7a44")

	func _draw() -> void:
		var w := size.x
		var h := maxf(size.y, 1.0)
		var accent := _accent()
		var bands := 18
		for index in bands:
			var t := float(index) / float(maxi(1, bands - 1))
			var top := Color(0.105, 0.088, 0.072).lerp(Color(0.030, 0.028, 0.025), t)
			draw_rect(Rect2(0, h * t, w, h / float(bands) + 1.0), top)
		var arch_color := Color(accent.r * 0.30, accent.g * 0.30, accent.b * 0.30, 0.6)
		for index in 3:
			var cx := w * (0.17 + 0.33 * index)
			var aw := minf(w * 0.19, 240.0)
			var ah := h * (0.46 + 0.05 * index)
			var base := h * 0.78
			draw_rect(Rect2(cx - aw * 0.5, base - ah, aw, ah), arch_color)
			draw_circle(Vector2(cx, base - ah), aw * 0.5, arch_color)
			draw_rect(Rect2(cx - aw * 0.5, base - ah, aw, ah), arch_color)
			draw_arc(Vector2(cx, base - ah), aw * 0.5, PI, TAU, 24, Color(accent.r, accent.g, accent.b, 0.30), 1.5, true)
		var floor_y := h * 0.76
		draw_rect(Rect2(0, floor_y, w, h - floor_y), Color(0.072, 0.060, 0.048, 0.96))
		draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color(accent.r, accent.g, accent.b, 0.34), 1.5)
		draw_line(Vector2(0, floor_y + 3.0), Vector2(w, floor_y + 3.0), Color(0.45, 0.34, 0.20, 0.22), 1.0)
		draw_rect(Rect2(5, 5, w - 10, h - 10), Color(0.55, 0.42, 0.24, 0.20), false, 1.0)
		for mote in _motes:
			var x := fposmod(mote.x * w + sin(_time * 0.3 + mote.z * 8.0) * 12.0, w)
			var y := fposmod(mote.y * h - _time * (4.0 + mote.z * 6.0), h * 0.74)
			var alpha := 0.07 + 0.07 * sin(_time * 0.9 + mote.z * 12.0)
			draw_circle(Vector2(x, y), 1.1 + mote.z, Color(0.85, 0.78, 0.60, maxf(alpha, 0.0)))
		if wounded:
			draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.05, 0.03, 0.12))


class StsOrb extends Control:
	var current := 3
	var maximum := 3
	var font: Font
	var _time := 0.0
	var _last := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(118, 128)

	func configure(now: int, top: int, font_ref: Font) -> void:
		current = now
		maximum = maxi(1, top)
		font = font_ref
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		if _time - _last >= 0.05:
			_last = _time
			queue_redraw()

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, 55.0)
		var radius := 44.0
		var lit := current > 0
		draw_circle(center, radius + 7.0, Color(0.085, 0.072, 0.058, 0.95))
		draw_arc(center, radius + 5.0, 0.0, TAU, 72, Color(0.57, 0.45, 0.27, 0.95), 2.0, true)
		draw_arc(center, radius + 1.5, 0.0, TAU, 72, Color(0.32, 0.24, 0.15, 0.9), 2.0, true)
		var deep := Color(0.07, 0.13, 0.16) if lit else Color(0.075, 0.075, 0.068)
		var glow := Color(0.32, 0.63, 0.72) if lit else Color(0.22, 0.22, 0.20)
		draw_circle(center, radius, deep)
		for index in range(1, 5):
			var t := float(index) / 5.0
			draw_circle(center + Vector2(0, radius * 0.12 * (1.0 - t)), radius * (1.0 - t * 0.80), Color(glow.r, glow.g, glow.b, 0.05 + 0.12 * t))
		draw_circle(center + Vector2(-radius * 0.26, -radius * 0.30), radius * 0.30, Color(1, 1, 1, 0.10 if lit else 0.05))
		if lit:
			var pulse := 0.5 + 0.5 * sin(_time * 2.2)
			draw_arc(center, radius + 8.0 + pulse * 2.0, 0.0, TAU, 72, Color(glow.r, glow.g, glow.b, 0.20 * pulse), 2.0, true)
		if font != null:
			draw_string(font, Vector2(center.x - 60.0, center.y + 19.0), str(current), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 46, Color(0.97, 0.92, 0.82) if lit else Color(0.60, 0.57, 0.51))
			draw_string(font, Vector2(center.x - 60.0, 118.0), "能量 %d / %d" % [current, maximum], HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13, Color(0.70, 0.63, 0.48))
class BattleVignette extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var bands := 8
		var reach := minf(size.x, size.y) * 0.22
		for index in bands:
			var fade := 1.0 - float(index) / float(bands)
			var alpha := 0.34 * fade * fade
			var thickness := reach * fade
			var ink := Color(0.015, 0.013, 0.011, alpha)
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, thickness)), ink)
			draw_rect(Rect2(Vector2(0, size.y - thickness), Vector2(size.x, thickness)), ink)
			draw_rect(Rect2(Vector2.ZERO, Vector2(thickness * 0.55, size.y)), ink)
			draw_rect(Rect2(Vector2(size.x - thickness * 0.55, 0), Vector2(thickness * 0.55, size.y)), ink)


class EnergyMarks extends Control:
	var filled := 0
	var sockets := 3

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(45, 16)

	func set_energy(value: int) -> void:
		filled = maxi(0, value)
		sockets = clampi(maxi(3, filled), 3, 8)
		custom_minimum_size = Vector2(sockets * 15, 16)
		queue_redraw()

	func _draw() -> void:
		for index in sockets:
			var center := Vector2(7.0 + float(index) * 15.0, 8.0)
			var diamond := PackedVector2Array([
				center + Vector2(0, -6),
				center + Vector2(5, 0),
				center + Vector2(0, 6),
				center + Vector2(-5, 0),
			])
			if index < filled:
				draw_colored_polygon(diamond, Color("c7a66a"))
			else:
				draw_colored_polygon(diamond, Color("2a261f"))
				var outline := PackedVector2Array()
				for point in diamond:
					outline.append(point)
				outline.append(diamond[0])
				draw_polyline(outline, Color("8c7350"), 1.2, true)


func _menu() -> void:
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 66)
	margin.add_theme_constant_override("margin_top", 30)
	content.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_label(column, "G R E Y   O A T H", 18, GOLD)
	_label(column, "灰  誓", 106, PAPER, true)
	_label(column, "钟声已逝，誓言未熄。", 20, MUTED, true)
	var rule := ColorRect.new()
	rule.color = Color(GOLD, 0.6)
	rule.custom_minimum_size = Vector2(310, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(rule)
	var breath := Control.new()
	breath.custom_minimum_size.y = 16
	column.add_child(breath)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 350
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	actions.add_theme_constant_override("separation", 3)
	column.add_child(actions)
	var resume := _menu_entry(actions, "继续旅程", func():
		menu_open = false
		_refresh())
	resume.disabled = not bool(game.state.active)
	resume.tooltip_text = "继续自动保存的旅程" if game.state.active else "尚无进行中的旅程"
	var begin := _menu_entry(actions, "开始旅程", func():
		menu_page = "roles"
		_refresh())
	begin.name = "NewJourneyButton"
	var daily_box := VBoxContainer.new()
	daily_box.add_theme_constant_override("separation", 1)
	actions.add_child(daily_box)
	var daily_view: Dictionary = game.daily_view()
	var daily := _menu_entry(daily_box, "每日誓约", func():
		daily_error = ""
		menu_page = "daily"
		_refresh())
	daily.name = "DailyVowButton"
	daily.tooltip_text = "每日·%s · %s · %s" % [str(daily_view.get("role_name", "旅者")), str(daily_view.get("oath", {}).get("name", "")), str(daily_view.get("modifier", {}).get("name", ""))]
	var daily_note := _label(daily_box, "      " + _daily_menu_subtitle(daily_view), 12, Color("9a8f79"))
	daily_note.add_theme_constant_override("outline_size", 0)
	daily_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_entry(actions, "新手教学", func():
		menu_page = "tutorial"
		_refresh()).name = "TutorialButton"
	_menu_entry(actions, "本地创意工坊", func():
		menu_page = "workshop"
		_refresh()).name = "WorkshopButton"
	_menu_entry(actions, "卡牌图鉴", _show_collection).name = "CollectionButton"
	_menu_entry(actions, "成就", _show_achievements).name = "AchievementsButton"
	_menu_entry(actions, "设置", _show_settings).name = "SettingsButton"
	_menu_entry(actions, "退出游戏", _request_quit)
	_spacer(column, true)
	var status := "尚无进行中的旅程"
	if game.state.active:
		status = "%s · %s · 第 %d 层" % [game.role_data(str(game.state.role)).get("name", "旅者"), _chapter().get("name", "长夜"), int(game.state.row) + 1]
	var daily_record: Dictionary = game.profile.get("daily", {})
	if int(daily_record.get("streak", 0)) > 0 or int(daily_record.get("best", 0)) > 0:
		status += "   /   今日最佳 %d 分 · 连续 %d 天" % [int(daily_record.get("best", 0)), int(daily_record.get("streak", 0))]
	_label(column, "本地存档  /  " + status, 15, MUTED)
	_label(column, "卡牌收集 %d / %d    ·    成就 %d / %d" % [game.profile.seen_cards.size(), game.data.cards.size(), game.profile.achievements.size(), game.achievement_entries().size()], 15, GOLD)
	var foot := HBoxContainer.new()
	content.add_child(foot)
	_label(foot, "↑ ↓ 选择    Enter 确认    Esc 返回", 14, MUTED)
	_spacer(foot)
	var update: Dictionary = get_tree().get_meta("grey_oath_local_update", {})
	var version_text := "离线单人  ·  macOS  ·  v" + str(ProjectSettings.get_setting("application/config/version"))
	var update_state := str(update.get("status", ""))
	match update_state:
		"applied": version_text += " · 本地更新 %d" % int(update.get("revision", 0))
		"rejected": version_text += " · 本地更新未应用"
		"bypassed": version_text += " · 已跳过本地更新"
	var version_label := _label(foot, version_text, 14, RED if update_state == "rejected" else MUTED)
	version_label.name = "LocalUpdateVersion"
	version_label.tooltip_text = str(update.get("detail", ""))
	if not version_label.tooltip_text.is_empty():
		version_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not save_warning.is_empty() or not notice.is_empty():
		notice_label = _paragraph(content, save_warning if not save_warning.is_empty() else notice, 15, RED if not save_warning.is_empty() else MUTED)
	var focus_target := resume if game.state.active else begin
	(func():
		if is_instance_valid(focus_target) and focus_target.is_inside_tree():
			focus_target.grab_focus()).call_deferred()


func _daily_menu_subtitle(view: Dictionary) -> String:
	if bool(view.get("active", false)):
		return "进行中 · 今日最佳 %d 分 · 连续 %d 天" % [int(view.get("best", 0)), int(view.get("streak", 0))]
	if int(view.get("attempts", 0)) > 0:
		return "今日最佳 %d 分 · 连续 %d 天" % [int(view.get("best", 0)), int(view.get("streak", 0))]
	var modifier: Dictionary = view.get("modifier", {})
	return "%s · %s" % [str(view.get("role_name", "旅者")), str(modifier.get("name", "长夜"))]


func _daily_modifier_name(modifier_id: String) -> String:
	var view: Dictionary = game.daily_view()
	var modifier: Dictionary = view.get("modifier", {})
	if modifier_id.is_empty() or str(modifier.get("id", "")) == modifier_id:
		return str(modifier.get("name", "长夜"))
	return "长夜"


func _daily_fact(parent: Node, caption: String, value: String, tone: Color = PAPER) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _sts_box(Color(0.082, 0.078, 0.064, 0.92), Color(0.32, 0.28, 0.22, 0.85), 1))
	parent.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	frame.add_child(column)
	var key := _label(column, caption, 11, Color("9a8f79"))
	key.add_theme_constant_override("outline_size", 0)
	_label(column, value, 16, tone, true)
	return frame


func _start_daily() -> void:
	var result: Dictionary = game.start_daily_run()
	if bool(result.get("ok", false)):
		daily_error = ""
		notice = str(result.get("message", "今日誓约已开始。"))
		menu_open = false
		selected_target = 0
		_refresh()
		_show_achievement_toast(result.get("achievements", []))
		return
	daily_error = str(result.get("message", "今日誓约无法开始。"))
	notice = daily_error
	_refresh()


func _daily() -> void:
	var view: Dictionary = game.daily_view()
	var oath: Dictionary = view.get("oath", {})
	var modifier: Dictionary = view.get("modifier", {})
	var frame := PanelContainer.new()
	frame.name = "DailyVowScreen"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _sts_box(Color(0.05, 0.046, 0.04, 0.93), Color(0.46, 0.37, 0.23, 0.55), 1))
	content.add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_label(column, "D A I L Y   V O W", 13, GOLD)
	_label(column, "每日誓约", 42, PAPER, true)
	_paragraph(column, "每天只有一场考验。角色、誓约与长夜变体都由日期决定，所有旅者面对同一夜。", 17, MUTED)
	column.add_child(_room_rule())
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 10)
	column.add_child(facts)
	_daily_fact(facts, "日期", str(view.get("key", "")))
	_daily_fact(facts, "今日角色", str(view.get("role_name", "旅者")))
	_daily_fact(facts, "今日誓约", str(oath.get("name", "—")))
	_daily_fact(facts, "长夜变体", str(modifier.get("name", "—")))
	var detail := _panel(column, Color(0.072, 0.078, 0.062, 0.95), Color(0.40, 0.35, 0.24, 0.75))
	detail.get_parent().name = "DailyVowDetail"
	_label(detail, "%s · %s" % [str(oath.get("name", "誓约")), str(oath.get("kicker", ""))], 20, GOLD, true)
	_paragraph(detail, "恩惠：%s" % str(oath.get("boon", "")), 15, PAPER)
	_paragraph(detail, "代价：%s" % str(oath.get("price", "")), 15, MUTED)
	_label(detail, "长夜变体 · %s" % str(modifier.get("name", "")), 15, GOLD)
	_paragraph(detail, str(modifier.get("description", "")), 15, PAPER)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	column.add_child(stats)
	_daily_fact(stats, "今日最佳", "%d 分" % int(view.get("best", 0)))
	_daily_fact(stats, "连续天数", "%d 天" % int(view.get("streak", 0)))
	_daily_fact(stats, "尝试次数", "%d 次" % int(view.get("attempts", 0)))
	var status := _paragraph(column, str(view.get("status", "")), 15, GOLD if bool(view.get("can_start", true)) else MUTED)
	status.name = "DailyStatusText"
	if not daily_error.is_empty():
		var failure := _paragraph(column, daily_error, 15, RED)
		failure.name = "DailyError"
	_spacer(column, true)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 14)
	column.add_child(controls)
	var start := _wide_button(controls, "继续今日誓约" if bool(view.get("active", false)) else "开始今日誓约", _start_daily, 300)
	start.name = "StartDailyButton"
	start.add_theme_stylebox_override("normal", _sts_box(Color(0.40, 0.32, 0.18, 0.98), GOLD, 1, true))
	start.add_theme_stylebox_override("hover", _sts_box(Color(0.48, 0.39, 0.22, 1.0), GOLD, 1, true))
	start.add_theme_stylebox_override("pressed", _sts_box(Color(0.33, 0.26, 0.14, 0.98), GOLD, 1))
	start.add_theme_color_override("font_color", Color("f3e7cd"))
	start.add_theme_color_override("font_hover_color", PAPER)
	start.tooltip_text = "今日：%s · %s · %s" % [str(view.get("key", "")), str(oath.get("name", "")), str(modifier.get("name", ""))]
	_spacer(controls)
	var back := _button(controls, "← 返回主菜单", func():
		menu_page = "title"
		_refresh())
	back.name = "DailyBackButton"
	back.custom_minimum_size = Vector2(180, 50)
	_footer()


func _workshop() -> void:
	if workshop_draft.is_empty():
		workshop_draft = WorkshopPack.default_pack(game)
	var editor := WorkshopEditor.new()
	editor.setup(game, workshop_draft)
	editor.draft_changed.connect(func(pack: Dictionary): workshop_draft = pack)
	editor.trial_requested.connect(_start_workshop_trial)
	editor.back_requested.connect(func():
		menu_page = "title"
		_refresh())
	content.add_child(editor)
	if not workshop_start_error.is_empty():
		_paragraph(content, workshop_start_error, 15, RED)
		workshop_start_error = ""


func _start_workshop_trial(pack: Dictionary) -> void:
	var standard_game = game if workshop_return_game == null else workshop_return_game
	var trial := Rules.new("")
	var result: Dictionary = trial.start_workshop(pack)
	if not bool(result.get("ok", false)):
		if workshop_return_game != null:
			_leave_workshop_trial()
		workshop_start_error = str(result.get("message", "无法开始试玩。"))
		_refresh()
		return
	trial.profile.settings = standard_game.profile.settings.duplicate(true)
	if workshop_return_game == null:
		workshop_return_game = game
		workshop_return_ui = {"target": selected_target, "notice": notice, "save_warning": save_warning}
	workshop_draft = trial.state.workshop_pack.duplicate(true)
	game = trial
	selected_target = 0
	notice = str(result.get("message", "试玩开始。"))
	save_warning = ""
	menu_open = false
	_refresh()


func _leave_workshop_trial() -> void:
	if workshop_return_game == null:
		return
	_clear(overlay)
	game = workshop_return_game
	workshop_return_game = null
	selected_target = int(workshop_return_ui.target)
	notice = str(workshop_return_ui.notice)
	save_warning = str(workshop_return_ui.save_warning)
	workshop_return_ui.clear()
	menu_page = "workshop"
	menu_open = true
	_refresh()


func _workshop_trial_result() -> void:
	var won: bool = game.state.room == "victory"
	var pack: Dictionary = game.state.workshop_pack
	var result := _panel(body)
	result.name = "WorkshopTrialResult"
	_title(result, "WORKSHOP PLAYTEST", "试玩获胜" if won else "试玩结束")
	_paragraph(result, "%s · %s对阵%s · 经过 %d 回合" % [pack.title, pack.role.name, pack.enemy.name, game.state.turn], 20, GOLD)
	_paragraph(result, "流派「%s」 · %s" % [pack.build.name, pack.build.description], 18, PAPER)
	_paragraph(result, "可以修改数值后再试。正式旅程的存档和成就保持原状。", 16)
	var buttons := HBoxContainer.new()
	result.add_child(buttons)
	_button(buttons, "再试一次", _start_workshop_trial.bind(pack), true).name = "WorkshopRetryButton"
	_button(buttons, "返回编辑", _leave_workshop_trial).name = "WorkshopEditButton"


func _tutorial() -> void:
	var header := HBoxContainer.new()
	content.add_child(header)
	_title(header, "A QUIET FIRST STEP", "旅者教学")
	_spacer(header)
	_button(header, "← 返回主菜单", func():
		menu_page = "title"
		_refresh())
	_paragraph(content, "选一名英雄，用一场短战熟悉主要玩法。战斗中会根据手牌给出建议，你也可以自由出牌。练习不会改变旅程进度。", 19, PAPER)
	var recommendation := _panel(content)
	recommendation.name = "TutorialRecommendation"
	var recommendation_row := HBoxContainer.new()
	recommendation_row.add_theme_constant_override("separation", 18)
	recommendation.add_child(recommendation_row)
	var recommendation_copy := VBoxContainer.new()
	recommendation_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recommendation_row.add_child(recommendation_copy)
	_label(recommendation_copy, "第一次游玩 · 推荐从铁甲战士开始", 18, GOLD, true)
	_paragraph(recommendation_copy, "用两回合熟悉基础节奏：先看敌人意图，再用格挡防御、用力量进攻。", 16, PAPER)
	_button(recommendation_row, "开始推荐教学  →", _start_tutorial.bind("warden"), true).name = "TutorialRecommendedStart"
	_label(content, "也可以直接选择其他职业", 16, MUTED, true)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for role in game.data.roles:
		var role_id := str(role.id)
		var lesson: Dictionary = TutorialLessons.LESSONS.get(role_id, {})
		if lesson.is_empty():
			continue
		var tile := _panel(grid)
		tile.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var heading := HBoxContainer.new()
		tile.add_child(heading)
		var portrait := TextureRect.new()
		portrait.texture = preload("res://ui/role_art.gd").texture_for(role_id)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(54, 70)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_child(portrait)
		var names := VBoxContainer.new()
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		heading.add_child(names)
		_label(names, str(lesson.title), 16, GOLD, true)
		_label(names, str(role.name), 22, PAPER, true)
		_paragraph(tile, str(lesson.focus), 17, MUTED)
		var start := _button(tile, "开始练习  →", _start_tutorial.bind(role_id), true)
		start.name = "TutorialRole_" + role_id
	_footer()


func _start_tutorial(role_id: String) -> void:
	var practice := Rules.new("")
	var result := practice.start_tutorial(role_id)
	if not bool(result.get("ok", false)):
		tutorial_notice = str(result.message)
		_refresh()
		return
	practice.profile.settings = game.profile.settings.duplicate(true)
	if journey_game == null:
		journey_game = game
		tutorial_return_target = selected_target
	game = practice
	tutorial_notice = str(result.message)
	menu_open = false
	_refresh()


func _exit_tutorial(page: String = "tutorial", resume: bool = false) -> void:
	var practiced_role := str(game.state.role)
	game = journey_game
	if page == "roles" and game.is_role_unlocked(practiced_role):
		selected_role = practiced_role
		difficulty = mini(difficulty, int(game.unlocked_difficulty(selected_role)))
	journey_game = null
	tutorial_notice = ""
	selected_target = tutorial_return_target
	menu_page = page
	menu_open = not resume
	_refresh()


func _tutorial_battle_hint() -> String:
	var lesson: Dictionary = TutorialLessons.LESSONS[game.state.role]
	var turn := int(game.state.turn)
	var recommendation: Array = []
	if turn == 1:
		recommendation = _tutorial_card_hint(lesson.opening, true)
	elif turn == 2:
		recommendation = _tutorial_card_hint(lesson.followup, false)
	var instruction := str(recommendation[1]) if not recommendation.is_empty() else ""
	if int(game.state.get("pending_discard", 0)) > 0:
		recommendation = []
		instruction = "先完成主动弃牌选择，再继续本回合的教学提示。"
	elif turn == 1 and instruction.is_empty():
		instruction = str(lesson.end_turn)
	elif turn == 2 and not instruction.is_empty() and int(game.state.cards_played_this_turn) == 0:
		var lost := int(game.state.max_hp) - int(game.state.hp)
		var feedback := "上一回合未失去生命。" if lost == 0 else "上一回合失去 %d 生命。" % lost
		instruction = feedback + " " + instruction
	if instruction.is_empty():
		instruction = "看看敌方意图和手牌，继续攻击或防御。点「结束回合」或按 E 可换一批手牌。"
	var panel := _panel(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	_label(row, "第 %02d 回合 · %s" % [turn, lesson.focus], 16, GOLD, true)
	var hint := _paragraph(row, instruction, 17, PAPER)
	hint.name = "TutorialBattleHint"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return str(recommendation[0]) if not recommendation.is_empty() else ""


func _tutorial_card_hint(steps: Array, skip_used: bool) -> Array:
	for step in steps:
		var id := str(step[0])
		if skip_used and game.state.discard.any(func(card): return card.id == id):
			continue
		for instance in game.state.hand:
			if instance.id != id:
				continue
			var card: Dictionary = game.card_view(instance)
			if int(card.cost) <= int(game.state.energy) and int(card.get("star_cost", 0)) <= int(game.state.stars):
				return step
	return []


func _tutorial_result() -> void:
	var won: bool = game.state.room == "victory"
	_spacer(body, true)
	var lesson: Dictionary = TutorialLessons.LESSONS[game.state.role]
	_title(body, str(lesson.title), "练习完成" if won else "这次练习结束")
	var lost := int(game.state.max_hp) - int(game.state.hp)
	var recap := "历经 %d 回合 · 损失 %d 生命" % [game.state.turn, lost]
	_paragraph(body, recap, 20, GOLD)
	_paragraph(body, str(lesson.recap), 19, PAPER)
	var controls := HBoxContainer.new()
	body.add_child(controls)
	if won:
		var resume: bool = journey_game.state.active
		_button(controls, "继续旅程  →" if resume else "选择英雄  →",
			_exit_tutorial.bind("title" if resume else "roles", resume), true).name = "TutorialContinueButton"
	_button(controls, "再练一次", _start_tutorial.bind(str(game.state.role)), not won).name = "RetryTutorialButton"
	_button(controls, "换角色练习", _exit_tutorial).name = "SwitchTutorialRole"
	_button(controls, "返回主菜单", _exit_tutorial.bind("title", false)).name = "LeaveTutorialResult"
	_spacer(body, true)


func _menu_entry(parent: Node, title: String, callback: Callable) -> Button:
	var button := _button(parent, "   " + title, callback)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(350, 46)
	button.add_theme_font_size_override("font_size", 25)
	button.add_theme_font_override("font", heading_font)
	button.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", _style(Color(0.25, 0.24, 0.16, 0.28), Color(GOLD, 0.28)))
	button.add_theme_stylebox_override("disabled", _style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	var focus_style := _style(Color(0.25, 0.24, 0.16, 0.12), Color(0, 0, 0, 0))
	focus_style.border_color = Color(GOLD, 0.65)
	focus_style.set_border_width_all(0)
	focus_style.border_width_bottom = 1
	button.add_theme_stylebox_override("focus", focus_style)
	# 标题页多了一条入口，条目高度收紧 5px（内容边距 8 → 3）以免整页溢出。
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := button.get_theme_stylebox(state_name)
		if box is StyleBoxFlat:
			(box as StyleBoxFlat).content_margin_top = 3
			(box as StyleBoxFlat).content_margin_bottom = 3
	var enter := func():
		button.text = "◆  " + title
		_sfx("click", 0.01, -24.0)
	var leave := func():
		if not button.has_focus():
			button.text = "   " + title
	button.mouse_entered.connect(enter)
	button.focus_entered.connect(enter)
	button.mouse_exited.connect(leave)
	button.focus_exited.connect(func(): button.text = "   " + title)
	return button


func _request_quit() -> void:
	# A loaded corrupt save must never be overwritten by quitting from the title.
	if game.state.active and not game.save_game():
		_accept({"ok": false, "message": game.last_error, "save_error": game.last_error})
		return
	get_tree().quit()


func _show_collection() -> void:
	var box := _modal("卡牌图鉴", "已收集 %d / %d · 初始牌、奖励、购买和事件实际获得后永久收录。" % [game.profile.seen_cards.size(), game.data.cards.size()])
	var filters := HBoxContainer.new()
	box.add_child(filters)
	var roles := OptionButton.new()
	roles.add_item("全部职业")
	var role_ids: Array = ["all"]
	for role in game.data.roles:
		roles.add_item(str(role.name))
		role_ids.append(str(role.id))
	roles.add_item("中立")
	role_ids.append("neutral")
	roles.select(maxi(0, role_ids.find(collection_role)))
	roles.item_selected.connect(func(index):
		collection_role = role_ids[index]
		collection_page = 0
		_show_collection())
	filters.add_child(roles)
	var rarities := OptionButton.new()
	var rarity_ids: Array = ["all", "starter", "common", "uncommon", "rare"]
	for id in rarity_ids:
		rarities.add_item("全部稀有度" if id == "all" else RARITY_NAMES[id])
	rarities.select(maxi(0, rarity_ids.find(collection_rarity)))
	rarities.item_selected.connect(func(index):
		collection_rarity = rarity_ids[index]
		collection_page = 0
		_show_collection())
	filters.add_child(rarities)
	var owned := CheckButton.new()
	owned.text = "只看已收集"
	owned.button_pressed = collection_owned
	owned.toggled.connect(func(value):
		collection_owned = value
		collection_page = 0
		_show_collection())
	filters.add_child(owned)
	var search := LineEdit.new()
	search.name = "CollectionSearch"
	search.placeholder_text = "搜索卡名或效果，回车确认"
	search.text = collection_query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	var apply_search := func():
		collection_query = search.text.strip_edges()
		collection_page = 0
		_show_collection()
	search.text_submitted.connect(func(_text): apply_search.call())
	_button(filters, "搜索", apply_search)
	var matches: Array = []
	for card in game.data.cards:
		var collected: bool = game.profile.seen_cards.has(str(card.id))
		if collection_role != "all" and card.role != collection_role:
			continue
		if collection_rarity != "all" and card.rarity != collection_rarity:
			continue
		if collection_owned and not collected:
			continue
		# Undiscovered card names/effects cannot be probed through search.
		if not collection_query.is_empty() and (not collected or not (str(card.name) + str(card.description)).containsn(collection_query)):
			continue
		matches.append(card)
	matches.sort_custom(func(a, b):
		var a_owned: bool = game.profile.seen_cards.has(str(a.id))
		var b_owned: bool = game.profile.seen_cards.has(str(b.id))
		return a_owned if a_owned != b_owned else str(a.id) < str(b.id))
	var pages := maxi(1, int(ceil(matches.size() / 8.0)))
	collection_page = clampi(collection_page, 0, pages - 1)
	var paging := HBoxContainer.new()
	box.add_child(paging)
	var previous := _button(paging, "← 上一页", func():
		collection_page -= 1
		_show_collection())
	previous.disabled = collection_page == 0
	_label(paging, "第 %d / %d 页 · %d 张" % [collection_page + 1, pages, matches.size()], 17, GOLD)
	var next := _button(paging, "下一页 →", func():
		collection_page += 1
		_show_collection())
	next.disabled = collection_page >= pages - 1
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var gallery := CenterContainer.new()
	gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gallery)
	var grid := GridContainer.new()
	grid.name = "CollectionGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	gallery.add_child(grid)
	for card in matches.slice(collection_page * 8, collection_page * 8 + 8):
		var id := str(card.id)
		if game.profile.seen_cards.has(id):
			_card(grid, {"id": id, "upgraded": false}, _collection_detail.bind(id), Vector2(218, 245))
		else:
			var role_name := str(game.role_data(str(card.role)).get("name", "中立"))
			_locked_collection_card(grid, role_name, str(RARITY_NAMES.get(str(card.rarity), "")), int(card.unlock_wins))
	if matches.is_empty():
		_paragraph(box, "没有符合条件的卡牌。试试其他筛选条件。", 22)


func _locked_collection_card(parent: Node, role_name: String, rarity_name: String, wins: int) -> void:
	# Give the card back only the fields the collection already makes public.
	var locked := Button.new()
	locked.name = "LockedCollectionCard"
	locked.custom_minimum_size = Vector2(218, 245)
	locked.disabled = true
	locked.focus_mode = Control.FOCUS_NONE
	locked.add_theme_stylebox_override("disabled", _style(Color("171b18"), Color("625742")))
	parent.add_child(locked)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(Color("201f19"), Color("4f4837")))
	locked.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 8
	frame.offset_top = 8
	frame.offset_right = -8
	frame.offset_bottom = -8
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 4)
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(labels)
	_label(labels, "◈", 54, Color("9b8154")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(labels, "未收集", 23, PAPER, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(labels, "%s · %s" % [role_name, rarity_name], 15, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(labels, "胜场解锁条件  %d" % wins, 14, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignore_mouse(frame)


func _collection_detail(id: String) -> void:
	var card: Dictionary = game.card_view({"id": id, "upgraded": false})
	var improved: Dictionary = game.card_view({"id": id, "upgraded": true})
	var box := _modal(str(card.name), "对照原版和强化版的能量消耗与效果。")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	_card(row, {"id": id, "upgraded": false}, func(): pass, Vector2(250, 330), "compare").name = "BaseCardPreview"
	_card(row, {"id": id, "upgraded": true}, func(): pass, Vector2(250, 330), "compare").name = "UpgradedCardPreview"
	var details := ScrollContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(details)
	var text := _panel(details)
	text.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	_label(text, "能量消耗  %d → %d" % [card.cost, improved.cost], 22, GOLD, true)
	_label(text, "原版效果", 16, MUTED)
	_paragraph(text, str(card.description), 19, PAPER)
	_label(text, "强化效果", 16, GOLD)
	_paragraph(text, str(improved.description), 19, PAPER)
	if card.get("rarity", "") == "starter":
		_paragraph(text, "随职业初始牌组获得。", 18)
	else:
		var availability := "胜场条件已满足；第%d章起进入奖励与商店池。" % (int(card.get("min_chapter", 0)) + 1)
		_paragraph(text, availability if game.is_card_unlocked(card) else "尚未达到此卡的胜场解锁条件。", 18)
	_button(box, "← 返回图鉴", _show_collection)


func _show_achievements() -> void:
	var entries: Array = game.achievement_entries()
	var box := _modal("誓约成就", "已达成 %d / %d · 跨旅程永久保存，成就不改变战斗强度。" % [game.profile.achievements.size(), entries.size()])
	_button(box, "神圣图鉴 · %d / %d" % [game.profile.sacred_collection.size(), game.sacred_ids().size()], _show_sacred_collection).name = "SacredCollection"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in entries:
		var panel := _panel(list, Color("1c231e"), GOLD if entry.unlocked else BORDER)
		var row := HBoxContainer.new()
		panel.add_child(row)
		_label(row, ("◆  " if entry.unlocked else "◇  ") + str(entry.name), 24, GOLD if entry.unlocked else PAPER, true)
		_spacer(row)
		_label(row, "已达成" if entry.unlocked else "%d / %d" % [entry.progress, entry.goal], 17, GREEN if entry.unlocked else MUTED)
		_paragraph(panel, str(entry.description), 17)
		var progress := ProgressBar.new()
		progress.custom_minimum_size.y = 6
		progress.max_value = entry.goal
		progress.value = entry.goal if entry.unlocked else entry.progress
		progress.show_percentage = false
		panel.add_child(progress)


func _show_sacred_collection() -> void:
	var box := _modal("神圣图鉴", "永久收录 %d / %d · 完成诅咒的净化任务后收录，集齐解锁「长夜圣匣」。" % [game.profile.sacred_collection.size(), game.sacred_ids().size()])
	for id in game.sacred_ids():
		var item: Dictionary = game.item_data(str(id))
		var owned: bool = game.profile.sacred_collection.has(id)
		var panel := _panel(box)
		_label(panel, ("◆ 已收录 · " if owned else "◇ 未收录 · ") + str(item.name), 22, GOLD if owned else MUTED, true)
		_paragraph(panel, str(item.description), 17)
	_button(box, "← 返回成就", _show_achievements)


func _show_achievement_toast(ids: Array) -> void:
	if ids.is_empty():
		return
	if is_instance_valid(achievement_toast):
		achievement_toast.queue_free()
	var panel := PanelContainer.new()
	achievement_toast = panel
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("242a20"), GOLD, 2))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(size.x - 410, 30)
	panel.custom_minimum_size = Vector2(380, 85)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_label(box, "◆  成就达成", 16, GOLD)
	var names: Array[String] = []
	for entry in game.achievement_entries():
		if ids.has(entry.id):
			names.append(str(entry.name))
	_paragraph(box, " · ".join(names), 22, PAPER)
	_ignore_mouse(panel)
	_sfx("bell", 0.0, -14.0)
	var tween := create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)


func _show_settings() -> void:
	var box := _modal("设置", "音乐、音效与演出设置会随本地存档保存。")
	var controls: Dictionary = {}
	for item in [["music", "背景音乐"], ["sound", "战斗音效"], ["reduced_motion", "减少动态效果（关闭震屏、闪屏与镜头推拉）"]]:
		var toggle := CheckButton.new()
		toggle.text = item[1]
		toggle.button_pressed = bool(game.profile.settings.get(item[0], true))
		box.add_child(toggle)
		controls[item[0]] = toggle
	for item in [["music_volume", "音乐音量", 0.7], ["sound_volume", "音效音量", 0.8]]:
		var row := HBoxContainer.new()
		box.add_child(row)
		_label(row, item[1], 20)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(game.profile.settings.get(item[0], item[2]))
		slider.custom_minimum_size = Vector2(350, 32)
		row.add_child(slider)
		var value_label := _label(row, "%d%%" % roundi(slider.value * 100), 18, GOLD)
		slider.value_changed.connect(func(value): value_label.text = "%d%%" % roundi(value * 100))
		controls[item[0]] = slider
	var row := HBoxContainer.new()
	box.add_child(row)
	_label(row, "战斗动画速度", 20)
	var speed := OptionButton.new()
	var speeds := [1.0, 1.5, 2.0]
	for value in speeds:
		speed.add_item("%s 倍" % value)
	speed.select(maxi(0, speeds.find(float(game.profile.settings.get("combat_speed", 1.0)))))
	row.add_child(speed)
	_paragraph(box, "动画中按 Esc 可跳过演出；拖拽卡牌到战场出牌，结束回合使用 E。\n这些设置只影响演出，不改变战斗规则或随机结果。", 18)
	var update: Dictionary = get_tree().get_meta("grey_oath_local_update", {})
	if OS.get_name() == "macOS" and not OS.has_feature("editor") and update.has("directory"):
		var update_row := HBoxContainer.new()
		box.add_child(update_row)
		_button(update_row, "打开本地更新目录", _open_local_update_folder.bind(str(update.directory))).name = "LocalUpdateFolder"
		_label(update_row, "将已签名的更新放入此目录，重新打开游戏后生效。", 16, MUTED)
	_spacer(box, true)
	_button(box, "应用并保存", func():
		for key in controls:
			var value: Variant = controls[key].button_pressed if controls[key] is CheckButton else controls[key].value
			game.profile.settings[key] = value
		game.profile.settings.combat_speed = speeds[speed.selected]
		_clear(overlay)
		_accept(game.update_setting("combat_speed", speeds[speed.selected])), true)


func _open_local_update_folder(path: String) -> void:
	var directory := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(directory) != OK or OS.shell_open(directory) != OK:
		OS.alert("无法打开本地更新目录。", "灰誓")


func _configure_actor(actor: Control) -> void:
	actor.animation_speed = float(game.profile.settings.get("combat_speed", 1.0))
	actor.reduced_motion = bool(game.profile.settings.get("reduced_motion", false))


func _show_combat_log() -> void:
	var box := _modal("战斗记事", "最近十二条行动记录。当前行动结果也会显示在底部。")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for line in game.state.log:
		_paragraph(list, str(line), 20, PAPER)
