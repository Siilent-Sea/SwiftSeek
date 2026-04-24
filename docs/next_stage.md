# 下一阶段任务书：J6

当前活跃轨道：`everything-ux-parity`
当前阶段：`J6`
阶段名称：首次使用 / 权限引导 / Launch 行为 / 最终收口

## 交给 Claude 的任务

你现在只做 J6。目标是把 SwiftSeek 从“能工作的开发者工具”进一步收口为长期可用的 Mac 工具体验，并为 `everything-ux-parity` 的最终 `PROJECT COMPLETE` 做准备。

J6 不做云同步，不做遥测，不读取系统隐私数据，不假装已经完成签名 / 公证或 App Store 沙盒适配。

## 必须先审计的代码路径

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `Package.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/everything_ux_parity_gap.md`
- `docs/everything_ux_parity_taskbook.md`

重点确认：
- fresh profile 首次启动时，用户是否知道先加 root、为什么需要 Full Disk Access、compact / fullpath 怎么选
- 权限不足或 root 不可访问时，UI 是否给出可理解的提示和修复路径
- Launch at Login 在当前 SwiftPM / 本地 bundle 形态下能否真实实现；如果不适合实现，文档如何明确写限制
- 搜索窗口和设置窗口的位置 / 尺寸 / 当前 tab 是否需要持久化，以及会不会破坏现有列宽 / 排序持久化
- README / manual_test / known_issues / gap / acceptance 文档是否已经和最终代码一致

## 必须做

1. 补齐首次使用引导，至少让用户知道：
   - 先添加索引 root
   - 为什么可能需要 Full Disk Access
   - compact / fullpath 模式差异
   - Run Count 与 usage history 的语义边界
2. 权限不足时给出明确提示和修复路径，不能沉默失败。
3. 对 Launch at Login 给出真实结论：
   - 能实现就做真实实现
   - 当前形态不适合实现就明确写限制和推迟原因
   - 不能假实现
4. 记忆窗口状态：
   - 设置窗口大小 / 位置
   - 搜索窗口大小 / 位置
   - 设置页当前 tab（如成本合理）
5. 确保窗口状态持久化不破坏现有列宽 / 排序持久化。
6. 统一最终文档：
   - `README.md`
   - `docs/manual_test.md`
   - `docs/known_issues.md`
   - `docs/everything_ux_parity_gap.md`
   - `docs/codex_acceptance.md`
   - `docs/next_stage.md`
7. 给 `Sources/SwiftSeekSmokeTest/main.swift` 补可自动化的新增设置项 round-trip smoke。

## 明确不做

- 不承诺 App Store 沙盒适配。
- 不承诺签名 / 公证已完成，除非真实完成。
- 不读取系统隐私数据。
- 不做云同步。
- 不做遥测。
- 不用 private API。

## 验收标准

1. 首次使用用户能清楚知道先加 root、为何需要权限、索引模式怎么选。
2. 权限不足时不是沉默失败。
3. Launch at Login 有真实实现或明确推迟说明，不能假实现。
4. 窗口状态记忆不破坏现有列宽 / 排序持久化。
5. 文档与最终代码一致。
6. `swift build --disable-sandbox` 通过。
7. `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。
8. Codex 可据此判断 `everything-ux-parity` 是否达到 `PROJECT COMPLETE`。

## 必须补的手测

```text
1. fresh profile 首次启动，确认用户知道先加 root、如何理解权限提示、索引模式怎么选。
2. 在没有 Full Disk Access 或 root 不可访问时，确认 UI 提示清楚且有修复路径。
3. 重启 app 后，搜索窗口和设置窗口的位置 / 尺寸恢复；设置页 tab 如实现则同步恢复。
4. 验证窗口状态记忆不会破坏 J2 的列宽与排序持久化。
5. 若实现 Launch at Login，验证真实行为；若未实现，检查文档中的限制说明是否清楚。
6. 最终对照 README / manual_test / known_issues / ux parity gap / acceptance 文档是否一致。
```

## 验收后文档

J6 完成后交 Codex 验收。不要自己宣布 `PROJECT COMPLETE`。只有 Codex 在确认 J1-J6 全部收口、关键闭环成立、无阻塞问题、文档齐全后，才会给 `everything-ux-parity` 的最终 `PROJECT COMPLETE`。
