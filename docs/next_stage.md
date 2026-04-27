# 下一阶段任务书

当前活跃轨道：`everything-dockless-hardening`

当前阶段：`N2`
阶段名：默认无 Dock 的打包与启动策略硬化

## 交给 Claude 的 N2 任务

N1 已通过 Codex 验收。N2 开始处理默认 `.app` 产物的 Dock 策略硬化，让默认交付更接近 no-Dock / menu bar agent，而不是只靠历史文档声明。

### 必须完成

- 重新设计 `scripts/package-app.sh` 的 Dock 模式参数：
  - 默认生成 no-Dock / menu bar agent 包。
  - 增加显式 Dock App 模式参数，例如 `--dock-app`。
- 必须选定并实现一种主策略：
  - 推荐方案：默认包写 `LSUIElement=true`，`--dock-app` 写 `LSUIElement=false`。
  - 如果保留 `LSUIElement=false`，必须在代码和文档中给出可验证理由，并证明默认包仍能稳定 no-Dock；不能只复述 L1 历史结论。
- package 输出日志必须打印：
  - intended Dock mode
  - `LSUIElement` 值
  - `GitCommit`
  - bundle id
  - 输出 app path
- 保持 N1 Diagnostics 可用，并确保 `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 能直接验证 package 参数对应的 `LSUIElement`。
- 更新 `docs/install.md`、`docs/release_checklist.md`、`docs/known_issues.md` 中关于默认包体和 Dock App 包的说明。

### 禁止事项

- 不做 Developer ID 签名、公证、DMG、auto updater。
- 不移除 `dock_icon_visible` 设置。
- 不静默强改用户 DB。
- 不提前实现 N3 的设置页一键恢复 UI，除非只是为了让 N2 包策略不崩的最小文案同步。
- 不声称最终 release gate 已完成；真实 `.app` 全组合手测留给 N4。

### 验收方式

- `swift build --disable-sandbox`
- `swift run --disable-sandbox SwiftSeekSmokeTest`
- `./scripts/package-app.sh --sandbox`
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist`，确认默认包的 `LSUIElement` 与 N2 策略一致。
- `./scripts/package-app.sh --sandbox --dock-app`（或实现后的等价参数）
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist`，确认 Dock App 包的 `LSUIElement` 与参数一致。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist`
- `codesign -dv dist/SwiftSeek.app`
- 真实 `.app` 手测至少覆盖：
  - 默认包启动后 Dock 不出现，菜单栏入口可用。
  - Dock App 包启动后 Dock 出现，菜单栏入口仍可用。
  - Settings、Quit、Search window、global hotkey 没有明显回归。
