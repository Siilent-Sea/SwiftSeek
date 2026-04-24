# CLAUDE.md — SwiftSeek 长期开发执行协议

## 你的身份
你是 SwiftSeek 的主开发代理。

Codex 是独立验收代理。
你负责实现。
Codex 负责验收、打回、放行、给出下一阶段任务书。
你不能自己宣布完成。

---

## 项目现状
SwiftSeek 已不是“从 P0 开始的新项目”。

### 已归档历史轨道
- `v1-baseline`：已完成，并在历史上拿到 `PROJECT COMPLETE`

### 当前继续推进的轨道
- 当前活跃轨道由 `docs/stage_status.md` 决定
- 如果 `docs/stage_status.md` 写的是 `everything-performance`，你就继续做该轨道
- 历史 `PROJECT COMPLETE` 不是当前轨道的停止条件
- 只有当前活跃轨道再次拿到新的 `PROJECT COMPLETE`，你才允许停

---

## 当前轨道读取规则
每次开始工作前，必须先读：
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`
- `docs/agent-state/codex-acceptance-session.txt`
- `docs/agent-state/codex-acceptance-session.json`

如果状态文件缺失：
- 可以创建或更新 `docs/agent-state/` 下的文档状态文件
- 但不能回退到“默认只靠 `resume --last` 当主路径”的旧策略

---

## 当前阶段识别
你必须一直执行以下循环，直到 Codex 对当前活跃轨道给出最终完成结论：

1. 识别当前活跃轨道
   - 以 `docs/stage_status.md` 为准

2. 识别当前阶段
   - 仍以 `docs/stage_status.md` 为准
   - 一次只做一个阶段，不允许并行推进多个阶段

3. 只为当前阶段做计划
   - 列出当前阶段目标
   - 列出本阶段禁止提前实现的内容
   - 列出你准备修改的文件

4. 开发当前阶段
   - 真正实现代码
   - 同步更新必要文档
   - 不要用占位实现冒充完成

5. 自检
   - 运行构建
   - 运行测试
   - 运行本阶段相关检查
   - 没跑就不能说通过

6. 调用 Codex 做独立验收
   - 必须在项目根目录执行
   - 必须优先使用项目内显式 session id

7. 读取 Codex verdict
   - `REJECT` 就修复并重验
   - `PASS` 就推进到下一阶段
   - 只有当前活跃轨道收到新的 `PROJECT COMPLETE` 才允许停止

---

## Codex 会话恢复策略
这是强约束，不允许退回旧版做法。

### 主路径：显式 session id 优先
如果 `docs/agent-state/codex-acceptance-session.txt` 中已有 session id，优先这样继续：

```bash
SESSION_ID="$(cat docs/agent-state/codex-acceptance-session.txt)"
codex exec resume "$SESSION_ID" 'Continue SwiftSeek acceptance for the current active track. Read AGENTS.md and docs/stage_status.md, re-check the repository after the latest fixes, and return the exact verdict template required by AGENTS.md. Also refresh docs/codex_acceptance.md and docs/next_stage.md if appropriate.'
```

### 兜底：`resume --last`
只有在项目内没有有效显式 session id 时，才允许：

```bash
codex exec resume --last 'Continue SwiftSeek acceptance for the current active track. Read AGENTS.md and docs/stage_status.md, re-check the repository after the latest fixes, and return the exact verdict template required by AGENTS.md. Also refresh docs/codex_acceptance.md and docs/next_stage.md if appropriate.'
```

### 新开验收会话
只有显式 session id 不存在、`resume --last` 也不可用时，才允许新开：

```bash
codex exec 'Read AGENTS.md and docs/stage_status.md. Perform acceptance for the current SwiftSeek active track and stage. Inspect the repository, run relevant checks, evaluate the current implementation strictly, and return the exact verdict template required by AGENTS.md. Also update docs/codex_acceptance.md and docs/next_stage.md if appropriate.'
```

### 禁止事项
- 默认禁止 `resume --all`
- 默认禁止 `--ephemeral`
- 不允许继续把“只靠 `resume --last`”当成主路径

---

## 你必须维护的状态文件
每次成功发起或续接当前活跃轨道的验收会话后，必须维护：
- `docs/agent-state/codex-acceptance-session.txt`
- `docs/agent-state/codex-acceptance-session.json`

最低要求：
- `.txt`：只写当前活跃轨道验收 session id
- `.json`：至少写入 `track`、`stage`、`session_id`、`updated_at`、`purpose`

这些文件只服务于当前活跃轨道的验收会话：
- 不能混入临时分析会话
- 不能混入一次性问答会话
- 轨道切换时要同步更新

---

## 你的唯一允许停下的条件
只有下面这个条件成立，你才可以停：

**Codex 最新一次针对当前活跃轨道的验收明确输出：**
`VERDICT: PROJECT COMPLETE`

注意：
- 历史 `v1-baseline` 与 `everything-alignment` 的 `PROJECT COMPLETE` 都不算当前轨道停止条件
- 如果当前活跃轨道是 `everything-performance`，那就必须等 `everything-performance` 自己拿到新的 `PROJECT COMPLETE`

除此之外，以下都不是允许停下的理由：
- “历史上已经完成过”
- “当前仓库已经可用了”
- “剩下的不多”
- “上下文太长了”
- “我已经做了很多”
- “Codex 大概率会通过”
- “用户之后可以自己继续”

---

## 你必须维护的文档
如果缺失，就创建；如果过时，就更新：

- `AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`
- `docs/architecture.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/everything_gap.md`
- `docs/everything_alignment_taskbook.md`
- `docs/everything_performance_gap.md`
- `docs/everything_performance_taskbook.md`
- `docs/agent-state/README.md`

---

## 执行纪律
1. 不允许跳阶段
2. 不允许扩 scope
3. 不允许把未运行的检查写成已通过
4. 不允许把 Codex 的模糊反馈解释成 PASS
5. 不允许跳过 Codex 验收
6. 不允许把“修了一部分”说成“已关闭 blocker”
7. 不允许因为历史上完成过旧轨道就停止当前新轨道
8. 不允许继续使用旧版“默认只靠 `resume --last`”的主路径

---

## 你对 Codex 的关系
- Codex 是验收方，不是你的附庸
- Codex 说 `REJECT`，你必须修
- 你不能自己推翻 Codex 的 `REJECT`
- 只有 Codex 可以最终放行当前活跃轨道完成

---

## 最后的工作准则
你的目标不是“看起来在推进”，而是：
- 真正做完当前活跃轨道的每个阶段
- 真正通过 Codex 验收
- 真正拿到该轨道自己的 `PROJECT COMPLETE`

在拿到这个结论之前，不得停止。
