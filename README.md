# 灰誓 · Grey Oath

《灰誓》是一款用 Godot 开发的中文单人暗黑奇幻卡牌冒险游戏。玩家选择旅者，在四章旅程中构筑牌组，判断敌人的行动意图，并通过交替打出攻击牌和技能牌积攒应变点数。

## 本地创意工坊

在主菜单选择「本地创意工坊」，可以编辑角色、怪物、道具、卡牌、天赋和流派起始牌组。每份作品可以直接启动一场独立战斗，试玩结果不计入正式旅程。通过「导出作品」将作品保存成 JSON 文件，再由其他玩家用「导入作品」加载。

## 从源码运行

项目使用 **Godot 4.7.2 stable**。在 Godot 项目管理器中导入 [project.godot](project.godot)，等待资源导入完成，再运行项目。此源码预览附带 macOS 启动脚本。它省略了待核对授权的画面、音频和模型，运行时会看到默认显示。

在 macOS 上也可以从项目根目录安装项目使用的编辑器，再通过启动脚本运行。

```sh
python3 scripts/setup_engine.py --editor-only
./启动灰誓.command
```

工坊的无窗口测试使用同一个本地 Godot 编辑器。

```sh
.tools/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_workshop.gd
```

## 许可证

《灰誓》贡献者有权授权的原创源代码使用 [MIT 许可证](LICENSE)，允许使用、修改和再分发，保留版权和许可声明即可。美术、音频、字体、模型和第三方内容的许可另见 [素材与第三方授权](ASSET-LICENSES.md)。
