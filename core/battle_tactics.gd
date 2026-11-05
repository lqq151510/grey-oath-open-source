extends RefCounted
## Shared tactical rules. Calculations return new values without mutating game state.

const MAX_POINTS := 3
const COST := 2
const GAIN_LIMIT := 2
const BASE_STRIKE_DAMAGE := 6
const BASE_GUARD_BLOCK := 7
const CHAPTER_STRIKE_STEP := 2
const CHAPTER_GUARD_STEP := 2
const CYCLE_DRAW := 2
const OPTIONS := [
	{"id": "strike", "name": "追击"},
	{"id": "guard", "name": "固守"},
	{"id": "cycle", "name": "整备"},
]


# 战术收益随章节提升，让应变在后期仍值 2 点：章节 0 与旧版数值完全一致。
static func strike_damage(chapter: int) -> int:
	return BASE_STRIKE_DAMAGE + CHAPTER_STRIKE_STEP * clampi(chapter, 0, 9)


static func guard_block(chapter: int) -> int:
	return BASE_GUARD_BLOCK + CHAPTER_GUARD_STEP * clampi(chapter, 0, 9)


static func option_title(id: String, chapter: int) -> String:
	match id:
		"strike": return "追击 · %d伤害" % strike_damage(chapter)
		"guard": return "固守 · %d格挡" % guard_block(chapter)
		"cycle": return "整备 · 抽%d弃1" % CYCLE_DRAW
	return id


static func option_description(id: String, chapter: int) -> String:
	match id:
		"strike": return "对选中敌人造成 %d 点固定伤害，受格挡与虚化影响。不受力量、虚弱、易伤影响，不触发荆棘或攻击牌效果。" % strike_damage(chapter)
		"guard": return "获得 %d 点固定格挡，不受敏捷与脆弱影响。" % guard_block(chapter)
		"cycle": return "抽 %d 张牌，再主动弃置 1 张；可触发机巧。需要至少 2 个手牌空位与 2 张可抽牌。" % CYCLE_DRAW
	return ""


# 学习入口：这段纯函数决定哪些出牌顺序能获得应变；默认实现可直接游玩。
# 如调整奖励策略，保留每回合获取上限与持有上限，并同步运行 test_tactics.gd。
static func next_chain(points: int, gained: int, last_type: String, card_type: String) -> Dictionary:
	var result := {"points": points, "gained": gained, "last_type": last_type, "added": 0}
	if card_type not in ["attack", "skill"]:
		return result
	if not last_type.is_empty() and card_type != last_type and points < MAX_POINTS and gained < GAIN_LIMIT:
		result.points += 1
		result.gained += 1
		result.added = 1
	result.last_type = card_type
	return result


static func chain_hint(points: int, gained: int, last_type: String) -> String:
	if points >= MAX_POINTS:
		return "应变已满：可发动战术，或保留到下一回合。"
	if points >= COST:
		return "应变已足够：现在就能发动一次战术，也可以继续连携攒到 3 点。"
	if gained >= GAIN_LIMIT:
		return "本回合已获得 2 点应变，下回合可继续连携。"
	match last_type:
		"attack": return "上一张为攻击牌 → 再打技能牌可获得 1 点应变。"
		"skill": return "上一张为技能牌 → 再打攻击牌可获得 1 点应变。"
	return "交替打出攻击牌与技能牌，获得应变；能力牌不打断连携。"
