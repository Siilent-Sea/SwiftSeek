# 下一阶段任务书：J4

当前活跃轨道：`everything-ux-parity`
当前阶段：`J4`
阶段名称：搜索历史、Saved Filters 与快速过滤器

## 交给 Claude 的任务

你现在只做 J4。目标是提升高频使用体验，让用户能复用最近查询和常用过滤器，而不是每次重新输入复杂表达式。

J4 不做上下文菜单，不做首次使用流程，不做云同步，不做遥测，不读取系统搜索历史。

## 必须先审计的代码路径

- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`

重点确认：
- 最近查询历史如何落盘
- 重复查询如何去重并更新时间
- Saved Filters / 收藏查询如何新增、列出、删除
- 搜索窗里如何暴露最近查询 / Saved Filters / 快速过滤器入口
- 隐私边界文案如何写清楚
- 是否会影响普通输入搜索的热路径体验

## 必须做

1. 为普通查询增加最近历史记录。
2. 历史记录必须去重并更新时间，而不是无限追加。
3. 支持清空历史，并让 UI 立即反映。
4. 支持保存当前查询为 Saved Filter。
5. 支持删除 Saved Filter。
6. 提供最近查询 / Saved Filters / 快速过滤器入口，但不能干扰正常 typing 搜索。
7. 文档明确所有历史只保存在本地，不上传、不同步、不遥测。
8. 更新 `docs/manual_test.md`，补 J4 手测步骤。
9. 给 `Sources/SwiftSeekSmokeTest/main.swift` 补 query history insert / dedupe / clear、saved filter add / remove / list smoke。
10. 更新 `docs/known_issues.md`，把 J4 已解决和剩余限制写清楚。

## 明确不做

- 不做 J5：上下文菜单动作扩展。
- 不做 J6：首次使用完整向导、Launch at Login、签名 / 公证。
- 不做云同步。
- 不做遥测。
- 不读取系统搜索历史。
- 不把搜索历史和 file usage 混成同一张表。

## 验收标准

1. 普通查询执行后写入最近查询历史。
2. 重复查询去重并更新时间。
3. 可以清空历史，清空后 UI 立即反映。
4. 可以保存当前查询为 Saved Filter。
5. 可以删除 Saved Filter。
6. 入口不会干扰普通 typing 搜索性能。
7. 文档明确隐私边界。
8. `swift build --disable-sandbox` 通过。
9. `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。
10. `docs/manual_test.md` 有明确 J4 GUI 手测步骤。

## 必须补的手测

```text
1. 执行几条普通查询，确认最近查询入口出现并按时间排序。
2. 重复执行同一查询，确认去重且时间刷新。
3. 清空历史，确认 UI 立即为空。
4. 保存当前查询为 Saved Filter，确认可再次选用。
5. 删除 Saved Filter，确认 UI 立即反映。
6. 验证快速过滤器插入不会卡顿，也不会打断正常 typing。
7. 对照文档确认历史只保存在本地，不上传、不同步、不遥测。
```

## 验收后文档

J4 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 J5 任务书；如果 REJECT，按 blocker 修复。
