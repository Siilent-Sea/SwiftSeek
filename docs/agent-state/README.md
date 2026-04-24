# `docs/agent-state/`

这个目录存放**当前活跃轨道专用**的验收会话状态文件。

用途：
- 让 Claude 与 Codex 在长期迭代里优先续接同一条验收会话
- 避免回到“默认只靠 `resume --last`”的旧路径
- 避免把正式验收会话和临时分析会话混在一起
- 轨道切换时明确隔离历史 session，避免把已归档轨道的 `PROJECT COMPLETE` 误当成当前轨道结论

## 当前轨道
- 当前活跃轨道：`everything-usage`（已完成）
- 当前阶段：`H5`（已完成）
- 要求：保留当前 `everything-usage` 验收 session 作为归档记录；如未来开启新轨道，必须新建 `.txt` / `.json`
- 禁止：混用已归档 `everything-footprint` session

## 约定文件

### `codex-acceptance-session.txt`
- 只存当前活跃轨道的 Codex 验收 session id
- 便于脚本直接 `cat` 读取并用于 `codex exec resume <session-id>`

### `codex-acceptance-session.json`
- 存结构化状态
- 至少应包含：
  - `track`
  - `stage`
  - `session_id`
  - `updated_at`
  - `purpose`

## 使用规则
- 这是**当前活跃轨道**的专用验收会话状态
- 不与临时分析会话混用
- 不与一次性问答会话混用
- 轨道切换时要同步更新
- `v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint` 的历史 session 均只作为归档背景
- `everything-usage` 必须使用新的验收 session
- 如果当前轨道还没创建正式验收会话，可以暂时只有这个 README；首次创建后再补 `.txt` 和 `.json`
