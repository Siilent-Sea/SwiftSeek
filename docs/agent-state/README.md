# `docs/agent-state/`

这个目录存放**当前活跃轨道专用**的验收会话状态文件。

用途：
- 让 Claude 与 Codex 在长期迭代里优先续接同一条验收会话
- 避免回到“默认只靠 `resume --last`”的旧路径
- 避免把正式验收会话和临时分析会话混在一起
- 轨道切换时明确隔离历史 session，避免把已归档轨道的 `PROJECT COMPLETE` 误当成当前轨道结论

## 当前轨道

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M1`
- 当前验收 session：待创建
- 要求：`everything-filemanager-integration` 必须使用新的 Codex 验收 session。
- 禁止：不得复用已归档 `everything-menubar-agent` session `019dc5fc-318e-7d31-bb00-2810eaf6642c`，也不得复用更早轨道 session。

## 约定文件

### `codex-acceptance-session.txt`

- 正常情况下只存当前活跃轨道的 Codex 验收 session id
- 当前 M1 尚未创建正式验收 session，因此文件内为占位标记 `PENDING_NEW_CODEX_ACCEPTANCE_SESSION`
- Claude 不得把该占位标记传给 `codex exec resume`
- 一旦新 session 创建成功，必须用真实 session id 覆盖该文件

### `codex-acceptance-session.json`

- 存结构化状态
- 至少应包含：
  - `track`
  - `stage`
  - `session_id`
  - `updated_at`
  - `purpose`
- 当前 `session_id` 为 `null`，表示新轨道尚未创建正式验收会话

## 使用规则

- 这是**当前活跃轨道**的专用验收会话状态
- 不与临时分析会话混用
- 不与一次性问答会话混用
- 轨道切换时要同步更新
- `v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization`、`everything-menubar-agent` 的历史 session 均只作为归档背景
- 如果 `.txt` 中不是有效 session id，Claude 必须新开或恢复正确的新轨道验收会话，并在成功后写回真实 session id
