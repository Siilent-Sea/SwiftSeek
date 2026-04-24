# 下一阶段任务书：J2

当前活跃轨道：`everything-ux-parity`
当前阶段：`J2`
阶段名称：Run Count 可见性与结果列体验复核

## 交给 Claude 的任务

你现在只做 J2。目标是解决用户“没看到启动次数 / Run Count”的实际体验问题。H1-H5 已证明 usage 数据链路存在，但 J2 必须重新以用户可见性为准验收。

J2 不做查询语法，不做搜索历史，不做上下文菜单，不做首次使用流程，不把 usage tie-break 改成压过文本相关性。

## 必须先审计的代码路径

- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/UsageTypes.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`

重点确认：
- `file_usage.open_count` / `last_opened_at` 是否真实写入
- `SearchEngine` 是否稳定把 usage 数据 join 到 `SearchResult`
- 结果表“打开次数” / “最近打开”两列是否默认可见
- 列宽持久化是否会把列压窄到用户看不见
- 是否需要“恢复默认列宽”或等价恢复入口
- 文案是否要同时写清“Run Count / 打开次数”
- `recent:` / `frequent:` 与可见列是否对同一 usage 数据一致
- 用户运行 release 包时是否可能因为旧构建导致“没看到列”

## 必须做

1. 基于当前 H1-H5 实现审计 Run Count 为什么“用户没看到”。
2. 如果问题是列默认可见性、列宽、标题文案、空值表达、旧持久化状态或 release 构建路径，做最小必要修复。
3. 保证打开某文件 3 次后，搜索该文件时“打开次数”显示为 3，“最近打开”同步更新。
4. 保证 fresh DB / 从未打开文件显示清晰空值，例如 `—`。
5. 如果列宽持久化会把列压窄到几乎不可见，提供“恢复默认列宽”或等价入口。
6. UI 或文档要明确 Run Count 只统计 SwiftSeek 内部成功 `.open`；Reveal / Copy 不计入。
7. `recent:` / `frequent:` 结果与显示列一致，不出现“数据有但列看不到”的不一致。
8. 更新 `docs/manual_test.md`，加入 J2 手测步骤。
9. 如能自动化，给 `Sources/SwiftSeekSmokeTest/main.swift` 补 usage 可见性/列配置相关 smoke；不能自动化的 GUI 行为必须写入 manual test。
10. 更新 `docs/known_issues.md`：修完后把 Run Count 可见性问题改成已解决或缩小为真实剩余限制。

## 明确不做

- 不做 J3：wildcard / quote / OR / NOT。
- 不做 J4：搜索历史 / Saved Filters。
- 不做 J5：上下文菜单动作扩展。
- 不做 J6：首次使用完整向导、Launch at Login、签名 / 公证。
- 不读取 macOS 全局历史。
- 不改 H2 相关性边界：usage 只能做同 score tie-break，不能压过高相关结果。

## 验收标准

1. 通过 SwiftSeek 打开某文件 3 次后，搜索该文件可见“打开次数”为 3。
2. “最近打开”时间随成功 `.open` 更新。
3. fresh DB / 从未打开文件显示清晰空值，如 `—`。
4. 默认列宽下“打开次数 / 最近打开”无需横向滚动或极端拉宽即可看见。
5. 历史列宽异常时有恢复默认列宽的路径。
6. 文档和 UI 都明确 Run Count 不是 macOS 全局启动次数。
7. `recent:` / `frequent:` 结果与显示列一致。
8. `swift build --disable-sandbox` 通过。
9. `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。
10. `docs/manual_test.md` 有明确 J2 GUI 手测步骤。

## 必须补的手测

```text
1. 选择一个已被索引的文件，通过 SwiftSeek 连续打开 3 次。
2. 再次搜索该文件，确认“打开次数”列显示 3。
3. 确认“最近打开”列同步刷新为刚刚的时间。
4. 找一个从未通过 SwiftSeek 打开的文件，确认显示为 `—` 而不是误导性数值。
5. 如果列初始不可见，验证恢复默认列宽/重置入口可恢复显示。
6. 输入 `recent:` / `frequent:`，确认结果和列里的 usage 数据一致。
7. 文案处明确说明 Run Count 只统计 SwiftSeek 内部成功 `.open`。
```

## 验收后文档

J2 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 J3 任务书；如果 REJECT，按 blocker 修复。
