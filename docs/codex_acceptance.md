# Codex 验收记录

本文件只保留当前有效结论。

VERDICT: REJECT
TRACK: everything-alignment
STAGE: E1
SUMMARY:
- SwiftSeek 的 `v1-baseline` 已经是可构建、可运行、可冒烟验证的完成态；`swift build` 与 `swift run SwiftSeekSmokeTest` 都通过，说明这不是空仓库，也不是回退态。
- 但当前活跃轨道 `everything-alignment` 的 E1 目标还没有真正开始落地。`SearchEngine` 仍是 baseline 时代的粗粒度匹配；`SearchViewController` 仍把 GUI 结果上限写死为 20；设置页里也没有结果上限配置入口。
- 因此，历史上的 `PROJECT COMPLETE` 只能归档到 `v1-baseline`，不能作为 `everything-alignment` 的放行依据。当前轨道仍应继续开发。

BLOCKERS:
1. `Sources/SwiftSeekCore/SearchEngine.swift` 仍按完整字符串做匹配，plain query 没有多词 AND 语义；`alpha report` 这类查询仍依赖连续子串或 gram 命中，不是 Everything-like 的多词收窄行为。
2. `SearchEngine.score()` 只有 exact / prefix / contains / path-only 四档，没有 basename / token boundary / path segment / extension bonus，E1 定义的相关性升级尚未落地。
3. `Sources/SwiftSeek/UI/SearchViewController.swift` 里 `runQuery` 仍固定 `let limit = 20`，状态栏也写死“仅显示前 20 条”；`SettingsWindowController` 中没有结果上限配置项，E1 的“结果上限设置化”尚未开始。

REQUIRED_FIXES:
1. 按 `docs/next_stage.md` 完成 E1：多词 AND、细粒度加分规则、结果上限设置化。
2. 为 E1 新行为补充 `SwiftSeekSmokeTest` 覆盖，至少覆盖多词 AND、同分排序、结果上限配置生效。
3. 完成后重新运行 `swift build` 与 `swift run SwiftSeekSmokeTest`，再进入下一轮 Codex 验收。

NON_BLOCKING_NOTES:
1. 现有 baseline 代码已经暴露出 Everything-alignment 的主要入口点：`SearchEngine.swift`、`SearchViewController.swift`、`SettingsWindowController.swift`。后续工作不需要大面积重构仓库结构。
2. 本轮 `swift run SwiftSeekSmokeTest` 仍有一个 Swift 6 兼容性 warning：`RebuildCoordinator.Progress` 持有的 `IndexProgress` 尚未声明 `Sendable`。它不阻塞本轮文档整理，但后续最好顺手收掉。

EVIDENCE:
- 实际检查文件：
  - `AGENTS.md`
  - `CLAUDE.md`
  - `README.md`
  - `docs/stage_status.md`
  - `docs/codex_acceptance.md`
  - `docs/known_issues.md`
  - `docs/architecture.md`
  - `docs/next_stage.md`
  - `Sources/SwiftSeekCore/SearchEngine.swift`
  - `Sources/SwiftSeek/UI/SearchViewController.swift`
  - `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - `Sources/SwiftSeekCore/Database.swift`
  - `Sources/SwiftSeek/App/GlobalHotkey.swift`
  - `Sources/SwiftSeekCore/RebuildCoordinator.swift`
- 实际运行命令：
  - `swift build`
  - `swift run SwiftSeekSmokeTest`
- 实际观察结果：
  - `swift build` 成功，输出 `Build complete!`
  - `swift run SwiftSeekSmokeTest` 成功，输出 `Smoke total: 51  pass: 51  fail: 0`
  - smoke 过程中出现一个 warning：`RebuildCoordinator.Progress` 的 `indexProgress` 持有非 `Sendable` 类型 `IndexProgress`
  - `SearchViewController.swift` 明确存在 `let limit = 20`
  - `SearchEngine.swift` 明确仍只有四档打分与单串匹配逻辑

NEXT_STAGE_TASKBOOK:
- 见 `docs/next_stage.md`
