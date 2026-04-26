# `docs/agent-state/`

这个目录存放**当前活跃轨道专用**的验收会话状态文件。

用途：
- 让 Claude 与 Codex 在长期迭代里优先续接同一条验收会话
- 避免回到“默认只靠 `resume --last`”的旧路径
- 避免把正式验收会话和临时分析会话混在一起
- 轨道切换时明确隔离历史 session，避免把已归档轨道的 `PROJECT COMPLETE` 误当成当前轨道结论

## 当前轨道

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M3`
- 当前验收 session：`019dc959-3bf6-7671-ace6-cf3a3598e592`
- 要求：`everything-filemanager-integration` 必须继续使用该 Codex 验收 session。
- 禁止：不得复用已归档 `everything-menubar-agent` session `019dc5fc-318e-7d31-bb00-2810eaf6642c`，也不得复用更早轨道 session。

## 约定文件

### `codex-acceptance-session.txt`

- 正常情况下只存当前活跃轨道的 Codex 验收 session id
- 当前文件内应为真实 session id：`019dc959-3bf6-7671-ace6-cf3a3598e592`
- Claude 应优先用该 session 继续当前 M 轨道验收，不得回到归档轨道 session

### `codex-acceptance-session.json`

- 存结构化状态
- 至少应包含：
  - `track`
  - `stage`
  - `session_id`
  - `updated_at`
  - `purpose`
- 当前 `session_id` 为 `019dc959-3bf6-7671-ace6-cf3a3598e592`

## 使用规则

- 这是**当前活跃轨道**的专用验收会话状态
- 不与临时分析会话混用
- 不与一次性问答会话混用
- 轨道切换时要同步更新
- `v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization`、`everything-menubar-agent` 的历史 session 均只作为归档背景
- 如果 `.txt` 中不是有效 session id，Claude 必须新开或恢复正确的新轨道验收会话，并在成功后写回真实 session id
