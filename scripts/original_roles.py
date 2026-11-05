"""Card recipes for Grey Oath's original travelers, ordered by chapter gate."""


def original_class_cards(spec, effect, damage, block):
    def resonance(value):
        return effect("resonance", value)

    def ring(value, **target):
        return effect("resonant_damage", value, **target)

    def shelter(value):
        return effect("resonant_block", value)

    def cinder(value, **target):
        return effect("cinder", value, **target)

    def ignite(value, **target):
        return effect("ignite", value, **target)

    return {
        "bellscribe": [
            spec("拓音", 1, damage(7), resonance(1)),
            spec("抱钟", 1, block(6), resonance(1)),
            spec("敲碑", 1, damage(6), ring(8)),
            spec("空廊余音", 1, block(6), shelter(7)),
            spec("试钟", 0, resonance(2), exhaust=True),
            spec("廊下钟雨", 1, damage(4, target="all"), ring(5, target="all")),
            spec("抄录刻痕", 1, resonance(2), effect("draw", 2)),
            spec("听壁", 1, block(7), resonance(2)),
            spec("沉响", 2, damage(12), ring(14)),
            spec("错拍", 1, damage(4, hits=2), resonance(1)),
            spec("长阶护音", 2, block(10), shelter(12), retain=True),
            spec("续弦", 0, resonance(1), effect("draw", 1)),
            spec("断梁鸣", 1, damage(6), ring(7), effect("weak", 1)),
            spec("拓夜成册", 2, resonance(4), block(10), effect("draw", 1)),
            spec("合钟", 2, damage(5, target="all"), ring(9, target="all")),
            spec("闭钟庭", 1, block(7), shelter(10), resonance(1)),
            spec("迟归的钟声", 2, damage(11), ring(18), retain=True),
            spec("回廊藏声", 0, resonance(3), effect("next_energy", 1), exhaust=True),
            spec("钟群齐鸣", 3, damage(9, target="all"), ring(14, target="all"), ring(9, target="all")),
            spec("无响碑文", 2, block(12), shelter(9), shelter(9), effect("draw", 1)),
        ],
        "ashlamper": [
            spec("灯针", 1, damage(7), cinder(2)),
            spec("护风", 1, block(7)),
            spec("点烬", 1, ignite(2), damage(7)),
            spec("分火", 1, block(6), cinder(3)),
            spec("拂灰", 0, cinder(2), effect("draw", 1), exhaust=True),
            spec("走灯", 1, damage(4, target="all"), cinder(1, target="all")),
            spec("回焰", 1, ignite(2), block(7)),
            spec("灯油瓶", 1, cinder(4), effect("weak", 1)),
            spec("热针", 1, damage(3, hits=2), cinder(2)),
            spec("灯下潮", 2, damage(5, target="all"), ignite(2, target="all")),
            spec("裁焰", 1, ignite(3), effect("draw", 1)),
            spec("拢烟", 1, block(7), cinder(2, target="all")),
            spec("烧尽旧芯", 0, ignite(2), effect("next_energy", 1), exhaust=True),
            spec("贴烛", 2, damage(10), cinder(6)),
            spec("提灯过隙", 1, block(9), cinder(1), effect("draw", 1)),
            spec("燎纹", 1, cinder(2), ignite(3), retain=True),
            spec("风井火舌", 2, ignite(3, target="all"), block(10)),
            spec("归灯路", 1, cinder(3, target="all"), effect("draw", 2), exhaust=True),
            spec("烛街火线", 3, cinder(3, target="all"), ignite(4, target="all"), exhaust=True),
            spec("灰脉尽燃", 2, ignite(5), damage(8), effect("heal", 3), exhaust=True),
        ],
    }
