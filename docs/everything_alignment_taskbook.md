# SwiftSeek Everything-alignment 任务书

> Archived note:
> 这份任务书属于已归档的 `everything-alignment` 轨道。
> 当前活跃轨道已切换为 `everything-performance`。
> 后续开发应优先查看 [docs/everything_performance_taskbook.md](docs/everything_performance_taskbook.md)。

目标：在不推翻 `v1-baseline` 的前提下，把 SwiftSeek 沿着更接近 Everything 的主路线继续推进。

约束：
- 只做本地、原生 macOS 文件搜索器
- 不做全文搜索
- 不做 AI 语义搜索
- 不做云盘一致性承诺
- 阶段控制在 5 个，不再继续碎分

---

## E1：搜索相关性与结果上限

### 阶段目标
- 让 plain query 具备多词 AND 语义
- 把当前粗粒度排序提升到更接近文件搜索器使用习惯
- 去掉 GUI 固定 20 条上限，并把结果上限做成设置项

### 明确做什么
- plain query 分词、terms AND
- basename / token boundary / path segment / extension bonus
- 结果上限默认值提高
- 结果上限持久化配置

### 明确不做什么
- 不做 query DSL
- 不做大 UI 改版
- 不做多列视图

### 涉及的关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`

### 验收标准
1. 多词 query 为 AND 语义
2. 新 bonus 真实影响排序
3. GUI 不再固定显示 20 条
4. 结果上限可配置且持久化
5. `swift build` 与 `swift run SwiftSeekSmokeTest` 全绿

### 需要补的测试
- 多词 AND
- basename / token boundary / path segment / extension ranking
- 结果上限配置读写与搜索窗口实际生效

---

## E2：结果视图与排序 / 显示密度

### 阶段目标
- 让结果展示更像文件搜索器，而不是单列 launcher 列表
- 提升扫读效率

### 明确做什么
- 多列或等价高密度视图
- 更明确地展示 name / path / mtime / size
- 至少支持排序方式切换，或等价的排序入口

### 明确不做什么
- 不做 query DSL
- 不做全文搜索
- 不引入复杂预览面板重构

### 涉及的关键文件
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `docs/manual_test.md`

### 验收标准
1. 结果密度明显高于当前单列 cell 模式
2. 用户能清楚看到 name / path / mtime / size
3. 至少有一种可切换排序方式
4. 现有打开 / Reveal / Copy Path 行为不回退

### 需要补的测试
- 结果排序切换的状态测试
- GUI 手测项补充：结果展示、排序切换、键盘与鼠标行为不回退

---

## E3：查询语法与过滤能力

### 阶段目标
- 在不碰全文搜索的前提下，为文件搜索加入实用过滤语法

### 明确做什么
- 支持：
  - `ext:`
  - `kind:`
  - `path:`
  - `root:`
  - `hidden:`
- plain query 与过滤条件可组合

### 明确不做什么
- 不做全文搜索
- 不做 AI 语义搜索
- 不做过度复杂的 DSL

### 涉及的关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekSearch/main.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`

### 验收标准
1. 过滤语法有明确、稳定的解析规则
2. 过滤语法与 plain query 可组合
3. CLI 与 GUI 至少在核心语义上保持一致
4. 文档明确说明支持的语法与不支持的语法

### 需要补的测试
- parser 覆盖
- 不同 filter 组合的搜索结果覆盖
- 非法 / 冲突语法的容错覆盖

---

## E4：索引自动化体验与 root 健康状态

### 阶段目标
- 让 root 与索引状态更自解释
- 减少“我改了设置但系统到底有没有生效”的不确定感

### 明确做什么
- add root 后自动后台索引
- hidden / exclude 改动的生效路径明确可感知
- root 可用性 / 外接盘状态提示
- 让用户知道 root 当前是 ready、indexing、offline、unavailable 还是 paused

### 明确不做什么
- 不做云盘一致性承诺
- 不做复杂后台服务化

### 涉及的关键文件
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `docs/known_issues.md`

### 验收标准
1. 新增 root 后无需再弹“要不要现在重建”的旧式流程
2. root 状态对用户可见
3. hidden / exclude 改动后，用户能明确知道立即生效的部分与需重建的部分
4. 外接盘 / 不可访问 root 至少有状态提示，不再只是静默留旧数据

### 需要补的测试
- root 状态流转测试
- 自动索引触发测试
- 手测项补充：root 添加、拔盘、恢复挂载、exclude / hidden 生效反馈

---

## E5：热键自定义、使用习惯优化、收尾文档

### 阶段目标
- 收掉高频使用层面的最后一批短板

### 明确做什么
- 热键配置
- 如实现成本可控，可加入轻量 usage-based tie-break
- 补齐文档与手测

### 明确不做什么
- 不引入新的搜索后端
- 不做大规模 UX 重写

### 涉及的关键文件
- `Sources/SwiftSeek/App/GlobalHotkey.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. 热键可配置且持久化
2. 热键冲突与无效输入有明确反馈
3. 如果引入 usage-based tie-break，必须可解释且不破坏基础相关性
4. 文档与手测对齐最终行为

### 需要补的测试
- 热键配置读写
- 热键变更后重新注册行为
- 如果有 usage tie-break，补稳定性测试
