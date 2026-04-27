# 下一阶段任务书

当前活跃轨道：`everything-dockless-hardening`

当前阶段：`N4`
阶段名：真实 `.app` 手测 gate 与最终收口

## 交给 Claude 的 N4 任务

N1-N3 已通过 Codex 验收。N4 是 `everything-dockless-hardening` 的最终收口：把 Dock 是否隐藏从源码/文档声明升级为真实 `.app` release gate，并同步最终文档。N4 通过后才允许 Codex 考虑该轨道 `PROJECT COMPLETE`。

### 必须完成

- 更新 `docs/release_checklist.md`，增加 `everything-dockless-hardening` 的硬 gate，至少覆盖：
  - fresh DB + 默认 agent package。
  - existing DB with `dock_icon_visible=1`。
  - existing DB with `dock_icon_visible=0`。
  - 默认 agent package：`LSUIElement=true`。
  - `--dock-app` package：`LSUIElement=false`。
  - stale bundle / wrong bundle path 识别。
  - menu bar search / settings / quit。
  - global hotkey。
  - N1 Diagnostics Dock block。
  - N3 Settings Dock detail block + restore button。
- 更新 `docs/install.md`，让普通用户能确认：
  - 自己运行的是默认 no-Dock agent 包还是 `--dock-app` 包。
  - 当前 `Info.plist LSUIElement` 是什么。
  - 如何识别 stale `/Applications/SwiftSeek.app` 与 `dist/SwiftSeek.app`。
  - 如何用 N3 设置页恢复菜单栏模式。
- 更新 `docs/known_issues.md`，清理仍与 N2/N3 事实冲突的旧描述；尤其不要再写“当前 Info.plist 仍保留 `LSUIElement=false`”作为当前事实。
- 必要时同步 `docs/manual_test.md` / `docs/architecture.md` / README 中与 Dock hardening 相关的最终状态，避免历史 L1/L2 结论压过 N 轨道事实。
- `docs/codex_acceptance.md` 需要记录 N1-N4 验收链路，明确哪些是自动化验证、哪些是 GUI 手测。
- 最终状态文件必须仍指向当前 resumable session `019dcd82-9d9c-7bb0-a06e-e2d98dab2d72`。

### 禁止事项

- 不做 Developer ID 签名、公证、DMG、auto updater。
- 不移除 `dock_icon_visible` 设置。
- 不静默强改用户 DB。
- 不改变 N2 package mode 策略。
- 不引入 Finder 插件、QSpace 私有 API、URL scheme 猜测或任何文件管理器集成新 scope。
- 不新增新产品能力；N4 是 release gate + 文档收口，不是继续扩功能。

### 验收方式

- `swift build --disable-sandbox`
- `swift run --disable-sandbox SwiftSeekSmokeTest`
- `./scripts/package-app.sh --sandbox`
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 确认 `LSUIElement=true`、`GitCommit` 为当前 HEAD。
- `./scripts/package-app.sh --sandbox --dock-app`
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 确认 `LSUIElement=false`。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist`
- `codesign -dv dist/SwiftSeek.app`
- 真实 `.app` GUI 手测必须形成可验收记录，至少包含：
  - 默认 agent 包 fresh DB：Dock 不出现，菜单栏图标出现。
  - `dock_icon_visible=1` 旧 DB：Dock 出现原因在 Settings detail / Diagnostics 中可见。
  - 点击 N3 恢复按钮：写回 false，退出重启后 Dock 隐藏。
  - `--dock-app` 包：Dock 出现，Settings detail 能显示 `LSUIElement=false（包体允许 Dock）`。
  - stale bundle：Diagnostics / Settings 能看出 bundle path 与预期不一致。
