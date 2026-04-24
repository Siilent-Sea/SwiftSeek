# 下一阶段任务书

## Track
`everything-alignment`

## Stage
`E2` — 结果视图与排序 / 显示密度

> 本文件在 E1 round 2 刷新（2026-04-24）切换为 E2 任务书。E1 功能面已全部落地（多词 AND、4 个 bonus、结果上限设置化），Codex round 1 因文档未同步给出 REJECT；round 2 刷新四项文档后应拿到 E1 PASS，随后正式进入本阶段。

## 目标
让 SwiftSeek 结果展示从“单列 launcher 列表”进化到“文件搜索器高密度视图”：一屏能扫读更多结果、name / path / mtime / size 显示更清晰、支持排序切换。

## 本阶段必须做
1. 结果视图升级到多列或等价高密度形式：
   - 至少清楚展示 name / path / mtime / size
   - 不再像 launcher 那样把所有信息挤成单行 cell
2. 排序入口：
   - 允许用户切换排序维度（至少包含 name / mtime / size）
   - 默认仍为 score 优先
   - 切换到其它维度时稳定可重现，能切回默认
3. 兼容 E1 与 v1-baseline 已有行为：
   - ↑↓ ⏎ ⌘⏎ ⌘⇧C ⌘Y ESC 键盘流不回退
   - 右键菜单、拖拽、QuickLook、substring 高亮继续可用
   - 空态提示、仅显示前 N 条、toast 等 E1 / UX polish 结果维持
4. 更新本阶段相关文档

## 本阶段明确不做
- 不做 query DSL（留给 E3）
- 不做 root 状态 / 自动索引（留给 E4）
- 不做热键配置（留给 E5）
- 不做全文搜索 / OCR / AI 语义
- 不做预览面板重构

## 涉及关键文件
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`（如排序逻辑需下沉到核心）
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/known_issues.md`
- `docs/manual_test.md`

## 验收标准
1. 结果密度明显高于单列 cell 模式
2. 用户能清楚看到 name / path / mtime / size
3. 至少一种可切换排序方式
4. 打开 / Reveal / Copy Path / QuickLook / 拖拽 / 右键菜单 / substring 高亮不回退
5. `swift build` 与 `swift run SwiftSeekSmokeTest` 全绿
6. 新增 smoke 覆盖：
   - 排序切换的稳定性
   - 切回默认后的顺序与原始 score 排序一致

## 验证方法
```bash
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
    swift build --disable-sandbox
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
    swift run --disable-sandbox SwiftSeekSmokeTest
```

手测补充：
- 启动 GUI，按 ⌥Space 呼出搜索窗，执行一个较大命中 query（例如 `txt`）
- 验证结果行展示 name / path / mtime / size 四个字段清晰可辨
- 切换排序维度（name / mtime / size），确认排序正确且切回默认后回到 score 顺序
- 验证键盘流 / 右键菜单 / QuickLook / 拖拽 / 复制路径 toast / 高亮仍然工作
