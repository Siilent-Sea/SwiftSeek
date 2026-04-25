# 下一阶段任务书：K6

当前活跃轨道：`everything-productization`
当前阶段：`K6`
阶段名称：Release QA、包体产物与最终收口

## 交给 Claude 的任务

你现在只做 K6。目标不是新增功能，而是把 K1-K5 已完成内容串成一条可执行、可复查的最终 release QA 路径，让 Codex 能判断 `everything-productization` 是否可以 `PROJECT COMPLETE`。

K6 不做 Developer ID 签名、不做 notarization、不做 DMG、不做 auto updater，除非用户明确改变范围。

## 必须先审计的路径

- `scripts/build.sh`
- `scripts/package-app.sh`
- `scripts/make-icon.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `README.md`
- `docs/install.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/architecture.md`
- `docs/everything_productization_gap.md`
- `docs/everything_productization_taskbook.md`

重点确认：
- K1 build identity / stale bundle 防护仍准确。
- K2 package app 流水线仍可重复运行。
- K3 diagnostics 和 K5 root health 诊断同源。
- K4 install / upgrade / rollback 文档和当前 bundle 行为一致。
- README、known issues、manual test、architecture 没有仍停在 K4/K5 的过期表述。

## 必须做

1. 建立最终 release checklist，至少覆盖：
   - fresh / clean workspace build
   - package app
   - launch app
   - settings reopen 10 次
   - search window hotkey / ESC hide
   - add root
   - search
   - open file
   - Run Count update
   - DB stats
   - Launch at Login note
   - app icon
   - About build identity
   - diagnostics copy
   - K5 root health / FDA recheck
   - install / upgrade / rollback docs
2. 增加 release notes 模板，必须诚实写明：
   - 当前是本地 ad-hoc bundle
   - 不含 Developer ID signing
   - 不含 notarization
   - 不含 DMG / auto updater
   - 已知权限 / FDA / 外接盘边界
3. 同步 `README.md`、`docs/manual_test.md`、`docs/known_issues.md`、`docs/architecture.md`，让它们反映 K1-K6 最终状态。
4. 确认 `scripts/build.sh`、`scripts/package-app.sh`、icon、Info.plist、codesign 文档一致。
5. 保留 K1-K5 已通过面，不重写已稳定实现。

## 明确不做

- 不做 Apple Developer ID 签名。
- 不做 notarization。
- 不做 Sparkle / auto updater。
- 不做 App Store packaging。
- 不新增搜索 / ranking / 索引业务功能。
- 不把 K6 继续拆成 K7；如果 K6 通过，Codex 应能判断是否 `PROJECT COMPLETE`。

## 验收标准

1. release checklist 可从 clean workspace 实际跑通。
2. `.app` 产物可重复生成并启动。
3. app icon、Info.plist、bundle id、version、build identity 可验证。
4. 设置窗口生命周期 release gate 通过。
5. About / diagnostics 可复制，且包含 K3/K5 关键字段。
6. README / known issues / manual test / architecture 与最终代码一致。
7. 未签名 / 未公证 / ad-hoc 边界诚实，不夸大交付能力。

## 必须补的验证

```text
1. shell: `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox`
2. shell: `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
3. shell: `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox`
4. shell: `plutil -lint dist/SwiftSeek.app/Contents/Info.plist`
5. shell: `codesign -dv --verbose=2 dist/SwiftSeek.app`
6. GUI: `open dist/SwiftSeek.app` 后确认启动日志 build identity 三连。
7. GUI: 设置窗口 10 次 close/show、菜单栏重开、主菜单重开、Dock reopen。
8. GUI: add root → search → open file → Run Count update。
9. GUI: About → 复制诊断信息，确认包含 build identity、schema、DB stats、Launch at Login、roots 健康（K5）。
10. GUI/docs: 按 release checklist 验证 install / upgrade / rollback / FDA recheck 文档没有矛盾。
```

## 验收后文档

K6 完成后交 Codex 验收。不要自己宣布 `PROJECT COMPLETE`。Codex 如果通过，会给 `PROJECT COMPLETE`；如果拒绝，按 blocker 修复。
