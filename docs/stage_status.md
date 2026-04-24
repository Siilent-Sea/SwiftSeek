# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：`everything-alignment`
- 当前阶段：`E4`（索引自动化 + root 状态；功能落地，等待 Codex 验收）
- 已归档轨道：`v1-baseline`
- 轨道内已通过阶段：E1、E2、E3（均 2026-04-24）

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6

## 当前活跃轨道：`everything-alignment`

### 已通过
- **E1**（搜索相关性与结果上限，round 2 PASS）
- **E2**（结果视图与排序切换，round 2 PASS）
- **E3**（查询语法与过滤，round 1 PASS —— 预刷新文档策略奏效）

### 当前阶段：`E4`
索引自动化体验与 root 健康状态。

### 当前阶段目标（均已落地，待 Codex 验收）
- ✅ 新增 root 后去掉 "是否立即索引" 弹窗，改为自动后台 `indexOneRoot`
- ✅ hidden 开关切换后明确弹"已保存 + 立即重建/稍后"选择，不再静默
- ✅ roots 列显示状态：`就绪 / 索引中 / 停用 / 未挂载 / 不可访问`
- ✅ IndexingPane 订阅 `RebuildCoordinator.onStateChange` 实时刷新；链接到 AppDelegate 已有 observer，不覆盖菜单栏逻辑
- ✅ `Database.computeRootHealth(for:currentlyIndexingPath:)` pure-ish helper，测试覆盖 5 个状态
- ✅ `RebuildCoordinator.currentlyIndexingPath` 公开当前正在索引的路径
- ✅ exclude 新增时已立即清理（v1 已有），现在文案明确"无需重建"

### 当前阶段禁止事项
- 不做云盘 / 网络盘实时一致性承诺
- 不做复杂后台服务化
- 不做热键配置（留 E5）
- 不引入新的搜索后端

### 当前代码状态（E4 快照）
- `Sources/SwiftSeekCore/SettingsTypes.swift`
  - 新 `RootHealth` enum（ready / indexing / paused / offline / unavailable）+ `.uiLabel`
  - `Database.computeRootHealth(for:currentlyIndexingPath:)` extension
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
  - 新 `indexOneRoot(path:onProgress:onFinish:)` 单 root 后台索引 API
  - 新 `currentlyIndexingPath` public 只读属性，worker queue 更新 `_currentPath`
  - rebuild() 循环也维护 `_currentPath`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - IndexingPane `viewWillAppear` chained observer 保证 menu-bar & pane 都刷新；`viewWillDisappear` 恢复
  - onAddRoot / drag-add 两条路径都走新的 `autoIndexAfterAdd`，移除确认弹窗
  - roots table viewFor 用 `RootHealth.uiLabel + path` 代替旧的 ✅/⏸
  - rootsStatus 文案改为提及 5 档状态
  - GeneralPane onToggle 切换 hidden 后弹"立即重建/稍后"选择
- `Sources/SwiftSeekSmokeTest/main.swift`
  - +7 条 E4 用例（paused / ready / offline / indexing pinning / uiLabel / indexOneRoot 驱动 onStateChange / currentlyIndexingPath idle nil）
  - smoke 总数 51 + 10 (E1) + 7 (E2) + 17 (E3) + 7 (E4) = 92，全绿

### 当前阶段完成判定标准
1. ✅ 新增 root 无需再弹 "要不要现在重建"
2. ✅ root 状态对用户可见
3. ✅ hidden 改动后有明确反馈路径（立即 / 稍后）
4. ✅ 外接盘 / 不可访问 root 有状态标示（`offline` / `unavailable`）
5. ✅ `swift build` + smoke 全绿

### 当前最新 Codex 结论
- 轨道内最新 PASS：`E3 / round 1 / 2026-04-24`
- 当前阶段（E4）：等待 round 1 验收

### 当前活跃轨道验收会话状态
- 当前 session id：`019dbd4c-e0c9-7370-8a0c-1d4263a9f19b`
- 恢复策略：`codex exec resume <session_id>`
