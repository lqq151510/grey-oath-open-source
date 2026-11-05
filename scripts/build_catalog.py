#!/usr/bin/env python3
"""Build Grey Oath's deterministic, engine-compatible offline content catalog."""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
from spire_pools import additional_class_cards
from expedition_items import make_items
from original_roles import original_class_cards

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "catalog.json"
PLAYER_OPS = {
    "damage", "block", "draw", "energy", "heal", "self_damage", "poison",
    "weak", "vulnerable", "strength", "thorns", "regen", "soul", "summon",
    "mark", "lifesteal", "block_damage", "cleanse", "exhaust_hand", "next_energy",
    "stars", "forge", "fetch_blade", "minion", "osty_summon", "osty_attack", "osty_sacrifice", "doom", "soul_card", "shiv", "discard", "channel", "evoke", "dualcast", "orb_slots", "focus", "dexterity", "intangible", "frail", "exhaust_block", "exhaust_draw",
    "strength_each_turn", "retain_block", "shiv_damage", "poison_multiply", "discard_draw", "discard_energy", "soul_summon",
    "resonance", "resonant_damage", "resonant_block", "cinder", "ignite",
}
ENEMY_OPS = {
    "damage", "block", "heal", "poison", "weak", "vulnerable", "strength", "thorns",
    "charge_strike", "sunder", "echo_strike", "heal_ally",
}
RELIC_OPS = {
    "max_hp", "start_block", "start_strength", "turn_block", "turn_heal",
    "turn_draw", "first_damage", "combat_heal", "gold_bonus", "poison_bonus",
}


def effect(op: str, value: int, **kwargs) -> dict:
    return {"op": op, "value": value, **kwargs}


def damage(value: int, **kwargs) -> dict:
    return effect("damage", value, **kwargs)


def block(value: int) -> dict:
    return effect("block", value)


def spec(name: str, cost: int, *effects: dict, **options) -> dict:
    return {"name": name, "cost": cost, "effects": list(effects), **options}


def _scale_hint(item: dict) -> str:
    source = {
        "block": "当前格挡", "combo": "本回合打出的攻击牌数",
        "souls": "当前灵魂", "stars": "当前星辰", "blade": "锻造值",
        "missing_hp": "已损失生命", "poison": "目标的中毒层数",
    }[item["scale"]]
    return f"{source}越多，伤害越高"


def describe_effect(item: dict) -> str:
    """Use short player-facing wording without changing the effect rules."""
    op, value = item["op"], item["value"]
    amount = str(value)
    target = "所有敌人" if item.get("target") == "all" else "目标"
    recipient = "你" if item.get("target") == "self" else target

    if op == "stars":
        return f"获得{amount}点星辰，本场战斗内保留"
    if op == "forge":
        return f"锻造{amount}点：首次获得君王之剑，之后提升它的伤害"
    if op == "fetch_blade":
        return "把君王之剑从抽牌堆、弃牌堆或消耗堆拿回手牌；手牌满时不移动"
    if op == "minion":
        return "把其他手牌变成侍从（0费；打出后获得11点格挡并消耗）"
    if op == "osty_summon":
        return f"奥斯蒂增加{amount}点生命"
    if op == "osty_attack":
        text = f"奥斯蒂对{target}造成{amount}点伤害"
        if item.get("hits", 1) > 1:
            text += f"，连续攻击{item['hits']}次"
        return text + "（不受力量和虚弱影响；奥斯蒂需要存活）"
    if op == "osty_sacrifice":
        return "牺牲奥斯蒂，使它的生命归零"
    if op == "doom":
        turn_owner = "你的" if item.get("target") == "self" else "目标的"
        return f"{recipient}获得{amount}点灾厄：{turn_owner}回合结束时，灾厄达到剩余生命就会死亡；灾厄不会自动减少"
    if op == "soul_card":
        return f"把{amount}张灵魂加入手牌（0费；打出后抽2张牌并消耗，手牌满时放入弃牌堆）"
    if op == "shiv":
        return f"把{amount}张小刀加入手牌（0费；造成6点伤害后消耗，手牌满时放入弃牌堆）"
    if op == "discard":
        return f"选择并弃掉{amount}张手牌；机巧牌被这样弃掉时会免费打出"
    if op == "channel":
        orb = {"lightning": "闪电", "frost": "冰霜", "dark": "黑暗", "plasma": "等离子", "glass": "玻璃"}.get(item.get("orb"), "闪电")
        return f"生成{amount}颗{orb}球；球槽已满时，先激发最左边的球"
    if op == "evoke":
        return f"激发并移除最左边的{amount}颗充能球"
    if op == "dualcast":
        return f"移除最左边的充能球，并激发它{amount}次"
    if op == "orb_slots":
        return f"增加{amount}个球槽，最多10个"
    if op == "focus":
        return f"获得{amount}点集中，增强闪电、冰霜、黑暗和玻璃球；不影响等离子球"
    if op == "dexterity":
        return f"获得{amount}点敏捷；格挡牌额外获得等量格挡"
    if op == "intangible":
        return f"获得{amount}回合虚化：每次受到伤害最多损失1点生命"
    if op == "frail":
        return f"获得{amount}回合脆弱：格挡牌少获得25%格挡"
    if op == "exhaust_block":
        return f"本场战斗中，每消耗1张牌就获得{amount}点格挡"
    if op == "exhaust_draw":
        return f"本场战斗中，每消耗1张牌就抽{amount}张牌"
    if op == "strength_each_turn":
        return f"从下回合开始，每回合获得{amount}点力量"
    if op == "retain_block":
        return "本场战斗的格挡会保留到下回合"
    if op == "shiv_damage":
        return f"本场战斗中，小刀伤害增加{amount}点"
    if op == "poison_multiply":
        return f"把{target}的中毒层数变为{amount}倍；没有中毒时无效"
    if op == "discard_draw":
        return f"本场战斗中，每主动弃掉1张牌就抽{amount}张牌；回合末自动弃牌不触发"
    if op == "discard_energy":
        return f"本场战斗中，每主动弃掉1张牌就获得{amount}点能量；回合末自动弃牌不触发"
    if op == "soul_summon":
        return f"本场战斗中，每打出1张灵魂牌，奥斯蒂增加{amount}点生命"
    if op == "resonance":
        return f"获得{amount}点回响，最多6点"
    if op == "resonant_damage":
        return f"有3点以上回响时，消耗3点，对{target}追加{amount}点伤害"
    if op == "resonant_block":
        return f"有3点以上回响时，消耗3点并额外获得{amount}点格挡"
    if op == "cinder":
        return f"{target}增加{amount}层余烬，最多8层；不会自动消失"
    if op == "ignite":
        return f"引燃{target}身上的全部余烬，每层造成{amount}点伤害（受格挡影响）"
    if op in {"damage", "lifesteal", "block_damage"}:
        if item.get("scale"):
            text = f"对{target}造成{amount}点基础伤害（{_scale_hint(item)}）"
        elif op == "block_damage":
            text = f"对{target}造成{amount}点伤害，当前格挡也会加到伤害里"
        else:
            text = f"对{target}造成{amount}点伤害"
        if item.get("hits", 1) > 1:
            text += f"，连续攻击{item['hits']}次"
        if op == "lifesteal":
            text += "，并按实际造成的伤害回复生命"
        return text
    if op == "block":
        return f"获得{amount}点格挡"
    if op in {"poison", "weak", "vulnerable"}:
        state_name = {"poison": "中毒", "weak": "虚弱", "vulnerable": "易伤"}[op]
        if op == "poison":
            detail = "每回合开始时按层数受到伤害，之后减少1层"
        elif op == "weak":
            detail = "攻击伤害降低25%，每回合结束减少1层"
        else:
            detail = "受到攻击伤害增加50%，每回合结束减少1层"
        return f"{recipient}{state_name}{amount}层：{detail}"
    if op == "mark":
        mark_name = ["", "日", "月", "星"][value]
        return f"获得1枚{mark_name}印；集齐3枚后全部消耗，按最后一枚触发效果（日造成8点全体伤害、月获得12点格挡、星抽2张牌）"
    if op == "summon":
        return f"召唤灵体，持续3回合；每回合结束时对首个存活敌人造成{amount}点伤害（格挡可抵挡），最多3个；超出时替换剩余回合最少的灵体"
    if op == "cleanse":
        return "清除你身上的中毒、虚弱和易伤"
    if op == "exhaust_hand":
        return f"消耗其余所有手牌，然后抽{amount}张牌"
    if op == "draw":
        return f"抽{amount}张牌"
    if op == "energy":
        return f"获得{amount}点能量"
    if op == "heal":
        return f"回复{amount}点生命"
    if op == "self_damage":
        return f"失去{amount}点生命，无视格挡，可能致死"
    if op == "strength":
        return f"本场战斗中获得{amount}点力量"
    if op == "thorns":
        return f"本场战斗中获得{amount}点荆棘"
    if op == "regen":
        return f"获得{amount}层再生：回合开始时按层数回复生命，然后减少1层"
    if op == "soul":
        return f"获得{amount}点灵魂"
    if op == "next_energy":
        return f"下回合多获得{amount}点能量"
    raise ValueError(f"无法生成效果说明：{op}")


def describe_card(card: dict, upgraded: bool = False) -> str:
    effects = card["upgrade_effects"] if upgraded else card["effects"]
    parts = [describe_effect(item) for item in effects]
    if card.get("soul_cost", 0):
        parts.insert(0, f"打出时额外消耗{card['soul_cost']}点灵魂")
    if card.get("star_cost", 0):
        parts.insert(0, f"打出时消耗{card['star_cost']}点星辰")
    if card.get("sly"):
        parts.append("机巧：主动弃掉时免费打出；回合末自动弃牌不触发")
    if card.get("ethereal"):
        parts.append("回合结束时若还在手牌中，就会消耗")
    if card.get("retain"):
        parts.append("回合结束时保留在手牌")
    if card.get("type") == "power":
        parts.append("能力牌：效果持续到战斗结束；不会再次抽到，也不触发消耗效果")
    elif card.get("exhaust"):
        parts.append("消耗：打出后本场战斗不会再抽到")
    return "。".join(parts) + "。"


def upgrade_effects(effects: list[dict]) -> list[dict]:
    """Improve each beneficial component; never increase costs or change a mark's identity."""
    result = deepcopy(effects)
    improved = False
    for item in result:
        op, value = item["op"], item["value"]
        if op in {"damage", "block", "lifesteal", "block_damage", "heal"}:
            item["value"] += max(2 if item.get("hits", 1) > 1 else 5, (value + 1) // 2)
            improved = True
        elif op in {"poison", "weak", "vulnerable", "strength", "thorns", "regen", "soul", "summon", "draw", "exhaust_hand", "energy", "next_energy", "stars", "forge", "osty_summon", "osty_attack", "doom", "soul_card", "shiv", "focus", "dexterity", "exhaust_block", "exhaust_draw", "channel", "strength_each_turn", "shiv_damage", "discard_draw", "discard_energy", "soul_summon", "poison_multiply"}:
            item["value"] += max(1, value // 2)
            improved = True
        elif op in {"resonance", "cinder", "ignite", "resonant_damage", "resonant_block"}:
            item["value"] += 2 if op in {"resonant_damage", "resonant_block"} else 1
            improved = True
        elif op == "self_damage" and value > 1:
            item["value"] = max(1, value - 2)
            improved = True
        if item.get("scale"):
            item["factor"] = round(item.get("factor", 1) * 1.5, 2)
            improved = True
    if not improved:
        # A deferred hand choice must stay last: all other effects have already resolved.
        result.insert(len(result) - (1 if result[-1]["op"] == "discard" else 0), block(6))
    return result


def role_specs() -> dict[str, list[dict]]:
    e = effect
    return {
        "warden": [
            spec("残剑斩", 1, damage(6)),
            spec("守誓", 1, block(5)),
            spec("盾缘重击", 1, e("block_damage", 3)),
            spec("沉钟之壁", 1, block(8), e("weak", 1)),
            spec("铁肩", 1, block(7), damage(3)),
            spec("墓碑重压", 2, damage(14)),
            spec("缺口刺击", 1, damage(7), e("vulnerable", 1)),
            spec("双刃守备", 1, damage(3, hits=2), block(3)),
            spec("整顿阵线", 1, block(6), e("draw", 1)),
            spec("铁盔", 0, block(4)),
            spec("沉锋", 2, damage(10), e("weak", 2)),
            spec("古盾", 1, block(10)),
            spec("长阶横扫", 1, damage(5, target="all")),
            spec("誓言回响", 0, e("next_energy", 1), exhaust=True),
            spec("战壕", 2, block(16)),
            spec("护手反击", 1, block(4), e("block_damage", 2)),
            spec("盾击", 1, e("block_damage", 5)),
            spec("不退", 1, block(7), retain=True),
            spec("锈甲荆刺", 1, e("thorns", 3), type="power"),
            spec("守墓人的耐心", 1, block(5), e("next_energy", 1)),
            spec("重整誓约", 1, e("cleanse", 0), block(6)),
            spec("碎铁风暴", 2, damage(8, target="all"), block(5)),
            spec("荒原壁垒", 2, block(12), e("thorns", 2)),
            spec("沉钟反震", 2, e("block_damage", 3, target="all")),
            spec("誓剑磨砺", 1, e("strength", 2), type="power"),
            spec("残垣掩护", 1, block(9), e("weak", 1)),
            spec("旧日勋章", 0, e("draw", 2), exhaust=True),
            spec("背水守望", 1, e("block", 4, scale="missing_hp", factor=0.25)),
            spec("永夜堡垒", 3, block(24), e("thorns", 4), exhaust=True),
            spec("破晓誓斩", 2, e("block_damage", 12)),
            spec("王盾之重", 2, block(15), e("block_damage", 0)),
            spec("最后的守门人", 2, e("strength", 3), e("thorns", 3), type="power"),
            spec("铜钟短击", 1, damage(5, hits=2)),
            spec("斜盾", 0, block(5), retain=True),
            spec("回响石壁", 1, block(8), e("next_energy", 1), exhaust=True),
            spec("长夜行军", 1, block(6), e("draw", 2)),
            spec("断誓者审判", 2, damage(12), e("vulnerable", 2)),
            spec("碎盾誓火", 2, e("block_damage", 8), e("weak", 2)),
            spec("失名要塞", 2, block(18), e("draw", 1)),
            spec("铁雨", 2, damage(4, hits=3, target="all")),
            spec("石心", 1, e("thorns", 5), type="power"),
            spec("古王的盾墙", 3, block(28), retain=True),
            spec("余烬誓剑", 3, e("block_damage", 18), exhaust=True),
            spec("灰誓不灭", 2, block(12), e("strength", 4), type="power"),
        ],
        "ranger": [
            spec("暮箭", 1, damage(6)),
            spec("林影", 1, block(5)),
            spec("毒羽", 1, damage(4), e("poison", 3)),
            spec("寻迹", 0, e("draw", 2), exhaust=True),
            spec("双羽", 1, damage(3, hits=2)),
            spec("短弓快射", 0, damage(3)),
            spec("蛇牙", 1, damage(5), e("poison", 2)),
            spec("伏草", 1, block(7), e("draw", 1)),
            spec("枯藤绊索", 1, e("weak", 2), block(4)),
            spec("淬毒箭头", 1, e("poison", 5)),
            spec("追射", 1, damage(4, scale="combo", factor=2)),
            spec("落羽", 0, block(4)),
            spec("穿林", 1, damage(7), e("draw", 1)),
            spec("散箭", 1, damage(4, target="all")),
            spec("猎兽标记", 0, e("vulnerable", 1)),
            spec("退入夜色", 1, block(9)),
            spec("刺藤", 1, e("poison", 3), e("weak", 1)),
            spec("磨箭", 1, e("strength", 1), e("draw", 1), type="power"),
            spec("毒雾", 2, e("poison", 4, target="all")),
            spec("三重弦响", 1, damage(3, hits=3)),
            spec("窒息箭", 1, damage(4, scale="poison", factor=1)),
            spec("回环步", 1, block(6), e("draw", 2)),
            spec("伏猎", 1, damage(8), retain=True),
            spec("黑翎", 2, damage(10), e("poison", 4)),
            spec("再上弦", 0, e("energy", 1), e("draw", 1), exhaust=True),
            spec("荆路", 1, block(8), e("thorns", 2)),
            spec("分岔箭", 2, damage(5, hits=2, target="all")),
            spec("解毒叶", 1, e("cleanse", 0), e("draw", 1)),
            spec("百步追魂", 2, damage(8, scale="combo", factor=4)),
            spec("雾林葬礼", 2, e("poison", 7, target="all"), exhaust=True),
            spec("无声猎季", 1, e("strength", 3), type="power"),
            spec("夜雨齐射", 3, damage(5, hits=4, target="all"), exhaust=True),
            spec("余弦", 0, damage(4), exhaust=True),
            spec("绿蚀", 1, e("poison", 4), e("draw", 1)),
            spec("掠影", 1, block(6), damage(5)),
            spec("飞羽换位", 1, damage(4, hits=2), e("draw", 1)),
            spec("毒沼潜行", 1, block(8), e("poison", 3)),
            spec("月下弓弦", 0, e("next_energy", 2), exhaust=True),
            spec("断喉箭", 2, damage(9, scale="poison", factor=1.5)),
            spec("群鸦落", 2, damage(7, target="all"), e("weak", 1, target="all")),
            spec("隐林步法", 0, block(7), e("draw", 1), exhaust=True),
            spec("毒王之吻", 2, e("poison", 12), exhaust=True),
            spec("长夜连星", 2, damage(4, hits=5), exhaust=True),
            spec("最后一箭", 3, damage(15, scale="combo", factor=5), retain=True),
        ],
        "medium": [
            spec("魂火", 1, damage(6)),
            spec("薄幕", 1, block(5)),
            spec("引魂灯", 1, e("soul", 2), block(3)),
            spec("唤回亡影", 1, e("summon", 3)),
            spec("残魂弹", 1, damage(5, scale="souls", factor=1)),
            spec("灯影护身", 1, e("block", 5, scale="souls", factor=1)),
            spec("渡口低语", 0, e("soul", 1)),
            spec("寒灵", 1, damage(5), e("weak", 1)),
            spec("冥烛", 1, e("soul", 2), e("draw", 1)),
            spec("纸甲", 1, block(8)),
            spec("墓尘", 1, damage(5, target="all")),
            spec("借来的手", 1, e("summon", 4)),
            spec("听魂", 1, e("draw", 2), e("soul", 1)),
            spec("魂链", 1, damage(7), e("vulnerable", 1)),
            spec("静默灯火", 0, block(4)),
            spec("亡者馈赠", 1, e("soul", 4)),
            spec("长眠咒", 1, e("weak", 2), e("soul", 1)),
            spec("归途", 1, block(6), e("draw", 1)),
            spec("荒冢守卫", 2, e("summon", 5), block(6)),
            spec("魂焰洪流", 2, damage(7, scale="souls", factor=2), soul_cost=2),
            spec("灵幕", 1, e("block", 7, scale="souls", factor=1.5), soul_cost=1),
            spec("三途回声", 1, e("soul", 3), e("draw", 1)),
            spec("旧友", 2, e("summon", 4), e("summon", 4)),
            spec("摆渡费", 0, e("energy", 1), soul_cost=2, exhaust=True),
            spec("黄泉薄雾", 1, e("weak", 1, target="all"), block(5)),
            spec("灵火锻身", 1, e("strength", 2), soul_cost=2, type="power"),
            spec("忘川净流", 1, e("cleanse", 0), e("soul", 2)),
            spec("封魂匣", 1, e("soul", 3), retain=True),
            spec("百魂夜行", 3, e("summon", 6), e("summon", 6), e("summon", 6), exhaust=True),
            spec("渡魂者审判", 2, damage(9, target="all", scale="souls", factor=1.5), soul_cost=3),
            spec("彼岸之门", 2, e("soul", 7), e("draw", 2), exhaust=True),
            spec("无名者归来", 2, e("summon", 9), soul_cost=3),
            spec("魂砂", 0, e("soul", 2), exhaust=True),
            spec("送别", 1, damage(6), e("soul", 2)),
            spec("夜渡", 1, block(7), e("soul", 2)),
            spec("灯尽魂生", 1, e("exhaust_hand", 3), e("soul", 2)),
            spec("魂刺", 1, damage(3, hits=2, scale="souls", factor=0.5)),
            spec("荒魂守望", 1, e("summon", 5), soul_cost=1),
            spec("冥河倒影", 2, e("block", 12, scale="souls", factor=1)),
            spec("永别之歌", 2, damage(12), e("weak", 2), e("soul", 2)),
            spec("纸船远去", 0, e("draw", 2), soul_cost=2),
            spec("万魂灯", 2, e("soul", 10), exhaust=True),
            spec("故人列阵", 3, e("summon", 8), e("summon", 8), soul_cost=4),
            spec("彼岸焚城", 3, damage(12, target="all", scale="souls", factor=2), soul_cost=4, exhaust=True),
        ],
        "arcanist": [
            spec("微星", 1, damage(6)),
            spec("星纱", 1, block(5)),
            spec("日轮刻印", 1, damage(5), e("mark", 1)),
            spec("月相刻印", 1, block(5), e("mark", 2)),
            spec("启明星", 1, e("draw", 1), e("mark", 3)),
            spec("焦日", 1, damage(8), e("mark", 1)),
            spec("半月", 1, block(8), e("mark", 2)),
            spec("星图残页", 0, e("mark", 3)),
            spec("流星屑", 1, damage(3, hits=2)),
            spec("无光观测", 1, e("draw", 2)),
            spec("日蚀", 1, e("weak", 1), e("mark", 1)),
            spec("月蚀", 1, e("vulnerable", 1), e("mark", 2)),
            spec("引力井", 1, damage(5, target="all")),
            spec("玻璃星盘", 0, block(4)),
            spec("预兆", 1, block(5), e("next_energy", 1)),
            spec("日火", 2, damage(14), e("mark", 1)),
            spec("寒月", 1, block(6), e("weak", 1)),
            spec("碎星拾遗", 1, e("draw", 1), block(4), e("mark", 3)),
            spec("双日", 2, damage(8), e("mark", 1), e("mark", 1)),
            spec("双月", 2, block(10), e("mark", 2), e("mark", 2)),
            spec("双星", 1, e("mark", 3), e("mark", 3), exhaust=True),
            spec("失星学说", 1, e("strength", 2), type="power"),
            spec("星轨切割", 2, damage(5, hits=3)),
            spec("昼夜更替", 1, e("mark", 1), e("mark", 2), block(3)),
            spec("群星归位", 1, e("mark", 2), e("mark", 3), e("draw", 1)),
            spec("穹顶净空", 1, e("cleanse", 0), e("mark", 3)),
            spec("流光储藏", 0, e("next_energy", 2), exhaust=True),
            spec("星界屏障", 2, block(15), e("mark", 2)),
            spec("白昼终章", 2, e("mark", 1), e("mark", 1), e("mark", 1), damage(8, target="all")),
            spec("长夜月冠", 2, e("mark", 2), e("mark", 2), e("mark", 2), block(8)),
            spec("最后的星座", 1, e("mark", 3), e("mark", 3), e("mark", 3), exhaust=True),
            spec("天穹坠落", 3, damage(24, target="all"), exhaust=True),
            spec("晨光刻度", 0, e("mark", 1), exhaust=True),
            spec("暮光刻度", 0, e("mark", 2), exhaust=True),
            spec("陨石火", 1, damage(10)),
            spec("月面裂隙", 1, block(7), e("mark", 3)),
            spec("逆行星", 1, damage(7), e("mark", 2)),
            spec("黄道余辉", 1, e("draw", 2), e("mark", 1)),
            spec("恒星燃烧", 2, damage(10, target="all"), e("mark", 1)),
            spec("银海", 2, block(13), e("mark", 2), e("mark", 3)),
            spec("九曜笔记", 1, e("draw", 3), exhaust=True),
            spec("赤日归冕", 3, damage(20), e("mark", 1), e("mark", 1)),
            spec("永夜观星者", 2, block(9), e("mark", 3), e("mark", 3)),
            spec("万象归寂", 3, damage(16, target="all"), e("mark", 1), e("mark", 2), e("mark", 3), exhaust=True),
        ],
        "sister": [
            spec("戒尺", 1, damage(6)),
            spec("祷衣", 1, block(5)),
            spec("血烛", 0, e("self_damage", 2), e("energy", 1), exhaust=True),
            spec("怜悯之刃", 1, e("lifesteal", 5)),
            spec("荆棘祷告", 1, e("self_damage", 2), block(10)),
            spec("赎罪击", 1, damage(6, scale="missing_hp", factor=0.2)),
            spec("赤线", 1, e("self_damage", 2), damage(11)),
            spec("静祷", 1, block(8)),
            spec("微光圣餐", 1, e("heal", 5), exhaust=True),
            spec("破戒", 1, damage(7), e("weak", 1)),
            spec("血书", 0, e("self_damage", 3), e("draw", 2)),
            spec("尖刺圣环", 1, e("thorns", 3), type="power"),
            spec("灯芯未熄", 0, block(4)),
            spec("清洗圣痕", 1, e("cleanse", 0), block(4)),
            spec("赤誓横扫", 1, damage(5, target="all")),
            spec("痛楚回响", 1, e("self_damage", 2), damage(4, hits=2)),
            spec("布带包扎", 1, block(6), e("draw", 1)),
            spec("血色余温", 1, e("lifesteal", 7)),
            spec("残损圣像", 1, e("self_damage", 3), e("strength", 3), type="power"),
            spec("荆棘修行", 2, block(12), e("thorns", 2)),
            spec("伤口颂歌", 1, e("block", 5, scale="missing_hp", factor=0.3)),
            spec("血焰", 2, e("self_damage", 4), damage(12, target="all")),
            spec("宽恕", 1, e("heal", 8), e("cleanse", 0), exhaust=True),
            spec("苦修之夜", 0, e("self_damage", 3), e("next_energy", 2), exhaust=True),
            spec("圣痕之刃", 2, damage(10, scale="missing_hp", factor=0.35)),
            spec("无声布道", 1, e("weak", 2, target="all")),
            spec("余烬圣油", 1, e("regen", 3), exhaust=True),
            spec("红纱", 1, block(10), retain=True),
            spec("最后的圣餐", 2, e("heal", 15), exhaust=True),
            spec("血月赦令", 3, e("lifesteal", 10, target="all"), exhaust=True),
            spec("殉道之光", 2, e("self_damage", 6), e("strength", 5), type="power"),
            spec("赤誓审判", 3, damage(15, scale="missing_hp", factor=0.5)),
            spec("绷带结", 0, block(5)),
            spec("小小献祭", 0, e("self_damage", 2), damage(6)),
            spec("血印祷词", 1, e("self_damage", 2), e("draw", 3)),
            spec("荆冠", 1, e("self_damage", 2), e("thorns", 5), type="power"),
            spec("还愿", 1, e("lifesteal", 8), exhaust=True),
            spec("孤灯守夜", 1, block(7), e("regen", 2), exhaust=True),
            spec("痛觉启示", 1, e("self_damage", 3), damage(8, scale="missing_hp", factor=0.25)),
            spec("修女的怜悯", 2, e("lifesteal", 12), e("weak", 1)),
            spec("朱砂结界", 2, block(17), e("thorns", 2)),
            spec("无罪之血", 1, e("self_damage", 4), e("energy", 2), e("draw", 2), exhaust=True),
            spec("红莲圣咏", 3, e("self_damage", 5), damage(22, target="all"), exhaust=True),
            spec("此身即烛", 2, e("self_damage", 3), block(18), e("regen", 4), exhaust=True),
        ],
        "neutral": [
            spec("投石", 0, damage(3)),
            spec("急救布", 1, e("heal", 4), exhaust=True),
            spec("旅人盾", 1, block(7)),
            spec("破风", 1, damage(8)),
            spec("翻找行囊", 1, e("draw", 2)),
            spec("沙尘", 0, e("weak", 1), exhaust=True),
            spec("燧火", 1, damage(4, target="all")),
            spec("稳步", 1, block(5), e("draw", 1)),
            spec("铁钉", 0, damage(2), e("vulnerable", 1), exhaust=True),
            spec("收拢心神", 0, e("next_energy", 1), exhaust=True),
            spec("清泉", 1, e("cleanse", 0), e("draw", 1)),
            spec("余力", 0, e("energy", 1), exhaust=True),
            spec("孤注", 1, e("exhaust_hand", 4)),
            spec("破甲锤", 2, damage(12), e("vulnerable", 2)),
            spec("宿营布", 1, block(10), retain=True),
            spec("旧时代勇气", 1, e("strength", 2), type="power"),
            spec("不灭火种", 2, e("regen", 4), exhaust=True),
            spec("旅途终点", 3, damage(24), exhaust=True),
            spec("碎瓶", 1, damage(5), e("poison", 2)),
            spec("短憩", 1, block(6), e("next_energy", 1)),
            spec("石雨", 2, damage(8, target="all")),
            spec("旧歌", 0, e("draw", 2), exhaust=True),
            spec("利齿挂坠", 1, e("thorns", 3), type="power"),
            spec("紧急包扎", 1, e("heal", 8), exhaust=True),
            spec("余烬突刺", 2, damage(6, hits=3)),
            spec("漫长归途", 2, block(14), e("draw", 1)),
            spec("燃尽行囊", 0, e("exhaust_hand", 5), exhaust=True),
            spec("破晓灯火", 1, e("energy", 2), exhaust=True),
            spec("无名英雄", 2, e("strength", 3), block(8), type="power"),
            spec("灰烬中的誓言", 3, damage(16, target="all"), block(12), exhaust=True),
        ],
    }


def spire_class_specs() -> dict[str, list[dict]]:
    e = effect
    pools = {
        "warden": [
            spec("铁甲·重斩", 1, damage(8)), spec("铁甲·坚守", 1, block(7)),
            spec("铁甲·破甲", 2, damage(12), e("vulnerable", 2)), spec("铁甲·战意", 1, e("strength", 3), type="power"),
            spec("铁甲·燃血", 0, e("self_damage", 3), e("energy", 2), exhaust=True),
            spec("铁甲·燎原", 1, damage(7, target="all")), spec("铁甲·壁垒", 1, block(12), e("draw", 1)),
            spec("铁甲·无痛", 1, e("exhaust_block", 4), type="power"), spec("铁甲·拥暗", 2, e("exhaust_draw", 1), type="power"),
            spec("铁甲·焚手", 1, e("exhaust_hand", 4)), spec("铁甲·噬血", 2, e("lifesteal", 12)),
            spec("铁甲·盾击", 1, e("block_damage", 3)), spec("铁甲·狂怒", 1, damage(5, hits=3)),
            spec("铁甲·背水", 2, damage(10, scale="missing_hp", factor=0.5)),
        ],
        "ranger": [
            spec("猎手·突刺", 1, damage(7)), spec("猎手·闪避", 1, block(7)),
            spec("猎手·断筋", 0, damage(5), e("weak", 1)), spec("猎手·生存", 1, block(12), e("discard", 1)),
            spec("猎手·刀舞", 1, e("shiv", 3)), spec("猎手·毒刃", 1, damage(6), e("poison", 4)),
            spec("猎手·杂技", 1, e("draw", 3), e("discard", 1)), spec("猎手·机巧", 1, damage(10), sly=True),
            spec("猎手·毒雾", 1, e("poison", 5, target="all")), spec("猎手·灵动", 1, e("dexterity", 3), type="power"),
            spec("猎手·幽影", 2, e("intangible", 1), exhaust=True), spec("猎手·准备", 0, e("draw", 2), e("discard", 1)),
            spec("猎手·回旋", 1, block(8), e("draw", 1), sly=True), spec("猎手·旋刃", 1, damage(3, hits=2, target="all")),
        ],
        "sister": [
            spec("机体·冲击", 1, damage(8)), spec("机体·护壁", 1, block(7)),
            spec("机体·充电", 1, e("channel", 1, orb="lightning")), spec("机体·双放", 1, e("dualcast", 2)),
            spec("机体·寒流", 1, block(5), e("channel", 1, orb="frost")),
            spec("机体·集中", 1, e("focus", 2), type="power"), spec("机体·拓展", 1, e("orb_slots", 2), type="power"),
            spec("机体·暗涌", 1, e("channel", 1, orb="dark")), spec("机体·等离", 2, e("channel", 1, orb="plasma")),
            spec("机体·折射", 1, damage(4, target="all"), e("channel", 1, orb="glass")),
            spec("机体·冰阵", 2, e("channel", 3, orb="frost")), spec("机体·雷阵", 2, e("channel", 3, orb="lightning")),
            spec("机体·释放", 0, e("evoke", 1), e("draw", 1)), spec("机体·检索", 0, e("draw", 2)),
        ],
        "arcanist": [
            spec("储君·敕击", 1, damage(8)), spec("储君·王卫", 1, block(7)),
            spec("储君·落星", 0, damage(11), e("weak", 1), e("vulnerable", 1), star_cost=2),
            spec("储君·铸誓", 1, e("stars", 2), e("forge", 6)),
            spec("储君·聚星", 1, e("stars", 5)), spec("储君·唤剑", 1, e("forge", 8), e("fetch_blade", 1)),
            spec("储君·侍从", 1, e("minion", 1), exhaust=True), spec("储君·星幕", 0, block(15), star_cost=2),
            spec("储君·彗落", 1, damage(8, scale="stars", factor=2), star_cost=1),
            spec("储君·帝威", 1, e("strength", 3), type="power"), spec("储君·锤炼", 2, e("forge", 16)),
            spec("储君·银河", 1, damage(12, target="all"), star_cost=2),
            spec("储君·观星", 0, e("draw", 2), star_cost=1), spec("储君·御令", 1, block(8), e("stars", 3)),
        ],
        "medium": [
            spec("契约·刺骨", 1, damage(8)), spec("契约·守墓", 1, block(8)),
            spec("契约·护卫", 1, e("osty_summon", 6), e("osty_attack", 10)), spec("契约·咒印", 1, e("doom", 10)),
            spec("契约·唤魂", 1, e("soul_card", 2)), spec("契约·骨潮", 1, e("osty_summon", 10)),
            spec("契约·扼握", 2, e("osty_attack", 22)),
            spec("契约·骨爆", 1, e("osty_attack", 12, target="all"), block(10), e("osty_sacrifice", 1)),
            spec("契约·凋零", 2, e("doom", 16, target="all")), spec("契约·魂壁", 1, block(10), e("soul_card", 1)),
            spec("契约·冥息", 1, e("draw", 3), ethereal=True), spec("契约·预兆", 0, e("doom", 5)),
            spec("契约·复生", 2, e("osty_summon", 18), e("draw", 1)),
            spec("契约·薄暮", 2, e("intangible", 1), e("soul_card", 1), exhaust=True),
        ],
    }
    additions = additional_class_cards(spec, effect, damage, block)
    result = {"neutral": role_specs()["neutral"]}
    for role, templates in pools.items():
        # Keep the existing introductory IDs; new cards deepen the same systems.
        advanced = sorted(additions[role], key=card_complexity)
        result[role] = templates + advanced
        for index, recipe in enumerate(result[role]):
            recipe["complexity"] = card_complexity(recipe)
            recipe["min_chapter"] = 0 if index < 18 else 1 if index < 28 else 2 if index < 36 else 3
    for role, recipes in original_class_cards(spec, effect, damage, block).items():
        result[role] = recipes
        for index, recipe in enumerate(recipes):
            recipe["complexity"] = card_complexity(recipe)
            recipe["min_chapter"] = 0 if index < 10 else 1 if index < 15 else 2 if index < 18 else 3
    return result


def card_complexity(card: dict) -> int:
    """Teaching order: actions, then resources/scaling, then persistent triggers."""
    triggers = {"exhaust_block", "exhaust_draw", "strength_each_turn", "retain_block", "shiv_damage", "discard_draw", "discard_energy", "soul_summon"}
    resources = {"stars", "forge", "fetch_blade", "minion", "osty_summon", "osty_attack", "osty_sacrifice", "doom", "soul_card", "shiv", "discard", "channel", "evoke", "dualcast", "poison_multiply", "resonance", "resonant_damage", "resonant_block", "cinder", "ignite"}
    return len(card["effects"]) + sum(2 * (item["op"] in triggers) + (item["op"] in resources) + bool(item.get("scale")) + (item.get("hits", 1) > 1) for item in card["effects"]) + bool(card.get("sly")) + bool(card.get("star_cost"))


def make_tokens() -> list[dict]:
    tokens = [
        {"id":"token_shiv", "name":"小刀", "cost":0, "type":"attack", "effects":[damage(6)], "exhaust":True},
        {"id":"token_soul", "name":"灵魂", "cost":0, "type":"skill", "effects":[effect("draw",2)], "exhaust":True},
        {"id":"token_blade", "name":"君王之剑", "cost":2, "type":"attack", "effects":[damage(10,scale="blade",factor=1)], "retain":True},
        {"id":"token_minion", "name":"侍从献身", "cost":0, "type":"skill", "effects":[block(11)], "exhaust":True},
    ]
    for card in tokens:
        card.update(role="neutral", rarity="common", unlock_wins=0)
        card["upgrade_effects"] = upgrade_effects(card["effects"])
        card["description"] = describe_card(card)
        card["upgrade_description"] = describe_card(card, True)
    return tokens


def make_cards(starter_ids: set[str]) -> list[dict]:
    cards = []
    for role, recipes in spire_class_specs().items():
        for index, recipe in enumerate(recipes):
            card = deepcopy(recipe)
            card_id = f"{role}_{index + 1:02d}"
            if role == "neutral":
                unlock = 0 if index < 18 else [3, 8, 15, 25][(index - 18) // 3]
                rarity = "common" if index < 10 else "uncommon" if index < 15 else "rare"
            elif role in {"bellscribe", "ashlamper"}:
                unlock = 0
                rarity = "starter" if index < 4 else "common" if index < 10 else "uncommon" if index < 16 else "rare"
            else:
                unlock = 0 if index < 32 else [5, 10, 20, 30][(index - 32) // 3]
                rarity = "starter" if index < 4 else "common" if index < 18 else "uncommon" if index < 28 else "rare"
            card.update({
                "id": card_id, "role": role, "rarity": rarity,
                "unlock_wins": unlock,
                "art": f"res://assets/art/cards/{card_id}.webp" if card_id in starter_ids else "",
                "type": card.get("type", "attack" if any(x["op"] in {"damage", "lifesteal", "block_damage", "osty_attack", "resonant_damage", "ignite"} for x in card["effects"]) else "skill"),
                "upgrade_effects": upgrade_effects(card["effects"]),
            })
            card["description"] = describe_card(card)
            card["upgrade_description"] = describe_card(card, upgraded=True)
            cards.append(card)
    return cards


CHAPTERS = [
    {"id": "sunken_bells", "name": "沉钟墓园", "subtitle": "钟声沉入尘土", "description": "最后一次葬礼早已结束，墓园里的钟却仍在地下敲响。沿着残碑，找出守门人的誓言。", "color": "#a99c7d"},
    {"id": "thorn_abbey", "name": "荆棘修道院", "subtitle": "祈祷长出尖刺", "description": "修道院以痛苦延续永昼。无人记得，最初的祈祷究竟献给谁。", "color": "#ad706b"},
    {"id": "lost_star", "name": "失星观测所", "subtitle": "星图上空无一物", "description": "天文学家仍在测量已经消失的星辰。每一架望远镜，都指向同一个黑暗。", "color": "#8c9eb7"},
    {"id": "sunless_court", "name": "无日王庭", "subtitle": "王冠等待最后的黎明", "description": "无日之王将整个国度留在誓约里。穿过空旷王庭，让长夜有一个结局。", "color": "#c7a66a"},
]


def make_roles() -> list[dict]:
    definitions = [
        ("warden", "铁甲战士", "力量与连击", "力量会让攻击更疼；打出消耗牌还能换来格挡或抽牌。战斗结束时，初始遗物会回复8点生命。", "#c76b57", 90, 0),
        ("ranger", "寂静猎手", "中毒、小刀与弃牌", "用中毒慢慢削弱敌人，靠免费小刀攻击，也能主动弃牌触发机巧牌。第一回合多抽2张牌。", "#8eae82", 80, 0),
        ("sister", "故障机器人", "充能球攻防", "开战有3个球位和1颗闪电球。不同球会自动攻击、提供格挡或能量；集中能增强大多数球。", "#79b9d6", 85, 0),
        ("arcanist", "储君", "星辰与君王之剑", "每场战斗开始有3点星辰。花星辰强化卡牌，也能锻造君王之剑，让它在本场战斗中越来越强。", "#d7b65c", 85, 0),
        ("medium", "亡灵契约师", "奥斯蒂与灾厄", "奥斯蒂帮你承受攻击并出手。给敌人累积灾厄，等灾厄达到它剩余生命时就能收割；灵魂牌可以免费抽牌。", "#b59acb", 80, 0),
        ("bellscribe", "回响抄钟人", "回响攻防", "开战有2点回响。攻击和格挡都能积攒回响；攒够3点后，可换成额外攻击或格挡。", "#73c5b5", 82, 0),
        ("ashlamper", "灰脉巡灯人", "余烬与引燃", "先给敌人加余烬，再引燃造成伤害。可以集中烧一个危险敌人，也能同时攻击多个敌人。", "#db9162", 84, 0),
    ]
    return [{
        "id": role, "name": name, "title": title, "description": description, "color": color,
        "max_hp": hp, "unlock_wins": unlock, "starter_relic": f"starter_{role}",
        "starter_cards": [f"{role}_01"] * 4 + [f"{role}_02"] * 4 + [f"{role}_03", f"{role}_04"],
    } for role, name, title, description, color, hp, unlock in definitions]


def make_enemies() -> list[dict]:
    names = [
        ["失名掘墓人", "枯骨哨兵", "墓灯蛾", "沉泥尸", "守碑犬", "锈钟小卒", "灰鸦", "遗忘的送葬者", "负钟巨人", "无面守墓人", "缠链骑士", "沉钟看守", "墓园的无名王"],
        ["刺冠侍者", "蜡泪修士", "荆鞭苦行者", "破袍颂唱者", "圣烛兽", "藤甲门卫", "血墨抄经人", "赎罪信徒", "执刑圣像", "荆棘审判官", "缄默双刃", "无泪院长", "盛放的圣母像"],
        ["碎星学徒", "盲眼观测者", "铜镜傀儡", "星尘蠕虫", "错时信使", "月蚀残影", "黄道卫兵", "引力侍从", "陨铁巨像", "失星大导师", "逆行巡猎者", "无星占卜师", "破碎天穹之眼"],
        ["空铠近卫", "王庭执灯人", "枯荣侍女", "旧誓书记官", "断冠骑士", "白灰猎犬", "无日御医", "缄口传令官", "黑金禁卫", "誓约刽子手", "无昼摄政", "无日之王", "王座下的旧誓"],
    ]
    enemies = []
    for chapter, chapter_names in enumerate(names):
        for index, name in enumerate(chapter_names):
            kind = "normal" if index < 8 else "elite" if index < 11 else "boss"
            if kind == "normal":
                hp = 23 + chapter * 10 + (index % 4) * 3
                attack = 5 + chapter * 2 + index % 2
                patterns = [
                    [[damage(attack)], [block(4 + chapter * 2)], [damage(attack + 2)]],
                    [[damage(attack)], [block(5 + chapter)], [damage(attack - 2, hits=2)]],
                    [[effect("weak", 1)], [damage(attack + 1)], [damage(attack)]],
                    [[block(3 + chapter)], [effect("poison", 2 + chapter)], [damage(attack)]],
                    [[damage(attack - 2, hits=2)], [effect("vulnerable", 1)], [damage(attack)]],
                    [[damage(attack)], [effect("strength", 1)], [damage(attack + 1)]],
                    [[damage(attack)], [effect("heal", 3 + chapter)], [damage(attack + 2)]],
                    [[block(4 + chapter)], [damage(attack + 2)], [effect("weak", 1), damage(attack - 2)]],
                ][index]
            elif kind == "elite":
                hp = 55 + chapter * 20 + (index - 8) * 6
                attack = 10 + chapter * 3
                patterns = [
                    [[damage(attack)], [block(8 + chapter * 2), effect("strength", 1)], [damage(attack + 4)]],
                    [[effect("weak", 1), block(6)], [damage(attack - 3, hits=2)], [effect("poison", 3 + chapter)]],
                    [[damage(attack - 4, hits=2)], [effect("vulnerable", 1)], [damage(attack + 5)]],
                ][index - 8]
            else:
                hp = 100 + chapter * 40 + (index - 11) * 12
                attack = 12 + chapter * 4
                patterns = [
                    [[damage(attack)], [block(12 + chapter * 3), effect("strength", 1)], [damage(attack - 6, hits=3)], [effect("weak", 1), damage(attack - 4)]],
                    [[block(10 + chapter * 3)], [effect("vulnerable", 1)], [damage(attack + 7)], [damage(attack - 4), effect("poison", 3 + chapter)]],
                ][index - 11]
            enemies.append({
                "id": f"ch{chapter + 1}_{kind}_{index + 1:02d}", "name": name,
                "chapter": chapter, "kind": kind, "hp": hp, "color": CHAPTERS[chapter]["color"],
                "description": f"徘徊于{CHAPTERS[chapter]['name']}的{ {'normal': '敌人', 'elite': '精英', 'boss': '首领'}[kind]}。行动按显示的意图依次循环。",
                "pattern": [{"intent": f"第 {step + 1} 式", "effects": sequence} for step, sequence in enumerate(patterns)],
            })
    specialists = [
        ("ch1_bellsmith", "回响铸钟人", 27,
         "预告钟槌时，只要让它损失生命就能打断；中毒也有效，打在格挡上无效。",
         [("拾槌", [block(4)]), ("钟槌", [effect("charge_strike", 13)]), ("清炉", [damage(6)])]),
        ("ch2_armor_priest", "蚀盾司祭", 35,
         "蚀盾刺先移除至多 4 点格挡，再造成攻击伤害；可多叠格挡或施加虚弱。",
         [("蚀盾刺", [effect("sunder", 4), damage(7)]), ("盐甲祷词", [block(6)]), ("盐灰", [damage(8)])]),
        ("ch3_star_arbiter", "错时裁星者", 45,
         "预告错时裁决时，本回合每打出超过第 3 张的牌，攻击伤害基础值 +2，最多 +6。",
         [("错时裁决", [effect("echo_strike", 9)]), ("重排星盘", [block(8)]), ("偏移星轨", [damage(10)])]),
        ("ch4_oath_mender", "归誓缝卫", 54,
         "缝誓会治疗损失生命最多的存活同伴；没有受伤同伴时，它给自己加 7 点格挡。",
         [("缝誓", [effect("heal_ally", 11, fallback_block=7)]), ("裁线", [damage(12)]), ("穿针", [effect("weak", 1), damage(9)])]),
    ]
    for chapter, (enemy_id, name, hp, hint, pattern) in enumerate(specialists):
        enemies.append({
            "id": enemy_id, "name": name, "chapter": chapter, "kind": "normal", "hp": hp,
            "color": CHAPTERS[chapter]["color"], "description": hint, "mechanic_hint": hint,
            "pattern": [{"intent": intent, "effects": effects} for intent, effects in pattern],
        })
    return enemies


def relic_description(op: str, value: int) -> str:
    return {
        "max_hp": f"获得时，最大生命与当前生命各增加 {value} 点。",
        "start_block": f"每场战斗首回合额外获得 {value} 点格挡。",
        "start_strength": f"每场战斗开始获得 {value} 点力量。",
        "turn_block": f"每回合开始获得 {value} 点格挡。",
        "turn_heal": f"每回合开始回复 {value} 点生命。",
        "turn_draw": f"每回合开始额外抽 {value} 张牌。",
        "first_damage": f"每场战斗第一次伤害类卡牌或药水效果的首段命中额外增加 {value} 点基础伤害（仍受力量、虚弱与易伤影响）。",
        "combat_heal": f"每场战斗胜利后回复 {value} 点生命。",
        "gold_bonus": f"每场战斗胜利后额外获得 {value} 金币。",
        "poison_bonus": f"每次通过卡牌或药水给敌人施毒时，额外施加 {value} 层中毒。",
    }[op]


def make_relics() -> list[dict]:
    starters = [
        ("warden", "沉钟碎片", "combat_heal", 8),
        ("ranger", "暮林羽饰", "first_damage", 3),
        ("medium", "引魂灯芯", "start_block", 6),
        ("arcanist", "失星罗盘", "start_block", 6),
        ("sister", "雷光核心", "start_block", 4),
        ("bellscribe", "听潮钟舌", "start_block", 5),
        ("ashlamper", "未熄的风灯", "first_damage", 4),
    ]
    relics = [{"id": f"starter_{role}", "name": name, "role": role, "rarity": "starter", "effect": effect(op, value), "description": relic_description(op, value)} for role, name, op, value in starters]
    groups = [
        ("max_hp", [5, 7, 9, 11, 14, 18], ["温热骨片", "干枯橡果", "旅人骨笛", "生命琥珀", "古树心核", "不朽之种"]),
        ("start_block", [5, 7, 9, 12, 16, 20], ["生锈护符", "折翼门环", "旧式胸针", "门卫铁印", "黎明盾徽", "王庭封锁印"]),
        ("start_strength", [1, 1, 2, 2, 3, 4], ["狼齿", "磨损砥石", "破军铜章", "赤铁指环", "英雄断刃", "旧王战旗"]),
        ("turn_block", [1, 1, 2, 2, 3, 4], ["石壳", "灰陶护符", "铁丝环", "星砂甲片", "守夜石", "不动山心"]),
        ("turn_heal", [1, 1, 1, 2, 2], ["露珠瓶", "未枯苔藓", "温灯芯", "不尽泉石", "长生烛"]),
        ("turn_draw", [1, 1, 1, 1, 2], ["旧书签", "旅人眼镜", "乌鸦羽笔", "观星透镜", "先知残卷"]),
        ("first_damage", [3, 5, 7, 10, 14], ["燧石齿", "银箭簇", "初鸣铃", "破晓枪尖", "天火残核"]),
        ("combat_heal", [2, 3, 4, 6, 8], ["净水石", "回乡丝带", "缝补针", "圣餐银杯", "归途灯盏"]),
        ("gold_bonus", [3, 4, 6, 8, 12], ["缺角铜币", "行商算盘", "旧王钱袋", "镀金枯叶", "财富遗诏"]),
        ("poison_bonus", [1, 1, 2, 2, 3, 4], ["青蛇鳞", "苦杏仁", "毒菇孢子", "幽绿琉璃", "毒王蜕皮", "永腐之核"]),
    ]
    for op, values, names in groups:
        for index, (value, name) in enumerate(zip(values, names, strict=True)):
            rarity = "common" if index < 2 else "uncommon" if index < 3 else "rare" if index < 4 else "boss"
            relics.append({"id": f"relic_{op}_{index + 1}", "name": name, "description": relic_description(op, value), "rarity": rarity, "role": "neutral", "effect": effect(op, value)})
    return relics


def make_potions() -> list[dict]:
    recipes = [
        ("ember", "余烬瓶", [damage(15)]),
        ("fire", "焰雨瓶", [damage(9, target="all")]),
        ("guard", "铁肤药", [block(12)]),
        ("strength", "烈心药", [effect("strength", 2)]),
        ("heal", "凝露药", [effect("heal", 12)]),
        ("poison", "苦绿毒液", [effect("poison", 6)]),
        ("weak", "灰雾瓶", [effect("weak", 2, target="all")]),
        ("vulnerable", "蚀甲酸", [effect("vulnerable", 3)]),
        ("energy", "醒神药", [effect("energy", 2)]),
        ("draw", "清明露", [effect("draw", 3)]),
        ("cleanse", "净化盐水", [effect("cleanse", 0), block(4)]),
        ("regen", "再生灵液", [effect("regen", 4)]),
        ("thorns", "荆刺药", [effect("thorns", 4)]),
        ("soul", "幽魂瓶", [effect("soul", 5), effect("summon", 3)]),
        ("stars", "三相星露", [effect("mark", 1), effect("mark", 2), effect("mark", 3)]),
    ]
    return [{"id": f"potion_{slug}", "name": name, "description": "。".join(describe_effect(item) for item in effects) + "。仅战斗中使用。", "effects": effects} for slug, name, effects in recipes]


def choice(label: str, **changes) -> dict:
    parts = []
    for key, amount in changes.items():
        if key in {"hp", "gold", "max_hp"}:
            parts.append(f"{'增加' if amount >= 0 else '失去'} {abs(amount)} { {'hp': '生命', 'gold': '金币', 'max_hp': '最大生命（不同时增加当前生命）'}[key]}")
        elif key == "heal":
            parts.append(f"回复 {amount} 点生命")
        elif key == "card":
            parts.append(f"获得卡牌「{CARD_NAMES[amount]}」")
        elif key == "relic":
            parts.append(f"获得遗物「{RELIC_NAMES[amount]}」：{RELIC_TEXT[amount]}")
    return {"label": label, "description": "；".join(parts) + "。" if parts else "不产生任何变化。", **changes}


CARD_NAMES: dict[str, str] = {}
RELIC_NAMES: dict[str, str] = {}
RELIC_TEXT: dict[str, str] = {}


def make_events() -> list[dict]:
    scenes = [
        [("未敲响的钟", "墓穴里传来低低的金属声。一口小钟被锁在死者胸前。"), ("枯井", "井底倒映着白昼。系在井沿的绳索尚能承重。"), ("守墓人的午餐", "没有人的石凳上，摆着半块面包和一碗温汤。"), ("失名墓碑", "碑上没有姓名，只有一枚被手掌磨亮的铜币。"), ("送葬队伍", "黑伞无声地经过。队伍末尾给你留了一个位置。"), ("骨匠小摊", "骨匠将零碎战利品摆在布上，等你以伤换取。"), ("墓灯", "一盏灯快熄了，旁边的刻痕写着：别让他迷路。"), ("纸鸦来信", "纸鸦落在肩上，信里只有一句尚未说出的告别。"), ("铁门背后", "锈门后有货物碰撞的声音。门缝里伸出一只戴手套的手。"), ("第一次誓言", "古老石壁上，你看见许多被人反复描摹的誓词。")],
        [("带刺的圣杯", "圣杯盛满清水，杯沿却缠着细密的荆棘。"), ("缄默告解室", "木墙后有人等待你的秘密，只收取一滴鲜血。"), ("面包与圣灰", "厨房里留着一块硬面包，旁边是一小袋圣灰。"), ("燃尽的烛台", "烛台下压着钱袋。蜡油已经凝成一只伸出的手。"), ("苦行者队列", "修士们绕着大厅行走，用伤痕记下每一圈距离。"), ("圣像修补匠", "修补匠向你展示一枚金属碎片，说它曾经听懂祈祷。"), ("封闭花园", "铁栅栏内，花朵沿着剑伤盛开。"), ("被删掉的经文", "你从灰堆中找到几页异端文字。墨迹还未干透。"), ("晚祷集市", "走廊里响起银币声，只有钟响前这里才允许交易。"), ("最后一页祷词", "经书的最后一页没有神的名字，只写着一个人的承诺。")],
        [("逆走的日晷", "影子向着光源挪动。晷盘中间嵌着一颗温热石头。"), ("空白星图", "星图并不空白，你的呼吸使看不见的线条逐渐浮现。"), ("观测者茶歇", "桌上茶水还温着，守夜人的椅子却覆满星尘。"), ("坠落的铜星", "黄铜星球仪裂开，散落的零件仍在绕着中心转动。"), ("失时走廊", "走廊尽头有人回头看你，与你有着相同的步伐。"), ("陨铁雕刻师", "雕刻师的工具发出冷光，他正在雕出不存在的星座。"), ("望远镜的眼泪", "镜片积着一滴水，映出很久以后的夜空。"), ("被抹去的论文", "纸页说，失去的星辰从未消失，只是有人闭上了眼睛。"), ("零点交易", "一名戴钟面具的商人坚持在指针重合时成交。"), ("最后一颗星", "穹顶有一道窄缝。你终于看见一点光，正在缓缓熄灭。")],
        [("空王冠", "王冠静静躺在台阶上，内圈刻着第一位守誓者的名字。"), ("没有水的倒影", "地面干燥，却映出另一个站得更直的你。"), ("停摆的宴席", "酒杯举在半空，食物依然温热，座椅上空无一人。"), ("旧王的税箱", "箱中整齐码放着早已不再流通的银币。"), ("无声朝会", "石柱的影子像一群臣子，在王座前低下头。"), ("王庭珍宝官", "珍宝官失去了眼睛，却能准确叫出每一道伤口的名字。"), ("裂缝里的草", "黑色大理石间冒出一丛嫩草。这里不该有生命。"), ("未颁布的赦令", "赦令上没有盖印。纸角写着一条隐秘的离城路线。"), ("最后的行商", "商人正在收拾行囊。他愿意把最后一件货物留下。"), ("王座前的誓词", "最后一道门没有锁。门上刻着：决定你愿为谁走进去。")],
    ]
    events = []
    for chapter, entries in enumerate(scenes):
        for index, (name, description) in enumerate(entries):
            hp_cost = 5 + chapter * 2
            gold_gain = 24 + chapter * 8
            options = [
                [choice("以血唤醒", hp=-hp_cost, relic="relic_first_damage_1"), choice("留下祭品", gold=-16, heal=12), choice("安静离开")],
                [choice("伸手探寻", hp=-hp_cost, max_hp=5), choice("闭目休息", heal=6), choice("继续赶路")],
                [choice("买下食物", gold=-15, heal=18), choice("献出一枚钱币", gold=-5, heal=7), choice("留给后来者")],
                [choice("取走遗物", relic="relic_gold_bonus_1", hp=-hp_cost), choice("只取钱币", gold=12), choice("不惊动它")],
                [choice("以伤换路", hp=-hp_cost, gold=gold_gain), choice("支付引路费", gold=-20, max_hp=5), choice("自行绕路")],
                [choice("换取护符", hp=-hp_cost - 2, relic="relic_start_block_2"), choice("买下石壳", gold=-40, relic="relic_turn_block_1"), choice("告别匠人")],
                [choice("留下余力", hp=-4, max_hp=7), choice("补给灯火", gold=-12, heal=10), choice("守望片刻")],
                [choice("带走知识", card="neutral_13"), choice("以金币换医药", gold=-14, card="neutral_02"), choice("把它留在原处")],
                [choice("购买珍宝", gold=-65, relic="relic_start_strength_3"), choice("购买旅人盾", gold=-20, card="neutral_03"), choice("离开集市")],
                [choice("承受旧誓", hp=-hp_cost, card="neutral_18"), choice("接过微光", card="neutral_17"), choice("遵循自己的道路")],
            ][index]
            events.append({"id": f"event_ch{chapter + 1}_{index + 1:02d}", "name": name, "chapter": chapter, "description": description, "choices": options})
    return events


def build() -> dict:
    roles = make_roles()
    starter_ids = {card_id for role in roles for card_id in role["starter_cards"]}
    cards = make_cards(starter_ids)
    relics = make_relics()
    CARD_NAMES.update({card["id"]: card["name"] for card in cards})
    RELIC_NAMES.update({relic["id"]: relic["name"] for relic in relics})
    RELIC_TEXT.update({relic["id"]: relic["description"] for relic in relics})
    return {"version": 1, "roles": roles, "cards": cards, "tokens": make_tokens(), "enemies": make_enemies(), "relics": relics, "items": make_items(effect, relic_description), "potions": make_potions(), "events": make_events(), "chapters": deepcopy(CHAPTERS)}


def validate(catalog: dict) -> dict[str, int]:
    expected = {"roles": 7, "cards": 290, "enemies": 56, "relics": 62, "items": 40, "potions": 15, "events": 40, "chapters": 4}
    for key, count in expected.items():
        entries = catalog[key]
        assert len(entries) == count, (key, len(entries), count)
        assert len({entry["id"] for entry in entries}) == count, f"duplicate {key} IDs"
        assert len({entry["name"] for entry in entries}) == count, f"duplicate {key} names"
    cards = {card["id"]: card for card in catalog["cards"]}
    relics = {relic["id"]: relic for relic in catalog["relics"]}
    items = {item["id"]: item for item in catalog["items"]}
    assert Counter(item["kind"] for item in items.values()) == {"positive": 24, "temporary": 4, "curse": 4, "sacred": 4, "permanent": 4}
    for item in items.values():
        negative = item["kind"] in {"temporary", "curse", "permanent"}
        assert item["effects"] and all(entry["op"] in RELIC_OPS - {"max_hp"} and (entry["value"] < 0 if negative else entry["value"] > 0) for entry in item["effects"])
        if item["kind"] == "positive":
            assert item["price"] > 0
        if item["kind"] == "temporary":
            assert item["duration"] > 0 and (not item["transforms_to"] or items[item["transforms_to"]]["kind"] == "positive")
        if item["kind"] == "curse":
            assert item["task"]["goal"] > 0 and item["task"]["metric"] in {"elite_wins", "attacks_played", "shop_gold", "cards_upgraded"}
            assert items[item["transforms_to"]]["kind"] == "sacred"
    assert {item["transforms_to"] for item in items.values() if item["kind"] == "curse"} == {item["id"] for item in items.values() if item["kind"] == "sacred"}
    role_ids = {role["id"] for role in catalog["roles"]}
    original_roles = {"bellscribe", "ashlamper"}
    assert role_ids == {"warden", "ranger", "medium", "arcanist", "sister"} | original_roles
    assert all(role["unlock_wins"] == 0 for role in catalog["roles"])
    for role in catalog["roles"]:
        pool = [card for card in cards.values() if card["role"] == role["id"]]
        original = role["id"] in original_roles
        count = 20 if original else 44
        assert len(pool) == count
        fingerprints = [json.dumps({key: card.get(key) for key in ("cost", "type", "effects", "exhaust", "retain", "sly", "ethereal", "star_cost")}, sort_keys=True, ensure_ascii=False) for card in pool]
        assert len(set(fingerprints)) == count, f"duplicate gameplay recipes for {role['id']}"
        chapter_counts = {0: 10, 1: 5, 2: 3, 3: 2} if original else {0: 18, 1: 10, 2: 8, 3: 8}
        assert Counter(card["min_chapter"] for card in pool) == chapter_counts
        assert any(card["min_chapter"] == 0 and card["rarity"] != "starter" and any(entry.get("target") == "all" and entry["op"] in {"damage", "lifesteal", "block_damage", "osty_attack"} for entry in card["effects"]) for card in pool), f"no opening group attack for {role['id']}"
        unlock_counts = {0: 20} if original else {0: 32, 5: 3, 10: 3, 20: 3, 30: 3}
        assert Counter(card["unlock_wins"] for card in pool) == unlock_counts
        assert Counter(card["rarity"] for card in pool)["starter"] == 4
        assert len(role["starter_cards"]) == 10
        assert sorted(Counter(role["starter_cards"]).values()) == [1, 1, 4, 4]
        assert all(cards[cid]["role"] == role["id"] and cards[cid]["rarity"] == "starter" for cid in role["starter_cards"])
        assert relics[role["starter_relic"]]["rarity"] == "starter"
    neutrals = [card for card in cards.values() if card["role"] == "neutral"]
    assert Counter(card["unlock_wins"] for card in neutrals) == {0: 18, 3: 3, 8: 3, 15: 3, 25: 3}
    for card in cards.values():
        assert card["role"] in role_ids | {"neutral"}
        assert card["type"] in {"attack", "skill", "power"} and 0 <= card["cost"] <= 3
        assert card["effects"] and card["upgrade_effects"] != card["effects"]
        assert card["description"] == describe_card(card)
        assert card["upgrade_description"] == describe_card(card, True)
        for effects in (card["effects"], card["upgrade_effects"]):
            assert all(item["op"] != "discard" for item in effects[:-1]), f"{card['id']}: active choice must be the last effect"
        for item in card["effects"] + card["upgrade_effects"]:
            assert item["op"] in PLAYER_OPS and item["value"] >= 0
            assert item.get("target", "enemy") in {"self", "enemy", "all"}
            assert item.get("scale", "") in {"", "block", "combo", "souls", "missing_hp", "poison", "stars", "blade"}
            assert 1 <= item.get("hits", 1) <= 30
            if item["op"] == "mark":
                assert item["value"] in {1, 2, 3}
    for chapter in range(4):
        enemies = [enemy for enemy in catalog["enemies"] if enemy["chapter"] == chapter]
        assert Counter(enemy["kind"] for enemy in enemies) == {"normal": 9, "elite": 3, "boss": 2}
        assert sum(bool(enemy.get("mechanic_hint")) for enemy in enemies) == 1
        assert sum(event["chapter"] == chapter for event in catalog["events"]) == 10
    for enemy in catalog["enemies"]:
        assert enemy["hp"] > 0 and enemy["pattern"]
        for move in enemy["pattern"]:
            assert move["effects"]
            assert all(item["op"] in ENEMY_OPS and item["value"] > 0 for item in move["effects"])
    for relic in relics.values():
        assert relic["effect"]["op"] in RELIC_OPS
        assert relic["description"] == relic_description(relic["effect"]["op"], relic["effect"]["value"])
    assert Counter(relic["rarity"] for relic in relics.values())["starter"] == len(role_ids)
    for potion in catalog["potions"]:
        assert all(item["op"] in PLAYER_OPS for item in potion["effects"])
    for event in catalog["events"]:
        assert 1 <= len(event["choices"]) <= 3
        for option in event["choices"]:
            assert option.get("card", next(iter(cards))) in cards
            assert option.get("relic", next(iter(relics))) in relics
            if "card" in option:
                assert cards[option["card"]]["unlock_wins"] == 0, "events must not bypass progression unlocks"
            assert option["description"] == choice(option["label"], **{key: value for key, value in option.items() if key not in {"label", "description"}})["description"]
    return expected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate generated content and verify the saved catalog matches without writing")
    args = parser.parse_args()
    catalog = build()
    counts = validate(catalog)
    rendered = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        assert OUTPUT.read_text(encoding="utf-8") == rendered, "catalog.json differs: run scripts/build_catalog.py"
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(rendered, encoding="utf-8")
    print(json.dumps({"ok": True, "mode": "check" if args.check else "build", "counts": counts}, ensure_ascii=False))


if __name__ == "__main__":
    main()
