# `docs/agent-state/`

这个目录存放**当前活跃轨道专用**的 Codex 验收会话状态文件。

用途：
- 让 Claude 与 Codex 在长期迭代里优先续接同一条正式验收会话
- 避免回到默认只靠 `resume --last` 的旧路径
- 避免把正式验收会话和临时分析会话混在一起
- 轨道切换时隔离历史 session，避免把已归档轨道的 `PROJECT COMPLETE` 误当成当前轨道结论

## 当前轨道

- 当前活跃轨道：`everything-dockless-hardening`
- 当前阶段：`N2`
- 当前验收 session：`be0f0316-31b1-479f-be88-6069e185762c`
- 当前状态：N1 已通过 Codex 验收，N2 待执行。
- 要求：不得复用已归档 `everything-filemanager-integration` session `019dc959-3bf6-7671-ace6-cf3a3598e592`。

## 约定文件

### `codex-acceptance-session.txt`

- 正常情况下只存当前活跃轨道的 Codex 验收 session id。
- 新轨道刚切换且尚未创建正式验收 session 时，允许临时写入 `PENDING_NEW_CODEX_ACCEPTANCE_SESSION`。
- `PENDING_NEW_CODEX_ACCEPTANCE_SESSION` 不是可 resume 的真实 id；Claude / Codex 必须创建或记录新的正式 session 后再替换。

### `codex-acceptance-session.json`

- 存结构化状态。
- 至少应包含：
  - `track`
  - `stage`
  - `session_id`
  - `updated_at`
  - `purpose`
- 当前 `session_id` 必须指向 `everything-dockless-hardening` 的正式验收 session。

## 使用规则

- 这是**当前活跃轨道**的专用验收会话状态。
- 不与临时分析会话混用。
- 不与一次性问答会话混用。
- 轨道切换时必须同步更新。
- 历史轨道 session 只作为归档背景，不能作为当前轨道放行依据。
- 如果 `.txt` 中不是有效 session id，Claude 必须新开或恢复正确的新轨道验收会话，并在成功后写回真实 session id。
