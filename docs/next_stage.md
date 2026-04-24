# 下一阶段任务书：J3

当前活跃轨道：`everything-ux-parity`
当前阶段：`J3`
阶段名称：查询语法增强：wildcard / quote / OR / NOT

## 交给 Claude 的任务

你现在只做 J3。目标是补齐 Everything 风格常用查询表达能力，让用户可以更精确地表达文件名匹配、短语、二选一和排除。

J3 不做搜索历史，不做上下文菜单，不做首次使用流程，不做完整括号表达式或 regex。

## 必须先审计的代码路径

- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Gram.swift`
- `Sources/SwiftSeekSearch/main.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `Sources/SwiftSeekBench/main.swift`

重点确认：
- `*` wildcard
- `?` wildcard
- quoted phrase，例如 `"foo bar"`
- OR，例如 `foo|bar`
- NOT，例如 `!foo` 或 `-foo`
- 与既有 `ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:` 的组合语义
- GUI 和 CLI 的 query 解析是否一致
- 复杂语法是否会把热路径明显拖慢

## 必须做

1. 在当前 parser / search 流程上补 `*`、`?`、quoted phrase、OR、NOT。
2. 定义清楚优先级和容错策略，避免“部分像布尔、部分像字面量”的半吊子行为。
3. 保持与现有 `ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:` 兼容。
4. GUI 和 CLI 对同一 query 的结果语义必须一致。
5. 非法语法不能崩溃；应容错为字面量或空结果。
6. 更新 `docs/manual_test.md`，补 J3 手测步骤。
7. 给 `Sources/SwiftSeekSmokeTest/main.swift` 补 wildcard / quote / OR / NOT 及其组合 smoke。
8. 如有必要，给 `Sources/SwiftSeekBench/main.swift` 补典型复杂语法 bench，确认不会明显拖慢热路径。
9. 更新 `docs/known_issues.md`，把 J3 已解决和剩余未解决 DSL 边界写清楚。

## 明确不做

- 不做 J4：搜索历史 / Saved Filters。
- 不做 J5：上下文菜单动作扩展。
- 不做 J6：首次使用完整向导、Launch at Login、签名 / 公证。
- 不做完整括号表达式。
- 不做 regex。
- 不做全文搜索或 AI 语义搜索。
- 不改 H2 usage tie-break 和 J2 列宽/可见性语义。

## 验收标准

1. `foo*` / `f?o` 等 wildcard 按预期匹配。
2. `"foo bar"` 作为短语匹配，不被空格拆成两个独立 AND token。
3. `foo|bar` 返回包含 foo 或 bar 的结果。
4. `foo !bar` 或 `foo -bar` 能排除 bar。
5. 与 `ext:` / `path:` / `recent:` / `frequent:` 组合时语义明确。
6. 非法语法不崩溃，能容错为字面量或空结果。
7. GUI 与 CLI 对同一 query 结果一致。
8. `swift build --disable-sandbox` 通过。
9. `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。
10. `docs/manual_test.md` 有明确 J3 GUI/CLI 手测步骤。

## 必须补的手测

```text
1. GUI 输入 `foo*`、`f?o`，确认 wildcard 生效。
2. GUI 输入 `"foo bar"`，确认按短语匹配而不是拆词。
3. GUI 输入 `foo|bar`，确认 OR 生效。
4. GUI 输入 `foo !bar` 或 `foo -bar`，确认排除生效。
5. GUI 输入 `recent: ext:md foo*`，确认与既有 filter 可组合。
6. CLI `SwiftSeekSearch` 对同样 query 返回一致结果。
7. 非法语法样例不崩溃，行为与文档一致。
```

## 验收后文档

J3 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 J4 任务书；如果 REJECT，按 blocker 修复。
