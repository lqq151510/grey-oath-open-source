extends RefCounted
## Cards are listed in draw order. Guidance is optional and never gates combat.

const LESSONS := {
	"warden": {
		"title": "墓园初战", "focus": "格挡与力量", "enemy": "ch1_normal_01", "hp": 27,
		"deck": [
			"warden_02", "warden_01", "warden_01", "warden_02", "warden_02",
			"warden_04", "warden_01", "warden_01", "warden_02", "warden_02",
		],
		"opening": [
			["warden_02", "看敌人头顶的意图。把「铁甲·坚守」拖到战场，获得 7 格挡来抵消伤害。"],
			["warden_01", "把「铁甲·重斩」拖到敌人身上。力量会提高每段攻击的伤害。"],
		],
		"end_turn": "点「结束回合」或按 E，观察格挡怎样抵消伤害。",
		"followup": [
			["warden_04", "格挡在新回合清空。先把「铁甲·战意」拖到战场，让后续重斩打得更重。"],
			["warden_01", "把「铁甲·重斩」拖到敌人身上。对比加力量前后的伤害。"],
		],
		"recap": "先用格挡应对敌方攻击，再用力量提高后续攻击的每段伤害。",
	},
	"ranger": {
		"title": "碑影伏击", "focus": "主动弃牌与机巧", "enemy": "ch1_normal_05", "hp": 30,
		"deck": [
			"ranger_04", "ranger_08", "ranger_03", "ranger_01", "ranger_02", "ranger_02", "ranger_01",
			"ranger_01", "ranger_01", "ranger_01", "ranger_02", "ranger_02",
		],
		"opening": [
			["ranger_04", "把「猎手·生存」拖到战场，获得格挡并打开弃牌窗口。保留手里的「猎手·机巧」供弃置。"],
			["ranger_03", "把 0 费的「猎手·断筋」拖到敌人身上，施加虚弱以降低它的攻击。"],
			["ranger_01", "用剩余能量打出「猎手·突刺」。格挡足够时，可以把能量留给进攻。"],
		],
		"end_turn": "点「结束回合」或按 E。回合结束时自动丢掉的牌不会触发机巧。",
		"followup": [
			["ranger_01", "用「猎手·突刺」收尾。记住，主动弃置机巧牌能省下它的能量费用。"],
		],
		"recap": "先打出带主动弃牌的牌，再在弹窗里选择机巧牌，让它免费结算。",
	},
	"sister": {
		"title": "雷槽重启", "focus": "充能球与双放", "enemy": "ch1_normal_02", "hp": 27,
		"deck": [
			"sister_03", "sister_04", "sister_02", "sister_01", "sister_02",
			"sister_01", "sister_01", "sister_01", "sister_02", "sister_02",
		],
		"opening": [
			["sister_03", "你开场就有一颗闪电球。把「机体·充电」拖到战场，生成第二颗。"],
			["sister_04", "把「机体·双放」拖到战场，移除最左一颗球，并将它的激发效果结算两次。"],
			["sister_02", "把「机体·护壁」拖到战场，挡下大部分伤害。留在球槽里的闪电会在回合结束时自动伤敌。"],
		],
		"end_turn": "点「结束回合」或按 E，观察剩余闪电球先造成被动伤害。",
		"followup": [
			["sister_01", "把「机体·冲击」拖到敌人身上。还差一点伤害时，结束回合可让闪电补刀。"],
		],
		"recap": "充能会把球放入槽中。留着球可以获得被动效果，双放则用掉最左的球换取两次激发。",
	},
	"arcanist": {
		"title": "初铸王剑", "focus": "星辰、锻造与保留", "enemy": "ch1_normal_08", "hp": 31,
		"deck": [
			"arcanist_04", "arcanist_03", "arcanist_02", "arcanist_01", "arcanist_02",
			"arcanist_01", "arcanist_01", "arcanist_02", "arcanist_02", "arcanist_02",
		],
		"opening": [
			["arcanist_04", "把「储君·铸誓」拖到战场，获得星辰并创造「君王之剑」。锻造越高，剑伤越高。"],
			["arcanist_03", "把「储君·落星」拖到敌人身上。这张牌花 2 星辰，能量费用是 0。"],
		],
		"end_turn": "可以先结束回合，看看有「保留」的君王之剑如何留在手中。",
		"followup": [
			["token_blade", "「君王之剑」保留到了新回合。把它拖到敌人身上，花 2 能量打出锻造后的伤害。"],
			["arcanist_01", "用「储君·敕击」收尾。先前的格挡会抵消一部分剑伤。"],
		],
		"recap": "星辰和能量分别支付。锻造会提高君王之剑的伤害，保留让你能把剑留到下一回合。",
	},
	"medium": {
		"title": "鸦墓契约", "focus": "奥斯蒂代承与灾厄收割", "enemy": "ch1_normal_07", "hp": 28,
		"deck": [
			"medium_03", "medium_01", "medium_04", "medium_02", "medium_02",
			"medium_01", "medium_01", "medium_04", "medium_02", "medium_02",
		],
		"opening": [
			["medium_03", "把「契约·护卫」拖到敌人身上。奥斯蒂会增加 6 生命并攻击它。"],
			["medium_01", "用「契约·刺骨」把敌人压到 10 生命。灾厄达到敌人当前生命时才能收割。"],
			["medium_04", "把「契约·咒印」拖到敌人身上，施加 10 灾厄。它会在敌人行动后检查收割。"],
		],
		"end_turn": "点「结束回合」或按 E。先看奥斯蒂代承攻击，再看灾厄是否收割敌人。",
		"followup": [
			["medium_01", "用「契约·刺骨」压低敌人生命，查看它身上的灾厄层数。"],
		],
		"recap": "奥斯蒂代承穿过格挡的攻击。灾厄达到敌人当前生命时，会在它的回合结束时收割。",
	},
	"bellscribe": {
		"title": "听钟试音", "focus": "攒回响再触发共鸣", "enemy": "ch1_normal_04", "hp": 46,
		"deck": [
			"bellscribe_02", "bellscribe_03", "bellscribe_01", "bellscribe_02", "bellscribe_04",
			"bellscribe_01", "bellscribe_01", "bellscribe_03", "bellscribe_02", "bellscribe_04",
		],
		"opening": [
			["bellscribe_02", "开场有 2 回响。把「抱钟」拖到战场，获得格挡并把回响攒到 3。"],
			["bellscribe_03", "把「敲碑」拖到敌人身上。手上有 3 回响时，这张牌会消耗它们，追加 8 伤害。"],
			["bellscribe_01", "用「拓音」攻击并补 1 回响。回响可以留到下一回合。"],
		],
		"end_turn": "点「结束回合」或按 E。下一回合先看剩余回响，再决定何时打共鸣牌。",
		"followup": [
			["bellscribe_01", "把「拓音」拖到敌人身上。每次加 1 回响，够 3 后再打「敲碑」。"],
			["bellscribe_03", "用「敲碑」收尾。看看这次回响够不够触发追加伤害。"],
		],
		"recap": "用抱钟或拓音攒回响，到 3 点再打共鸣牌，换取追加伤害或格挡。",
	},
	"ashlamper": {
		"title": "灰巷引火", "focus": "叠余烬再引燃", "enemy": "ch1_normal_03", "hp": 46,
		"deck": [
			"ashlamper_01", "ashlamper_04", "ashlamper_03", "ashlamper_02", "ashlamper_02",
			"ashlamper_01", "ashlamper_01", "ashlamper_03", "ashlamper_02", "ashlamper_02",
		],
		"opening": [
			["ashlamper_01", "把「灯针」拖到敌人身上，造成伤害并叠 2 层余烬。留意敌人状态栏。"],
			["ashlamper_04", "把「分火」拖到敌人身上。它给你格挡，并为同一目标再加 3 层余烬。"],
			["ashlamper_03", "把「点烬」拖到有余烬的敌人身上。它先消耗余烬造成每层 2 伤害，再结算攻击。"],
		],
		"end_turn": "点「结束回合」或按 E。引燃后要重新叠余烬，才能再打出这段伤害。",
		"followup": [
			["ashlamper_01", "用「灯针」重新叠余烬。把火集中到准备引燃的同一名敌人身上。"],
			["ashlamper_03", "用「点烬」引燃刚叠的余烬，收尾。"],
		],
		"recap": "把余烬叠在同一目标身上，再引燃结算。引燃会清空这个目标的余烬。",
	},
}
