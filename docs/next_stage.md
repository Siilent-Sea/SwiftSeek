# 下一阶段任务书：J1

当前活跃轨道：`everything-ux-parity`
当前阶段：`J1`
阶段名称：设置窗口与 App 生命周期修复

## 交给 Claude 的任务

你现在只做 J1。目标是修复用户当前复现的高优先级 UX bug：设置窗口点左上角关闭后，再次无法正常打开设置，只能退出重启。

J1 不做业务搜索功能，不做 Run Count UI，不做查询语法，不做搜索历史，不做上下文菜单扩展。

## 必须先审计的代码路径

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/App/MainMenu.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`

重点确认：
- `AppDelegate.showSettings(_:)`
- `SettingsWindowController` 的 window 创建与关闭行为
- `window.isReleasedWhenClosed`
- 是否需要 `windowShouldClose`
- 是否需要设置 `NSWindowDelegate`
- 是否需要实现 `applicationShouldHandleReopen(_:hasVisibleWindows:)`
- 主菜单“设置…”入口
- 菜单栏“设置…”入口
- Dock 图标点击行为
- 搜索窗口 show / hide / toggle 是否受影响

## 必须做

1. 复现或基于代码确认设置窗口关闭后不可重新打开的原因。
2. 修复设置窗口关闭后的重开路径。
3. 保证从菜单栏图标“设置…”可以重新打开设置。
4. 保证从主菜单 `SwiftSeek -> 设置…` 可以重新打开设置。
5. 实现或补齐 Dock reopen：无可见窗口时点击 Dock 图标必须能重新唤起可操作窗口或明确入口。
6. 推荐修法：
   - 设置窗口关闭按钮只隐藏窗口，不销毁 controller；或
   - 关闭后 `AppDelegate` 能安全重新创建 `SettingsWindowController`。
7. 确认搜索窗口热键 / 菜单 / 菜单栏呼出不回归。
8. 更新 `docs/manual_test.md`，加入 J1 手测步骤。
9. 如能自动化，给 `Sources/SwiftSeekSmokeTest/main.swift` 补生命周期相关轻量测试；不能自动化的 GUI 行为必须写入 manual test。
10. 更新 `docs/known_issues.md`：修复后把“当前待修 bug”改成历史限制或已解决说明，不要继续说未修。

## 明确不做

- 不做 J2：Run Count 列、列宽、文案、可见性改版。
- 不做 J3：wildcard / quote / OR / NOT。
- 不做 J4：搜索历史 / Saved Filters。
- 不做 J5：上下文菜单动作扩展。
- 不做 J6：首次使用完整向导、Launch at Login、签名 / 公证。
- 不重写整个 UI。

## 验收标准

1. 启动 App 后设置窗口可正常出现。
2. 点设置窗口左上角关闭后，从菜单栏图标“设置…”可以再次打开。
3. 点设置窗口左上角关闭后，从主菜单 `SwiftSeek -> 设置…` 可以再次打开。
4. 所有窗口都不可见时，点击 Dock 图标可以重新唤起可操作窗口或明确的搜索 / 设置入口。
5. 重复 10 次关闭 / 打开设置窗口，不崩溃、不丢 controller、不出现菜单入口失效。
6. 搜索窗口通过热键、主菜单、菜单栏呼出仍正常。
7. ESC / 失焦隐藏搜索窗口行为没有回归。
8. `swift build` 通过。
9. `swift run SwiftSeekSmokeTest` 通过。
10. `docs/manual_test.md` 有明确 J1 GUI 手测步骤。

## 必须补的手测

```text
1. 启动 App，设置窗口出现。
2. 点设置窗口左上角 × 关闭设置窗口。
3. 从菜单栏图标打开“设置…”，必须成功。
4. 再次点 × 关闭设置窗口。
5. 从主菜单 SwiftSeek -> 设置… 打开，必须成功。
6. 关闭所有可见窗口。
7. 点击 Dock 图标，必须能重新唤起可操作窗口或明确入口。
8. 重复设置窗口关闭 / 打开 10 次，不崩溃、不失效。
9. 用热键或菜单打开搜索窗口，确认搜索窗口仍能 show / hide。
10. ESC 或失焦隐藏搜索窗口，确认原行为没有回归。
```

## 验收后文档

J1 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 J2 任务书；如果 REJECT，按 blocker 修复。
