# Everything Dockless Hardening Gap

轨道名：`everything-dockless-hardening`

本文基于当前真实代码审计 SwiftSeek “Dock 仍常驻 / no-Dock 不够硬”的差距。用户已经反馈打包后 Dock 仍然出现，因此历史 `everything-menubar-agent` 的完成结论只能作为背景，不能作为当前事实。

## 审计依据

- `scripts/package-app.sh`：生成的 `Info.plist` 仍写 `<key>LSUIElement</key><false/>`。
- `Sources/SwiftSeek/App/AppDelegate.swift`：启动时先 `NSApp.setActivationPolicy(.accessory)`，DB 打开后读取 `dock_icon_visible`，为 true 时切到 `.regular`。
- `Sources/SwiftSeekCore/SettingsTypes.swift`：存在 `SettingsKey.dockIconVisible = "dock_icon_visible"`，默认 false，`1` 表示下次启动显示 Dock。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`：设置页已有“在 Dock 显示 SwiftSeek 图标”复选框，切换需重启。
- `Sources/SwiftSeekCore/Diagnostics.swift`：已有 build identity、bundle、binary、DB、Launch at Login、Reveal target，但没有完整 Dock mode 诊断块。
- `docs/install.md` / `docs/release_checklist.md`：已声明 L1 默认 no Dock，但实现依赖 runtime activation policy 和持久化设置。

## Gap 1：包体层面仍是 `LSUIElement=false`

- 当前现状：`scripts/package-app.sh` 写入 `LSUIElement=false`，注释说明 no-Dock 由 `AppDelegate` 运行时 `.accessory` 控制。
- 为什么是问题：包体仍是普通 App，Dock 隐藏不是 Info.plist 层面的强约束；LaunchServices、旧 bundle、用户设置都可能让实际体验偏离“默认 no Dock”。
- 用户影响：用户打包启动后仍可能看到 SwiftSeek 常驻 Dock，并且很难判断是包体、旧设置还是旧 bundle 造成。
- 推荐优先级：高。
- 建议解决阶段：N2。

## Gap 2：runtime `.accessory` 不是包体级硬隐藏

- 当前现状：`AppDelegate.applicationDidFinishLaunching` 先调用 `NSApp.setActivationPolicy(.accessory)`，再继续初始化主菜单、DB、status item、窗口和热键。
- 为什么是问题：no-Dock 依赖运行时路径执行成功；如果运行时随后切 `.regular`、启动路径异常、或用户运行旧 bundle，Dock 仍会出现。
- 用户影响：文档说“默认菜单栏 agent”，但真实运行时仍可能表现为普通 Dock App。
- 推荐优先级：高。
- 建议解决阶段：N1 先诊断，N2 再硬化策略。

## Gap 3：`dock_icon_visible` 持久化设置可能污染真实体验

- 当前现状：DB 中 `dock_icon_visible=1` 会让 `AppDelegate` 在启动后调用 `NSApp.setActivationPolicy(.regular)`。该值可能来自用户手动勾选，也可能来自测试、旧版本状态或排查过程。
- 为什么是问题：只要旧 DB 保留该值，即使新包体和文档都说默认 no-Dock，用户仍会看到 Dock。
- 用户影响：用户无法直观看出 Dock 常驻是“用户意图”还是“实现失败”，只能靠手工查 SQLite 或看 Console 日志。
- 推荐优先级：高。
- 建议解决阶段：N1 诊断暴露，N3 提供 UI 自救路径。

## Gap 4：设置页缺少明确修复路径

- 当前现状：设置页有“在 Dock 显示 SwiftSeek 图标”复选框和重启说明，但没有“一键恢复菜单栏模式 / 隐藏 Dock”的强引导，也没有直接显示当前 effective activation policy / Info.plist 状态。
- 为什么是问题：用户看到 Dock 常驻时，需要的是明确修复动作，而不是理解底层 activation policy 细节。
- 用户影响：用户可能不知道取消勾选后要退出重启，也不知道自己当前运行的是 `/Applications` 旧 bundle 还是 `dist` 新 bundle。
- 推荐优先级：高。
- 建议解决阶段：N3。

## Gap 5：Diagnostics 缺少 Dock 状态块

- 当前现状：`Diagnostics.snapshot` 已包含版本、commit、bundle、binary、DB、Launch at Login、Reveal target 等，但没有 persisted `dock_icon_visible`、intended mode、effective activation policy、Info.plist `LSUIElement`。
- 为什么是问题：这是当前问题最需要的证据面。没有这些字段，用户反馈“Dock 仍出现”时无法快速判断根因。
- 用户影响：排查需要让用户手工执行 `sqlite3`、`plutil`、看 Console；对普通用户不够可操作。
- 推荐优先级：高。
- 建议解决阶段：N1。

## Gap 6：release checklist 对 Dock 的验证还不够硬

- 当前现状：`docs/release_checklist.md` 已有 L1/L2 no-Dock 和 Dock 显示开关手测，但它没有把 `LSUIElement` 值、fresh DB、`dock_icon_visible=1` 旧 DB、`dock_icon_visible=0` 旧 DB、stale bundle 同时作为 release gate。
- 为什么是问题：只测 fresh path 容易通过；真实用户往往有历史 DB、旧 `/Applications` bundle、LaunchServices 缓存或多个 bundle 并存。
- 用户影响：release checklist 通过后，用户仍可能在真实机器上看到 Dock 常驻。
- 推荐优先级：高。
- 建议解决阶段：N4。

## Gap 7：多实例 / stale bundle 会放大误判

- 当前现状：L4 已有同 bundle id 单实例防护，K1/K3 已有 build identity；但 Dock 问题仍可能来自用户启动了旧 `/Applications/SwiftSeek.app`，而不是刚打包的 `dist/SwiftSeek.app`。
- 为什么是问题：如果用户运行旧 bundle，任何源码层修复都不会生效；Dock 仍出现会被误判为当前实现失败。
- 用户影响：用户看到“代码已修但体验没变”，需要 Diagnostics 明确 bundle path、binary path、Info.plist 和 Dock mode。
- 推荐优先级：中。
- 建议解决阶段：N1 和 N4。

## Gap 8：package 策略尚未重新定案

- 当前现状：历史 L1/L2 选择保留 `LSUIElement=false`，由 runtime `.accessory` + `dock_icon_visible` 控制 Dock。用户反馈说明这个策略对“默认不常驻 Dock”的产品要求不够强。
- 为什么是问题：继续沿用旧策略会让 no-Dock 依赖太多条件；改成 `LSUIElement=true` 又会影响 Dock 显示开关、主菜单、激活和 Launch at Login，需要明确取舍。
- 用户影响：不定案会导致后续 Claude 只做局部补丁，无法保证最终交付形态。
- 推荐优先级：高。
- 建议解决阶段：N2。
