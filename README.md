# 灰誓 · Grey Oath

《灰誓》是一款用 Godot 开发的中文单人暗黑奇幻卡牌冒险游戏。玩家选择旅者，在四章旅程中构筑牌组，判断敌人的行动意图，并通过交替打出攻击牌和技能牌积攒应变点数。

## 发布版本

当前版本 **0.2.3**，使用 Godot 4.7.2 stable 构建。Windows 与 macOS 使用同一份资源包。

| 平台 | 产物 | 运行环境 | 签名状态 |
| --- | --- | --- | --- |
| macOS | `灰誓-0.2.3-macOS.dmg`、`.zip` | universal；arm64 需 macOS 11.0+，x86_64 需 macOS 10.15+ | 临时（ad-hoc）签名，未做 Apple 公证 |
| Windows | `灰誓-0.2.3-Windows-x86_64.zip` | Windows 10/11，x86_64，支持 OpenGL 3.3 的显卡 | 未签名 |

macOS 首次打开如被系统拦截，可右键选择「打开」，或执行 `xattr -d com.apple.quarantine /Applications/灰誓.app`。Windows 首次运行可能触发 SmartScreen 提示，请先核对发布页提供的 SHA-256 再决定是否继续。

Windows 压缩包内的 `灰誓.exe` 与 `灰誓.pck` 必须保持在同一目录。签名的本地更新机制仅适用于 macOS 安装包；Windows 版本按设计不加载本地补丁，详见 [本地更新](docs/LOCAL_UPDATES.md)。

## 本地创意工坊

在主菜单选择「本地创意工坊」，可以编辑角色、怪物、道具、卡牌、天赋和流派起始牌组。每份作品可以直接启动一场独立战斗，试玩结果不计入正式旅程。通过「导出作品」将作品保存成 JSON 文件，再由其他玩家用「导入作品」加载。

## 从源码运行

项目使用 **Godot 4.7.2 stable**。在 Godot 项目管理器中导入 [project.godot](project.godot)，等待资源导入完成，再运行项目。仓库提供 macOS 启动脚本，以及 macOS、Windows 两个导出预设；导出前需安装与引擎版本一致的导出模板。

在 macOS 上也可以从项目根目录安装项目使用的编辑器，再通过启动脚本运行。

```sh
python3 scripts/setup_engine.py --editor-only
./启动灰誓.command
```

命令行打包会优先使用 `.tools` 内的固定编辑器，未安装时使用 `PATH` 中的 `godot`（版本必须是 4.7.2 stable）：

```sh
GREY_OATH_BUILD_DIR="$PWD/build/macOS" bash scripts/package_macos.sh
GREY_OATH_BUILD_DIR="$PWD/build/Windows" bash scripts/package_windows.sh
```

单个无窗口测试与完整回归矩阵：

```sh
godot --headless --path . --script tests/test_workshop.gd
bash scripts/run_tests.sh
```

## 许可证

《灰誓》贡献者有权授权的原创源代码使用 [MIT 许可证](LICENSE)，允许使用、修改和再分发，保留版权和许可声明即可。美术、音频、字体、模型和第三方内容的许可另见 [素材与第三方授权](ASSET-LICENSES.md)。
