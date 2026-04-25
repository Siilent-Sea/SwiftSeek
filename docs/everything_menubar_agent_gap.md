# Everything Menubar Agent Gap

本文基于当前代码审计 SwiftSeek 与菜单栏 agent / tray-like 工具形态之间的差距。它不是功能完成度复述，而是 L 轨道立项依据。

## 审计依据

- `scripts/package-app.sh`：当前 `Info.plist` 写入 `<key>LSUIElement</key><false/>`
- `Sources/SwiftSeek/App/AppDelegate.swift`：安装 `NSStatusItem`，包含搜索、设置、索引状态、退出菜单；同时仍设置主菜单、启动时激活 App、支持 Dock reopen
- `Sources/SwiftSeek/App/MainMenu.swift`：主菜单包含搜索、设置、隐藏、退出
- `Sources/SwiftSeek/UI/SearchWindowController.swift`：搜索窗 show 时调用 `NSApp.activate(ignoringOtherApps:)`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`：设置窗口 hide-only close、frame/tab 记忆已存在
- `Sources/SwiftSeek/App/GlobalHotkey.swift`：全局热键可作为无 Dock 模式的重要入口
- `docs/release_checklist.md` / `docs/install.md`：仍把 Dock 图标、Dock reopen、Dock 退出写成当前默认交付路径的一部分

## Gap 1：Dock 图标仍然常驻

- 当前现状：`scripts/package-app.sh` 生成 `Info.plist` 时写 `LSUIElement=false`，打包后的 `SwiftSeek.app` 是普通 Dock App。
- 为什么是问题：用户期望 SwiftSeek 是类似 Everything / tray-like 的常驻小工具；常驻 Dock 会让它看起来像普通前台应用。
- 用户影响：Dock 和 Command+Tab 被 SwiftSeek 占用，工具感弱，长期运行时干扰日常窗口管理。
- 推荐优先级：高。
- 建议解决阶段：L1。

## Gap 2：菜单栏入口已经存在，但还不是主入口

- 当前现状：`AppDelegate.installStatusItem()` 已创建 `NSStatusItem`，菜单包含"搜索…"、"设置…"、"索引：空闲/索引中"、"退出 SwiftSeek"。
- 为什么是问题：功能上已有菜单栏入口，但产品形态仍由 Dock App 决定；release checklist 也仍要求 Dock 图标行为。
- 用户影响：用户不知道应从菜单栏操作，隐藏 Dock 后的主入口心智没有建立。
- 推荐优先级：高。
- 建议解决阶段：L1。

## Gap 3：隐藏 Dock 后主菜单、激活和窗口前置需要重新验证

- 当前现状：`AppDelegate.applicationDidFinishLaunching` 设置 `NSApp.mainMenu` 并调用 `NSApp.activate(ignoringOtherApps:)`；`showSettings` 和 `SearchWindowController.show()` 也调用 `NSApp.activate`。代码中没有当前轨道专门的 `NSApp.setActivationPolicy` 路径。
- 为什么是问题：`LSUIElement=true` 或 `.accessory` 模式会改变 Dock、Command+Tab、主菜单可见性与激活行为。原本依赖 Dock/主菜单的路径可能不再成立。
- 用户影响：可能出现菜单栏点了搜索/设置但窗口不前置、主菜单不可见、Dock reopen 不存在但文档仍要求它的情况。
- 推荐优先级：高。
- 建议解决阶段：L1-L2。

## Gap 4：Quit 路径必须从 Dock 迁移到菜单栏

- 当前现状：status item 已有"退出 SwiftSeek"，但 `docs/install.md` 和 release checklist 仍把 Dock 右键退出 / Dock 图标验证作为默认路径。
- 为什么是问题：隐藏 Dock 后用户不能依赖 Dock 右键退出。如果 status item 异常，用户需要明确 fallback。
- 用户影响：用户可能不知道如何退出后台 agent，尤其是在无 Dock、无主窗口状态下。
- 推荐优先级：高。
- 建议解决阶段：L1。

## Gap 5：Launch at Login 与 LSUIElement / activationPolicy 的关系未收口

- 当前现状：`LaunchAtLogin.swift` 使用公开 `SMAppService.mainApp`，并已说明未签名 / ad-hoc bundle 可能注册不稳定。但没有把菜单栏 agent 模式、登录启动后无 Dock、首次窗口是否出现、状态项是否可见一起纳入验收。
- 为什么是问题：菜单栏 agent 最常见运行方式就是登录后后台常驻；未验证这条路径会让用户误以为 app 没启动。
- 用户影响：登录后无 Dock 图标时，若菜单栏图标未出现或窗口无法前置，用户会认为启动失败。
- 推荐优先级：中。
- 建议解决阶段：L2-L4。

## Gap 6：多实例 / stale bundle 风险在菜单栏 agent 形态下更明显

- 当前现状：productization 轨道已补 build identity 和 stale bundle 文档，但当前没有单实例保护。`docs/install.md` 已说明多个 bundle 可能共享同一 DB，SQLite writer 会竞争。
- 为什么是问题：菜单栏 app 没 Dock 图标，多开后用户更难发现哪个实例在跑；旧 `/Applications` bundle 与新 `dist` bundle 可能同时常驻。
- 用户影响：菜单栏可能出现多个 SwiftSeek 图标，或用户操作的不是最新构建，甚至出现 DB busy / hotkey 争用。
- 推荐优先级：中。
- 建议解决阶段：L4。

## Gap 7：隐藏 Dock 的用户可配置性缺失

- 当前现状：`SettingsTypes.swift` 有热键、索引模式、列宽、登录启动等设置，但没有 Dock 显示 / 菜单栏模式设置键；设置页也没有相关开关。
- 为什么是问题：默认隐藏 Dock 符合工具形态，但部分用户仍可能需要 Dock / Command+Tab 入口；动态切换是否可靠也要按 macOS 行为实测。
- 用户影响：一旦隐藏 Dock 且菜单栏或热键异常，用户缺少可见恢复入口。
- 推荐优先级：中。
- 建议解决阶段：L2。

## Gap 8：菜单栏状态信息仍偏基础

- 当前现状：status item tooltip 只是"SwiftSeek 搜索"，菜单里只有索引状态，没有 build version、index mode、root count、DB 大小等简况。
- 为什么是问题：菜单栏成为主入口后，它需要承担状态可见性，否则用户仍要打开设置页才能判断工具是否正常。
- 用户影响：后台索引、DB 膨胀、root 状态、当前构建等关键信息不可快速确认。
- 推荐优先级：中。
- 建议解决阶段：L3。
