"""Expedition items: market goods, temporary burdens, curses and purified rewards."""


def make_items(effect, describe):
    goods = [
        ("cinder", "余烬香囊", 40, [("start_block", 4)]),
        ("charm", "断钟护符", 50, [("start_strength", 1)]),
        ("bandage", "金线绷带", 50, [("combat_heal", 4)]),
        ("clover", "银叶草", 45, [("gold_bonus", 5)]),
        ("needle", "寻隙细针", 55, [("first_damage", 4)]),
        ("moss", "苔石护心", 60, [("turn_block", 2)]),
        ("ink", "毒藤墨瓶", 65, [("poison_bonus", 1)]),
        ("cup", "晨露盏", 55, [("turn_heal", 1)]),
        ("folio", "折页手记", 100, [("turn_draw", 1)]),
        ("lantern", "晨星提灯", 70, [("start_block", 6), ("gold_bonus", 2)]),
        ("coin", "长路古币", 65, [("gold_bonus", 8)]),
        ("quill", "乌银笔", 80, [("first_damage", 5), ("start_strength", 1)]),
        ("needlework", "缝命针线", 85, [("combat_heal", 5), ("turn_heal", 1)]),
        ("knot", "旅人结绳", 60, [("start_block", 4), ("turn_block", 1)]),
        ("bell", "扶风铃", 90, [("start_strength", 2)]),
        ("scale", "磐岩鳞片", 100, [("turn_block", 3)]),
        ("wax", "无烟松蜡", 80, [("turn_heal", 2)]),
        ("vial", "翠蛇玻瓶", 90, [("poison_bonus", 2)]),
        ("teeth", "战兽臼齿", 90, [("first_damage", 7)]),
        ("talisman", "报春木符", 85, [("combat_heal", 7)]),
        ("seal", "行商旧印", 100, [("gold_bonus", 10), ("start_block", 3)]),
        ("lens", "夜巡透镜", 110, [("turn_draw", 1), ("first_damage", 2)]),
        ("ribbon", "赤金发带", 100, [("start_strength", 1), ("turn_block", 2)]),
        ("feather", "白羽信物", 115, [("turn_draw", 1), ("combat_heal", 3)]),
    ]
    burdens = [
        ("sore", "沉重护臂", [("start_strength", -1)], 2, ""),
        ("haze", "迷路烟雾", [("turn_draw", -1)], 2, ""),
        ("tax", "滞留税印", [("gold_bonus", -6)], 3, "good_coin"),
        ("blunt", "蒙尘刃坠", [("first_damage", -3)], 3, "good_needle"),
    ]
    curses = [
        ("oath", "破誓锁链", [("start_strength", -2)], "elite_wins", 2, "赢下精英战斗", "破晓锁环", [("start_strength", 2), ("combat_heal", 5)]),
        ("veil", "昏睡面纱", [("turn_draw", -1)], "attacks_played", 15, "打出攻击牌", "苏醒面纱", [("turn_draw", 1), ("start_block", 5)]),
        ("purse", "贪欲钱袋", [("gold_bonus", -8)], "shop_gold", 100, "在商店实际消费金币", "施舍钱袋", [("gold_bonus", 10), ("turn_heal", 1)]),
        ("iron", "锈蚀砥石", [("first_damage", -4)], "cards_upgraded", 2, "在营地强化卡牌", "净火砥石", [("first_damage", 7), ("turn_block", 2)]),
    ]
    permanent = [
        ("shackles", "沉星镣铐", [("start_strength", -2)]),
        ("blindfold", "永夜眼罩", [("turn_draw", -1)]),
        ("debt", "无赦债契", [("gold_bonus", -10)]),
        ("blade", "折锋残刃", [("first_damage", -5)]),
    ]
    negative_text = {
        "start_strength": "开战时力量减少 {n}",
        "turn_draw": "每回合少抽 {n} 张牌",
        "gold_bonus": "每次战斗胜利少获得 {n} 金币",
        "first_damage": "每场战斗首段攻击基础伤害减少 {n}",
    }

    def entry(id, name, kind, modifiers, **meta):
        descriptions = [describe(op, value) if value > 0 else negative_text[op].format(n=-value) for op, value in modifiers]
        return {"id": id, "name": name, "kind": kind, "effects": [effect(op, value) for op, value in modifiers], "description": "；".join(text.rstrip("。") for text in descriptions) + "。", **meta}

    result = [entry(f"good_{key}", name, "positive", mods, price=price) for key, name, price, mods in goods]
    result.extend(entry(f"burden_{key}", name, "temporary", mods, duration=duration, transforms_to=target) for key, name, mods, duration, target in burdens)
    for key, name, mods, metric, goal, task, sacred_name, sacred_mods in curses:
        result.append(entry(f"curse_{key}", name, "curse", mods, task={"metric": metric, "goal": goal, "label": task}, transforms_to=f"sacred_{key}"))
        result.append(entry(f"sacred_{key}", sacred_name, "sacred", sacred_mods))
    result.extend(entry(f"permanent_{key}", name, "permanent", mods) for key, name, mods in permanent)
    return result
