# `docs/agent-state/`

这个目录存放**当前活跃轨道专用**的验收会话状态文件。

用途：
- 让 Claude 与 Codex 在长期迭代里优先续接同一条验收会话
- 避免回到“默认只靠 `resume --last`”的旧路径
- 避免把正式验收会话和临时分析会话混在一起
- 轨道切换时明确隔离历史 session，避免把已归档轨道的 `PROJECT COMPLETE` 误当成当前轨道结论

## 当前轨道

- 当前活跃轨道：`everything-menubar-agent`
- 当前阶段：`L4`
- 当前验收 session：`019dc5fc-318e-7d31-bb00-2810eaf6642c`
- 要求：`everything-menubar-agent` 必须继续使用这个新的 Codex 验收 session。
- 禁止：不得复用已归档 `everything-productization` session `019dc54e-017d-7de3-a24f-35c23f09ce08`，也不得复用更早轨道 session。

## 约定文件

### `codex-acceptance-session.txt`

- 正常情况下只存当前活跃轨道的 Codex 验收 session id
- 当前文件应为 `019dc5fc-318e-7d31-bb00-2810eaf6642c`
- Claude / Codex 后续 L4 最终验收应优先恢复这个 session，而不是使用 `resume --last`

### `codex-acceptance-session.json`

- 存结构化状态
- 至少应包含：
  - `track`
  - `stage`
  - `session_id`
  - `updated_at`
  - `purpose`
- 当前 `session_id` 为 `019dc5fc-318e-7d31-bb00-2810eaf6642c`，表示 L-track 正式验收会话已创建

## 使用规则

- 这是**当前活跃轨道**的专用验收会话状态
- 不与临时分析会话混用
- 不与一次性问答会话混用
- 轨道切换时要同步更新
- `v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization` 的历史 session 均只作为归档背景
- 如果 `.txt` 中不是有效 session id，Claude 必须新开或恢复正确的新轨道验收会话，并在成功后写回真实 session id
