# 下一阶段任务书

当前活跃轨道：`everything-dockless-hardening`

当前阶段：`N1`
阶段名：Dock 常驻根因审计与诊断暴露

## 交给 Claude 的 N1 任务

本阶段只做 Dock 根因审计、日志和 Diagnostics 暴露，不提前改 package 默认策略，不把 `LSUIElement` 改成 `true`，不强制改用户 DB。

### 必须完成

- 审计并记录当前 Dock 相关路径：`NSApp.setActivationPolicy`、`dock_icon_visible`、`LSUIElement`、package `Info.plist`、Settings UI、About / Diagnostics。
- About / Diagnostics 增加 Dock 状态块：persisted `dock_icon_visible`、intended mode、effective activation policy、Info.plist `LSUIElement`、bundle path、executable path。
- 启动日志打印 Dock mode 判断：persisted setting、chosen activation policy、Info.plist `LSUIElement`、bundle path、executable path。
- 如果 `dock_icon_visible=1`，日志必须明确说明 Dock 出现是用户设置导致。
- smoke 覆盖 fresh DB default false、true/false round-trip、Diagnostics 包含 Dock mode 关键字段。

### 验收方式

- `swift build --disable-sandbox`
- `swift run --disable-sandbox SwiftSeekSmokeTest`
- 复制 About / Diagnostics，确认能区分 fresh DB、`dock_icon_visible=0`、`dock_icon_visible=1`。
- 本阶段不要求真实 `.app` 默认策略改变；那是 N2。
