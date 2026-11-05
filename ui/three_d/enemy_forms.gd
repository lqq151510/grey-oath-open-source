extends RefCounted
## 56 个敌人的 3D 造型 spec 表（显式数据，不依赖 actor_rig.gd）。
##
## 契约（docs/UI_REBUILD_20261104.md 第三节）：
##   static func spec(enemy_id: String, definition: Dictionary) -> Dictionary
## 返回键：id / name / archetype / height / bulk / palette / weapon / accessories / seed，
## 另外附带 chapter / tier 供测试与捕捉脚本使用。每条 spec 的 height 以
## BASE_HEIGHTS[archetype] 为骨架高度，按 tier 放大：普通 0.86~1.12 倍骨架、
## 精英 1.10~1.25 倍、首领 1.35~1.80 倍；bulk 同步变重（普通 <=1.10，精英 >=1.12，首领 >=1.22）。
## 四章色温：沉钟墓园灰绿、荆棘修道院暗红、失星观测所冷蓝、无日王庭旧金黑。
##
## 与 ui/three_d/actor_rig.gd 的接口对照（已逐项核对 2026-11-04 rig3d 版本）：
##   archetype  -> rig 的 _build_body() match 分支：skeleton/knight/caster/sovereign/
##                 automaton/giant/wraith/beast/moth/raven/worm/eye/bell，
##                 其余（含 humanoid）走默认 _humanoid_body({})。
##   weapon     -> rig 的 _apply_weapon()：none 直接返回，其余 sword/spear/staff/
##                 scythe/claw/hammer/banner/bell 均有专属构件；未知值会退化成剑，
##                 因此本表只写这九个合法值。
##   accessories-> rig 的 _apply_accessories() match：cloak/hood/horns/crown/wings/
##                 shield/lantern/chains/mask/books，与上方 ACCESSORIES 完全一致。
##   palette    -> rig 读取 cloth/metal/trim/accent/skin/dark 六色并派生
##                 cloth_dark、metal_light、bone、glow 等；六键必须齐全。
##   height     -> rig 会把 height 夹到 1.15..3.4；本表所有值落在 1.15..3.36，
##                 因此 spec 高度与实际渲染高度一致，不会被静默改尺寸。
##   bulk       -> rig 会把 bulk 夹到 0.70..1.65；本表 0.90..1.32，全部原样生效。
##   staff_top  -> 可选扩展键（仅 weapon=staff 的条目带）：rig 支持 orb/star/
##                 lantern/censer，用于同原型法杖造型区分；缺省 orb。
##
## 造型区分策略：同 archetype 靠 height 抖动 + bulk + 武器 + 配件组合 + 六色配色 +
## seed 细节抖动区分；精英比普通重且高 10~25%，首领 1.35~1.8 倍且必带专属配件。

const ARCHETYPES := [
	"humanoid", "skeleton", "knight", "caster", "beast", "moth", "raven",
	"worm", "eye", "bell", "sovereign", "automaton", "giant", "wraith",
]
const WEAPONS := ["none", "sword", "spear", "staff", "scythe", "claw", "hammer", "banner", "bell"]
const ACCESSORIES := ["cloak", "hood", "horns", "crown", "wings", "shield", "lantern", "chains", "mask", "books"]

## 各原型普通档的骨架高度（米）。精英/首领在此基础上按 tier 放大。
const BASE_HEIGHTS := {
	"humanoid": 1.80, "skeleton": 1.72, "knight": 1.95, "caster": 1.76,
	"beast": 1.30, "moth": 1.15, "raven": 1.16, "worm": 1.15,
	"eye": 1.60, "bell": 2.10, "sovereign": 2.10, "automaton": 1.90,
	"giant": 2.30, "wraith": 1.85,
}

## 章节主色（与 data/catalog.json chapters[].color 一致），用于兜底配色。
const CHAPTER_TINTS := {
	0: Color("a99c7d"), 1: Color("ad706b"), 2: Color("8c9eb7"), 3: Color("c7a66a"),
}

## 章节基色，四章色温明确区分；每条 spec 在其上做显式明度/色相偏移。
const CHAPTER_PALETTES := {
	0: {
		"cloth": Color("4a5248"), "metal": Color("565b52"), "trim": Color("8c8571"),
		"accent": Color("a9b08c"), "skin": Color("9aa088"), "dark": Color("1b211d"),
	},
	1: {
		"cloth": Color("5a2a2c"), "metal": Color("4a3a38"), "trim": Color("8a5a4a"),
		"accent": Color("b5554e"), "skin": Color("b09a94"), "dark": Color("1f1416"),
	},
	2: {
		"cloth": Color("2e3c50"), "metal": Color("5a6a78"), "trim": Color("7f97a8"),
		"accent": Color("8cc3d6"), "skin": Color("98a8b4"), "dark": Color("10161f"),
	},
	3: {
		"cloth": Color("211e1a"), "metal": Color("8a7434"), "trim": Color("c7a66a"),
		"accent": Color("d8b96f"), "skin": Color("a79c86"), "dark": Color("0e0c09"),
	},
}

## 56 条显式造型。顺序与 data/catalog.json enemies 一致（4 章 × 13 + 4 个机制敌人）。
const SPECS := {
	"ch1_normal_01": {
		"id": "ch1_normal_01", "name": "失名掘墓人", "chapter": 0, "tier": "normal",
		"archetype": "humanoid", "height": 1.764, "bulk": 1.02,
		"palette": {"cloth": Color("464e44"), "metal": Color("565b52"), "trim": Color("8c8571"), "accent": Color("a9b08c"), "skin": Color("8f9884"), "dark": Color("1b211d")},
		"weapon": "hammer", "accessories": ["cloak", "hood"], "seed": 108,
	},
	"ch1_normal_02": {
		"id": "ch1_normal_02", "name": "枯骨哨兵", "chapter": 0, "tier": "normal",
		"archetype": "skeleton", "height": 1.754, "bulk": 0.9,
		"palette": {"cloth": Color("3f463f"), "metal": Color("6a6f64"), "trim": Color("9a947e"), "accent": Color("c8cbb0"), "skin": Color("d8d5bd"), "dark": Color("1b211d")},
		"weapon": "spear", "accessories": ["shield"], "seed": 205,
	},
	"ch1_normal_03": {
		"id": "ch1_normal_03", "name": "墓灯蛾", "chapter": 0, "tier": "normal",
		"archetype": "moth", "height": 1.15, "bulk": 0.95,
		"palette": {"cloth": Color("5f6a56"), "metal": Color("7c8264"), "trim": Color("b3a67e"), "accent": Color("d6c07c"), "skin": Color("c9c7a6"), "dark": Color("2a3126")},
		"weapon": "none", "accessories": ["lantern"], "seed": 302,
	},
	"ch1_normal_04": {
		"id": "ch1_normal_04", "name": "沉泥尸", "chapter": 0, "tier": "normal",
		"archetype": "humanoid", "height": 1.89, "bulk": 1.1,
		"palette": {"cloth": Color("3b4038"), "metal": Color("565b52"), "trim": Color("7a745f"), "accent": Color("8e9a78"), "skin": Color("6d7a63"), "dark": Color("1b211d")},
		"weapon": "none", "accessories": ["chains"], "seed": 399,
	},
	"ch1_normal_05": {
		"id": "ch1_normal_05", "name": "守碑犬", "chapter": 0, "tier": "normal",
		"archetype": "beast", "height": 1.3, "bulk": 1.05,
		"palette": {"cloth": Color("4b5147"), "metal": Color("5c6055"), "trim": Color("8c8571"), "accent": Color("b9a97e"), "skin": Color("7f8672"), "dark": Color("1b211d")},
		"weapon": "claw", "accessories": [], "seed": 496,
	},
	"ch1_normal_06": {
		"id": "ch1_normal_06", "name": "锈钟小卒", "chapter": 0, "tier": "normal",
		"archetype": "automaton", "height": 1.805, "bulk": 0.95,
		"palette": {"cloth": Color("5a5148"), "metal": Color("8a5f3f"), "trim": Color("a08050"), "accent": Color("b98a55"), "skin": Color("9a8a70"), "dark": Color("1b211d")},
		"weapon": "bell", "accessories": [], "seed": 593,
	},
	"ch1_normal_07": {
		"id": "ch1_normal_07", "name": "灰鸦", "chapter": 0, "tier": "normal",
		"archetype": "raven", "height": 1.16, "bulk": 0.92,
		"palette": {"cloth": Color("5e6d70"), "metal": Color("7a8b90"), "trim": Color("b6c3c6"), "accent": Color("d2e0e3"), "skin": Color("a3b2b7"), "dark": Color("39464a")},
		"weapon": "none", "accessories": [], "seed": 690,
	},
	"ch1_normal_08": {
		"id": "ch1_normal_08", "name": "遗忘的送葬者", "chapter": 0, "tier": "normal",
		"archetype": "wraith", "height": 1.85, "bulk": 0.94,
		"palette": {"cloth": Color("3a4239"), "metal": Color("555a50"), "trim": Color("b0a98c"), "accent": Color("9fb59c"), "skin": Color("8f9a8b"), "dark": Color("1b211d")},
		"weapon": "staff", "accessories": ["hood", "lantern"], "seed": 787, "staff_top": "lantern",
	},
	"ch1_elite_09": {
		"id": "ch1_elite_09", "name": "负钟巨人", "chapter": 0, "tier": "elite",
		"archetype": "giant", "height": 2.806, "bulk": 1.18,
		"palette": {"cloth": Color("4d5347"), "metal": Color("7a6a4a"), "trim": Color("8c8571"), "accent": Color("c0a36a"), "skin": Color("8a8f78"), "dark": Color("1b211d")},
		"weapon": "bell", "accessories": ["chains"], "seed": 884,
	},
	"ch1_elite_10": {
		"id": "ch1_elite_10", "name": "无面守墓人", "chapter": 0, "tier": "elite",
		"archetype": "knight", "height": 2.242, "bulk": 1.16,
		"palette": {"cloth": Color("3e4640"), "metal": Color("5f6558"), "trim": Color("90896f"), "accent": Color("aebba3"), "skin": Color("c9c6b0"), "dark": Color("1b211d")},
		"weapon": "spear", "accessories": ["mask", "shield"], "seed": 981,
	},
	"ch1_elite_11": {
		"id": "ch1_elite_11", "name": "缠链骑士", "chapter": 0, "tier": "elite",
		"archetype": "knight", "height": 2.301, "bulk": 1.2,
		"palette": {"cloth": Color("444a42"), "metal": Color("6a6a5c"), "trim": Color("a38d5f"), "accent": Color("9aa98f"), "skin": Color("7c8272"), "dark": Color("1b211d")},
		"weapon": "sword", "accessories": ["chains"], "seed": 1078,
	},
	"ch1_boss_12": {
		"id": "ch1_boss_12", "name": "沉钟看守", "chapter": 0, "tier": "boss",
		"archetype": "bell", "height": 3.15, "bulk": 1.3,
		"palette": {"cloth": Color("4a5044"), "metal": Color("6f5a3c"), "trim": Color("8c8571"), "accent": Color("d0b273"), "skin": Color("9aa084"), "dark": Color("1b211d")},
		"weapon": "bell", "accessories": ["chains", "crown"], "seed": 1175,
	},
	"ch1_boss_13": {
		"id": "ch1_boss_13", "name": "墓园的无名王", "chapter": 0, "tier": "boss",
		"archetype": "sovereign", "height": 3.255, "bulk": 1.28,
		"palette": {"cloth": Color("343b34"), "metal": Color("8a7748"), "trim": Color("b89a5e"), "accent": Color("d4b878"), "skin": Color("c2bda4"), "dark": Color("1b211d")},
		"weapon": "banner", "accessories": ["crown", "cloak"], "seed": 1272,
	},
	"ch2_normal_01": {
		"id": "ch2_normal_01", "name": "刺冠侍者", "chapter": 1, "tier": "normal",
		"archetype": "humanoid", "height": 1.728, "bulk": 0.98,
		"palette": {"cloth": Color("552a2c"), "metal": Color("4a3a38"), "trim": Color("9a5f4e"), "accent": Color("c06a5e"), "skin": Color("b09a94"), "dark": Color("1f1416")},
		"weapon": "staff", "accessories": ["horns"], "seed": 1376, "staff_top": "censer",
	},
	"ch2_normal_02": {
		"id": "ch2_normal_02", "name": "蜡泪修士", "chapter": 1, "tier": "normal",
		"archetype": "caster", "height": 1.76, "bulk": 0.92,
		"palette": {"cloth": Color("4a2a2a"), "metal": Color("4f3e38"), "trim": Color("8a6a52"), "accent": Color("d8c09a"), "skin": Color("cdb8a2"), "dark": Color("1f1416")},
		"weapon": "staff", "accessories": ["hood"], "seed": 1473, "staff_top": "lantern",
	},
	"ch2_normal_03": {
		"id": "ch2_normal_03", "name": "荆鞭苦行者", "chapter": 1, "tier": "normal",
		"archetype": "humanoid", "height": 1.872, "bulk": 1.04,
		"palette": {"cloth": Color("5e2628"), "metal": Color("4a3a38"), "trim": Color("7a4538"), "accent": Color("a83f3c"), "skin": Color("8e5f55"), "dark": Color("1f1416")},
		"weapon": "claw", "accessories": [], "seed": 1570,
	},
	"ch2_normal_04": {
		"id": "ch2_normal_04", "name": "破袍颂唱者", "chapter": 1, "tier": "normal",
		"archetype": "caster", "height": 1.795, "bulk": 0.94,
		"palette": {"cloth": Color("6a3134"), "metal": Color("4a3a38"), "trim": Color("9a6048"), "accent": Color("c98a72"), "skin": Color("a88a84"), "dark": Color("1f1416")},
		"weapon": "none", "accessories": ["books", "hood"], "seed": 1667,
	},
	"ch2_normal_05": {
		"id": "ch2_normal_05", "name": "圣烛兽", "chapter": 1, "tier": "normal",
		"archetype": "beast", "height": 1.326, "bulk": 1,
		"palette": {"cloth": Color("4f2325"), "metal": Color("5a4038"), "trim": Color("8a5a4a"), "accent": Color("e0b46a"), "skin": Color("9a6a5a"), "dark": Color("1f1416")},
		"weapon": "none", "accessories": ["lantern"], "seed": 1764,
	},
	"ch2_normal_06": {
		"id": "ch2_normal_06", "name": "藤甲门卫", "chapter": 1, "tier": "normal",
		"archetype": "knight", "height": 1.911, "bulk": 1.08,
		"palette": {"cloth": Color("3f2a28"), "metal": Color("5a4a3e"), "trim": Color("8a7a52"), "accent": Color("7f8a5f"), "skin": Color("8a7a68"), "dark": Color("1f1416")},
		"weapon": "spear", "accessories": ["shield"], "seed": 1861,
	},
	"ch2_normal_07": {
		"id": "ch2_normal_07", "name": "血墨抄经人", "chapter": 1, "tier": "normal",
		"archetype": "caster", "height": 1.725, "bulk": 0.9,
		"palette": {"cloth": Color("4a2024"), "metal": Color("4a3a38"), "trim": Color("8a5a4a"), "accent": Color("9a3f3a"), "skin": Color("b8a49a"), "dark": Color("1f1416")},
		"weapon": "staff", "accessories": ["books", "mask"], "seed": 1958, "staff_top": "orb",
	},
	"ch2_normal_08": {
		"id": "ch2_normal_08", "name": "赎罪信徒", "chapter": 1, "tier": "normal",
		"archetype": "humanoid", "height": 1.8, "bulk": 1.02,
		"palette": {"cloth": Color("5e3a36"), "metal": Color("4f3a34"), "trim": Color("8a5a4a"), "accent": Color("b56a5e"), "skin": Color("a89088"), "dark": Color("1f1416")},
		"weapon": "none", "accessories": ["chains", "hood"], "seed": 2055,
	},
	"ch2_elite_09": {
		"id": "ch2_elite_09", "name": "执刑圣像", "chapter": 1, "tier": "elite",
		"archetype": "giant", "height": 2.599, "bulk": 1.2,
		"palette": {"cloth": Color("3a2426"), "metal": Color("7a5a44"), "trim": Color("9a6a4a"), "accent": Color("b06a52"), "skin": Color("b8a89a"), "dark": Color("1f1416")},
		"weapon": "hammer", "accessories": ["mask"], "seed": 2152,
	},
	"ch2_elite_10": {
		"id": "ch2_elite_10", "name": "荆棘审判官", "chapter": 1, "tier": "elite",
		"archetype": "knight", "height": 2.34, "bulk": 1.17,
		"palette": {"cloth": Color("4a1e20"), "metal": Color("4a3834"), "trim": Color("8a4a3e"), "accent": Color("c04a44"), "skin": Color("9a7a72"), "dark": Color("1f1416")},
		"weapon": "scythe", "accessories": ["horns"], "seed": 2249,
	},
	"ch2_elite_11": {
		"id": "ch2_elite_11", "name": "缄默双刃", "chapter": 1, "tier": "elite",
		"archetype": "knight", "height": 2.242, "bulk": 1.13,
		"palette": {"cloth": Color("2e1c1e"), "metal": Color("7a6a64"), "trim": Color("9a6a58"), "accent": Color("d0b6a6"), "skin": Color("8a7a74"), "dark": Color("1f1416")},
		"weapon": "sword", "accessories": ["mask"], "seed": 2346,
	},
	"ch2_boss_12": {
		"id": "ch2_boss_12", "name": "无泪院长", "chapter": 1, "tier": "boss",
		"archetype": "caster", "height": 2.728, "bulk": 1.26,
		"palette": {"cloth": Color("3a1a1c"), "metal": Color("8a6a44"), "trim": Color("a87a4a"), "accent": Color("d8b06a"), "skin": Color("c8b6a6"), "dark": Color("1f1416")},
		"weapon": "staff", "accessories": ["books", "crown"], "seed": 2443, "staff_top": "censer",
	},
	"ch2_boss_13": {
		"id": "ch2_boss_13", "name": "盛放的圣母像", "chapter": 1, "tier": "boss",
		"archetype": "giant", "height": 3.335, "bulk": 1.3,
		"palette": {"cloth": Color("5a2426"), "metal": Color("8a6a4a"), "trim": Color("b8865e"), "accent": Color("e0a08a"), "skin": Color("c9b0a4"), "dark": Color("1f1416")},
		"weapon": "staff", "accessories": ["wings", "crown"], "seed": 2540, "staff_top": "star",
	},
	"ch3_normal_01": {
		"id": "ch3_normal_01", "name": "碎星学徒", "chapter": 2, "tier": "normal",
		"archetype": "humanoid", "height": 1.62, "bulk": 0.9,
		"palette": {"cloth": Color("2e3c50"), "metal": Color("5a6a78"), "trim": Color("7f97a8"), "accent": Color("9acbe0"), "skin": Color("98a8b4"), "dark": Color("10161f")},
		"weapon": "staff", "accessories": ["books"], "seed": 2644, "staff_top": "star",
	},
	"ch3_normal_02": {
		"id": "ch3_normal_02", "name": "盲眼观测者", "chapter": 2, "tier": "normal",
		"archetype": "eye", "height": 1.6, "bulk": 1,
		"palette": {"cloth": Color("24303f"), "metal": Color("5a6a78"), "trim": Color("7f97a8"), "accent": Color("c0dce8"), "skin": Color("b8c4cc"), "dark": Color("10161f")},
		"weapon": "none", "accessories": ["mask"], "seed": 2741,
	},
	"ch3_normal_03": {
		"id": "ch3_normal_03", "name": "铜镜傀儡", "chapter": 2, "tier": "normal",
		"archetype": "automaton", "height": 1.9, "bulk": 1,
		"palette": {"cloth": Color("3a3a34"), "metal": Color("9a7a4a"), "trim": Color("9a8a6a"), "accent": Color("c8b080"), "skin": Color("8a8a80"), "dark": Color("10161f")},
		"weapon": "none", "accessories": ["shield"], "seed": 2838,
	},
	"ch3_normal_04": {
		"id": "ch3_normal_04", "name": "星尘蠕虫", "chapter": 2, "tier": "normal",
		"archetype": "worm", "height": 1.15, "bulk": 1,
		"palette": {"cloth": Color("2a3548"), "metal": Color("4a5a68"), "trim": Color("7f97a8"), "accent": Color("a0d0e8"), "skin": Color("6a7a88"), "dark": Color("10161f")},
		"weapon": "none", "accessories": [], "seed": 2935,
	},
	"ch3_normal_05": {
		"id": "ch3_normal_05", "name": "错时信使", "chapter": 2, "tier": "normal",
		"archetype": "wraith", "height": 1.887, "bulk": 0.92,
		"palette": {"cloth": Color("333f52"), "metal": Color("55636f"), "trim": Color("7f97a8"), "accent": Color("8fbfd4"), "skin": Color("8a9aa8"), "dark": Color("10161f")},
		"weapon": "staff", "accessories": ["hood", "lantern"], "seed": 3032, "staff_top": "lantern",
	},
	"ch3_normal_06": {
		"id": "ch3_normal_06", "name": "月蚀残影", "chapter": 2, "tier": "normal",
		"archetype": "wraith", "height": 1.813, "bulk": 0.9,
		"palette": {"cloth": Color("1f2a38"), "metal": Color("4a5562"), "trim": Color("7f97a8"), "accent": Color("c8c0d8"), "skin": Color("7a8494"), "dark": Color("10161f")},
		"weapon": "none", "accessories": ["mask"], "seed": 3129,
	},
	"ch3_normal_07": {
		"id": "ch3_normal_07", "name": "黄道卫兵", "chapter": 2, "tier": "normal",
		"archetype": "knight", "height": 1.95, "bulk": 1.05,
		"palette": {"cloth": Color("2a3850"), "metal": Color("7a8a98"), "trim": Color("8a9aa8"), "accent": Color("b0c8e0"), "skin": Color("a0aeb8"), "dark": Color("10161f")},
		"weapon": "spear", "accessories": ["shield"], "seed": 3226,
	},
	"ch3_normal_08": {
		"id": "ch3_normal_08", "name": "引力侍从", "chapter": 2, "tier": "normal",
		"archetype": "caster", "height": 1.69, "bulk": 0.96,
		"palette": {"cloth": Color("38455a"), "metal": Color("5f6f7d"), "trim": Color("7f97a8"), "accent": Color("7fb0c8"), "skin": Color("94a4b0"), "dark": Color("10161f")},
		"weapon": "staff", "accessories": ["books"], "seed": 3323, "staff_top": "star",
	},
	"ch3_elite_09": {
		"id": "ch3_elite_09", "name": "陨铁巨像", "chapter": 2, "tier": "elite",
		"archetype": "giant", "height": 2.806, "bulk": 1.22,
		"palette": {"cloth": Color("26303e"), "metal": Color("5f6f7a"), "trim": Color("8a94a0"), "accent": Color("a8b8c0"), "skin": Color("6a747e"), "dark": Color("10161f")},
		"weapon": "hammer", "accessories": ["shield"], "seed": 3420,
	},
	"ch3_elite_10": {
		"id": "ch3_elite_10", "name": "失星大导师", "chapter": 2, "tier": "elite",
		"archetype": "caster", "height": 2.024, "bulk": 1.14,
		"palette": {"cloth": Color("1e2a3e"), "metal": Color("7a8a9a"), "trim": Color("9ab0c0"), "accent": Color("c0e0f0"), "skin": Color("b0bcc8"), "dark": Color("10161f")},
		"weapon": "staff", "accessories": ["books", "crown"], "seed": 3517, "staff_top": "star",
	},
	"ch3_elite_11": {
		"id": "ch3_elite_11", "name": "逆行巡猎者", "chapter": 2, "tier": "elite",
		"archetype": "wraith", "height": 2.183, "bulk": 1.15,
		"palette": {"cloth": Color("2a3244"), "metal": Color("606c78"), "trim": Color("7f97a8"), "accent": Color("90c0d8"), "skin": Color("7a8694"), "dark": Color("10161f")},
		"weapon": "scythe", "accessories": ["hood"], "seed": 3614,
	},
	"ch3_boss_12": {
		"id": "ch3_boss_12", "name": "无星占卜师", "chapter": 2, "tier": "boss",
		"archetype": "caster", "height": 2.781, "bulk": 1.25,
		"palette": {"cloth": Color("161e2e"), "metal": Color("8a9aac"), "trim": Color("aac0d0"), "accent": Color("d0ecff"), "skin": Color("c0ccd8"), "dark": Color("10161f")},
		"weapon": "staff", "accessories": ["books", "mask", "crown"], "seed": 3711, "staff_top": "star",
	},
	"ch3_boss_13": {
		"id": "ch3_boss_13", "name": "破碎天穹之眼", "chapter": 2, "tier": "boss",
		"archetype": "eye", "height": 2.592, "bulk": 1.3,
		"palette": {"cloth": Color("101826"), "metal": Color("5a6a7a"), "trim": Color("8fb0c8"), "accent": Color("c8eaff"), "skin": Color("b8cce0"), "dark": Color("10161f")},
		"weapon": "none", "accessories": ["horns"], "seed": 3808,
	},
	"ch4_normal_01": {
		"id": "ch4_normal_01", "name": "空铠近卫", "chapter": 3, "tier": "normal",
		"archetype": "automaton", "height": 1.9, "bulk": 1.05,
		"palette": {"cloth": Color("1e1c18"), "metal": Color("7a6a3a"), "trim": Color("c7a66a"), "accent": Color("c7a66a"), "skin": Color("8a8272"), "dark": Color("0e0c09")},
		"weapon": "spear", "accessories": ["shield"], "seed": 3912,
	},
	"ch4_normal_02": {
		"id": "ch4_normal_02", "name": "王庭执灯人", "chapter": 3, "tier": "normal",
		"archetype": "humanoid", "height": 1.764, "bulk": 0.96,
		"palette": {"cloth": Color("24201a"), "metal": Color("6a5a34"), "trim": Color("c7a66a"), "accent": Color("e0c07a"), "skin": Color("9a9078"), "dark": Color("0e0c09")},
		"weapon": "staff", "accessories": ["lantern", "cloak"], "seed": 4009, "staff_top": "lantern",
	},
	"ch4_normal_03": {
		"id": "ch4_normal_03", "name": "枯荣侍女", "chapter": 3, "tier": "normal",
		"archetype": "wraith", "height": 1.776, "bulk": 0.9,
		"palette": {"cloth": Color("2a2620"), "metal": Color("7a6a48"), "trim": Color("c7a66a"), "accent": Color("c8a878"), "skin": Color("a89e8a"), "dark": Color("0e0c09")},
		"weapon": "staff", "accessories": ["crown"], "seed": 4106, "staff_top": "lantern",
	},
	"ch4_normal_04": {
		"id": "ch4_normal_04", "name": "旧誓书记官", "chapter": 3, "tier": "normal",
		"archetype": "caster", "height": 1.725, "bulk": 0.92,
		"palette": {"cloth": Color("1c1a16"), "metal": Color("8a7434"), "trim": Color("c7a66a"), "accent": Color("d0b070"), "skin": Color("b0a48c"), "dark": Color("0e0c09")},
		"weapon": "staff", "accessories": ["books"], "seed": 4203, "staff_top": "orb",
	},
	"ch4_normal_05": {
		"id": "ch4_normal_05", "name": "断冠骑士", "chapter": 3, "tier": "normal",
		"archetype": "knight", "height": 1.95, "bulk": 1.02,
		"palette": {"cloth": Color("22201a"), "metal": Color("8a7a44"), "trim": Color("b09050"), "accent": Color("d8b870"), "skin": Color("9a9484"), "dark": Color("0e0c09")},
		"weapon": "sword", "accessories": ["crown"], "seed": 4300,
	},
	"ch4_normal_06": {
		"id": "ch4_normal_06", "name": "白灰猎犬", "chapter": 3, "tier": "normal",
		"archetype": "beast", "height": 1.3, "bulk": 1,
		"palette": {"cloth": Color("2a2822"), "metal": Color("6a6048"), "trim": Color("c7a66a"), "accent": Color("c7a66a"), "skin": Color("b8b2a2"), "dark": Color("0e0c09")},
		"weapon": "claw", "accessories": [], "seed": 4397,
	},
	"ch4_normal_07": {
		"id": "ch4_normal_07", "name": "无日御医", "chapter": 3, "tier": "normal",
		"archetype": "caster", "height": 1.69, "bulk": 0.94,
		"palette": {"cloth": Color("1a1814"), "metal": Color("7a6a40"), "trim": Color("9a8450"), "accent": Color("d8c090"), "skin": Color("a89c84"), "dark": Color("0e0c09")},
		"weapon": "staff", "accessories": ["mask"], "seed": 4494, "staff_top": "censer",
	},
	"ch4_normal_08": {
		"id": "ch4_normal_08", "name": "缄口传令官", "chapter": 3, "tier": "normal",
		"archetype": "humanoid", "height": 1.836, "bulk": 0.98,
		"palette": {"cloth": Color("26221c"), "metal": Color("8a7434"), "trim": Color("c7a66a"), "accent": Color("e0c888"), "skin": Color("9a927e"), "dark": Color("0e0c09")},
		"weapon": "banner", "accessories": ["mask", "cloak"], "seed": 4591,
	},
	"ch4_elite_09": {
		"id": "ch4_elite_09", "name": "黑金禁卫", "chapter": 3, "tier": "elite",
		"archetype": "knight", "height": 2.301, "bulk": 1.22,
		"palette": {"cloth": Color("12100c"), "metal": Color("a08040"), "trim": Color("c7a66a"), "accent": Color("e0c078"), "skin": Color("8a8270"), "dark": Color("0e0c09")},
		"weapon": "hammer", "accessories": ["shield"], "seed": 4688,
	},
	"ch4_elite_10": {
		"id": "ch4_elite_10", "name": "誓约刽子手", "chapter": 3, "tier": "elite",
		"archetype": "knight", "height": 2.379, "bulk": 1.18,
		"palette": {"cloth": Color("1a1612"), "metal": Color("6a5a34"), "trim": Color("a88a4a"), "accent": Color("d0a860"), "skin": Color("8a8272"), "dark": Color("0e0c09")},
		"weapon": "scythe", "accessories": ["hood"], "seed": 4785,
	},
	"ch4_elite_11": {
		"id": "ch4_elite_11", "name": "无昼摄政", "chapter": 3, "tier": "elite",
		"archetype": "sovereign", "height": 2.415, "bulk": 1.2,
		"palette": {"cloth": Color("14120e"), "metal": Color("9a7a3a"), "trim": Color("c7a66a"), "accent": Color("e8cc84"), "skin": Color("b0a488"), "dark": Color("0e0c09")},
		"weapon": "banner", "accessories": ["crown"], "seed": 4882,
	},
	"ch4_boss_12": {
		"id": "ch4_boss_12", "name": "无日之王", "chapter": 3, "tier": "boss",
		"archetype": "sovereign", "height": 3.36, "bulk": 1.32,
		"palette": {"cloth": Color("0e0c08"), "metal": Color("a8863c"), "trim": Color("c7a66a"), "accent": Color("f0d48c"), "skin": Color("b8ac90"), "dark": Color("0e0c09")},
		"weapon": "sword", "accessories": ["crown", "cloak"], "seed": 4979,
	},
	"ch4_boss_13": {
		"id": "ch4_boss_13", "name": "王座下的旧誓", "chapter": 3, "tier": "boss",
		"archetype": "wraith", "height": 2.775, "bulk": 1.26,
		"palette": {"cloth": Color("18140e"), "metal": Color("7a6636"), "trim": Color("b09050"), "accent": Color("d8bc7a"), "skin": Color("8a7e6a"), "dark": Color("0e0c09")},
		"weapon": "scythe", "accessories": ["chains", "crown"], "seed": 5076,
	},
	"ch1_bellsmith": {
		"id": "ch1_bellsmith", "name": "回响铸钟人", "chapter": 0, "tier": "normal",
		"archetype": "humanoid", "height": 1.8, "bulk": 1.04,
		"palette": {"cloth": Color("4b463c"), "metal": Color("8a6a44"), "trim": Color("8c8571"), "accent": Color("c8a866"), "skin": Color("9a8f78"), "dark": Color("1b211d")},
		"weapon": "hammer", "accessories": ["cloak"], "seed": 5152,
	},
	"ch2_armor_priest": {
		"id": "ch2_armor_priest", "name": "蚀盾司祭", "chapter": 1, "tier": "normal",
		"archetype": "knight", "height": 1.911, "bulk": 1.06,
		"palette": {"cloth": Color("4a2e2a"), "metal": Color("5f5040"), "trim": Color("8a6a4e"), "accent": Color("a88a5f"), "skin": Color("a89080"), "dark": Color("1f1416")},
		"weapon": "staff", "accessories": ["shield"], "seed": 5256, "staff_top": "censer",
	},
	"ch3_star_arbiter": {
		"id": "ch3_star_arbiter", "name": "错时裁星者", "chapter": 2, "tier": "normal",
		"archetype": "humanoid", "height": 1.836, "bulk": 1,
		"palette": {"cloth": Color("26324a"), "metal": Color("6f8190"), "trim": Color("8fa2b2"), "accent": Color("b0d4e8"), "skin": Color("8a98a8"), "dark": Color("10161f")},
		"weapon": "scythe", "accessories": ["mask"], "seed": 5360,
	},
	"ch4_oath_mender": {
		"id": "ch4_oath_mender", "name": "归誓缝卫", "chapter": 3, "tier": "normal",
		"archetype": "skeleton", "height": 1.72, "bulk": 1.05,
		"palette": {"cloth": Color("1c1a14"), "metal": Color("8a7434"), "trim": Color("a08a50"), "accent": Color("c8ae78"), "skin": Color("c0b8a0"), "dark": Color("0e0c09")},
		"weapon": "spear", "accessories": ["chains"], "seed": 5464,
	},
}

## 显式表优先；未知 id 用 definition 生成确定性兜底 spec，不返回空。
static func spec(enemy_id: String, definition: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = SPECS.get(enemy_id, {})
	if entry.is_empty():
		return _fallback(enemy_id, definition)
	var out: Dictionary = entry.duplicate(true)
	out["id"] = enemy_id
	if definition.has("name"):
		var display := String(definition["name"])
		if not display.is_empty():
			out["name"] = display
	if definition.has("chapter"):
		out["chapter"] = int(definition["chapter"])
	out["definition_id"] = String(definition.get("id", enemy_id))
	return out


static func has_form(enemy_id: String) -> bool:
	return SPECS.has(enemy_id)


static func all_ids() -> Array:
	return SPECS.keys()


## 未知 id 的兜底：按 definition 的章节基色 + 名字哈希抖动，保持确定性。
static func _fallback(enemy_id: String, definition: Dictionary) -> Dictionary:
	var chapter := int(definition.get("chapter", 0))
	if not CHAPTER_PALETTES.has(chapter):
		chapter = 0
	var palette: Dictionary = CHAPTER_PALETTES[chapter].duplicate(true)
	var seed_value: int = absi(hash(enemy_id))
	var name := String(definition.get("name", enemy_id))
	return {
		"id": enemy_id,
		"name": name,
		"archetype": "humanoid",
		"height": BASE_HEIGHTS["humanoid"] * (0.94 + float(seed_value % 13) * 0.01),
		"bulk": 0.94 + float(seed_value % 9) * 0.01,
		"palette": palette,
		"weapon": WEAPONS[seed_value % WEAPONS.size()],
		"accessories": [],
		"seed": seed_value % 100000,
		"chapter": chapter,
		"tier": String(definition.get("kind", "normal")),
		"definition_id": enemy_id,
	}
