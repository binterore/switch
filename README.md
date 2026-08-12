# BB Switch（macOS 菜单栏）

一个跑在 macOS 顶部菜单栏的 Agent 模型切换器：点击菜单栏图标弹出面板，点一下即可切换
Claude Code / Codex / OpenCode 使用的模型，风格参考 Clash 类菜单栏面板（窄边菜单 + 分组列表 + 勾选标记 + 子菜单展开）。

## 功能

- 菜单栏常驻图标，显示当前模型短名（如 `qwen3.7-plus`），悬停显示完整 agent + 模型。
- macOS 原生级联菜单：
  - 使用系统 `NSMenu` 绘制悬停、勾选、箭头、阴影与间距。
  - 按 `Agent → Provider → 模型` 展开，当前 Provider 与模型使用系统勾选。
  - 支持为每个 Agent 添加 Provider（名称、Base URL、SK、模型列表）；SK 保存在 macOS 钥匙串。
  - 选项开关：切换时自动备份、启动时显示面板。
  - 操作项：刷新配置、打开配置、退出。
  - 当前模型带系统勾选标记；底部状态栏实时反馈。
- 从 Agent 右侧菜单点击模型后立即切换并写回真实配置文件，切换前自动备份原文件
  （`settings.json.bak.<时间戳>` 等，与原文件同目录）。

## 支持的 Agent 与写入位置

| Agent | 配置文件 | 写入字段 |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` | `env.ANTHROPIC_MODEL` 及 `ANTHROPIC_DEFAULT_*_MODEL(_NAME)`，并把新模型加入 `availableModels` |
| Codex | `~/.codex/config.toml` | 顶层 `model = "..."`（仅替换顶层，不动 `[model_providers.*]`） |
| OpenCode | `~/.config/opencode/opencode.json` | `model` 字段 |

其它键值（API Key、Base URL、hooks、MCP 等）原样保留。

## 构建与运行

无需 Xcode，只要装了 Command Line Tools：

```bash
make build   # 编译 Universal 2 应用（Apple 芯片 + Intel，最低 macOS 12）
make package # 生成可发送的 build/BBSwitch-universal.zip
make run     # 打开 App（会出现在菜单栏，Dock 无图标）
make probe   # 打印当前检测到的 agent / 模型 / 配置路径，用于自检
make clean
```

发给其他人时请发送 `BBSwitch-universal.zip`，不要直接通过聊天工具发送裸 `.app` 目录。
当前构建使用本地临时签名；正式公开分发仍需 Apple Developer ID 签名并公证。

启动后点击菜单栏图标（⇄ 样式）即可切换模型。

## 代码结构

- `Sources/main.swift` — App 入口、菜单栏图标、弹窗控制、`--probe` 自检。
- `Sources/ConfigStore.swift` — 三个 agent 配置的读取 / 写入 / 备份 / 自定义模型。
- `Sources/NativeMenuController.swift` — 原生 macOS 级联菜单、Provider/模型选择与操作项。
- `Sources/ProviderStore.swift` — Provider 元数据与 macOS 钥匙串中的 SK 管理。
- `Resources/Info.plist` — `LSUIElement` 使 App 只驻留菜单栏。
- `Makefile` — swiftc 编译 + .app 打包 + 本地签名。

## 常见问题

- **切换后不生效**：请确认目标 agent 已退出重开（CLI 在启动时读取配置）。
- **没有某个 agent**：面板只显示检测到配置文件的 agent；未安装的 agent 会标注原因。
- **想支持更多 agent（如 Gemini CLI）**：在 `ConfigStore.swift` 增加一个 `readGemini()`
  和对应的 `writeGemini(model:)`，并在 `agents()` 里挂上即可；Gemini CLI 的模型走
  `~/.gemini/settings.json` 的 `model` 字段。

## 后续可做

- 开机自启（`SMAppService`）。
- 切换成功后的系统通知。
- Gemini CLI / Claude Desktop 支持。
- 每个 agent 独立的「模型别名」展示（把 `vip/qwen3.7-plus` 显示成友好名称）。
