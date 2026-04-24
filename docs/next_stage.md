# 下一阶段任务书

## Track
`everything-alignment`

## Stage
`E1`

## 目标
把 SwiftSeek 从“v1 baseline 可用搜索”推进到“Everything-alignment 的第一阶段”：
- plain query 多词 AND 语义
- 更细的相关性排序
- 结果上限设置化，默认值提高

## 本阶段必须做
1. 在 `Sources/SwiftSeekCore/SearchEngine.swift` 中重构查询处理：
   - plain query 按 term 拆分
   - term 之间为 AND
   - 不引入 query DSL
2. 在现有排序基础上补齐 bonus：
   - basename
   - token boundary
   - path segment
   - extension
3. 在 GUI 中去掉固定 20 条上限：
   - `Sources/SwiftSeek/UI/SearchViewController.swift` 不再写死 `let limit = 20`
   - 默认值提高
   - 上限值可配置
4. 在 `Sources/SwiftSeek/UI/SettingsWindowController.swift` 与相关设置持久化位置中补一个最小可用配置入口
5. 更新本阶段相关文档

## 本阶段不要做
- 不做结果列表大改版
- 不做多列高密度视图
- 不做 query DSL
- 不做全文搜索
- 不做 AI 语义搜索
- 不做热键自定义

## 涉及关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/known_issues.md`

## 验收标准
1. 多词 query 具备 AND 语义
2. basename / token boundary / path segment / extension bonus 真实生效
3. GUI 默认结果上限高于 20
4. GUI 结果上限可配置且重启后仍生效
5. `swift build` 成功
6. `swift run SwiftSeekSmokeTest` 成功
7. 新增 smoke 覆盖：
   - 多词 AND
   - 细粒度排序
   - 结果上限配置生效

## 验证方法
```bash
swift build
swift run SwiftSeekSmokeTest
swift run SwiftSeekSearch "alpha report"
```

必要时补手工验证：
- 启动 `swift run SwiftSeek`
- 修改结果上限设置
- 搜索高命中 query，确认不再固定只显示 20 条
