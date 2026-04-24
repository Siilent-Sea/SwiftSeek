# SwiftSeek Everything-performance 任务书

目标：在不推翻既有功能的前提下，把 SwiftSeek 继续推进到“更快、更真实、更可验收”的 Everything-like 状态。

约束：
- 只做本地、原生 macOS 文件搜索器
- 不做全文搜索
- 不做 AI 语义搜索
- 不做云盘一致性承诺
- 阶段固定为 `F1` ~ `F5`

---

## F1：搜索热路径性能

### 阶段目标
- 先解决“建了索引但搜索仍慢”的核心问题

### 明确做什么
- 避免 2+ 字符查询继续走 `%LIKE%` 全表扫描主路径
- 为 2 字符 / 3+ 字符查询建立更适合倒排索引或等价可扩展结构的主路径
- 减少搜索热路径重复开销：
  - prepared statement 复用或等价优化
  - roots / settings 热路径缓存或等价优化
- 增加 benchmark / perf probe
- 固化 warm search timing 目标

### 明确不做什么
- 不做大 UI 改版
- 不做大规模相关性重写
- 不做 DSL 扩张

### 涉及的关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSearch/main.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/stage_status.md`
- `docs/next_stage.md`

### 验收标准
1. 2 字符查询不再以 `%LIKE%` 扫描作为主路径
2. 3+ 字符查询保持索引驱动且不回退
3. 同类 SQL 不再每次搜索都重新 prepare，或有等价可验证优化
4. roots / settings 热路径读取开销下降，或有缓存 / 等价机制
5. 仓库中有 benchmark / perf probe
6. 文档中固化明确目标，例如：
   - warm CLI search median：2 字符 <= 50ms
   - warm CLI search median：3+ 字符 <= 30ms
   - p95 不明显失控
7. `swift build` 与 `swift run SwiftSeekSmokeTest` 全绿

### 需要补的测试 / benchmark / 手测
- 短查询热路径 probe
- 3+ 字符查询热路径 probe
- prepared statement / cache 行为验证
- 手测：高频输入时状态栏 `ms` 明显收敛

---

## F2：真实相关性与 limit 接线

### 阶段目标
- 把“排序更像 Everything”与“limit 真正一致”重新做实

### 明确做什么
- 重新审视 plain query 多词 AND 的真实效果
- 继续校准 basename / token boundary / path segment / extension bonus
- 统一 GUI / CLI / settings 的结果上限语义
- 把文档和当前代码重新对齐

### 明确不做什么
- 不做大性能架构重写
- 不做结果视图重设计
- 不做复杂 DSL

### 涉及的关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSearch/main.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `docs/known_issues.md`

### 验收标准
1. 多词 AND 与 ranking 行为有明确、可重复验证结果
2. GUI 与 CLI 的结果上限行为不再互相漂移
3. 文档对相关性和 limit 的描述与代码一致
4. `swift build` 与 smoke 全绿

### 需要补的测试 / benchmark / 手测
- ranking regression 覆盖
- GUI / CLI limit 语义覆盖
- 手测：同 query 在 GUI / CLI 上的结果规模与排序基本一致

---

## F3：高密度结果视图与排序入口

### 阶段目标
- 把结果列表从“已多列”推进到“更像文件搜索器”

### 明确做什么
- 提升结果密度
- 强化 name / path / mtime / size 的扫读效率
- 增强排序方式切换体验
- 收口列布局与状态保留

### 明确不做什么
- 不做 DSL 扩张
- 不做新搜索后端

### 涉及的关键文件
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `docs/manual_test.md`

### 验收标准
1. 结果视图更高密度
2. 主要字段一眼可扫
3. relevance / path / name / mtime / size 等排序入口可用
4. 现有键盘流、QuickLook、右键、拖拽不回退

### 需要补的测试 / benchmark / 手测
- 排序切换状态测试
- 手测：结果展示、排序切换、交互不回退

---

## F4：查询 DSL 与 root 健康状态真正落地

### 阶段目标
- 让过滤能力和 root 状态真的可用、可见、可解释

### 明确做什么
- 继续把 `ext:` / `kind:` / `path:` / `root:` / `hidden:` 做实
- 清理 filter-only 查询的低效路径
- 把 `RootHealth` 从“设置页有状态 badge”推进到更完整的产品心智
- 让搜索行为与 root 状态关系更清楚

### 明确不做什么
- 不做全文搜索
- 不做云盘一致性承诺
- 不做复杂布尔查询语言

### 涉及的关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `docs/known_issues.md`

### 验收标准
1. DSL 核心字段可用且高频场景效率可接受
2. `RootHealth` 不再只停留在类型和单个列表 badge
3. root 状态与搜索结果之间的关系对用户更可解释
4. 文档能准确描述当前支持和不支持的 DSL 能力

### 需要补的测试 / benchmark / 手测
- DSL 组合查询覆盖
- root 健康状态流转覆盖
- 手测：offline / unavailable / paused 行为

---

## F5：索引自动化与最终收尾

### 阶段目标
- 把设置改动、root 添加、后台索引、使用习惯和最终文档一起收口

### 明确做什么
- 继续打磨 add root 自动后台索引
- 明确 hidden / exclude 变化后的可感知生效链路
- 如成本可控，引入轻量 usage-based tie-break
- 收口文档 / 手测 / known issues

### 明确不做什么
- 不引入新的大搜索后端
- 不做大规模 UI 重写

### 涉及的关键文件
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/codex_acceptance.md`

### 验收标准
1. 设置改动后的系统行为更自解释
2. root 添加、后台索引、状态反馈链路顺畅
3. 如果引入 usage tie-break，不破坏基础相关性
4. 文档、手测、已知限制与最终代码对齐
5. 具备进入当前轨道最终验收的条件

### 需要补的测试 / benchmark / 手测
- 自动索引链路覆盖
- hidden / exclude 生效链路覆盖
- usage tie-break 稳定性测试（如果实现）
- 最终回归手测
