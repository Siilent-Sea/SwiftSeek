# 下一阶段任务书

当前活跃轨道：`everything-dockless-hardening`

当前阶段：`N3`
阶段名：设置页 Dock 模式修复与用户自救路径

## 交给 Claude 的 N3 任务

N2 已通过 Codex 验收。N3 处理用户被旧 DB / 测试状态 / 手动设置污染时的自救路径：用户应能在设置页看懂当前 Dock 为什么出现，并能一键恢复菜单栏模式，而不是手工改 SQLite。

### 必须完成

- 设置页常规区域增加 Dock 状态说明，至少展示：
  - 用户意图：显示 Dock / 隐藏 Dock（来自 `dock_icon_visible`）。
  - 当前有效 activation policy：`.regular` / `.accessory` / 其他。
  - 当前包体 `Info.plist LSUIElement`：`true` / `false` / 未声明 / 无法探测。
  - 当前 bundle path / executable path，方便识别 stale bundle。
- 提供“一键恢复菜单栏模式 / 隐藏 Dock”操作：
  - 将 `dock_icon_visible` 明确设回 false。
  - 不静默改其他 DB 字段。
  - 操作后给出清楚的重启/退出提示。
- 如果当前 `dock_icon_visible=1`，文案必须明确说明 Dock 出现来自用户设置 / 旧 DB 状态，不把它描述为 package 回归。
- 如果当前包体是 `--dock-app`（`LSUIElement=false`），文案必须区分“包体允许 Dock”与“runtime 用户设置要求 Dock”。
- N1 Diagnostics 与设置页显示的字段名/含义要保持一致，避免用户复制诊断和 UI 看到两套说法。
- 更新 `docs/install.md`、`docs/known_issues.md`、`docs/manual_test.md` 或现有手测文档中关于设置页自救路径的说明。

### 禁止事项

- 不做 Developer ID 签名、公证、DMG、auto updater。
- 不移除 `dock_icon_visible` 设置。
- 不静默强改用户 DB。
- 不改变 N2 package mode 策略。
- 不引入 Finder 插件、QSpace 私有 API、URL scheme 猜测或任何文件管理器集成新 scope。
- 不声称最终 release gate 已完成；真实 `.app` 全组合手测仍留给 N4。

### 验收方式

- `swift build --disable-sandbox`
- `swift run --disable-sandbox SwiftSeekSmokeTest`
- Smoke 必须覆盖：
  - fresh DB 默认 `dock_icon_visible=false`。
  - reset helper / 一键恢复操作把 `dock_icon_visible` 设回 false。
  - `dock_icon_visible=1` 时设置页状态模型能显示“用户希望显示 Dock”。
  - `LSUIElement=true/false/nil` 的显示模型与 N1 Diagnostics 语义一致。
- 手测至少覆盖：
  - 默认 agent 包 + fresh DB：设置页显示隐藏 Dock / agent 形态。
  - 旧 DB `dock_icon_visible=1`：设置页解释 Dock 来自用户设置，并可一键恢复。
  - 点击恢复后退出重启：设置保持 false，菜单栏入口仍可用。
  - `--dock-app` 包：设置页能解释包体模式，不误导用户。
