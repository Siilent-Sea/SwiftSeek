# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K2`
- 当前阶段验收结论：K2 round 2 `REJECT`
- 当前正式验收 session：`019dc54e-017d-7de3-a24f-35c23f09ce08`
- 日期：2026-04-25

### 当前审计结论
K2 round 2 基于提交 `5bbb071` 复验，结论仍为 `REJECT`。

本轮确认成立的事实：
- round 1 的直接问题确实修掉了一部分：`scripts/make-icon.swift` 不再用 `NSImage.lockFocus()`，`scripts/package-app.sh` 也新增了 PNG 尺寸预检查。
- 我在当前沙箱里实际跑通了：
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
  - 结果 `201/201` 通过。
- 同一套沙箱变量下，`HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 能完成 release build、生成 10 个 PNG、通过尺寸检查，然后才进入 `iconutil`。

本轮 blocker 也已确认：
- 即便 10 个 PNG 的尺寸现在全部正确，`scripts/package-app.sh --sandbox` 仍然在 `iconutil -c icns` 处失败，错误还是 `Invalid Iconset`。
- 因为 `iconutil` 失败，脚本仍然没有生成 `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns`，也没有进入 `Info.plist` 校验、`codesign` 校验和完整 bundle 自检的通过态。
- 当前 `dist/SwiftSeek.app` 只有：
  - `Contents/MacOS/SwiftSeek`
  - 空的 `Contents/Resources`
  这不满足 K2 的 `.app` 完整产物标准。
- 我复查了 round 2 生成的 iconset：
  - 10 个 `icon_*.png` 都存在
  - `sips -g pixelWidth -g pixelHeight` 显示尺寸与文件名声明一致
  - 但 `iconutil` 仍拒绝该 iconset
- 结论是：round 2 修掉了“像素尺寸不匹配”这个子问题，但 K2 主链路依然没有通过，说明 iconset 还有别的合法性问题未解决。

## 当前验收要求
K2 完成后，Codex 才能给出下一轮 `PASS` 或 `REJECT`。当前不允许因为 K1 已通过就把后续产品化阶段视为自动完成。

验收时必须检查：
- `.app` package 脚本能从 fresh clone 稳定生成 bundle。
- `Info.plist` / `AppIcon.icns` / ad-hoc codesign 进入可重复流程，而不是依赖手工注入。
- `dist/SwiftSeek.app` 或等价输出路径明确。
- `open` 启动、`codesign -dv`、`plutil`、bundle 结构检查都可验证。
- K1 的 build identity 和 settings release gate 不回退。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
