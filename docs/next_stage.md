# 下一阶段任务书：L2

当前活跃轨道：`everything-menubar-agent`

当前阶段：`L2`

前置状态：L1 已通过 Codex 验收。L1 采用 `NSApp.setActivationPolicy(.accessory)` 作为默认 no Dock 方案，`Info.plist` 继续保持 `LSUIElement=false`，菜单栏 status item 是默认主入口。

任务性质：交给 Claude 执行的实现任务书。L2 只做 Dock 显示开关与激活策略稳定化，不做菜单栏复杂状态、不做单实例、不做签名/公证/DMG。

## L2 目标

给用户一个清晰、可持久化的方式恢复 Dock 图标，并把隐藏 Dock / 显示 Dock 两种模式下的搜索、设置、退出、热键和前置行为验证到可交付。

## 必须做

1. 增加设置项
   - 在设置存储中新增 Dock 可见性或菜单栏模式设置，例如 `dock_icon_visible` 或 `menubar_agent_mode`。
   - 默认值必须保持 L1 行为：默认隐藏 Dock。
   - 读写失败时必须有保守 fallback，不允许导致 app 无入口。

2. 设置页增加开关
   - 在设置窗口中加入"显示 Dock 图标"或"菜单栏模式"开关。
   - 文案要直接说明影响：开启后 SwiftSeek 会出现在 Dock / Command+Tab；关闭后只保留菜单栏入口。
   - 如果切换需要重启生效，UI 必须明确提示；不要假装实时成功。

3. 激活策略收口
   - 明确并实现切换策略：
     - 如果 `.regular` / `.accessory` 实时切换在当前代码路径稳定，则允许实时切换；
     - 如果真实行为不稳定，则保存设置并提示重启生效。
   - 启动早期根据设置决定 `NSApp.setActivationPolicy(...)`。
   - 保持 `LSUIElement=false`，除非你同时更新脚本、文档和验收说明并解释为什么要换方案。

4. 两种模式入口验证
   - no Dock 模式：菜单栏搜索、菜单栏设置、菜单栏退出、全局热键必须可用。
   - Dock visible 模式：Dock / Command+Tab 可见；菜单栏入口仍可用；全局热键仍可用。
   - 设置窗口和搜索窗口在两种模式下都必须能前置。

5. 文档同步
   - 更新 `docs/install.md`：说明如何恢复 Dock 图标、何时需要重启、异常时如何回到菜单栏模式。
   - 更新 `docs/manual_test.md`：新增 L2 手测矩阵，覆盖隐藏 Dock -> 显示 Dock -> 重启 -> 再隐藏 Dock。
   - 更新 `docs/release_checklist.md`：把两种模式的最小入口验证纳入 release gate。
   - 更新 `docs/known_issues.md`：把"隐藏 Dock 的用户可配置性尚未完成"改为 L2 已落地，同时保留 macOS activation policy 行为差异边界。
   - 更新 `docs/stage_status.md`：写入 L2 实现状态，提交 Codex 验收前标为"待 Codex 验收"。

## 明确不做

- 不做单实例 / 多 bundle 防护，那是 L4。
- 不做菜单栏最近打开、常用、DB 大小、root 简况，那是 L3。
- 不做正式 Developer ID 签名、公证、DMG、auto updater。
- 不重写搜索窗口或设置窗口系统。
- 不修改搜索、索引、DB schema、Run Count、usage ranking、query history、saved filters 等业务能力。
- 不把 plist `LSUIElement=true` 和 runtime activation policy 同时做成互相冲突的双控制源。

## 关键文件

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `scripts/package-app.sh`
- `docs/install.md`
- `docs/manual_test.md`
- `docs/release_checklist.md`
- `docs/known_issues.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`

## 验收标准

- 新安装 / 新数据库默认仍是 no Dock 菜单栏 agent。
- 设置页能清楚看到并修改 Dock 可见性选项。
- 设置值能持久化，重启后仍生效。
- 如声明实时切换，则切换后 Dock / Command+Tab 行为实际变化；如声明重启生效，则 UI 和文档都明确要求重启。
- no Dock 和 Dock visible 两种模式下，菜单栏搜索、菜单栏设置、菜单栏退出、全局热键均可用。
- 设置窗口 / 搜索窗口在两种模式下都能前置。
- 文档不再把 Dock 显示开关写成未完成项。
- 没有提前实现 L3/L4 内容。

## 必须运行的检查

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift build --disable-sandbox

HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekSmokeTest

HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/package-app.sh --sandbox

plutil -p dist/SwiftSeek.app/Contents/Info.plist | grep -E 'LSUIElement|CFBundleIdentifier|GitCommit|BuildDate'
```

## 必须手测

1. 新 HOME / 新 DB 启动 `dist/SwiftSeek.app`，确认默认 no Dock、菜单栏图标存在。
2. 菜单栏 → 设置 → 开启"显示 Dock 图标"。
3. 按实现声明执行：实时确认 Dock 出现，或重启后确认 Dock 出现。
4. Dock visible 模式下确认菜单栏搜索、菜单栏设置、全局热键、退出均可用。
5. 再关闭"显示 Dock 图标"。
6. 按实现声明执行：实时确认 Dock 消失，或重启后确认 Dock 消失。
7. no Dock 模式下确认菜单栏搜索、菜单栏设置、全局热键、退出均可用。
8. 重复切换 3 次，不出现不可退出、窗口不可前置、菜单栏图标丢失或 Dock 状态与设置不一致。
