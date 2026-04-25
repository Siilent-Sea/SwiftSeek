# 下一阶段任务书：K1

当前活跃轨道：`everything-productization`
当前阶段：`K1`
阶段名称：设置窗口回归门禁 + stale build 防护

## 交给 Claude 的任务

你现在只做 K1。目标不是新增业务功能，也不是开始正式打包，而是把用户真实遇到过的设置窗口问题变成长期 release gate，并让用户能判断当前运行的是不是最新构建。

K1 不做 `.app` 打包流水线，不做 DMG，不做 notarization，不做 Apple Developer ID 签名，不做 Launch at Login 大改。

## 必须先审计的代码路径

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/App/LaunchAtLogin.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `scripts/build.sh`
- `scripts/make-icon.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

重点确认：
- `windowShouldClose` 是否仍是 hide-only close。
- `AppDelegate.applicationShouldHandleReopen` 是否仍覆盖 Dock reopen。
- 主菜单 / menu bar 设置入口是否仍指向 `showSettings`。
- 设置 tab 记忆是否仍用 KVO，不能回退到非法 `tabView.delegate`。
- `scripts/build.sh` 是否仍只产出 `.build/release` 二进制。
- `scripts/build.sh` 是否还有过期 schema 文案。
- About / diagnostics 是否缺少 version / commit / build timestamp / bundle path。

## 必须做

1. 建立设置窗口 release gate：
   - 设置窗口 10 次关闭 / 打开。
   - 启动后打开设置、关闭、从菜单栏重开。
   - 从主菜单 `SwiftSeek -> 设置…` 重开。
   - 无可见窗口时 Dock 点击重开。
   - 设置 tab 反复切换不崩溃。
2. 把上述 release gate 写入 `docs/manual_test.md` 或明确 release checklist 文档。
3. 增加运行时 build identity：
   - About / diagnostics 显示 app version。
   - 显示 schema version。
   - 显示 git commit 或 build timestamp。
   - 显示 bundle path 或 executable path。
4. 启动日志打印 build identity。
5. 如果无法自动注入 git commit，先用 build-info 文件或 Swift 常量，并在文档说明限制。
6. 修正 `scripts/build.sh` 中已知过期文案，至少不能继续打印 schema v3。
7. 更新 README / known issues / manual test，说明如何确认当前运行的是最新 bundle / binary。
8. 保持 J1/J6 生命周期修复不回归。

## 明确不做

- 不做 K2：正式 `.app` package 脚本。
- 不做 DMG。
- 不做 notarization。
- 不做 Apple Developer ID 签名。
- 不做 auto updater。
- 不做 Launch at Login 大改。
- 不新增搜索 / ranking / 索引功能。

## 验收标准

1. 设置窗口 release gate 已写入文档，且步骤可执行。
2. 设置窗口关闭 / 菜单栏重开 / 主菜单重开 / Dock reopen 的手测路径明确。
3. 设置 tab 切换不再使用非法 `tabView.delegate` 方案。
4. About / diagnostics 或等价 UI 可见 version、schema、build identity、bundle/executable path。
5. 启动日志打印 build identity。
6. 用户可通过文档判断 stale bundle / stale binary。
7. `scripts/build.sh` 不再输出 schema v3 等明显过期内容。
8. `swift build` 通过。
9. `swift run SwiftSeekSmokeTest` 通过。

## 必须补的手测

```text
1. 构建并启动当前 App。
2. 打开 About / diagnostics，确认能看到 version、schema、commit 或 build timestamp、bundle/executable path。
3. 查看启动日志，确认打印 build identity。
4. 点设置窗口左上角 × 关闭。
5. 从菜单栏图标打开“设置…”，必须成功。
6. 再次关闭设置窗口。
7. 从主菜单 SwiftSeek -> 设置… 打开，必须成功。
8. 关闭所有可见窗口。
9. 点击 Dock 图标，必须能重新唤起可操作窗口。
10. 重复设置窗口关闭 / 打开 10 次。
11. 连续切换设置 tab 20 次，不崩溃。
12. 对照 diagnostics 的 build identity，确认当前运行的不是旧 bundle。
```

## 验收后文档

K1 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 K2 任务书；如果 REJECT，按 blocker 修复。
