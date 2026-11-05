extends RefCounted
## Offline, explainable build suggestions. Reading a guide never changes a card pool or RNG.

const PLANS = {
	"warden": [
		["strength", "力量猛攻", "用力量让每次攻击更疼；连续攻击时，每一下都能得到加成。", ["strength", "multi_hit"], ["vulnerable", "draw", "energy"]],
		["exhaust", "消耗换收益", "打出消耗牌后，本场不会再抽到；部分卡会因此给你格挡或抽牌。", ["exhaust_fuel", "exhaust_payoff"], ["draw", "energy", "block"]],
		["bastion", "格挡反击", "先获得格挡，再用盾击把格挡加进伤害。", ["block", "block_damage", "retain_block"], ["thorns", "weak", "draw"]],
	],
	"ranger": [
		["poison", "中毒慢慢磨", "先让敌人中毒，再用相关卡提高伤害；格挡和虚弱帮你撑过回合。", ["poison", "poison_multiply", "poison_scale"], ["weak", "block", "intangible"]],
		["shiv", "小刀连击", "生成免费小刀，再用力量和小刀强化提高攻击伤害。", ["shiv", "shiv_damage"], ["strength", "draw", "vulnerable"]],
		["discard", "主动弃牌", "主动弃牌可以让机巧牌免费打出，也能带来额外抽牌或能量。", ["discard", "sly", "discard_payoff"], ["draw", "energy"]],
	],
	"sister": [
		["lightning", "闪电进攻", "多放闪电球，让它们自动攻击；提前触发可以立刻造成更多伤害。", ["lightning", "focus"], ["evoke", "orb_slots", "draw"]],
		["frost", "冰霜防守", "多放冰霜球获得格挡，再用更多球位和强化效果稳住防守。", ["frost", "focus", "orb_slots"], ["block", "evoke", "draw"]],
		["dark", "黑暗蓄力", "让黑暗球逐回合变强，再提前触发它攻击生命最低的敌人。", ["dark", "evoke"], ["focus", "block", "draw"]],
	],
	"arcanist": [
		["stars", "星辰强化", "积攒星辰来强化卡牌；部分攻击还会按剩下的星辰增加伤害。", ["stars", "star_spend", "star_scale"], ["draw", "block", "energy"]],
		["blade", "锻造君王之剑", "反复锻造君王之剑让它变强，再把它拿回手牌继续攻击。", ["forge", "fetch_blade"], ["strength", "block", "draw"]],
	],
	"medium": [
		["osty", "奥斯蒂帮忙作战", "增加奥斯蒂生命，让它替你承受攻击并反击敌人。", ["osty_summon", "osty_attack"], ["soul_summon", "block", "draw"]],
		["doom", "灾厄收割", "给敌人累积灾厄；灾厄达到敌人剩余生命时，就能收割它。", ["doom"], ["weak", "block", "intangible"]],
		["souls", "灵魂抽牌", "生成免费灵魂牌来抽牌，打出灵魂还可以增加奥斯蒂生命。", ["soul_card", "soul_summon"], ["draw", "energy", "osty_summon"]],
	],
	"bellscribe": [
		["echo_strike", "回响攻击", "用攻击和格挡攒回响；攒够3点后，攻击牌可以额外造成伤害。", ["resonance", "resonant_damage"], ["draw", "energy", "multi_hit"]],
		["echo_guard", "回响防守", "用攻击和格挡攒回响；攒够3点后，格挡牌可以额外提供格挡。", ["resonance", "resonant_block"], ["block", "weak", "draw"]],
	],
	"ashlamper": [
		["ignite", "集中引燃", "给一个敌人加余烬，再一次引燃全部余烬造成伤害。", ["cinder_single", "ignite_single"], ["draw", "weak", "block"]],
		["wildfire", "余烬扩散", "给多个敌人加余烬，再同时引燃他们身上的余烬。", ["cinder_all", "ignite_all"], ["area_damage", "draw", "block"]],
	],
}

const TAG_TEXT = {
	"strength": "力量能提高攻击伤害", "multi_hit": "这张牌会连续攻击", "vulnerable": "让敌人更容易受伤",
	"draw": "补充手牌", "energy": "补充能量", "block": "获得格挡",
	"exhaust_fuel": "打出后本场不会再抽到", "exhaust_payoff": "消耗牌可带来额外效果",
	"block_damage": "格挡越多，伤害越高", "retain_block": "格挡会留到下回合", "thorns": "受到攻击时反击",
	"weak": "降低敌人的攻击伤害", "intangible": "每次受到伤害最多损失1点生命", "poison": "中毒会持续扣血",
	"poison_multiply": "增加敌人已有的中毒", "poison_scale": "敌人中毒越多，伤害越高", "shiv": "获得免费小刀",
	"shiv_damage": "提高小刀伤害", "discard": "可以主动弃牌", "sly": "主动弃掉时免费打出",
	"discard_payoff": "弃牌后还能抽牌或得能量", "lightning": "生成闪电球", "frost": "生成冰霜球",
	"dark": "生成黑暗球", "focus": "强化部分充能球", "evoke": "立刻触发最左边的球", "orb_slots": "增加球位",
	"stars": "积攒星辰", "star_spend": "打出时花费星辰", "star_scale": "星辰越多，伤害越高",
	"forge": "锻造并强化君王之剑", "fetch_blade": "把君王之剑拿回手牌", "osty_summon": "增加奥斯蒂生命",
	"osty_attack": "让奥斯蒂攻击", "soul_summon": "打出灵魂会增加奥斯蒂生命", "doom": "累积灾厄来收割敌人",
	"soul_card": "获得免费灵魂牌", "resonance": "积攒回响", "resonant_damage": "花3点回响追加攻击",
	"resonant_block": "花3点回响增加格挡", "cinder_single": "给一个敌人加余烬", "ignite_single": "引燃一个敌人的余烬",
	"cinder_all": "给多个敌人加余烬", "ignite_all": "引燃多个敌人的余烬", "area_damage": "攻击多个敌人",
}


static func options(role_id: String) -> Array:
	var result: Array = [{"id": "", "name": "自由选择 · 自动推荐", "description": "不固定玩法；奖励会按当前牌组自动标出更搭的卡。", "core": [], "support": []}]
	for plan in PLANS.get(role_id, []):
		result.append({"id": plan[0], "name": plan[1], "description": plan[2], "core": plan[3].duplicate(), "support": plan[4].duplicate()})
	return result


static func plan_for(role_id: String, plan_id: String) -> Dictionary:
	for plan in options(role_id):
		if plan.id == plan_id:
			return plan
	return {}


static func inferred_plan(role_id: String, deck: Array) -> Dictionary:
	var role_options := options(role_id)
	if role_options.size() <= 1:
		return {}
	var best: Dictionary = role_options[1]
	var best_score := -1
	var best_core_count := 0
	for plan in role_options.slice(1):
		var core_count := 0
		var support_count := 0
		for card in deck:
			var tags := card_tags(card)
			if plan.core.any(func(tag): return tags.has(tag)):
				core_count += 1
			if plan.support.any(func(tag): return tags.has(tag)):
				support_count += 1
		var score := affinity_score(core_count, support_count)
		if score > best_score:
			best = plan
			best_score = score
			best_core_count = core_count
	return {"plan": best, "score": maxi(0, best_score), "core_count": best_core_count}


static func card_tags(card: Dictionary) -> Array:
	var tags: Array = []
	for effect in card.get("effects", []):
		if int(effect.get("value", 0)) <= 0 and str(effect.get("op", "")) != "block_damage":
			continue
		var op := str(effect.get("op", ""))
		if TAG_TEXT.has(op):
			tags.append(op)
		match op:
			"strength_each_turn": tags.append("strength")
			"next_energy": tags.append("energy")
			"exhaust_hand": tags.append("exhaust_fuel")
			"exhaust_draw", "exhaust_block": tags.append("exhaust_payoff")
			"discard_draw", "discard_energy": tags.append("discard_payoff")
			"dualcast": tags.append("evoke")
			"channel": tags.append(str(effect.get("orb", "")))
			"cinder", "ignite": tags.append(op + ("_all" if effect.get("target", "") == "all" else "_single"))
		if op in ["damage", "lifesteal", "block_damage"]:
			if int(effect.get("hits", 1)) > 1:
				tags.append("multi_hit")
			if effect.get("target", "") == "all":
				tags.append("area_damage")
		if effect.get("scale", "") == "stars":
			tags.append("star_scale")
		elif effect.get("scale", "") == "poison":
			tags.append("poison_scale")
	if bool(card.get("exhaust", false)):
		tags.append("exhaust_fuel")
	if bool(card.get("sly", false)):
		tags.append("sly")
	if int(card.get("star_cost", 0)) > 0:
		tags.append("star_spend")
	var unique: Array = []
	for tag in tags:
		if not unique.has(tag):
			unique.append(tag)
	return unique


## Core synergy always outweighs generic support; suggestions do not affect random rewards.
static func affinity_score(core_matches: int, support_matches: int) -> int:
	return maxi(0, core_matches) * 10 + mini(3, maxi(0, support_matches))


static func recommend(card: Dictionary, role_id: String, plan_id: String, deck: Array = []) -> Dictionary:
	var automatic := plan_id.is_empty()
	var inferred := inferred_plan(role_id, deck) if automatic else {}
	var plan: Dictionary = inferred.get("plan", {}) if automatic else plan_for(role_id, plan_id)
	var result := {"score": 0, "tier": "none", "label": "按需要选择", "reason": "", "core_count": 0, "owned": 0, "plan_id": str(plan.get("id", "")), "plan_name": str(plan.get("name", "")), "source": "automatic" if automatic else "preset"}
	if plan.is_empty() or card.is_empty() or card.get("role", "neutral") not in [role_id, "neutral"]:
		return result
	var tags := card_tags(card)
	var primary: Array = plan.core.filter(func(tag): return tags.has(tag))
	var support: Array = plan.support.filter(func(tag): return tags.has(tag))
	result.score = affinity_score(primary.size(), support.size())
	var reasons: Array[String] = []
	for tag in primary + support:
		reasons.append(str(TAG_TEXT[tag]))
	if not primary.is_empty():
		result.tier = "core"
		result.label = "推荐 · 核心牌"
	elif not support.is_empty():
		result.tier = "support"
		result.label = "可选 · 有帮助"
	else:
		result.label = "其他选择"
	if not reasons.is_empty():
		result.reason = "、".join(reasons.slice(0, 2))
	elif automatic:
		result.reason = "你的牌组更偏向「%s」。这张牌配合不多，可按需要选择。" % plan.name
	else:
		result.reason = "这张牌和当前玩法配合不多，可以按需要选择。"
	for owned_card in deck:
		if str(owned_card.get("id", "")) == str(card.get("id", "")):
			result.owned += 1
		var owned_tags := card_tags(owned_card)
		if plan.core.any(func(tag): return owned_tags.has(tag)):
			result.core_count += 1
	return result
